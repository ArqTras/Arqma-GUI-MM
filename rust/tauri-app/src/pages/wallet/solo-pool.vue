<template>
  <q-page
    class="q-pa-md"
    :class="theme === 'dark' ? 'solo-pool-page solo-pool-page--dark' : 'solo-pool-page solo-pool-page--light'"
  >
    <div class="solo-pool-scroll">
      <div class="solo-pool-content">
    <div class="row items-center q-mb-md">
      <div class="text-h6">{{ $t("components.solo_pool.title") }}</div>
      <q-space />
      <q-chip
        dense
        :color="statusColor"
        text-color="white"
      >
        {{ statusLabel }}
      </q-chip>
    </div>

    <q-banner
      v-if="daemonType === 'remote'"
      rounded
      dense
      class="bg-orange-2 text-black q-mb-md"
    >
      {{ $t("components.solo_pool.remote_warning") }}
    </q-banner>
    <q-banner
      v-if="settings.server.enabled && poolState.desynced"
      rounded
      dense
      class="bg-amber-2 text-black q-mb-md"
    >
      {{ $t("components.solo_pool.pool_desync_hint") }}
    </q-banner>
    <q-banner
      v-if="settings.server.enabled && poolState.system_clock_error"
      rounded
      dense
      class="bg-negative text-white q-mb-md"
    >
      {{ $t("components.solo_pool.system_clock_error_hint") }}
    </q-banner>

    <q-card
      flat
      bordered
      class="solo-pool-card q-pa-md q-mb-md"
      :dark="theme === 'dark'"
    >
      <q-checkbox
        v-model="settings.server.enabled"
        :label="$t('components.solo_pool.enable')"
        :disable="daemonType === 'remote'"
      />

      <q-select
        v-model="settings.mining.address"
        :options="walletAddressOptions"
        emit-value
        map-options
        :label="$t('components.solo_pool.mining_address')"
        class="q-mt-sm"
        :dark="theme === 'dark'"
      />

      <div class="row q-col-gutter-md q-mt-sm">
        <div class="col-8">
          <q-select
            v-model="settings.server.bindIP"
            :options="bindIpOptions"
            emit-value
            map-options
            :label="$t('components.solo_pool.bind_ip')"
            :dark="theme === 'dark'"
          />
        </div>
        <div class="col-4">
          <q-input
            v-model.number="settings.server.bindPort"
            type="number"
            min="1024"
            max="65535"
            :label="$t('components.solo_pool.port')"
            :dark="theme === 'dark'"
          />
        </div>
      </div>
    </q-card>

    <div class="row q-col-gutter-sm q-mb-sm">
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.net_hashrate") }}</div>
          <div class="text-weight-medium">{{ shortHashrate(poolStats.networkHashrate) }}</div>
        </q-card>
      </div>
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.net_difficulty") }}</div>
          <div class="text-weight-medium">{{ commas(poolStats.diff) }}</div>
        </q-card>
      </div>
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.height") }}</div>
          <div class="text-weight-medium">{{ commas(poolStats.height) }}</div>
        </q-card>
      </div>
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.workers") }}</div>
          <div class="text-weight-medium">{{ poolStats.activeWorkers || 0 }}</div>
        </q-card>
      </div>
    </div>

    <div class="row q-col-gutter-sm q-mb-sm">
      <div
        v-for="(ec, i) in effortCards"
        :key="`eff-${i}`"
        class="col-6 col-sm-4 col-md"
      >
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ ec.label }}</div>
          <div class="text-weight-medium">{{ ec.value }}</div>
        </q-card>
      </div>
    </div>

    <div class="text-subtitle2 q-mb-sm">
      {{ $t("components.solo_pool.pool_hashrate") }}
    </div>
    <div class="row q-col-gutter-sm q-mb-md">
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.hashrate_5m") }}</div>
          <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_5min) }}</div>
        </q-card>
      </div>
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.hashrate_1h") }}</div>
          <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_1hr) }}</div>
        </q-card>
      </div>
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.hashrate_6h") }}</div>
          <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_6hr) }}</div>
        </q-card>
      </div>
      <div class="col-3">
        <q-card flat bordered class="solo-pool-card q-pa-sm" :dark="theme === 'dark'">
          <div class="text-caption">{{ $t("components.solo_pool.hashrate_24h") }}</div>
          <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_24hr) }}</div>
        </q-card>
      </div>
    </div>

    <q-card flat bordered class="solo-pool-card q-pa-sm q-mb-md" :dark="theme === 'dark'">
      <div class="row items-center q-mb-sm">
        <div class="text-caption">{{ $t("components.solo_pool.hashrate_chart") }}</div>
        <q-space />
        <q-select
          v-model="selectedWorker"
          dense
          outlined
          emit-value
          map-options
          style="min-width: 200px;"
          :options="workerSelectOptions"
          :label="$t('components.solo_pool.chart_worker')"
          :dark="theme === 'dark'"
        />
        <q-space class="q-mx-sm" />
        <q-btn-toggle
          v-model="chartRange"
          dense
          unelevated
          color="primary"
          toggle-color="accent"
          :options="chartRangeOptions"
        />
      </div>
      <div class="row q-mb-xs text-caption">
        <div class="col">{{ shortHashrate(chartMax) }}</div>
        <div class="col text-center">{{ shortHashrate(chartMid) }}</div>
        <div class="col text-right">0 H/s</div>
      </div>
      <svg width="100%" height="120" viewBox="0 0 600 120" preserveAspectRatio="none">
        <line
          v-for="(gy, i) in gridY"
          :key="`gy-${i}`"
          x1="0"
          :y1="gy"
          x2="600"
          :y2="gy"
          stroke="rgba(200, 175, 130, 0.35)"
          stroke-width="1"
        />
        <line
          v-for="(gx, i) in gridX"
          :key="`gx-${i}`"
          :x1="gx"
          y1="0"
          :x2="gx"
          y2="120"
          stroke="rgba(200, 175, 130, 0.18)"
          stroke-width="1"
        />
        <polyline
          fill="none"
          stroke="#d4b76a"
          stroke-width="2"
          :points="hashratePolyline"
        />
        <polyline
          v-for="line in workerPolylines"
          :key="line.miner"
          fill="none"
          :stroke="line.color"
          stroke-width="1.8"
          :points="line.points"
          opacity="0.9"
        />
      </svg>
      <div
        v-if="selectedWorker === '__all__'"
        class="row q-col-gutter-xs q-mt-xs"
      >
        <div
          v-for="line in workerPolylines"
          :key="`legend-${line.miner}`"
          class="col-auto"
        >
          <q-chip dense square text-color="white" :style="{ backgroundColor: line.color }">
            {{ line.miner }}
          </q-chip>
        </div>
      </div>
      <div class="row text-caption q-mt-xs">
        <div class="col">{{ chartRangeLeftLabel }}</div>
        <div class="col text-center">{{ chartRangeMidLabel }}</div>
        <div class="col text-right">{{ chartRangeRightLabel }}</div>
      </div>
    </q-card>

    <q-table
      dense
      flat
      bordered
      :dark="theme === 'dark'"
      class="solo-pool-card"
      :rows="workers"
      :columns="workerColumns"
      row-key="miner"
      :rows-per-page-options="[0]"
      hide-bottom
    />

    <div class="text-subtitle2 q-mt-md q-mb-sm">Blocks</div>
    <q-table
      dense
      flat
      bordered
      :dark="theme === 'dark'"
      class="solo-pool-card"
      :rows="blocks"
      :columns="blockColumns"
      row-key="timeFound"
      :rows-per-page-options="[0]"
      hide-bottom
    />

    <q-card
      flat
      bordered
      class="solo-pool-card q-mb-md q-pa-md q-mt-md"
      :dark="theme === 'dark'"
    >
      <div class="text-subtitle1 q-mb-xs">{{ $t("components.solo_pool.vardiff_section") }}</div>
      <div
        class="text-caption q-mb-md"
        :class="theme === 'dark' ? 'text-grey-5' : 'text-grey-8'"
      >
        {{ $t("components.solo_pool.vardiff_caption") }}
      </div>
      <div class="row q-col-gutter-md">
        <div class="col-6 col-sm-4">
          <q-input
            v-model.number="settings.varDiff.startDiff"
            type="number"
            min="1000"
            step="100"
            :label="$t('components.solo_pool.vardiff_start_diff')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
        <div class="col-6 col-sm-4">
          <q-input
            v-model.number="settings.varDiff.minDiff"
            type="number"
            min="1000"
            step="100"
            :label="$t('components.solo_pool.vardiff_min')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
        <div class="col-12 col-sm-4">
          <q-input
            v-model.number="settings.varDiff.maxDiff"
            type="number"
            min="1000"
            step="1000"
            :label="$t('components.solo_pool.vardiff_max')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
        <div class="col-6 col-sm-4">
          <q-input
            v-model.number="settings.varDiff.targetTime"
            type="number"
            min="5"
            max="600"
            :label="$t('components.solo_pool.vardiff_target_time')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
        <div class="col-6 col-sm-4">
          <q-input
            v-model.number="settings.varDiff.retargetTime"
            type="number"
            min="10"
            max="3600"
            :label="$t('components.solo_pool.vardiff_retarget_time')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
        <div class="col-6 col-sm-4">
          <q-input
            v-model.number="settings.varDiff.variancePercent"
            type="number"
            min="1"
            max="95"
            :label="$t('components.solo_pool.vardiff_variance')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
        <div class="col-6 col-sm-4">
          <q-input
            v-model.number="settings.varDiff.maxJump"
            type="number"
            min="1"
            max="10000"
            :label="$t('components.solo_pool.vardiff_max_jump')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
        <div class="col-6 col-sm-4">
          <q-input
            v-model="settings.varDiff.fixedDiffSeparator"
            maxlength="2"
            :label="$t('components.solo_pool.vardiff_separator')"
            :dark="theme === 'dark'"
            dense
          />
        </div>
      </div>
    </q-card>

    <div class="row justify-end q-mt-md">
      <q-btn
        color="primary"
        :label="$t('components.solo_pool.save')"
        @click="save"
      />
    </div>
      </div>
    </div>
  </q-page>
</template>

<script>
import { computed, defineComponent, inject, nextTick, ref, watch } from "vue"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import { useI18n } from "vue-i18n"

function snapshotVarDiffParams (vd) {
  if (!vd || typeof vd !== "object") return null
  return {
    startDiff: Number(vd.startDiff) || 0,
    minDiff: Number(vd.minDiff) || 0,
    maxDiff: Number(vd.maxDiff) || 0,
    targetTime: Number(vd.targetTime) || 0,
    retargetTime: Number(vd.retargetTime) || 0,
    variancePercent: Number(vd.variancePercent) || 0,
    maxJump: Number(vd.maxJump) || 0,
    fixedDiffSeparator: String(vd.fixedDiffSeparator ?? ".")
  }
}

function varDiffParamsChanged (before, after) {
  const a = snapshotVarDiffParams(before)
  const b = snapshotVarDiffParams(after)
  if (a === null && b === null) return false
  if (a === null || b === null) return true
  return JSON.stringify(a) !== JSON.stringify(b)
}

const defaults = () => ({
  server: {
    enabled: false,
    bindIP: "",
    bindPort: 3333
  },
  mining: {
    address: "",
    enableBlockRefreshInterval: false,
    blockRefreshInterval: 5,
    minerTimeout: 900,
    uniform: true
  },
  varDiff: {
    enabled: true,
    startDiff: 150000,
    minDiff: 150000,
    maxDiff: 10000000,
    targetTime: 20,
    retargetTime: 30,
    variancePercent: 25,
    maxJump: 200,
    fixedDiffSeparator: "."
  }
})

export default defineComponent({
  name: "SoloPoolPage",
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()
    const gateway = inject("gateway")

    const settings = ref(defaults())
    const chartRange = ref("60m")
    const selectedWorker = ref("__all__")

    const wallets = computed(() => $store.state.gateway.wallets.list || [])
    const currentWallet = computed(() => $store.state.gateway.wallet.info || {})
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const poolState = computed(() => $store.state.gateway.pool || { status: 0 })
    const appConfig = computed(() => $store.state.gateway.app.config || {})
    const daemonType = computed(() => {
      const net = appConfig.value?.app?.net_type
      return appConfig.value?.daemons?.[net]?.type || "remote"
    })
    const networkInterfaces = computed(() => {
      const remotes = $store.state.gateway.app?.remotes || []
      const configuredBindIp = appConfig.value?.pool?.server?.bindIP || ""
      const candidates = ["127.0.0.1"]
        .concat(configuredBindIp ? [configuredBindIp] : [])
        .concat(remotes.map((r) => r.host || r.address || ""))
        .filter((v) => !!v)
      const unique = [...new Set(candidates)]
      return unique.map((ip) => ({ label: ip, value: ip }))
    })

    const walletAddressOptions = computed(() => {
      const activeAddress = currentWallet.value?.address || ""
      if (activeAddress) {
        const activeWallet = wallets.value.find((w) => w.address === activeAddress)
        const label = activeWallet ? `${activeWallet.name} - ${activeWallet.address}` : activeAddress
        return [{ label, value: activeAddress }]
      }
      return wallets.value.slice(0, 1).map((w) => ({
        label: `${w.name} - ${w.address}`,
        value: w.address
      }))
    })
    const bindIpOptions = computed(() => networkInterfaces.value)

    const statusLabel = computed(() => {
      if (poolState.value.status === 2) return t("components.solo_pool.status_ready")
      if (poolState.value.status === 1) return t("components.solo_pool.status_waiting")
      if (poolState.value.status === -1) return t("components.solo_pool.status_error")
      return t("components.solo_pool.status_not_ready")
    })
    const statusColor = computed(() => {
      if (poolState.value.status === 2) return "positive"
      if (poolState.value.status === 1) return "warning"
      if (poolState.value.status === -1) return "negative"
      return "grey"
    })
    const poolStats = computed(() => poolState.value?.stats || {})
    const workers = computed(() => (poolState.value?.workers || []).filter((w) => w.miner !== "all"))
    const blocks = computed(() => poolState.value?.blocks || [])
    const poolHashrates = computed(() => poolState.value?.stats?.h || {})
    const workerSelectOptions = computed(() => {
      const base = [{ label: t("components.solo_pool.chart_all_workers"), value: "__all__" }]
      return base.concat(workers.value.map((w) => ({ label: w.miner, value: w.miner })))
    })
    const workerColumns = computed(() => [
      { name: "miner", field: "miner", label: t("components.solo_pool.worker"), align: "left" },
      { name: "difficulty", field: "difficulty", label: t("components.solo_pool.difficulty"), align: "right", format: (v) => commas(v) },
      { name: "rejects", field: "rejects", label: t("components.solo_pool.rejects"), align: "right", format: (v) => commas(v) },
      { name: "lastShare", field: "lastShare", label: t("components.solo_pool.last_share"), align: "left", format: (v) => v ? new Date(v).toLocaleString() : "-" }
    ])
    const blockColumns = computed(() => [
      { name: "height", field: "height", label: t("components.solo_pool.height"), align: "right", format: (v) => commas(v) },
      {
        name: "status",
        field: "status",
        label: t("components.footer.status"),
        align: "left",
        format: (v) => (Number(v) === 2 ? "Unlocked" : (Number(v) === 1 ? "Orphaned" : "Pending"))
      },
      { name: "difficulty", field: "diff", label: t("components.solo_pool.difficulty"), align: "right", format: (v) => commas(v) },
      { name: "worker", field: "miner", label: t("components.solo_pool.worker"), align: "left" },
      {
        name: "hash",
        field: "hash",
        label: t("components.swap_list_tabular.block_hash"),
        align: "left",
        format: (v) => (v ? String(v).slice(0, 18) + "..." : "-")
      },
      {
        name: "time",
        field: "timeFound",
        label: t("components.solo_pool.last_share"),
        align: "left",
        format: (v) => v ? new Date(v).toLocaleString() : "-"
      }
    ])

    const syncFromConfig = () => {
      const d = defaults()
      const p = appConfig.value.pool
      if (!p) {
        settings.value = d
      } else {
        const raw = JSON.parse(JSON.stringify(p))
        settings.value = {
          server: { ...d.server, ...(raw.server || {}) },
          mining: { ...d.mining, ...(raw.mining || {}) },
          varDiff: { ...d.varDiff, ...(raw.varDiff || {}) }
        }
      }
      if (!settings.value.mining.address && wallets.value.length > 0) {
        settings.value.mining.address = wallets.value[0].address
      }
      settings.value.varDiff.enabled = true
    }
    watch([appConfig, wallets], syncFromConfig, { immediate: true })

    const save = async () => {
      if (!settings.value.mining.address) {
        $q.notify({ type: "negative", message: t("components.solo_pool.address_required"), timeout: 1500 })
        return
      }
      if (settings.value.server.bindPort < 1024 || settings.value.server.bindPort > 65535) {
        $q.notify({ type: "negative", message: t("components.solo_pool.invalid_port"), timeout: 1500 })
        return
      }
      if (daemonType.value === "remote") {
        $q.notify({ type: "warning", message: t("components.solo_pool.remote_warning"), timeout: 2000 })
        settings.value.server.enabled = false
      }
      settings.value.varDiff.enabled = true
      const prevPool = appConfig.value?.pool
      const prevVardiff = prevPool?.varDiff
      await api.send("core", "save_pool_config", settings.value)
      $q.notify({ type: "positive", message: t("components.solo_pool.saved"), timeout: 1500 })
      if (
        prevPool &&
        varDiffParamsChanged(prevVardiff, settings.value.varDiff) &&
        gateway?.confirmClose
      ) {
        void nextTick(() => {
          gateway.confirmClose(t("components.solo_pool.vardiff_restart_prompt"), true)
        })
      }
    }

    const commas = (v) => (Number(v || 0)).toLocaleString()
    const shortHashrate = (h) => {
      let n = Number(h || 0)
      const units = ["H/s", "kH/s", "MH/s", "GH/s", "TH/s"]
      let i = 0
      while (n >= 1000 && i < units.length - 1) {
        n /= 1000
        i += 1
      }
      return `${n.toFixed(2)} ${units[i]}`
    }

    const formatBlockTime = (ms) => {
      const n = Number(ms || 0)
      if (!n) return "—"
      if (n < 60000) return `${Math.round(n / 1000)} s`
      if (n < 3600000) return `${Math.round(n / 60000)} min`
      return `${(n / 3600000).toFixed(1)} h`
    }
    const effortCards = computed(() => {
      const s = poolStats.value
      return [
        { label: t("components.solo_pool.round_hashes"), value: commas(s.roundHashes) },
        { label: t("components.solo_pool.current_effort"), value: Number(s.currentEffort || 0).toFixed(2) },
        { label: t("components.solo_pool.average_effort"), value: Number(s.averageEffort || 0).toFixed(2) },
        { label: t("components.solo_pool.est_block_time"), value: formatBlockTime(s.blockTime) },
        { label: t("components.solo_pool.blocks_found"), value: String(s.blocksFound ?? 0) }
      ]
    })

    const hashratePolyline = computed(() => {
      const rangeToBuckets = { "15m": 15, "60m": 60, "6h": 360 }
      const wanted = rangeToBuckets[chartRange.value] || 60
      const sourceWorkers = selectedWorker.value === "__all__"
        ? workers.value
        : workers.value.filter((w) => w.miner === selectedWorker.value)
      const buckets = new Map()
      for (const w of sourceWorkers) {
        const g = w.hashrate_graph || {}
        Object.keys(g).forEach((k) => {
          const cur = buckets.get(k) || 0
          buckets.set(k, cur + Number(g[k] || 0))
        })
      }
      const ordered = Array.from(buckets.entries())
        .sort((a, b) => Number(a[0]) - Number(b[0]))
        .slice(-wanted)
        .map(([, v]) => Number(v || 0))
      if (ordered.length < 2) return "0,120 600,120"
      const max = Math.max(...ordered, 1)
      return ordered.map((v, i) => {
        const x = (i / (ordered.length - 1)) * 600
        const y = 120 - ((v / max) * 110)
        return `${x},${y}`
      }).join(" ")
    })

    // Gold tones (theme) — distinct hues for multiple workers, no green/blue
    const linePalette = [
      "#dbd19c", "#a89060", "#e8d4a8", "#8b7355", "#c9a86c", "#f0e4c4", "#6d5a40", "#b89b6a"
    ]
    const workerPolylines = computed(() => {
      if (selectedWorker.value !== "__all__") return []
      const rangeToBuckets = { "15m": 15, "60m": 60, "6h": 360 }
      const wanted = rangeToBuckets[chartRange.value] || 60
      const topWorkers = workers.value
        .map((w) => ({ miner: w.miner, h: Number(w.hashrate_5min || 0), g: w.hashrate_graph || {} }))
        .sort((a, b) => b.h - a.h)
        .slice(0, 6)
      return topWorkers.map((w, idx) => {
        const ordered = Object.entries(w.g)
          .sort((a, b) => Number(a[0]) - Number(b[0]))
          .slice(-wanted)
          .map(([, v]) => Number(v || 0))
        if (ordered.length < 2) {
          return { miner: w.miner, color: linePalette[idx % linePalette.length], points: "0,120 600,120" }
        }
        const max = Math.max(...ordered, 1)
        const points = ordered.map((v, i) => {
          const x = (i / (ordered.length - 1)) * 600
          const y = 120 - ((v / max) * 110)
          return `${x},${y}`
        }).join(" ")
        return { miner: w.miner, color: linePalette[idx % linePalette.length], points }
      })
    })
    const chartPoints = computed(() => hashratePolyline.value
      .split(" ")
      .map((p) => {
        const parts = p.split(",")
        return { x: Number(parts[0] || 0), y: Number(parts[1] || 120) }
      })
      .filter((p) => !Number.isNaN(p.x) && !Number.isNaN(p.y))
    )
    const chartMax = computed(() => {
      if (!chartPoints.value.length) return 0
      const minY = Math.min(...chartPoints.value.map((p) => p.y))
      return Math.round(((120 - minY) / 110) * 1000) * 1000
    })
    const chartMid = computed(() => Math.round(chartMax.value / 2))
    const gridY = computed(() => [0, 30, 60, 90, 120])
    const gridX = computed(() => [0, 100, 200, 300, 400, 500, 600])
    const chartRangeOptions = computed(() => [
      { label: t("components.solo_pool.range_15m"), value: "15m" },
      { label: t("components.solo_pool.range_60m"), value: "60m" },
      { label: t("components.solo_pool.range_6h"), value: "6h" }
    ])
    const chartRangeLeftLabel = computed(() => (chartRange.value === "15m" ? "-15m" : (chartRange.value === "6h" ? "-6h" : "-60m")))
    const chartRangeMidLabel = computed(() => (chartRange.value === "15m" ? "-7.5m" : (chartRange.value === "6h" ? "-3h" : "-30m")))
    const chartRangeRightLabel = computed(() => t("components.solo_pool.now"))

    return {
      settings,
      theme,
      walletAddressOptions,
      bindIpOptions,
      daemonType,
      statusLabel,
      statusColor,
      poolState,
      poolStats,
      effortCards,
      workers,
      blocks,
      poolHashrates,
      workerColumns,
      blockColumns,
      chartRange,
      selectedWorker,
      workerSelectOptions,
      chartRangeOptions,
      chartMax,
      chartMid,
      gridY,
      gridX,
      chartRangeLeftLabel,
      chartRangeMidLabel,
      chartRangeRightLabel,
      hashratePolyline,
      workerPolylines,
      commas,
      shortHashrate,
      save
    }
  }
})
</script>

<style scoped>
/* Light theme: default Quasar (dark text). We used to force #f2f2f2, which made fields invisible on light background. */
.solo-pool-page--dark {
  color: #f2f2f2;
}

.solo-pool-page--dark :deep(.q-field__native),
.solo-pool-page--dark :deep(.q-field__input),
.solo-pool-page--dark :deep(.q-field__label),
.solo-pool-page--dark :deep(.q-checkbox__label),
.solo-pool-page--dark :deep(.q-item__label) {
  color: #f2f2f2 !important;
}

.solo-pool-scroll {
  width: 100%;
  height: calc(100vh - 240px);
  overflow: auto;
  padding-right: 4px;
}

.solo-pool-content {
  min-width: 0;
  width: 100%;
  max-width: 1280px;
}

.solo-pool-card {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.2);
}

/* Same idea as the first card (Enable solo mining): slightly stronger background behind the VarDiff toggle */
</style>
