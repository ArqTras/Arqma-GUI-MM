# Arqma Wallet — Android (Flutter)

Android-focused shell derived from `flutter-mobile/` (`arqma_wallet_mobile`). Same UI and `MobileNativeBridge` (remote nodes only, in-process `arqma-wallet-flutter-ffi`).

## Layout

```
flutter-android/
  README.md
  arqma_wallet_android/    # Flutter app (lib/, android/, assets/)
```

## Prerequisites

- Flutter SDK ≥ 3.41.9
- **JDK 17** for Gradle (`JAVA_HOME` must not point at Java 8 — otherwise `assembleDebug` fails with “requires at least JVM runtime version 11”)
- Android SDK + NDK (Android Studio or `sdkmanager`)
- Rust toolchain + **Android NDK** for `aarch64-linux-android` (and optional `armv7-linux-androideabi`)
- Arqma `wallet_merged` for Android (see `rust/docs/NATIVE_WALLET2.md` and `rust/tool/build_android_wallet_merged.sh`)

## Wallet FFI (prebuilt from GitHub Release)

Prebuilt binaries: [ArqTras/FFI releases](https://github.com/ArqTras/FFI/releases) (default `ARQMA_FFI_RELEASE_VERSION=1.0.0`). **Android x86_64** artifacts from **1.0.0** may fail at runtime (`epee` symbols) — use a newer FFI tag after rebuild, or set `ARQMA_BUILD_FFI_FROM_SOURCE=1` and build with `rust/tool/build_mobile_wallet_ffi_android.sh` (WSL/Linux).

From repository root (downloads into `.prebuilt/arqma-wallet-ffi/1.0.0/` and copies into `jniLibs`):

```powershell
.\build\ci\fetch-arqma-wallet-ffi-release.ps1 -Platforms android-arm64,android-x86_64
.\flutter-android\arqma_wallet_android\tool\copy_android_wallet_ffi.ps1
```

`copy_android_wallet_ffi.ps1` runs the fetch automatically when prebuilts are missing. To compile FFI locally instead, set `ARQMA_BUILD_FFI_FROM_SOURCE=1` and use `rust/tool/build_mobile_wallet_ffi_android.sh` (WSL recommended).

## Run on device / emulator

```bash
cd flutter-android/arqma_wallet_android
flutter pub get
flutter run -d android
# release APK (after FFI copy):
./tool/package_android_release.sh
# or:
flutter build apk --release
```

Override FFI path: `ARQMA_FLUTTER_WALLET_FFI=/absolute/path/to/libarqma_wallet_flutter_ffi.so`

UI-only without FFI: `ARQMA_FLUTTER_USE_STUB=1 flutter run -d android`

## Android-specific notes

- **Remote JSON-RPC** uses cleartext HTTP to public nodes (port 19994) — `android:usesCleartextTraffic` is enabled (parity with iOS ATS exceptions).
- **No local daemon** — same as iOS mobile; pick node1–node4 in settings.
- **ABI**: phones use `arm64-v8a`. Prebuilts include **arm64** and **x86_64**; `copy_android_wallet_ffi.ps1` also copies **`libc++_shared.so`** from the installed Android NDK (required to load the FFI `.so`).
- **Emulator on Windows (x86_64 PC)**: use an **x86_64** AVD (e.g. `Arqma_API_34`), not `Arqma_API_34_arm64` — QEMU cannot run arm64 system images on an x86_64 host.
- **WSL / checkout on Windows**: before `contrib/depends`, strip CRLF:  
  `find rust/arqma-rpc-upstream/contrib/depends -type f -exec sed -i 's/\r$//' {} +`
- **UI without FFI** (emulator smoke test): `ARQMA_FLUTTER_USE_STUB=1 flutter run -d android`

## iOS

Use `flutter-mobile/` on branch `mobile` for iOS / TestFlight; this tree is maintained for **Android** only.
