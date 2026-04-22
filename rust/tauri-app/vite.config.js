import { defineConfig } from "vite"
import { fileURLToPath, URL } from "node:url"
import vue from "@vitejs/plugin-vue"
import { quasar, transformAssetUrls } from "@quasar/vite-plugin"
import AutoImport from "unplugin-auto-import/vite"

export default defineConfig({
  // Tauri: ścieżki względne w buildzie — bez tego /assets/... daje 404 w WebView (biały ekran)
  base: "./",
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  preview: { port: 1420, strictPort: true },
  resolve: {
    extensions: [".mjs", ".js", ".mts", ".ts", ".jsx", ".tsx", ".json", ".vue"],
    alias: {
      "@": fileURLToPath(new URL("src", import.meta.url)),
      src: fileURLToPath(new URL("src", import.meta.url)),
      components: fileURLToPath(new URL("src/components", import.meta.url)),
      layouts: fileURLToPath(new URL("src/layouts", import.meta.url)),
      pages: fileURLToPath(new URL("src/pages", import.meta.url)),
      buffer: "buffer",
      events: "events"
    }
  },
  define: {
    "process.env.DEBUGGING": false,
    "process.env.SERVER": false,
    "process.env.VUE_ROUTER_MODE": JSON.stringify("hash")
  },
  plugins: [
    AutoImport({
      include: [/\.[tj]sx?$/, /\.vue$/, /\.vue\?vue/],
      imports: {
        "@/bridge/api": ["api"]
      },
      dts: "src/auto-imports.d.ts"
    }),
    vue({ template: { transformAssetUrls } }),
    quasar({ sassVariables: fileURLToPath(new URL("src/css/quasar.variables.scss", import.meta.url)) })
  ],
  build: {
    target: "es2020",
    outDir: "dist",
    sourcemap: false,
    chunkSizeWarningLimit: 2000,
    commonjsOptions: { transformMixedEsModules: true }
  },
  optimizeDeps: {
    include: ["quasar", "@quasar/extras", "buffer"]
  }
})
