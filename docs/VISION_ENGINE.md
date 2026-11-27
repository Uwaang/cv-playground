# CV Playground Native Vision Engine

## Design

- **One application repository**: Flutter app and local Dart/C++ package.
- **OpenCV source**: official `opencv/opencv` Git submodule at `third_party/opencv`, pinned to release **4.14.0** (commit `0654a42e19`). Do not directly edit upstream OpenCV.
- **Compilation**: CMake builds OpenCV from source with `BUILD_SHARED_LIBS=OFF` and initial modules `core,imgproc`. The C++ FFI boundary is exported from one `vision_engine` shared library for platforms supporting that packaging model.
- **Initial dependency policy**: Disable Intel IPP and OpenCV Android example projects. These are optional for the first grayscale Canny smoke test and caused failures on the first Linux/Android Actions run.
- **CMake header propagation**: The bundled build exposes the OpenCV core/imgproc public include directories explicitly to `vision_engine`; linking OpenCV's static targets alone did not expose those headers on several GitHub-hosted platforms.
- **Generated headers**: OpenCV's generated `opencv2/opencv_modules.hpp` must also be reachable from the containing CMake build directory.
- **Windows CRT**: Keep OpenCV static libraries and the shared engine on the same MSVC dynamic CRT (`/MD`) using `BUILD_WITH_STATIC_CRT=OFF`. Static OpenCV linking is separate from the C runtime linking choice.
- **Native Assets logging**: The build hook uses an inherited logger level, rather than setting a named logger's level while hierarchical logging is disabled.
- **Windows smoke test**: CMake copies the engine DLL next to the CTest executable so the Windows loader can resolve it without modifying the runner's global PATH.
- **Dart integration**: `packages/vision_engine` contains `hook/build.dart` and a C ABI accessed through Dart `@Native` declarations. The native-assets CMake adapter is experimental: platform builds must verify hook output, packaging, and runtime loading before the app depends on it.
- **Current algorithm**: The new Flutter Image Playground picks PNG/JPEG with `file_selector`, downsizes to a maximum dimension of 1024 pixels, converts to grayscale in a Dart Isolate, and calls Canny through the C ABI. This is **not** a zero-copy real-time camera pipeline.
- **Web**: The page supports selecting and previewing an image, but native Canny is unavailable; WebAssembly OpenCV requires a separate bridge.
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

To exercise the Dart Native Assets adapter, resolve dependencies in `packages/vision_engine` and run `dart test` on a native platform. Native Flutter packaging and file selection still require independent platform CI and manual device validation.

## CI boundaries

The inherited Flutter template already compiles Web JS, Web WASM, Android, iOS, Windows, Linux and macOS. The new `native-vision.yml` separately attempts the 5 native target operating systems with source-built OpenCV. **No build or runtime pass is claimed until Actions runs succeed.** iOS packaging, Android C++ runtime bundling and loading, and browser WASM remain explicit follow-up validation tasks.

## Update policy

Change the submodule pointer in its own reviewable update. Test a normal native C++ build, the FFI ABI, and the affected platforms before adoption. Keep the C API backwards compatible where possible; version it if semantics or layout changes. Do not create per-platform code forks without a measured need.

## Remote repository

The cloned development workspace initially points at its source template as `template-upstream`. Create a distinct `Uwaang/cv-playground` GitHub repository and configure it as the new `origin` before pushing. Never push project changes to the source template.

## Expanded operation suite — Issue #4

The current feature branch adds a native grayscale operation registry with 37
selectable OpenCV functions. The original Canny C ABI remains available.
Input PNG/JPEG is decoded, orientation-corrected, limited to 1024 pixels on
the longest side, converted to grayscale and processed off the Flutter UI
isolate. Second images are resized to the first image size. The Dart caller
owns all buffers across the FFI boundary; metadata is copied to a bounded
caller-owned UTF-8 buffer.

Enabled modules: core, imgproc, features2d, calib3d, objdetect, dnn,
video and photo. These increase native compile time and binary size.

| Domain | Demo operations | Known limitations |
| --- | --- | --- |
| Image processing | Blur, threshold, Canny/Sobel/Laplacian, morphology, CLAHE, histogram, contours, Hough | 8-bit grayscale output |
| Features and geometry | ORB, QR, ArUco, matched keypoints, RANSAC homography | Pair matching requires suitable textured images |
| Video analysis | Dense Farneback flow and motion difference | Two selected frames only, no live camera or temporal tracker |
| Photography | Denoise, scratch inpaint, exposure fusion, blended aligned views | Scratch mask uses bright-pixel threshold; panorama is cropped to input size |
| Camera / 3D | Chessboard corner display, illustrative undistort, StereoBM disparity | No complete multi-view calibration, need rectified stereo pair |
| DNN | Local ONNX YOLO boxes and scores, CPU, COCO class names | Supports raw 640x640 YOLOv8/YOLO11-like detection outputs only |

### Models and licensing

The app does not bundle, download, share or upload model weights. Choose a
compatible local raw YOLO ONNX model (without baked-in NMS); the file is staged
in the app's temporary directory (128 MB limit). CPU inference first resizes
grayscale input to 640x640 BGR and parses common YOLO box tensors.
Other shapes, segmentation masks and model-specific preprocessing are not
supported. COCO labels are correct only for COCO-trained models. Verify
licenses for any third-party weights: Ultralytics YOLO models can be subject
to AGPL-3.0 or a commercial Enterprise license.

Web is preview-only: C++ Native Assets are not executed in JavaScript/WASM
builds. Camera capture, live video, real calibration, and ONNX Runtime are
separate future features. Native CI, Dart FFI smoke, real images and a real
ONNX model are required before this proposed suite can be called verified.
