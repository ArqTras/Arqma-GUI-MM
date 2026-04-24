<template>
  <div
    v-if="type=='in'"
    class="tx-icon"
  >
    <q-icon
      name="call_received"
      size="40px"
      class="main-icon"
    />

    <q-tooltip
      v-if="tooltip"
      anchor="center right"
      self="center left"
      :offset="[10, 10]"
    >
      {{ $t('components.tx_type_icon.incoming_transaction') }}
    </q-tooltip>
  </div>
  <div
    v-else-if="type=='out'"
    class="tx-icon"
  >
    <q-icon
      name="call_made"
      size="40px"
      class="main-icon"
    />

    <q-tooltip
      v-if="tooltip"
      anchor="center right"
      self="center left"
      :offset="[10, 10]"
    >
      {{ $t('components.tx_type_icon.outgoing_transaction') }}
    </q-tooltip>
  </div>
  <div
    v-else-if="type=='pool'"
    class="tx-icon"
  >
    <q-icon
      name="call_received"
      size="40px"
      class="main-icon"
    />
    <q-icon
      name="access_time"
      size="14px"
      class="sub-icon"
    />

    <q-tooltip
      v-if="tooltip"
      anchor="center right"
      self="center left"
      :offset="[10, 10]"
    >
      {{ $t('components.tx_type_icon.pending_incoming_transaction') }}
    </q-tooltip>
  </div>
  <div
    v-else-if="type=='pending'"
    class="tx-icon"
  >
    <q-icon
      name="call_made"
      size="40px"
      class="main-icon"
    />
    <q-icon
      name="access_time"
      size="14px"
      class="sub-icon"
    />

    <q-tooltip
      v-if="tooltip"
      anchor="center right"
      self="center left"
      :offset="[10, 10]"
    >
      {{ $t('components.tx_type_icon.pending_outgoing_transaction') }}
    </q-tooltip>
  </div>
  <div
    v-else-if="type=='failed'"
    class="tx-icon"
  >
    <q-icon
      name="close"
      size="40px"
      class="main-icon"
      color="red"
    />

    <q-tooltip
      v-if="tooltip"
      anchor="center right"
      self="center left"
      :offset="[10, 10]"
    >
      {{ $t('components.tx_type_icon.failed_transaction') }}
    </q-tooltip>
  </div>
</template>

<script>
import { defineComponent } from "vue"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "TxTypeIcon",
  props: {
    type: {
      type: String,
      required: true
    },
    tooltip: {
      type: Boolean,
      default: true,
      required: false
    }
  },
  setup (props) {
    const { t } = useI18n()

    return {
      t
    }
  }
})
</script>

<style>
.tx-icon {
width: 32px;
height: 32px;
position:relative;
}
.tx-icon .main-icon {
margin: -4px 0 0 -4px;
}
.tx-icon .sub-icon {
width: 14px;
height: 14px;
position:absolute;
bottom: -3px;
right: 0;
}
</style>
