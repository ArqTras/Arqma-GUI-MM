<template>
  <div>
    <q-item-section class="self-start">
      <q-item-label
        sublabel
        class="title"
      >
        {{ title }}
      </q-item-label>
      <q-item-label class="row">
        <q-item-section
          class="break-all"
          style="font-size: 18px"
        >
          {{ address }}
        </q-item-section>
        <q-item-section
          v-if="showCopy"
          side
        >
          <q-btn
            ref="copy"
            color="primary"
            padding="xs"
            size="sm"
            icon="file_copy"
            @click="copyAddress"
          >
            <q-tooltip
              anchor="center left"
              self="center right"
              :offset="[5, 10]"
            >
              {{ $t('components.address_header.copy_address') }}
            </q-tooltip>
          </q-btn>
        </q-item-section>
      </q-item-label>
      <q-item-label
        v-if="payment_id"
        header
      >
        {{ t('components.address_header.payment_id') }} {{ payment_id }}
      </q-item-label>
      <q-item-label
        v-if="extra"
        header
        class="extra non-selectable"
      >
        {{ extra }}
      </q-item-label>
    </q-item-section>

    <q-menu context-menu>
      <q-list
        separator
        class="context-menu"
      >
        <q-item
          v-close-popup
          clickable
          @click="copyAddress(/*address, $event*/)"
        >
          <q-item-section>{{ $t('components.address_header.copy_address') }}</q-item-section>
        </q-item>
      </q-list>
    </q-menu>
  </div>
</template>

<script>
import { defineComponent, ref, toRefs } from "vue"
import { useQuasar } from "quasar"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "AddressHeader",
  components: {},
  props: {
    title: {
      type: String,
      required: true
    },
    address: {
      type: String,
      required: true
    },
    paymentId: {
      type: String,
      required: false,
      default: ""
    },
    extra: {
      type: String,
      required: false,
      default: ""
    },
    showCopy: {
      type: Boolean,
      required: false,
      default: true
    }
  },
  setup (props) {
    const $q = useQuasar()
    const { t } = useI18n()

    const { title, address, paymentId, extra, showCopy } = toRefs(props)
    const payment_id = ref("")
    const copy = ref(null)

    // Methods
    const copyAddress = async () => {
      try {
        copy.value.$el.blur()
        api.writeText(address.value)
        if (payment_id.value) {
          $q
            .dialog({
              title: t("components.address_header.copy_address"),
              message: t("components.address_header.copy_address_message"),
              ok: {
                label: t("components.address_header.copy_address_ok_label"),
                color: "positive"
              },
              transitionShow: "flip-up",
              transitionHide: "flip-down"
            })
            .onDismiss(() => {})
            .onCancel(() => {})
            .onOk(() => {
              $q.notify({
                type: "positive",
                timeout: 3000,
                message: t("components.address_header.copy_address_ok_message")
              })
            })
        } else {
          $q.notify({
            type: "positive",
            timeout: 3000,
            message: t("components.address_header.copy_address_ok_message")
          })
        }
      } catch (error) {
        await api.error("components/address_header", "copyAddress", error.stack || error)
      }
    }

    return {
      t,
      payment_id,
      copy,
      copyAddress
    }
  }
})
</script>

<style lang="scss">
.title {
  font-size: 18px;
  margin-bottom: 4px;
}

.extra {
  margin-top: 8px;
}

.address-header {
  padding: 0;
  img {
    float: left;
    margin-right: 15px;
  }
  h3 {
    margin: 15px 0 0;
  }
  p {
    word-break: break-all;
  }

  &::after {
    content: "";
    clear: both;
    display: table;
  }

  .q-item-label {
    .q-item-label {
      font-weight: 400;
    }
  }
}
</style>
