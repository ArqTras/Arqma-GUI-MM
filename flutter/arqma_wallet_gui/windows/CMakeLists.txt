# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(arqma_wallet_gui LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
# Matches Tauri `productName` / macOS `PRODUCT_NAME` (Arqma-Wallet).
set(BINARY_NAME "Arqma-Wallet")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
if(IS_DIRECTORY "${NATIVE_ASSETS_DIR}")
  install(DIRECTORY "${NATIVE_ASSETS_DIR}"
     DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
     COMPONENT Runtime)
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Arqma Windows binaries — same `src-tauri/bin` as Tauri; installed next to the app under `bin/`.
set(_arqma_tauri_bin "${CMAKE_CURRENT_SOURCE_DIR}/../../../rust/tauri-app/src-tauri/bin")
foreach(_n IN ITEMS arqmad.exe arqma_flutter_solo_pool.exe)
  if(EXISTS "${_arqma_tauri_bin}/${_n}")
    install(FILES "${_arqma_tauri_bin}/${_n}" DESTINATION "${CMAKE_INSTALL_PREFIX}/bin" COMPONENT Runtime)
  endif()
endforeach()

# Native wallet2 FFI — DLL under `Release/lib/` (see `wallet_native_ffi.dart`, `install_arqma_wallet_ffi.cmake.in`).
# **Prefer `x86_64-pc-windows-gnu` (MinGW)** over host `target/{debug,release}/` (MSVC): same as
# Tauri Windows CI (`ci:tauri:native:windows-gnu`) and `arqma-wallet2-api` + `libwallet_merged.a` from `build-mingw`.
# Picking MSVC `target/release/*.dll` when `wallet_merged` was built with MinGW causes wrong / unloadable FFI.
# Profile/Release require the DLL; Debug skips fatal error so you can iterate UI without Rust.
set(_rust_root "${CMAKE_CURRENT_SOURCE_DIR}/../../../rust")
set(_wallet_ffi_win "")
if(EXISTS "${_rust_root}/target/x86_64-pc-windows-gnu/release/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/target/x86_64-pc-windows-gnu/release/arqma_wallet_flutter_ffi.dll")
elseif(EXISTS "${_rust_root}/target/x86_64-pc-windows-gnu/debug/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/target/x86_64-pc-windows-gnu/debug/arqma_wallet_flutter_ffi.dll")
elseif(EXISTS "${_rust_root}/tauri-app/src-tauri/target/x86_64-pc-windows-gnu/release/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/tauri-app/src-tauri/target/x86_64-pc-windows-gnu/release/arqma_wallet_flutter_ffi.dll")
elseif(EXISTS "${_rust_root}/tauri-app/src-tauri/target/x86_64-pc-windows-gnu/debug/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/tauri-app/src-tauri/target/x86_64-pc-windows-gnu/debug/arqma_wallet_flutter_ffi.dll")
elseif(EXISTS "${_rust_root}/target/release/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/target/release/arqma_wallet_flutter_ffi.dll")
elseif(EXISTS "${_rust_root}/target/debug/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/target/debug/arqma_wallet_flutter_ffi.dll")
elseif(EXISTS "${_rust_root}/tauri-app/src-tauri/target/release/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/tauri-app/src-tauri/target/release/arqma_wallet_flutter_ffi.dll")
elseif(EXISTS "${_rust_root}/tauri-app/src-tauri/target/debug/arqma_wallet_flutter_ffi.dll")
  set(_wallet_ffi_win "${_rust_root}/tauri-app/src-tauri/target/debug/arqma_wallet_flutter_ffi.dll")
endif()
# Single-config generators (Ninja): fail fast for non-Debug without the DLL. Multi-config (VS) has no
# CMAKE_BUILD_TYPE at configure time — warn only; ensure the DLL is built before packaging Release.
get_property(_arqma_gen_multi GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(_wallet_ffi_win STREQUAL "" AND NOT _arqma_gen_multi AND NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  message(FATAL_ERROR "Windows bundle (${CMAKE_BUILD_TYPE}) requires arqma_wallet_flutter_ffi.dll — build the FFI crate (see rust/tool/build_wallet_flutter_ffi.sh).")
endif()
if(_wallet_ffi_win STREQUAL "" AND _arqma_gen_multi)
  message(WARNING "arqma_wallet_flutter_ffi.dll not found under rust/target; Profile/Release packages need a prior `cargo build -p arqma-wallet-flutter-ffi --release`.")
endif()
# Copy FFI + MinGW deps at **install** time (see `cmake/install_arqma_wallet_ffi.cmake.in`):
# configure-time `install(FILES)`/`file(GLOB)` misses DLLs built or updated after the first CMake run.
# Do not use CMAKE_INSTALL_PREFIX in that script: VS multi-config leaves it as $<TARGET_FILE_DIR:...>
# which breaks file(COPY). Use concrete runner/{Debug,Profile,Release} dirs instead.
set(_arqma_ffi_install_in "${CMAKE_CURRENT_SOURCE_DIR}/cmake/install_arqma_wallet_ffi.cmake.in")
set(_arqma_ffi_install_gen "${CMAKE_CURRENT_BINARY_DIR}/install_arqma_wallet_ffi.gen.cmake")
set(ARQMA_WALLET_FFI_RUST_ROOT "${_rust_root}")
set(ARQMA_WIN_BUNDLE_DEBUG "${CMAKE_CURRENT_BINARY_DIR}/runner/Debug")
set(ARQMA_WIN_BUNDLE_PROFILE "${CMAKE_CURRENT_BINARY_DIR}/runner/Profile")
set(ARQMA_WIN_BUNDLE_RELEASE "${CMAKE_CURRENT_BINARY_DIR}/runner/Release")
configure_file("${_arqma_ffi_install_in}" "${_arqma_ffi_install_gen}" @ONLY)
install(SCRIPT "${_arqma_ffi_install_gen}" COMPONENT Runtime)
