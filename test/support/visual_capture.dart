import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const captureUi = bool.fromEnvironment('CAPTURE_UI');

/// Opt-in previews use Flutter's installed Roboto files instead of Ahem.
Future<void> loadPreviewFonts() async {
  if (!captureUi) return;
  await loadAppFonts();
}

/// Use the app's actual font metrics for keyboard and text-scaling assertions.
Future<void> loadAppFonts() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final flutter = packages.cast<Map<String, dynamic>>().singleWhere(
    (package) => package['name'] == 'flutter',
  );
  final flutterPackage = Directory.fromUri(
    configFile.uri.resolve(flutter['rootUri'] as String),
  );
  final fonts = p.join(
    flutterPackage.parent.parent.path,
    'bin',
    'cache',
    'artifacts',
    'material_fonts',
  );
  final loader = FontLoader('Roboto');
  for (final name in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]) {
    loader.addFont(
      File(p.join(fonts, name))
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)),
    );
  }
  await loader.load();
  final icons = FontLoader('MaterialIcons');
  icons.addFont(
    File(p.join(fonts, 'materialicons-regular.otf'))
        .readAsBytes()
        .then((bytes) => ByteData.sublistView(bytes)),
  );
  await icons.load();
}

Future<void> capturePreview(
  WidgetTester tester,
  GlobalKey key,
  String name, {
  String outputDirectory = 'build/phase2-preview',
  bool settle = true,
}) async {
  if (!captureUi) return;
  if (settle) await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(outputDirectory).create(recursive: true);
    await File(p.join(directory.path, '$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
