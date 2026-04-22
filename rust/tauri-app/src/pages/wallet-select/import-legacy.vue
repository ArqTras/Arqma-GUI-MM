<template>
  <q-page>
    <div class="q-mx-md">
      <template v-if="wallets_legacy.length == 2">
        <q-field>
          <div class="row gutter-md">
            <div>
              <q-radio
                v-model="legacy_type"
                val="0"
                :label="$t('pages.wallet_select.import_legacy.full_wallet')"
              />
            </div>
            <div>
              <q-radio
                v-model="legacy_type"
                val="1"
                :label="$t('pages.wallet_select.import_legacy.lite_wallet')"
              />
            </div>
          </div>
        </q-field>
      </template>

      <arqmaField
        :label="$t('pages.wallet_select.import_legacy.new_account_name')"
        :error="v$.wallet.name.$error"
      >
        <q-input
          v-model="wallet.name"
          :placeholder="$t('pages.wallet_select.import_legacy.new_account_name_placeholder')"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="import_wallet"
          @blur="v$.wallet.name.$touch"
        />
      </arqmaField>

      <arqmaField
        :label="$t('pages.wallet_select.import_legacy.account_file')"
        disable-hover
        :error="v$.wallet.path.$error"
      >
        <q-input
          v-model="wallet.path"
          :placeholder="$t('pages.wallet_select.import_legacy.account_file_placeholder')"
          disable
          :dark="theme == 'dark'"
          borderless
          dense
        />
        <input
          id="walletPath"
          ref="fileInput"
          type="file"
          hidden
          @change="setWalletPath"
        >
        <q-btn
          color="positive"
          :label="$t('pages.wallet_select.import_legacy.select_account_file')"
          :test-color="theme == 'dark' ? 'white' : 'dark'"
          @click="selectFile"
        />
      </arqmaField>

      <!-- <q-field>
        <div class="row gutter-sm">
          <div class="col-12">
            <q-input
              v-model="wallet_path"
              stack-label="Account File"
              disable
              :dark="theme=='dark'"
            />
          </div>
        </div>
      </q-field> -->

      <arqmaField :label="$t('pages.wallet_select.import_legacy.password')">
        <q-input
          v-model="wallet.password"
          :placeholder="$t('pages.wallet_select.import_legacy.password_placeholder')"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="import_wallet"
        />
      </arqmaField>

      <!-- <q-field>
        <q-input
          v-model="wallet.password"
          type="password"
          float-label="Password"
          :dark="theme=='dark'"
        />
      </q-field> -->

      <arqmaField :label="$t('pages.wallet_select.import_legacy.confirm_password')">
        <q-input
          v-model="wallet.password_confirm"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="import_wallet"
        />
      </arqmaField>

      <!-- <q-field>
        <q-input
          v-model="wallet.password_confirm"
          type="password"
          float-label="Confirm Password"
          :dark="theme=='dark'"
        />
      </q-field> -->

      <q-btn
        class="submit-button"
        color="positive"
        :label="$t('pages.wallet_select.import_legacy.import_account')"
        @click="import_wallet"
      />

      <!-- <q-field>
        <q-btn
          color="primary"
          label="Import Account"
          @click="import_wallet"
        />
      </q-field> -->
    </div>
  </q-page>
</template>

<script>
import { computed, defineComponent, reactive, ref, watch } from "vue"
import { useVuelidate } from "@vuelidate/core"
import { required, sameAs } from "@vuelidate/validators"
import { useRouter } from "vue-router"
import { useStore } from "vuex"
import { useQuasar, extend } from "quasar"
import arqmaField from "components/arqma_field"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "ImportLegacy",
  components: {
    arqmaField
  },
  setup () {
    const router = useRouter()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const fileInput = ref(null)
    const wallet = reactive({
      name: "",
      path: "",
      password: "",
      password_confirm: ""
    })
    const legacy_type = ref("0")

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const status = computed(() => $store.state.gateway.wallet.status)
    const wallets_legacy = computed(() => $store.state.gateway.wallets.legacy)
    const wallet_path = computed(() => {
      return "" // $store.state.gateway.wallets.legacy[legacy_type.value].path
    })

    // Watchers
    const statusWatcher = watch(status, async (newVal, oldVal) => {
      try {
        if (val.code === old.code) return
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
        await api.error("pages/wallet-select/import-legacy", "statusWatcher", error.stack || error)
      }
    })

    // Validations
    const rules = computed(() => {
      return {
        name: { required },
        path: { required },
        password: {},
        password_confirm: { sameAs: sameAs(wallet.password) }
      }
    })
    const v$ = useVuelidate(rules, wallet)

    // Methods
    const selectFile = async () => {
      try {
        fileInput.value.click()
      } catch (error) {
        await api.error("pages/wallet-select/created", "selectFile", error.stack || error)
      }
    }

    const setWalletPath = async (file) => {
      try {
        wallet.path = file.target.files[0].path
      } catch (error) {
        await api.error("pages/wallet-select/created", "setWalletPath", error.stack || error)
      }
    }

    const import_wallet = async () => {
      try {
        await v$.value.$validate()

        if (v$.value.name.$error && v$.value.path.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_legacy.import_file_path_message")
          })
          return
        }

        if (v$.value.name.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_legacy.enter_account_name")
          })
          return
        }

        if (v$.value.path.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_legacy.enter_path_file")
          })
          return
        }

        if (v$.value.password_confirm.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import_legacy.passwords_dont_match")
          })
          return
        }

        $q.loading.show({
          delay: 0
        })

        api.send("wallet", "import_wallet", extend(true, {}, wallet))
      } catch (error) {
        await api.error("pages/wallet-select/created", "import_wallet", error.stack || error)
      }
    }

    const cancel = async () => {
      try {
        router.push({ path: "/wallet-select" })
      } catch (error) {
        await api.error("pages/wallet-select/created", "cancel", error.stack || error)
      }
    }

    return {
      t,
      v$,
      fileInput,
      wallet,
      legacy_type,
      theme,
      status,
      wallets_legacy,
      wallet_path,
      statusWatcher,
      selectFile,
      setWalletPath,
      import_wallet,
      cancel,
      arqmaField
    }
  }
})
</script>

<style lang="scss">
.import-wallet {
    .q-if-disabled {
        cursor: default !important;
        .q-input-target {
            cursor: default !important;
        }
    }

    .arqma-field {
        margin-top: 16px;
    }
}
</style>
