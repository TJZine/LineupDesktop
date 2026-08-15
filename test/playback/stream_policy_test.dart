import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/stream_policy.dart';

void main() {
  const capabilities = StreamCapabilities(
    containers: {'mkv'},
    videoCodecs: {'h264'},
    audioCodecs: {'aac'},
  );

  test('unknown facts never silently become supported', () {
    final decision = decideStream(
      const StreamFacts(
        container: null,
        videoCodec: 'h264',
        audioCodec: 'aac',
        dynamicRange: DynamicRange.sdr,
      ),
      capabilities,
    );
    expect(decision.kind, StreamDecisionKind.unsupported);
    expect(decision.unknowns, contains('container-unknown'));
  });

  test('ranks direct play, remux, then transcode', () {
    expect(
      decideStream(
        const StreamFacts(
          container: 'mkv',
          videoCodec: 'h264',
          audioCodec: 'aac',
          dynamicRange: DynamicRange.sdr,
        ),
        capabilities,
      ).kind,
      StreamDecisionKind.directPlay,
    );
    expect(
      decideStream(
        const StreamFacts(
          container: 'mp4',
          videoCodec: 'h264',
          audioCodec: 'aac',
          dynamicRange: DynamicRange.sdr,
        ),
        capabilities,
      ).kind,
      StreamDecisionKind.directStream,
    );
    expect(
      decideStream(
        const StreamFacts(
          container: 'mkv',
          videoCodec: 'hevc',
          audioCodec: 'aac',
          dynamicRange: DynamicRange.sdr,
        ),
        capabilities,
      ).kind,
      StreamDecisionKind.transcode,
    );
  });

  test('does not infer HDR support', () {
    final decision = decideStream(
      const StreamFacts(
        container: 'mkv',
        videoCodec: 'h264',
        audioCodec: 'aac',
        dynamicRange: DynamicRange.hdr10,
      ),
      const StreamCapabilities(
        containers: {'mkv'},
        videoCodecs: {'h264'},
        audioCodecs: {'aac'},
        transcode: false,
      ),
    );
    expect(decision.kind, StreamDecisionKind.unsupported);
    expect(decision.reasons, contains('dynamic-range-incompatible'));
  });

  test('unrestricted backends accept reported formats and HDR', () {
    final decision = decideStream(
      const StreamFacts(
        container: 'future-container',
        videoCodec: 'future-video',
        audioCodec: 'truehd',
        dynamicRange: DynamicRange.dolbyVision,
      ),
      const StreamCapabilities.unrestricted(),
    );

    expect(decision.kind, StreamDecisionKind.directPlay);
  });

  test('unrestricted backends try streams with incomplete metadata', () {
    final decision = decideStream(
      const StreamFacts(
        container: null,
        videoCodec: null,
        audioCodec: null,
        dynamicRange: DynamicRange.unknown,
      ),
      const StreamCapabilities.unrestricted(),
    );

    expect(decision.kind, StreamDecisionKind.directPlay);
    expect(decision.unknowns, isNotEmpty);
  });
}
