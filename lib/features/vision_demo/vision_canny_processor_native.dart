import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_app/features/vision_demo/canny_result.dart';
import 'package:image/image.dart' as img;
import 'package:vision_engine/vision_engine.dart' as vision;

bool get isNativeCannySupported => true;

/// Run image decoding, grayscale conversion, OpenCV and PNG encoding off the
/// Flutter UI isolate. This is an intentionally bounded still-image pipeline.
Future<CannyResult> runCanny(
  Uint8List encodedImage, {
  required int lowThreshold,
  required int highThreshold,
}) {
  return Isolate.run(
    () => _processImage(encodedImage, lowThreshold, highThreshold),
  );
}

CannyResult _processImage(Uint8List encoded, int low, int high) {
  final decoded = img.decodeImage(encoded);
  if (decoded == null) {
    throw const FormatException('Could not decode this image as PNG or JPEG.');
  }

  final upright = img.bakeOrientation(decoded);
  const maxDimension = 1024;
  final longest = upright.width > upright.height
      ? upright.width
      : upright.height;
  final scale = longest > maxDimension ? maxDimension / longest : 1.0;
  final width = (upright.width * scale).round().clamp(1, maxDimension).toInt();
  final height = (upright.height * scale).round().clamp(1, maxDimension).toInt();
  final image = scale < 1.0
      ? img.copyResize(upright, width: width, height: height)
      : upright;

  final grayscale = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      // Composite transparent input onto white rather than black.
      final maxValue = pixel.maxChannelValue;
      final alpha = pixel.a.toDouble() / maxValue;
      final r = (pixel.r.toDouble() / maxValue) * 255 * alpha +
          255 * (1 - alpha);
      final g = (pixel.g.toDouble() / maxValue) * 255 * alpha +
          255 * (1 - alpha);
      final b = (pixel.b.toDouble() / maxValue) * 255 * alpha +
          255 * (1 - alpha);
      grayscale[y * width + x] =
          ((77 * r + 150 * g + 29 * b) / 256).round().clamp(0, 255);
    }
  }

  final edges = vision.cannyGray(
    grayscale,
    width: width,
    height: height,
    lowThreshold: low.toDouble(),
    highThreshold: high.toDouble(),
  );

  final output = img.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = edges[y * width + x];
      output.setPixelRgb(x, y, value, value, value);
    }
  }

  return CannyResult(
    png: Uint8List.fromList(img.encodePng(output)),
    width: width,
    height: height,
    openCvVersion: vision.openCvVersion,
  );
}
