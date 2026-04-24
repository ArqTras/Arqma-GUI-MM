<template>
  <q-dialog
    v-model="isVisible"
    maximized
    transition-show="flip-up"
    transition-hide="flip-down"
  >
    <q-layout style="overflow:hidden;">
      <q-header
        class="row justify-between items-center"
        style="border-bottom: 1px solid white"
      >
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
          <q-toolbar-title> Address details </q-toolbar-title>
          <q-btn
            flat
            label="Show QR Code"
            @click="isQRCodeVisible = true"
          />
          <q-btn
            class="q-ml-sm"
            color="primary"
            label="Copy address"
            @click="copyAddress()"
          />
        </q-toolbar>
      </q-header>
      <q-page-container>
        <div class="layout-padding">
          <template v-if="address != null">
            <AddressHeader
              :address="address.address"
              :title="
                address.address_index == 0
                  ? $t('components.address_book_detail.address_header_primary_title')
                  : `${$t('components.address_book_detail.address_header_subaddress_title')} ${address.address_index} )`"
              :extra="`${t('components.address_book_detail.address_header_primary_title')} (${address.used ? t('components.address_book_detail.used') : t('components.address_book_detail.not_used')}) ${t('components.address_book_detail.this_address')}`"
              :show-copy="false"
            />

            <template v-if="address.used">
              <div
                class="row justify-between"
                style="max-width: 768px"
              >
                <div class="infoBox">
                  <div class="infoBoxContent">
                    <div class="text">
                      <span>{{ $t('components.address_book_detail.balance') }}</span>
                    </div>
                    <div class="value">
                      <span><Formatarqma :amount="address.balance || 0" /></span>
                    </div>
                  </div>
                </div>

                <div class="infoBox">
                  <div class="infoBoxContent">
                    <div class="text">
                      <span>{{ $t('components.address_book_detail.unlocked_balance') }}</span>
                    </div>
                    <div class="value">
                      <span><Formatarqma :amount="address.unlocked_balance || 0" /></span>
                    </div>
                  </div>
                </div>

                <div class="infoBox">
                  <div class="infoBoxContent">
                    <div class="text">
                      <span>{{ $t('components.address_book_detail.number_of_unspent_outputs') }}</span>
                    </div>
                    <div class="value">
                      <span>{{ address.num_unspent_outputs || 0 }}</span>
                    </div>
                  </div>
                </div>
              </div>
            </template>
            <template v-else>
              <div
                class="row justify-between"
                style="max-width: 768px"
              >
                <div class="infoBox">
                  <div class="infoBoxContent">
                    <div class="text">
                      <span>{{ $t('components.address_book_detail.balance') }}</span>
                    </div>
                    <div class="value">
                      <span>0</span>
                    </div>
                  </div>
                </div>

                <div class="infoBox">
                  <div class="infoBoxContent">
                    <div class="text">
                      <span>{{ $t('components.address_book_detail.unlocked_balance') }}</span>
                    </div>
                    <div class="value">
                      <span>0</span>
                    </div>
                  </div>
                </div>

                <div class="infoBox">
                  <div class="infoBoxContent">
                    <div class="text">
                      <span>{{ $t('components.address_book_detail.number_of_unspent_outputs') }}</span>
                    </div>
                    <div class="value">
                      <span>0</span>
                    </div>
                  </div>
                </div>
              </div>
            </template>

            <div class="q-mt-sm">
              <div class="non-selectable recent-transactions-wrapper">
                <q-icon
                  name="history"
                  size="24px"
                />
                <span class="vertical-middle q-ml-xs">{{ $t('components.address_book_detail.recent_incoming_tx_to_this_address') }}</span>
              </div>

              <div class="col scroller1">
                <!-- <div
                style="max-height: 400px; overflow: auto"
                class="col"
              > -->
                <div
                  :visible="false"
                  class="fit column"
                >
                  <TxList
                    :key="address.address"
                  />
                </div>
                <!-- :limit="5" -->
              </div>
              <!-- </div> -->
            </div>
          </template>
        </div>
      </q-page-container>
    </q-layout>

    <template v-if="address != null">
      <q-dialog
        v-model="isQRCodeVisible"
        transition-show="flip-up"
        transition-hide="flip-down"
        minimized
        :content-class="'qr-code-modal'"
      >
        <q-card class="qr-code-card">
          <div
            class="text-center q-mb-sm q-pa-md"
            style="background: white"
          >
            <qrcode-vue
              ref="qr"
              :value="address.address"
              :size="300"
              render-as="svg"
            />
            <q-menu
              context-menu
              transition-show="flip-up"
              transition-hide="flip-down"
            >
              <q-list
                link
                separator
                style="min-width: 150px; max-height: 300px"
              >
                <q-item
                  v-close-popup
                  @click="copyQR()"
                >
                  <q-item-label
                    :label="$t('components.address_book_detail.copy_qr_code')"
                  />
                </q-item>
                <q-item
                  v-close-popup
                  @click="
                    saveQR()"
                >
                  <q-item-label :label="$t('components.address_book_detail.save_qr_code')" />
                </q-item>
              </q-list>
            </q-menu>
          </div>
          <q-card-actions>
            <q-btn
              color="primary"
              :label="$t('components.address_book_detail.close')"
              @click="isQRCodeVisible = false"
            />
          </q-card-actions>
        </q-card>
      </q-dialog>
    </template>
  </q-dialog>
</template>

<script>
import { defineComponent, ref, onBeforeUnmount, onBeforeMount } from "vue"
import { useQuasar } from "quasar"
import AddressHeader from "components/address_header"
import Formatarqma from "components/format_arqma"
import QrcodeVue from "qrcode.vue"
import TxList from "components/tx_list"
import { useDebounce } from "src/composables/debounce"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "AddressDetails",
  components: {
    AddressHeader,
    TxList,
    Formatarqma,
    QrcodeVue
  },
  setup () {
    const $q = useQuasar()
    const { t } = useI18n()
    const { debounce } = useDebounce()

    const isVisible = ref(false)
    const isQRCodeVisible = ref(false)
    const address = ref(null)
    const qr = ref(null)
    const maxHeight1 = ref(`${Number(document.documentElement.clientHeight) - 400}px`)

    // Methods
    const debouncedFn = debounce(() => {
      const clientHeight = document.documentElement.clientHeight
      maxHeight1.value = `${Number(clientHeight) - 400}px`
    }, 500)

    const copyQR = async () => {
      try {
        const svg = qr.value.$el.outerHTML
        api.writeText(svg)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: t("components.address_book_detail.copied_qr_code_to_clipboard")
        })
      } catch (error) {
        await api.error("components/address_details", "copyQR", error.stack || error)
      }
    }

    onBeforeMount(() => {
      try {
        const clientHeight = document.documentElement.clientHeight
        maxHeight1.value = `${Number(clientHeight) - 400}px`
        window.addEventListener("resize", debouncedFn)
      } catch (error) {
        api.error("components/address_details", "onBeforeMount", error.stack || error)
      }
    })

    onBeforeUnmount(() => {
      try {
        window.removeEventListener("resize", debouncedFn)
      } catch (error) {
        api.error("components/address_details", "onBeforeUnmount", error.stack || error)
      }
    })

    const saveQR = async () => {
      try {
        const svg = qr.value.$el.outerHTML
        api.send("core", "save_svg", { svg, type: "QR Code" })
      } catch (error) {
        await api.error("components/address_details", "saveQR", error.stack || error)
      }
    }

    const copyAddress = async () => {
      try {
        api.writeText(address.value.address)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: $t("components.address_book_detail.address_copied_to_clipboard")
        })
      } catch (error) {
        await api.error("components/address_details", "copyAddress", error.stack || error)
      }
    }

    return {
      t,
      isVisible,
      isQRCodeVisible,
      address,
      qr,
      copyQR,
      saveQR,
      copyAddress,
      AddressHeader,
      TxList,
      Formatarqma,
      QrcodeVue,
      maxHeight1,
      debouncedFn
    }
  }
})
</script>

<style scoped>
  .scroller1 {
    max-height: v-bind(maxHeight1);
    overflow: auto;
  }
</style>

<style lang="scss">
/* .layout-padding {
    padding: 16px;
} */
</style>
