#ifndef VISION_ENGINE_H_
#define VISION_ENGINE_H_

#include <stdint.h>

#if defined(_WIN32)
  #if defined(VISION_ENGINE_BUILD)
    #define VISION_ENGINE_API __declspec(dllexport)
  #else
    #define VISION_ENGINE_API __declspec(dllimport)
  #endif
#else
  #define VISION_ENGINE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ABI v1. C buffers are caller-owned: OpenCV objects never cross the boundary.
VISION_ENGINE_API int32_t vision_engine_abi_version(void);
VISION_ENGINE_API const char* vision_engine_opencv_version(void);

// Legacy Canny entry point. Strides are bytes; gray is 8-bit single channel.
VISION_ENGINE_API int32_t vision_engine_canny_gray(
    const uint8_t* input, int32_t width, int32_t height, int32_t input_stride,
    uint8_t* output, int32_t output_stride,
    double low_threshold, double high_threshold);

// Apply an operation from lib/features/vision_demo/vision_operations.dart.
// A second, already resized gray frame is required for pair-based operations.
// model_path is only required for operation 31 (YOLO ONNX).
// Input/output are width * height 8-bit grayscale; stride in bytes.
// metadata is a caller-owned NUL-terminated UTF-8 buffer.
// 0 success, -1 invalid arguments, -2 OpenCV error, -3 unexpected error,
// -4 insufficient feature matches or unsupported model output.
VISION_ENGINE_API int32_t vision_engine_process_gray(
    const uint8_t* input, int32_t width, int32_t height, int32_t input_stride,
    const uint8_t* second, int32_t second_stride,
    uint8_t* output, int32_t output_stride,
    int32_t operation, double parameter_a, double parameter_b,
    const char* model_path, char* metadata, int32_t metadata_capacity);

#ifdef __cplusplus
}
#endif

#endif  // VISION_ENGINE_H_
