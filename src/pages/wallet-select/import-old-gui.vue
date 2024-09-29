<template>
  <q-page>
    <div class="q-mx-md import-old-gui">
      <q-list
        link
        dark
        no-border
        class="wallet-list"
      >
        <q-item
          v-for="state in directory_state"
          :key="state.directory"
          :class="{selected : state.selected}"
        >
          <q-item-section>
            <q-checkbox
              v-model="state.selected"
              dark
              color="dark"
            />
          </q-item-section>
          <q-item-label @click="state.selected = !state.selected">
            <q-item-label header>
              {{ state.directory }}
            </q-item-label>
          </q-item-label>
          <q-item-section>
            <q-select
              v-model="state.type"
              hide-underline
              dark
              class="q-ma-none full-width"
              :options="selectOptions"
            />
          </q-item-section>
        </q-item>
      </q-list>

      <q-field>
        <q-btn
          color="positive"
          :label="$t('pages.wallet_select.import_old_gui.import_accounts')"
          :disable="selectedWallets.length === 0"
          @click="import_wallets"
        />
      </q-field>
    </div>
  </q-page>
</template>

<script>
import { computed, defineComponent, onMounted, ref, watch } from "vue"
import { useRouter } from "vue-router"
import { useStore } from "vuex"
import { useQuasar, extend } from "quasar"
import { useI18n } from "vue-i18n"

export default defineComponent({
  setup () {
    const router = useRouter()
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const directory_state = ref([])

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const directories = computed(() => ["foo", "bar"]) // $store.state.gateway.wallets.directories)
    const old_gui_import_status = computed(() => $store.state.gateway.old_gui_import_status)
    const selectOptions = computed(() => [
      {
        label: "Main",
        value: "mainnet"
      },
      {
        label: "Staging",
        value: "stagenet"
      },
      {
        label: "Test",
        value: "testnet"
      }
    ])
    const selectedWallets = computed(() => {
      return directory_state.value.filter(s => s.selected)
    })

    // Watchers
    const directoriesWatcher = watch(directories, (newVal, oldVal) => {
      populate_state()
    })

    const old_gui_import_statusWatcher = watch(old_gui_import_status, async (newVal, oldVal) => {
      try {
        if (newVal.code === oldVal.code) return

        const { code, failed_wallets } = old_gui_import_status.value

        // Imported
        if (code === 0) {
          $q.loading.hide()
          if (failed_wallets.length === 0) {
            router.push({ path: "/wallet-select" })
          } else {
            failed_wallets.forEach(wallet => {
              $q.notify({
                type: "negative",
                timeout: 3000,
                message: `${t("pages.wallet_select.import_old_gui.failed_to_import_account")}: ${wallet}`
              })
            })
          }
        }
      } catch (error) {
        await api.error("pages/wallet-select/import-old-gui", "old_gui_import_statusWatcher", error.stack || error)
      }
    })

    onMounted(async () => {
      try {
        populate_state()
      } catch (error) {
        await api.error("pages/wallet-select/import-old-gui", "onMounted", error.stack || error)
      }
    })

    // Methods
    const populate_state = async () => {
      try {
        // Keep any directories that intersect
        const new_state = directory_state.value.filter(state => directories.value.includes(state.directory))

        // Add in new directories
        directories.value
          .filter(dir => !new_state.find(state => state.directory === dir))
          .forEach(directory => {
            new_state.push({
              directory,
              selected: false,
              type: "mainnet"
            })
          })

        // Sort them
        directory_state.value = new_state.sort(function (a, b) {
          return a.directory.localeCompare(b.directory)
        })
      } catch (error) {
        await api.error("pages/wallet-select/import-old-gui", "populate_state", error.stack || error)
      }
    }

    const import_wallets = async () => {
      try {
        $q.loading.show({
          delay: 0
        })
        api.send("wallet", "copy_old_gui_wallets", {
          wallets: extend(true, [], selectedWallets.value)
        })
      } catch (error) {
        await api.error("pages/wallet-select/import-old-gui", "import_wallets", error.stack || error)
      }
    }

    const cancel = async () => {
      try {
        router.push({ path: "/wallet-select" })
      } catch (error) {
        await api.error("pages/wallet-select/import-old-gui", "cancel", error.stack || error)
      }
    }

    return {
      t,
      directory_state,
      theme,
      directories,
      old_gui_import_status,
      selectOptions,
      selectedWallets,
      directoriesWatcher,
      old_gui_import_statusWatcher,
      populate_state,
      import_wallets,
      cancel
    }
  }
})
</script>

<style lang="scss">
.import-old-gui {
    .wallet-list {
        .q-item {
            margin: 10px 0px;
            margin-bottom: 0px;
            padding: 14px;
            border-radius: 3px;
        }
    }
}
</style>
