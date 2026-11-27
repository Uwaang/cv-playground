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
  # The engine DLL uses MSVC's dynamic CRT (/MD); use the same CRT for
  # static OpenCV libraries to avoid LNK2038 and duplicate CRT symbols.
  set(BUILD_WITH_STATIC_CRT OFF CACHE BOOL "" FORCE)
  set(BUILD_LIST "core,imgproc,flann,features2d,calib3d,objdetect,dnn,video,photo" CACHE STRING "" FORCE)
  set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(BUILD_PERF_TESTS OFF CACHE BOOL "" FORCE)
  set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  # BUILD_EXAMPLES does not control OpenCV's separate Android sample projects.
  set(BUILD_ANDROID_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(INSTALL_ANDROID_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(BUILD_opencv_apps OFF CACHE BOOL "" FORCE)
  set(BUILD_JAVA OFF CACHE BOOL "" FORCE)
  set(BUILD_opencv_python2 OFF CACHE BOOL "" FORCE)
  set(BUILD_opencv_python3 OFF CACHE BOOL "" FORCE)
  set(WITH_FFMPEG OFF CACHE BOOL "" FORCE)
  set(WITH_GSTREAMER OFF CACHE BOOL "" FORCE)
  set(WITH_GTK OFF CACHE BOOL "" FORCE)
  set(WITH_QT OFF CACHE BOOL "" FORCE)
  # Minimal cross-platform first build: avoid optional Intel IPP/IPP HAL
  # libraries (also eliminates the current Linux ipphal header failure).
  set(WITH_IPP OFF CACHE BOOL "" FORCE)
  set(BUILD_IPP_IW OFF CACHE BOOL "" FORCE)

  add_subdirectory("${OPENCV_SOURCE_DIR}"
                   "${CMAKE_CURRENT_BINARY_DIR}/opencv-build"
                   EXCLUDE_FROM_ALL)
  set(VISION_OPENCV_LIBS opencv_core opencv_imgproc opencv_features2d
      opencv_calib3d opencv_objdetect opencv_dnn opencv_video opencv_photo
       opencv_flann)
else()
  find_package(OpenCV REQUIRED COMPONENTS core imgproc flann features2d calib3d objdetect dnn video photo)
  set(VISION_OPENCV_LIBS ${OpenCV_LIBS})
endif()

add_library(vision_engine SHARED src/vision_engine.cpp)
target_compile_definitions(vision_engine PRIVATE VISION_ENGINE_BUILD)
target_include_directories(vision_engine PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
if(VISION_ENGINE_BUNDLED_OPENCV)
  # OpenCV's in-tree static targets do not consistently export the public
  # headers to external targets in every platform/SDK configuration.
  target_include_directories(vision_engine PRIVATE
    "${OPENCV_SOURCE_DIR}/modules/core/include"
    "${OPENCV_SOURCE_DIR}/modules/imgproc/include"
    "${OPENCV_SOURCE_DIR}/modules/flann/include"
    "${OPENCV_SOURCE_DIR}/modules/features2d/include"
    "${OPENCV_SOURCE_DIR}/modules/calib3d/include"
    "${OPENCV_SOURCE_DIR}/modules/objdetect/include"
    "${OPENCV_SOURCE_DIR}/modules/dnn/include"
    "${OPENCV_SOURCE_DIR}/modules/video/include"
    "${OPENCV_SOURCE_DIR}/modules/photo/include"
    # OpenCV generates opencv2/opencv_modules.hpp under CMAKE_BINARY_DIR.
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}/opencv-build"
  )
endif()
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
  if(WIN32)
    # The Windows test executable lives under bin/Release, while our DLL
    # is built under Release. Put the DLL next to the test for CTest.
    add_custom_command(TARGET vision_engine_smoke POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
              "$<TARGET_FILE:vision_engine>"
              "$<TARGET_FILE_DIR:vision_engine_smoke>"
      VERBATIM
    )
  endif()
  add_test(NAME vision_engine_smoke COMMAND vision_engine_smoke)
endif()
