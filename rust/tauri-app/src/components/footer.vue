<template>
  <q-footer class="status-footer">
    <div class="status-line row items-center">
      <div class="status row items-center">
        <span>{{ $t("components.footer.status") }}:</span>
        <span
          class="status-text"
          :class="[status]"
        >{{
          status
        }}</span>
      </div>
      <div class="status row items-center">
        {{ $t("components.footer.version") }} {{ version }}
      </div>
      <div class="status row items-center cursor-pointer">
        <q-icon
          name="language"
          color="positive"
          size="24px"
          class="cursor-pointer"
          style="padding-right:8px;"
        />
        {{ $t("components.footer.language") }}: {{ selectedLocale.label }}
        <q-menu
          anchor="top middle"
          self="top middle"
        >
          <q-list>
            <q-item
              v-for="localeOption in localeOptions"
              :key="localeOption"
              dense
              clickable
              @click="changeLocale(localeOption)"
            >
              <q-item-section v-close-popup>
                {{ localeOption.label }}
              </q-item-section>
            </q-item>
          </q-list>
        </q-menu>
      </div>
      <div class="row">
        <template v-if="config_daemon.type !== 'remote'">
          <div>
            {{ $t("components.footer.daemon") }}: {{ daemonHeightDisplay }} /
            {{ target_height }} ({{ daemon_local_pct }}%)
          </div>
        </template>

        <template v-if="config_daemon.type !== 'local'">
          <div>{{ $t("components.footer.remote") }}: {{ remote_daemon_height }}</div>
        </template>

        <div>
          {{ $t("components.footer.wallet") }}: {{ walletHeightDisplay }} / {{ target_height }} ({{
            wallet_pct
          }}%)
          <span
            v-if="wallet_blocks_left > 0"
            class="text-grey-5 q-ml-sm"
          >· {{ $t("components.footer.blocks_left", { n: walletBlocksLeftFormatted }) }}</span>
        </div>
      </div>
    </div>
    <!-- Shown only while catching up: daemon bar (top) + wallet bar (bottom), gold like Apply / positive. -->
    <div
      v-if="showProgressBars"
      class="status-bars-dual"
      :class="[status]"
    >
      <div
        v-if="config_daemon.type !== 'remote'"
        class="bar-track"
        :title="`${$t('components.footer.daemon')}: ${daemon_local_pct}%`"
      >
        <div
          class="bar-fill bar-fill--daemon"
          :style="{ width: daemon_bar_pct + '%' }"
        />
      </div>
      <div
        class="bar-track"
        :title="`${$t('components.footer.wallet')}: ${wallet_pct}%`"
      >
        <div
          class="bar-fill bar-fill--wallet"
          :style="{ width: wallet_bar_pct + '%' }"
        />
      </div>
    </div>
  </q-footer>
</template>

<script>
import { computed, defineComponent, onMounted, ref, inject } from "vue"
import { useStore } from "vuex"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "StatusFooter",
  setup () {
    const $store = useStore()
    const { locale, t } = useI18n()

    const gateway = inject("gateway")
    const version = ref("")
    const localeOptions = [{ value: "en-US", label: "English" },
      { value: "de-DE", label: "Deutsch" },
      { value: "fr-FR", label: "Français" },
      { value: "ua-UA", label: "українська" },
      { value: "pl-PL", label: "Polski" },
      { value: "es-ES", label: "Spanish" },
      { value: "cn-CN", label: "中國人" }, // Added Chinese
      { value: "jp-JP", label: "日本語" }, // Added Japanese
      { value: "ms-MY", label: "Bahasa Melayu" }, // Added Malay
      { value: "ar-SA", label: "العربية" }, // Added Arabic
      { value: "pt-BR", label: "Português (Brasil)" }, // Added Brazilian Portuguese
      { value: "ru-RU", label: "Русский" } // Added Russian
    ]

    const selectedLocale = computed(() => localeOptions.find(c => c.value === locale.value))

    // Computed props
    const config = computed(() => $store.state.gateway.app.config)
    const daemon = computed(() => $store.state.gateway.daemon)
    const walletHeight = computed(() => Number($store.state.gateway.wallet?.info?.height) || 0)
    const config_daemon = computed(() => {
      if (config.value.app && config.value.app.net_type) {
        return config.value.daemons[config.value.app.net_type]
      }
      return { type: "local" }
    })
    const target_height = computed(() => {
      const info = daemon.value?.info
      if (!info) return 0
      const h = Number(info.height) || 0
      const th = Number(info.target_height) || 0
      return Math.max(h, th)
    })

    const daemon_pct = computed(() => {
      const t = config_daemon.value.type
      if (t === "local" || t === "local_remote") {
        return daemon_local_pct.value
      }
      return 0
    })

    const daemonHeightDisplay = computed(() => {
      const info = daemon.value?.info
      if (!info) return 0
      if (!target_height.value) {
        return Number(info.height_without_bootstrap) || 0
      }
      const d = Number(info.height_without_bootstrap) || 0
      return Math.min(d, Number(target_height.value))
    })

    const daemon_local_pct = computed(() => {
      if (config_daemon.value.type === "remote") {
        return 0
      }
      if (!target_height.value) {
        return 0
      }
      const dwo = Number(daemon.value?.info?.height_without_bootstrap) || 0
      const target = Number(target_height.value)
      const pct = (100 * dwo) / target
      if (dwo < target && Math.round(pct * 10) / 10 >= 100) {
        return 99.9
      }
      const decimals = pct >= 100 ? 1 : 2
      return Math.max(0, Math.min(Number(pct.toFixed(decimals)), 100))
    })

    const wallet_pct = computed(() => {
      if (!target_height.value) return 0
      const wh = Number(walletHeight.value) || 0
      const target = Number(target_height.value)
      const pct = (100 * wh) / target
      if (pct >= 100) {
        return Math.min(Number(pct.toFixed(1)), 100)
      }
      // Near the tip, 2 decimals look “frozen” (e.g. 99.97 → 99.98); show 3 until fully caught up.
      if (wh < target && pct >= 99) {
        return Math.min(Number(pct.toFixed(3)), 100)
      }
      return Math.min(Number(pct.toFixed(2)), 100)
    })

    const bar_pctWithFloor = (pct) => {
      const p = Number(pct) || 0
      if (p <= 0) {
        return 0
      }
      if (p >= 100) {
        return 100
      }
      return Math.max(p, 1)
    }
    const wallet_bar_pct = computed(() => bar_pctWithFloor(wallet_pct.value))
    const daemon_bar_pct = computed(() => bar_pctWithFloor(daemon_pct.value))

    const wallet_blocks_left = computed(() => {
      if (!target_height.value) {
        return 0
      }
      const t = Number(target_height.value) || 0
      const wh = Number(walletHeight.value) || 0
      return Math.max(0, t - wh)
    })

    const walletBlocksLeftFormatted = computed(() => {
      const n = wallet_blocks_left.value
      if (n <= 0) {
        return "0"
      }
      return n.toLocaleString(undefined, { maximumFractionDigits: 0 })
    })

    const showProgressBars = computed(() => {
      if (!target_height.value) {
        return false
      }
      const t = Number(target_height.value)
      const wh = Number(walletHeight.value) || 0
      if (config_daemon.value.type === "remote") {
        return wh < t
      }
      const dwo = Number(daemon.value?.info?.height_without_bootstrap) || 0
      return dwo < t || wh < t
    })

    const status = computed(() => {
      let result = ""
      if (!target_height.value) {
        return result
      }
      const wh = Number(walletHeight.value) || 0
      const target = Number(target_height.value)
      const walletBehind = wh < target
      if (config_daemon.value.type === "local") {
        if ((Number(daemon.value?.info?.height_without_bootstrap) || 0) < target) {
          result = t("components.footer.syncing")
        } else if (walletBehind) {
          result = t("components.footer.scanning")
        } else {
          result = t("components.footer.ready")
        }
      } else {
        if (walletBehind) {
          result = t("components.footer.scanning")
        } else if (
          config_daemon.value.type === "local_remote" &&
          (Number(daemon.value?.info?.height_without_bootstrap) || 0) < target
        ) {
          result = t("components.footer.syncing")
        } else {
          result = t("components.footer.ready")
        }
      }
      return result ? result.toUpperCase() : ""
    })

    const walletHeightDisplay = computed(() => {
      const wh = Number(walletHeight.value) || 0
      const t = Number(target_height.value) || 0
      if (!t) return wh
      return Math.min(wh, t)
    })

    const remote_daemon_height = computed(() => Number(daemon.value?.info?.height) || 0)

    onMounted(async () => {
      version.value = await api.version()
    })

    const changeLocale = async (newLocale) => {
      try {
        await gateway.setLanguage(newLocale.value)
        locale.value = newLocale.value
      } catch (error) {
        await api.error("components/footer", "changeLocale", error.stack || error)
      }
    }

    return {
      t,
      walletHeightDisplay,
      daemonHeightDisplay,
      selectedLocale,
      locale,
      localeOptions,
      changeLocale,
      version,
      config,
      daemon,
      remote_daemon_height,
      walletHeight,
      config_daemon,
      target_height,
      daemon_pct,
      daemon_local_pct,
      wallet_pct,
      wallet_bar_pct,
      daemon_bar_pct,
      wallet_blocks_left,
      walletBlocksLeftFormatted,
      showProgressBars,
      status
    }
  }
})
</script>

<style lang="scss">
/* Quasar footer can clip absolute-positioned children; leave room for the bars. */
.q-footer.status-footer {
  overflow: visible;
  padding-bottom: 2px;
}

/*
 * Footer sync bars must stay gold (theme / Quasar "positive" must not recolor to green/teal).
 * Literal hex + !important so nothing overrides the fill.
 */
.q-footer.status-footer .status-bars-dual {
  .bar-fill--daemon {
    background: linear-gradient(90deg, #7a6228 0%, #a89050 40%, #c9a85a 100%) !important;
    background-color: #9a7d3a !important;
    box-shadow: 0 0 8px rgba(180, 140, 60, 0.45) !important;
  }

  .bar-fill--wallet {
    background: linear-gradient(90deg, #8a6e30 0%, #b89848 40%, #ddc878 100%) !important;
    background-color: #a68438 !important;
    box-shadow: 0 0 8px rgba(200, 165, 80, 0.5) !important;
  }
}
</style>
