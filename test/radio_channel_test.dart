import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/models/radio_channel.dart';

RadioChannel channelAt(int location) =>
    RadioChannel(location: location, name: 'CH $location', frequency: 146.52);

void main() {
  test('Midland MXT295 shows Midland channel numbers', () {
    expect(channelNumberLabel('Baofeng_UV-5R', 16), '16');
    expect(showsMidlandChannelNumbers('Baofeng_UV-5R'), isFalse);
    expect(showsMidlandChannelNumbers(midlandMxt295Model), isTrue);
    expect(channelNumberLabel(midlandMxt295Model, 1), '1');
    expect(channelNumberLabel(midlandMxt295Model, 15), '15');
    expect(channelNumberLabel(midlandMxt295Model, 16), 'RPTR 15');
    expect(channelNumberLabel(midlandMxt295Model, 17), '16');
    expect(channelNumberLabel(midlandMxt295Model, 18), 'RPTR 16');
    expect(channelNumberLabel(midlandMxt295Model, 19), '17');
    expect(channelNumberLabel(midlandMxt295Model, 29), '22');
    expect(channelNumberLabel(midlandMxt295Model, 30), 'RPTR 22');
    expect(channelNumberLabel(midlandMxt295Model, 31), '23');
    expect(channelNumberLabel(midlandMxt295Model, 107), '99');
    expect(channelNumberLabel(midlandMxt295Model, 0), '0');
  });

  test('Midland repeater rows reset to the plain GMRS repeater', () {
    expect(isMidlandRepeaterRow('Baofeng_UV-5R', 16), isFalse);
    expect(isMidlandRepeaterRow(midlandMxt295Model, 15), isFalse);
    expect(isMidlandRepeaterRow(midlandMxt295Model, 17), isFalse);
    expect(isMidlandRepeaterRow(midlandMxt295Model, 31), isFalse);
    expect(isMidlandRepeaterRow(midlandMxt295Model, 16), isTrue);
    expect(isMidlandRepeaterRow(midlandMxt295Model, 30), isTrue);
    expect(midlandRepeaterRxMhz[16], 462.550);
    expect(midlandRepeaterRxMhz[30], 462.725);

    final row = RadioChannel(
      location: 24,
      name: 'CALICO',
      frequency: 146.52,
      duplex: '',
      skip: '',
      power: 'Low',
    );
    row.restorePlainMidlandRepeater();
    expect(row.cleared, isFalse);
    expect(row.name, isEmpty);
    expect(row.frequency, 462.650);
    expect(row.duplex, '+');
    expect(row.offset, 5);
    expect(row.tone, isEmpty);
    expect(row.mode, 'FM');
    expect(row.step, 12.5);
    expect(row.skip, 'S');
    expect(row.power, 'High');

    final normal = channelAt(17);
    normal.restorePlainMidlandRepeater();
    expect(normal.name, 'CH 17');
    expect(normal.frequency, 146.52);
  });

  test('scan codes use the same words in the list and the editor', () {
    expect(scanLabel(''), 'Include');
    expect(scanLabel('S'), 'Skip');
    expect(scanLabel('P'), 'Priority');
    expect(scanLabel('X'), 'X');
    expect(scanChoices(const ['', 'S']), {'': 'Include', 'S': 'Skip'});
    expect(scanChoices(null).keys.toList(), ['', 'S', 'P']);
  });

  test('provides the standard DTCS code set without a radio image', () {
    expect(standardDtcsCodes, hasLength(104));
    expect(standardDtcsCodes.first, 23);
    expect(standardDtcsCodes.last, 754);
    expect(standardDtcsCodes, containsAll([25, 131, 431, 732]));
  });

  test('next channel location stays within radio memory bounds', () {
    expect(
      RadioChannel.nextAvailableLocation(const [], minimum: 1, maximum: 199),
      1,
    );
    expect(
      RadioChannel.nextAvailableLocation(
        [channelAt(1), channelAt(2), channelAt(150)],
        minimum: 1,
        maximum: 199,
      ),
      151,
    );
    expect(
      RadioChannel.nextAvailableLocation(
        [channelAt(1), channelAt(2), channelAt(199)],
        minimum: 1,
        maximum: 199,
      ),
      3,
    );
    expect(
      RadioChannel.nextAvailableLocation(
        [channelAt(0), channelAt(2)],
        minimum: 0,
        maximum: 2,
      ),
      1,
    );
  });

  test('next channel location reports a full radio', () {
    expect(
      RadioChannel.nextAvailableLocation(
        [channelAt(1), channelAt(2), channelAt(3)],
        minimum: 1,
        maximum: 3,
      ),
      isNull,
    );
  });

  test('channel validation uses the selected radio memory bounds', () {
    expect(
      channelAt(200).validate(minimumLocation: 1, maximumLocation: 199),
      contains('Location must be between 1 and 199 for this radio.'),
    );
    expect(
      channelAt(107).validate(minimumLocation: 1, maximumLocation: 199),
      isEmpty,
    );
  });
}
