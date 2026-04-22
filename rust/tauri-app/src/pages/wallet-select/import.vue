<template>
  <q-page>
    <div class="q-mx-md import-wallet">
      <arqmaField
        :label="$t('pages.wallet_select.import.account_name')"
        :error="v$.name.$error"
      >
        <q-input
          v-model="wallet.name"
          :placeholder="$t('pages.wallet_select.import.wallet_name_placeholder')"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="import_wallet"
          @blur="v$.name.$validate()"
        />
      </arqmaField>

      <arqmaField
        :label="$t('pages.wallet_select.import.account_file')"
        disable-hover
        :error="v$.path.$error"
      >
        <q-input
          v-model="wallet.path"
          :placeholder="$t('pages.wallet_select.import.select_file')"
          disable
          :dark="theme == 'dark'"
          borderless
          dense
          @blur="v$.path.$validate()"
        />
        <input
          id="walletPath"
          ref="fileInput"
          type="file"
          accept=".keys"
          hidden
          @change="setWalletPath"
        >
        <q-btn
          color="positive"
          :label="$t('pages.wallet_select.import.select_account_file')"
          :test-color="theme == 'dark' ? 'white' : 'dark'"
          @click="selectFile"
        />
      </arqmaField>

      <arqmaField :label="$t('pages.wallet_select.import.password')">
        <q-input
          v-model="wallet.password"
          :placeholder="$t('pages.wallet_select.import.password_placeholder')"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="import_wallet"
        />
      </arqmaField>

      <arqmaField :label="$t('pages.wallet_select.import.confirm_password')">
        <q-input
          v-model="wallet.password_confirm"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
          @keyup.enter="import_wallet"
        />
      </arqmaField>

      <q-btn
        class="submit-button"
        color="positive"
        :label="$t('pages.wallet_select.import.import_account')"
        @click="import_wallet"
      />
    </div>
  </q-page>
</template>

<script>
import { useVuelidate } from "@vuelidate/core"
import { required, sameAs } from "@vuelidate/validators"
import { useStore } from "vuex"
import { useQuasar, extend } from "quasar"
import arqmaField from "components/arqma_field"
import { defineComponent, ref, reactive, computed, watch } from "vue"
import { useRouter } from "vue-router"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Import",
  components: {
    arqmaField
  },
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const router = useRouter()
    const { t } = useI18n()

    const fileInput = ref(null)
    const wallet = reactive({
      name: "",
      path: "",
      password: "",
      password_confirm: ""
    })

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const status = computed(() => $store.state.gateway.wallet.status)

    // Watchers
    const statusWatcher = watch(status, async (newVal, oldVal) => {
      try {
        if (newVal.code === oldVal.code) return
        const { code, message } = newVal
        switch (code) {
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
              message
            })
            break
        }
      } catch (error) {
        await api.error("pages/wallet-select/import", "statusWatch", error.stack || error)
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
        await api.error("pages/wallet-select/import", "selectFile", error.stack || error)
      }
    }

    const setWalletPath = async (file) => {
      try {
        wallet.path = file.target.files[0].path
      } catch (error) {
        await api.error("pages/wallet-select/import", "setWalletPath", error.stack || error)
      }
    }

    const import_wallet = async () => {
      try {
        await v$.value.$validate()

        if (v$.value.name.$error && v$.value.path.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import.import_file_path_message")
          })
          return
        }

        if (v$.value.name.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import.import_account_name_message")
          })
          return
        }

        if (v$.value.path.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import.import_path_message")
          })
          return
        }

        if (v$.value.password_confirm.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.import.passwords_dont_match")
          })
          return
        }

        $q.loading.show({
          delay: 0
        })

        api.send("wallet", "import_wallet", extend(true, {}, wallet))
      } catch (error) {
        await api.error("pages/wallet-select/import", "import_wallet", error.stack || error)
      }
    }

    const cancel = async () => {
      try {
        router.push({ path: "/wallet-select" })
      } catch (error) {
        await api.error("pages/wallet-select/import", "cancel", error.stack || error)
      }
    }

    return {
      t,
      v$,
      fileInput,
      wallet,
      theme,
      status,
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
