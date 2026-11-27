import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/vision_demo/canny_result.dart';
import 'package:flutter_app/features/vision_demo/vision_canny_processor_native.dart'
    if (dart.library.js_interop) 'vision_canny_processor_web.dart' as processor;

@RoutePage()
class VisionDemoPage extends StatefulWidget {
  const VisionDemoPage({super.key});

  @override
  State<VisionDemoPage> createState() => _VisionDemoPageState();
}

class _VisionDemoPageState extends State<VisionDemoPage> {
  Uint8List? _original;
  String? _fileName;
  CannyResult? _result;
  String? _error;
  bool _busy = false;
  double _lowThreshold = 50;
  double _highThreshold = 150;
  int _requestId = 0;

  Future<void> _selectImage() async {
    if (_busy) return;
    try {
      const types = XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png'],
        mimeTypes: ['image/jpeg', 'image/png'],
        uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
      );
      final selected = await openFile(acceptedTypeGroups: [types]);
      if (selected == null) return;
      if (await selected.length() > 16 * 1024 * 1024) {
        throw const FormatException(
          'Choose an image under 16 MB for this first demo.',
        );
      }
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty) {
        throw const FormatException('The selected image is empty.');
      }
      if (!mounted) return;
      setState(() {
        _requestId++;
        _original = bytes;
        _fileName = selected.name;
        _result = null;
        _error = null;
      });
      if (processor.isNativeCannySupported) await _apply();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeError(error));
    }
  }

  Future<void> _apply() async {
    final source = _original;
    if (_busy || source == null || !processor.isNativeCannySupported) {
      return;
    }
    final id = ++_requestId;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final output = await processor.runCanny(
        source,
        lowThreshold: _lowThreshold.round(),
        highThreshold: _highThreshold.round(),
      );
      if (!mounted || _requestId != id) return;
      setState(() => _result = output);
    } catch (error) {
      if (!mounted || _requestId != id) return;
      setState(() => _error = _describeError(error));
    } finally {
      if (mounted && _requestId == id) {
        setState(() => _busy = false);
      }
    }
  }

  String _describeError(Object error) {
    if (error is FormatException) return error.message;
    return 'Image processing failed: $error';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _original;
    final output = _result;
    final supported = processor.isNativeCannySupported;

    return Scaffold(
      appBar: AppBar(title: const Text('OpenCV · Canny edges')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Image playground', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Choose a PNG or JPEG, then compare the original with '
                  'edges detected by our source-built C++ OpenCV engine.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                if (!supported) ...[
                  const Card.filled(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Image preview works on Web. Native OpenCV '
                              'processing needs a future WASM bridge.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _selectImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Choose image'),
                    ),
                    if (source != null)
                      Text(
                        _fileName ?? 'Selected image',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (_busy)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (supported && source != null) ...[
                  const SizedBox(height: 24),
                  Text('Canny thresholds', style: theme.textTheme.titleMedium),
                  _ThresholdSlider(
                    label: 'Low',
                    value: _lowThreshold,
                    min: 0,
                    max: _highThreshold,
                    enabled: !_busy,
                    onChanged: (value) => setState(() {
                      _lowThreshold = value;
                      _result = null;
                    }),
                  ),
                  _ThresholdSlider(
                    label: 'High',
                    value: _highThreshold,
                    min: _lowThreshold,
                    max: 300,
                    enabled: !_busy,
                    onChanged: (value) => setState(() {
                      _highThreshold = value;
                      _result = null;
                    }),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _busy ? null : _apply,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Apply Canny'),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    key: const Key('vision_demo_error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                if (source == null)
                  Card.outlined(
                    child: SizedBox(
                      height: 220,
                      child: Center(
                        child: Text(
                          'No image selected',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 680;
                      final original = _PreviewCard(
                        title: 'Original',
                        bytes: source,
                        detail: _fileName,
                      );
                      final processed = _PreviewCard(
                        title: 'Canny output',
                        bytes: output?.png,
                        detail: output == null
                            ? (supported
                                  ? 'Apply Canny to see the result'
                                  : 'Not available on Web')
                            : '${output.width} × ${output.height} · OpenCV '
                                  '${output.openCvVersion}',
                      );
                      return wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: original),
                                const SizedBox(width: 16),
                                Expanded(child: processed),
                              ],
                            )
                          : Column(
                              children: [
                                original,
                                const SizedBox(height: 16),
                                processed,
                              ],
                            );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 48, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: enabled && min < max ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(value.round().toString(), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.title,
    required this.bytes,
    required this.detail,
  });

  final String title;
  final Uint8List? bytes;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainer,
                child: bytes == null
                    ? const Center(child: Icon(Icons.image_outlined, size: 48))
                    : Image.memory(
                        bytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 10),
              Text(detail!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
