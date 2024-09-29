<template>
  <div class="row items-center">
    <q-btn
      class="menu"
      icon="menu"
      size="lg"
      flat
    >
      <q-menu
        transition-show="flip-up"
        transition-hide="flip-down"
      >
        <q-list
          separator
          class="menu-list"
        >
          <q-item
            v-if="!disableSwitchWallet"
            v-close-popup
            clickable
            @click="switchWallet"
          >
            <q-item-label header>
              {{ $t("components.mainmenu.switch_account") }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            @click="openSettings"
          >
            <q-item-label header>
              {{ $t("components.mainmenu.daemon_settings") }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            @click="showAbout(true)"
          >
            <q-item-label header>
              {{ $t("components.mainmenu.about") }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            @click="exit"
          >
            <q-item-label header>
              {{ $t("components.mainmenu.exit_wallet") }}
            </q-item-label>
          </q-item>
        </q-list>
      </q-menu>
    </q-btn>
    <settings-modal ref="settingsModal" />
    <q-dialog
      ref="aboutModal"
      minimized
      transition-show="flip-up"
      transition-hide="flip-down"
    >
      <div
        class="about-modal"
        align="center"
      >
        <img
          class="q-mb-md"
          src="arq_logo_with_padding.png"
          width="75"
          height="75"
        >

        <p class="q-my-sm">
          Version: {{ version }}
        </p>
        <p class="q-my-sm">
          {{ daemonVersion }}
        </p>
        <p class="q-my-sm">
          Copyright (c) 2018-2024, Arqma Project
        </p>
        <p class="q-my-sm">
          Copyright (c) 2018-2019, Loki Project
        </p>
        <p class="q-my-sm">
          Copyright (c) 2018, Ryo Currency Project
        </p>
        <p class="q-my-sm">
          All rights reserved.
        </p>

        <div class="q-mt-md q-mb-lg external-links">
          <p>
            <a
              href="#"
              @click="openExternal('https://arqma.com/')"
            >https://arqma.com/</a>
          </p>
          <p>
            <a
              href="#"
              @click="openExternal('https://chat.arqma.com')"
            >Discord</a>
            -
            <a
              href="#"
              @click="openExternal('https://telegram.arqma.com')"
            >Telegram</a>
            -
            <a
              href="#"
              @click="
                openExternal('https://github.com/Arqma/Arqma')
              "
            >Github</a>
          </p>
        </div>

        <q-btn
          color="positive"
          label="Close"
          @click="showAbout(false)"
        />
      </div>
    </q-dialog>
  </div>
</template>

<script>
import { computed, defineComponent, inject, onMounted, ref, watch } from "vue"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import { useRouter } from "vue-router"
import SettingsModal from "components/settings"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "MainMenu",
  components: {
    SettingsModal
  },
  props: {
    disableSwitchWallet: {
      type: Boolean,
      required: false,
      default: false
    }
  },
  setup (props) {
    const $store = useStore()
    const $q = useQuasar()
    const router = useRouter()
    const { t } = useI18n()

    const version = ref("")
    const aboutModal = ref(null)
    const settingsModal = ref(null)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const daemonVersion = computed(() => $store.state.gateway.daemon_version)

    // Watchers

    onMounted(async () => {
      version.value = await api.version()
      await api.daemonVersion()
    })

    // Methods
    const openExternal = async (url) => {
      try {
        await api.send("core", "open_url", { url })
      } catch (error) {
        await api.error("components/mainmenu", "openExternal", error.stack || error)
      }
    }

    const showAbout = async (toggle) => {
      try {
        if (toggle) {
          aboutModal.value.show()
        } else {
          aboutModal.value.hide()
        }
      } catch (error) {
        await api.error("components/mainmenu", "showAbout", error.stack || error)
      }
    }

    const openSettings = async () => {
      try {
        settingsModal.value.isVisible = true
      } catch (error) {
        await api.error("components/mainmenu", "openSettings", error.stack || error)
      }
    }

    const switchWallet = async () => {
      try {
        $q
          .dialog({
            title: t("components.mainmenu.switch_account"),
            message: t("components.mainmenu.confirm_close"),
            ok: {
              label: t("components.mainmenu.switch_account_ok_label"),
              color: "positive"
            },
            cancel: {
              flat: true,
              label: t("components.mainmenu.switch_account_cancel_label"),
              color: "red"
            },
            transitionShow: "flip-up",
            transitionHide: "flip-down",
            style: "min-width: 500px; overflow-wrap: break-word;",
            dark: theme.value === "dark"
          })
          .onOk(() => {
            router.push({ path: "/wallet-select" })
            api.send("wallet", "close_wallet")
            setTimeout(() => {
              // short delay to prevent wallet data reaching the
              // websocket moments after we close and reset data
              $store.dispatch("gateway/resetWalletData")
            }, 250)
          })
          .onCancel(() => {})
          .onDismiss(() => {})
      } catch (error) {
        await api.error("components/mainmenu", "switchWallet", error.stack || error)
      }
    }

    const gateway = inject("gateway")

    const exit = async () => {
      try {
        gateway.confirmClose(t("components.mainmenu.confirm_close"))
      } catch (error) {
        await api.error("components/mainmenu", "exit", error.stack || error)
      }
    }

    return {
      t,
      version,
      daemonVersion,
      aboutModal,
      settingsModal,
      theme,
      openExternal,
      showAbout,
      openSettings,
      switchWallet,
      exit,
      SettingsModal,
      gateway
    }
  }
})
</script>

<style lang="scss">
.about-modal {
  padding: 25px;
  background-color: $dark;
//   color: navy;
  color: white;

  .external-links {
    a {
      color: #497dc6;
      text-decoration: none;

      &:hover,
      &:active,
      &:visited {
        text-decoration: underline;
      }
    }
  }
}
</style>
