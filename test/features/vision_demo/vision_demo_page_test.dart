import 'package:flutter/material.dart';
import 'package:flutter_app/features/vision_demo/vision_demo_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Canny page has image selection and a truthful empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: VisionDemoPage()),
    );

    expect(find.text('Image playground'), findsOneWidget);
    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Canny output'), findsNothing);
  });
}
