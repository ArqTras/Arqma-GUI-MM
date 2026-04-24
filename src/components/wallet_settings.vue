<template>
  <div class="wallet-settings">
    <q-btn
      icon-right="more_vert"
      :label="$t('components.wallet_settings.settings')"
      size="md"
      flat
    >
      <q-menu
        anchor="bottom right"
        self="top right"
        transition-show="flip-up"
        transition-hide="flip-down"
      >
        <q-list
          separator
          class="menu-list"
        >
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="getPrivateKeys()"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.show_private_keys') }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="showModal('change_password')"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.change_password') }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="showModal('rescan')"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.rescan_account') }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="showModal('sweep_all')"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.sweep_all') }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="showModal('key_image')"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.manage_key_images') }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="deleteWallet()"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.delete_account') }}
            </q-item-label>
          </q-item>
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="showModal('export_transactions')"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.export_transactions') }}
            </q-item-label>
          </q-item>
          <!-- :disable="!is_ready" -->
          <q-item
            v-close-popup
            clickable
            :disable="!is_ready"
            @click="showModal('register_servicenode')"
          >
            <q-item-label header>
              {{ $t('components.wallet_settings.register_service_node') }}
            </q-item-label>
          </q-item>
        </q-list>
      </q-menu>
    </q-btn>

    <q-dialog
      v-model="modals.private_keys.visible"
      minimized
      class="private-key-modal"
      transition-show="flip-up"
      transition-hide="flip-down"
      @hide="closePrivateKeys()"
    >
      <q-card :dark="theme == 'dark'">
        <q-card-section>
          <div class="text-h6">
            {{ $t('components.wallet_settings.show_private_keys') }}
          </div>
        </q-card-section>
        <q-card-section>
          <template v-if="secret.mnemonic">
            <h6 class="q-mb-xs q-mt-lg">
              {{ $t('components.wallet_settings.seed_words') }}
            </h6>
            <div class="row">
              <div class="col">
                {{ secret.mnemonic }}
              </div>
              <div class="col-auto">
                <q-btn
                  class="copy-btn"
                  color="positive"
                  padding="xs"
                  size="sm"
                  icon="file_copy"
                  @click="copyPrivateKey('mnemonic', $event)"
                >
                  <q-tooltip
                    anchor="center left"
                    self="center right"
                    :offset="[5, 10]"
                  >
                    {{ $t('components.wallet_settings.copy_seed_words') }}
                  </q-tooltip>
                </q-btn>
              </div>
            </div>
          </template>

          <template v-if="secret.view_key != secret.spend_key">
            <h6 class="q-mb-xs">
              {{ $t('components.wallet_settings.view_key') }}
            </h6>
            <div class="row">
              <div
                class="col"
                style="word-break: break-all"
              >
                {{ secret.view_key }}
              </div>
              <div class="col-auto">
                <q-btn
                  class="copy-btn"
                  color="positive"
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
                    {{ $t('components.wallet_settings.copy_view_key') }}
                  </q-tooltip>
                </q-btn>
              </div>
            </div>
          </template>

          <template v-if="!/^0*$/.test(secret.spend_key)">
            <h6 class="q-mb-xs">
              {{ $t('components.wallet_settings.spend_key') }}
            </h6>
            <div class="row">
              <div
                class="col"
                style="word-break: break-all"
              >
                {{ secret.spend_key }}
              </div>
              <div class="col-auto">
                <q-btn
                  class="copy-btn"
                  color="positive"
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
                    {{ $t('components.wallet_settings.copy_spend_key') }}
                  </q-tooltip>
                </q-btn>
              </div>
            </div>
          </template>
        </q-card-section>
        <q-card-actions class="row justify-end items-center">
          <q-btn
            color="positive"
            :label="$t('components.wallet_settings.close')"
            @click="hideModal('private_keys')"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog
      v-model="modals.rescan.visible"
      minimized
      transition-show="flip-up"
      transition-hide="flip-down"
    >
      <q-card :dark="theme == 'dark'">
        <q-card-section>
          <div class="a-ma-lg text-h6">
            {{ $t('components.wallet_settings.rescan_account') }}
          </div>
        </q-card-section>
        <q-card-section>
          <p>{{ $t('components.wallet_settings.scan_type_message') }}</p>

          <div class="q-mt-lg">
            <q-radio
              v-model="modals.rescan.type"
              val="full"
              :label="$t('components.wallet_settings.rescan_full_blockchain')"
            />
          </div>
          <div class="q-mt-sm">
            <q-radio
              v-model="modals.rescan.type"
              val="spent"
              :label="$t('components.wallet_settings.rescan_spent_outputs')"
            />
          </div>
        </q-card-section>

        <q-card-actions class="row justify-end items-center">
          <q-btn
            flat
            class="q-mr-sm"
            :label="$t('components.wallet_settings.close')"
            @click="hideModal('rescan')"
          />
          <q-btn
            color="red"
            :label="$t('components.wallet_settings.rescan')"
            @click="rescanWallet()"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog
      v-model="modals.sweep_all.visible"
      minimized
      :persistent="true"
      transition-show="flip-up"
      transition-hide="flip-down"
    >
      <q-card :dark="theme == 'dark'">
        <q-card-section>
          <div class="a-ma-lg text-h6">
            {{ modals.sweep_all.title }}
          </div>
        </q-card-section>
        <q-card-section>
          <q-card-section>
            <p>{{ modals.sweep_all.message }}</p>
          </q-card-section>
          <q-card-actions class="row justify-end items-center">
            <q-btn
              flat
              class="q-mr-sm"
              :label="modals.sweep_all.cancelLabel"
              @click="modals.sweep_all.cancel()"
            />
            <q-btn
              color="positive"
              :label="modals.sweep_all.proceedLabel"
              :disable="modals.sweep_all.loading"
              @click="modals.sweep_all.proceed()"
            />
          </q-card-actions>
        </q-card-section>
      </q-card>
    </q-dialog>

    <q-dialog
      v-model="modals.key_image.visible"
      class="key-image-modal"
      minimized
      transition-show="flip-up"
      transition-hide="flip-down"
    >
      <q-card :dark="theme == 'dark'">
        <q-card-section>
          <div class="text-h6">
            {{ modals.key_image.type }} {{ $t('components.wallet_settings.key_images') }}
          </div>
        </q-card-section>
        <q-card-section>
          <div class="q-mr-xl">
            <q-radio
              v-model="modals.key_image.type"
              val="Export"
              :label="$t('components.wallet_settings.export')"
            />
          </div>
          <div>
            <q-radio
              v-model="modals.key_image.type"
              val="Import"
              :label="$t('components.wallet_settings.import')"
            />
          </div>
        </q-card-section>

        <template v-if="modals.key_image.type == 'Export'">
          <q-card-section>
            <div class="q-mr-xl">
              <q-radio
                v-model="modals.key_image.all"
                :val="true"
                :label="$t('components.wallet_settings.export_all')"
              />
              <q-radio
                v-model="modals.key_image.all"
                :val="false"
                :label="$t('components.wallet_settings.export_since')"
              />
            </div>
          </q-card-section>
          <q-card-section>
            <arqmaField
              class="q-mt-lg"
              :label="$t('components.wallet_settings.key_image_export_directory')"
              disable-hover
            >
              <q-input
                v-model="modals.key_image.export_path"
                disable
                borderless
              />
              <input
                id="keyImageExportPath"
                ref="keyImageExportSelect"
                class="image-path"
                type="file"
                webkitdirectory
                directory
                hidden
                @change="setKeyImageExportPath"
              >
              <!-- <q-btn
                color="positive"
                @click="selectKeyImageExportPath"
              >
                {{ $t('components.wallet_settings.browse') }}
              </q-btn> -->
            </arqmaField>
          </q-card-section>
        </template>
        <template v-if="modals.key_image.type == 'Import'">
          <q-card-section>
            <arqmaField
              class="q-mt-lg"
              :label="$t('components.wallet_settings.key_image_import_file')"
              disable-hover
            >
              <q-input
                v-model="modals.key_image.import_path"
                disable
                borderless
              />
              <input
                id="keyImageImportPath"
                ref="keyImageImportSelect"
                class="image-path"
                type="file"
                hidden
                @change="setKeyImageImportPath"
              >
              <q-btn
                color="positive"
                @click="selectKeyImageImportPath"
              >
                {{ $t('components.wallet_settings.browse') }}
              </q-btn>
            </arqmaField>
          </q-card-section>
        </template>

        <q-card-actions class="row justify-end items-center">
          <q-btn
            flat
            class="q-mr-sm"
            :label="$t('components.wallet_settings.close')"
            @click="hideModal('key_image')"
          />
          <q-btn
            color="positive"
            :label="$t(`components.wallet_settings.${modals.key_image.type.toLowerCase()}`)"
            @click="doKeyImages()"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog
      v-model="modals.change_password.visible"
      minimized
      transition-show="flip-up"
      transition-hide="flip-down"
      @hide="clearChangePassword()"
    >
      <q-card :dark="theme == 'dark'">
        <q-card-section class="text-h6">
          {{ $t('components.wallet_settings.change_password') }}
        </q-card-section>
        <q-card-section>
          <q-input
            v-model="modals.change_password.old_password"
            type="password"
            :label="$t('components.wallet_settings.old_password')"
            :dark="theme == 'dark'"
          />
          <q-input
            v-model="modals.change_password.new_password"
            type="password"
            :label="$t('components.wallet_settings.new_password')"
            :dark="theme == 'dark'"
          />
          <q-input
            v-model="modals.change_password.new_password_confirm"
            type="password"
            :label="$t('components.wallet_settings.confirm_new_password')"
            :dark="theme == 'dark'"
          />
        </q-card-section>
        <q-card-actions class="row justify-end items-center">
          <q-btn
            flat
            class="q-mr-sm"
            :label="$t('components.wallet_settings.close')"
            @click="hideModal('change_password')"
          />
          <q-btn
            color="positive"
            :label="$t('components.wallet_settings.change')"
            @click="doChangePassword()"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog
      v-model="modals.export_transactions.visible"
      class="export_transactions-modal"
      minimized
      transition-show="flip-up"
      transition-hide="flip-down"
    >
      <q-card :dark="theme == 'dark'">
        <q-card-section>
          <div class="text-h6">
            {{ $t('components.wallet_settings.export_transactions') }}
          </div>
        </q-card-section>
        <q-card-section>
          <arqmaField
            class="q-mt-lg"
            :label="$t('components.wallet_settings.transactions_export_directory')"
            disable-hover
          >
            <q-input
              v-model="modals.export_transactions.export_path"
              disable
              borderless
            />
            <q-btn
              color="positive"
              @click="setTransactionsExportPath()"
            >
              {{ $t('components.wallet_settings.browse') }}
            </q-btn>
          </arqmaField>
        </q-card-section>
        <q-card-actions class="row justify-end items-center">
          <q-btn
            flat
            class="q-mr-sm"
            :label="$t('components.wallet_settings.close')"
            @click="hideModal('export_transactions')"
          />
          <q-btn
            color="positive"
            :label="$t('components.wallet_settings.export')"
            @click="export_transactions()"
          />
        </q-card-actions>
      </q-card>
    </q-dialog>

    <q-dialog
      v-model="modals.register_servicenode.visible"
      class="register_servicenode-modal"
      minimized
      transition-show="flip-up"
      transition-hide="flip-down"
    >
      <q-card :dark="theme == 'dark'">
        <q-card-section>
          <div class="text-h6">
            {{ $t('components.wallet_settings.register_service_node') }}
          </div>
        </q-card-section>
        <q-card-section>
          <div
            class="description q-mb-lg col-auto"
            v-html="$t('components.wallet_settings.register_service_node_message_one')"
          />
          <div
            class="description q-mb-lg col-auto"
            v-html="$t('components.wallet_settings.register_service_node_message_two')"
          />
          <div
            class="description q-mb-lg col-auto"
            v-html="$t('components.wallet_settings.register_service_node_message_three')"
          />

          <arqmaField
            class="col-auto"
            :label="$t('components.wallet_settings.service_node_command')"
            :error="v$.registration_string.$error"
            :disable-menu="false"
          >
            <q-input
              v-model.trim="registration.registration_string"
              type="textarea"
              :dark="theme == 'dark'"
              class="full-width text-area-arqma"
              :placeholder="$t('components.wallet_settings.service_node_command_placeholder')"
              borderless
              dense
              :disable="registration_status.sending"
              @blur="v$.registration_string.$validate()"
              @paste="onPaste"
            />
          </arqmaField>
        </q-card-section>
        <q-card-actions class="row justify-end items-center">
          <q-btn
            class="col-auto"
            color="positive"
            :label="$t('components.wallet_settings.register_service_node')"
            :disable="registration_status.sending"
            @click="register()"
          />
        </q-card-actions>

        <q-inner-loading
          :showing="registration_status.sending"
          :dark="theme == 'dark'"
        >
          <q-spinner
            color="primary"
            size="30"
          />
        </q-inner-loading>
      </q-card>
    </q-dialog>
  </div>
</template>

<script>
import { computed, defineComponent, onMounted, ref, watch, reactive } from "vue"
import { useStore } from "vuex"
import { useQuasar, extend } from "quasar"
import { usePasswordConfirmation } from "src/composables/wallet_password"
import arqmaField from "components/arqma_field"
import { useVuelidate } from "@vuelidate/core"
import { required } from "@vuelidate/validators"
import { register_service_node } from "src/validators/common"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "WalletSettings",
  components: {
    arqmaField
  },
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const { showPasswordConfirmation, hasRPCWalletCachedPassword } = usePasswordConfirmation()

    const registration = reactive({
      registration_string: ""
    })

    const modals = ref({
      private_keys: {
        visible: false
      },
      rescan: {
        visible: false,
        type: "full"
      },
      sweep_all: {
        visible: false,
        title: t("components.wallet_settings.sweep_all"),
        message: t("components.wallet_settings.sweep_all_inputs"),
        proceed: async () => await sweepAll(),
        proceedLabel: t("components.wallet_settings.sweep_all_proceed_label"),
        cancel: async () => await hideModal("sweep_all"),
        cancelLabel: t("components.wallet_settings.close"),
        loading: false
      },
      key_image: {
        visible: false,
        type: "Export",
        export_path: "",
        import_path: "",
        all: true
      },
      change_password: {
        visible: false,
        old_password: "",
        new_password: "",
        new_password_confirm: ""
      },
      export_transactions: {
        visible: false,
        type: "Export",
        export_path: ""
      },
      register_servicenode: {
        visible: false
      }
    })
    const keyImageExportSelect = ref(null)
    const keyImageImportSelect = ref(null)

    // Validations
    const rules = computed(() => {
      return {
        registration_string: { required, register_service_node }
      }
    })

    const v$ = useVuelidate(rules, registration)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const info = computed(() => $store.state.gateway.wallet.info)
    const unlocked_balance = computed(() => $store.state.gateway.wallet.info.unlocked_balance)
    const tx_status = computed(() => $store.state.gateway.tx_status)
    const secret = computed(() => $store.state.gateway.wallet.secret)
    const award_address = computed(() => $store.state.gateway.wallet.info.address)
    const wallet_data_dir = computed(() => $store.state.gateway.app.config.app.wallet_data_dir)
    const is_ready = computed(() => {
      return $store.getters["gateway/isReady"]
    })
    const registration_status = computed(() => $store.state.gateway.service_node_status.registration)
    const sweep_all_progress = computed(() => $store.state.gateway.sweep_all_progress)

    // Watchers
    const secretWatcher = watch(secret, async (newVal, oldVal) => {
      try {
        if (newVal.view_key === oldVal.view_key) return
        switch (newVal.view_key) {
          case "":
            break
          case -1:
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: secret.value.mnemonic
            })
            $store.commit("gateway/set_wallet_secret", {
              mnemonic: "",
              spend_key: "",
              view_key: ""
            })
            break
          default:
            showModal("private_keys")
            break
        }
      } catch (error) {
        await api.error("components/wallet_settings", "secretWatcher", error.stack || error)
      }
    })

    const tx_statusWatcher = watch(tx_status, async (newVal, oldVal) => {
      try {
        const { code, message, origin } = newVal
        if (origin !== "wallet_settings") return
        switch (code) {
          case 100:
            $store.commit("gateway/set_sweep_all_progress", null)
            $q.notify({
              type: "positive",
              timeout: 3000,
              message: t(message)
            })
            resetSweepAll()
            break
          case 99:
            if (modals.value.sweep_all.visible) {
              $store.commit("gateway/set_sweep_all_progress", null)
              modals.value.sweep_all.loading = false
              modals.value.sweep_all.message = `${t("components.wallet_settings.sweep_all_fee")} ${message}`
              modals.value.sweep_all.title = t("components.wallet_settings.sweep_all_proceed")
              modals.value.sweep_all.proceed = async () => await sweepAllConfirmed()
              modals.value.sweep_all.proceedLabel = t("components.wallet_settings.sweep_all_ok_label")
              modals.value.sweep_all.cancel = async () => await sweepAllCancelled()
              modals.value.sweep_all.cancelLabel = t("components.wallet_settings.sweep_all_cancel_label")
            } else {
              await resetSweepAll()
            }
            break
          case -99:
            $store.commit("gateway/set_sweep_all_progress", null)
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: t(message)
            })
            break
          case -100:
            $store.commit("gateway/set_sweep_all_progress", null)
            $q.notify({
              type: "negative",
              timeout: 3000,
              message
            })
            resetSweepAll()
            break
        }
      } catch (error) {
        await api.error("components/wallet_settings", "tx_statusWatcher", error.stack || error)
      }
    })

    const sweepProgressWatcher = watch(sweep_all_progress, (pg) => {
      try {
        if (!modals.value.sweep_all.visible || !modals.value.sweep_all.loading) return
        if (pg == null) return
        if (pg.origin !== "wallet_settings") return
        if (pg.stage === "outputs_counted") {
          const c = Number(pg.total) || 0
          modals.value.sweep_all.message = t(
            "components.wallet_settings.sweep_all_progress_outputs_counted",
            { count: c }
          )
        } else if (pg.stage === "building_tx") {
          const c = Number(pg.total) || 0
          const wr = Number(pg.wait_round) || 0
          const elapsed = wr * 3
          modals.value.sweep_all.message = t(
            "components.wallet_settings.sweep_all_progress_building",
            { count: c, elapsed }
          )
        }
      } catch (error) {
        void api.error("components/wallet_settings", "sweepProgressWatcher", error.stack || error)
      }
    })

    const registration_statusWatcher = watch(registration_status, async (newVal, oldVal) => {
      try {
        const { code, message } = newVal
        switch (code) {
          case 0:
          case 1:
            $q.notify({
              type: "positive",
              timeout: 3000,
              message
            })
            v$.value.$reset()
            registration.registration_string = ""
            break
          case -1:
            $q.notify({
              type: "negative",
              timeout: 3000,
              message
            })
            break
        }
      } catch (error) {
        await api.error("components/service_node_registration", "registration_statusWatcher", error.stack || error)
      }
    })

    onMounted(async () => {
      modals.value.key_image.export_path = await api.join(
        wallet_data_dir.value,
        "images",
        info.value.name
      )
      modals.value.key_image.import_path = await api.join(
        wallet_data_dir.value,
        "images",
        info.value.name,
        "key_image_export"
      )
      modals.value.export_transactions.export_path = wallet_data_dir.value
    })

    // Methods
    const showModal = async (which) => {
      try {
        if (!is_ready.value) return
        modals.value[which].visible = true
      } catch (error) {
        await api.error("components/wallet_settings", "showModal", error.stack || error)
      }
    }

    const hideModal = async (which) => {
      try {
        modals.value[which].visible = false
      } catch (error) {
        await api.error("components/wallet_settings", "hideModal", error.stack || error)
      }
    }

    const copyPrivateKey = async (type, event) => {
      try {
        event.stopPropagation()
        if (secret.value[type] == null) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("components.wallet_settings.copy_private_key_message")
          })
          return
        }

        api.writeText(secret.value[type])
        const type_human =
              type.substring(0, 1).toUpperCase() +
              type.substring(1).replace("_", " ")

        $q
          .dialog({
            title: `${t("components.wallet_settings.copy")} ${type_human}`,
            message: t("components.wallet_settings.write_text_message"),
            ok: {
              label: t("components.wallet_settings.write_text_ok_label"),
              color: "positive"
            },
            dark: theme.value === "dark",
            color: theme.value === "dark" ? "white" : "dark",
            transitionShow: "flip-up",
            transitionHide: "flip-down"
          })
          .onDismiss(() => {})
          .onCancel(() => {})
          .onOk(() => {
            $q.notify({
              type: "positive",
              timeout: 3000,
              message: `${type_human} ${t("components.wallet_settings.write_text_ok_message")}}`
            })
          })
      } catch (error) {
        await api.error("components/wallet_settings", "copyPrivateKey", error.stack || error)
      }
    }

    const getPrivateKeys = async () => {
      try {
        if (!is_ready.value) return
        const dialog = await showPasswordConfirmation({
          title: t("components.wallet_settings.show_private_keys"),
          noPasswordMessage: t("components.wallet_settings.show_password_confirmation_message"),
          ok: {
            label: t("components.wallet_settings.show_password_confirmation_ok_label"),
            color: "positive"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })

        dialog.onOk((password) => {
          password = password || ""
          api.send("wallet", "get_private_keys", { password })
        })
          .onDismiss(() => {})
          .onCancel(() => {})
      } catch (error) {
        await api.error("components/wallet_settings", "getPrivateKeys", error.stack || error)
      }
    }

    const closePrivateKeys = () => {
      try {
        hideModal("private_keys")
        setTimeout(() => {
          $store.commit("gateway/set_wallet_secret", {
            mnemonic: "",
            spend_key: "",
            view_key: ""
          })
        }, 500)
      } catch (error) {
        api.error("components/wallet_settings", "closePrivateKeys", error.stack || error)
      }
    }

    const rescanWallet = async () => {
      try {
        hideModal("rescan")
        if (modals.value.rescan.type === "full") {
          $q
            .dialog({
              title: t("components.wallet_settings.rescan_wallet_title"),
              message: t("components.wallet_settings.rescan_wallet_message"),
              ok: {
                label: t("components.wallet_settings.rescan_wallet_ok_label"),
                color: "positive"
              },
              cancel: {
                flat: true,
                label: t("components.wallet_settings.rescan_wallet_cancel_label")
              },
              color: theme.value === "dark" ? "white" : "dark",
              dark: theme.value === "dark",
              transitionShow: "flip-up",
              transitionHide: "flip-down"
            })
            .onOk((password) => {
              api.send("wallet", "rescan_blockchain")
            })
            .onDismiss(() => {})
            .onCancel(() => {})
        } else {
          api.send("wallet", "rescan_spent")
        }
      } catch (error) {
        await api.error("components/wallet_settings", "rescanWallet", error.stack || error)
      }
    }

    const sweepAll = async () => {
      try {
        const { unlocked_balance } = info.value

        if (unlocked_balance <= 0) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("components.wallet_settings.sweep_all_no_unlocked_balance")
          })
          return
        }

        const tx = {
          amount: unlocked_balance / 1e9,
          address: award_address.value,
          priority: 0
        }

        const dialog = await showPasswordConfirmation({
          title: t("components.wallet_settings.sweep_all"),
          message: t("components.wallet_settings.sweep_all_consolidate_inputs"),
          ok: {
            label: t("components.wallet_settings.sweep_all_consolidate_ok_label"),
            color: "positive"
          },
          cancel: {
            flat: true,
            label: t("components.wallet_settings.sweep_all_consolidate_cancel_label")
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })

        dialog.onOk((password) => {
          password = password || ""
          $store.commit("gateway/set_tx_status", {
            code: 1,
            message: t("components.wallet_settings.sweep_all_sweeping_all"),
            sending: true
          })
          modals.value.sweep_all.message = t("components.wallet_settings.sweep_all_calculating_label")
          modals.value.sweep_all.proceed = () => sweepAllProceed()
          modals.value.sweep_all.proceedLabel = t("components.wallet_settings.sweep_all_ok_label")
          modals.value.sweep_all.cancelLabel = t("components.wallet_settings.sweep_all_cancel_label")
          modals.value.sweep_all.loading = true // Disable button
          api.send("wallet", "sweepAll", { password, do_not_relay: true, origin: "wallet_settings" })
        })
          .onDismiss(() => {})
          .onCancel(() => {
            hideModal("sweep_all")
          })
      } catch (error) {
        modals.value.sweep_all.loading = false
        await api.error("components/wallet_settings", "sweepAll", error.stack || error)
      }
    }

    const sweepAllConfirmed = async () => {
      try {
        hideModal("sweep_all")
        modals.value.sweep_all.cancel = async () => await sweepAllCancelled()
        api.send("wallet", "relay_sweepAll", { origin: "wallet_settings" })
      } catch (error) {
        await api.error("components/wallet_settings", "sweepAllConfirmed", error.stack || error)
      }
    }

    const sweepAllCancelled = async () => {
      try {
        await hideModal("sweep_all")
        await resetSweepAll()
        api.send("wallet", "cancelTransaction", { type: "sweepAll" })
      } catch (error) {
        await api.error("components/wallet_settings", "sweepAllConfirmed", error.stack || error)
      }
    }

    const resetSweepAll = async () => {
      $store.commit("gateway/set_sweep_all_progress", null)
      modals.value.sweep_all.title = t("components.wallet_settings.sweep_all")
      modals.value.sweep_all.message = t("components.wallet_settings.sweep_all_inputs")
      modals.value.sweep_all.proceed = async () => await sweepAll()
      modals.value.sweep_all.proceedLabel = t("components.wallet_settings.sweep_all_proceed_label")
      modals.value.sweep_all.cancel = async () => await hideModal("sweep_all")
      modals.value.sweep_all.cancelLabel = t("components.wallet_settings.close")
    }

    const selectKeyImageExportPath = async () => {
      try {
        keyImageExportSelect.value.click()
      } catch (error) {
        await api.error("components/wallet_settings", "selectKeyImageExportPath", error.stack || error)
      }
    }

    const setKeyImageExportPath = async (file) => {
      try {
        modals.value.key_image.export_path = file.target.files[0].path
      } catch (error) {
        await api.error("components/wallet_settings", "setKeyImageExportPath", error.stack || error)
      }
    }

    const selectKeyImageImportPath = async () => {
      try {
        keyImageImportSelect.value.click()
      } catch (error) {
        await api.error("components/wallet_settings", "selectKeyImageImportPath", error.stack || error)
      }
    }

    const setKeyImageImportPath = async (file) => {
      try {
        modals.value.key_image.import_path = file.target.files[0].path
      } catch (error) {
        await api.error("components/wallet_settings", "setKeyImageImportPath", error.stack || error)
      }
    }

    const doKeyImages = async () => {
      try {
        hideModal("key_image")
        const dialog = await showPasswordConfirmation({
          title: `${modals.value.key_image.type} ${t("components.wallet_settings.key_images")}`,
          noPasswordMessage: `${t("components.wallet_settings.show_key_images_password_confirmation_message_one")} ${modals.value.key_image.type.toLowerCase()} ${t("components.wallet_settings.show_key_images_password_confirmation_message_two")}`,
          ok: {
            label: modals.value.key_image.type,
            color: "positive"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })

        dialog.onOk((password) => {
          password = password || ""
          if (modals.value.key_image.type === "Export") {
            api.send("wallet", "export_key_images", {
              password,
              path: modals.value.key_image.export_path,
              all: modals.value.key_image.all
            })
          } else if (modals.value.key_image.type === "Import") {
            api.send("wallet", "import_key_images", {
              password,
              path: modals.value.key_image.import_path
            })
          }
        })
          .onCancel(() => {})
          .onDismiss(() => {})
      } catch (error) {
        await api.error("components/wallet_settings", "doKeyImages", error.stack || error)
      }
    }

    const doChangePassword = async () => {
      try {
        const old_password = modals.value.change_password.old_password
        const new_password = modals.value.change_password.new_password
        const new_password_confirm = modals.value.change_password.new_password_confirm

        if (new_password === old_password) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("components.wallet_settings.invalid_change_password_message")
          })
          return
        }

        if (new_password !== new_password_confirm) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("components.wallet_settings.invalid_change_password_not_match_message")
          })
          return
        }

        hideModal("change_password")
        api.send("wallet", "change_wallet_password", {
          old_password,
          new_password
        })
      } catch (error) {
        await api.error("components/wallet_settings", "doChangePassword", error.stack || error)
      }
    }

    const clearChangePassword = async () => {
      try {
        modals.value.change_password.old_password = ""
        modals.value.change_password.new_password = ""
        modals.value.change_password.new_password_confirm = ""
      } catch (error) {
        await api.error("components/wallet_settings", "clearChangePassword", error.stack || error)
      }
    }

    const setTransactionsExportPath = async (file) => {
      try {
        const result = await api.openDirectory(modals.value.export_transactions.export_path)
        if (result && !result.cancelled && !!result.filePaths[0]) {
          modals.value.export_transactions.export_path = result.filePaths[0]
        }
      } catch (error) {
        await api.error("components/wallet_settings", "setTransactionsExportPath", error.stack || error)
      }
    }

    const export_transactions = async () => {
      try {
        hideModal("export_transactions")
        const dialog = await showPasswordConfirmation({
          title: t("components.wallet_settings.export_transactions"),
          noPasswordMessage: t("components.wallet_settings.show_password_confirmation_export_transactions_message_one"),
          ok: {
            label: modals.value.export_transactions.type,
            color: "positive"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })

        dialog.onOk((password) => {
          password = password || ""
          api.send("wallet", "export_transactions", {
            password,
            path: modals.value.export_transactions.export_path
          })
        })
          .onCancel(() => {})
          .onDismiss(() => {})
      } catch (error) {
        await api.error("components/wallet_settings", "export_transactions", error.stack || error)
      }
    }

    const deleteWallet = async () => {
      try {
        if (!is_ready.value) return
        $q
          .dialog({
            title: t("components.wallet_settings.delete_account"),
            message: t("components.wallet_settings.delete_account_message"),
            ok: {
              label: t("components.wallet_settings.delete_account_ok_label"),
              color: "red"
            },
            cancel: {
              flat: true,
              label: t("components.wallet_settings.delete_account_cancel_label"),
              color: theme.value === "dark" ? "white" : "dark"
            },
            dark: theme.value === "dark",
            color: theme.value === "dark" ? "white" : "dark",
            transitionShow: "flip-up",
            transitionHide: "flip-down"
          })
          .onOk(() => {
            return hasRPCWalletCachedPassword()
          })
          .onOk((hasPassword) => {
            if (!hasPassword) {
              return $q.dialog({
                title: t("components.wallet_settings.delete_account"),
                message: t("components.wallet_settings.show_delete_account_password_confirmation_message"),
                prompt: {
                  model: "",
                  type: "password"
                },
                transitionShow: "flip-up",
                transitionHide: "flip-down",
                ok: {
                  label: t("components.wallet_settings.show_delete_account_password_confirmation_ok_label"),
                  color: "negative"
                },
                cancel: {
                  flat: true,
                  label: t("components.wallet_settings.rescan_wallet_cancel_label"),
                  color: theme.value === "dark" ? "white" : "dark"
                },
                dark: theme.value === "dark",
                color: "positive"
              })
                .onOk((password) => {
                  api.send("wallet", "delete_wallet", { password })
                })
                .onDismiss(() => {})
                .onCancel(() => {})
            } else {
              api.send("wallet", "delete_wallet", { password })
            }
          })
          .onDismiss(() => {})
          .onCancel(() => {})
      } catch (error) {
        await api.error("components/wallet_settings", "deleteWallet", error.stack || error)
      }
    }

    const onPaste = async () => {
      try {
        //   await nextTick()
        registration.registration_string = registration.registration_string.trim()
      } catch (error) {
        await api.error("components/service_node_registration", "onPaste", error.stack || error)
      }
    }

    const register = async () => {
      try {
        await v$.value.$validate()
        if (v$.value.registration_string.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("components.wallet_settings.invalid_service_node_command")
          })
          return
        }

        const dialog = await showPasswordConfirmation({
          title: t("components.wallet_settings.show_register_service_node_password_confirmation_title"),
          noPasswordMessage: t("components.wallet_settings.show_register_service_node_password_confirmation_message"),
          ok: {
            label: t("components.wallet_settings.show_register_service_node_password_confirmation_ok_label"),
            color: "positive"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })

        dialog.onOk((password) => {
          hideModal("register_servicenode")
          password = password || ""
          $store.commit("gateway/set_snode_status", {
            registration: {
              code: 1,
              message: t("components.wallet_settings.service_node_registering_message"),
              sending: true
            }
          })
          api.send("wallet", "register_service_node", {
            password,
            string: registration.registration_string.trim()
          })
        })
          .onDismiss(() => {})
          .onCancel(() => {})
      } catch (error) {
        await api.error("components/service_node_registration", "register", error.stack || error)
      }
    }

    return {
      t,
      v$,
      registration,
      modals,
      keyImageExportSelect,
      keyImageImportSelect,
      theme,
      info,
      unlocked_balance,
      tx_status,
      secret,
      award_address,
      wallet_data_dir,
      is_ready,
      secretWatcher,
      tx_statusWatcher,
      sweepProgressWatcher,
      showModal,
      hideModal,
      copyPrivateKey,
      getPrivateKeys,
      closePrivateKeys,
      rescanWallet,
      sweepAll,
      sweepAllConfirmed,
      sweepAllCancelled,
      selectKeyImageExportPath,
      setKeyImageExportPath,
      selectKeyImageImportPath,
      setKeyImageImportPath,
      doKeyImages,
      doChangePassword,
      clearChangePassword,
      deleteWallet,
      arqmaField,
      showPasswordConfirmation,
      setTransactionsExportPath,
      export_transactions,
      onPaste,
      register,
      registration_status,
      registration_statusWatcher
    }
  }
})
</script>

<!-- .menu-list { } -->

<style lang="scss">
.wallet-settings {
  .q-btn {
    color: white;
  }
}

.register_servicenode {
    min-width: 400px;
}

.password-modal {
  min-width: 400px;
}

.image-path {
  opacity: 0;
  overflow: hidden;
}

.key-image-modal {
  label * {
    color: #cecece !important;
    text-overflow: ellipsis;
    overflow: hidden;
  }
  input {
    overflow: ellipsis;
  }
}

.private-key-modal {
  .copy-btn {
    margin-left: 8px;
  }
}

.key-image-modal {
  min-width: 600px;
  width: 45vw;

  .arqma-field {
    flex: 1;
  }
}
</style>
