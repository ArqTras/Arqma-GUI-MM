<template>
  <q-page class="welcome">
    <q-stepper
      ref="stepper"
      v-model="step"
      class="welcome-stepper"
      flat
      dark
      header-nav
    >
      <q-step
        :name="1"
        :title="$t('pages.welcome.step_one')"
        :done="step > 1"
        class="first-step"
      >
        <div class="welcome-container">
          <img
            src="arq_logo_with_padding.png"
            height="100"
            class="q-mb-md"
          >
          <p class="q-my-sm">
            {{ $t('pages.welcome.version') }}: {{ version }}
          </p>
          <p class="q-my-sm">
            {{ daemonVersion }}
          </p>

          <q-btn
            color="primary"
            size="md"
            :label="$t('pages.welcome.load_wallet')"
            @click="clickNext()"
          />
        </div>
      </q-step>

      <q-step
        :name="2"
        :title="$t('pages.welcome.step_two')"
      >
        <SettingsGeneral
          ref="settingsGeneral"
        />
      </q-step>
    </q-stepper>

    <q-footer
      v-if="!(step === 1)"
      class="no-shadow q-pa-sm"
    >
      <div class="row justify-end">
        <div>
          <q-btn
            flat
            :label="$t('pages.welcome.button_back')"
            @click="clickPrev()"
          />
        </div>
        <div>
          <q-btn
            class="q-ml-sm"
            color="primary"
            :label="$t('pages.welcome.button_next')"
            @click="clickNext()"
          />
        </div>
      </div>
    </q-footer>
  </q-page>
</template>

<script>
import { computed, defineComponent, onMounted, ref } from "vue"
import { useRouter } from "vue-router"
import { useStore } from "vuex"
import SettingsGeneral from "components/settings_general"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Welcome",
  components: {
    SettingsGeneral
  },
  setup () {
    const $store = useStore()
    const router = useRouter()
    const { t } = useI18n()

    const stepper = ref(null)
    const step = ref(1)
    const choose_lang = ("EN")
    const version = ref("")

    // Computed props
    const theme = computed(() => $store.state.gateway.appearance.theme)
    const pending_config = computed(() => $store.state.gateway.app.pending_config)
    const config_daemon = computed(() => pending_config.value.daemons[pending_config.value.app.net_type])
    const daemonVersion = computed(() => $store.state.gateway.daemon_version)

    // Hooks

    // Methods

    const clickNext = async () => {
      try {
        if (step.value === 2) {
          await $store.dispatch("gateway/notifier", { save: true, method: "save_config_init" })
          await $store.dispatch("gateway/setAppData", { status: { code: 1 } })
          await router.push({ path: "/" })
        } else {
          stepper.value.next()
        }
      } catch (error) {
        await api.error("pages/init/welcome", "clickNext", error.stack || error)
      }
    }
    const clickPrev = async () => {
      try {
        stepper.value.previous()
      } catch (error) {
        await api.error("pages/init/welcome", "clickPrev", error.stack || error)
      }
    }

    // Mounted
    onMounted(async () => {
      try {
        version.value = await api.version()
        $store.commit("gateway/set_app_data", {
          status: {
            code: 2 // Loading config
          }
        })
      } catch (error) {
        await api.error("pages/init/welcome", "onMounted", error.stack || error)
      }
    })

    return {
      t,
      stepper,
      step,
      choose_lang,
      version,
      daemonVersion,
      theme,
      pending_config,
      config_daemon,
      clickNext,
      clickPrev,
      SettingsGeneral
    }
  }
})

</script>

<style lang="scss">

.welcome {
    .welcome-stepper {
      height: 100%;
      background: transparent;
    }

    .welcome-container {
        padding-top: 14vh;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        background-color: transparent;
    }

    .first-step .q-stepper-step-inner {
        min-height: 250px;
        height: 100%;
    }
}

</style>
