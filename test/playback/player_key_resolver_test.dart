import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/player_key_resolver.dart';

typedef _Case = ({
  LogicalKeyboardKey key,
  PlayerOverlay overlay,
  bool dvr,
  bool unsupported,
  bool initialPress,
  bool hasProgram,
  bool tvOsdAtBottom,
  PlayerAction? action,
  String? digit,
});

void main() {
  final cases = <_Case>[];
  void row(
    Iterable<LogicalKeyboardKey> keys,
    PlayerOverlay overlay,
    PlayerAction? action, {
    bool dvr = true,
    bool unsupported = false,
    bool initialPress = true,
    bool hasProgram = true,
    bool tvOsdAtBottom = false,
    String? digit,
  }) {
    for (final key in keys) {
      cases.add((
        key: key,
        overlay: overlay,
        dvr: dvr,
        unsupported: unsupported,
        initialPress: initialPress,
        hasProgram: hasProgram,
        tvOsdAtBottom: tvOsdAtBottom,
        action: action,
        digit: digit,
      ));
    }
  }

  const enter = [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
  ];
  const media = [
    LogicalKeyboardKey.mediaPlay,
    LogicalKeyboardKey.mediaPause,
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.mediaStop,
    LogicalKeyboardKey.mediaRewind,
    LogicalKeyboardKey.mediaFastForward,
  ];
  const keyboardTransport = [
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyL,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  ];
  const noSleepClose = {
    PlayerAction.ignored,
    PlayerAction.consumed,
    PlayerAction.backToGuide,
    PlayerAction.collapseNowPlaying,
    PlayerAction.closeOverlay,
    PlayerAction.commitChannelNumber,
    PlayerAction.miniGuideUp,
    PlayerAction.miniGuideDown,
    PlayerAction.tuneMiniGuide,
    PlayerAction.showOsd,
    PlayerAction.openMenu,
    PlayerAction.showSleepTimer,
  };

  for (final overlay in PlayerOverlay.values.where(
    (o) => o != PlayerOverlay.programInfo,
  )) {
    // Back outranks every mode/availability guard, including repeats.
    for (final dvr in [false, true]) {
      for (final unsupported in [false, true]) {
        for (final initialPress in [false, true]) {
          row(
            [
              LogicalKeyboardKey.escape,
              LogicalKeyboardKey.backspace,
              LogicalKeyboardKey.goBack,
            ],
            overlay,
            switch (overlay) {
              PlayerOverlay.none => PlayerAction.backToGuide,
              PlayerOverlay.nowPlaying => PlayerAction.collapseNowPlaying,
              _ => PlayerAction.closeOverlay,
            },
            dvr: dvr,
            unsupported: unsupported,
            initialPress: initialPress,
          );
        }
      }
    }
    // Physical media transport is consumed with DVR off even in owned drawers.
    row(media, overlay, PlayerAction.consumed, dvr: false);
    row([LogicalKeyboardKey.keyQ], overlay, PlayerAction.ignored);
    final owned =
        overlay == PlayerOverlay.audioTracks ||
        overlay == PlayerOverlay.subtitleTracks;
    final error = overlay == PlayerOverlay.error;
    final number = overlay == PlayerOverlay.channelNumber;
    final mini = overlay == PlayerOverlay.miniGuide;
    final ordinary = [
      PlayerOverlay.none,
      PlayerOverlay.osd,
      PlayerOverlay.nowPlaying,
    ].contains(overlay);
    final now = overlay == PlayerOverlay.nowPlaying;

    row(
      [
        LogicalKeyboardKey.keyG,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.guide,
      ],
      overlay,
      error || number ? PlayerAction.ignored : PlayerAction.openGuide,
    );
    row(
      [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.channelUp],
      overlay,
      owned || number
          ? PlayerAction.ignored
          : mini
          ? PlayerAction.miniGuidePageUp
          : PlayerAction.previousChannel,
    );
    row(
      [LogicalKeyboardKey.pageDown, LogicalKeyboardKey.channelDown],
      overlay,
      owned || number
          ? PlayerAction.ignored
          : mini
          ? PlayerAction.miniGuidePageDown
          : PlayerAction.nextChannel,
    );
    row(
      enter,
      overlay,
      owned || error
          ? PlayerAction.ignored
          : number
          ? PlayerAction.commitChannelNumber
          : mini
          ? PlayerAction.tuneMiniGuide
          : now || overlay == PlayerOverlay.none
          ? PlayerAction.showOsd
          : PlayerAction.ignored,
    );
    row(
      [LogicalKeyboardKey.space],
      overlay,
      owned || error || number
          ? PlayerAction.ignored
          : mini
          ? PlayerAction.tuneMiniGuide
          : ordinary
          ? PlayerAction.togglePlayback
          : PlayerAction.ignored,
    );
    row(
      [LogicalKeyboardKey.keyK, LogicalKeyboardKey.mediaPlayPause],
      overlay,
      ordinary ? PlayerAction.togglePlayback : PlayerAction.ignored,
    );
    row(
      [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyJ],
      overlay,
      ordinary ? PlayerAction.seekBackward : PlayerAction.ignored,
    );
    row(
      [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyL],
      overlay,
      mini
          ? PlayerAction.openGuide
          : ordinary
          ? PlayerAction.seekForward
          : PlayerAction.ignored,
    );
    row(
      [LogicalKeyboardKey.arrowUp],
      overlay,
      mini
          ? PlayerAction.miniGuideUp
          : overlay == PlayerOverlay.none || overlay == PlayerOverlay.osd
          ? PlayerAction.showMiniGuide
          : PlayerAction.ignored,
    );
    for (final hasProgram in [false, true]) {
      row(
        [LogicalKeyboardKey.arrowDown],
        overlay,
        mini
            ? PlayerAction.miniGuideDown
            : overlay == PlayerOverlay.none || overlay == PlayerOverlay.osd
            ? hasProgram
                  ? PlayerAction.showNowPlaying
                  : PlayerAction.showOsdFromInfo
            : PlayerAction.ignored,
        hasProgram: hasProgram,
      );
    }
    final blocksActions = owned || error || number;
    row(
      [
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.info,
        LogicalKeyboardKey.contextMenu,
      ],
      overlay,
      blocksActions
          ? PlayerAction.ignored
          : now
          ? PlayerAction.showOsdFromInfo
          : PlayerAction.showNowPlaying,
    );
    row(
      [LogicalKeyboardKey.keyF, LogicalKeyboardKey.f11],
      overlay,
      blocksActions ? PlayerAction.ignored : PlayerAction.toggleFullscreen,
    );
    row(
      [LogicalKeyboardKey.keyS],
      overlay,
      blocksActions ? PlayerAction.ignored : PlayerAction.showSleepTimer,
    );
    row(
      [
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.info,
        LogicalKeyboardKey.contextMenu,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.keyS,
      ],
      overlay,
      PlayerAction.ignored,
      initialPress: false,
    );
    for (final initialPress in [false, true]) {
      row(
        [LogicalKeyboardKey.keyA],
        overlay,
        blocksActions ? PlayerAction.ignored : PlayerAction.showAudioTracks,
        initialPress: initialPress,
      );
      row(
        [LogicalKeyboardKey.keyC],
        overlay,
        blocksActions ? PlayerAction.ignored : PlayerAction.showSubtitleTracks,
        initialPress: initialPress,
      );
    }
    row(
      [LogicalKeyboardKey.mediaPlay],
      overlay,
      blocksActions
          ? PlayerAction.ignored
          : now
          ? PlayerAction.playAndShowOsd
          : PlayerAction.play,
    );
    row(
      [LogicalKeyboardKey.mediaPause],
      overlay,
      blocksActions
          ? PlayerAction.ignored
          : now
          ? PlayerAction.pauseAndShowOsd
          : PlayerAction.pause,
    );
    row(
      [LogicalKeyboardKey.mediaStop],
      overlay,
      blocksActions ? PlayerAction.ignored : PlayerAction.stop,
    );
    row(
      [LogicalKeyboardKey.mediaRewind],
      overlay,
      blocksActions
          ? PlayerAction.ignored
          : now
          ? PlayerAction.seekBackward
          : PlayerAction.rewind,
    );
    row(
      [LogicalKeyboardKey.mediaFastForward],
      overlay,
      blocksActions
          ? PlayerAction.ignored
          : now
          ? PlayerAction.seekForward
          : PlayerAction.fastForward,
    );

    if (ordinary) {
      row(keyboardTransport, overlay, PlayerAction.consumed, dvr: false);
    }
    if (!ordinary) {
      row(
        [LogicalKeyboardKey.keyK, LogicalKeyboardKey.keyJ],
        overlay,
        PlayerAction.ignored,
        dvr: false,
      );
      row(
        [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyL],
        overlay,
        mini ? PlayerAction.openGuide : PlayerAction.ignored,
        dvr: false,
      );
      row(
        [LogicalKeyboardKey.space],
        overlay,
        mini ? PlayerAction.tuneMiniGuide : PlayerAction.ignored,
        dvr: false,
      );
    }
    row(
      [LogicalKeyboardKey.arrowLeft],
      overlay,
      overlay == PlayerOverlay.none
          ? PlayerAction.consumed
          : ordinary
          ? PlayerAction.seekBackward
          : PlayerAction.ignored,
      unsupported: true,
    );
    row(
      [LogicalKeyboardKey.arrowRight],
      overlay,
      overlay == PlayerOverlay.none
          ? PlayerAction.consumed
          : mini
          ? PlayerAction.openGuide
          : ordinary
          ? PlayerAction.seekForward
          : PlayerAction.ignored,
      unsupported: true,
    );
    // Unsupported policy runs before overlay ownership and initial-press guards.
    row(
      [
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.mediaPlay,
        LogicalKeyboardKey.mediaPause,
        LogicalKeyboardKey.mediaStop,
        LogicalKeyboardKey.mediaRewind,
        LogicalKeyboardKey.mediaFastForward,
      ],
      overlay,
      PlayerAction.consumed,
      unsupported: true,
      initialPress: false,
    );
    row(
      [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.channelUp],
      overlay,
      mini ? PlayerAction.miniGuidePageUp : PlayerAction.consumed,
      unsupported: true,
    );
    row(
      [LogicalKeyboardKey.pageDown, LogicalKeyboardKey.channelDown],
      overlay,
      mini ? PlayerAction.miniGuidePageDown : PlayerAction.consumed,
      unsupported: true,
    );
    row(
      enter,
      overlay,
      overlay == PlayerOverlay.none || mini
          ? PlayerAction.consumed
          : number
          ? PlayerAction.commitChannelNumber
          : now
          ? PlayerAction.showOsd
          : PlayerAction.ignored,
      unsupported: true,
    );
    row(
      [LogicalKeyboardKey.space, LogicalKeyboardKey.mediaPlayPause],
      overlay,
      overlay == PlayerOverlay.none || mini
          ? PlayerAction.consumed
          : ordinary
          ? PlayerAction.togglePlayback
          : PlayerAction.ignored,
      unsupported: true,
    );
    for (final (key, digit) in [
      (LogicalKeyboardKey.digit0, '0'),
      (LogicalKeyboardKey.digit1, '1'),
      (LogicalKeyboardKey.digit2, '2'),
      (LogicalKeyboardKey.digit3, '3'),
      (LogicalKeyboardKey.digit4, '4'),
      (LogicalKeyboardKey.digit5, '5'),
      (LogicalKeyboardKey.digit6, '6'),
      (LogicalKeyboardKey.digit7, '7'),
      (LogicalKeyboardKey.digit8, '8'),
      (LogicalKeyboardKey.digit9, '9'),
      (LogicalKeyboardKey.numpad0, '0'),
      (LogicalKeyboardKey.numpad1, '1'),
      (LogicalKeyboardKey.numpad2, '2'),
      (LogicalKeyboardKey.numpad3, '3'),
      (LogicalKeyboardKey.numpad4, '4'),
      (LogicalKeyboardKey.numpad5, '5'),
      (LogicalKeyboardKey.numpad6, '6'),
      (LogicalKeyboardKey.numpad7, '7'),
      (LogicalKeyboardKey.numpad8, '8'),
      (LogicalKeyboardKey.numpad9, '9'),
    ]) {
      row(
        [key],
        overlay,
        owned || error ? PlayerAction.ignored : null,
        digit: owned || error ? null : digit,
        initialPress: false,
      );
      row([key], overlay, PlayerAction.consumed, unsupported: true);
    }
  }

  // Holding selection, navigation, or transport keys repeats the same intent;
  // only I/F/F11/S are deliberately restricted to the initial press.
  for (final c in List<_Case>.of(cases)) {
    if (c.initialPress &&
        (media.contains(c.key) ||
            keyboardTransport.contains(c.key) ||
            enter.contains(c.key) ||
            const [
              LogicalKeyboardKey.arrowUp,
              LogicalKeyboardKey.arrowDown,
              LogicalKeyboardKey.pageUp,
              LogicalKeyboardKey.pageDown,
            ].contains(c.key))) {
      cases.add((
        key: c.key,
        overlay: c.overlay,
        dvr: c.dvr,
        unsupported: c.unsupported,
        initialPress: false,
        hasProgram: c.hasProgram,
        tvOsdAtBottom: c.tvOsdAtBottom,
        action: c.action,
        digit: c.digit,
      ));
    }
  }

  final tvAliases = {
    LogicalKeyboardKey.channelUp,
    LogicalKeyboardKey.channelDown,
    LogicalKeyboardKey.guide,
    LogicalKeyboardKey.info,
    LogicalKeyboardKey.contextMenu,
  };
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    for (final tv in [false, true]) {
      test('Player key priority, aliases and sleep policy on $platform TV=$tv', () {
        debugDefaultTargetPlatformOverride = platform;
        try {
          final actions = <PlayerAction>{};
          for (final c in cases) {
            final reason =
                '${c.key.keyLabel} / ${c.overlay.name} / dvr=${c.dvr} / unsupported=${c.unsupported} / initial=${c.initialPress} / program=${c.hasProgram}';
            final command = resolvePlayerKey(
              c.key,
              overlay: c.overlay,
              androidTv: tv,
              dvr: c.dvr,
              unsupported: c.unsupported,
              initialPress: c.initialPress,
              hasProgram: c.hasProgram,
              tvOsdAtBottom: c.tvOsdAtBottom,
            );
            final expectedAction = !tv && tvAliases.contains(c.key)
                ? PlayerAction.ignored
                : tv && c.key == LogicalKeyboardKey.contextMenu
                ? PlayerAction.openMenu
                : tv &&
                      c.key == LogicalKeyboardKey.arrowDown &&
                      (c.overlay == PlayerOverlay.none ||
                          c.overlay == PlayerOverlay.osd)
                ? c.overlay == PlayerOverlay.none
                      ? PlayerAction.showOsd
                      : c.tvOsdAtBottom && c.hasProgram
                      ? PlayerAction.showNowPlaying
                      : PlayerAction.consumed
                : c.action;
            if (c.digit != null) {
              expect(
                command,
                isA<AppendChannelDigit>().having(
                  (value) => value.digit,
                  'digit',
                  c.digit,
                ),
                reason: reason,
              );
              expect(command.closesSleepPicker, isTrue, reason: reason);
            } else {
              expect(command, expectedAction, reason: reason);
              expect(
                command.closesSleepPicker,
                !noSleepClose.contains(expectedAction),
                reason: reason,
              );
              actions.add(expectedAction!);
            }
          }
          expect(
            actions,
            containsAll(
              PlayerAction.values.where(
                (action) => tv || action != PlayerAction.openMenu,
              ),
            ),
            reason: 'Every executor action has behavioral table evidence.',
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  test('M1 TV Menu and compact details intents are state-specific', () {
    PlayerCommand resolve(
      LogicalKeyboardKey key, {
      required PlayerOverlay overlay,
      bool androidTv = true,
      bool hasProgram = true,
      bool tvOsdAtBottom = false,
      bool initialPress = true,
    }) => resolvePlayerKey(
      key,
      overlay: overlay,
      androidTv: androidTv,
      dvr: true,
      unsupported: false,
      initialPress: initialPress,
      hasProgram: hasProgram,
      tvOsdAtBottom: tvOsdAtBottom,
    );

    for (final overlay in [
      PlayerOverlay.none,
      PlayerOverlay.osd,
      PlayerOverlay.nowPlaying,
    ]) {
      expect(
        resolve(LogicalKeyboardKey.contextMenu, overlay: overlay),
        PlayerAction.openMenu,
      );
    }
    expect(
      resolve(LogicalKeyboardKey.arrowDown, overlay: PlayerOverlay.none),
      PlayerAction.showOsd,
    );
    expect(
      resolve(
        LogicalKeyboardKey.arrowDown,
        overlay: PlayerOverlay.none,
        hasProgram: false,
      ),
      PlayerAction.showOsd,
    );
    expect(
      resolve(LogicalKeyboardKey.arrowDown, overlay: PlayerOverlay.osd),
      PlayerAction.consumed,
    );
    expect(
      resolve(
        LogicalKeyboardKey.arrowDown,
        overlay: PlayerOverlay.osd,
        tvOsdAtBottom: true,
      ),
      PlayerAction.showNowPlaying,
    );
    expect(
      resolve(
        LogicalKeyboardKey.arrowDown,
        overlay: PlayerOverlay.osd,
        tvOsdAtBottom: true,
        hasProgram: false,
      ),
      PlayerAction.consumed,
    );
    expect(
      resolve(LogicalKeyboardKey.keyI, overlay: PlayerOverlay.none),
      PlayerAction.showNowPlaying,
    );
    expect(
      resolve(LogicalKeyboardKey.info, overlay: PlayerOverlay.nowPlaying),
      PlayerAction.showOsdFromInfo,
    );
    for (final key in [LogicalKeyboardKey.info, LogicalKeyboardKey.keyI]) {
      for (final overlay in [PlayerOverlay.none, PlayerOverlay.osd]) {
        expect(
          resolve(key, overlay: overlay, hasProgram: false),
          PlayerAction.showOsd,
        );
        expect(
          resolve(
            key,
            overlay: overlay,
            hasProgram: false,
            initialPress: false,
          ),
          PlayerAction.ignored,
        );
      }
    }
    expect(
      resolve(
        LogicalKeyboardKey.keyI,
        overlay: PlayerOverlay.none,
        androidTv: false,
        hasProgram: false,
      ),
      PlayerAction.showNowPlaying,
    );
  });

  for (final dvr in [false, true]) {
    for (final unsupported in [false, true]) {
      test(
        'program info remote availability DVR=$dvr unsupported=$unsupported',
        () {
          for (final key in [
            LogicalKeyboardKey.escape,
            LogicalKeyboardKey.goBack,
            LogicalKeyboardKey.backspace,
          ]) {
            expect(
              resolvePlayerKey(
                key,
                overlay: PlayerOverlay.programInfo,
                androidTv: true,
                dvr: dvr,
                unsupported: unsupported,
                initialPress: false,
                hasProgram: true,
              ),
              PlayerAction.closeOverlay,
            );
          }
          expect(
            resolvePlayerKey(
              LogicalKeyboardKey.guide,
              overlay: PlayerOverlay.programInfo,
              androidTv: true,
              dvr: dvr,
              unsupported: unsupported,
              initialPress: true,
              hasProgram: true,
            ),
            PlayerAction.openGuide,
          );
          for (final entry in {
            LogicalKeyboardKey.mediaPlayPause: PlayerAction.togglePlayback,
            LogicalKeyboardKey.mediaPlay: PlayerAction.play,
            LogicalKeyboardKey.mediaPause: PlayerAction.pause,
            LogicalKeyboardKey.mediaStop: PlayerAction.stop,
            LogicalKeyboardKey.mediaRewind: PlayerAction.rewind,
            LogicalKeyboardKey.mediaFastForward: PlayerAction.fastForward,
            LogicalKeyboardKey.channelUp: PlayerAction.previousChannel,
            LogicalKeyboardKey.channelDown: PlayerAction.nextChannel,
          }.entries) {
            final media =
                entry.key != LogicalKeyboardKey.channelUp &&
                entry.key != LogicalKeyboardKey.channelDown;
            final blocked = unsupported || (media && !dvr);
            expect(
              resolvePlayerKey(
                entry.key,
                overlay: PlayerOverlay.programInfo,
                androidTv: true,
                dvr: dvr,
                unsupported: unsupported,
                initialPress: true,
                hasProgram: true,
              ),
              blocked ? PlayerAction.consumed : entry.value,
              reason: entry.key.keyLabel,
            );
          }
          for (final key in [
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.select,
          ]) {
            expect(
              resolvePlayerKey(
                key,
                overlay: PlayerOverlay.programInfo,
                androidTv: true,
                dvr: dvr,
                unsupported: unsupported,
                initialPress: true,
                hasProgram: true,
              ),
              PlayerAction.ignored,
            );
          }
        },
      );
    }
  }

  test('a pressed Command key leaves every key unresolved for the menu', () {
    for (final key in [
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyF,
      LogicalKeyboardKey.keyC,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.escape,
    ]) {
      expect(
        resolvePlayerKey(
          key,
          overlay: PlayerOverlay.none,
          androidTv: false,
          dvr: true,
          unsupported: false,
          initialPress: true,
          hasProgram: true,
          commandPressed: true,
        ),
        PlayerAction.ignored,
        reason: key.keyLabel,
      );
    }
    expect(
      resolvePlayerKey(
        LogicalKeyboardKey.keyK,
        overlay: PlayerOverlay.none,
        androidTv: false,
        dvr: true,
        unsupported: false,
        initialPress: true,
        hasProgram: true,
      ),
      PlayerAction.togglePlayback,
    );
  });
}
