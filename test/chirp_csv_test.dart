import 'package:flutter_test/flutter_test.dart';
import 'package:newchirp/models/radio_channel.dart';
import 'package:newchirp/services/chirp_csv.dart';

void main() {
  test('CHIRP CSV round trips values and quoted comments', () {
    final source = RadioChannel(
      location: 12,
      name: 'LOCAL',
      frequency: 146.52,
      duplex: '-',
      offset: 0.6,
      tone: 'Tone',
      txTone: 100,
      comment: 'Club, primary "calling" channel',
    );

    final decoded = ChirpCsv.decode(ChirpCsv.encode([source]));

    expect(decoded, hasLength(1));
    expect(decoded.single.location, 12);
    expect(decoded.single.frequency, 146.52);
    expect(decoded.single.duplex, '-');
    expect(decoded.single.comment, source.comment);
  });

  test('GMRS starter library contains all 22 channels', () {
    final channels = gmrsStarterChannels();
    expect(channels, hasLength(22));
    expect(channels.first.frequency, 462.5625);
    expect(channels.last.duplex, '+');
    expect(channels.last.offset, 5.0);
  });
}
