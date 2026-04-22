<template>
  <q-page>
    <div class="init-screen-page text-center">
      <div class="absolute-center">
        <img
          src="arq_logo_with_padding.png"
          height="100"
          class="q-mb-md"
        >

        <div class="q-mt-xl q-mb-lg">
          <q-spinner
            color="primary"
            :size="60"
          />
        </div>

        <div class="message">
          {{ $t('pages.quit.closing') }}
        </div>
      </div>
    </div>
  </q-page>
</template>

<script>
import { defineComponent } from "vue"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "Quit",
  setup () {
    const { t } = useI18n()

    return {
      t
    }
  }
})
</script>

<style lang="scss">
.init-screen-page {
  height: 100vh;
  position: relative;
}
</style>
