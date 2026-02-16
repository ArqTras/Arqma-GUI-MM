<template>
  <q-dialog
    v-model="isVisible"
    maximized
    class="settings-modal"
    transition-show="flip-up"
    transition-hide="flip-down"
  >
    <q-layout>
      <q-header
        class="row justify-between items-center header-border-bottom"
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
          <q-toolbar-title shrink>
            {{ $t('components.settings.settings') }}
          </q-toolbar-title>

          <div class="row col justify-center q-pr-xl">
            <q-btn-toggle
              v-model="page"
              toggle-color="primary"
              color="tertiary"
              size="md"
              :options="tabs"
            />
          </div>

          <q-btn
            color="primary"
            :label="$t('components.settings.save')"
            @click="save"
          />
        </q-toolbar>
      </q-header>

      <q-page-container>
        <div v-if="page == 'general'">
          <div class="q-pa-lg">
            <SettingsGeneral
              ref="settingsGeneral"
            />
          </div>
        </div>

        <div v-if="page == 'peers'">
          <q-list
            :dark="theme == 'dark'"
            no-border
          >
            <q-item-label>{{ $t('components.settings.peer_list') }}</q-item-label>

            <q-item
              v-for="entry in daemon.connections"
              :key="entry.address"
              link
              @click="showPeerDetails(entry)"
            >
              <q-item-label>
                <q-item-label header>
                  {{ entry.address }}
                </q-item-label>
                <q-item-label caption>
                  {{ $t('components.settings.height') }}{{ entry.height }}
                </q-item-label>
              </q-item-label>
            </q-item>

            <template v-if="daemon.bans.length">
              <q-item-label class="q-list-header">
                {{ $t('components.settings.banned_peers') }}
              </q-item-label>
              <q-item
                v-for="entry in daemon.bans"
                :key="entry.host"
              >
                <q-item-label>
                  <q-item-label header>
                    {{ entry.host }}
                  </q-item-label>
                  <q-item-label caption>
                    {{ $t('components.settings.banned_until') }}
                    {{
                      new Date(
                        Date.now() + entry.seconds * 1000
                      ).toLocaleString()
                    }}
                  </q-item-label>
                </q-item-label>
              </q-item>
            </template>
          </q-list>
        </div>
      </q-page-container>
    </q-layout>
  </q-dialog>
</template>

<script>
import { computed, defineComponent, ref } from "vue"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import SettingsGeneral from "components/settings_general"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "SettingsModal",
  components: {
    SettingsGeneral
  },
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const page = ref("general")
    const isVisible = ref(false)
    const settingsGeneral = ref(null)

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const daemon = computed(() => $store.state.gateway.daemon)
    const pending_config = computed(() => $store.state.gateway.app.pending_config)
    const config = computed(() => $store.state.gateway.app.config)
    const tabs = computed(() => {
      const { app, daemons } = $store.state.gateway.app.config
      const tabs = [{ label: t("components.settings.general"), value: "general", icon: "settings" }]
      if (daemons[app.net_type].type !== "remote") {
        tabs.push({ label: t("components.settings.peers"), value: "peers", icon: "cloud_queue" })
      }
      return tabs
    })

    // Methods
    const save = async () => {
      try {
        await $store.dispatch("gateway/notifier", { save: true, method: "save_config" })
        isVisible.value = false
      } catch (error) {
        await api.error("components/settings", "save", error.stack || error)
      }
    }

    const showPeerDetails = async (entry) => {
      try {
        $q
          .dialog({
            title: t("components.settings.peer_details_title"),
            message: JSON.stringify(entry, null, 2),
            ok: {
              label: t("components.settings.peer_ok_label"),
              color: "negative"
            },
            cancel: {
              flat: true,
              label: t("components.settings.peer_details_cancel_label"),
              color: "red"
            },
            transitionShow: "flip-up",
            transitionHide: "flip-down"
          })
          .onOk(() => {
            $q
              .dialog({
                title: t("components.settings.peer_details_title"),
                message: t("components.settings.peer_details_message"),
                prompt: {
                  model: "",
                  type: "number"
                },
                transitionShow: "flip-up",
                transitionHide: "flip-down",
                ok: {
                  label: t("components.settings.peer_details_ok_label"),
                  color: "negative"
                },
                cancel: {
                  flat: true,
                  label: t("components.settings.peer_details_cancel_label"),
                  color: "red"
                }
              })
              .onOk((seconds) => {
                api.send("daemon", "ban_peer", {
                  host: entry.host,
                  seconds
                })
              })
              .onDismiss(() => {})
              .onCancel(() => {})
          })
          .onCancel(() => {})
          .onDismiss(() => {})
      } catch (error) {
        await api.error("components/settings", "showPeerDetails", error.stack || error)
      }
    }

    return {
      t,
      page,
      isVisible,
      theme,
      daemon,
      pending_config,
      config,
      tabs,
      save,
      showPeerDetails,
      SettingsGeneral,
      settingsGeneral
    }
  }
})
</script>

<style lang="scss"></style>
