import 'dart:typed_data';

/// Result of source-built OpenCV Canny on an optionally downscaled image.
class CannyResult {
  const CannyResult({
    required this.png,
    required this.width,
    required this.height,
    required this.openCvVersion,
  });

  final Uint8List png;
  final int width;
  final int height;
  final String openCvVersion;
}
