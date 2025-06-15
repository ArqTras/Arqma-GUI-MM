<template>
  <q-page class="send">
    <template v-if="view_only">
      <div class="column q-pa-md">
        {{ $t('pages.wallet.send.view_only_mode') }}
      </div>
    </template>
    <template v-else>
      <div class="column q-pa-md">
        <!-- amount in xeq-->
        <div class="row gutter-md">
          <div class="col-6 amount">
            <arqmaField
              :label="$t('pages.wallet.send.amount')"
              :error="v$.amount.$error"
            >
              <q-input
                v-model="newTx.amount"
                :dark="theme == 'dark'"
                type="number"
                placeholder="0"
                borderless
                dense
                @update:model-value="handleAmountInput"
                @blur="v$.amount.$validate()"
              />
              <!-- @change="conversionFromXtri()" -->
              <q-btn
                color="positive"
                :text-color="theme == 'dark' ? 'white' : 'dark'"
                @click="all()"
              >
                {{ $t('pages.wallet.send.all') }}
              </q-btn>
            </arqmaField>
          </div>
          <div class="col-6">
            <arqmaField
              :label="$t('pages.wallet.send.address')"
              :error="v$.address.$error"
            >
              <q-input
                v-model="newTx.address"
                :placeholder="address_placeholder"
                :dark="theme == 'dark'"
                borderless
                dense
                @blur="v$.address.$validate()"
              />
              <q-btn
                color="positive"
                :text-color="theme == 'dark' ? 'white' : 'dark'"
                to="addressbook"
              >
                {{ $t('pages.wallet.send.contacts') }}
              </q-btn>
            </arqmaField>
          </div>
        </div>

        <!-- Notes -->
        <div class="col q-mt-sm">
          <arqmaField
            :label="$t('pages.wallet.send.notes')"
            optional
          >
            <q-input
              v-model="newTx.note"
              class="full-width text-area-arqma"
              type="textarea"
              :dark="theme == 'dark'"
              :placeholder="$t('pages.wallet.send.notes_placeholder')"
              borderless
              dense
            />
          </arqmaField>
        </div>

        <div
          v-if="newTx.address_book.save"
          class="col"
        >
          <arqmaField
            :label="$t('pages.wallet.send.name')"
            optional
          >
            <q-input
              v-model="newTx.address_book.name"
              :dark="theme == 'dark'"
              :placeholder="$t('pages.wallet.send.name_placeholder')"
              borderless
              dense
            />
          </arqmaField>
          <arqmaField
            class="q-mt-sm"
            :label="$t('pages.wallet.send.notes')"
            optional
          >
            <q-input
              v-model="newTx.address_book.description"
              type="textarea"
              class="full-width text-area-arqma"
              rows="2"
              :dark="theme == 'dark'"
              :placeholder="$t('pages.wallet.send.additional_notes_placeholder')"
              borderless
              dense
            />
          </arqmaField>
        </div>

        <div class="row justify-end items-center">
          <q-checkbox
            v-model="newTx.address_book.save"
            :label="$t('pages.wallet.send.save_to_addressbook')"
            class="save_address_book"
            :dark="theme == 'dark'"
            color="dark"
          />
          <div>
            <q-btn
              class="send_button col-auto"
              :disable="!is_able_to_send"
              color="positive"
              :label="$t('pages.wallet.send.send')"
              @click="send()"
            />
          </div>
        </div>
      </div>

      <q-inner-loading
        :showing="tx_status.sending"
        :dark="theme == 'dark'"
      >
        <q-spinner
          color="primary"
          size="60"
        />
      </q-inner-loading>

      <!-- <q-dialog v-model="confirmXEQSend"               transition-show="flip-up"
              transition-hide="flip-down">
            <q-card :dark="theme == 'dark'">
                <q-card-section>
                    <h5>CONFIRM AMOUNT</h5>
                    <arqmaField :error="v$.newTx.amount.$error">
                            <q-input v-model="newTx.amount"
                                type="number"
                                min="0"
                                :max="unlocked_balance / 1e9"
                                placeholder="0"
                                @blur="v$.newTx.amount.$touch"
                                borderless
                                dense
                                suffix="xeq"
                            />

                        </arqmaField>
                    </q-card-section>
                    <q-card-actions align="right">
                        <q-btn class="sendBtn"
                                color="positive"
                                @click="send()"
                                label="Confirm"/>
                </q-card-actions>
            </q-card>
        </q-dialog> -->
    </template>
  </q-page>
</template>

<script>
import { computed, defineComponent, onMounted, reactive, ref, watch } from "vue"
import axios from "axios"
import { useVuelidate } from "@vuelidate/core"
import { required, decimal, between } from "@vuelidate/validators"
import { payment_id, address, greater_than_zero } from "src/validators/common"
import arqmaField from "components/arqma_field"
import { usePasswordConfirmation } from "src/composables/wallet_password"
import { useRoute, onBeforeRouteUpdate } from "vue-router"
import { useStore } from "vuex"
import { useQuasar, extend } from "quasar"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Send",
  components: {
    arqmaField
  },
  setup () {
    const route = useRoute()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const { showPasswordConfirmation } = usePasswordConfirmation()

    const newTx = reactive({
      amount: "",
      address: "",
      payment_id: "",
      priority: 0,
      currency: 0,
      address_book: {
        save: false,
        name: "",
        description: ""
      },
      note: ""
    })
    const confirmXEQSend = ref(false)
    const sending = ref(false)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const view_only = computed(() => $store.state.gateway.wallet.info.view_only)
    const unlocked_balance = computed(() => $store.state.gateway.wallet.info.unlocked_balance)
    const tx_status = computed(() => $store.state.gateway.tx_status)
    const is_ready = computed(() => $store.getters["gateway/isReady"])
    const is_able_to_send = computed(() => $store.getters["gateway/isAbleToSend"])
    const address_placeholder = computed(() => {
      const wallet = $store.state.gateway.wallet.info
      const prefix = (wallet && wallet.address && wallet.address[0]) || "L"
      return `${prefix}..`
    })
    const conversion_data = computed(() => $store.state.gateway.conversion_data)

    // Validations
    const rules = computed(() => {
      return {
        amount: { between: between(0.0001, unlocked_balance.value / 1e9), decimal, required },
        address: { required },
        payment_id: { required },
        currency: { },
        address_book: {
          save: { },
          name: { },
          description: { }
        },
        note: { }
      }
    })

    const v$ = useVuelidate(rules, newTx)

    // Hooks

    onMounted(() => {
      if (route.path === "/wallet/send" && route.query.address) {
        autoFill(route.query)
      }
    })

    // Methods
    const autoFill = async (info) => {
      try {
        newTx.address = info.address
        newTx.payment_id = info.payment_id
      } catch (error) {
        await api.error("/pages/wallet/send", "autoFill", error.stack || error)
      }
    }

    const getAmount = async () => {
      try {
        return newTx.amount
      } catch (error) {
        await api.error("/pages/wallet/send", "getAmount", error.stack || error)
      }
    }

    const conversionFromXtri = () => {
      try {
        // Do conversion with current currency
        newTx.amountInCurrency = (newTx.amount * conversion_data.value.currentPrice * conversion_data.value.sats).toFixed(9)
        return 1
      } catch (error) {
        api.error("/pages/wallet/send", "conversionFromXtri", error.stack || error)
      }
    }

    const all = () => {
      newTx.amount = (unlocked_balance.value / 1e9)
      conversionFromXtri()
    }

    const send = async () => {
      try {
        await v$.value.$validate()
        if (v$.value.amount.$error && v$.value.address.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.send.invalid_amount_address")
          })
          return
        }

        if (v$.value.amount.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.send.invalid_amount")
          })
          return
        }

        if (v$.value.address.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.send.invalid_address")
          })
          return
        }

        const dialog = await showPasswordConfirmation({
          title: t("pages.wallet.send.show_password_confirmation_title"),
          noPasswordMessage: t("pages.wallet.send.show_password_confirmation_message"),
          ok: {
            label: t("pages.wallet.send.show_password_confirmation_ok_label"),
            color: "primary"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })

        dialog.onOk((password) => {
          password = password || ""
          const copy = extend(true, {}, newTx, { password })
          api.send("wallet", "transfer", copy)
        })
          .onDismiss(() => {})
          .onCancel(() => {})
      } catch (error) {
        await api.error("/pages/wallet/send", "send", error.stack || error)
      }
    }

    function resetNewTx () {
      newTx.amount = ""
      newTx.address = ""
      newTx.payment_id = ""
      newTx.priority = 0
      newTx.address_book.save = false
      newTx.address_book.name = ""
      newTx.address_book.description = ""
      newTx.note = ""
    }

    // Watchers
    const tx_statusWatcher = watch(tx_status, async (newVal, oldVal) => {
      try {
        if (!newVal || typeof newVal.code === "undefined") return
        const { code, message } = newVal
        switch (code) {
          case 200:
            $q
              .dialog({
                title: t("pages.wallet.send.tx_status_title"),
                message,
                ok: {
                  label: t("pages.wallet.send.tx_status_ok_label"),
                  color: "positive"
                },
                cancel: {
                  flat: true,
                  label: t("pages.wallet.send.tx_status_cancel_label"),
                  color: "red"
                },
                transitionShow: "flip-up",
                transitionHide: "flip-down",
                dark: theme.value === "dark",
                color: theme.value === "dark" ? "white" : "dark"
              })
              .onOk(() => {
                api.send("wallet", "relay_transfer", {})
              })
              .onDismiss(() => {
                api.send("wallet", "cancelTransaction", { type: "transfer_split" })
              }).onCancel(() => {
                api.send("wallet", "cancelTransaction", { type: "transfer_split" })
              })

            break
          case 201:
            $q.notify({
              type: "positive",
              timeout: 3000,
              message
            })
            v$.value.$reset()
            resetNewTx()
            break
          case -200:
            $q.notify({
              type: "negative",
              timeout: 3000,
              message
            })
            break
        }
      } catch (error) {
        await api.error("/pages/wallet/send", "tx_statusWatcher", error.stack || error)
      }
    })

    function handleAmountInput (val) {
      // Only allow numbers, remove leading zeros, allow empty for editing
      if (val === "" || val === null) {
        newTx.amount = ""
      } else {
        // Remove leading zeros, but allow '0' as a valid value
        const num = Number(val)
        newTx.amount = isNaN(num) ? "" : num
      }
    }

    return {
      t,
      v$,
      newTx,
      all,
      confirmXEQSend,
      sending,
      theme,
      view_only,
      unlocked_balance,
      tx_status,
      is_ready,
      is_able_to_send,
      address_placeholder,
      autoFill,
      getAmount,
      conversionFromXtri,
      send,
      tx_statusWatcher,
      arqmaField,
      showPasswordConfirmation,
      handleAmountInput
    }
  }
})

</script>

<style lang="scss">
.amount {
  padding-right: 10px;
}

.priority {
  padding-left: 10px;
}

.confirmBtn {
  text-align: center;
  .sendBtn {
    margin-top: 2rem;
  }
}
</style>
