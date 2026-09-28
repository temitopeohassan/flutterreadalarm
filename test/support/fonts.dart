import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the real Roboto and Material Icons fonts that ship with the Flutter
/// SDK, so widget tests lay text out like a device does instead of using the
/// square-glyph test font.
Future<void> loadAppFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;

  Future<void> load(String family, Iterable<String> files) async {
    final loader = FontLoader(family);
    for (final name in files) {
      final file = File('${dir.path}/$name');
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final w in [
      'Thin',
      'Light',
      'Regular',
      'Medium',
      'Bold',
      'Black'
    ]) ...[
      'Roboto-$w.ttf',
      'Roboto-${w == 'Regular' ? '' : w}Italic.ttf',
    ],
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}
