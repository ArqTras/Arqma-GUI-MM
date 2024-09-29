<template>
  <router-view />
</template>

<script>
import { defineComponent, onMounted, inject } from "vue"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "App",
  setup () {
    const { t } = useI18n()

    const gateway = inject("gateway")
    onMounted(() => {
      api.receiveConfirmClose((event, message) => {
        !!gateway.confirmClose(t("app.confirm_close"))
      })
    })
    return {
      t
    }
  }
})
</script>
