#include "vision_engine.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

int main() {
  if (vision_engine_abi_version() != 1) return 1;
  const char* version = vision_engine_opencv_version();
  if (version == nullptr || std::strncmp(version, "4.14.0", 6) != 0) return 2;

  const int width = 160;
  const int height = 96;
  std::vector<uint8_t> input(width * height, 0);
  std::vector<uint8_t> output(width * height, 0);
  std::vector<uint8_t> second(width * height, 0);
  char metadata[512] = {0};
  for (int y = 16; y < 70; ++y) {
    for (int x = 16; x < 70; ++x) {
      input[y * width + x] = 255;
      second[y * width + x + 6] = 255;
    }
  }
  if (vision_engine_canny_gray(input.data(), width, height, width,
                               output.data(), width, 50, 150) != 0) return 3;
  const bool saw_edge = std::any_of(
      output.begin(), output.end(), [](uint8_t pixel) { return pixel != 0; });
  if (!saw_edge) return 4;

  const int simple_operations[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
                                   12, 13, 14, 15, 16, 18, 19, 20, 21,
                                   22, 23, 26, 27, 33, 35, 36};
  for (int op : simple_operations) {
    std::fill(output.begin(), output.end(), 0);
    double a = 5, b = 30;
    if (op == 0) { a = 50; b = 150; }
    const int code = vision_engine_process_gray(
        input.data(), width, height, width, nullptr, 0,
        output.data(), width, op, a, b, nullptr,
        metadata, sizeof(metadata));
    if (code != 0) {
      std::cerr << "OpenCV operation " << op << " failed: " << code << '\n';
      return 10 + op;
    }
  }

  for (int op : {24, 25, 28, 29, 32}) {
    const int code = vision_engine_process_gray(
        input.data(), width, height, width, second.data(), width,
        output.data(), width, op, 9, 30, nullptr,
        metadata, sizeof(metadata));
    if (code != 0) {
      std::cerr << "OpenCV paired operation " << op << " failed: " << code << '\n';
      return 60 + op;
    }
  }
  if (vision_engine_process_gray(
          input.data(), width, height, width, nullptr, 0,
          output.data(), width, 24, 0, 0, nullptr,
          metadata, sizeof(metadata)) != -1) return 99;
  std::cout << "OpenCV " << version
            << ", ABI 1, Canny and extended operation smoke passed\n";
  return 0;
}
