#include "vision_engine.h"

#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>

int main() {
  if (vision_engine_abi_version() != 1) return 1;
  const char* version = vision_engine_opencv_version();
  if (version == nullptr || std::strncmp(version, "4.14.0", 6) != 0) return 2;

  const int width = 64;
  const int height = 64;
  std::vector<uint8_t> input(width * height, 0);
  std::vector<uint8_t> output(width * height, 0);
  for (int y = 16; y < 48; ++y) {
    for (int x = 16; x < 48; ++x) {
      input[y * width + x] = 255;
    }
  }
  if (vision_engine_canny_gray(input.data(), width, height, width,
                               output.data(), width, 50, 150) != 0) {
    return 3;
  }
  bool saw_edge = false;
  for (uint8_t pixel : output) saw_edge |= pixel != 0;
  if (!saw_edge) return 4;
  std::cout << "OpenCV " << version << ", ABI 1, Canny smoke passed\n";
  return 0;
}
