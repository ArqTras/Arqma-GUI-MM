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
            {{ $t("components.footer.daemon") }}: {{ daemon.info.height_without_bootstrap }} /
            {{ target_height }} ({{ daemon_local_pct }}%)
          </div>
        </template>

        <template v-if="config_daemon.type !== 'local'">
          <div>{{ $t("components.footer.remote") }}: {{ daemon.info.height }}</div>
        </template>

        <div>
          {{ $t("components.footer.wallet") }}: {{ walletHeight }} / {{ target_height }} ({{
            wallet_pct
          }}%)
        </div>
      </div>
    </div>
    <div
      class="status-bars"
      :class="[status]"
    >
      <div :style="{ width: daemon_pct + '%' }" />
      <div :style="{ width: wallet_pct + '%' }" />
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
      { value: "pt-BR", label: "Português (Brasil)" } // Added Brazilian Portuguese
    ]

    const selectedLocale = computed(() => localeOptions.find(c => c.value === locale.value))

    // Computed props
    const config = computed(() => $store.state.gateway.app.config)
    const daemon = computed(() => $store.state.gateway.daemon)
    const walletHeight = computed(() => $store.state.gateway.wallet.info.height)
    const config_daemon = computed(() => {
      if (config.value.app && config.value.app.net_type) {
        return config.value.daemons[config.value.app.net_type]
      }
      return { type: "local" }
    })
    const target_height = computed(() => {
      if (config_daemon.value.type === "local") {
        return Math.max(
          daemon.value.info.height,
          daemon.value.info.target_height
        )
      } else {
        return daemon.value.info.height
      }
    })

    const daemon_pct = computed(() => {
      if (config_daemon.value.type === "local") {
        return daemon_local_pct.value
      }
      return 0
    })

    const daemon_local_pct = computed(() => {
      if (config_daemon.value.type === "remote") {
        return 0
      }
      if (!target_height.value) {
        return 0
      }
      const pct = (100 * daemon.value.info.height_without_bootstrap) / target_height.value
      if (
        pct >= 100 &&
        daemon.value.info.height_without_bootstrap < target_height.value
      ) {
        return 99.9
      } else {
        return Math.max(0, Math.min(Number(pct.toFixed(1)), 100))
      }
    })

    const wallet_pct = computed(() => {
      if (target_height.value && walletHeight.value) {
        const pct = (100 * walletHeight.value) / target_height.value
        // If walletHeight is less than target but pct rounds to 100, show 99.9
        if (
          walletHeight.value < target_height.value &&
          Math.round(pct * 10) / 10 >= 100
        ) {
          return 99.9
        }
        return Math.min(Number(pct.toFixed(1)), 100)
      }
      return 0
    })

    const status = computed(() => {
      let result = ""
      if (!target_height.value) {
        return result
      }
      if (config_daemon.value.type === "local") {
        if (daemon.value.info.height_without_bootstrap < target_height.value) {
          result = t("components.footer.syncing")
        } else if (
          walletHeight.value < target_height.value - 1 &&
          walletHeight.value !== 0
        ) {
          result = t("components.footer.scanning")
        } else {
          result = t("components.footer.ready")
        }
      } else {
        if (
          walletHeight.value < target_height.value - 1 &&
          walletHeight.value !== 0
        ) {
          result = t("components.footer.scanning")
        } else if (
          config_daemon.value.type === "local_remote" &&
          daemon.value.info.height_without_bootstrap < target_height.value
        ) {
          result = t("components.footer.syncing")
        } else {
          result = t("components.footer.ready")
        }
      }
      return result ? result.toUpperCase() : ""
    })

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
      selectedLocale,
      locale,
      localeOptions,
      changeLocale,
      version,
      config,
      daemon,
      walletHeight,
      config_daemon,
      target_height,
      daemon_pct,
      daemon_local_pct,
      wallet_pct,
      status
    }
  }
})
</script>

<style lang="scss"></style>
