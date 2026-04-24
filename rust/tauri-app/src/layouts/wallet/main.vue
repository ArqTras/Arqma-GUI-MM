<template>
  <q-layout view="hHh Lpr lFf">
    <q-header
      class="row justify-between items-center"
      style="border-bottom: 1px solid white"
    >
      <div class="col-2">
        <div
          class="menu q-focus-helper"
          style="
            margin-top: 5px;
            top: 0px;
            left: 0px;
            position: absolute;
            opacity: 1 !important;
            margin: 10px;
          "
        >
          <img
            src="arq_logo_with_padding.png"
            height="60"
          >
        </div>
      </div>
      <div class="col-8">
        <div class="column items-center">
          <div class="balance">
            <div
              v-if="price != 0"
              class="value"
              style="font-size: 30px"
            >
              $<span><Formatarqma
                :amount="info.balance * price"
                :digits="2"
              /></span>
              <q-btn
                class="large-btn"
                size="md"
                icon-right="refresh"
                align="between"
                @click="refresh_coin_price()"
              />
            </div>
            <div
              v-else
              class="value"
            >
              <span><Formatarqma :amount="info.balance" /> ARQ</span>
            </div>
          </div>
          <div
            v-if="price != 0"
            class="row unlocked"
          >
            <span><Formatarqma :amount="info.balance" /> ARQ</span>
          </div>
          <div
            v-if="info.balance != info.unlocked_balance"
            class="row unlocked"
          >
            <span>{{ $t('layouts.wallet.main.temporarily_locked') }}
              <Formatarqma :amount="Math.abs(info.balance - info.unlocked_balance)" />
              ARQ</span>
          </div>
        </div>
      </div>
      <MainMenu class="col-2 row items-center justify-end" />
    </q-header>

    <q-page-container>
      <!-- <AddressHeader :address="
        info.address"
        :title="info.name"
      /> -->
      <!--        <WalletDetails />-->
      <div
        class="app-content"
        style="margin-top: 15px"
      >
        <div class="navigation row justify-around">
          <router-link to="/wallet">
            <q-btn
              class="large-btn"
              :label="$t('layouts.wallet.main.transactions')"
              size="md"
              icon-right="swap_horiz"
              align="between"
            />
          </router-link>
          <router-link to="/wallet/send">
            <q-btn
              class="large-btn"
              :label="$t('layouts.wallet.main.send')"
              size="md"
              icon-right="arrow_right_alt"
              align="between"
            />
          </router-link>
          <router-link to="/wallet/receive">
            <q-btn
              class="large-btn"
              :label="$t('layouts.wallet.main.receive')"
              size="md"
              icon-right="save_alt"
              align="between"
            />
          </router-link>
          <!-- <router-link to="/wallet/swap">
            <q-btn
              class="large-btn"
              :label="$t('layouts.wallet.main.wxeq')"
              size="md"
              icon-right="swap_vert"
              align="between"
            />
          </router-link> -->
          <router-link to="/wallet/staking-pools">
            <q-btn
              class="large-btn"
              :label="$t('layouts.wallet.main.staking_pools')"
              size="md"
              icon-right="arrow_right_alt"
              align="between"
            />
          </router-link>
          <router-link to="/wallet/addressbook">
            <q-btn
              class="large-btn"
              :label="$t('layouts.wallet.main.address_book')"
              size="md"
              icon-right="person"
            />
          </router-link>
          <router-link to="/wallet/solo-pool">
            <q-btn
              class="large-btn"
              :label="$t('components.mainmenu.solo_pool')"
              size="md"
              icon-right="engineering"
              align="between"
            />
          </router-link>
          <div class="address">
            <WalletSettings />
          </div>
        </div>
        <div class="hr-separator" />
        <!-- <div
          style="max-height: 750px; overflow: auto"
          class="col"
        >
          <div
            :visible="false"
            class="fit column"
          >
            <router-view />
          </div>
        </div> -->
        <!-- <div style="height: 75vh;">
          <q-scroll-area
            :thumb-style="{
              right: '4px',
              borderRadius: '5px',
              backgroundColor: '#027be3',
              width: '8px',
              opacity: 0.75
            }"
            :bar-style="{
              right: '2px',
              borderRadius: '9px',
              backgroundColor: '#027be3',
              width: '12px',
              opacity: 0.2
            }"
            class="fit"
          >
            <router-view />
          </q-scroll-area>
        </div> -->
        <router-view />
      </div>
    </q-page-container>

    <StatusFooter />
  </q-layout>
</template>

<script>
import { defineComponent, ref, computed, onMounted, onBeforeUnmount } from "vue"
import { useQuasar } from "quasar"
import { useStore } from "vuex"
import Formatarqma from "components/format_arqma"
import WalletSettings from "components/wallet_settings"
import StatusFooter from "components/footer"
import MainMenu from "components/mainmenu"
import { useI18n } from "vue-i18n"
import { useDebounce } from "src/composables/debounce"
import { useRouter } from "vue-router"

export default defineComponent({
  name: "LayoutDefault",
  components: {
    StatusFooter,
    MainMenu,
    WalletSettings,
    Formatarqma
  },
  setup () {
    const $q = useQuasar()
    const $store = useStore()
    const { t } = useI18n()
    const { debounce } = useDebounce()
    const router = useRouter()

    const selectedTab = ref("tab-1")

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const info = computed(() => $store.state.gateway.wallet.info)
    const price = computed(() => $store.state.gateway.coin_price)
    // 1–30 = minutes; 31 = "∞" — no inactivity log-out when solo pool server is enabled; if solo is off, treat as 30 min.
    const soloPoolServerEnabled = computed(() => {
      return $store.state.gateway.app.config?.pool?.server?.enabled === true
    })
    const inactivityTimeoutMinutes = computed(() => {
      return $store.state.gateway.app.config.app.inactivityTimeout
    })
    const inactivityTimeoutMs = computed(() => {
      const m = inactivityTimeoutMinutes.value
      if (m === 31) {
        return soloPoolServerEnabled.value ? 0 : 30 * 60000
      }
      return m * 60000
    })
    const is_able_to_send = computed(() => {
      return $store.getters["gateway/isAbleToSend"]
    })
    const events = ["mousemove", "touchmove", "keypress"]
    let inactivityTimerFn = null
    let listenersAdded = false

    onMounted(async () => {
      try {
        api.send("wallet", "get_coin_price", {})
        if (!listenersAdded) {
          for (const event of events) {
            window.addEventListener(event, resetInactiveTimeoutFn)
          }
          listenersAdded = true
        }
        resetInactiveTimeoutFn()
      } catch (error) {
        await api.error("layouts/wallet/main", "onMounted", error.stack || error)
      }
    })

    onBeforeUnmount(() => {
      if (listenersAdded) {
        for (const event of events) {
          window.removeEventListener(event, resetInactiveTimeoutFn)
        }
        listenersAdded = false
      }
      if (inactivityTimerFn !== null) {
        clearTimeout(inactivityTimerFn)
        inactivityTimerFn = null
      }
    })

    // Methods
    $q.openURL

    const resetInactiveTimeoutFn = debounce(() => {
      if (inactivityTimerFn !== null) {
        clearTimeout(inactivityTimerFn)
        inactivityTimerFn = null
      }
      if (inactivityTimeoutMinutes.value === 31 && soloPoolServerEnabled.value) {
        return
      }
      inactivityTimerFn = setTimeout(() => {
        if (is_able_to_send.value) {
          clearTimeout(inactivityTimerFn)
          inactivityTimerFn = null
          switchWallet()
          $q.notify({
            type: "positive",
            timeout: 3000,
            message: t("layouts.wallet.main.wallet_inactivityMessage")
          })
        } else {
          resetInactiveTimeoutFn()
        }
      }, inactivityTimeoutMs.value)
    }, 300)

    const refresh_coin_price = async () => {
      try {
        api.send("wallet", "get_coin_price", {})
      } catch (error) {
        await api.error("layouts/wallet/main", "refresh_coin_price", error.stack || error)
      }
    }

    const switchWallet = async () => {
      await api.send("wallet", "close_wallet")
      router.push({ path: "/wallet-select" })
      setTimeout(() => {
        $store.dispatch("gateway/resetWalletData")
      }, 250)
    }

    return {
      t,
      refresh_coin_price,
      selectedTab,
      price,
      theme,
      info,
      StatusFooter,
      MainMenu,
      WalletSettings,
      Formatarqma,
      resetInactiveTimeoutFn,
      switchWallet
    }
  }
})
</script>

<style lang="scss">
.navigation {
  padding: 8px 12px;

  > * {
    margin: 2px 0;
    margin-right: 12px;
  }

  > *:last-child {
    margin-right: 0px;
  }

  .address {
    margin-left: auto;
  }

  .single-icon {
    width: 38px;
    padding: 0;
  }

  a {
    text-decoration: none;
  }
}
</style>
