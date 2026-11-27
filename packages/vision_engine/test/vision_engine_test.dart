import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vision_engine/vision_engine.dart';

void main() {
  test('native engine ABI and OpenCV source version', () {
    expect(visionEngineAbiVersion, 1);
    expect(openCvVersion, startsWith('4.14.0'));
  });

  test('Canny produces a nonempty edge map for a white square', () {
    const side = 64;
    final pixels = Uint8List(side * side);
    for (var y = 16; y < 48; y++) {
      for (var x = 16; x < 48; x++) {
        pixels[y * side + x] = 255;
      }
    }
    final result = cannyGray(
      pixels,
      width: side,
      height: side,
      lowThreshold: 50,
      highThreshold: 150,
    );
    expect(result.length, side * side);
    expect(result.any((value) => value != 0), isTrue);
  });
}
