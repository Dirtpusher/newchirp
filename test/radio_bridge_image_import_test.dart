import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/services/radio_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('detects a native CHIRP image and returns its model', () async {
    final source = Directory('build_support/chirp-20261023').existsSync()
        ? 'build_support/chirp-20261023'
        : '../chirp-20260626';
    final image = File(
      '${Directory.systemTemp.path}/newchirp-image-import-$pid.img',
    );
    await image.writeAsBytes(List<int>.filled(21312, 0), flush: true);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });

    final imported = await RadioBridge(
      sourcePath: source,
    ).readImage(image.path);

    expect(imported.model, 'Icom_IC-2730A');
    expect(imported.imagePath, image.path);
  });
}
