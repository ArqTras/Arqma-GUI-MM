<template>
  <q-page>
    <div
      style="max-height: 75vh; overflow: auto"
      class="col"
    >
      <div
        :visible="false"
        class="fit column"
      >
        <q-list
          class="wallet-list"
          link
          no-border
          :dark="theme == 'dark'"
        >
          <template v-if="wallets.list.length">
            <div class="header row justify-between items-center">
              <div class="header-title">
                {{ $t("pages.wallet_select.index.accounts") }}
              </div>
              <q-btn
                v-if="wallets.list.length"
                class="add"
                icon="add"
                size="md"
                color="primary"
              >
                <q-menu
                  transition-show="flip-up"
                  transition-hide="flip-down"
                  class="header-popover"
                  :content-class="'header-popover'"
                >
                  <q-list separator>
                    <div>
                      <q-item
                        v-for="action in actions"
                        :key="action.name"
                        clickable
                        @click="action.handler"
                      >
                        <q-item-section>
                          {{ action.name }}
                        </q-item-section>
                      </q-item>
                    </div>
                  </q-list>
                </q-menu>
              </q-btn>
            </div>
            <div class="hr-separator" />
            <q-item
              v-for="wallet in wallets.list"
              :key="`${wallet.address}-${wallet.name}`"
              clickable
              @click="openWallet(wallet)"
            >
              <q-item-section avatar>
                <q-icon class="wallet-icon">
                  <svg
                    width="48"
                    viewBox="0 0 17 16"
                    version="1.1"
                    xmlns="http://www.w3.org/2000/svg"
                    xmlns:xlink="http://www.w3.org/1999/xlink"
                    class="si-glyph si-glyph-wallet"
                  >
                    <defs class="si-glyph-fill" />
                    <g
                      stroke="none"
                      stroke-width="1"
                      fill="none"
                      fill-rule="evenodd"
                    >
                      <g
                        transform="translate(1.000000, 0.000000)"
                        fill="#434343"
                      >
                        <path
                          d="M7.988,10.635 L7.988,8.327 C7.988,7.578 8.561,6.969 9.267,6.969 L13.964,6.969 L13.964,5.531 C13.964,4.849 13.56,4.279 13.007,4.093 L13.007,4.094 L11.356,4.08 L11.336,4.022 L3.925,4.022 L3.784,4.07 L1.17,4.068 L1.165,4.047 C0.529,4.167 0.017,4.743 0.017,5.484 L0.017,13.437 C0.017,14.269 0.665,14.992 1.408,14.992 L12.622,14.992 C13.365,14.992 13.965,14.316 13.965,13.484 L13.965,12.031 L9.268,12.031 C8.562,12.031 7.988,11.384 7.988,10.635 L7.988,10.635 Z"
                          class="si-glyph-fill"
                        />
                        <path
                          d="M14.996,8.061 L14.947,8.061 L9.989,8.061 C9.46,8.061 9.031,8.529 9.031,9.106 L9.031,9.922 C9.031,10.498 9.46,10.966 9.989,10.966 L14.947,10.966 L14.996,10.966 C15.525,10.966 15.955,10.498 15.955,9.922 L15.955,9.106 C15.955,8.528 15.525,8.061 14.996,8.061 L14.996,8.061 Z M12.031,10.016 L9.969,10.016 L9.969,9 L12.031,9 L12.031,10.016 L12.031,10.016 Z"
                          class="si-glyph-fill"
                        />
                        <path
                          d="M3.926,4.022 L10.557,1.753 L11.337,4.022 L12.622,4.022 C12.757,4.022 12.885,4.051 13.008,4.092 L11.619,0.051 L1.049,3.572 L1.166,4.048 C1.245,4.033 1.326,4.023 1.408,4.023 L3.926,4.023 L3.926,4.022 Z"
                          class="si-glyph-fill"
                        />
                      </g>
                    </g>
                  </svg>
                </q-icon>
              </q-item-section>
              <q-item-section>
                <q-item-label
                  class="wallet-name"
                  caption
                >
                  {{ wallet.name }}
                </q-item-label>
                <q-item-label
                  class="monospace ellipsis"
                  caption
                >
                  {{ wallet.address }}
                </q-item-label>
              </q-item-section>

              <q-menu
                context-menu
                transition-show="flip-up"
                transition-hide="flip-down"
              >
                <q-list
                  link
                  separator
                  class="context-menu"
                >
                  <q-item
                    v-close-popup
                    clickable
                    @click="openWallet(wallet)"
                  >
                    <q-item-section>{{ $t("pages.wallet_select.index.open_account") }}</q-item-section>
                  </q-item>

                  <q-item
                    v-close-popup
                    clickable
                    @click="copyAddress(wallet.address, $event)"
                  >
                    <q-item-section>{{ $t("pages.wallet_select.index.copy_address") }}</q-item-section>
                  </q-item>
                </q-list>
              </q-menu>
            </q-item>
            <q-separator />
          </template>
          <template v-else>
            <div>
              <q-item
                v-for="action in actions"
                :key="action.name"
                clickable
                @click="action.handler"
              >
                <q-item-section>
                  {{ action.name }}
                </q-item-section>
              </q-item>
            </div>
          </template>
        </q-list>
      </div>
    </div>
  </q-page>
</template>

<script>
import { computed, defineComponent, watch } from "vue"
import { useRouter } from "vue-router"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import { useI18n } from "vue-i18n"

export default defineComponent({
  components: {
    // Identicon
  },
  setup () {
    const router = useRouter()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const wallets = computed(() => $store.state.gateway.wallets)
    const status = computed(() => $store.state.gateway.wallet.status)
    const actions = computed(() => {
      const actions = [
        {
          name: t("pages.wallet_select.index.create_new_account"),
          handler: createNewWallet
        },
        {
          name: t("pages.wallet_select.index.restore_account_from_seed"),
          handler: restoreWallet
        },
        {
          name: t("pages.wallet_select.index.import_account_from_file"),
          handler: importWallet
        },
        {
          name: t("pages.wallet_select.index.restore_account_from_viewkey"),
          handler: restoreViewWallet
        }
      ]

      if (wallets.value.directories.length > 0) {
        actions.push({
          name: t("pages.wallet_select.index.import_accounts_from_old_gui"),
          handler: importOldGuiWallets
        })
      }
      return actions
    })
    // Watchers
    const statusWatcher = watch(status, async (newVal, oldVal) => {
      try {
        if (newVal.code === oldVal.code) return
        switch (newVal.code) {
          case 0: // Wallet loaded
            $q.loading.hide()
            router.push({ path: "/wallet" })
            break
          case -1: // Error
          case -22:
            $q.loading.hide()
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: status.value.message
            })
            $store.commit("gateway/reset_wallet_status", {
              status: {
                code: 1 // Reset to 1 (ready for action)
              }
            })
            break
        }
      } catch (error) {
        await api.error("pages/wallet-select/index", "statusWatcher", error.stack || error)
      }
    })

    // Methods
    const openWallet = async (wallet) => {
      try {
        if (wallet.password_protected !== false) {
          $q
            .dialog({
              title: t("pages.wallet_select.index.open_wallet_password_title"),
              message: t("pages.wallet_select.index.open_wallet_password_message"),
              prompt: {
                model: "",
                type: "password"
              },
              ok: {
                label: t("pages.wallet_select.index.open_wallet_ok_label"),
                color: "positive"
              },
              cancel: {
                flat: true,
                label: t("pages.wallet_select.index.open_wallet_cancel_label"),
                color: theme.value === "dark" ? "white" : "dark"
              },
              transitionShow: "flip-up",
              transitionHide: "flip-down",
              dark: theme.value === "dark",
              color: "red"
            })
            .onOk((password) => {
              $q.loading.show({
                delay: 0
              })
              api.send("wallet", "open_wallet", {
                name: wallet.name,
                password
              })
            })
            .onCancel(() => {})
            .onDismiss(() => {})
        } else {
          $q.loading.show({
            delay: 0
          })
          api.send("wallet", "open_wallet", {
            name: wallet.name,
            password: ""
          })
        }
      } catch (error) {
        await api.error("pages/wallet-select/index", "openWallet", error.stack || error)
      }
    }

    const createNewWallet = async () => {
      try {
        router.push({ path: "/wallet-select/create" })
      } catch (error) {
        await api.error("pages/wallet-select/index", "createNewWallet", error.stack || error)
      }
    }

    const restoreWallet = async () => {
      try {
        router.push({ path: "/wallet-select/restore" })
      } catch (error) {
        await api.error("pages/wallet-select/index", "restorWallet", error.stack || error)
      }
    }

    const restoreViewWallet = async () => {
      try {
        router.push({ path: "/wallet-select/import-view-only" })
      } catch (error) {
        await api.error("pages/wallet-select/index", "restoreViewWallet", error.stack || error)
      }
    }

    const importWallet = async () => {
      try {
        router.push({ path: "/wallet-select/import" })
      } catch (error) {
        await api.error("pages/wallet-select/index", "importWallet", error.stack || error)
      }
    }

    const importOldGuiWallets = async () => {
      try {
        router.push({ path: "/wallet-select/import-old-gui" })
      } catch (error) {
        await api.error("pages/wallet-select/index", "importOldGuiWallets", error.stack || error)
      }
    }

    const importLegacyWallet = async () => {
      try {
        router.push({ path: "/wallet-select/import-legacy" })
      } catch (error) {
        await api.error("pages/wallet-select/index", "importLegacyWallet", error.stack || error)
      }
    }

    const copyAddress = async (address, event) => {
      try {
        event.stopPropagation()
        api.writeText(address)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: t("pages.wallet_select.index.copy_address_message")
        })
      } catch (error) {
        await api.error("pages/wallet-select/index", "copyAddress", error.stack || error)
      }
    }

    return {
      t,
      theme,
      wallets,
      status,
      actions,
      statusWatcher,
      openWallet,
      createNewWallet,
      restoreViewWallet,
      restoreWallet,
      importWallet,
      importOldGuiWallets,
      importLegacyWallet,
      copyAddress
    }
  }
})
</script>

<style lang="scss">
.header-popover.q-popover {
  max-width: 250px !important;
}
.wallet-list {
  .wallet-icon {
    font-size: 3rem;
  }

  .header {
    margin: 0 16px;
    margin-bottom: 8px;
    min-height: 36px;

    .header-title {
      font-size: 20px;
      font-weight: 500;
      margin-left: 71px;
    }

    .add {
      width: 38px;
      padding: 0;
    }
  }
  .wallet-name {
    font-size: 1.1rem;
  }
  .q-item {
    margin: 10px 16px;
    margin-bottom: 0px;
    padding: 14px;
    border-radius: 3px;
  }
  .context-menu {
    min-width: 150px;
    max-height: 300px;
    color: white;
  }
}
</style>
