import 'dart:typed_data';

import 'package:flutter_app/features/vision_demo/canny_result.dart';

bool get isNativeCannySupported => false;

/// Browsers need a separate OpenCV WASM bridge; never claim Dart FFI runs here.
Future<CannyResult> runCanny(
  Uint8List encodedImage, {
  required int lowThreshold,
  required int highThreshold,
}) {
  return Future.error(
    UnsupportedError('Native OpenCV is not available in the browser yet.'),
  );
}
