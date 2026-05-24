import axios from "axios"

const $api = axios.create({ baseURL: "https://api.example.com" })

export function setupAxios (app) {
  app.config.globalProperties.$axios = axios
  app.config.globalProperties.$api = $api
}

export { $api as api }
