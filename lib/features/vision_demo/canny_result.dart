import 'dart:typed_data';

/// Common output from an OpenCV operation. PNG is owned by the Dart caller.
class VisionResult {
  const VisionResult({
    required this.png,
    required this.width,
    required this.height,
    required this.openCvVersion,
    this.metadata = '',
  });

  final Uint8List png;
  final int width;
  final int height;
  final String openCvVersion;
  final String metadata;
}

/// Backwards-compatible result from the original Canny demo.
class CannyResult extends VisionResult {
  const CannyResult({
    required super.png,
    required super.width,
    required super.height,
    required super.openCvVersion,
  });
}
