# On-device Stable Diffusion on iOS

## First-time build

Building `libsd_ios_complete.a` compiles **stable-diffusion.cpp** and **ggml** for the active SDK (device or simulator). The first run can take **several minutes** and requires **network** for CMake `FetchContent`.

Xcode runs `ios/sd_cmake/build_sd_ios.sh` before compiling the Runner target. You can also run it manually:

```bash
cd mobile_app/ios/sd_cmake
export PLATFORM_NAME=iphoneos   # or iphonesimulator
export ARCHS=arm64
./build_sd_ios.sh
```

Output: `ios/Runner/libs/<PLATFORM_NAME>/libsd_ios_complete.a` (gitignored).

## Physical iPhone

- Expect **high RAM use** while loading weights and sampling; close other apps if the process is jetsam-killed.
- The sticker screen **unloads the native model when you close it** so RAM is not held while drawing elsewhere.
- **Xcode Run (Debug)** adds LLDB + diagnostics overhead. For heavy SD runs, set the Run scheme’s **Build Configuration** to **Release** (Edit Scheme → Run), use **`flutter run --release`**, or install a **Release** build from Xcode; turn off **View Debugging** / **GPU Validation** in the scheme if you still attach the debugger.
- **CPU-only** inference (`SD_METAL=OFF`) is slow but matches the Android baseline.
- Default weights are **SDXS-512 tiny distilled** GGUF (~**0.65 GB** Q8_0, `concedo/sdxs-512-tinySDdistilled-GGUF`). Native uses **1 step + cfg 1** (mandatory for SDXS). If you switch to **`lcm-ssd-1b*.gguf`**, the bridge turns on **LCM** sampler/scheduler. Mmap + low thread count + VAE tiling stay on.

## Simulator

- The same **arm64** (Apple Silicon) or **x86_64** (Intel) static library is built for `iphonesimulator`.
- Performance is poor; use a **real device** for meaningful sticker latency tests.

## Troubleshooting

- **Android CMake / FetchContent** fails with submodule errors: the project only initializes the `ggml` submodule (not the optional server UI). If you still see clone failures, delete `android/app/.cxx` and `build/.cxx` and rebuild with a stable network.
- **Link errors** for `libsd_ios_complete.a`: run the script manually and confirm the file exists under `Runner/libs/$(PLATFORM_NAME)/`.
- **`libtool` errors**: use Xcode’s toolchain (`/usr/bin/libtool -static`).
- **Duplicate symbols** when merging archives: report upstream; you may need to trim which `.a` files are merged in `build_sd_ios.sh`.
