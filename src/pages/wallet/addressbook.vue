<template>
  <q-page class="address-book">
    <div
      class="header row q-pt-md q-pb-xs q-mx-md q-mb-none items-center non-selectable"
    >
      {{ $t('pages.wallet.addressbook.address_book') }}
    </div>

    <template v-if="address_book_combined.length">
      <q-list
        link
        no-border
        :dark="theme == 'dark'"
        class="arqma-list"
      >
        <q-item
          v-for="entry in address_book_combined"
          :key="`${entry.address}-${entry.name}-${entry.payment_id}`"
          clickable
          class="arqma-list-item"
          @click="details(entry)"
        >
          <q-item-section>
            <q-item-label class="ellipsis">
              {{ entry.address }}
            </q-item-label>
            <q-item-label
              class="non-selectable"
              caption
            >
              {{ entry.name }}
            </q-item-label>
          </q-item-section>
          <q-item-section side>
            <q-item-label>
              <q-icon
                size="24px"
                :name="entry.starred ? 'star' : 'star_border'"
              />
              <q-btn
                color="positive"
                style="margin-left: 10px"
                :label="$t('pages.wallet.addressbook.send')"
                :disabled="view_only"
                @click="sendToAddress(entry, $event)"
              />
            </q-item-label>
          </q-item-section>

          <q-menu
            context-menu
            transition-show="flip-up"
            transition-hide="flip-down"
          >
            <q-list class="context-menu">
              <q-item
                v-close-popup
                clickable
                @click="details(entry)"
              >
                <q-item-section>{{ $t('pages.wallet.addressbook.show_details') }}</q-item-section>
              </q-item>

              <q-item
                v-close-popup
                clickable
                @click="sendToAddress(entry, $event)"
              >
                <q-item-section>{{ $t('pages.wallet.addressbook.send_to_address') }}</q-item-section>
              </q-item>

              <q-item
                v-close-popup
                clickable
                @click="copyAddress(entry, $event)"
              >
                <q-item-section>{{ $t('pages.wallet.addressbook.copy_address') }}</q-item-section>
              </q-item>
            </q-list>
          </q-menu>
        </q-item>
      </q-list>
    </template>
    <template v-else>
      <p class="q-ma-md">
        {{ $t('pages.wallet.addressbook.address_book_is_empty') }}
      </p>
    </template>

    <q-page-sticky
      position="bottom-right"
      :offset="[18, 18]"
    >
      <q-btn
        :disable="!is_ready"
        round
        color="positive"
        icon="add"
        @click="addEntry"
      />
    </q-page-sticky>
    <AddressBookDetails ref="addressBookDetails" />
  </q-page>
</template>

<script>
import { computed, defineComponent, ref } from "vue"
import { useRouter } from "vue-router"
import { useStore } from "vuex"
import { useQuasar, extend } from "quasar"
import AddressBookDetails from "components/address_book_details"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Addressbook",
  components: {
    AddressBookDetails
  },
  setup () {
    const $store = useStore()
    const router = useRouter()
    const $q = useQuasar()
    const { t } = useI18n()

    const addressBookDetails = ref(null)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const view_only = computed(() => $store.state.gateway.wallet.info.view_only)
    const address_book = computed(() => $store.state.gateway.wallet.address_list.address_book)
    const address_book_starred = computed(() => $store.state.gateway.wallet.address_list.address_book_starred)
    const is_ready = computed(() => $store.getters["gateway/isReady"])
    const address_book_combined = computed(() => {
      const starred = address_book_starred.value.map((a) => ({ ...a, starred: true }))
      return [...starred, ...address_book.value]
    })

    // Hooks

    // Methods
    const details = async (entry) => {
      try {
        await $store.dispatch("gateway/set_transactions_filter", { label: "AddressBook", value: (c) => (c.destinations && c.destinations.some(addr => addr.address === entry.address)) })
        addressBookDetails.value.placeholder = extend(true, {}, entry, { payment_id: "" })
        addressBookDetails.value.mode = "view"
        addressBookDetails.value.isVisible = true
      } catch (error) {
        await api.error("/pages/wallet/addressbook", "details", error.stack || error)
      }
    }

    const addEntry = async () => {
      try {
        addressBookDetails.value.mode = "new"
        addressBookDetails.value.isVisible = true
      } catch (error) {
        await api.error("/pages/wallet/addressbook", "addEntry", error.stack || error)
      }
    }

    const sendToAddress = async (address, event) => {
      try {
        event.stopPropagation()
        router.push({
          path: "/wallet/send",
          query: { address: address.address, payment_id: address.payment_id }
        })
      } catch (error) {
        await api.error("/pages/wallet/addressbook", "sendToAddress", error.stack || error)
      }
    }

    const copyAddress = async (entry, event) => {
      try {
        event.stopPropagation()
        api.writeText(entry.value.address)
        if (entry.value.payment_id) {
          $q
            .dialog({
              title: t("pages.wallet_select.import_view_only.payment_id_title"),
              message: t("pages.wallet_select.import_view_only.payment_id_message"),
              ok: {
                label: t("pages.wallet_select.import_view_only.payment_id_ok_label"),
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
                message: t("pages.wallet_select.import_view_only.payment_id_notify_message")
              })
            })
        } else {
          $q.notify({
            type: "positive",
            timeout: 3000,
            message: t("pages.wallet_select.import_view_only.payment_id_notify_message")
          })
        }
      } catch (error) {
        await api.error("/pages/wallet/addressbook", "copyAddress", error.stack || error)
      }
    }

    return {
      t,
      addressBookDetails,
      theme,
      view_only,
      address_book,
      address_book_starred,
      is_ready,
      address_book_combined,
      details,
      addEntry,
      sendToAddress,
      copyAddress,
      AddressBookDetails
    }
  }
})

</script>

<style lang="scss">
.address-book {
  .header {
    font-size: 14px;
    font-weight: 500;
  }

  .arqma-list-item {
    cursor: pointer;
    padding-top: 12px;
    padding-bottom: 12px;

    .q-item-sublabel {
      font-size: 14px;
    }

    .q-item-label {
      font-weight: 400;
    }

    .q-item-section {
      display: flex;
      justify-content: center;
      align-items: center;
      margin-left: 12px;
    }
  }
}
</style>
