/// Minimal public API to the in-repository OpenCV C++ engine.
/// Camera integration and Web support are intentionally separate decisions.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

@Native<Int32 Function()>(symbol: 'vision_engine_abi_version')
external int _abiVersion();

@Native<Pointer<Char> Function()>(symbol: 'vision_engine_opencv_version')
external Pointer<Char> _opencvVersion();

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
    Pointer<Uint8>,
    Int32,
    Double,
    Double
  )
>(symbol: 'vision_engine_canny_gray')
external int _cannyGray(
  Pointer<Uint8> input,
  int width,
  int height,
  int inputStride,
  Pointer<Uint8> output,
  int outputStride,
  double lowThreshold,
  double highThreshold,
);

int get visionEngineAbiVersion => _abiVersion();

String get openCvVersion => _opencvVersion().cast<Utf8>().toDartString();

/// Canny on a packed 8-bit grayscale image (not RGB/YUV camera planes).
///
/// This first implementation copies both buffers across FFI. It is suitable
/// for still-image validation; real-time streaming needs a separate buffer API.
Uint8List cannyGray(
  Uint8List grayscale, {
  required int width,
  required int height,
  required double lowThreshold,
  required double highThreshold,
}) {
  if (width <= 0 ||
      height <= 0 ||
      grayscale.length != width * height ||
      lowThreshold < 0 ||
      highThreshold < lowThreshold) {
    throw ArgumentError('Invalid dimensions, input length or Canny thresholds.');
  }

  final input = calloc<Uint8>(grayscale.length);
  final output = calloc<Uint8>(grayscale.length);
  try {
    input.asTypedList(grayscale.length).setAll(0, grayscale);
    final status = _cannyGray(
      input, width, height, width, output, width, lowThreshold, highThreshold,
    );
    if (status != 0) {
      throw StateError('OpenCV Canny failed: native error $status');
    }
    return Uint8List.fromList(output.asTypedList(grayscale.length));
  } finally {
    calloc.free(output);
    calloc.free(input);
  }
}
