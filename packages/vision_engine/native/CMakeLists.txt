cmake_minimum_required(VERSION 3.24)
project(vision_engine LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(VISION_ENGINE_BUNDLED_OPENCV "Compile OpenCV from the pinned submodule" ON)

if(VISION_ENGINE_BUNDLED_OPENCV)
  set(OPENCV_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../third_party/opencv"
      CACHE PATH "Pinned OpenCV submodule path")
  if(NOT EXISTS "${OPENCV_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "OpenCV submodule missing. Run: git submodule update --init --recursive")
  endif()

  # OpenCV becomes static code inside our one FFI shared library.
  set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
  set(BUILD_LIST "core,imgproc" CACHE STRING "" FORCE)
  set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(BUILD_PERF_TESTS OFF CACHE BOOL "" FORCE)
  set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(BUILD_opencv_apps OFF CACHE BOOL "" FORCE)
  set(BUILD_JAVA OFF CACHE BOOL "" FORCE)
  set(BUILD_opencv_python2 OFF CACHE BOOL "" FORCE)
  set(BUILD_opencv_python3 OFF CACHE BOOL "" FORCE)
  set(WITH_FFMPEG OFF CACHE BOOL "" FORCE)
  set(WITH_GSTREAMER OFF CACHE BOOL "" FORCE)
  set(WITH_GTK OFF CACHE BOOL "" FORCE)
  set(WITH_QT OFF CACHE BOOL "" FORCE)

  add_subdirectory("${OPENCV_SOURCE_DIR}"
                   "${CMAKE_CURRENT_BINARY_DIR}/opencv-build"
                   EXCLUDE_FROM_ALL)
  set(VISION_OPENCV_LIBS opencv_core opencv_imgproc)
else()
  find_package(OpenCV REQUIRED COMPONENTS core imgproc)
  set(VISION_OPENCV_LIBS ${OpenCV_LIBS})
endif()

add_library(vision_engine SHARED src/vision_engine.cpp)
target_compile_definitions(vision_engine PRIVATE VISION_ENGINE_BUILD)
target_include_directories(vision_engine PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(vision_engine PRIVATE ${VISION_OPENCV_LIBS})

set_target_properties(vision_engine PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
)

install(TARGETS vision_engine
  RUNTIME DESTINATION lib
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib)

# Native host smoke checks. Cross-compiled mobile targets remain compile-only.
include(CTest)
if(BUILD_TESTING AND NOT CMAKE_CROSSCOMPILING)
  add_executable(vision_engine_smoke test/vision_engine_smoke.cpp)
  target_link_libraries(vision_engine_smoke PRIVATE vision_engine)
  add_test(NAME vision_engine_smoke COMMAND vision_engine_smoke)
endif()
