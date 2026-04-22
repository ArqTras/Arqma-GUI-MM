import { Buffer } from "buffer"
globalThis.Buffer = Buffer

import { createApp } from "vue"
import { Quasar, Dialog, Loading, LocalStorage, Notify } from "quasar"
import "@quasar/extras/roboto-font/roboto-font.css"
import "@quasar/extras/material-icons/material-icons.css"
import "quasar/src/css/index.sass"
import { createAppRouter } from "src/router"
import { createAppStore } from "src/store"
import { i18n, loadLocaleMessages, language } from "src/boot/i18n"
import { setupAxios } from "src/boot/axios"
import { setupGateway } from "src/boot/receiver"
import { setupTimeago } from "src/boot/timeago"
import App from "src/App.vue"
import "src/css/app.scss"

void (async () => {
  const app = createApp(App)
  app.use(Quasar, {
    plugins: { Dialog, Loading, LocalStorage, Notify }
  })
  await loadLocaleMessages(i18n, language)
  const store = createAppStore()
  const router = createAppRouter()
  app.use(store)
  app.use(router)
  app.use(i18n)
  setupAxios(app)
  setupTimeago(app)
  setupGateway(app, store, router)
  app.mount("#q-app")
})()
