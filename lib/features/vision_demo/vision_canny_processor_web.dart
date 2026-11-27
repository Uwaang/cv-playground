import 'dart:typed_data';

import 'package:flutter_app/features/vision_demo/canny_result.dart';
import 'package:flutter_app/features/vision_demo/vision_operations.dart';

bool get isNativeCannySupported => false;
bool get isNativeVisionSupported => false;

Future<String> stageOnnxModel(Uint8List bytes) =>
    Future.error(UnsupportedError('ONNX inference requires a native device.'));

/// Browsers cannot load the source-built C++ Native Assets library via Dart FFI.
Future<VisionResult> runVision(
  Uint8List encodedImage, {
  required VisionOperation operation,
  required double parameterA,
  required double parameterB,
  Uint8List? secondImage,
  String? modelPath,
}) {
  return Future.error(
    UnsupportedError('Native OpenCV is not available in the browser yet.'),
  );
}

Future<CannyResult> runCanny(
  Uint8List encodedImage, {
  required int lowThreshold,
  required int highThreshold,
}) {
  return Future.error(
    UnsupportedError('Native OpenCV is not available in the browser yet.'),
  );
}
