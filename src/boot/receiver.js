import { boot } from "quasar/wrappers"
import { Receiver } from "src/receiver/receiver"

export default boot(({ app, store, router }) => {
  app.config.globalProperties.$gateway = new Receiver(store, router)
  app.provide("gateway", app.config.globalProperties.$gateway)
})
