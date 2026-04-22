<template>
  <q-page class="receive">
    <q-list
      link
      no-border
      :dark="theme == 'dark'"
      class="arqma-list"
    >
      <div class="scroller">
        <div
          :visible="false"
          class="fit column"
        >
          <q-item-label header>
            {{ $t('pages.wallet.receive.my_primary_address') }}
          </q-item-label>
          <ReceiveItem
            v-for="address in address_list.primary"
            :key="address.address"
            class="primary-address"
            :address="address"
            :sublabel="$t('pages.wallet.receive.sub_label')"
            :show-q-r="showQR"
            :copy-address="copyAddress"
            :details="details"
            white-q-r-icon
          />

          <template v-if="address_list.used.length">
            <q-item-label header>
              {{ $t('pages.wallet.receive.my_used_addresses') }}
            </q-item-label>
            <ReceiveItem
              v-for="address in address_list.used"
              :key="address.address"
              :address="address"
              :sublabel="`${t('pages.wallet.receive.sub_address_label')}&nbsp;${address.address_index}`"
              :show-q-r="showQR"
              :copy-address="copyAddress"
              :details="details"
            />
          </template>

          <template v-if="address_list.unused.length">
            <q-item-label header>
              {{ $t('pages.wallet.receive.my_unused_addresses') }}
            </q-item-label>
            <ReceiveItem
              v-for="address in address_list.unused"
              :key="address.address"
              :address="address"
              :sublabel="`${t('pages.wallet.receive.my_unused_address')}&nbsp;${address.address_index}`"
              :show-q-r="showQR"
              :copy-address="copyAddress"
              :details="details"
              :should-show-info="false"
            />
          </template>
        </div>
      </div>
    </q-list>
    <AddressDetails ref="addressDetails" />

    <!-- QR Code -->
    <template v-if="QR.address != null">
      <q-dialog
        v-model="QR.visible"
        transition-show="flip-up"
        transition-hide="flip-down"
        :content-class="'qr-code-modal'"
      >
        <q-card class="qr-code-card">
          <div
            class="text-center q-mb-sm q-pa-md"
            style="background: white"
          >
            <QrcodeVue
              ref="qr"
              :value="QR.address"
              :size="200"
              render-as="svg"
            />
            <q-menu
              context-menu
              transition-show="flip-up"
              transition-hide="flip-down"
            >
              <q-list class="context-menu">
                <q-item
                  v-close-popup
                  clickable
                  @click="copyQR()"
                >
                  <q-item-section>{{ $t('pages.wallet.receive.copy_qr_code') }}</q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="saveQR()"
                >
                  <q-item-section>{{ $t('pages.wallet.receive.save_qr_code') }}</q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </div>
          <q-card-actions class="row justify-end items-center">
            <q-btn
              color="positive"
              :label="$t('pages.wallet.receive.close')"
              @click="QR.visible = false"
            />
          </q-card-actions>
        </q-card>
      </q-dialog>
    </template>
  </q-page>
</template>

<script>
import { computed, defineComponent, ref, onBeforeUnmount, onBeforeMount } from "vue"
import { useStore } from "vuex"
import QrcodeVue from "qrcode.vue"
import AddressDetails from "components/address_details"
import ReceiveItem from "components/receive_item"
import { useQuasar } from "quasar"
import { useDebounce } from "src/composables/debounce"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Receive",
  components: {
    AddressDetails,
    QrcodeVue,
    ReceiveItem
  },
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const { debounce } = useDebounce()
    const addressDetails = ref(null)
    const show = ref(false)
    const qr = ref(null)
    const QR = ref({
      visible: false,
      address: null,
      show: false,
      showMessage: t("pages.wallet.receive.show_unused_addresses")
    })
    const maxHeight = ref(`${Number(document.documentElement.clientHeight) - 230}px`)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const address_list = computed(() => $store.state.gateway.wallet.address_list)

    // Hooks
    onBeforeUnmount(() => {
      try {
        const clientHeight = document.documentElement.clientHeight
        maxHeight.value = `${Number(clientHeight) - 230}px`
        window.removeEventListener("resize", debouncedFn)
      } catch (error) {
        api.error("/pages/wallet/receive", "onBeforeUnmount", error.stack || error)
      }
    })

    onBeforeMount(() => {
      try {
        window.addEventListener("resize", debouncedFn)
      } catch (error) {
        api.error("/pages/wallet/receive", "onBeforeMounted", error.stack || error)
      }
    })

    // Methods
    const debouncedFn = debounce(() => {
      const clientHeight = document.documentElement.clientHeight
      maxHeight.value = `${Number(clientHeight) - 230}px`
    }, 500)

    const showUnused = () => {
      try {
        show.value = !show.value
        // TODO: fix $forceUpdate()
        //   $forceUpdate()
      } catch (error) {
        api.error("/pages/wallet/receive", "showUnused", error.stack || error)
      }
    }

    const details = async (address) => {
      try {
        await $store.dispatch("gateway/set_transactions_filter", { label: "Receive", value: (c) => (c.subaddr_index && c.subaddr_index.minor === address.address_index) || (c.destinations && c.destinations.some(addr => addr.address === address.address)) })
        addressDetails.value.address = address
        addressDetails.value.isVisible = true
      } catch (error) {
        await api.error("/pages/wallet/receive", "details", error.stack || error)
      }
    }

    const showQR = async (address, event) => {
      try {
        event.stopPropagation()
        QR.value.visible = true
        QR.value.address = address
      } catch (error) {
        await api.error("/pages/wallet/receive", "showQR", error.stack || error)
      }
    }

    const copyQR = async () => {
      try {
        const svg = qr.value.$el.outerHTML
        api.writeText(svg)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: t("pages.wallet.receive.copied_qr_code_to_clipboard")
        })
      } catch (error) {
        await api.error("/pages/wallet/receive", "copyQR", error.stack || error)
      }
    }

    const saveQR = async () => {
      try {
        const svg = qr.value.$el.outerHTML
        api.send("core", "save_svg", { svg, type: "QR Code" })
      } catch (error) {
        await api.error("/pages/wallet/receive", "saveQR", error.stack || error)
      }
    }

    const copyAddress = async (address, event) => {
      try {
        event.stopPropagation()
        api.writeText(address)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: t("pages.wallet.receive.address_copied_to_clipboard")
        })
      } catch (error) {
        await api.error("/pages/wallet/receive", "copyAddress", error.stack || error)
      }
    }

    return {
      t,
      addressDetails,
      show,
      qr,
      QR,
      theme,
      address_list,
      showUnused,
      details,
      showQR,
      copyQR,
      saveQR,
      copyAddress,
      AddressDetails,
      QrcodeVue,
      ReceiveItem,
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
.qr-options-menu {
  min-width: 150px;
  max-height: 300px;
  color: white;
}

.receive {
    margin: 8px;
  .q-item-label {
    font-weight: 400;
  }

  .arqma-list-item {
    cursor: pointer;

    .q-item-section {
      display: flex;
      justify-content: center;
      align-items: center;
    }

    .info {
      span {
        font-size: 14px;
      }

      .value {
        font-size: 16px;
        font-weight: bold;
      }
    }
  }
}
</style>
