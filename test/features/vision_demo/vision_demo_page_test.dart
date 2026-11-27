import 'package:flutter/material.dart';
import 'package:flutter_app/features/vision_demo/vision_demo_page.dart';
import 'package:flutter_app/features/vision_demo/vision_operations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Vision playground has image selection and truthful empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: VisionDemoPage()));
    expect(find.text('Image playground'), findsOneWidget);
    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Canny output'), findsNothing);
    expect(find.text('OpenCV operation'), findsOneWidget);
  });

  test('operation IDs are unique and pair/model requirements explicit', () {
    expect(VisionOperation.values.length, 37);
    expect(VisionOperation.values.map((op) => op.id).toSet().length, 37);
    expect(VisionOperation.opticalFlow.needsSecond, isTrue);
    expect(VisionOperation.stereo.needsSecond, isTrue);
    expect(VisionOperation.yolo.needsModel, isTrue);
    expect(VisionOperation.canny.defaultA, 50);
    expect(VisionOperation.canny.defaultB, 150);
  });
}
