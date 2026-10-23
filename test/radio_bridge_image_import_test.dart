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
    expect(
      imported.imagePath.replaceAll('\\', '/'),
      image.path.replaceAll('\\', '/'),
    );
  });

  test('FT-857 images with reserved AM step values remain readable', () async {
    final source = Directory('build_support/chirp-20261023').existsSync()
        ? 'build_support/chirp-20261023'
        : '../chirp-20260626';
    final sample = File('$source/tests/images/Yaesu_FT-857_897.img');
    expect(await sample.exists(), isTrue);

    final bytes = await sample.readAsBytes();
    const firstMemory = 0x4DF;
    bytes[firstMemory] = (bytes[firstMemory] & 0xF8) | 4;
    bytes[firstMemory + 3] = (bytes[firstMemory + 3] & 0xC7) | (7 << 3);

    final image = File(
      '${Directory.systemTemp.path}/newchirp-ft857-am-step-$pid.img',
    );
    await image.writeAsBytes(bytes, flush: true);
    addTearDown(() async {
      if (await image.exists()) await image.delete();
    });

    final imported = await RadioBridge(
      sourcePath: source,
      newDriversPath: 'drivers',
    ).readImage(image.path);

    expect(imported.model, 'Yaesu_FT-857_897');
    final channel = imported.channels.singleWhere(
      (candidate) => candidate.location == 1,
    );
    expect(channel.mode, 'AM');
    expect(channel.step, 5.0);
  });
}
