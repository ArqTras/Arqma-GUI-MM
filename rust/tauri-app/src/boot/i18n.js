import { createI18n } from "vue-i18n"
import { nextTick } from "vue"
import { LocalStorage } from "quasar"

export const SUPPORT_LOCALES = ["en-US", "de-DE", "fr-FR", "ua-UA", "pl-PL"]

function normalizeLocale (locale) {
  if (!locale || typeof locale !== "string") return "en-US"
  const parts = locale.split("-")
  if (parts.length >= 2) {
    parts[0] = parts[0].toLowerCase()
    parts[1] = parts[1].toUpperCase()
    return parts.join("-")
  }
  return locale
}

let language = "en-US"
try {
  if (LocalStorage.has("language")) {
    language = normalizeLocale(LocalStorage.getItem("language"))
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
  document.querySelector("html").setAttribute("lang", locale)
}

export async function loadLocaleMessages (i18n, locale) {
  const normalized = normalizeLocale(locale)
  const messages = await import(`@/locales/${normalized}.json`)
  i18n.global.setLocaleMessage(normalized, messages.default)
  setI18nLanguage(i18n, normalized)
  LocalStorage.set("language", normalized)
  return nextTick()
}

export const i18n = setupI18n({ locale: language })

export { language }
