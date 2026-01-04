# Quasar App (quasar-project)

A Quasar Project 3.9.0

## Notice Win 10 support

For windows 10 support is needed VC Redist library that can be downloaded from official MS site

https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170

For win 10 x64

https://aka.ms/vs/17/release/vc_redist.x64.exe

## Install the dependencies

```bash
yarn
# or
npm install
```

### Start the app in development mode (hot-code reloading, error reporting, etc.)

```bash
quasar dev
```

### Lint the files

```bash
yarn lint
# or
npm run lint
```

### Format the files

```bash
yarn format
# or
npm run format
```

### Build the app for production

```bash
quasar build
```

### Customize the configuration

See [Configuring quasar.config.js](https://v2.quasar.dev/quasar-cli-webpack/quasar-config-js).

### Log Files

%APPDATE%\Roaming\Arqma-Electron-Wallet\logs\Arqma.log on Windows
C:\Users\{USERNAME}\AppData\Roaming\Arqma-Electron-Wallet\logs\Arqma.log

~/.config/Arqma-Electron-Wallet/logs/Arqma.log on Linux
/home/{USERNAME}/.config/Arqma-Electron-Wallet/logs/Arqma.log

~/library/Application Support/Arqma-Electron-Wallet/logs/Arqma.log on macOS
/System/Volumes/Data/Users/{USERNAME}/Library/Application Support/Arqma-Electron-Wallet/logs/Arqma.log


### Watching Logs

## Linux
watch tail -n 10 ~/.config/Arqma-Electron-Wallet/logs/Arqma.log

## maxOS
watch tail -n 10 ~/library/Application Support/Arqma-Electron-Wallet/logs/Arqma.log
