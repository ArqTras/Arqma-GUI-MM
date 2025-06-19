<template>
  <q-page>
    <div>
      <div
        class="row justify-start q-gutter-x-md q-pt-sm q-mx-md q-mb-sm"
      >
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.network_stats') }}
        </p>
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.total_nodes') }}
          {{ pool_count.toLocaleString() }}
        </p>
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.monthly_yield') }} {{ monthlyYield.toLocaleString() }}%
        </p>
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.node_reward') }} ({{ nodeDuration }} days): {{ nodeReward.toLocaleString() }} ARQ
        </p>
        <p class="col-xs-12 col-sm-6 col-md-auto">
          {{ $t('pages.wallet.staking_pools.tvl') }} ${{ tvl.toLocaleString() }}
        </p>
      </div>
    </div>

    <div
      v-if="stake_data.total_staked"
    >
      <div
        class="row justify-start q-gutter-x-md q-pt-sm q-mx-md q-mb-sm"
      >
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.operator_stats') }}
        </p>
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.total_staked') }}
          {{ (stake_data.total_staked ? stake_data.total_staked : 0).toLocaleString() }} ARQ
        </p>
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.percentage_of_pool') }} {{ percentageOfPool.toLocaleString() }}%
        </p>
        <!-- <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.monthly_reward') }} {{ personalNodeRewards.toLocaleString() }} ARQ
        </p> -->
        <!-- <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.nodes_staked_to') }}
          {{ stake_data.staked_nodes.toLocaleString() }}
        </p> -->
        <p class="col-xs-12 col-sm-6 col-md-2">
          {{ $t('pages.wallet.staking_pools.nodes_operating') }}
          {{ stake_data.num_operating.toLocaleString() }}
        </p>
      </div>
    </div>

    <div
      class="row q-pt-sm q-mx-md q-mb-sm items-end non-selectable"
    >
      <arqmaField
        class="col-5 q-px-sm"
        :label="$t('pages.wallet.staking_pools.filter_by_oracle_nodeid')"
        :disable-menu="false"
      >
        <q-input
          v-model="node_id"
          :dark="theme == 'dark'"
          :placeholder="$t('pages.wallet.staking_pools.filter_by_oracle_nodeid_placeholder')"
          borderless
          dense
          :clearable="true"
        />
      </arqmaField>

      <arqmaField
        class="col-5 q-px-sm"
        :label="$t('pages.wallet.staking_pools.filter_by_operator_address')"
      >
        <q-input
          v-model="operator_id"
          :placeholder="$t('pages.wallet.staking_pools.filter_by_operator_address_placeholder')"
          :dark="theme == 'dark'"
          borderless
          dense
          :clearable="true"
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
              v-for="option in address_book"
              :key="option.address"
              v-close-popup
              clickable
              @click="setPreset(option)"
            >
              <q-item-section>
                <q-item-label caption>
                  {{ option.name }}
                </q-item-label>
                <q-item-label>{{ option.address }}</q-item-label>
              </q-item-section>
            </q-item>
          </q-list>
        </q-btn-dropdown>
      </arqmaField>

      <arqmaField
        class="col-2"
        :label="$t('pages.wallet.staking_pools.filter_by_oracle_node_status')"
      >
        <q-select
          v-model="node_filter_option"
          :dark="theme == 'dark'"
          :options="node_filter_options"
          :option-label="opt => Object(opt) === opt && 'label' in opt ? $t(opt.label) : ''"
          borderless
          dense
          transition-show="flip-up"
          transition-hide="flip-down"
        />
      </arqmaField>
    </div>

    <div class="scroller">
      <div
        :visible="false"
        class="fit column"
      >
        <PoolListTabular />
      </div>
    </div>
  </q-page>
</template>

<script>
import { computed, defineComponent, ref, watch, onBeforeUnmount, onBeforeMount, nextTick } from "vue"
import { useStore } from "vuex"
import PoolListTabular from "components/pool_list_tabular"
import arqmaField from "components/arqma_field"
import { useDebounce } from "src/composables/debounce"
import { useI18n } from "vue-i18n"

export default defineComponent({
  components: {
    arqmaField,
    PoolListTabular
  },
  setup () {
    const $store = useStore()
    const { t } = useI18n()

    const { debounce } = useDebounce()
    const node_filter_options = ref([
      { index: 0, label: "pages.wallet.staking_pools.all", value: (c) => true },
      { index: 1, label: "pages.wallet.staking_pools.open", value: (c) => c.total_contributed < c.staking_requirement },
      { index: 2, label: "pages.wallet.staking_pools.closed", value: (c) => c.total_contributed === c.staking_requirement },
      { index: 3, label: "pages.wallet.staking_pools.operator", value: (c) => c.is_operator === true },
      { index: 3, label: "pages.wallet.staking_pools.contributor", value: (c) => c.is_contributor === true }
    ])
    const node_filter_option = ref({ index: 1, label: "pages.wallet.staking_pools.open", value: (c) => c.total_contributed < c.staking_requirement })
    const standardFilters = node_filter_options.value.map(filter => filter.index)
    const confirmSend = ref(false)
    const oracleKey = ref("")
    const oracleAddress = ref("")
    const maxAmount = ref("")
    const stake_amount = ref("")
    const node_id = ref("")
    const operator_id = ref("")
    const tvl = ref(0)
    const nodeDuration = ref(28)
    const operatorReward = 7.8076
    const contributorReward = 3.6035
    const blocksPerDay = 720
    const serviceNodeReward = operatorReward + contributorReward
    const serviceNodeDurationReward = serviceNodeReward * nodeDuration.value
    const nodeReward = ref(0)
    const personalNodeRewards = ref(0)
    const monthlyYield = ref(0)
    const percentageOfPool = ref(0)
    const stakingRequirement = 100000

    const maxHeight = ref(`${Number(document.documentElement.clientHeight) - 425}px`)

    // // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const total_contributed = computed(() => $store.getters["gateway/total_contributed"] || 0)
    const pool_count = computed(() => {
      return $store.getters["gateway/pool_count"] || []
    })
    const state = computed(() => {
      return $store.state
    })
    const current_price = computed(() => $store.state.gateway.coin_price)
    const conversion_data = computed(() => $store.state.gateway.conversion_data)

    const currentFilter = computed(() => $store.getters["gateway/get_pools_filter"])
    const current_node_id_filter = computed(() => $store.getters["gateway/get_node_id_filter"])
    const current_operator_id_filter = computed(() => $store.getters["gateway/get_operator_id_filter"])

    const stake_data = computed(() => state.value.gateway.pools.staker.stake)

    const nonoperator_pools = computed(() => $store.getters["gateway/nonoperator_pools"])
    const operator_pools = computed(() => $store.getters["gateway/operator_pools"] || [])

    const address_book = computed(() => $store.getters["gateway/get_address_list"])

    // Watchers
    const node_idWatcher = watch(node_id, async (newVal, oldVal) => {
      if (newVal !== oldVal) {
        await $store.dispatch("gateway/set_node_id_filter", { index: 3, label: "Transaction", value: newVal })
        await nextTick()
      }
    })

    const operator_idWatcher = watch(operator_id, async (newVal, oldVal) => {
      if (newVal !== oldVal) {
        await $store.dispatch("gateway/set_operator_id_filter", { index: 4, label: "Operator", value: newVal })
        await nextTick()
      }
    })

    const node_filterWatcher = watch(node_filter_option, async (newVal, oldVal) => {
      await $store.dispatch("gateway/set_pools_filter", node_filter_option.value)
    })

    const nonoperator_poolsWatcher = watch(nonoperator_pools, (newVal, oldVal) => {
      const sumXeqStaked = total_contributed.value
      console.log("nonoperator_poolsWatcher", sumXeqStaked)
      conversionFromXtri(sumXeqStaked)
      getNodeReward()
      getPersonalNodeRewards()
      getMonthlyYield()
      getPercentageOfPool(sumXeqStaked)
    })

    const operator_poolsWatcher = watch(operator_pools, (newVal, oldVal) => {
      const sumXeqStaked = total_contributed.value
      console.log("operator_poolsWatcher", sumXeqStaked)
      conversionFromXtri(sumXeqStaked)
      getNodeReward()
      getPersonalNodeRewards()
      getMonthlyYield()
      getPercentageOfPool(sumXeqStaked)
    })

    const debouncedFn = debounce(() => {
      const clientHeight = document.documentElement.clientHeight
      maxHeight.value = `${Number(clientHeight) - 425}px`
    }, 500)

    // Hooks
    onBeforeMount(() => {
      try {
        window.addEventListener("resize", debouncedFn)
        api.send("wallet", "begin_Stake_Acquisition", {})

        if (!standardFilters.includes(currentFilter.value.index)) {
          node_filter_option.value = node_filter_options.value[1]
        } else {
          node_filter_option.value = currentFilter.value
        }
        if (!!current_node_id_filter.value) {
          node_id.value = current_node_id_filter.value.value
        }
        if (!!current_operator_id_filter.value) {
          operator_id.value = current_operator_id_filter.value.value
        }
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "onBeforeMounted", error.stack || error)
      }
    })

    onBeforeUnmount(() => {
      try {
        const clientHeight = document.documentElement.clientHeight
        maxHeight.value = `${Number(clientHeight) - 425}px`
        window.removeEventListener("resize", debouncedFn)
        $store.dispatch("gateway/resetPoolsData")
        api.send("wallet", "end_Stake_Acquisition", {})
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "onBeforeUnmount", error.stack || error)
      }
    })

    // Methods
    const isFull = (item) => {
      try {
        return item.total_contributed < item.staking_requirement
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "isFull", error.stack || error)
      }
    }

    const roundToTwo = (num) => {
      try {
        return +(Math.round(num + "e+2") + "e-2")
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "roundToTwo", error.stack || error)
      }
    }

    const getNodeReward = () => {
      try {
        let amount = 0
        if (pool_count.value > 0) { amount = roundToTwo((blocksPerDay / pool_count.value) * serviceNodeDurationReward) }
        nodeReward.value = amount
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "getNodeReward", error.stack || error)
      }
    }

    const getPersonalNodeRewards = () => {
      try {
        const amount = roundToTwo((stake_data.value.total_staked / tvl.value) * Number((blocksPerDay / pool_count.value) * nodeDuration.value * nodeDuration.value))
        personalNodeRewards.value = amount
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "getPersonalNodeRewards", error.stack || error)
      }
    }

    const getMonthlyYield = () => {
      try {
        let amount = 0
        if (pool_count.value > 0) {
          amount = roundToTwo((((blocksPerDay / pool_count.value) * operatorReward * nodeDuration.value) / (stakingRequirement)) * 100)
        }
        monthlyYield.value = amount
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "getMonthlyYield", error.stack || error)
      }
    }

    const getPercentageOfPool = (sumXeqStaked) => {
      try {
        const amount = roundToTwo((stake_data.value.total_staked / sumXeqStaked) * 100)
        percentageOfPool.value = amount
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "getPercentageOfPool", error.stack || error)
        percentageOfPool.value = 0
      }
    }

    const conversionFromXtri = (amount) => {
      try {
        // Do conversion with current currency
        tvl.value = roundToTwo(amount * conversion_data.value.currentPrice * conversion_data.value.sats)
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "conversionFromXtri", error.stack || error)
      }
    }

    // const getSumXeqStaked = () => {
    //   try {
    //     let sum_xeq_staked = 0
    //     for (let i = 0; i < pool_count.value; i++) {
    //       sum_xeq_staked += all_pools.value[i].total_contributed
    //     }
    //     return sum_xeq_staked / 1e9
    //   } catch (error) {
    //     api.error("/pages/wallet/staking-pools", "getSumXeqStaked", error.stack || error)
    //   }
    // }

    const setPreset = async (option) => {
      try {
        operator_id.value = option.address
      } catch (error) {
        await api.error("components/settings_general", "setPreset", error.stack || error)
      }
    }

    return {
      t,
      setPreset,
      nodeDuration,
      nodeReward,
      personalNodeRewards,
      monthlyYield,
      percentageOfPool,
      node_filter_options,
      node_filter_option,
      confirmSend,
      oracleKey,
      oracleAddress,
      maxAmount,
      node_id,
      operator_id,
      stake_amount,
      tvl,
      stake_data,
      current_price,
      theme,
      pool_count,
      state,
      PoolListTabular,
      maxHeight,
      address_book
    }
  }
})
</script>

<style scoped>
  .scroller {
    max-height: v-bind(maxHeight);
    overflow: auto;
  }
</style>

<style lang="scss">
</style>
