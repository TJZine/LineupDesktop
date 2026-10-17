# Disposable probe reproduction record

These are review artifacts, not permanent tests or implementation patches. They exercise unchanged production owners using synthetic boundaries. Several intentionally assert the expected contract and fail on the reviewed source; the duration characterization instead asserts the observed failure and passes. Neither is passing product acceptance.

Source: 4fb7758034f4f47290fae13a4ea8275860ba1284. Pinned Flutter 3.47.6 / Dart 3.13.5, Darwin arm64, TZ=America/New_York. Run from repository root. Original ignored run directory: build/review-probes/2026-10-10-4fb77580/orchestrator-run. Verify a fresh unique ignored destination with git check-ignore before writing; do not overwrite the existing probes. The relative FixtureStore imports assume that directory depth.

Command template: TZ=America/New_York /Users/tristan/.cache/lineup-flutter/3.47.6/flutter/bin/flutter test --no-pub <probe-path>. SDK may write its normal cache. No live network/accounts/private media were used.

For multipart_probe_test.dart and pending_eof_probe_test.dart, the source shown below is the probe entry plus imports. Append the unchanged suffix of test/playback/player_coordinator_test.dart from the first `void _showPresentation` through EOF at the reviewed SHA. This reuses the existing deterministic continuation/lineup/native/store fixtures, not a copied production algorithm. The original main and all original tests are excluded. It includes unused fixture helpers solely to retain an unchanged fixture set. Inspect the fixture source from the exact reviewed SHA before reproducing on a changed candidate.

Expected distinctions:
- Worker: ordinary build works; repeated immediate/microtask/Timer.run disposal must settle. Race trial number is nondeterministic; 5-second noncompletion alone is not proof of permanent noncompletion—see the missing completer settlement source in F-004.
- PIN: no saved reconnect clears PIN; delayed saved connection failure retains PIN in the real shell despite accepted persisted profile. Escape recovers. Fake Plex at the external boundary does not override selectProfile.
- Duration: ordinary 1800000 ms works; one/two 9007199254740991 ms items build then projection errors; two overflow loop sign. Passing characterization is a bug observation.
- Guide: pointer menu invokes callback; actual focused Enter/Space incorrectly tune. Independent row completion deletes raw trailing space. This does not execute every sibling control or IME.
- Multipart: frozen clock ensures a valid first-part join. Both known durations retain part two at seek 40; missing second duration reloads part one. Initial wall-clock fixture attempts failed before reaching the claim and were corrected, not counted as defects.
- EOF: postcommit natural completion advances; playing then ended before delayed first load returns strands. This imposes an allowed fake-player ordering and does not establish that actual Windows messaging generates it. CAND-009 remains a hypothesis.

## worker_disposal_probe_test.dart

Full executed source SHA-256: 43a700cafd49c9aa51e22a3e70ea25980f1bbc0073ede1680e2c822f5dda9638

~~~dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/schedule_worker.dart';
import 'package:lineup_desktop/plex/plex_models.dart';

void main() {
  final channel = Channel(
    id: 'synthetic', number: 1, name: 'Synthetic',
    source: const LibrarySource(libraryId: 'library', libraryType: PlexLibraryType.movie),
    playbackMode: PlaybackMode.sequential, anchor: DateTime.utc(2026), shuffleSeed: 1,
  );
  final media = [PlexMediaItem(id: 'item', title: 'Synthetic', type: 'movie',
    duration: Duration(minutes: 30), libraryId: 'library',
    parts: [PlexMediaPart(path: '/library/parts/synthetic')])];
  test('real worker normal-build control and disposal startup races settle', () async {
    final control = ScheduleWorker(media, const []);
    expect((await control.build(channel)).items.single.id, 'item');
    control.dispose();
    for (var i = 0; i < 300; i++) {
      final worker = ScheduleWorker(media, const []);
      final result = worker.build(channel).then<Object>((value) => value, onError: (Object error) => error);
      switch (i % 3) {
        case 0: worker.dispose();
        case 1: scheduleMicrotask(worker.dispose);
        case 2: Timer.run(worker.dispose);
      }
      final observed = await result.timeout(const Duration(seconds: 5), onTimeout: () => 'TIMEOUT');
      worker.dispose();
      expect(observed, isNot('TIMEOUT'), reason: 'startup disposal trial $i must settle');
    }
  });
}
~~~

## pin_recovery_probe_test.dart

Full executed source SHA-256: 37e9014983239243a568feea0f203dc02ccf82d28fd27e26491abeafd16bedfd

~~~dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/app/lineup_shell.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import '../../../../test/support/ui_fixture.dart';

const users = [PlexHomeUser(id:'owner',name:'Owner',protected:false), PlexHomeUser(id:'protected',name:'Protected',protected:true)];
class Credentials implements CredentialStore {
  Future<String?> readAccountToken() async => 'synthetic-account';
  Future<String?> readProfileToken(String id) async => null;
  Future<void> writeAccountToken(String token) async {}
  Future<void> writeProfileToken(String id,String token) async {}
  Future<void> clear() async {}
}
class Plex extends PlexClient {
  Plex():super(clientIdentifier:'synthetic-client',httpClient:MockClient((_) async=>throw StateError('unexpected HTTP')));
  final connectionGate=Completer<PlexConnection>();
  int switches=0;
  Future<PlexAccount> account(String token) async => const PlexAccount(id:'owner',name:'Owner',email:'synthetic@example.invalid');
  Future<List<PlexHomeUser>> homeUsers(String token) async=>users;
  Future<String> switchHomeUser(String token,String id,String? pin) async {switches++; return 'synthetic-profile';}
  Future<List<PlexServerAccess>> discoverServers(String token) async=>[PlexServerAccess(server:const PlexServer(id:'server',name:'Synthetic server',connections:[]),token:'synthetic-pms')];
  Future<PlexConnection> selectConnection(PlexServer server,String token) => connectionGate.future;
}
void main(){
 for(final saved in [false,true]) {
 testWidgets(saved?'saved server failure must expose server recovery after accepted PIN':'accepted PIN without saved server reaches server picker', (tester) async {
  tester.view.physicalSize=const Size(1920,1080); tester.view.devicePixelRatio=1;
  addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
  final store=FixtureStore()..state=PersistedState(settings:const LineupSettings(reduceMotion:true),selectedServerByProfile:saved?{'protected':'server'}:{});
  final plex=Plex(); final controller=LineupController(store:store,credentials:Credentials(),plex:plex);
  await controller.initialize(); addTearDown(controller.dispose);
  expect(controller.stage,SetupStage.profiles);
  await tester.pumpWidget(MaterialApp(builder:LineupCanvas.builder,home:LineupShell(controller:controller,player:FixturePlayer())));
  await tester.pumpAndSettle(); await tester.tap(find.byKey(const ValueKey('profile-card-protected')));await tester.pumpAndSettle();
  for(final key in [LogicalKeyboardKey.digit1,LogicalKeyboardKey.digit2,LogicalKeyboardKey.digit3,LogicalKeyboardKey.digit4]) {await tester.sendKeyEvent(key);}
  await tester.pump(); await tester.pump(const Duration(milliseconds:250));
  expect(controller.profile?.id,'protected');expect(plex.switches,1);
  if(saved){
    expect(controller.stage,SetupStage.servers); expect(controller.busy,true);
    plex.connectionGate.completeError(const PlexException('server-unreachable','Synthetic server unavailable.'));
    await tester.pumpAndSettle();expect(controller.busy,false);expect(controller.error,isNotNull);
    print('PIN recovery observation: stage=${controller.stage.name}; profile committed=${controller.profile?.id=="protected"}; pin sheets=${find.byKey(const Key("profile-pin-sheet")).evaluate().length}; server tiles=${find.text("Synthetic server").evaluate().length}');
  } else {await tester.pumpAndSettle();}
  final retainedPin = find.byKey(const Key('profile-pin-sheet')).evaluate().isNotEmpty;
  if(saved){await tester.sendKeyEvent(LogicalKeyboardKey.escape);await tester.pumpAndSettle();expect(find.byKey(const Key('profile-pin-sheet')),findsNothing,reason:'Escape recovery control');expect(find.text('Synthetic server'),findsWidgets);}
  expect(retainedPin,false,reason:'accepted profile must leave the PIN step without manual Escape');
  expect(find.text('Synthetic server'),findsWidgets);
  await tester.pumpWidget(const SizedBox.shrink());
 });
 }
}
~~~

## duration_probe_test.dart

Full executed source SHA-256: 435067f1eb04165a699cfd017c55e3c9005e61d742490aa3c9092c561c2de05d

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/channels/content_resolver.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
void main(){
 for(final count in [1,2]){
 test('oversized external duration $count-item characterization',(){
  final items=[for(var i=0;i<count;i++) channelItemFor(parseMediaItem({'ratingKey':'synthetic-$i','title':'Synthetic','type':'movie','duration':9007199254740991,'Media':[{'Part':[{'key':'/library/parts/synthetic'}]}]},libraryId:'library'))];
  final schedule=buildSchedule(items,mode:PlaybackMode.sequential,seed:1);
  Object? failure;
  try {programAt(DateTime.utc(2026,10,10),DateTime.utc(2026),schedule);}catch(error){failure=error;}
  print('duration characterization count=$count loopPositive=${schedule.loopDuration>Duration.zero} projectionError=${failure.runtimeType}');
  expect(failure,isNotNull,reason:'characterizes accepted schedule that fails projection, not acceptance');
 });
 }
 test('ordinary parsed media schedule control projects successfully',(){
 final item=channelItemFor(parseMediaItem({'ratingKey':'synthetic','title':'Synthetic','type':'movie','duration':1800000,'Media':[{'Part':[{'key':'/library/parts/synthetic'}]}]}));
 final schedule=buildSchedule([item],mode:PlaybackMode.sequential,seed:1);
 expect(programAt(DateTime.utc(2026,10,10),DateTime.utc(2026),schedule).item.id,'synthetic');
 });
}
~~~

## guide_input_probe_test.dart

Full executed source SHA-256: 9a2c429ebabdd1d59421f10f0033eab0d3c67081caeb0118e6710ca68d6664ce

~~~dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/guide/guide_view.dart';
import 'package:lineup_desktop/ui/lineup_canvas.dart';
import '../../../../test/support/ui_fixture.dart';
final now=DateTime.utc(2026,10,10,12);
Channel channel(int i)=>Channel(id:'c$i',number:i,name:'channel $i',source:const ManualSource([ChannelItem(id:'item',title:'Synthetic',duration:Duration(minutes:30))]),playbackMode:PlaybackMode.sequential,anchor:DateTime.utc(2026),shuffleSeed:1);
ScheduleIndex schedule()=>buildSchedule(const [ChannelItem(id:'item',title:'Synthetic',duration:Duration(minutes:30))],mode:PlaybackMode.sequential,seed:1);
void main(){
 for(final key in [LogicalKeyboardKey.enter,LogicalKeyboardKey.space]){
 testWidgets('focused Guide menu owns ${key.keyLabel} activation',(tester)async{
 final lineup=FixtureController()..stage=SetupStage.ready..channels=[channel(1)];
 final guide=GuideController(lineup:lineup,clock:()=>now,loadSchedule:(_)async=>schedule());
 addTearDown(guide.dispose);addTearDown(lineup.dispose);
 var menus=0;var tunes=0;
 await tester.pumpWidget(MaterialApp(builder:LineupCanvas.builder,home:GuideView(controller:guide,onClose:(){},onTune:(_)async{tunes++;},onOpenMenu:(_,__) {menus++;})));
 await tester.pumpAndSettle();
 final menu=find.byKey(const Key('guide-app-menu'));
 await tester.tap(menu);await tester.pump();expect(menus,1,reason:'pointer positive control');
 tester.widget<TextButton>(menu).focusNode!.requestFocus();await tester.pump();
 expect(tester.widget<TextButton>(menu).focusNode!.hasFocus,true);
 await tester.sendKeyEvent(key);await tester.pumpAndSettle();
 print('Guide activation ${key.keyLabel}: menus=$menus tunes=$tunes');
 await tester.pumpWidget(const SizedBox.shrink());
 expect(menus,2,reason:'focused menu must activate via keyboard');expect(tunes,0);
 });}
 testWidgets('pending schedule completion preserves raw multiword search edit',(tester)async{
 final lineup=FixtureController()..stage=SetupStage.ready..channels=[channel(1),channel(2)];
 final pending=Completer<ScheduleIndex>();
 final guide=GuideController(lineup:lineup,clock:()=>now,loadSchedule:(c)=>c.id=='c1'?Future.value(schedule()):pending.future);
 addTearDown(guide.dispose);addTearDown(lineup.dispose);
 await tester.pumpWidget(MaterialApp(builder:LineupCanvas.builder,home:GuideView(controller:guide,onClose:(){},onTune:(_)async{})));
 await tester.pump();await tester.pump(const Duration(milliseconds:100));
 final search=find.byKey(const Key('guide-channel-search'));
 await tester.enterText(search,'channel');await tester.pump();
 await tester.enterText(search,'channel ');await tester.pump();
 expect(tester.widget<TextField>(search).controller!.text,'channel ',reason:'trailing space initially retained');
 pending.complete(schedule());await tester.pumpAndSettle();
 final value=tester.widget<TextField>(search).controller!.value;
 print('Guide editing: rawLength=${value.text.length} selection=${value.selection.baseOffset} normalized=${guide.searchQuery}');
 await tester.pumpWidget(const SizedBox.shrink());
 expect(value.text,'channel ',reason:'unrelated schedule completion must preserve separator');
 expect(value.selection.baseOffset,8);
 });
}
~~~

## multipart_probe_test.dart

Full executed source SHA-256: 5abfa78bac7d5fbe6b211cb4a3f1ef8f9aca0b8c019b556d36caa1dc3fda9c78

~~~dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/windows_native_player.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final complete in [true, false]) {
    test('later-part seek with complete metadata=$complete', () async {
      final fixture = _ContinuationFixture(parts: _parts(
        first: const Duration(seconds: 60),
        second: complete ? const Duration(seconds: 90) : null,
      ));
      final player = fixture.player;
      final coordinator = fixture.coordinator;
      addTearDown(fixture.close);
      await coordinator.tune('channel-b');
      player.duration = const Duration(seconds: 60);
      player.position = player.duration;
      player.emitStatus(PlayerState.ended, generation: player.loadGenerations.last);
      await pumpEventQueue(times: 5);
      expect(player.loads.last.path, '/part-2.mkv');
      player.position = const Duration(seconds: 10);
      player.duration = const Duration(seconds: 90);
      player.emitStatus(PlayerState.playing, generation: player.loadGenerations.last);
      await pumpEventQueue(times: 2);
      expect(coordinator.position, Duration(seconds: complete ? 70 : 10));
      final before = player.loads.length;
      await coordinator.seekBy(const Duration(seconds: 30));
      print('complete=$complete loadsBefore=$before loadsAfter=${player.loads.length} lastPart=${player.loads.last.path} seek=${player.seeks.last.inSeconds}');
      expect(player.loads.length, before, reason: 'A local +30s seek should remain in active part 2');
      expect(player.seeks.last, const Duration(seconds: 40));
    });
  }
}
~~~

## pending_eof_probe_test.dart

Full executed source SHA-256: 38f35e1102a23dad7e31a9ec7f009d2da10abbd59652c29a08d4254fd41c7291

~~~dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineup_desktop/app/lineup_controller.dart';
import 'package:lineup_desktop/channels/channel.dart';
import 'package:lineup_desktop/channels/scheduler.dart';
import 'package:lineup_desktop/guide/guide_controller.dart';
import 'package:lineup_desktop/persistence/app_store.dart';
import 'package:lineup_desktop/playback/native_player.dart';
import 'package:lineup_desktop/playback/player_coordinator.dart';
import 'package:lineup_desktop/playback/windows_native_player.dart';
import 'package:lineup_desktop/plex/plex_client.dart';
import 'package:lineup_desktop/plex/plex_models.dart';
import 'package:lineup_desktop/settings/lineup_settings.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final early in [false, true]) {
    test('EOF before load completion=$early (allowed event ordering)', () async {
      final player = _PendingEofPlayer(early);
      final fixture = _ContinuationFixture(player: player, parts: _parts(
        first: const Duration(seconds: 60), second: const Duration(seconds: 60)));
      addTearDown(fixture.close);
      await fixture.coordinator.tune('channel-b');
      if (!early) fixture.endNaturally();
      await pumpEventQueue(times: 5);
      print('early=$early loads=${player.loads.length} intent=${fixture.coordinator.hasPlaybackIntent} status=${fixture.coordinator.status.state}');
      expect(player.loads, hasLength(2), reason: 'Natural first-part EOF advances to second part');
    });
  }
}
class _PendingEofPlayer extends _EventPlayer {
  _PendingEofPlayer(this.early);
  final bool early;
  @override
  Future<void> load(Uri media, {String? plexToken, int? generation}) async {
    await super.load(media, plexToken: plexToken, generation: generation);
    if (!early || loads.length != 1) return;
    position = const Duration(seconds: 59);
    duration = const Duration(seconds: 60);
    status = const PlayerStatus(state: PlayerState.playing, message: 'Playing');
    emitStatus(PlayerState.playing, generation: generation);
    await Future<void>.delayed(Duration.zero);
    position = duration;
    status = const PlayerStatus(state: PlayerState.ended, message: 'Ended');
    emitStatus(PlayerState.ended, generation: generation);
    await Future<void>.delayed(Duration.zero);
  }
}
~~~

