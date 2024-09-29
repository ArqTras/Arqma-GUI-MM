<template>
  <q-dialog
    v-model="isVisible"
    maximized
    class="tx_details"
    transition-show="flip-up"
    transition-hide="flip-down"
  >
    <q-layout view="hHh Lpr lFf">
      <q-header class="row justify-between items-center tx_details_header">
        <q-toolbar
          color="dark"
          inverted
        >
          <q-btn
            flat
            round
            dense
            icon="reply"
            @click="isVisible = false"
          />
          <q-toolbar-title>{{ $t('components.tx_details.transaction_details') }}</q-toolbar-title>
          <q-btn
            flat
            class="q-mr-sm"
            :label="$t('components.tx_details.show_tx_details')"
            @click="showTxDetails"
          />
          <q-btn
            v-if="can_open"
            color="primary"
            :label="$t('components.tx_details.view_on_explorer')"
            @click="openExplorer"
          />
        </q-toolbar>
      </q-header>
      <q-page-container class="column tx_details_container">
        <div class="row items-center non-selectable">
          <div class="q-mr-sm">
            <TxTypeIcon
              :type="tx.type"
              :tooltip="false"
            />
          </div>

          <div
            v-if="tx.type == 'in'"
            :class="'tx-' + tx.type"
          >
            {{ $t('components.tx_details.incoming_transaction') }}
          </div>
          <div
            v-else-if="tx.type == 'out'"
            :class="'tx-' + tx.type"
          >
            {{ $t('components.tx_details.outgoing_transaction') }}
          </div>
          <div
            v-else-if="tx.type == 'pool'"
            :class="'tx-' + tx.type"
          >
            {{ $t('components.tx_details.pending_incoming_transaction') }}
          </div>
          <div
            v-else-if="tx.type == 'pending'"
            :class="'tx-' + tx.type"
          >
            {{ $t('components.tx_details.pending_outgoing_transaction') }}
          </div>
          <div
            v-else-if="tx.type == 'failed'"
            :class="'tx-' + tx.type"
          >
            {{ $t('components.tx_details.failed_transaction') }}
          </div>
        </div>

        <div
          class="row justify-between"
          style="max-width: 768px"
        >
          <div class="infoBox">
            <div class="infoBoxContent">
              <div class="text">
                <span>{{ $t('components.tx_details.amount') }}</span>
              </div>
              <div class="value">
                <span><Formatarqma
                  :amount="tx.amount"
                  raw-value
                /></span>
              </div>
            </div>
          </div>

          <div class="infoBox">
            <div class="infoBoxContent">
              <div class="text">
                <span>{{ $t('components.tx_details.fee') }}
                  <template v-if="tx.type == 'in' || tx.type == 'pool'">{{ $t('components.tx_details.paid_by_sender') }}</template></span>
              </div>
              <div class="value">
                <span><Formatarqma
                  :amount="tx.fee"
                  raw-value
                /></span>
              </div>
            </div>
          </div>

          <div class="infoBox">
            <div class="infoBoxContent">
              <div class="text">
                <span>{{ $t('components.tx_details.height') }}</span>
              </div>
              <div class="value">
                <span>{{ tx.height }}</span>
              </div>
            </div>
          </div>

          <div class="infoBox">
            <div class="infoBoxContent">
              <div class="text">
                <span>{{ $t('components.tx_details.timestamp') }}</span>
              </div>
              <div class="value">
                <span>{{ formatDate(tx.timestamp * 1000) }}</span>
              </div>
            </div>
          </div>
        </div>

        <div class="row q-mt-xs q-mb-none">
          <q-list
            class="column"
            no-border
          >
            <q-item
              header
              class="q-px-none"
            >
              {{ $t('components.tx_details.transaction_id') }}
            </q-item>
            <q-item class="row justify-start items-center q-px-none">
              <q-item-label class="col-auto non-selectable">
                {{ tx.txid }}
              </q-item-label>
              <q-btn
                class="col-auto copy-btn"
                color="positive"
                padding="xs"
                size="sm"
                icon="file_copy"
                @click="copyAddress(tx.txid, $event)"
              >
                <q-tooltip
                  anchor="center left"
                  self="center right"
                  :offset="[5, 10]"
                >
                  {{ $t('components.tx_details.copy_transaction_id') }}
                </q-tooltip>
              </q-btn>
              <q-menu
                context-menu
                transition-show="flip-up"
                transition-hide="flip-down"
              >
                <q-list
                  link
                  separator
                  class="context-menu"
                >
                  <q-item
                    v-close-popup
                    clickable
                    @click="copyAddress(tx.txid, $event)"
                  >
                    <q-item-section>{{ $t('components.tx_details.copy_transaction_id') }}</q-item-section>
                  </q-item>
                </q-list>
              </q-menu>
            </q-item>
          </q-list>
        </div>

        <div class="row q-mt-xs q-mb-none">
          <q-list no-border>
            <q-item
              header
              class="q-px-none"
            >
              {{ $t('components.tx_details.payment_id') }}
            </q-item>
            <q-item class="row justify-start items-center q-px-none">
              <q-item-label class="col-auto non-selectable">
                {{ tx.payment_id ? tx.payment_id : "N/A" }}
              </q-item-label>
              <q-btn
                v-if="!!tx.payment_id"
                class="col-auto copy-btn"
                color="positive"
                padding="xs"
                size="sm"
                icon="file_copy"
                @click="copyAddress(tx.payment_id, $event)"
              >
                <q-tooltip
                  anchor="center left"
                  self="center right"
                  :offset="[5, 10]"
                >
                  {{ $t('components.tx_details.copy_payment_id') }}
                </q-tooltip>
              </q-btn>
              <q-menu
                v-if="!!tx.payment_id"
                transition-show="flip-up"
                transition-hide="flip-down"
                context-menu
              >
                <q-list
                  link
                  separator
                  class="context-menu"
                >
                  <q-item
                    v-close-popup
                    clickable
                    @click="copyAddress(tx.payment_id, $event)"
                  >
                    <q-item-section>{{ $t('components.tx_details.copy_payment_id') }}</q-item-section>
                  </q-item>
                </q-list>
              </q-menu>
            </q-item>
          </q-list>
        </div>

        <div
          v-if="tx.type == 'in' || tx.type == 'pool'"
          class="row"
        >
          <q-list no-border>
            <q-item
              header
              class="q-px-none"
            >
              {{ $t('components.tx_details.incoming_transaction_sent_to') }}
            </q-item>
            <q-item class="row justify-start items-center q-px-none">
              <q-item-label>
                <q-item-label class="non-selectable">
                  {{ in_tx_address_used.address_index_text }}
                </q-item-label>
                <q-item-label class="monospace ellipsis">
                  {{ in_tx_address_used.address }}
                  <q-btn
                    class="col-auto copy-btn"
                    color="positive"
                    padding="xs"
                    size="sm"
                    icon="file_copy"
                    @click="copyAddress(in_tx_address_used.address, $event)"
                  >
                    <q-tooltip
                      anchor="center left"
                      self="center right"
                      :offset="[5, 10]"
                    >
                      {{ $t('components.tx_details.copy_primary_address') }}
                    </q-tooltip>
                  </q-btn>
                </q-item-label>
              </q-item-label>

              <q-menu
                context-menu
                transition-show="flip-up"
                transition-hide="flip-down"
              >
                <q-list
                  link
                  separator
                  class="context-menu"
                >
                  <q-item
                    v-close-popup
                    clickable
                    @click="copyAddress(in_tx_address_used.address, $event)"
                  >
                    <q-item-section>{{ $t('components.tx_details.copy_primary_address') }}</q-item-section>
                  </q-item>
                </q-list>
              </q-menu>
            </q-item>
          </q-list>
        </div>

        <div
          v-else-if="tx.type == 'out' || tx.type == 'pending'"
          class="row"
        >
          <q-list no-border>
            <q-item
              header
              class="q-px-none"
            >
              {{ $t('components.tx_details.outgoing_transaction_sent_to') }}
            </q-item>
            <template v-if="out_destinations">
              <q-item
                v-for="destination in out_destinations"
                :key="destination.address"
                class="q-px-none"
              >
                <q-item-label>
                  <q-item-label
                    header
                    class="q-px-none"
                  >
                    {{ destination.name }}
                  </q-item-label>
                  <q-item-label class="monospace ellipsis">
                    {{ destination.address }}
                  </q-item-label>
                  <q-item-label>
                    <Formatarqma :amount="destination.amount" />
                  </q-item-label>
                </q-item-label>
                <q-menu
                  context-menu
                  transition-show="flip-up"
                  transition-hide="flip-down"
                >
                  <q-list
                    separator
                    class="context-menu"
                  >
                    <q-item
                      v-close-popup
                      clickable
                      @click="copyAddress(destination.address, $event)"
                    >
                      <q-item-section>{{ $t('components.tx_details.copy_address') }}</q-item-section>
                    </q-item>
                  </q-list>
                </q-menu>
              </q-item>
            </template>
            <template v-else>
              <q-item class="q-px-none">
                <q-item-label>
                  <q-item-label header>
                    {{ $t('components.tx_details.destination_unknown') }}
                  </q-item-label>
                </q-item-label>
              </q-item>
            </template>
          </q-list>
        </div>

        <arqmaField
          class="col-auto"
          :label="$t('components.tx_details.transaction_notes')"
        >
          <q-input
            v-model.trim="txNotes"
            type="textarea"
            :dark="theme == 'dark'"
            class="full-width text-area-arqma"
            :placeholder="$t('components.tx_details.transaction_notes')"
            rows="5"
            borderless
            dense
            @paste="onPaste"
          />
        </arqmaField>

        <div class="row q-pa-md justify-end items-center">
          <q-btn
            :disable="!is_ready"
            :text-color="theme == 'dark' ? 'white' : 'dark'"
            :label="$t('components.tx_details.save_tx_notes')"
            color="positive"
            @click="saveTxNotes"
          />
        </div>
      </q-page-container>
    </q-layout>
  </q-dialog>
</template>

<script>
import { computed, defineComponent, ref } from "vue"
import { useStore } from "vuex"
import { useQuasar, date } from "quasar"
import arqmaField from "components/arqma_field"
import TxTypeIcon from "components/tx_type_icon"
import Formatarqma from "components/format_arqma"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "TxDetails",
  components: {
    TxTypeIcon,
    Formatarqma,
    arqmaField
  },
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const isVisible = ref(false)
    const txNotes = ref("")
    const tx = ref({
      address: "",
      amount: 0,
      double_spend_seen: false,
      fee: 0,
      height: 0,
      note: "",
      payment_id: "",
      subaddr_index: { major: 0, minor: 0 },
      timestamp: 0,
      txid: "",
      type: "",
      unlock_time: 0
    })

    // Validations

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const can_open = computed(() => {
      const { net_type } = $store.state.gateway.app.config.app
      return net_type.value !== "stagenet"
    })
    const in_tx_address_used = computed(() => {
      let i
      const used_addresses = $store.state.gateway.wallet.address_list.primary.concat(
        $store.state.gateway.wallet.address_list.used
      )
      for (i = 0; i < used_addresses.length; i++) {
        if (used_addresses[i].address_index === tx.value.subaddr_index.minor) {
          let address_index_text = ""
          if (used_addresses[i].address_index === 0) {
            address_index_text = t("components.tx_details.primary_address")
          } else {
            address_index_text =
              `${t("components.tx_details.incoming_transaction")}${used_addresses[i].address_index})`
          }
          return {
            address: used_addresses[i].address,
            address_index: used_addresses[i].address_index,
            address_index_text
          }
        }
      }
      return false
    })

    const out_destinations = async () => {
      try {
        if (!tx.value.destinations.value) return false
        let i, j
        const destinations = []
        const address_book = $store.state.gateway.wallet.address_list.address_book.value
        for (i = 0; i < tx.value.destinations.length; i++) {
          const destination = tx.value.destinations[i]
          destination.name = ""
          for (j = 0; j < address_book.length; j++) {
            if (destination.address === address_book[j].address) {
              const { name, description } = address_book[j]
              const separator = description === "" ? "" : " - "
              destination.name = `${name}${separator}${description}`
              break
            }
          }
          destinations.push(destination)
        }
        return destinations
      } catch (error) {
        await api.error("components/tx_details", "out_destinations ", error.stack || error)
      }
    }

    const is_ready = computed(() => {
      return $store.getters["gateway/isReady"]
    })

    // Methods
    const showTxDetails = async () => {
      try {
        $q
          .dialog({
            title: t("components.tx_details.transaction_details_title"),
            message: JSON.stringify(tx.value, null, 2),
            ok: {
              label: t("components.tx_details.transaction_details_ok_label"),
              color: "primary"
            },
            dark: theme.value === "dark",
            style: "min-width: 500px; overflow-wrap: break-word;",
            transitionShow: "flip-up",
            transitionHide: "flip-down"
          })
          .onOk(() => {})
          .onCancel(() => {})
          .onDismiss(() => {})
      } catch (error) {
        await api.error("components/tx_details", "showTxDetails ", error.stack || error)
      }
    }

    const openExplorer = async () => {
      try {
        api.send("core", "open_explorer", {
          type: "tx",
          id: tx.value.txid
        })
      } catch (error) {
        await api.error("components/tx_details", "openExplorer ", error.stack || error)
      }
    }

    const saveTxNotes = async () => {
      try {
        // TODO: fix me! why display notification before sending to wallet?
        $q.notify({
          timeout: 3000,
          type: "positive",
          message: t("components.tx_details.save_transaction_notes_message")
        })
        api.send("wallet", "save_tx_notes", {
          txid: tx.value.txid,
          note: txNotes.value
        })
      } catch (error) {
        await api.error("components/tx_details", "saveTxNotes ", error.stack || error)
      }
    }

    const formatDate = (timestamp) => {
      try {
        return date.formatDate(timestamp, "YYYY-MM-DD hh:mm a")
      } catch (error) {
        api.error("components/tx_details", "formatDate ", error.stack || error)
      }
    }

    const copyAddress = async (address, event) => {
      try {
        event.stopPropagation()
        api.writeText(address)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: t("components.tx_details.copy_address_message")
        })
      } catch (error) {
        await api.error("components/tx_details", "copyAddress ", error.stack || error)
      }
    }

    const onPaste = async () => {
      try {
        await nextTick()
        txNotes.value = txNotes.value.trim()
      } catch (error) {
        await api.error("components/tx_details", "onPaste ", error.stack || error)
      }
    }

    return {
      t,
      isVisible,
      txNotes,
      tx,
      theme,
      can_open,
      in_tx_address_used,
      out_destinations,
      is_ready,
      showTxDetails,
      openExplorer,
      saveTxNotes,
      formatDate,
      copyAddress,
      onPaste,
      TxTypeIcon,
      Formatarqma,
      arqmaField
    }
  }
})
</script>

<style></style>
