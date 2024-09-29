import { boot } from "quasar/wrappers"
import { createI18n } from "vue-i18n"
import { nextTick } from "vue"
import { LocalStorage } from "quasar"

export const SUPPORT_LOCALES = ["en-US", "de-DE", "fr-FR", "ua-UA", "pl-PL"]

let language = "en-US"
try {
  if (LocalStorage.has("language")) {
    language = LocalStorage.getItem("language")
  }
} catch (error) {}

export function setupI18n (options = { locale: "en-US" }) {
  options.legacy = false
  options.allowComposition = true
  options.globalInjection = true
  const i18n = createI18n(options)
  setI18nLanguage(i18n, options.locale)
  return i18n
}

export function setI18nLanguage (i18n, locale) {
  if (i18n.mode === "legacy") {
    i18n.global.locale = locale
  } else {
    i18n.global.locale.value = locale
  }
  /**
   * NOTE:
   * If you need to specify the language setting for headers, such as the `fetch` API, set it here.
   * The following is an example for axios.
   *
   * axios.defaults.headers.common['Accept-Language'] = locale
   */
  document.querySelector("html").setAttribute("lang", locale)
}

export async function loadLocaleMessages (i18n, locale) {
  // load locale messages with dynamic import
  const messages = await import(
    /* webpackChunkName: "locale-[request]" */ `src/locales/${locale}.json`
  )
  // set locale and locale message
  i18n.global.setLocaleMessage(locale, messages)
  LocalStorage.set("language", locale)
  return nextTick()
}

const i18n = setupI18n({ locale: language })

export default boot(async ({ app }) => {
  await loadLocaleMessages(i18n, language)
  // Set i18n instance on app
  app.use(i18n)
})

export { i18n }
