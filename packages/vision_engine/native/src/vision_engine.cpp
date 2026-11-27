#include "vision_engine.h"

#include <cstring>
#include <exception>
#include <opencv2/core.hpp>
#include <opencv2/core/version.hpp>
#include <opencv2/imgproc.hpp>

extern "C" {

int32_t vision_engine_abi_version(void) { return 1; }

const char* vision_engine_opencv_version(void) { return CV_VERSION; }

int32_t vision_engine_canny_gray(
    const uint8_t* input, int32_t width, int32_t height, int32_t input_stride,
    uint8_t* output, int32_t output_stride,
    double low_threshold, double high_threshold) {
  if (!input || !output || width <= 0 || height <= 0 ||
      input_stride < width || output_stride < width ||
      low_threshold < 0 || high_threshold < low_threshold) {
    return -1;
  }

  try {
    cv::Mat source(height, width, CV_8UC1,
                   const_cast<uint8_t*>(input), input_stride);
    cv::Mat edges;
    cv::Canny(source, edges, low_threshold, high_threshold);

    for (int32_t row = 0; row < height; ++row) {
      std::memcpy(output + static_cast<size_t>(row) * output_stride,
                  edges.ptr(row), static_cast<size_t>(width));
    }
    return 0;
  } catch (const cv::Exception&) {
    return -2;
  } catch (const std::exception&) {
    return -3;
  } catch (...) {
    return -3;
  }
}

}  // extern "C"
