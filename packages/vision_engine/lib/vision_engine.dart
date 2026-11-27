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
    Double,
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
    throw ArgumentError(
      'Invalid dimensions, input length or Canny thresholds.',
    );
  }

  final input = calloc<Uint8>(grayscale.length);
  final output = calloc<Uint8>(grayscale.length);
  try {
    input.asTypedList(grayscale.length).setAll(0, grayscale);
    final status = _cannyGray(
      input,
      width,
      height,
      width,
      output,
      width,
      lowThreshold,
      highThreshold,
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

/// A grayscale output owned by Dart and optional native diagnostic summary.
class VisionNativeResult {
  const VisionNativeResult({required this.pixels, required this.metadata});

  final Uint8List pixels;
  final String metadata;
}

@Native<
  Int32 Function(
    Pointer<Uint8>,
    Int32,
    Int32,
    Int32,
    Pointer<Uint8>,
    Int32,
    Pointer<Uint8>,
    Int32,
    Int32,
    Double,
    Double,
    Pointer<Utf8>,
    Pointer<Uint8>,
    Int32,
  )
>(symbol: 'vision_engine_process_gray')
external int _processGray(
  Pointer<Uint8> input,
  int width,
  int height,
  int inputStride,
  Pointer<Uint8> second,
  int secondStride,
  Pointer<Uint8> output,
  int outputStride,
  int operation,
  double parameterA,
  double parameterB,
  Pointer<Utf8> modelPath,
  Pointer<Uint8> metadata,
  int metadataCapacity,
);

/// Executes the native operation registry. The second image must have the
/// same dimensions; optional model weights are a local .onnx file, not bundled.
VisionNativeResult processGray(
  Uint8List grayscale, {
  required int width,
  required int height,
  required int operation,
  double parameterA = 0,
  double parameterB = 0,
  Uint8List? second,
  String? modelPath,
}) {
  if (width <= 0 ||
      height <= 0 ||
      width > 4096 ||
      height > 4096 ||
      grayscale.length != width * height ||
      (second != null && second.length != grayscale.length) ||
      operation < 0 ||
      operation > 36 ||
      !parameterA.isFinite ||
      !parameterB.isFinite) {
    throw ArgumentError('Invalid image size, pair, or operation parameters.');
  }
  final input = calloc<Uint8>(grayscale.length);
  final output = calloc<Uint8>(grayscale.length);
  final paired = second == null
      ? nullptr.cast<Uint8>()
      : calloc<Uint8>(second.length);
  final model = modelPath == null
      ? nullptr.cast<Utf8>()
      : modelPath.toNativeUtf8();
  const metadataCapacity = 2048;
  final metadata = calloc<Uint8>(metadataCapacity);
  try {
    input.asTypedList(grayscale.length).setAll(0, grayscale);
    if (second != null) paired.asTypedList(second.length).setAll(0, second);
    final status = _processGray(
      input,
      width,
      height,
      width,
      paired,
      second == null ? 0 : width,
      output,
      width,
      operation,
      parameterA,
      parameterB,
      model,
      metadata,
      metadataCapacity,
    );
    if (status != 0) {
      if (status == -4) {
        throw StateError(
          'Not enough image features, or unsupported ONNX output shape. '
          'Try another image pair or standard raw YOLOv8/YOLO11 ONNX export.',
        );
      }
      throw StateError(
        'OpenCV operation $operation failed (native error $status).',
      );
    }
    return VisionNativeResult(
      pixels: Uint8List.fromList(output.asTypedList(grayscale.length)),
      metadata: metadata.cast<Utf8>().toDartString(),
    );
  } finally {
    calloc.free(metadata);
    if (modelPath != null) calloc.free(model);
    if (second != null) calloc.free(paired);
    calloc.free(output);
    calloc.free(input);
  }
}
