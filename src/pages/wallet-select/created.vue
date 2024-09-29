<template>
  <q-page
    padding
    class="created"
  >
    <div class="col wallet q-mb-lg">
      <h6>{{ walletName }}</h6>
      <div class="row items-center">
        <div class="col address">
          {{ info.address }}
        </div>
        <div class="q-item-side">
          <q-btn
            color="primary"
            padding="xs"
            size="sm"
            icon="file_copy"
            @click="copyAddress(info.address, $event)"
          >
            <q-tooltip
              anchor="center left"
              self="center right"
              :offset="[5, 10]"
            >
              {{ $t('pages.wallet_select.created.copy_address') }}
            </q-tooltip>
          </q-btn>
        </div>
      </div>
    </div>

    <template v-if="secret.mnemonic">
      <div class="seed-box col">
        <h6 class="q-mb-xs q-mt-lg">
          {{ $t('pages.wallet_select.created.seed_words') }}
        </h6>
        <div class="seed q-my-lg">
          {{ secret.mnemonic }}
        </div>
        <div class="q-my-md warning">
          {{ $t('pages.wallet_select.created.save_to_secure_location') }}
        </div>
        <div>
          <q-btn
            color="primary"
            size="md"
            icon="file_copy"
            :label="$t('pages.wallet_select.created.copy_seed_words')"
            @click="copyPrivateKey('mnemonic', $event)"
          />
        </div>
      </div>
    </template>

    <q-expansion-item
      :label="$t('pages.wallet_select.created.advanced')"
      header-class="q-mt-sm non-selectable row reverse advanced-options-label"
    >
      <template v-if="secret.view_key != secret.spend_key">
        <h6 class="q-mb-xs title">
          {{ $t('pages.wallet_select.created.view_key') }}
        </h6>
        <div class="row">
          <div
            class="col"
            style="word-break: break-all"
          >
            {{ secret.view_key }}
          </div>
          <div class="q-item-side">
            <q-btn
              color="primary"
              padding="xs"
              size="sm"
              icon="file_copy"
              @click="copyPrivateKey('view_key', $event)"
            >
              <q-tooltip
                anchor="center left"
                self="center right"
                :offset="[5, 10]"
              >
                {{ $t('pages.wallet_select.created.copy_view_key') }}
              </q-tooltip>
            </q-btn>
          </div>
        </div>
      </template>

      <template v-if="!/^0*$/.test(secret.spend_key)">
        <h6 class="q-mb-xs title">
          {{ $t('pages.wallet_select.created.spend_key') }}
        </h6>
        <div class="row">
          <div
            class="col"
            style="word-break: break-all"
          >
            {{ secret.spend_key }}
          </div>
          <div class="q-item-side">
            <q-btn
              color="primary"
              padding="xs"
              size="sm"
              icon="file_copy"
              @click="copyPrivateKey('spend_key', $event)"
            >
              <q-tooltip
                anchor="center left"
                self="center right"
                :offset="[5, 10]"
              >
                {{ $t('pages.wallet_select.created.copy_spend_key') }}
              </q-tooltip>
            </q-btn>
          </div>
        </div>
      </template>
    </q-expansion-item>

    <q-btn
      class="q-mt-lg"
      color="positive"
      :label="$t('pages.wallet_select.created.open_account')"
      @click="open()"
    />
  </q-page>
</template>

<script>
import { computed, defineComponent } from "vue"
import { useRouter } from "vue-router"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Created",
  setup () {
    const router = useRouter()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const info = computed(() => $store.state.gateway.wallet.info)
    const secret = computed(() => $store.state.gateway.wallet.secret)
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const walletName = computed(() => {
      return `${t("pages.wallet_select.created.wallet")}: ${info.value.name}`
    })

    // Methods
    const open = async () => {
      try {
        await pause(1000)
        $store.commit("gateway/set_wallet_secret", {
          mnemonic: "",
          spend_key: "",
          view_key: ""
        })
        router.push({ path: "/wallet" })
      } catch (error) {
        await api.error("pages/wallet-select/created", "open", error.stack || error)
      }
    }

    const pause = (ms) => new Promise(resolve => setTimeout(resolve, ms))

    const copyAddress = async (address, event) => {
      try {
        event.stopPropagation()
        api.writeText(address)

        $q
          .dialog({
            title: t("pages.wallet_select.created.copy_address"),
            message: t("pages.wallet_select.created.copy_address_message"),
            ok: {
              label: t("pages.wallet_select.created.copy_address_ok_label"),
              color: "primary"
            },
            color: theme.value === "dark" ? "white" : "dark",
            dark: theme.value === "dark",
            transitionShow: "flip-up",
            transitionHide: "flip-down"
          })
          .onDismiss(() => {})
          .onCancel(() => {})
          .onOk(() => {
            $q.notify({
              type: "positive",
              timeout: 3000,
              message: t("pages.wallet_select.created.address_copied")
            })
          })
      } catch (error) {
        await api.error("pages/wallet-select/created", "copyAddress", error.stack || error)
      }
    }

    const copyPrivateKey = async (type, event) => {
      try {
        event.stopPropagation()
        if (secret.value[type] == null) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet_select.created.error_copying_private_key")
          })
          return
        }

        api.writeText(secret.value[type])
        const type_human =
        type.substring(0, 1).toUpperCase() +
        type.substring(1).replace("_", " ")

        $q
          .dialog({
            title: "Copy " + type_human,
            message: t("pages.wallet_select.created.private_key_warning_message"),
            ok: {
              label: t("pages.wallet_select.created.private_key_warning_ok_label"),
              color: "primary"
            },
            transitionShow: "flip-up",
            transitionHide: "flip-down",
            color: theme.value === "dark" ? "white" : "dark",
            dark: theme.value === "dark"
          })
          .onDismiss(() => {})
          .onCancel(() => {})
          .onOk(() => {
            $q.notify({
              type: "positive",
              timeout: 3000,
              message: type_human + t("pages.wallet_select.created.private_key_copied_message"),
              dark: theme.value === "dark"
            })
          })
      } catch (error) {
        await api.error("pages/wallet-select/created", "copyPrivateKey", error.stack || error)
      }
    }

    return {
      t,
      info,
      secret,
      theme,
      walletName,
      open,
      copyAddress,
      copyPrivateKey
    }
  }
})
</script>

<style lang="scss">
.created {
  .wallet h6 {
    text-align: center;
  }

  .address {
    text-align: center;
    word-break: break-all;
  }

  .seed-box {
    border: 1px solid white;
    border-radius: 3px;
    margin: 16px;
    padding: 16px;

    div,
    h6 {
      text-align: center;
    }

    .seed {
      font-size: 24px;
      text-transform: uppercase;
      font-weight: 600;
    }

    .warning {
      color: goldenrod;
    }
  }
  h6 {
    font-size: 18px;
    margin: 8px 0;
    font-weight: 450;
  }
  .advanced-options-label {
    padding-left: 0;
    padding-right: 0;
  }
}
</style>
