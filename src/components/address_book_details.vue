<template>
  <q-dialog
    v-model="isVisible"
    maximized
    class="address-book-details"
    transition-show="flip-up"
    transition-hide="flip-down"
  >
    <q-layout v-if="mode == 'edit' || mode == 'new'">
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
            @click="close()"
          />
          <q-toolbar-title v-if="mode == 'new'">
            {{ $t('components.address_book_details.add_address_book_entry') }}
          </q-toolbar-title>
          <q-toolbar-title v-else-if="mode == 'edit'">
            {{ $t('components.address_book_details.edit_address_book_entry') }}
          </q-toolbar-title>

          <q-btn
            v-if="mode == 'edit'"
            color="red flat no-ripple"
            :label="$t('components.address_book_details.cancel')"
            @click="cancelEdit()"
          />
          <q-btn
            class="q-ml-sm"
            color="positive"
            :label="$t('components.address_book_details.save')"
            @click="save()"
          />
        </q-toolbar>
      </q-header>

      <q-page-container>
        <div class="address-book-modal q-mx-md">
          <arqmaField
            :label="$t('components.address_book_details.address')"
            :error="v$.address.$error"
          >
            <q-input
              v-model.trim="newEntry.address"
              :placeholder="placeholder.address"
              :dark="theme == 'dark'"
              borderless
              dense
              @blur="v$.address.$validate()"
            />
            <q-btn
              v-model.trim="newEntry.starred"
              flat
              round
              :icon="newEntry.starred ? 'star' : 'star_border'"
              @click="updateStarred"
            />
          </arqmaField>
          <arqmaField
            :label="$t('components.address_book_details.name')"
            :error="v$.name.$error"
          >
            <q-input
              v-model="newEntry.name"
              :placeholder="placeholder.name"
              :dark="theme == 'dark'"
              borderless
              dense
              @blur="v$.name.$validate()"
            />
          </arqmaField>
          <arqmaField
            :label="$t('components.address_book_details.payment_id')"
            optional
            :error="v$.payment_id.$error"
          >
            <q-input
              v-model.trim="newEntry.payment_id"
              :placeholder="placeholder.payment_id"
              :dark="theme == 'dark'"
              borderless
              dense
              @blur="v$.payment_id.$validate()"
            />
          </arqmaField>
          <arqmaField
            :label="$t('components.address_book_details.notes')"
            optional
            :error="v$.description.$error"
          >
            <q-input
              v-model="newEntry.description"
              :placeholder="placeholder.description"
              type="textarea"
              class="full-width text-area-arqma"
              :dark="theme == 'dark'"
              borderless
              dense
              @blur="v$.description.$validate()"
            />
          </arqmaField>

          <q-btn
            v-if="mode == 'edit'"
            class="submit-button"
            color="red"
            :label="$t('components.address_book_details.delete')"
            @click="deleteEntry()"
          />
        </div>
      </q-page-container>
    </q-layout>

    <q-layout v-else>
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
            @click="close()"
          />
          <q-toolbar-title>{{ $t('components.address_book_details.cancel') }}</q-toolbar-title>
          <q-btn
            class="q-mr-sm"
            :disable="!is_ready"
            :label="$t('components.address_book_details.edit')"
            color="positive"
            @click="edit()"
          />
          <q-btn
            color="positive"
            :disabled="view_only"
            :label="$t('components.address_book_details.send_coins')"
            @click="sendToAddress(placeholder, $event)"
          />
        </q-toolbar>
      </q-header>
      <q-page-container>
        <div class="layout-padding">
          <template v-if="placeholder != null">
            <AddressHeader
              :address="placeholder.address"
              :title="placeholder.name"
              :payment_id="placeholder.payment_id"
              :extra="placeholder.description ? `${t('components.address_book_details.notes')}: ${placeholder.description}` : ''"
            />

            <div class="q-mt-lg">
              <div class="non-selectable">
                <q-icon
                  name="history"
                  size="24px"
                />
                <span class="vertical-middle q-ml-xs">{{ $t('components.address_book_details.recent_transactions_with_address') }}</span>
              </div>
              <TxList
                :key="placeholder.address"
                :limit="5"
              />
            </div>
          </template>
        </div>
      </q-page-container>
    </q-layout>
  </q-dialog>
</template>

<script>
import { computed, defineComponent, ref, reactive, watch } from "vue"
import { useStore } from "vuex"
import { useRouter } from "vue-router"
import { useQuasar, extend } from "quasar"
import AddressHeader from "components/address_header"
import TxList from "components/tx_list"
import arqmaField from "components/arqma_field"
import { useVuelidate } from "@vuelidate/core"
import { required, helpers } from "@vuelidate/validators"
import { payment_id, address } from "src/validators/common"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "AddressBookDetails",
  components: {
    AddressHeader,
    TxList,
    arqmaField
  },
  setup () {
    const router = useRouter()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const isVisible = ref(false)
    const mode = ref("view")

    const newEntry = reactive({
      index: false,
      address: "",
      payment_id: "",
      name: "",
      description: "",
      starred: false
    })

    const placeholder = ref({
      index: false,
      address: "a..",
      payment_id: t("components.address_book_details.payment_id_placeholder"),
      name: t("components.address_book_details.name"),
      description: t("components.address_book_details.additional_notes_placeholder"),
      starred: false
    })

    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const view_only = computed(() => $store.state.gateway.wallet.info.view_only)
    const is_ready = computed(() => $store.getters["gateway/isReady"])

    const modeWatcher = watch(mode, (newVal, oldVal) => {
      if (mode.value !== "new") {
        copyNewEntry(placeholder.value)
      } else {
        resetNewEntry()
      }
    })

    const mustNotContainDescriptionDelimiters = (value) => !value.includes("::")

    // Validations
    const rules = computed(() => {
      return {
        index: {},
        address: { required }, // TODO: validate address
        payment_id: { }, // TODO:  validate 16 and 64 hex
        name: {
          required,
          mustNotContainDescriptionDelimiters: helpers.withMessage(t("components.address_book_details.name_must_not_contain_colons"), mustNotContainDescriptionDelimiters)
        },
        description: {
          mustNotContainDescriptionDelimiters: helpers.withMessage(t("components.address_book_details.description_must_not_contain_colons"), mustNotContainDescriptionDelimiters)
        },
        starred: {}
      }
    })

    const v$ = useVuelidate(rules, newEntry)

    // Methods
    const save = async () => {
      try {
        await v$.value.$validate()

        if (v$.value.address.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("components.address_book_details.invalid_address")
          })
          return
        }

        if (v$.value.name.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: v$.value.name.$errors[0].$message
          })
          return
        }

        if (v$.value.description.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: v$.value.description.$errors[0].$message
          })
          return
        }
        api.send("wallet", "add_address_book", extend(true, {}, newEntry))
        resetNewEntry()
        close()
      } catch (error) {
        await api.error("components/address_book_details", "save", error.stack || error)
      }
    }

    const deleteEntry = async () => {
      try {
        const copy = extend(true, {}, newEntry)
        api.send("wallet", "delete_address_book", copy)
        close()
      } catch (error) {
        await api.error("components/address_book_details", "deleteEntry", error.stack || error)
      }
    }

    const sendToAddress = async (toAddress, event) => {
      try {
        router.push({
          path: "/wallet/send",
          query: {
            address: toAddress.address,
            payment_id: toAddress.payment_id
          }
        })
        close()
      } catch (error) {
        await api.error("components/address_book_details", "sendToAddress", error.stack || error)
      }
    }

    const edit = async () => {
      try {
        copyNewEntry(placeholder.value)
        mode.value = "edit"
      } catch (error) {
        await api.error("components/address_book_details", "edit", error.stack || error)
      }
    }

    const copyNewEntry = (toCopy) => {
      newEntry.index = toCopy.index
      newEntry.address = toCopy.address
      newEntry.payment_id = toCopy.payment_id
      newEntry.name = toCopy.name
      newEntry.description = toCopy.description
      newEntry.starred = toCopy.starred
    }

    const resetNewEntry = () => {
      placeholder.value.index = false
      placeholder.value.address = "T.."
      placeholder.value.payment_id = t("components.address_book_details.recent_transactions_with_address")
      placeholder.value.name = t("components.address_book_details.name")
      placeholder.value.description = t("components.address_book_details.additional_notes_placeholder")
      placeholder.value.starred = false
      copyNewEntry(placeholder)
    }

    const cancelEdit = async () => {
      try {
        mode.value = "view"
        v$.value.$reset()
        // resetNewEntry()
      } catch (error) {
        await api.error("components/address_book_details", "cancelEdit", error.stack || error)
      }
    }

    const updateStarred = async () => {
      try {
        newEntry.starred = !newEntry.starred
      } catch (error) {
        await api.error("components/address_book_details", "updateStarred", error.stack || error)
      }
    }

    const close = async () => {
      try {
        isVisible.value = false
        v$.value.$reset()
        mode.value = ""
        resetNewEntry()
      } catch (error) {
        await api.error("components/address_book_details", "close", error.stack || error)
      }
    }

    return {
      t,
      v$,
      isVisible,
      mode,
      newEntry,
      theme,
      view_only,
      is_ready,
      save,
      deleteEntry,
      sendToAddress,
      edit,
      cancelEdit,
      updateStarred,
      close,
      placeholder,
      modeWatcher
    }
  }
})
</script>

<style lang="scss">
.address-book-details {
  .address-book-modal {
    > .arqma-field {
      margin-top: 16px;
    }

    .star-entry {
      padding: 4px;
    }
  }
}
.layout-padding {
    padding: 16px;
}
</style>
