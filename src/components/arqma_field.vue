<template>
  <div
    class="arqma-field"
    :class="{ disable, 'disable-hover': disableHover }"
  >
    <div
      v-if="label"
      class="label row items-center"
      :disabled="disable"
    >
      {{ label }}
      <span
        v-if="optional"
        class="optional"
      >(Optional)</span>
    </div>
    <div
      class="content row items-center"
      :class="{ error }"
    >
      <slot />
    </div>
    <div
      v-if="error && errorLabel"
      class="error-label"
      :disabled="disable"
    >
      {{ errorLabel }}
    </div>
  </div>
</template>

<script>
import { defineComponent } from "vue"

export default defineComponent({
  name: "ArqmaField",
  props: {
    label: {
      type: String,
      required: false,
      default: ""
    },
    error: {
      type: Boolean,
      required: false
    },
    errorLabel: {
      type: String,
      required: false,
      default: ""
    },
    optional: {
      type: Boolean,
      required: false
    },
    disable: {
      type: Boolean,
      required: false
    },
    disableHover: {
      type: Boolean,
      required: false
    }
  },
  setup (props) {
    return {}
  }
})
</script>

<style lang="scss">
.arqma-field {
    .label {
        margin: 6px 2px;
        font-weight: bold;
        font-size: 12px;

        // Disable text selection
        -webkit-user-select: none;
        user-select: none;
        cursor: default;

        .optional {
            font-weight: 400;
            margin-left: 4px;
        }
    }
    .content {
        border-radius: 3px;
        padding: 4px 4px;
        // min-height: 42px;

        > * {
            margin-right: 4px;
        }

        > *:last-child {
            margin-right: 0px;
        }

        .q-input,
        .q-select {
          flex: 1;

          margin: 0;

          * {
            color: white;
          }
        }

        .q-textarea {
            textarea {
                resize: none;
            }
        }

        .q-date {
          min-width: 100%;
          max-width: 100%;
        }

        .q-btn {
            padding: 8px 8px;
            font-size: 12px !important;
        }
    }
}
</style>
