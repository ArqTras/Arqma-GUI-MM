import { createRouter, createWebHashHistory } from "vue-router"
import routes from "./routes"

export function createAppRouter () {
  return createRouter({
    scrollBehavior: () => ({ left: 0, top: 0 }),
    history: createWebHashHistory(import.meta.env.BASE_URL),
    routes
  })
}
