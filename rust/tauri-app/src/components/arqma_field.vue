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
      ref="content"
      class="content row items-center"
      :class="{ error }"
      @contextmenu.prevent="showMenu"
    >
      <slot />
      <q-menu
        v-if="!disableMenu"
        v-model="menu"
        :context-menu="true"
      >
        <q-list>
          <q-item
            v-if="hasSelection"
            v-close-popup
            clickable
            @click="copyInput"
          >
            <q-item-section>Copy</q-item-section>
          </q-item>
          <q-item
            v-close-popup
            clickable
            @click="pasteInput"
          >
            <q-item-section>Paste</q-item-section>
          </q-item>
        </q-list>
      </q-menu>
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
import { defineComponent, ref } from "vue"
import { copyToClipboard } from "quasar"

export default defineComponent({
  name: "ArqmaField",
  props: {
    label: { type: String, required: false, default: "" },
    error: { type: Boolean, required: false },
    errorLabel: { type: String, required: false, default: "" },
    optional: { type: Boolean, required: false },
    disable: { type: Boolean, required: false },
    disableHover: { type: Boolean, required: false },
    disableMenu: { type: Boolean, required: false, default: true } // <-- added
  },
  setup (props) {
    const menu = ref(false)
    const content = ref(null)
    const hasSelection = ref(false)

    function showMenu (e) {
      if (!props.disableMenu) {
        // Wait for the selection to update
        setTimeout(() => {
          const input = content.value.querySelector("input, textarea")
          hasSelection.value = false
          if (input) {
            const selStart = input.selectionStart
            const selEnd = input.selectionEnd
            hasSelection.value = selStart !== selEnd
          }
          menu.value = true
        }, 0)
      }
    }

    function copyInput () {
      const input = content.value.querySelector("input, textarea")
      if (input) {
        const selStart = input.selectionStart
        const selEnd = input.selectionEnd
        if (selStart !== selEnd) {
          const selectedText = input.value.substring(selStart, selEnd)
          copyToClipboard(selectedText)
        }
      }
    }

    async function pasteInput () {
      const input = content.value.querySelector("input, textarea")
      if (input) {
        try {
          const text = await navigator.clipboard.readText()
          input.value = text
          input.dispatchEvent(new Event("input"))
        } catch (e) {}
      }
    }

    return { menu, showMenu, copyInput, pasteInput, content, hasSelection }
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
