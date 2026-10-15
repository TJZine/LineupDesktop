import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/channel_studio_draft.dart';
import 'package:lineup_desktop/channels/channel.dart';

void main() {
  const source = ManualSource([]);
  ChannelStudioDraft newDraft() => ChannelStudioDraft(
    id: 'new-channel',
    source: source,
    duplicate: false,
    generated: false,
  )..configureSource();

  Map<String, Object?> signature(
    ChannelStudioDraft draft, {
    String name = 'New',
    String number = '7',
  }) => draft.signature(name: name, number: number, libraries: const []);

  Channel project(ChannelStudioDraft draft, {required bool preview}) => draft
      .project(name: 'New', number: '7', programming: source, preview: preview);

  test(
    'projection never stages timing and staging commits without dirtying',
    () {
      final draft = newDraft();
      draft.acceptBaseline(signature(draft));
      final placeholder = project(draft, preview: true);
      expect(draft.scheduleIdentityCommitted, isFalse);
      expect(project(draft, preview: true).toJson(), placeholder.toJson());
      var clockCalls = 0;
      final anchor = DateTime.utc(2026, 10, 12, 15);
      DateTime clock() {
        clockCalls++;
        return anchor;
      }

      draft.stageScheduleIdentity(clock, valid: false);
      expect(clockCalls, 0);
      draft.stageScheduleIdentity(clock, valid: true);
      draft.stageScheduleIdentity(clock, valid: true);
      expect(clockCalls, 1);
      final preview = project(draft, preview: true);
      expect(preview.anchor, anchor);
      expect(project(draft, preview: false).anchor, placeholder.anchor);
      draft.commitScheduleIdentity(signature(draft));
      expect(draft.dirty, isFalse);
      expect(draft.scheduleIdentityCommitted, isTrue);
      expect(project(draft, preview: false).toJson(), preview.toJson());
    },
  );

  test(
    'invalid text stays dirty while preview safely projects placeholders',
    () {
      final draft = newDraft();
      draft.acceptBaseline(signature(draft));
      draft.updateDirty(signature(draft, name: ' ', number: 'bad'));
      expect(draft.dirty, isTrue);
      final preview = draft.project(
        name: ' ',
        number: 'bad',
        programming: source,
        preview: true,
      );
      expect(preview.name, 'New channel');
      expect(preview.number, 1);
      expect(
        () => draft.project(
          name: ' ',
          number: 'bad',
          programming: source,
          preview: false,
        ),
        throwsFormatException,
      );
      draft.updateDirty(signature(draft));
      expect(draft.dirty, isFalse);
    },
  );

  test(
    'save-as-new retires candidates and saved reload restores committed timing',
    () {
      final draft = newDraft();
      draft.acceptBaseline(signature(draft));
      draft.stageScheduleIdentity(() => DateTime.utc(2026), valid: true);
      draft.prepareSaveAsNew('replacement');
      expect(draft.dirty, isTrue);
      expect(draft.scheduleIdentityCommitted, isFalse);
      expect(
        project(draft, preview: true).anchor,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      final replacementAnchor = DateTime.utc(2027);
      draft.stageScheduleIdentity(() => replacementAnchor, valid: true);
      draft.commitScheduleIdentity(signature(draft));
      final saved = project(draft, preview: false);
      expect(saved.shuffleSeed, stableChannelSeed('replacement'));
      draft.loadSaved(saved);
      draft.acceptBaseline(signature(draft));
      expect(draft.dirty, isFalse);
      expect(project(draft, preview: true).anchor, replacementAnchor);
    },
  );
}
