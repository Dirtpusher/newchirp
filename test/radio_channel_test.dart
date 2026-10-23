import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/models/radio_channel.dart';

RadioChannel channelAt(int location) =>
    RadioChannel(location: location, name: 'CH $location', frequency: 146.52);

void main() {
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
