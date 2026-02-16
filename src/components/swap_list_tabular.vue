<template>
  <div
    class="swap-list-tabular"
  >
    <template v-if="signature_data.length === 0">
      <p class="q-pa-md q-mb-none">
        {{ $t('components.swap_list_tabular.no_signature_data_found') }}
      </p>
    </template>
    <template v-else>
      <q-list
        link
        no-border
        :dark="theme == 'dark'"
        class="column"
      >
        <q-item
          v-for="item in signature_data"
          :key="item.signature"
          class="arqma-list-item transaction"
        >
          <q-item-label class="col-1 main">
            <q-item-label class="meta">
              {{ $t('components.swap_list_tabular.network') }}
            </q-item-label>
            <q-item-label
              class="network-label"
              caption
            >
              {{ item.network }}
            </q-item-label>
          </q-item-label>

          <q-item-label class="col-4 main">
            <q-item-label class="meta">
              {{ $t('components.swap_list_tabular.block_hash') }}
            </q-item-label>
            <q-item-label
              class="network-label"
              caption
            >
              {{ item.blockHash }}
            </q-item-label>
          </q-item-label>

          <q-item-label class="col-5 main">
            <q-item-label class="meta">
              {{ $t('components.swap_list_tabular.transaction_hash') }}
            </q-item-label>
            <q-item-label
              class="network-label"
              caption
            >
              {{ item.transactionHash }}
            </q-item-label>
          </q-item-label>

          <q-item-label class="col-1 main">
            <q-item-label class="meta">
              {{ $t('components.swap_list_tabular.amount') }}
            </q-item-label>
            <q-item-label caption>
              {{ item.amountFormatted }}
            </q-item-label>
          </q-item-label>

          <q-item-section
            v-if="item.type === 'Exchange'"
            class="col-1 type justify-end items-center"
          >
            <div>
              <q-btn
                size="sm"
                color="positive"
                :label="$t('pages.wallet.swap.accept_transfer')"
                @click="completeExchange(item)"
              />
            </div>
          </q-item-section>
          <q-item-section
            v-else-if="item.type === 'AirDrop'"
            class="col-1 type justify-end items-center"
          >
            <div>
              <q-btn
                size="sm"
                color="primary"
                :label="$t('pages.wallet.swap.claim_air_drop')"
                @click="completeExchange(item)"
              />
            </div>
          </q-item-section>
          <q-item-section
            v-else-if="item.type === 'Processing'"
            class="col-1 type justify-end items-center"
          >
            <div>
              <q-btn
                size="sm"
                color="positive"
                :label="$t('pages.wallet.swap.processing')"
                class="no-pointer-events"
              />
            </div>
          </q-item-section>
          <q-item-section
            v-else
            class="col-1 type justify-end items-center"
          >
            <div>
              <q-btn
                size="sm"
                color="gray"
                :label="$t('pages.wallet.swap.queued')"
                class="no-pointer-events"
              />
            </div>
          </q-item-section>
        </q-item>
      </q-list>
    </template>
  </div>
</template>

<script>
import { computed, defineComponent } from "vue"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import arqmaField from "components/arqma_field"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "SwapListTabular",
  components: {
    arqmaField
  },
  emits: ["complete-exchange"],
  setup (props, { emit }) {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const signature_data = computed(() => $store.getters["gateway/signature_data"])
    const state = computed(() => {
      return $store.state
    })

    const completeExchange = (signature_data) => {
      emit("complete-exchange", signature_data)
    }

    return {
      t,
      completeExchange,
      theme,
      arqmaField,
      signature_data
    }
  }
})
</script>

  <style scoped lang="scss">
  .network-label {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 100%;
    display: block;
  }
  </style>
