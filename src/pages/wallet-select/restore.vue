<template>
  <q-page>
    <div class="q-mx-md">
      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.restore.account_name')"
        :error="v$.name.$error"
      >
        <q-input
          v-model="wallet.name"
          :placeholder="$t('pages.wallet_select.restore.wallet_name_placeholder')"
          :dark="theme == 'dark'"
          borderless
          dense
          @blur="v$.name.$validate()"
        />
      </arqmaField>

      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.restore.mnemonic_seed')"
        :error="v$.seed.$error"
      >
        <q-input
          v-model="wallet.seed"
          class="full-width text-area-arqma"
          :placeholder="$t('pages.wallet_select.restore.mnemonic_seed_placeholder')"
          type="textarea"
          :dark="theme == 'dark'"
          borderless
          dense
          @blur="v$.seed.$validate()"
        />
      </arqmaField>

      <div class="row items-end q-mt-md">
        <div class="col-md-9 col-sm-8">
          <arqmaField
            v-if="wallet.refresh_type=='date'"
            :label="$t('pages.wallet_select.restore.restore_date')"
          >
            <q-input
              v-model="wallet.refresh_start_date"
              mask="date"
              borderless
              dense
            >
              <template #append>
                <q-icon
                  v-if="wallet.refresh_type == 'date'"
                  name="event"
                  class="cursor-pointer"
                >
                  <q-popup-proxy
                    ref="qDateProxy"
                    cover
                    transition-show="scale"
                    transition-hide="scale"
                  >
                    <q-date
                      v-model="wallet.refresh_start_date"
                      :dark="theme == 'dark'"
                      :options="dateRangeOptions"
                    >
                      <div class="row items-center justify-end">
                        <q-btn
                          v-close-popup
                          :label="$t('pages.wallet_select.restore.close')"
                          color="primary"
                          flat
                        />
                      </div>
                    </q-date>
                  </q-popup-proxy>
                </q-icon>
              </template>
            </q-input>
          </arqmaField>
          <arqmaField
            v-else-if="wallet.refresh_type=='height'"
            :label="$t('pages.wallet_select.restore.restore_from_block_height_label')"
            :error="v$.refresh_start_height.$error"
          >
            <q-input
              v-model="wallet.refresh_start_height"
              type="number"
              min="0"
              :dark="theme == 'dark'"
              borderless
              dense
              @blur="v$.refresh_start_height.$validate()"
            />
          </arqmaField>
        </div>
        <div class="col-sm-4 col-md-3">
          <template v-if="wallet.refresh_type == 'date'">
            <q-btn
              color="positive"
              :text-color="theme == 'dark' ? 'white' : 'dark'"
              @click="wallet.refresh_type = 'height'"
            >
              <div class="column justify-center items-center">
                <q-icon name="clear_all" />
                {{ $t('pages.wallet_select.restore.switch_to_height_select') }}
              </div>
            </q-btn>
          </template>
          <template v-else-if="wallet.refresh_type == 'height'">
            <q-btn
              color="positive"
              :text-color="theme == 'dark' ? 'white' : 'dark'"
              @click="wallet.refresh_type = 'date'"
            >
              <div class="column justify-center items-center">
                <q-icon name="today" />
                {{ $t('pages.wallet_select.restore.switch_to_date_select') }}
              </div>
            </q-btn>
          </template>
        </div>
      </div>

      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.restore.password_label')"
      >
        <q-input
          v-model="wallet.password"
          :placeholder="$t('pages.wallet_select.restore.password')"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="restore_wallet"
        />
      </arqmaField>

      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.restore.confirm_password')"
      >
        <q-input
          v-model="wallet.password_confirm"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="restore_wallet"
        />
      </arqmaField>

      <q-btn
        class="submit-button"
        color="positive"
        :label="$t('pages.wallet_select.restore.restore_account')"
        @click="restore_wallet"
      />
    </div>
  </q-page>
</template>

<script>
import { defineComponent, reactive, computed, watch } from "vue"
import { useVuelidate } from "@vuelidate/core"
import { required, numeric, sameAs } from "@vuelidate/validators"
import { trimmedRequired } from "src/validators/common"
import { useStore } from "vuex"
import arqmaField from "components/arqma_field"
import { date, useQuasar, extend } from "quasar"
import { useRouter } from "vue-router"
import { useI18n } from "vue-i18n"

const timeStampFirstBlock = "2018/10/31"
const qDateFormat = "YYYY/MM/DD"

export default defineComponent({
  name: "Restore",
  components: {
    arqmaField
  },
  setup () {
    const router = useRouter()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const wallet = reactive({
      name: "",
      seed: "",
      refresh_type: "date",
      refresh_start_height: 0,
      refresh_start_date: timeStampFirstBlock, // timestamp of block 1
      password: "",
      password_confirm: ""
    })

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const status = computed(() => $store.state.gateway.wallet.status)

    // Watchers
    const statusWatcher = watch(status, async (newVal, oldVal) => {
      try {
        switch (newVal.code) {
          case 1:
            break
          case 0:
            $q.loading.hide()
            router.push({ path: "/wallet-select/created" })
            break
          default:
            $q.loading.hide()
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: newVal.message
            })
            break
        }
      } catch (error) {
        await api.error("pages/wallet-select/restore", "statusWatcher", error.stack || error)
      }
    })

    const rules = computed(() => {
      return {
        name: { required: trimmedRequired },
        seed: { required: trimmedRequired },
        refresh_start_height: { numeric },
        password: {},
        password_confirm: { sameAs: sameAs(wallet.password) }
      }
    })

    const v$ = useVuelidate(rules, wallet)

    // Methods
    const restore_wallet = async () => {
      try {
        v$.value.$validate()

        if (v$.value.name.$error && v$.value.seed.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.restore.restore_wallet_message")
          })
          return
        }

        if (v$.value.name.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.restore.enter_wallet_name")
          })
          return
        }

        if (v$.value.seed.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.restore.enter_seed_words")
          })
          return
        }

        const seed = wallet.seed.trim()
          .replace(/\n/g, " ")
          .replace(/\t/g, " ")
          .replace(/\s{2,}/g, " ")
          .split(" ")

        if (seed.length !== 14 && seed.length !== 24 && seed.length !== 25 && seed.length !== 26) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.restore.invalid_seed_words")
          })
          return
        }

        if (wallet.refresh_type === "height") {
          if (v$.value.refresh_start_height.$error) {
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: t("pages.wallet_select.restore.invalid_restore_height")
            })
            return
          }
        }

        if (v$.value.password_confirm.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.restore.passwords_dont_match")
          })
          return
        }

        // Warn user if no password is set
        if (!wallet.password) {
          const dialog = $q.dialog({
            title: t("pages.wallet_select.restore.confirm_no_password_title"),
            message: t("pages.wallet_select.restore.confirm_no_password_message"),
            ok: {
              label: t("pages.wallet_select.restore.confirm_no_password_ok_label"),
              color: "positive"
            },
            cancel: {
              flat: true,
              label: t("pages.wallet_select.restore.confirm_no_password_cancel_label"),
              color: "red"
            },
            transitionShow: "flip-up",
            transitionHide: "flip-down",
            dark: theme.value === "dark",
            color: "positive"
          })

          dialog.onOk(() => {
            $q.loading.show({
              delay: 0
            })
            api.send("wallet", "restore_wallet", extend(true, {}, wallet))
          })
            .onDismiss(() => {})
            .onCancel(() => {})
          return
        }

        $q.loading.show({
          delay: 0
        })

        api.send("wallet", "restore_wallet", extend(true, {}, wallet))
      } catch (error) {
        await api.error("pages/wallet-select/restore", "restore_wallet", error.stack || error)
      }
    }

    const dateRangeOptions = (dateSelected) => {
      const now = Date.now()
      const formattedNow = date.formatDate(now, qDateFormat)
      return dateSelected > timeStampFirstBlock && dateSelected <= formattedNow
    }

    const cancel = () => {
      router.push({ path: "/wallet-select" })
    }

    return {
      t,
      wallet,
      theme,
      status,
      statusWatcher,
      v$,
      restore_wallet,
      dateRangeOptions,
      cancel,
      arqmaField
    }
  }
})
</script>

<style>
</style>
