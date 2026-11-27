import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_app/features/vision_demo/canny_result.dart';
import 'package:flutter_app/features/vision_demo/vision_operations.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:vision_engine/vision_engine.dart' as vision;

bool get isNativeCannySupported => true;
bool get isNativeVisionSupported => true;

/// Stage local model weights for mobile file pickers that return content URIs.
Future<String> stageOnnxModel(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 128 * 1024 * 1024) {
    throw const FormatException('Choose an ONNX model under 128 MB.');
  }
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/cv-playground-model.onnx');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Keeps decoding, OpenCV FFI and PNG encoding off the Flutter UI isolate.
Future<VisionResult> runVision(
  Uint8List encodedImage, {
  required VisionOperation operation,
  required double parameterA,
  required double parameterB,
  Uint8List? secondImage,
  String? modelPath,
}) {
  return Isolate.run(
    () => _processImage(
      encodedImage,
      operation,
      parameterA,
      parameterB,
      secondImage,
      modelPath,
    ),
  );
}

Future<CannyResult> runCanny(
  Uint8List encodedImage, {
  required int lowThreshold,
  required int highThreshold,
}) async {
  final result = await runVision(
    encodedImage,
    operation: VisionOperation.canny,
    parameterA: lowThreshold.toDouble(),
    parameterB: highThreshold.toDouble(),
  );
  return CannyResult(
    png: result.png,
    width: result.width,
    height: result.height,
    openCvVersion: result.openCvVersion,
  );
}

VisionResult _processImage(
  Uint8List encoded,
  VisionOperation operation,
  double a,
  double b,
  Uint8List? secondImage,
  String? modelPath,
) {
  final decoded = img.decodeImage(encoded);
  if (decoded == null) {
    throw const FormatException('Could not decode image as PNG or JPEG.');
  }

  final upright = img.bakeOrientation(decoded);
  const maxDimension = 1024;
  final longest = upright.width > upright.height ? upright.width : upright.height;
  final scale = longest > maxDimension ? maxDimension / longest : 1.0;
  final width = (upright.width * scale).round().clamp(1, maxDimension);
  final height = (upright.height * scale).round().clamp(1, maxDimension);
  final image = scale < 1.0 ? img.copyResize(upright, width: width, height: height) : upright;
  final grayscale = _toGray(image);

  Uint8List? second;
  if (secondImage != null) {
    final pairedDecoded = img.decodeImage(secondImage);
    if (pairedDecoded == null) {
      throw const FormatException('Could not decode second image.');
    }
    final paired = img.bakeOrientation(pairedDecoded);
    second = _toGray(img.copyResize(paired, width: width, height: height));
  }

  final nativeResult = vision.processGray(
    grayscale,
    width: width,
    height: height,
    operation: operation.id,
    parameterA: a,
    parameterB: b,
    second: second,
    modelPath: modelPath,
  );
  final output = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = nativeResult.pixels[y * width + x];
      output.setPixelRgb(x, y, value, value, value);
    }
  }
  return VisionResult(
    png: Uint8List.fromList(img.encodePng(output)),
    width: width,
    height: height,
    openCvVersion: vision.openCvVersion,
    metadata: nativeResult.metadata,
  );
}

Uint8List _toGray(img.Image image) {
  final width = image.width;
  final height = image.height;
  final grayscale = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final pixel = image.getPixel(x, y);
      // Composite transparent source pixels onto white.
      final maxValue = pixel.maxChannelValue;
      final alpha = pixel.a.toDouble() / maxValue;
      final r = (pixel.r.toDouble() / maxValue) * 255 * alpha + 255 * (1 - alpha);
      final g = (pixel.g.toDouble() / maxValue) * 255 * alpha + 255 * (1 - alpha);
      final b = (pixel.b.toDouble() / maxValue) * 255 * alpha + 255 * (1 - alpha);
      grayscale[y * width + x] = ((77 * r + 150 * g + 29 * b) / 256).round().clamp(0, 255);
    }
  }
  return grayscale;
}
