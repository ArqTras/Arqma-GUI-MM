<template>
  <q-page>
    <div class="q-mx-md">
      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.import_view_only.account_name')"
        :error="v$.name.$error"
      >
        <q-input
          v-model="wallet.name"
          :placeholder="$t('pages.wallet_select.import_view_only.account_name_placeholder')"
          :dark="theme == 'dark'"
          borderless
          dense
          @blur="v$.name.$validate"
        />
      </arqmaField>

      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.import_view_only.account_address')"
        :error="v$.address.$error"
      >
        <q-input
          v-model="wallet.address"
          class="full-width text-area-arqma"
          :placeholder="$t('pages.wallet_select.import_view_only.account_address_placeholder')"
          :dark="theme == 'dark'"
          borderless
          dense
          @blur="v$.address.$validate"
        />
      </arqmaField>

      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.import_view_only.private_view_key')"
        :error="v$.viewkey.$error"
      >
        <q-input
          v-model="wallet.viewkey"
          class="full-width text-area-arqma"
          :placeholder="$t('pages.wallet_select.import_view_only.private_view_key_placeholder')"
          :dark="theme == 'dark'"
          borderless
          dense
          @blur="v$.viewkey.$touch"
        />
      </arqmaField>

      <div class="row items-end q-mt-md">
        <div class="col-md-9 col-sm-8">
          <arqmaField
            v-if="wallet.refresh_type=='date'"
            :label="$t('pages.wallet_select.import_view_only.restore_from_date')"
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
                          :label="$t('pages.wallet_select.import_view_only.close')"
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
            :label="$t('pages.wallet_select.import_view_only.restore_from_height')"
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
                {{ $t('pages.wallet_select.import_view_only.switch_to_height_select') }}
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
                {{ $t('pages.wallet_select.import_view_only.switch_to_date_select') }}
              </div>
            </q-btn>
          </template>
        </div>
      </div>

      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.import_view_only.password')"
      >
        <q-input
          v-model="wallet.password"
          :placeholder="$t('pages.wallet_select.import_view_only.password_placeholder')"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="restore_view_wallet"
        />
      </arqmaField>

      <arqmaField
        class="q-mt-md"
        :label="$t('pages.wallet_select.import_view_only.confirm_password')"
      >
        <q-input
          v-model="wallet.password_confirm"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="restore_view_wallet"
        />
      </arqmaField>

      <q-btn
        class="submit-button"
        color="positive"
        :label="$t('pages.wallet_select.import_view_only.restore_view_only_account')"
        @click="restore_view_wallet"
      />
    </div>
  </q-page>
</template>

<script>
import { computed, defineComponent, ref, reactive, watch } from "vue"
import { useVuelidate } from "@vuelidate/core"
import { required, numeric, sameAs } from "@vuelidate/validators"
import { privkey } from "src/validators/common"
import { useStore } from "vuex"
import { date, useQuasar, extend } from "quasar"
import arqmaField from "components/arqma_field"
import { useRouter } from "vue-router"
import { useI18n } from "vue-i18n"

const timeStampFirstBlock = "2018/10/31"
const qDateFormat = "YYYY/MM/DD"

export default defineComponent({
  name: "ImportViewOnly",
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
      address: "",
      viewkey: "",
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
        await api.error("pages/wallet-select/import-view-only", "statusWatch", error.stack || error)
      }
    })

    // Validations
    const rules = computed(() => {
      return {
        name: { required },
        address: { required },
        viewkey: { required, privkey },
        refresh_start_height: { numeric },
        password: {},
        password_confirm: { sameAs: sameAs(wallet.password) }
      }
    })
    const v$ = useVuelidate(rules, wallet)

    // Methods
    const restore_view_wallet = async () => {
      try {
        await v$.value.$validate()

        if (v$.value.name.$error && v$.value.address.$error && v$.value.viewkey.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_view_only.enter_an_account_name_address_viewkey")
          })
          return
        }

        if (v$.value.name.$error && v$.value.address.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_view_only.enter_an_account_name_address")
          })
          return
        }

        if (v$.value.name.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_view_only.enter_an_account_name")
          })
          return
        }
        if (v$.value.address.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_view_only.invalid_account_address")
          })
          return
        }

        if (v$.value.viewkey.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_view_only.invalid_private_viewkey")
          })
          return
        }

        if (wallet.refresh_type === "height") {
          if (v$.value.refresh_start_height.$error) {
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: t("pages.wallet_select.import_view_only.invalid_restore_height")
            })
            return
          }
        }

        if (v$.value.password_confirm.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_view_only.passwords_do_not_match")
          })
          return
        }

        $q.loading.show({
          delay: 0
        })

        api.send("wallet", "restore_view_wallet", extend(true, {}, wallet))
      } catch (error) {
        await api.error("pages/wallet-select/import-view-only", "restore_view_wallet", error.stack || error)
      }
    }

    const dateRangeOptions = (dateSelected) => {
      const now = Date.now()
      const formattedNow = date.formatDate(now, qDateFormat)
      return dateSelected > timeStampFirstBlock && dateSelected <= formattedNow
    }

    const cancel = async () => {
      try {
        router.push({ path: "/wallet-select" })
      } catch (error) {
        await api.error("pages/wallet-select/import-view-only", "cancel", error.stack || error)
      }
    }

    return {
      t,
      v$,
      wallet,
      theme,
      status,
      statusWatcher,
      rules,
      restore_view_wallet,
      dateRangeOptions,
      cancel,
      arqmaField
    }
  }
})
</script>

<style>
</style>
