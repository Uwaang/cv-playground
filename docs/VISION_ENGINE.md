# CV Playground Native Vision Engine

## Design

- **One application repository**: Flutter app and local Dart/C++ package.
- **OpenCV source**: official `opencv/opencv` Git submodule at `third_party/opencv`, pinned to release **4.14.0** (commit `0654a42e19215ef25b1d367d822f3c630447e7c7`). Do not directly edit upstream OpenCV.
- **Compilation**: CMake builds OpenCV from source with `BUILD_SHARED_LIBS=OFF` and initial modules `core,imgproc`. The C++ FFI boundary is exported from one `vision_engine` shared library for platforms supporting that packaging model.
- **Initial dependency policy**: Disable Intel IPP and OpenCV Android example projects. These are optional for the first grayscale Canny smoke test and caused failures on the first Linux/Android Actions run.
- **CMake header propagation**: The bundled build exposes the OpenCV core/imgproc public include directories explicitly to `vision_engine`; linking OpenCV's static targets alone did not expose those headers on several GitHub-hosted platforms.
- **Generated headers**: OpenCV's generated `opencv2/opencv_modules.hpp` must also be reachable from the containing CMake build directory.
- **Windows CRT**: Keep OpenCV static libraries and the shared engine on the same MSVC dynamic CRT (`/MD`) using `BUILD_WITH_STATIC_CRT=OFF`. Static OpenCV linking is separate from the C runtime linking choice.
- **Native Assets logging**: The build hook uses an inherited logger level, rather than setting a named logger's level while hierarchical logging is disabled.
- **Dart integration**: `packages/vision_engine` contains `hook/build.dart` and a C ABI accessed through Dart `@Native` declarations. The native-assets CMake adapter is experimental: platform builds must verify hook output, packaging, and runtime loading before the app depends on it.
- **Current algorithm**: Canny on packed 8-bit grayscale images, as an intentionally small FFI smoke test. The Dart API copies pixels; this is **not** a zero-copy real-time camera pipeline.
- **Camera**: Flutter-first when implemented, only add native camera capture if performance tests justify it.
- **ORT/Web**: not yet integrated. Web requires a separate WASM-compatible bridge; native `dart:ffi` cannot run in browsers.

## Source and build

After checkout:

```bash
git submodule update --init --recursive

# Build native engine directly (host platform; CMake 3.24+)
cmake -S packages/vision_engine/native -B build/vision-native -DCMAKE_BUILD_TYPE=Release
cmake --build build/vision-native --config Release --parallel
```

To exercise the Dart Native Assets adapter, resolve dependencies in `packages/vision_engine` and run `dart test` on a native platform. This must be completed and validated in CI before adding `vision_engine` as a production dependency of the Flutter app.

## CI boundaries

The inherited Flutter template already compiles Web JS, Web WASM, Android, iOS, Windows, Linux and macOS. The new `native-vision.yml` separately attempts the 5 native target operating systems with source-built OpenCV. **No build or runtime pass is claimed until Actions runs succeed.** iOS packaging, Android C++ runtime bundling and loading, and browser WASM remain explicit follow-up validation tasks.

## Update policy

Change the submodule pointer in its own reviewable update. Test a normal native C++ build, the FFI ABI, and the affected platforms before adoption. Keep the C API backwards compatible where possible; version it if semantics or layout changes. Do not create per-platform code forks without a measured need.

## Remote repository

The cloned development workspace initially points at its source template as `template-upstream`. Create a distinct `Uwaang/cv-playground` GitHub repository and configure it as the new `origin` before pushing. Never push project changes to the source template.
