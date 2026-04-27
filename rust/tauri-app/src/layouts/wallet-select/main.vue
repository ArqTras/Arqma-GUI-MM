<template>
  <q-layout view="hHh Lpr lFf">
    <q-header class="row justify-between items-center">
      <q-toolbar>
        <template v-if="show_menu">
          <MainMenu :disable-switch-wallet="true" />
        </template>
        <template v-else>
          <q-btn
            class="cancel"
            icon="reply"
            flat
            round
            dense
            @click="cancel()"
          />
        </template>
        <q-toolbar-title
          v-if="page_title == 'Arqma'"
          class="flex items-center justify-center"
        >
          <img
            src="arq_logo_with_padding.png"
            height="60"
          >
        </q-toolbar-title>
        <q-toolbar-title
          v-else
          class="flex items-center justify-center"
        >
          {{ page_title }}
        </q-toolbar-title>
      </q-toolbar>
    </q-header>

    <q-page-container>
      <router-view ref="page" />
    </q-page-container>

    <StatusFooter />
  </q-layout>
</template>

<script>
import { computed, defineComponent } from "vue"
import StatusFooter from "components/footer"
import MainMenu from "components/mainmenu"
import { useRoute, useRouter } from "vue-router"
import { useStore } from "vuex"
import { useI18n } from "vue-i18n"
import { useQuasar } from "quasar"

export default defineComponent({
  components: {
    StatusFooter,
    MainMenu
  },
  setup () {
    const route = useRoute()
    const router = useRouter()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    // Computed props
    const show_menu = computed(() => {
      return route.name === "wallet-select"
    })

    const page_title = computed(() => {
      let title = ""
      switch (route.name) {
        case "wallet-create":
          title = t("layouts.wallet_select.main.wallet_create")
          break
        case "wallet-restore":
          title = t("layouts.wallet_select.main.wallet_restore")
          break
        case "wallet-import":
          title = t("layouts.wallet_select.main.wallet_import")
          break
        case "wallet-import-view-only":
          title = t("layouts.wallet_select.main.wallet_import_view_only")
          break
        case "wallet-import-legacy":
          title = t("layouts.wallet_select.main.wallet_import_legacy")
          break
        case "wallet-import-old-gui":
          title = t("layouts.wallet_select.main.wallet_import_old_gui")
          break
        case "wallet-created":
          title = t("layouts.wallet_select.main.wallet_created")
          break
        case "wallet-select":
          title = t("layouts.wallet_select.main.wallet_select")
          break
        default:
      }
      return title
    })

    // Methods
    const cancel = async () => {
      $q.loading.show({
        delay: 0,
        message: t("components.mainmenu.closing_wallet")
      })
      try {
        await api.send("wallet", "close_wallet")
        router.push({ path: "/wallet-select" })
        setTimeout(() => {
          $store.dispatch("gateway/resetWalletData")
        }, 250)
      } finally {
        $q.loading.hide()
      }
    }

    return {
      t,
      show_menu,
      page_title,
      cancel,
      StatusFooter,
      MainMenu
    }
  }
})
</script>

<style></style>
