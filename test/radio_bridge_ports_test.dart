import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/services/radio_bridge.dart';

void main() {
  group('Windows serial port details', () {
    test('merges device names with live ports in numeric order', () {
      final ports = RadioBridge.parseWindowsSerialPortDetails(
        '[{"port":"COM10","deviceName":"USB Serial Port"},'
        '{"port":"COM7","deviceName":"Prolific PL2303GS USB Serial COM Port"},'
        '{"port":"COM99","deviceName":"Disconnected Cable"},'
        '{"port":"COM7","deviceName":"USB Serial Port"}]',
        ['COM7', 'COM2', 'COM10'],
      );

      expect(ports.map((port) => port.port), ['COM2', 'COM7', 'COM10']);
      expect(ports[0].label, 'COM2');
      expect(ports[1].label, 'COM7 — Prolific PL2303GS USB Serial COM Port');
      expect(ports[2].label, 'COM10 — USB Serial Port');
    });

    test('accepts a single device entry', () {
      final ports = RadioBridge.parseWindowsSerialPortDetails(
        '{"port":"com5","deviceName":"Communications Port"}',
        ['COM5'],
      );

      expect(ports.single.port, 'COM5');
      expect(ports.single.label, 'COM5 — Communications Port');
    });

    test('keeps live ports when device metadata is unavailable', () {
      final ports = RadioBridge.parseWindowsSerialPortDetails('', ['COM3']);

      expect(ports.single.port, 'COM3');
      expect(ports.single.label, 'COM3');
    });
  });
}
