/* eslint-disable no-template-curly-in-string */
/* eslint-env node */

/*
 * This file runs in a Node context (it's NOT transpiled by Babel), so use only
 * the ES6 features that are supported by your Node version. https://node.green/
 */

// Configuration for your app
// https://v2.quasar.dev/quasar-cli-webpack/quasar-config-js

const ESLintPlugin = require("eslint-webpack-plugin")
const path = require("path")
const { configure } = require("quasar/wrappers")

module.exports = configure(function (ctx) {
  return {
    // https://v2.quasar.dev/quasar-cli-webpack/supporting-ts
    supportTS: false,

    // https://v2.quasar.dev/quasar-cli-webpack/prefetch-feature
    // preFetch: true,

    // app boot file (/src/boot)
    // --> boot files are part of "main.js"
    // https://v2.quasar.dev/quasar-cli-webpack/boot-files
    boot: ["i18n", "axios", "receiver", "timeago"],

    // https://v2.quasar.dev/quasar-cli-webpack/quasar-config-js#Property%3A-css
    css: ["app.scss"],

    // https://github.com/quasarframework/quasar/tree/dev/extras
    extras: [
      // 'ionicons-v4',
      // 'mdi-v5',
      // 'fontawesome-v6',
      // 'eva-icons',
      // 'themify',
      // 'line-awesome',
      // 'roboto-font-latin-ext', // this or either 'roboto-font', NEVER both!

      "roboto-font", // optional, you are not bound to it
      "material-icons" // optional, you are not bound to it
    ],

    // Full list of options: https://v2.quasar.dev/quasar-cli-webpack/quasar-config-js#Property%3A-build
    build: {
      vueRouterMode: "hash", // available values: 'hash', 'history'

      // Silence Sass deprecations (import, legacy-js-api) for Quasar/deps; cross-platform (Linux, Windows, macOS)
      scssLoaderOptions: {
        sassOptions: {
          silenceDeprecations: ["import", "legacy-js-api"]
        }
      },
      sassLoaderOptions: {
        sassOptions: {
          silenceDeprecations: ["import", "legacy-js-api"]
        }
      },

      // transpile: false,
      // publicPath: '/',

      // Add dependencies for transpiling with Babel (Array of string/regex)
      // (from node_modules, which are by default not transpiled).
      // Applies only if "transpile" is set to true.
      // transpileDependencies: [],

      // rtl: true, // https://quasar.dev/options/rtl-support
      // preloadChunks: true,
      // showProgress: false,
      // gzip: true,
      // analyze: true,

      // Options below are automatically set depending on the env, set them if you want to override
      // extractCSS: false,

      // https://v2.quasar.dev/quasar-cli-webpack/handling-webpack
      // "chain" is a webpack-chain object https://github.com/neutrinojs/webpack-chain

      chainWebpack (chain) {
        const nodePolyfillWebpackPlugin = require("node-polyfill-webpack-plugin")
        chain.plugin("node-polyfill").use(nodePolyfillWebpackPlugin)
        // Axios in renderer uses Buffer; provide it globally so resolve never sees "buffer" as path
        chain.plugin("provide-buffer").use(require("webpack").ProvidePlugin, [
          { Buffer: ["buffer", "Buffer"] }
        ])
        chain.resolve.merge({
          fallback: {
            buffer: require.resolve("buffer/")
          }
        })
        chain
          .plugin("eslint-webpack-plugin")
          .use(ESLintPlugin, [{ extensions: ["js", "vue"] }])
        chain
          .module.rule("i18n-resource")
          .test(/\.(json5?|ya?ml)$/)
          .include.add(path.resolve(__dirname, "./src/i18n"))
          .end()
          .type("javascript/auto")
          .use("i18n-resource")
          .loader("@intlify/vue-i18n-loader")
        chain
          .module
          .rule("i18n")
          .resourceQuery(/blockType=i18n/)
          .type("javascript/auto")
          .use("i18n")
          .loader("@intlify/vue-i18n-loader")
      }
    },

    // Full list of options: https://v2.quasar.dev/quasar-cli-webpack/quasar-config-js#Property%3A-devServer
    devServer: {
      server: {
        type: "http"
      },
      port: 8080,
      open: true // opens browser window automatically
    },

    // https://v2.quasar.dev/quasar-cli-webpack/quasar-config-js#Property%3A-framework
    framework: {
      lang: "en-US",
      components: [
        "QLayout",
        "QHeader",
        "QFooter",
        "QDrawer",
        "QPageContainer",
        "QPage",
        "QToolbar",
        "QToolbarTitle",
        "QTooltip",
        "QField",
        "QInput",
        "QRadio",
        "QOptionGroup",
        "QBtn",
        "QBtnToggle",
        "QIcon",
        "QTabs",
        "QTab",
        "QRouteTab",
        "QBtnDropdown",
        "QMenu",
        "QDialog",
        "QCard",
        "QStep",
        "QStepper",
        "QStepperNavigation",
        "QSpinner",
        "QList",
        "QItemLabel",
        "QItem",
        "QSeparator",
        "QItemSection",
        "QSelect",
        "QToggle",
        "QPageSticky",
        "QExpansionItem",
        "QCheckbox",
        "QInnerLoading",
        "QInfiniteScroll",
        "QDate",
        "QTime",
        "QScrollArea"
      ],
      directives: ["Ripple"],
      // Quasar plugins
      plugins: ["Notify", "Loading", "LocalStorage", "Dialog"]
    },

    // animations: 'all', // --- includes all animations
    // https://quasar.dev/options/animations
    animations: [],

    // https://v2.quasar.dev/quasar-cli-webpack/developing-ssr/configuring-ssr
    ssr: {
      pwa: false,

      // manualStoreHydration: true,
      // manualPostHydrationTrigger: true,

      prodPort: 3000, // The default port that the production server should use
      // (gets superseded if process.env.PORT is specified at runtime)

      maxAge: 1000 * 60 * 60 * 24 * 30,
      // Tell browser when a file from the server should expire from cache (in ms)

      chainWebpackWebserver (chain) {
        chain
          .plugin("eslint-webpack-plugin")
          .use(ESLintPlugin, [{ extensions: ["js"] }])
      },

      middlewares: [
        ctx.prod ? "compression" : "",
        "render" // keep this as last one
      ]
    },

    // https://v2.quasar.dev/quasar-cli-webpack/developing-pwa/configuring-pwa
    pwa: {
      workboxPluginMode: "GenerateSW", // 'GenerateSW' or 'InjectManifest'
      workboxOptions: {}, // only for GenerateSW

      // for the custom service worker ONLY (/src-pwa/custom-service-worker.[js|ts])
      // if using workbox in InjectManifest mode

      chainWebpackCustomSW (chain) {
        chain
          .plugin("eslint-webpack-plugin")
          .use(ESLintPlugin, [{ extensions: ["js"] }])
      },

      manifest: {
        // name: "Quasar App",
        // short_name: "Quasar App",
        // description: "A Quasar Project",
        display: "standalone",
        orientation: "portrait",
        background_color: "#ffffff",
        theme_color: "#027be3",
        icons: [
          {
            src: "icons/icon-128x128.png",
            sizes: "128x128",
            type: "image/png"
          },
          {
            src: "icons/icon-192x192.png",
            sizes: "192x192",
            type: "image/png"
          },
          {
            src: "icons/icon-256x256.png",
            sizes: "256x256",
            type: "image/png"
          },
          {
            src: "icons/icon-384x384.png",
            sizes: "384x384",
            type: "image/png"
          },
          {
            src: "icons/icon-512x512.png",
            sizes: "512x512",
            type: "image/png"
          }
        ]
      }
    },

    // Full list of options: https://v2.quasar.dev/quasar-cli-webpack/developing-cordova-apps/configuring-cordova
    cordova: {
      // noIosLegacyBuildFlag: true, // uncomment only if you know what you are doing
    },

    // Full list of options: https://v2.quasar.dev/quasar-cli-webpack/developing-capacitor-apps/configuring-capacitor
    capacitor: {
      hideSplashscreen: true
    },

    // Full list of options: https://v2.quasar.dev/quasar-cli-webpack/developing-electron-apps/configuring-electron
    electron: {
      bundler: "builder", // 'packager' or 'builder'

      packager: {
        // https://github.com/electron-userland/electron-packager/blob/master/docs/api.md#options
        // OS X / Mac App Store
        // appBundleId: '',
        // appCategoryType: '',
        // osxSign: '',
        // protocol: 'myapp://path',
        // Windows only
        // win32metadata: { ... }
        extraResource: [
          "bin",
          ".env"
        ]
      },

      builder: {
        // https://www.electron.build/configuration/configuration
        appId: "com.arqma.wallet",
        productName: "Arqma-Wallet",
        copyright: "Copyright © 2018-2026 Arqma Project, 2020 Ryo Currency Project, 2020 Loki Network",
        buildVersion: "4.0.2",
        artifactName: "Arqma-Wallet.${version}.${os}.${arch}.${ext}",
        // afterSign: "build/notarize.js", // Wyłączone - wygasłe konto deweloperskie

        linux: {
          target: ["AppImage", "tar.xz"],
          icon: "src-electron/icons/icon_512x512.png",
          category: "Finance"
        },

        mac: {
          target: ["dmg", "zip"],
          icon: "src-electron/icons/icon.icns",
          category: "public.app-category.finance",
          identity: null, // Wyłączone podpisywanie - wygasłe konto deweloperskie
          hardenedRuntime: false,
          gatekeeperAssess: false
        },

        dmg: {
          sign: false
        },

        nsis: {
          oneClick: false,
          allowToChangeInstallationDirectory: true
        },
        files: [
          "!build/notarize.js",
          "!.notenv"
        ],
        extraResources: [
          "bin"
        ],
        publish: {
          provider: "github",
          repo: "Arqma-GUI-MM",
          owner: "ArqTras",
          releaseType: "release",
          publishAutoUpdate: true,
          private: true
        }
      },

      // "chain" is a webpack-chain object https://github.com/neutrinojs/webpack-chain

      chainWebpackMain (chain) {
        chain
          .plugin("eslint-webpack-plugin")
          .use(ESLintPlugin, [{ extensions: ["js"] }])
      },

      chainWebpackPreload (chain) {
        chain
          .plugin("eslint-webpack-plugin")
          .use(ESLintPlugin, [{ extensions: ["js"] }])
      }
    }
  }
})
