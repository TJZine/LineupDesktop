import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_health_monitor.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';

import '../support/ui_fixture.dart';

void main() {
  test('bounds active and pending health work', () async {
    final controller = _ControlledHealthController(
      channels: [for (var index = 1; index <= 16; index++) _channel(index)],
    );
    final monitor = ChannelHealthMonitor(controller: controller);
    addTearDown(controller.dispose);
    addTearDown(monitor.dispose);

    for (final channel in controller.channels) {
      monitor.request(channel);
    }

    expect(controller.pending, hasLength(2));
    expect(controller.maximumActive, 2);
    while (controller.pending.isNotEmpty) {
      controller.complete(controller.pending.first.channel.id);
      await _flushHealthWork();
    }
    expect(controller.requests, 14);
  });

  test(
    'caches healthy results and distinguishes them from no result',
    () async {
      final channel = _channel(1);
      final controller = _ControlledHealthController(channels: [channel]);
      final monitor = ChannelHealthMonitor(controller: controller);
      addTearDown(controller.dispose);
      addTearDown(monitor.dispose);

      expect(monitor.issueFor(channel.id), isNull);
      monitor.request(channel);
      controller.complete(channel.id);
      await _flushHealthWork();

      expect(monitor.issueFor(channel.id), isFalse);
      monitor.request(channel);
      expect(controller.requests, 1);

      final changed = Channel.fromJson({
        ...channel.toJson(),
        'name': 'Health 1 changed',
      });
      await controller.saveChannel(changed, expectedBase: channel);
      expect(monitor.issueFor(channel.id), isNull);
      monitor.request(changed);
      controller.complete(channel.id, error: StateError('health failure'));
      await _flushHealthWork();
      expect(monitor.issueFor(channel.id), isTrue);
    },
  );

  test(
    'serializes same-channel refreshes across a generation change',
    () async {
      final original = _channel(1);
      final controller = _ControlledHealthController(channels: [original]);
      final monitor = ChannelHealthMonitor(controller: controller);
      addTearDown(controller.dispose);
      addTearDown(monitor.dispose);

      monitor.request(original);
      controller.generation++;
      controller.notifyListeners();
      monitor.request(original);

      expect(controller.pending, hasLength(1));
      controller.complete(original.id, error: StateError('stale failure'));
      await _flushHealthWork();

      expect(controller.pending, hasLength(1));
      controller.complete(original.id);
      await _flushHealthWork();

      expect(monitor.issueFor(original.id), isFalse);
      expect(controller.requests, 2);
    },
  );

  test('does not publish or reschedule after disposal', () async {
    final channel = _channel(1);
    final controller = _ControlledHealthController(channels: [channel]);
    final monitor = ChannelHealthMonitor(controller: controller);
    var notifications = 0;
    monitor.addListener(() => notifications++);

    monitor.request(channel);
    monitor.dispose();
    controller.complete(channel.id);
    await _flushHealthWork();
    controller.notifyListeners();

    expect(notifications, 0);
    expect(monitor.issueFor(channel.id), isNull);
    controller.dispose();
  });

  test('repeated cached requests use the current channel index', () async {
    final controller = _IndexedHealthController(
      channels: [for (var index = 1; index <= 1000; index++) _channel(index)],
    );
    final monitor = ChannelHealthMonitor(controller: controller);
    addTearDown(controller.dispose);
    addTearDown(monitor.dispose);

    for (final channel in controller.channels) {
      monitor.request(channel);
      controller.complete(channel.id);
      await _flushHealthWork();
    }
    final listReadsBefore = controller.channelListReads;
    final revisionReadsBefore = controller.revisionReads;
    final cached = controller.channels.first;
    for (var index = 0; index < 20; index++) {
      monitor.request(cached);
    }

    expect(controller.channelListReads - listReadsBefore, lessThan(100));
    expect(controller.revisionReads - revisionReadsBefore, lessThan(100));
  });
}

Future<void> _flushHealthWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Channel _channel(int number) => Channel(
  id: 'health-$number',
  number: number,
  name: 'Health $number',
  source: ManualSource([
    ChannelItem(
      id: 'health-$number-program',
      title: 'Health $number program',
      duration: const Duration(minutes: 30),
    ),
  ]),
  playbackMode: PlaybackMode.sequential,
  anchor: DateTime.utc(2026),
  shuffleSeed: number,
);

class _ControlledHealthController extends FixtureController {
  _ControlledHealthController({required List<Channel> channels})
    : super(scenario: LineupScenario(channels: channels));

  final pending = <_HealthCall>[];
  int generation = 0;
  int requests = 0;
  int maximumActive = 0;

  @override
  int get contentGeneration => generation;

  @override
  Future<ScheduleIndex> loadScheduleFor(Channel channel) {
    requests++;
    final call = _HealthCall(channel, Completer<ScheduleIndex>());
    pending.add(call);
    maximumActive = maximumActive < pending.length
        ? pending.length
        : maximumActive;
    return call.completer.future;
  }

  void complete(String id, {Object? error}) {
    final call = pending.firstWhere((item) => item.channel.id == id);
    pending.remove(call);
    if (error == null) {
      call.completer.complete(
        buildChannelSchedule(
          call.channel,
          (call.channel.source as ManualSource).items,
        ),
      );
    } else {
      call.completer.completeError(error);
    }
  }
}

class _IndexedHealthController extends _ControlledHealthController {
  _IndexedHealthController({required super.channels});

  int channelListReads = 0;
  int revisionReads = 0;

  @override
  List<Channel> get channels {
    channelListReads++;
    return super.channels;
  }

  @override
  int channelRevision(String id) {
    revisionReads++;
    return super.channelRevision(id);
  }
}

class _HealthCall {
  const _HealthCall(this.channel, this.completer);

  final Channel channel;
  final Completer<ScheduleIndex> completer;
}
