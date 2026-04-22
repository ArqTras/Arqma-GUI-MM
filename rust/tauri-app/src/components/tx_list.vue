<template>
  <div
    class="tx-list"
  >
    <template v-if="tx_list_filtered.length === 0">
      <p class="q-pa-md q-mb-none">
        {{ $t('components.tx_list.no_transactions_found') }}
      </p>
    </template>

    <template v-else>
      <q-list
        link
        no-border
        :dark="theme == 'dark'"
        class="column "
      >
        <q-item
          v-for="tx in tx_list_filtered"
          :key="`${tx.txid}-${tx.type}`"
          clickable
          class="arqma-list-item transaction"
          :class="'tx-' + tx.type"
          @click="details(tx)"
        >
          <q-item-section class="type">
            <div>{{ transactionTypeToString(tx.type) }}</div>
          </q-item-section>

          <q-item-label class="main">
            <q-item-label class="amount">
              <Formatarqma :amount="tx.amount" />
            </q-item-label>
            <q-item-label caption>
              {{ tx.txid }}
            </q-item-label>
          </q-item-label>

          <q-item-section class="meta">
            <q-item-label>
              <timeago
                :datetime="tx.timestamp * 1000"
                :auto-update="60"
              />
            </q-item-label>
            <q-item-label caption>
              {{ formatHeight(tx) }}
            </q-item-label>
          </q-item-section>

          <q-menu
            context-menu
            transition-show="flip-up"
            transition-hide="flip-down"
          >
            <q-list
              separator
              style="min-width: 150px; max-height: 300px"
            >
              <q-item
                v-close-popup
                clickable
                @click="details(tx)"
              >
                <q-item-section>{{ $t('components.tx_list.show_details') }}</q-item-section>
              </q-item>

              <q-item
                v-close-popup
                clickable
                @click="copyTxid(tx.txid, $event)"
              >
                <q-item-section>{{ $t('components.tx_list.copy_transaction_id') }}</q-item-section>
              </q-item>

              <q-item
                v-close-popup
                clickable
                @click="openExplorer(tx.txid)"
              >
                <q-item-section>{{ $t('components.tx_list.view_on_explorer') }}</q-item-section>
              </q-item>
            </q-list>
          </q-menu>
        </q-item>
        <div class="row justify-center align-center">
          <!-- <q-spinner-dots
              color="positive"
              :size="60"
            /> -->
        </div>
      </q-list>
      <!-- </q-infinite-scroll> -->
    </template>
    <TxDetails ref="txDetails" />
  </div>
</template>

<script>
import { computed, defineComponent, toRefs, ref, watch, onMounted, nextTick } from "vue"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import TxDetails from "components/tx_details"
import Formatarqma from "components/format_arqma"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "TxList",
  components: {
    TxDetails,
    Formatarqma
  },
  props: {
    limit: {
      type: Number,
      required: false,
      default: -1
    }
  },
  setup (props) {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const { limit } = toRefs(props)
    const page = ref(0)

    const amount = ref(25)
    const scroller = ref(null)
    const txDetails = ref(null)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const current_height = computed(() => $store.state.gateway.daemon.info.height)
    const wallet_height = computed(() => $store.state.gateway.wallet.info.height)
    const tx_list = computed(() => $store.state.gateway.wallet.transactions.tx_list)
    const transactions_filter = computed(() => $store.state.gateway.transactions_filter)
    const transaction_id_filter = computed(() => $store.state.gateway.transaction_id_filter)

    const tx_list_filtered = ref([])

    // Watchers
    const tx_listWatcher = watch(tx_list, async (newVal, oldVal) => {
      try {
        tx_list_filtered.value = $store.getters["gateway/filtered_transactions"]
      } catch (error) {
        await api.error("components/tx_list", "tx_listWatcher", error.stack || error)
      }
    })

    const transactions_filterWatcher = watch(transactions_filter, async (newVal, oldVal) => {
      try {
        tx_list_filtered.value = $store.getters["gateway/filtered_transactions"]
      } catch (error) {
        await api.error("components/tx_list", "transactions_filterWatcher", error.stack || error)
      }
    })

    const transaction_id_filterWatcher = watch(transaction_id_filter, async (newVal, oldVal) => {
      try {
        tx_list_filtered.value = $store.getters["gateway/filtered_transactions"]
      } catch (error) {
        await api.error("components/tx_list", "transaction_id_filterWatcher", error.stack || error)
      }
    })

    onMounted(() => {
      tx_list_filtered.value = $store.getters["gateway/filtered_transactions"]
    })

    // Methods
    const transactionTypeToString = (value) => {
      switch (value) {
        case "in":
          return t("components.tx_list.received")
        case "out":
          return t("components.tx_list.sent")
        case "failed":
          return t("components.tx_list.failed")
        case "pending":
        case "pool":
          return t("components.tx_list.pending")
        case "miner":
          return t("components.tx_list.miner")
        case "snode":
          return t("components.tx_list.service_node")
        case "stake":
          return t("components.tx_list.stake")
        case "net":
          return t("components.tx_list.network")
        default:
          return "-"
      }
    }

    const addmore = async () => {
      try {
        amount.value += 25
      } catch (error) {
        await api.error("components/tx_list", "addmore", error.stack || error)
      }
    }

    const loadMore = async (index, done) => {
      try {
        page.value = index
        if (
          limit.value !== -1 ||
              tx_list_filtered.value.length < page.value * 24 + 24
        ) {
          scroller.value.stop()
        }

        await nextTick()
        done()
      } catch (error) {
        await api.error("components/tx_list", "loadMore", error.stack || error)
      }
    }

    const details = (tx) => {
      try {
        txDetails.value.tx = tx
        txDetails.value.txNotes = tx.note
        txDetails.value.isVisible = true
      } catch (error) {
        api.error("components/tx_list", "details", error.stack || error)
      }
    }

    const formatHeight = (tx) => {
      try {
        const height = tx.height
        const confirms = Math.max(0, wallet_height.value - height)
        if (height === 0) {
          return t("components.tx_list.pending")
        }
        if (confirms < Math.max(10, tx.unlock_time - height)) {
          return `${t("components.tx_list.height")} ${height} (${confirms} ${t("components.tx_list.confirm")}${
            confirms === 1 ? "" : "s"
          })`
        } else {
          return `${t("components.tx_list.height")} ${height} ${t("components.tx_list.confirmed")}`
        }
      } catch (error) {
        api.error("components/tx_list", "formatHeight", error.stack || error)
      }
    }

    const copyTxid = async (txid, event) => {
      try {
        event.stopPropagation()
        api.writeText(txid)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: t("components.tx_list.copied_transaction_id_to_clipboard")
        })
      } catch (error) {
        await api.error("components/tx_list", "copyTxid", error.stack || error)
      }
    }

    const openExplorer = async (txid) => {
      try {
        api.send("core", "open_explorer", { type: "tx", id: txid })
      } catch (error) {
        await api.error("components/tx_list", "openExplorer", error.stack || error)
      }
    }

    return {
      t,
      page,
      tx_list_filtered,
      amount,
      scroller,
      theme,
      current_height,
      wallet_height,
      transaction_id_filterWatcher,
      tx_listWatcher,
      transactions_filterWatcher,
      transactionTypeToString,
      addmore,
      loadMore,
      details,
      formatHeight,
      copyTxid,
      openExplorer,
      TxDetails,
      Formatarqma,
      txDetails
    }
  }
})
</script>

<style lang="scss">
</style>
