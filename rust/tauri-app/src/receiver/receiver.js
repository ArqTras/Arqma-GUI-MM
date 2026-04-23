import { api } from "@/bridge/api"
import { Notify, Dialog, Loading } from "quasar"
import { EventEmitter } from "events"
import { i18n, loadLocaleMessages } from "src/boot/i18n"
const t = i18n.global.t

export class Receiver extends EventEmitter {
  closeDialog = false
  constructor (store, router) {
    super()
    this.store = store
    this.router = router

    // this.loadLanguage()
    api.autoUpdater((event, message) => {
      switch (message.event) {
        case "error":
        case "checking-for-update":
        case "update-available":
        case "update-not-available":
        case "update-downloading":
        case "update-downloaded":
        case "before-quit-for-update":
          console.log(message.event, message.data)
          break
      }
    })
    api.receive((event, message) => {
      switch (message.event) {
        case "set_has_password":
          this.emit("has_password", message.data)
          break

        case "set_valid_address":
          this.emit("validate_address", message.data)
          break

        case "set_app_data":
          this.store.commit("gateway/set_app_data", message.data)
          break

        case "set_ethereum_data":
          this.store.commit("gateway/set_ethereum_data", message.data)
          break

        case "set_daemon_data":
          this.store.commit("gateway/set_daemon_data", message.data)
          break

        case "reset_wallet_data":
          this.store.commit("gateway/reset_wallet_data", message.data)
          break

        case "set_wallet_error":
          this.store.commit("gateway/set_wallet_error", message.data)
          break

        case "set_wallet_transactions":
          this.store.commit("gateway/set_wallet_transactions", message.data)
          break

        case "set_wallet_transaction":
          this.store.commit("gateway/set_wallet_transaction", message.data)
          break

        case "reset_wallet_status":
          this.store.commit("gateway/reset_wallet_status", message.data)
          break

        case "set_wallet_address_list":
          this.store.commit("gateway/set_wallet_address_list", message.data)
          break

        case "set_wallet_address_book":
          this.store.commit("gateway/set_wallet_address_book", message.data)
          break

        case "set_wallet_info":
          this.store.commit("gateway/set_wallet_info", message.data)
          break

        case "set_wallet_secret":
          this.store.commit("gateway/set_wallet_secret", message.data)
          break

        case "set_pools_data":
          this.store.commit("gateway/set_pools_data", message.data)
          break
        case "set_pool_data":
          this.store.commit("gateway/set_pool_data", message.data)
          break

        case "set_coin_price":
          this.store.commit("gateway/set_coin_price", message.data)
          break

        case "set_conversion_data":
          this.store.commit("gateway/set_conversion_data", message.data)
          break

        case "set_signature_data":
          if (this.store.state.gateway.signature_data.length === 0 && message.data.length === 0) { return }
          this.store.commit("gateway/set_signature_data", message.data)
          break

        case "reset_wallet_error":
          this.store.dispatch("gateway/resetWalletStatus")
          break

        case "set_tx_status":
          this.store.commit("gateway/set_tx_status", message.data)
          break

        case "sweep_all_progress":
          this.store.commit("gateway/set_sweep_all_progress", message.data)
          break

        case "set_snode_status":
          this.store.commit("gateway/set_snode_status", message.data)
          break

        case "set_snode_status_unlock":
          this.store.commit("gateway/set_snode_status_unlock", message.data)
          break

        case "set_old_gui_import_status":
          this.store.commit("gateway/set_old_gui_import_status", message.data)
          break

        case "wallet_list":
          this.store.commit("gateway/set_wallet_list", message.data)
          break

        case "settings_changed_reboot":
          this.confirmClose(t("receiver.confirm_close"), true)
          break

        case "show_notification": {
          const notification = {
            type: "positive",
            timeout: 3000,
            message: ""
          }
          Notify.create(Object.assign(notification, message.data))
          break
        }

        case "show_loading":
          Loading.show({ ...(message.data || {}) })
          break

        case "hide_loading":
          Loading.hide()
          break

        case "return_to_wallet_select":
          this.router.push({ path: "/wallet-select" })
          // setTimeout(() => {
          // short delay to prevent wallet data reaching the
          // websocket moments after we close and reset data
          this.store.dispatch("gateway/resetWalletData")
          //   }, 250)
          break
        case "initialize":
          this.store.commit("gateway/set_app_data", {
            status: {
              code: 2 // Loading config
            }
          })
          api.info("receiver", "initialize", "before core init")
          api.send("core", "init")
          break
        case "daemon_version":
          this.store.commit("gateway/daemon_version", message.data)
          break
      }
    })
  }

  confirmClose = (msg, restart = false) => {
    if (this.closeDialog) {
      return
    }
    this.closeDialog = true
    const isDark = true
    try {
    //   isDark = this.app.store.state.gateway.app.config.apperance.theme === "dark"
    } catch (error) {}

    const isLoading = Loading.isActive
    Loading.hide()
    Dialog.create({
      title: restart ? t("receiver.restart") : t("receiver.exit"),
      message: msg,
      ok: {
        label: restart ? t("receiver.restart") : t("receiver.exit"),
        color: "positive"
      },
      cancel: {
        flat: true,
        label: t("receiver.cancel"),
        color: "red"
      },
      dark: isDark,
      transitionShow: "flip-up",
      transitionHide: "flip-down"
    })
      .onOk(() => {
        this.closeDialog = false
        Loading.hide()
        this.router.replace({ path: "/quit" })
        api.confirmClose(restart)
      }).onCancel(() => {
        this.closeDialog = false
        if (isLoading) {
          Loading.show()
        }
      })
  }

  setLanguage = async (language) => {
    await loadLocaleMessages(i18n, language)
  }
}
