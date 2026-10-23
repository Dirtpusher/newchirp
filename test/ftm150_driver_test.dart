import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/services/radio_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog exposes the experimental Yaesu FTM-150 driver', () async {
    final source = Directory('build_support/chirp-20261023').existsSync()
        ? 'build_support/chirp-20261023'
        : '../chirp-20260626';
    final bridge = RadioBridge(sourcePath: source, newDriversPath: 'drivers');

    expect(await bridge.models(), contains('Yaesu_FTM-150R'));
    final instructions = await bridge.instructions('Yaesu_FTM-150R');
    expect(instructions.experimental, contains('experimental'));
    expect(instructions.info, contains('SCU-56'));
  });
}
