<template>
  <q-list
    class="arqma-list-item"
    no-border
    @click="details(address)"
  >
    <q-item>
      <q-item-section class="flex">
        <q-item-label class="ellipsis">
          {{ address.address }}
        </q-item-label>
        <q-item-label
          v-if="sublabel"
          caption
          class="non-selectable"
        >
          {{ sublabel }}
        </q-item-label>
      </q-item-section>
      <q-item-section side>
        <div class="row">
          <q-btn
            style="margin-right: 4px"
            flat
            padding="xs"
            size="md"
            @click="showQR(address.address, $event)"
          >
            <img
              :src="qrImage"
              height="24"
            >
            <q-tooltip
              anchor="bottom right"
              self="top right"
              :offset="[0, 5]"
            >
              {{ $t('components.receive_item.show_qr_code') }}
            </q-tooltip>
          </q-btn>
          <q-btn
            flat
            padding="xs"
            size="md"
            icon="file_copy"
            @click="copyAddress(address.address, $event)"
          >
            <q-tooltip
              anchor="bottom right"
              self="top right"
              :offset="[0, 5]"
            >
              {{ $t('components.receive_item.copy_address') }}
            </q-tooltip>
          </q-btn>
        </div>
      </q-item-section>
    </q-item>
    <template v-if="shouldShowInfo">
      <q-separator />
      <q-item>
        <q-item-section>
          <div class="row info-section">
            <span class="col-sm-4">
              <span>{{ $t('components.receive_item.balance') }}</span>
              <br>
              <span class="value">{{ currency(address.balance) }}</span>
            </span>
            <span class="col-sm-4">
              <span>{{ $t('components.receive_item.unlocked_balance') }}</span>
              <br>
              <span class="value">{{
                currency(address.unlocked_balance)
              }}</span>
            </span>
            <span class="col-sm-4">
              <span>{{ $t('components.receive_item.unspent_outputs') }}</span>
              <br>
              <span class="value">{{
                address.num_unspent_outputs || 0
              }}</span>
            </span>
          </div>
        </q-item-section>
      </q-item>
    </template>
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
          @click="details(address)"
        >
          <q-item-section>{{ $t('components.receive_item.show_details') }}</q-item-section>
        </q-item>

        <q-item
          v-close-popup
          clickable
          @click="copyAddress(address.address, $event)"
        >
          <q-item-section>{{ $t('components.receive_item.copy_address') }}</q-item-section>
        </q-item>
      </q-list>
    </q-menu>
  </q-list>
</template>

<script>
import { computed, defineComponent, toRefs } from "vue"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "ReceiveItem",
  props: {
    address: {
      required: true,
      type: Object
    },
    sublabel: {
      type: String,
      required: false,
      default: ""
    },
    shouldShowInfo: {
      type: Boolean,
      required: false,
      default: true
    },
    showQR: {
      type: Function,
      required: true
    },
    copyAddress: {
      type: Function,
      required: true
    },
    details: {
      type: Function,
      required: true
    },
    whiteQRIcon: {
      type: Boolean,
      required: false,
      default: false
    }
  },
  setup (props) {
    const { address, sublabel, shouldShowInfo, showQR, copyAddress, details, whiteQRIcon } = toRefs(props)

    const { t } = useI18n()

    // Computed props
    const qrImage = computed(() => {
      const image = whiteQRIcon.value ? "qr-code" : "qr-code-grey"
      return `${image}.svg`
    })

    // Methods
    const currency = (value) => {
      try {
        if (isNaN(value)) {
          return "N/A"
        }
        const amount = value / 1e9
        return amount.toLocaleString()
      } catch (error) {
        api.error("components/receive_item", "currency", error.stack || error)
      }
    }

    const toString = (value) => {
      try {
        if (!!value || typeof value !== "number") {
          return "N/A"
        }
        return String(value)
      } catch (error) {
        api.error("components/receive_item", "toString", error.stack || error)
      }
    }

    return {
      t,
      qrImage,
      currency,
      toString
    }
  }
})
</script>

<style>
.into-section {
  max-height: 3rem;
}
</style>
