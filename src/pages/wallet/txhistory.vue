<template>
  <q-page>
    <div
      class="row q-pt-sm q-mx-md q-mb-sm items-end non-selectable"
    >
      <arqmaField
        class="col-10 q-px-sm"
        :label="$t('pages.wallet.txhistory.filter_by_transactionid')"
        :disable-menu="false"
      >
        <q-input
          v-model="tx_txid"
          :dark="theme == 'dark'"
          :placeholder="$t('pages.wallet.txhistory.filter_by_transactionid')"
          borderless
          dense
          :clearable="true"
        />
      </arqmaField>

      <arqmaField
        class="col-2"
        :label="$t('pages.wallet.txhistory.filter_by_transaction_type')"
      >
        <q-select
          v-model="tx_type"
          :dark="theme == 'dark'"
          :options="tx_type_options"
          :option-label="opt => Object(opt) === opt && 'label' in opt ? $t(opt.label) : ''"
          borderless
          dense
          transition-show="flip-up"
          transition-hide="flip-down"
        />
      </arqmaField>
    </div>

    <div
      class="row q-pt-sm q-mx-md q-mb-sm items-end non-selectable"
    >
      <div>{{ $t('pages.wallet.txhistory.transactions') }}</div>
    </div>

    <div class="scroller">
      <div
        :visible="false"
        class="fit column"
      >
        <TxList
          class="col"
          :txid="tx_txid"
        />
      </div>
    </div>
  </q-page>
</template>

<script>
import { defineComponent, ref, computed, watch, nextTick, onBeforeUnmount, onBeforeMount } from "vue"
import { useStore } from "vuex"
import TxList from "components/tx_list"
import arqmaField from "components/arqma_field"
import { extend } from "quasar"
import { useDebounce } from "src/composables/debounce"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "TxHistory",
  components: {
    TxList,
    arqmaField
  },
  setup () {
    const $store = useStore()
    const { t } = useI18n()
    const { debounce } = useDebounce()

    const tx_type = ref({ index: 0, label: t("pages.wallet.txhistory.all"), value: (c) => true })
    const tx_txid = ref("")

    const tx_type_options = ref([
      { index: 0, label: "pages.wallet.txhistory.all", value: (c) => true },
      { index: 1, label: "pages.wallet.txhistory.incoming", value: (c) => c.type === "in" },
      { index: 2, label: "pages.wallet.txhistory.outgoing", value: (c) => c.type === "out" },
      { index: 3, label: "pages.wallet.txhistory.pending", value: (c) => ["pending", "pool"].includes(c.type) },
      { index: 4, label: "pages.wallet.txhistory.service_node", value: (c) => c.type === "snode" },
      { index: 5, label: "pages.wallet.txhistory.stake", value: (c) => c.type === "stake" },
      { index: 6, label: "pages.wallet.txhistory.failed", value: (c) => c.type === "failed" }
    ])

    const standardFilters = tx_type_options.value.map(filter => filter.index)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const daysOfTransactions = ref(1)
    const currentFilter = computed(() => $store.getters["gateway/get_transactions_filter"])
    const current_tx_txid_filter = computed(() => $store.getters["gateway/get_transaction_id_filter"])

    const maxHeight = ref(`${Number(document.documentElement.clientHeight) - 400}px`)

    const debouncedFn = debounce(() => {
      const clientHeight = document.documentElement.clientHeight
      maxHeight.value = `${Number(clientHeight) - 400}px`
    }, 500)

    onBeforeMount(() => {
      try {
        const clientHeight = document.documentElement.clientHeight
        maxHeight.value = `${Number(clientHeight) - 400}px`
        window.addEventListener("resize", debouncedFn)
        if (!standardFilters.includes(currentFilter.value.index)) {
          tx_type.value = tx_type_options.value[0]
        } else {
          tx_type.value = currentFilter.value
        }
        if (!!current_tx_txid_filter.value) {
          tx_txid.value = current_tx_txid_filter.value.value
        }
        extend(false, daysOfTransactions, $store.getters["gateway/daysOfTransactions"])
      } catch (error) {
        api.error("/pages/wallet/txhistory", "onBeforeMount", error.stack || error)
      }
    })

    onBeforeUnmount(() => {
      try {
        window.removeEventListener("resize", debouncedFn)
      } catch (error) {
        api.error("/pages/wallet/txhistory", "onBeforeUnmount", error.stack || error)
      }
    })

    const daysOfTransactionsWatcher = watch(daysOfTransactions, async (newVal, oldVal) => {
      await api.send("core", "set_daysOfTransactions", { daysOfTransactions: newVal })
    })

    const tx_type_filterWatcher = watch(tx_type, async (newVal, oldVal) => {
      if (newVal !== oldVal) {
        await $store.dispatch("gateway/set_transactions_filter", newVal)
        await nextTick()
      }
    })

    const tx_txid_Watcher = watch(tx_txid, async (newVal, oldVal) => {
      if (newVal !== oldVal) {
        await $store.dispatch("gateway/set_transaction_id_filter", { index: 7, label: "Transaction", value: newVal })
        await nextTick()
      }
    })

    return {
      t,
      tx_type_filterWatcher,
      tx_txid_Watcher,
      theme,
      tx_type,
      tx_txid,
      tx_type_options,
      TxList,
      arqmaField,
      daysOfTransactions,
      daysOfTransactionsWatcher,
      maxHeight,
      debouncedFn
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
