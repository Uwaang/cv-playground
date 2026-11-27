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

// ABI v1. All functions must remain C-compatible; no cv::Mat crosses this boundary.
VISION_ENGINE_API int32_t vision_engine_abi_version(void);
VISION_ENGINE_API const char* vision_engine_opencv_version(void);

// 8-bit single-channel input/output. Stride is in bytes.
// 0 = success; -1 = invalid arguments; -2 = OpenCV error; -3 = unexpected error.
// Caller owns both buffers; writes only width bytes per output row.
VISION_ENGINE_API int32_t vision_engine_canny_gray(
    const uint8_t* input, int32_t width, int32_t height, int32_t input_stride,
    uint8_t* output, int32_t output_stride,
    double low_threshold, double high_threshold);

#ifdef __cplusplus
}
#endif

#endif  // VISION_ENGINE_H_
