import { useQuasar } from "quasar"
import { inject } from "vue"
import { useI18n } from "vue-i18n"

export function usePasswordConfirmation () {
  const q$ = useQuasar()
  const { t } = useI18n()

  const gateway = inject("gateway")

  // Methods
  const hasRPCWalletCachedPassword = () => {
    return new Promise((resolve) => {
      gateway.once("has_password", (message) => {
        resolve(message)
      })
      api.send("wallet", "has_password")
    })
  }

  const showPasswordConfirmation = async (options) => {
    const { noPasswordMessage, ...other } = options
    const result = await hasRPCWalletCachedPassword()
    const sharedOpts = {
      cancel: {
        flat: true,
        label: t("composables.cancel"),
        color: "red"
      },
      ...other
    }
    let usedOpts = null
    if (result) {
      usedOpts = {
        ...sharedOpts,
        message: noPasswordMessage
      }
    } else {
      usedOpts = {
        ...sharedOpts,
        message: t("composables.enter_wallet_password_to_continue"),
        transitionShow: "flip-up",
        transitionHide: "flip-down",
        prompt: {
          model: "",
          type: "password"
        }
      }
    }
    return q$.dialog(usedOpts)
  }

  return {
    t,
    hasRPCWalletCachedPassword,
    showPasswordConfirmation,
    q$
  }
}
