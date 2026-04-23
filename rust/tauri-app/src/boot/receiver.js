import { Receiver } from "src/receiver/receiver"

export function setupGateway (app, store, router) {
  const gateway = new Receiver(store, router)
  app.config.globalProperties.$gateway = gateway
  app.provide("gateway", gateway)
}
