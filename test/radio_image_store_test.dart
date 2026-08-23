import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/services/radio_image_store.dart';

void main() {
  test('stores and detects a reusable image per model', () async {
    final directory = await Directory.systemTemp.createTemp(
      'newchirp-radio-image-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.img');
    await source.writeAsBytes([1, 2, 3, 4]);

    final store = RadioImageStore(rootDirectory: directory);
    final saved = await store.saveForModel('Baofeng_UV-5R', source.path);

    expect(saved, store.pathForModel('Baofeng_UV-5R'));
    expect(store.hasForModel('Baofeng_UV-5R'), isTrue);
    expect(store.hasForModel('Yaesu_FT-60'), isFalse);
    expect(await File(saved).readAsBytes(), [1, 2, 3, 4]);
  });
}
