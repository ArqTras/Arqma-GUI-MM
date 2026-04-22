<template>
  <div class="settings-general">
    <template v-if="config_daemon.type != 'remote'">
      <div class="row pl-sm">
        <arqmaField
          class="col-8"
          :label="$t('components.general_settings.local_daemon_ip')"
          disable
        >
          <q-input
            v-model="config_daemon.rpc_bind_ip"
            :dark="theme == 'dark'"
            disable
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-4"
          :label="$t('components.general_settings.local_daemon_port')"
        >
          <q-input
            v-model="config_daemon.rpc_bind_port"
            type="number"
            :decimals="0"
            :step="1"
            min="1024"
            max="65535"
            :dark="theme == 'dark'"
            borderless
            dense
          />
        </arqmaField>
      </div>
    </template>

    <template v-if="config_daemon.type != 'local'">
      <div class="row q-mt-md pl-sm">
        <arqmaField
          class="col-8"
          :label="$t('components.general_settings.remote_node_host')"
          :disable-menu="false"
        >
          <q-input
            v-model="config_daemon.remote_host"
            placeholder="daemon_defaults.remote_host"
            :dark="theme == 'dark'"
            borderless
            dense
          />
          <q-btn-dropdown
            class="remote-dropdown"
            flat
            transition-show="flip-up"
            transition-hide="flip-down"
          >
            <q-list
              link
              dark
              no-border
            >
              <q-item
                v-for="option in remotes"
                :key="option.host"
                v-close-popup
                clickable
                @click="setPreset(option)"
              >
                <q-item-label>
                  <q-item-label header>
                    {{ option.host }}:{{ option.port }}
                  </q-item-label>
                </q-item-label>
              </q-item>
            </q-list>
          </q-btn-dropdown>
        </arqmaField>
        <arqmaField
          class="col-4"
          :label="$t('components.general_settings.remote_node_port')"
          :disable-menu="false"
        >
          <q-input
            v-model="config_daemon.remote_port"
            type="number"
            :decimals="0"
            :step="1"
            min="1024"
            max="65535"
            :dark="theme == 'dark'"
            borderless
            dense
          />
        </arqmaField>
      </div>
      <div class="row justify-start align-center">
        <q-item-section>
          {{ $t('components.general_settings.warning') }}
        </q-item-section>
      </div>
      <div class="row justify-start align-center">
        <q-btn
          class="remote_node_buttons"
          :label="$t('components.general_settings.remove_node')"
          color="negative"
          @click="removeRemote()"
        />

        <q-btn
          class="remote_node_buttons"
          :label="$t('components.general_settings.add_node')"
          color="positive"
          @click="addRemote()"
        />
      </div>
    </template>

    <div class="row justify-start align-center">
      <template v-if="config_daemon.type != 'local'">
        <arqmaField
          :helper="$t('components.general_settings.remote_node_scan_helper')"
          :label="$t('components.general_settings.remote_node_scan')"
          class="network-group-field col-auto"
        >
          <q-option-group
            v-model="pending_config.app.scan"
            :options="remoteScanOptions"
            inline
          />
        </arqmaField>
      </template>

      <arqmaField
        :helper="$t('components.general_settings.prompt_for_password')"
        :label="$t('components.general_settings.prompt_for_password')"
        class="network-group-field col-auto"
      >
        <q-option-group
          v-model="pending_config.app.promptForPassword"
          :options="promptForPasswordOptions"
          inline
        />
      </arqmaField>
      <arqmaField
        :helper="$t('components.general_settings.debug_log_levels')"
        :label="$t('components.general_settings.debug_log_levels')"
        class="network-group-field col-auto"
      >
        <q-option-group
          v-model="pending_config.app.loggingLevel"
          :options="loggingLevels"
          inline
        />
      </arqmaField>
      <arqmaField
        :helper="$t('components.general_settings.transactions_to_display')"
        :label="$t('components.general_settings.transactions_to_display')"
        class="network-group-field col-auto"
      >
        <q-slider
          v-model="pending_config.app.daysOfTransactions"
          :min="1"
          :max="30"
          color="positive"
          label
          label-always
          :label-value="`${pending_config.app.daysOfTransactions}${t('components.general_settings.days')}`"
          switch-label-side
        />
      </arqmaField>
      <arqmaField
        :helper="$t('components.general_settings.inactivity_timeout')"
        :label="$t('components.general_settings.inactivity_timeout')"
        class="network-group-field col-auto"
      >
        <q-slider
          v-model="pending_config.app.inactivityTimeout"
          :min="1"
          :max="30"
          color="positive"
          label
          label-always
          :label-value="`${pending_config.app.inactivityTimeout}${t('components.general_settings.minutes')}`"
          switch-label-side
        />
      </arqmaField>
    </div>
    <q-expansion-item
      :label="$t('components.general_settings.advanced_options')"
      header-class="q-mt-sm non-selectable row reverse advanced-options-label"
    >
      <div class="row justify-between q-mb-md">
        <div>
          <q-radio
            v-model="config_daemon.type"
            val="remote"
            :label="$t('components.general_settings.remote_daemon_only')"
          />
        </div>
        <div>
          <q-radio
            v-model="config_daemon.type"
            val="local_remote"
            :label="$t('components.general_settings.local_and_remote_daemon')"
          />
        </div>
        <div>
          <q-radio
            v-model="config_daemon.type"
            val="local"
            :label="$t('components.general_settings.local_daemon_only')"
          />
        </div>
      </div>

      <p v-if="config_daemon.type == 'local_remote'">
        {{ $t('components.general_settings.local_remote_message') }}
      </p>
      <p v-if="config_daemon.type == 'local'">
        {{ $t('components.general_settings.local_message') }}
      </p>
      <p v-if="is_remote">
        {{ $t('components.general_settings.remote_message') }}
      </p>
      <div class="col q-mt-md pt-sm">
        <arqmaField
          :label="$t('components.general_settings.data_storage_path')"
          disable-hover
        >
          <q-input
            v-model="pending_config.app.data_dir"
            disable
            :dark="theme == 'dark'"
            borderless
            dense
          />
          <q-btn
            color="positive"
            :text-color="theme == 'dark' ? 'white' : 'dark'"
            @click="setDataPath()"
          >
            {{ $t('components.general_settings.select_location') }}
          </q-btn>
        </arqmaField>
        <arqmaField
          :label="$t('components.general_settings.wallet_storage_path')"
          disable-hover
        >
          <q-input
            v-model="pending_config.app.wallet_data_dir"
            disable
            :dark="theme == 'dark'"
            borderless
            dense
          />
          <q-btn
            color="positive"
            :text-color="theme == 'dark' ? 'white' : 'dark'"
            :label="$t('components.general_settings.select_location')"
            @click="setWalletDataPath()"
          />
        </arqmaField>
      </div>
      <div class="row pl-sm q-mt-sm">
        <arqmaField
          class="col-6"
          :label="$t('components.general_settings.daemon_log_level')"
          :disable="is_remote"
        >
          <q-input
            v-model="config_daemon.log_level"
            :disable="is_remote"
            :dark="theme == 'dark'"
            type="number"
            :decimals="0"
            :step="1"
            min="0"
            max="4"
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-6"
          :label="$t('components.general_settings.wallet_log_level')"
        >
          <q-input
            v-model="pending_config.wallet.log_level"
            :dark="theme == 'dark'"
            type="number"
            :decimals="0"
            :step="1"
            min="0"
            max="4"
            borderless
            dense
          />
        </arqmaField>
      </div>

      <div class="row pl-sm q-mt-md">
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.max_incoming_peers')"
          :disable="is_remote"
        >
          <q-input
            v-model="config_daemon.in_peers"
            :disable="is_remote"
            :dark="theme == 'dark'"
            type="number"
            :decimals="0"
            :step="1"
            min="-1"
            max="65535"
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.max_outgoing_peers')"
          :disable="is_remote"
        >
          <q-input
            v-model="config_daemon.out_peers"
            :disable="is_remote"
            :dark="theme == 'dark'"
            type="number"
            :decimals="0"
            :step="1"
            min="-1"
            max="65535"
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.limit_upload_rate')"
          :disable="is_remote"
        >
          <q-input
            v-model="config_daemon.limit_rate_up"
            :disable="is_remote"
            :dark="theme == 'dark'"
            type="number"
            suffix="Kb/s"
            :decimals="0"
            :step="1"
            min="-1"
            max="65535"
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.limit_download_rate')"
          :disable="is_remote"
        >
          <q-input
            v-model="config_daemon.limit_rate_down"
            :disable="is_remote"
            :dark="theme == 'dark'"
            type="number"
            suffix="Kb/s"
            :decimals="0"
            :step="1"
            min="-1"
            max="65535"
            dense
          />
        </arqmaField>
      </div>
      <div class="row pl-sm q-mt-md">
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.daemon_p2p_port')"
          :disable="is_remote"
        >
          <q-input
            v-model="config_daemon.p2p_bind_port"
            :disable="is_remote"
            :dark="theme == 'dark'"
            float-
            type="number"
            :decimals="0"
            :step="1"
            min="1024"
            max="65535"
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.daemon_zmq_port')"
          :disable="is_remote"
        >
          <q-input
            v-model="config_daemon.zmq_rpc_bind_port"
            :disable="is_remote"
            :dark="theme == 'dark'"
            float-
            type="number"
            :decimals="0"
            :step="1"
            min="1024"
            max="65535"
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.internal_wallet_port')"
        >
          <q-input
            v-model="pending_config.app.ws_bind_port"
            :dark="theme == 'dark'"
            float-
            type="number"
            :decimals="0"
            :step="1"
            min="1024"
            max="65535"
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-3"
          :label="$t('components.general_settings.wallet_rpc_port')"
          :disable="is_remote"
        >
          <q-input
            v-model="pending_config.wallet.rpc_bind_port"
            :disable="is_remote"
            :dark="theme == 'dark'"
            type="number"
            :decimals="0"
            :step="1"
            min="1024"
            max="65535"
            dense
          />
        </arqmaField>
      </div>
      <arqmaField
        :helper="$t('components.general_settings.choose_a_network_helper')"
        :label="$t('components.general_settings.choose_a_network')"
        class="network-group-field"
      >
        <q-option-group
          v-model="pending_config.app.net_type"
          :options="networkOptions"
          inline
        />
      </arqmaField>
    </q-expansion-item>
    <!-- <q-expansion-item
      v-if="isDevelopment"
      :label="$t('components.general_settings.advanced_swap_options')"
      header-class="q-mt-sm non-selectable row reverse advanced-options-label"
    >
      <div class="row justify-between q-mb-md">
        <div>
          <q-radio
            v-model="ethereum_network_index"
            val="0"
            :label="$t('components.general_settings.network_mainnet')"
          />
        </div>
        <div>
          <q-radio
            v-model="ethereum_network_index"
            val="1"
            :label="$t('components.general_settings.network_testnet')"
          />
        </div>
      </div>
      <div
        v-for="network in ethereum_network"
        :key="network.id"
        class="row pl-sm q-mt-sm"
      >
        <arqmaField
          class="col-6"
          :label="`${network.network.toUpperCase()} ${$t('components.general_settings.token_address')}`"
        >
          <q-input
            v-model="network.token_address"
            :dark="theme == 'dark'"
            placeholder="0x..."
            type="text"
            borderless
            dense
          />
        </arqmaField>
        <arqmaField
          class="col-6"
          :label="`${network.network.toUpperCase()} ${$t('components.general_settings.bridge_address')}`"
        >
          <q-input
            v-model="network.bridge_address"
            :dark="theme == 'dark'"
            placeholder="0x..."
            type="text"
            borderless
            dense
          />
        </arqmaField>
      </div>
    </q-expansion-item> -->
  </div>
</template>

<script>
import { computed, defineComponent, onMounted, onBeforeMount, ref, watch, toRefs } from "vue"
import arqmaField from "components/arqma_field"
import { useStore } from "vuex"
import { extend } from "quasar"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "SettingsGeneral",
  components: {
    arqmaField
  },
  setup () {
    const $store = useStore()
    const { t } = useI18n()

    const select = ref(0)
    const remotes = ref([])
    const isDevelopment = ref(false)

    const remoteScanOptions = [{ label: t("components.general_settings.enabled"), value: true }, { label: t("components.general_settings.disabled"), value: false }]
    const promptForPasswordOptions = [{ label: t("components.general_settings.always"), value: true }, { label: t("components.general_settings.never"), value: false }]
    const networkOptions = [{ label: "Main Net", value: "mainnet" }, { label: "Stage Net", value: "stagenet" }, { label: "Test Net", value: "testnet" }]
    const loggingLevels = [{ label: "error", value: "error" }, { label: "Info", value: "info" }]
    const pending_config = ref({})
    const defaults = ref({})

    const ethereum_network_index = ref("0")
    const ethereum_config = ref({})

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const config_daemon = computed(() => {
      return pending_config.value.daemons[pending_config.value.app.net_type]
    })
    const is_remote = computed(() => {
      return config_daemon.value.type === "remote"
    })
    const daemon_defaults = computed(() => {
      return defaults.value.daemons[pending_config.value.app.net_type]
    })
    const notifier = computed(() => $store.state.gateway.notifier)

    const notifierWatcher = watch(notifier, (newVal, oldVal) => {
      if (newVal.save) { save(newVal) }
    })
    const ethereum_network = computed(() => {
      return ethereum_config.value.networks[ethereum_network_index.value]
    })

    onBeforeMount(async () => {
      try {
        // NOTE: config_daemon and is_remote derive their values from this copy of the store values
        pending_config.value = extend(true, {}, $store.state.gateway.app.pending_config)
        if (pending_config.value.app.promptForPassword === undefined) { pending_config.value.app.promptForPassword = true }
        if (pending_config.value.app.loggingLevel === undefined) { pending_config.value.app.loggingLevel = "error" }
        if (pending_config.value.app.daysOfTransactions === undefined) { pending_config.value.app.daysOfTransactions = 1 }
        if (pending_config.value.app.inactivityTimeout === undefined) { pending_config.value.app.inactivityTimeout = 5 }
        defaults.value = extend(true, {}, $store.state.gateway.app.defaults)
        remotes.value = extend(true, [], $store.state.gateway.app.remotes)
        ethereum_config.value = extend(true, {}, $store.state.gateway.ethereum)
        ethereum_network_index.value = ethereum_config.value.ethereum_network_index
      } catch (error) {
        await api.error("components/settings_general", "onMounted", error.stack || error)
      }
    })

    onMounted(async () => {
      try {
        isDevelopment.value = await api.isDevelopment()
        if (
          remotes.value.length > 0 &&
          pending_config.value.app.net_type === "mainnet"
        ) {
          let remote = remotes.value.find(c => c.host === config_daemon.value.remote_host)
          if (!remote) {
            remote = remotes.value[0]
          }
          setPreset(remote)
        }
      } catch (error) {
        await api.error("components/settings_general", "onMounted", error.stack || error)
      }
    })

    const save = async (value) => {
      try {
        await api.saveLoggingLevelToEnvironmentFile(pending_config.value.app.loggingLevel)
      } catch (error) {
        await api.error("components/settings_general", "save", error.stack || error)
      }
      try {
        const new_ethereum_config = extend(true, {}, ethereum_config.value, { ethereum_network_index: ethereum_network_index.value })
        await api.send("core", "change_ethereum", extend(true, {}, new_ethereum_config))

        await api.send("core", "change_remotes", extend(true, [], remotes.value))

        const new_pending_config = extend(true, {}, pending_config.value, { ethereum: new_ethereum_config })
        await $store.dispatch("gateway/savePendingConfig", new_pending_config)

        await api.send("core", value.method, new_pending_config)

        await $store.dispatch("gateway/notifier", { save: false })
      } catch (error) {
        await api.error("components/settings_general", "save", error.stack || error)
      }
    }

    const removeRemote = async () => {
      try {
        if (remotes.value.length === 1) {
          return
        }
        if (!remotes.value.some(element => {
          return element.host === config_daemon.value.remote_host
        })) {
          return
        }

        remotes.value.splice(remotes.value.findIndex(item => item.host === config_daemon.value.remote_host), 1)
        setPreset(remotes.value.length > 0 ? remotes.value[0] : [])
      } catch (error) {
        await api.error("components/settings_general", "removeRemote", error.stack || error)
      }
    }

    const addRemote = async () => {
      try {
        if (remotes.value.some(element => {
          return element.host === config_daemon.value.remote_host
        })) {
          return
        }
        remotes.value.push({ host: config_daemon.value.remote_host, port: config_daemon.value.remote_port })
      } catch (error) {
        await api.error("components/settings_general", "addRemote", error.stack || error)
      }
    }

    const setDataPath = async () => {
      try {
        const result = await api.openDirectory(pending_config.value.app.data_dir)
        // Support both 'canceled' and 'cancelled'
        const isCanceled = result.canceled || result.cancelled
        // Support both 'filePath' (string) and 'filePaths' (array)
        const path = result.filePath || (result.filePaths && result.filePaths[0])
        if (!isCanceled && path) {
          pending_config.value.app.data_dir = path
        }
      } catch (error) {
        await api.error("components/settings_general", "selectPath", error.stack || error)
      }
    }

    const setWalletDataPath = async () => {
      try {
        const result = await api.openDirectory(pending_config.value.app.wallet_data_dir)
        if (result && !result.cancelled && !!result.filePaths[0]) {
          pending_config.value.app.wallet_data_dir = result.filePaths[0]
        }
      } catch (error) {
        await api.error("components/settings_general", "selectPath", error.stack || error)
      }
    }

    const setPreset = async (option) => {
      try {
        config_daemon.value.remote_host = option.host
        config_daemon.value.remote_port = option.port
      } catch (error) {
        await api.error("components/settings_general", "setPreset", error.stack || error)
      }
    }

    const asString = (value) => {
      if (!value && typeof value !== "number") return ""
      return String(value)
    }

    return {
      t,
      notifier,
      notifierWatcher,
      save,
      remoteScanOptions,
      networkOptions,
      promptForPasswordOptions,
      loggingLevels,
      select,
      remotes,
      theme,
      pending_config,
      config_daemon,
      is_remote,
      defaults,
      daemon_defaults,
      removeRemote,
      addRemote,
      setDataPath,
      setWalletDataPath,
      setPreset,
      asString,
      arqmaField,
      ethereum_network,
      ethereum_network_index,
      isDevelopment
    }
  }
})
</script>

<style lang="scss">
.settings-general {
  .q-field {
    margin: 20px 0;
  }

  .q-if-disabled {
    cursor: default !important;

    .q-input-target {
      cursor: default !important;
    }
  }

  .q-item,
  .q-collapsible-sub-item {
    padding: 0;
  }

  .row.pl-sm {
    > * + * {
      padding-left: 16px;
    }
  }

  .col.pt-sm {
    > * + * {
      padding-top: 16px;
    }
  }

  .remote-dropdown {
    padding: 0 !important;
  }
}
</style>
