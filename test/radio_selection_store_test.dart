import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/services/radio_selection_store.dart';

void main() {
  test('radio model and port persist across store instances', () async {
    final directory = await Directory.systemTemp.createTemp(
      'newchirp-radio-selection-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/radio-selection.json';

    await RadioSelectionStore(path: path).save(
      const RadioSelection(
        model: 'Baofeng_UV-5R',
        port: '/dev/cu.usbserial-1234',
      ),
    );
    final restored = await RadioSelectionStore(path: path).load();

    expect(restored?.model, 'Baofeng_UV-5R');
    expect(restored?.port, '/dev/cu.usbserial-1234');
  });
}
