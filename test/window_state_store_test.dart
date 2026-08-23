import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/services/window_state_store.dart';

void main() {
  test('window size, position, and maximized state persist', () async {
    final directory = await Directory.systemTemp.createTemp(
      'newchirp-window-state-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/window-state.json';

    await WindowStateStore(path: path).save(
      const WindowState(
        width: 1280,
        height: 800,
        x: 120,
        y: 60,
        maximized: true,
      ),
    );
    final restored = await WindowStateStore(path: path).load();

    expect(restored?.width, 1280);
    expect(restored?.height, 800);
    expect(restored?.x, 120);
    expect(restored?.y, 60);
    expect(restored?.maximized, isTrue);
  });

  test('malformed state falls back to null', () async {
    final directory = await Directory.systemTemp.createTemp(
      'newchirp-window-state-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/window-state.json';
    await File(path).writeAsString('{not json');

    expect(await WindowStateStore(path: path).load(), isNull);
  });
}
