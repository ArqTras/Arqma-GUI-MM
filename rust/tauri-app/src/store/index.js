import { createStore, createLogger } from "vuex"
import gateway from "./gateway"

export function createAppStore () {
  return createStore({
    modules: { gateway },
    strict: false,
    plugins: false ? [createLogger()] : []
  })
}
