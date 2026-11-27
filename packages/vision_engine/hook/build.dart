import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

/// Native Assets hook: compile the pinned OpenCV sources through CMake.
///
/// A generated native asset is declared for the same library URI used by
/// @Native functions in lib/vision_engine.dart.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final opencv = input.packageRoot.resolve('../../third_party/opencv/');
    if (!File.fromUri(opencv.resolve('CMakeLists.txt')).existsSync()) {
      throw StateError(
        'Pinned OpenCV submodule is missing. '
        'Run git submodule update --init --recursive before Flutter build.',
      );
    }

    final logger = Logger('vision_engine')
      ..onRecord.listen((record) => stderr.writeln(record));

    final native = input.packageRoot.resolve('native/');
    final install = input.outputDirectory.resolve('install');

    output.dependencies.add(input.packageRoot.resolve('native/CMakeLists.txt'));
    output.dependencies.add(input.packageRoot.resolve('native/include/vision_engine.h'));
    output.dependencies.add(input.packageRoot.resolve('native/src/vision_engine.cpp'));
    output.dependencies.add(opencv);

    final builder = CMakeBuilder.create(
      name: 'vision_engine',
      sourceDir: native,
      defines: {
        'CMAKE_BUILD_TYPE': 'Release',
        'CMAKE_INSTALL_PREFIX': install.toFilePath(),
        'OPENCV_SOURCE_DIR': opencv.toFilePath(),
        'VISION_ENGINE_BUNDLED_OPENCV': 'ON',
      },
      targets: ['install'],
      buildLocal: true,
      logger: logger,
    );
    await builder.run(input: input, output: output, logger: logger);

    final assets = await output.findAndAddCodeAssets(
      input,
      names: {r'^(lib)?vision_engine\.(dll|so|dylib)$': 'vision_engine.dart'},
      outDir: install,
      logger: logger,
      regExp: true,
    );
    if (assets.isEmpty) {
      throw StateError('CMake install did not produce vision_engine shared library.');
    }
  });
}
