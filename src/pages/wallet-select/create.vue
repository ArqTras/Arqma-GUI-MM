<template>
  <q-page class="create-wallet">
    <div class="fields q-mx-md q-mt-md">
      <arqmaField
        :label="$t('pages.wallet_select.create.account_name')"
        :error="v$.name.$error"
      >
        <q-input
          v-model="wallet.name"
          :dark="theme == 'dark'"
          :placeholder="$t('pages.wallet_select.create.wallet_name_placeholder')"
          borderless
          dense
          @blur="v$.name.$validate()"
        />
      </arqmaField>

      <arqmaField :label="$t('pages.wallet_select.create.seed_language')">
        <q-select
          v-model="wallet.language"
          :options="languageOptions"
          :dark="theme == 'dark'"
          borderless
          dense
        />
      </arqmaField>

      <arqmaField
        :label="$t('pages.wallet_select.create.password')"
        optional
      >
        <q-input
          v-model="wallet.password"
          type="password"
          :dark="theme == 'dark'"
          :placeholder="$t('pages.wallet_select.create.optional_password_for_account')"
          borderless
          dense
        />
      </arqmaField>

      <arqmaField :label="$t('pages.wallet_select.create.confirm_password')">
        <q-input
          v-model="wallet.password_confirm"
          type="password"
          :dark="theme == 'dark'"
          borderless
          dense
        />
      </arqmaField>

      <q-btn
        class="submit-button"
        color="positive"
        :label="$t('pages.wallet_select.create.create_account')"
        @click="create"
      />
    </div>
  </q-page>
</template>

<script>
import { computed, defineComponent, ref, reactive, watch } from "vue"
import { useVuelidate } from "@vuelidate/core"
import { required, sameAs } from "@vuelidate/validators"
import { useRouter } from "vue-router"
import arqmaField from "components/arqma_field"
import { useQuasar, extend } from "quasar"
import { useStore } from "vuex"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Create",
  components: {
    arqmaField
  },
  setup () {
    const router = useRouter()
    const $q = useQuasar()
    const $store = useStore()
    const { t } = useI18n()

    const wallet = reactive({
      name: "",
      language: "English",
      password: "",
      password_confirm: ""
    })

    const languageOptions = ref([

      { label: "English", value: "English" },
      { label: "Deutsch", value: "Deutsch" },
      { label: "Español", value: "Español" },
      { label: "Français", value: "Français" },
      { label: "Italiano", value: "Italiano" },
      { label: "Nederlands", value: "Nederlands" },
      { label: "Português", value: "Português" },
      { label: "Русский", value: "Русский" },
      { label: "日本語", value: "日本語" },
      { label: "简体中文 (中国)", value: "简体中文 (中国)" },
      { label: "Esperanto", value: "Esperanto" },
      { label: "Lojban", value: "Lojban" }

    ])

    // Validations
    const rules = computed(() => {
      return {
        name: { required },
        password: {},
        password_confirm: { sameAs: sameAs(wallet.password) }
      }
    })

    const v$ = useVuelidate(rules, wallet)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const status = computed(() => $store.state.gateway.wallet.status)

    // Watchers
    const statusWatcher = watch(status, async (newVal, oldVal) => {
      try {
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
        await api.error("pages/wallet-select/create", "statusWatch", error.stack || error)
      }
    })

    // Methods
    const create = async () => {
      try {
        await v$.value.$validate()

        if (v$.value.name.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.create.enter_an_account_name")
          })
          return
        }
        if (v$.value.password_confirm.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.create.passwords_do_not_match")
          })
          return
        }

        // Warn user if no password is set
        if (!wallet.password) {
          const dialog = $q.dialog({
            title: t("pages.wallet_select.create.confirm_no_password_title"),
            message: t("pages.wallet_select.create.confirm_no_password_message"),
            ok: {
              label: t("pages.wallet_select.create.confirm_no_password_ok_label"),
              color: "positive"
            },
            cancel: {
              flat: true,
              label: t("pages.wallet_select.create.confirm_no_password_cancel_label"),
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
            api.send("wallet", "create_wallet", extend(true, {}, wallet))
          })
            .onDismiss(() => {})
            .onCancel(() => {})
          return
        }

        $q.loading.show({
          delay: 0
        })
        api.send("wallet", "create_wallet", extend(true, {}, wallet))
      } catch (error) {
        await api.error("/pages/wallet-select/create", "create", error.stack || error)
      }
    }

    const cancel = () => {
      router.push({ path: "/wallet-select" })
    }

    return {
      t,
      v$,
      wallet,
      languageOptions,
      rules,
      theme,
      status,
      statusWatcher,
      create,
      cancel,
      arqmaField
    }
  }
})
</script>

<style lang="scss">
</style>
