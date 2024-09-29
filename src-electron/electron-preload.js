import { contextBridge, ipcRenderer } from "electron"

contextBridge.exposeInMainWorld("api", {
  error: (module, method, message) => {
    return ipcRenderer.invoke("foo:error", { module, method, message })
  },
  remotes: (data_dir, subdirectory, fileName) => {
    return ipcRenderer.invoke("foo:remotes", { data_dir, subdirectory, fileName })
  },
  noMutate: (v1, v2) => {
    return ipcRenderer.invoke("foo:noMutate", { v1, v2 })
  },
  join: (data_dir, subdirectory, fileName) => {
    return ipcRenderer.invoke("foo:join", { data_dir, subdirectory, fileName })
  },
  writeText: (v1) => {
    return ipcRenderer.invoke("foo:writeText", v1)
  },
  writeImage: (v1) => {
    return ipcRenderer.invoke("foo:writeImage", v1)
  },
  createFromDataURL: (data) => {
    return ipcRenderer.invoke("foo:createFromDataURL", data)
  },
  isDevelopment: () => {
    return ipcRenderer.invoke("foo:isDevelopment")
  },
  version: () => {
    return ipcRenderer.invoke("foo:version")
  },
  daemonVersion: () => {
    return ipcRenderer.invoke("foo:daemonVersion")
  },
  send: (module, method, data = {}) => {
    const message = { module, method, data }
    return ipcRenderer.invoke("foo:send", message)
  },
  receive: (data) => {
    ipcRenderer.on("receive", data)
  },
  autoUpdater: (data) => {
    ipcRenderer.on("autoUpdater", data)
  },
  receiveConfirmClose: (data) => {
    ipcRenderer.on("receiveConfirmClose", data)
  },
  confirmClose: (data) => {
    return ipcRenderer.invoke("confirmClose", data)
  },
  openDirectory: (path) => {
    return ipcRenderer.invoke("foo:openDirectory", path)
  },
  saveLoggingLevelToEnvironmentFile: (data) => {
    return ipcRenderer.invoke("foo:saveLoggingLevelToEnvironmentFile", data)
  }
})

window.addEventListener("DOMContentLoaded", () => {
  const replaceText = (selector, text) => {
    const element = document.getElementById(selector)
    if (element) element.innerText = text
  }

  for (const type of ["chrome", "node", "electron"]) {
    replaceText(`${type}-version`, process.versions[type])
  }
})
