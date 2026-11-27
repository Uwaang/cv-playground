import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/vision_demo/canny_result.dart';
import 'package:flutter_app/features/vision_demo/vision_operations.dart';
import 'package:flutter_app/features/vision_demo/vision_canny_processor_native.dart'
    if (dart.library.js_interop) 'vision_canny_processor_web.dart'
    as processor;

@RoutePage()
class VisionDemoPage extends StatefulWidget {
  const VisionDemoPage({super.key});

  @override
  State<VisionDemoPage> createState() => _VisionDemoPageState();
}

class _VisionDemoPageState extends State<VisionDemoPage> {
  Uint8List? _original;
  Uint8List? _second;
  String? _originalName;
  String? _secondName;
  String? _modelPath;
  String? _modelName;
  VisionResult? _result;
  String? _error;
  bool _busy = false;
  VisionOperation _operation = VisionOperation.canny;
  double _a = VisionOperation.canny.defaultA;
  double _b = VisionOperation.canny.defaultB;
  int _generation = 0;

  static const imageTypes = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png'],
    mimeTypes: ['image/jpeg', 'image/png'],
    uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
  );

  bool get _canApply => _original != null && (!_operation.needsSecond || _second != null) && (!_operation.needsModel || _modelPath != null);

  Future<void> _loadImage({bool secondary = false}) async {
    if (_busy) return;
    try {
      final selected = await openFile(acceptedTypeGroups: [imageTypes]);
      if (selected == null) return;
      if (await selected.length() > 16 * 1024 * 1024) {
        throw const FormatException('Choose a PNG or JPEG under 16 MB.');
      }
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty) throw const FormatException('Image is empty.');
      if (!mounted) return;
      setState(() {
        _generation++;
        if (secondary) {
          _second = bytes;
          _secondName = selected.name;
        } else {
          _original = bytes;
          _originalName = selected.name;
        }
        _result = null;
        _error = null;
      });
      if (processor.isNativeVisionSupported && _canApply) await _apply();
    } on Object catch (error) {
      if (mounted) setState(() => _error = _describeError(error));
    }
  }

  Future<void> _loadModel() async {
    if (_busy || !processor.isNativeVisionSupported) return;
    try {
      const types = XTypeGroup(label: 'ONNX model', extensions: ['onnx']);
      final selected = await openFile(acceptedTypeGroups: [types]);
      if (selected == null) return;
      if (await selected.length() > 128 * 1024 * 1024) {
        throw const FormatException('Choose an ONNX model under 128 MB.');
      }
      final path = await processor.stageOnnxModel(await selected.readAsBytes());
      if (!mounted) return;
      setState(() {
        _modelPath = path;
        _modelName = selected.name;
        _generation++;
        _result = null;
        _error = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = _describeError(error));
    }
  }

  void _changeOperation(VisionOperation operation) {
    if (_busy) return;
    setState(() {
      _operation = operation;
      _a = operation.defaultA;
      _b = operation.defaultB;
      _result = null;
      _error = null;
      _generation++;
    });
  }

  Future<void> _apply() async {
    final source = _original;
    if (source == null || _busy || !_canApply || !processor.isNativeVisionSupported) return;
    final request = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final output = await processor.runVision(
        source,
        operation: _operation,
        parameterA: _a,
        parameterB: _b,
        secondImage: _operation.needsSecond ? _second : null,
        modelPath: _operation.needsModel ? _modelPath : null,
      );
      if (!mounted || request != _generation) return;
      setState(() => _result = output);
    } on Object catch (error) {
      if (mounted && request == _generation) {
        setState(() => _error = _describeError(error));
      }
    } finally {
      if (mounted && request == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  String _describeError(Object error) {
    if (error is FormatException) return error.message;
    return 'OpenCV processing failed: $error';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _original;
    final output = _result;
    final operation = _operation;
    final supported = processor.isNativeVisionSupported;
    return Scaffold(
      appBar: AppBar(title: const Text('OpenCV Playground')),
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
                  'Explore filters, features, geometry, optical flow, '
                  'photography, stereo vision and local ONNX detection.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
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
                              'Web supports selecting images and operations. '
                              'Native OpenCV requires a desktop or mobile build; '
                              'the WASM bridge is not implemented.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _loadImage(),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Choose image'),
                    ),
                    if (_originalName != null) Text(_originalName!),
                    if (_busy)
                      const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<VisionOperation>(
                  key: ValueKey(operation),
                  initialValue: operation,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'OpenCV operation',
                  ),
                  items: [
                    for (final candidate in VisionOperation.values)
                      DropdownMenuItem(
                        value: candidate,
                        child: Text(
                          candidate.category + ' · ' + candidate.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (candidate) {
                          if (candidate != null) _changeOperation(candidate);
                        },
                ),
                if (operation.needsSecond) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _loadImage(secondary: true),
                        icon: const Icon(Icons.compare),
                        label: const Text('Choose second image / frame'),
                      ),
                      if (_secondName != null) Text(_secondName!),
                    ],
                  ),
                  Text(
                    'Pair mode resizes the second image. For stereo depth, '
                    'use a rectified left/right pair.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (operation.needsModel) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _loadModel,
                        icon: const Icon(Icons.model_training),
                        label: const Text('Choose local YOLO .onnx'),
                      ),
                      if (_modelName != null) Text(_modelName!),
                    ],
                  ),
                  Text(
                    'Use a raw 640×640 YOLOv8/YOLO11 ONNX detector. '
                    'Inference is CPU-only, COCO names are assumed, '
                    'and model weights are not bundled or uploaded.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (supported && source != null) ...[
                  const SizedBox(height: 12),
                  if (operation.aMax > 0)
                    _ParameterSlider(
                      label: operation.aLabel,
                      value: _a,
                      max: operation.aMax,
                      enabled: !_busy,
                      onChanged: (value) => setState(() {
                        _a = value;
                        _result = null;
                      }),
                    ),
                  if (operation.bMax > 0)
                    _ParameterSlider(
                      label: operation.bLabel,
                      value: _b,
                      max: operation.bMax,
                      enabled: !_busy,
                      onChanged: (value) => setState(() {
                        _b = value;
                        _result = null;
                      }),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _busy || !_canApply ? null : _apply,
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Apply ' + operation.label),
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
                      final original = _PreviewCard(
                        title: 'Original',
                        bytes: source,
                        detail: _originalName,
                      );
                      final processed = _PreviewCard(
                        title: operation.label + ' output',
                        bytes: output?.png,
                        detail: output == null
                            ? (supported ? 'Apply to see the result' : 'Not available on Web')
                            : output.width.toString() +
                                  ' × ' +
                                  output.height.toString() +
                                  ' · OpenCV ' +
                                  output.openCvVersion +
                                  '\n' +
                                  output.metadata,
                      );
                      if (constraints.maxWidth < 680) {
                        return Column(
                          children: [
                            original,
                            const SizedBox(height: 16),
                            processed,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: original),
                          const SizedBox(width: 16),
                          Expanded(child: processed),
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

class _ParameterSlider extends StatelessWidget {
  const _ParameterSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(
          flex: 4,
          child: Slider(
            value: value.clamp(0.0, max),
            min: 0,
            max: max,
            onChanged: enabled ? onChanged : null,
          ),
        ),
        SizedBox(
          width: 42,
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
