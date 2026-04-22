import { invoke } from "@tauri-apps/api/core"
import { listen } from "@tauri-apps/api/event"

const backendSend = (module, method, data = {}) =>
  invoke("backend_send", { message: { module, method, data } })

const invokeSimple = (cmd, args = {}) => invoke(cmd, args)

export const api = {
  error: (module, method, message) => invokeSimple("app_log_error", { module, method, message }),
  info: (module, method, message) => invokeSimple("app_log_info", { module, method, message }),
  remotes: (data_dir, subdirectory, fileName) => invokeSimple("fs_read_json_remotes", { data_dir, subdirectory, fileName }),
  noMutate: (v1, v2) => invokeSimple("util_no_mutate", { v1, v2 }),
  join: (data_dir, subdirectory, fileName) => invokeSimple("util_join_path", { data_dir, subdirectory, fileName }),
  writeText: (v1) => invokeSimple("clip_write_text", { text: v1 }),
  writeImage: (v1) => invokeSimple("clip_write_image", { v1 }),
  createFromDataURL: (data) => invokeSimple("image_from_data_url", { data }),
  isDevelopment: () => invokeSimple("app_is_dev"),
  version: () => invokeSimple("app_version_str"),
  daemonVersion: () => invokeSimple("daemon_version_probe"),
  send: (module, method, data = {}) => backendSend(module, method, data),
  receive: (data) => {
    void listen("backend-receive", (ev) => {
      if (typeof data === "function") { data({ }, ev.payload) }
    }).catch((e) => console.error("[api] listen backend-receive", e))
  },
  autoUpdater: (data) => {
    void listen("auto-updater", (ev) => {
      if (typeof data === "function") { data({ }, ev.payload) }
    }).catch((e) => console.error("[api] listen auto-updater", e))
  },
  receiveConfirmClose: (data) => {
    void listen("confirm-close", (ev) => {
      if (typeof data === "function") { data({ }, ev.payload) }
    }).catch((e) => console.error("[api] listen confirm-close", e))
  },
  confirmClose: (data) => invokeSimple("confirm_close", { restart: data }),
  openDirectory: (p) => invokeSimple("dialog_open_dir", { defaultPath: p }),
  saveLoggingLevelToEnvironmentFile: (data) => invokeSimple("app_save_log_level", { value: data })
}

export default api
