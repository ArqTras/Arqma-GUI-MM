<template>
  <q-dialog
    v-model="isVisible"
    transition-show="flip-up"
    transition-hide="flip-down"
  >
    <q-card style="min-width: 760px; max-width: 90vw;">
      <q-card-section class="row items-center q-pb-sm">
        <div class="text-h6">{{ $t("components.solo_pool.title") }}</div>
        <q-space />
        <q-chip
          dense
          :color="statusColor"
          text-color="white"
        >
          {{ statusLabel }}
        </q-chip>
      </q-card-section>

      <q-separator />

      <q-card-section class="q-gutter-md">
        <q-banner
          v-if="daemonType === 'remote'"
          rounded
          dense
          class="bg-orange-2 text-black"
        >
          {{ $t("components.solo_pool.remote_warning") }}
        </q-banner>

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
        />

        <div class="row q-col-gutter-md">
          <div class="col-8">
            <q-select
              v-model="settings.server.bindIP"
              :options="bindIpOptions"
              emit-value
              map-options
              :label="$t('components.solo_pool.bind_ip')"
            />
          </div>
          <div class="col-4">
            <q-input
              v-model.number="settings.server.bindPort"
              type="number"
              min="1024"
              max="65535"
              :label="$t('components.solo_pool.port')"
            />
          </div>
        </div>

        <div class="row q-col-gutter-sm">
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.net_hashrate") }}</div>
              <div class="text-weight-medium">{{ shortHashrate(poolStats.networkHashrate) }}</div>
            </q-card>
          </div>
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.net_difficulty") }}</div>
              <div class="text-weight-medium">{{ commas(poolStats.diff) }}</div>
            </q-card>
          </div>
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.height") }}</div>
              <div class="text-weight-medium">{{ commas(poolStats.height) }}</div>
            </q-card>
          </div>
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.workers") }}</div>
              <div class="text-weight-medium">{{ poolStats.activeWorkers || 0 }}</div>
            </q-card>
          </div>
        </div>

        <div class="text-subtitle2 q-mt-sm">
          {{ $t("components.solo_pool.pool_hashrate") }}
        </div>
        <div class="row q-col-gutter-sm">
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.hashrate_5m") }}</div>
              <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_5min) }}</div>
            </q-card>
          </div>
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.hashrate_1h") }}</div>
              <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_1hr) }}</div>
            </q-card>
          </div>
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.hashrate_6h") }}</div>
              <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_6hr) }}</div>
            </q-card>
          </div>
          <div class="col-3">
            <q-card flat bordered class="q-pa-sm">
              <div class="text-caption">{{ $t("components.solo_pool.hashrate_24h") }}</div>
              <div class="text-weight-medium">{{ shortHashrate(poolHashrates.hashrate_24hr) }}</div>
            </q-card>
          </div>
        </div>

        <q-card flat bordered class="q-pa-sm">
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
          <svg
            width="100%"
            height="120"
            viewBox="0 0 600 120"
            preserveAspectRatio="none"
          >
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
              <q-chip
                dense
                square
                text-color="white"
                :style="{ backgroundColor: line.color }"
              >
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
          :rows="workers"
          :columns="workerColumns"
          row-key="miner"
          :rows-per-page-options="[0]"
          hide-bottom
        />

        <q-card
          flat
          bordered
          class="q-mt-md q-pa-md"
        >
          <div class="text-subtitle2 q-mb-xs">{{ $t("components.solo_pool.vardiff_section") }}</div>
          <div class="text-caption text-grey-5 q-mb-md">{{ $t("components.solo_pool.vardiff_caption") }}</div>
          <div class="row q-col-gutter-sm">
            <div class="col-6 col-sm-4">
              <q-input
                v-model.number="settings.varDiff.startDiff"
                type="number"
                min="1000"
                :label="$t('components.solo_pool.vardiff_start_diff')"
                dense
              />
            </div>
            <div class="col-6 col-sm-4">
              <q-input
                v-model.number="settings.varDiff.minDiff"
                type="number"
                min="1000"
                :label="$t('components.solo_pool.vardiff_min')"
                dense
              />
            </div>
            <div class="col-12 col-sm-4">
              <q-input
                v-model.number="settings.varDiff.maxDiff"
                type="number"
                min="1000"
                :label="$t('components.solo_pool.vardiff_max')"
                dense
              />
            </div>
            <div class="col-6 col-sm-4">
              <q-input
                v-model.number="settings.varDiff.targetTime"
                type="number"
                min="5"
                :label="$t('components.solo_pool.vardiff_target_time')"
                dense
              />
            </div>
            <div class="col-6 col-sm-4">
              <q-input
                v-model.number="settings.varDiff.retargetTime"
                type="number"
                min="10"
                :label="$t('components.solo_pool.vardiff_retarget_time')"
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
                dense
              />
            </div>
            <div class="col-6 col-sm-4">
              <q-input
                v-model.number="settings.varDiff.maxJump"
                type="number"
                min="1"
                :label="$t('components.solo_pool.vardiff_max_jump')"
                dense
              />
            </div>
            <div class="col-6 col-sm-4">
              <q-input
                v-model="settings.varDiff.fixedDiffSeparator"
                maxlength="2"
                :label="$t('components.solo_pool.vardiff_separator')"
                dense
              />
            </div>
          </div>
        </q-card>
      </q-card-section>

      <q-card-actions align="right">
        <q-btn
          flat
          :label="$t('components.solo_pool.close')"
          @click="isVisible = false"
        />
        <q-btn
          color="primary"
          :label="$t('components.solo_pool.save')"
          @click="save"
        />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script>
import { computed, defineComponent, inject, nextTick, ref } from "vue"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import { useI18n } from "vue-i18n"

const defaults = () => ({
  server: {
    enabled: false,
    bindIP: "0.0.0.0",
    bindPort: 3333
  },
  mining: {
    address: "",
    enableBlockRefreshInterval: true,
    blockRefreshInterval: 5,
    minerTimeout: 900
  },
  varDiff: {
    enabled: true,
    startDiff: 60000,
    minDiff: 25000,
    maxDiff: 5000000,
    targetTime: 45,
    retargetTime: 30,
    variancePercent: 25,
    maxJump: 50,
    fixedDiffSeparator: "."
  }
})

export default defineComponent({
  name: "SoloPoolModal",
  setup (props, { expose }) {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()
    const gateway = inject("gateway")

    const isVisible = ref(false)
    const settings = ref(defaults())
    const chartRange = ref("60m")
    const selectedWorker = ref("__all__")

    const wallets = computed(() => $store.state.gateway.wallets.list || [])
    const poolState = computed(() => $store.state.gateway.pool || { status: 0 })
    const appConfig = computed(() => $store.state.gateway.app.config || {})
    const daemonType = computed(() => {
      const net = appConfig.value?.app?.net_type
      return appConfig.value?.daemons?.[net]?.type || "remote"
    })
    const networkInterfaces = computed(() => {
      const remotes = $store.state.gateway.app?.remotes || []
      return [{ label: "0.0.0.0", value: "0.0.0.0" }, { label: "127.0.0.1", value: "127.0.0.1" }]
        .concat(remotes.map((r) => ({ label: r.host || r.address || "", value: r.host || r.address || "" })))
    })

    const walletAddressOptions = computed(() => wallets.value.map((w) => ({
      label: `${w.name} - ${w.address}`,
      value: w.address
    })))
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

    const syncFromConfig = () => {
      const d = defaults()
      const p = appConfig.value.pool
      if (!p) {
        settings.value = d
      } else {
        const raw = JSON.parse(JSON.stringify(p))
        const mergedMining = { ...d.mining, ...(raw.mining || {}) }
        settings.value = {
          server: { ...d.server, ...(raw.server || {}) },
          mining: mergedMining,
          varDiff: { ...d.varDiff, ...(raw.varDiff || {}) }
        }
      }
      if (!settings.value.mining.address && wallets.value.length > 0) {
        settings.value.mining.address = wallets.value[0].address
      }
      settings.value.varDiff.enabled = true
    }

    const open = () => {
      syncFromConfig()
      selectedWorker.value = "__all__"
      isVisible.value = true
    }

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
      const poolPayload = JSON.parse(JSON.stringify(settings.value))
      await api.send("core", "save_pool_config", poolPayload)
      $q.notify({ type: "positive", message: t("components.solo_pool.saved"), timeout: 1500 })
      isVisible.value = false
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

    const hashratePolyline = computed(() => {
      const rangeToBuckets = {
        "15m": 15,
        "60m": 60,
        "6h": 360
      }
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
    const linePalette = [
      "#dbd19c", "#a89060", "#e8d4a8", "#8b7355", "#c9a86c", "#f0e4c4", "#6d5a40", "#b89b6a"
    ]
    const workerPolylines = computed(() => {
      if (selectedWorker.value !== "__all__") return []
      const rangeToBuckets = {
        "15m": 15,
        "60m": 60,
        "6h": 360
      }
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
    const chartPoints = computed(() => {
      return hashratePolyline.value
        .split(" ")
        .map((p) => {
          const parts = p.split(",")
          return { x: Number(parts[0] || 0), y: Number(parts[1] || 120) }
        })
        .filter((p) => !Number.isNaN(p.x) && !Number.isNaN(p.y))
    })
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
    const chartRangeLeftLabel = computed(() => {
      if (chartRange.value === "15m") return "-15m"
      if (chartRange.value === "6h") return "-6h"
      return "-60m"
    })
    const chartRangeMidLabel = computed(() => {
      if (chartRange.value === "15m") return "-7.5m"
      if (chartRange.value === "6h") return "-3h"
      return "-30m"
    })
    const chartRangeRightLabel = computed(() => t("components.solo_pool.now"))

    expose({ open })

    return {
      isVisible,
      settings,
      walletAddressOptions,
      bindIpOptions,
      daemonType,
      statusLabel,
      statusColor,
      poolStats,
      workers,
      poolHashrates,
      workerColumns,
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
