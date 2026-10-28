#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

#include <mach-o/dyld.h>
#include <limits.h>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#import "LineupNativePlayer.h"
#include "player_core/mpv_operations.h"

namespace {
const char* test_ca = nullptr;
std::string mode;
mpv_handle* observed_client = nullptr;

// One load per process. Only the worker touches lifecycle flags; publication
// to the platform messenger is atomic. No load target/property jump is progress.
struct PlaybackObservation {
  explicit PlaybackObservation(bool nonzero = false) : nonzero(nonzero) {}
  const bool nonzero;
  int files_started = 0;
  bool loaded = false;
  bool restarted = false;
  std::atomic<double> landing{-1.0};
  std::atomic<bool> advanced{false};
  std::atomic<bool> sampled{false};
  std::atomic<bool> initial_paused{false};
  std::atomic<bool> released{false};

  void Restart(double seconds, bool seeking, bool paused) {
    if (!loaded || restarted || seeking) return;
    restarted = true;
    // The alternate fixture has independently checked keyframes at 0,1,...,5.
    // Starting exactly at 3.5 or ignoring start and landing at 0 must fail.
    initial_paused.store(paused);
    if (paused && std::isfinite(seconds) && seconds >= 0 &&
        (nonzero ? std::abs(seconds - 3.0) <= 0.15 : seconds <= 0.15)) landing.store(seconds);
    sampled.store(true);
  }

  void Position(double seconds, bool seeking, bool paused) {
    const double baseline = landing.load();
    if (loaded && released.load() && !paused && !seeking && baseline >= 0 && std::isfinite(seconds) &&
        seconds >= baseline + 0.2) advanced.store(true);
  }
};
PlaybackObservation* observation = nullptr;
bool delay_exercised = false;
bool ignored_start = false;

// Deliberately omit only start in the sensitivity control. The original map
// retains authentication, redirect restrictions, and hr-seek policy.
int CommandTestNode(mpv_handle* client, mpv_node* command, mpv_node* result) {
  if (mode != "control-ignore-start-delayed") return mpv_command_node(client, command, result);
  if (command->format != MPV_FORMAT_NODE_ARRAY || command->u.list->num != 5)
    return MPV_ERROR_INVALID_PARAMETER;
  const auto& options = command->u.list->values[4];
  if (options.format != MPV_FORMAT_NODE_MAP) return MPV_ERROR_INVALID_PARAMETER;
  std::vector<mpv_node> values;
  std::vector<char*> keys;
  for (int i = 0; i < options.u.list->num; ++i) {
    if (std::strcmp(options.u.list->keys[i], "start") == 0) {
      ignored_start = true;
      continue;
    }
    values.push_back(options.u.list->values[i]);
    keys.push_back(options.u.list->keys[i]);
  }
  mpv_node_list option_list{static_cast<int>(values.size()), values.data(), keys.data()};
  mpv_node arguments[5];
  for (int i = 0; i < 5; ++i) arguments[i] = command->u.list->values[i];
  arguments[4].u.list = &option_list;
  mpv_node_list argument_list{5, arguments, nullptr};
  mpv_node altered{};
  altered.format = MPV_FORMAT_NODE_ARRAY;
  altered.u.list = &argument_list;
  return mpv_command_node(client, &altered, result);
}

mpv_event* WaitTestEvent(mpv_handle* client, double timeout) {
  auto* event = mpv_wait_event(client, timeout);
  if (!observation || !event) return event;
  if (event->event_id == MPV_EVENT_START_FILE) {
    ++observation->files_started;
    observation->loaded = false;
  }
  if (event->event_id == MPV_EVENT_FILE_LOADED && observation->files_started == 1)
    observation->loaded = true;
  if (event->event_id == MPV_EVENT_END_FILE) observation->loaded = false;
  if (event->event_id == MPV_EVENT_PLAYBACK_RESTART && observation->loaded &&
      !delay_exercised && (mode == "control-delayed-start" || mode == "control-ignore-start-delayed")) {
    delay_exercised = true;
    std::this_thread::sleep_for(std::chrono::seconds(3));
  }
  if (event->event_id == MPV_EVENT_PLAYBACK_RESTART ||
      event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
    const auto* property = event->event_id == MPV_EVENT_PROPERTY_CHANGE
        ? static_cast<mpv_event_property*>(event->data) : nullptr;
    if (event->event_id == MPV_EVENT_PLAYBACK_RESTART ||
        (property && std::strcmp(property->name, "time-pos") == 0)) {
      double seconds = 0;
      int seeking = 1;
      int paused = 0;
      if (mpv_get_property(client, "seeking", MPV_FORMAT_FLAG, &seeking) >= 0 &&
          mpv_get_property(client, "pause", MPV_FORMAT_FLAG, &paused) >= 0 &&
          mpv_get_property(client, "time-pos", MPV_FORMAT_DOUBLE, &seconds) >= 0) {
        if (event->event_id == MPV_EVENT_PLAYBACK_RESTART)
          observation->Restart(seconds, seeking != 0, paused != 0);
        else
          observation->Position(seconds, seeking != 0, paused != 0);
      }
    }
  }
  return event;
}

int SetTestOption(mpv_handle* client, const char* name, const char* value) {
  if (mode == name) return MPV_ERROR_OPTION_NOT_FOUND;
  // Deliberate violations are confined to explicitly selected negative controls.
  if (mode == "control-allow-references" &&
      (std::strcmp(name, "access-references") == 0 ||
       std::strcmp(name, "autoload-files") == 0)) value = "yes";
  if (mode == "control-disable-tls" && std::strcmp(name, "tls-verify") == 0)
    value = "no";
  return mpv_set_option_string(client, name, value);
}

mpv_handle* CreateTestClient() {
  auto* client = mpv_create();
  if (client && mpv_set_option_string(client, "tls-ca-file", test_ca) < 0) {
    mpv_terminate_destroy(client);
    return nullptr;
  }
  observed_client = client;
  return client;
}

int InitializeTestClient(mpv_handle* client) {
  for (const auto* name : {"vo", "ao"}) {
    const int status = mpv_set_option_string(client, name, "null");
    if (status < 0) return status;
  }
  return mpv_initialize(client);
}

bool RuntimeBound() {
  namespace fs = std::filesystem;
  const fs::path runtime = fs::canonical(LINEUP_REFERENCE_RUNTIME);
  const fs::path flutter = fs::canonical(LINEUP_REFERENCE_FLUTTER);
  bool found = false;
  for (uint32_t i = 1; i < _dyld_image_count(); ++i) {
    const std::string image = _dyld_get_image_name(i);
    if (image.rfind("/System/Library/", 0) == 0 || image.rfind("/usr/lib/", 0) == 0)
      continue;
    const auto path = fs::canonical(image);
    if (path.parent_path() == runtime) {
      if (path.filename() == "libmpv.2.dylib") found = true;
    } else if (path.string().rfind(flutter.string() + "/", 0) != 0) {
      return false;
    }
  }
  return found;
}
}  // namespace

@interface LineupNativePlayer (ReferenceTestOperations)
- (lineup::player::MpvOperations)mpvOperations;
@end

@interface ReferenceTestPlayer : LineupNativePlayer
@end
@implementation ReferenceTestPlayer
- (lineup::player::MpvOperations)mpvOperations {
  auto operations = lineup::player::LibmpvOperations();
  operations.create = CreateTestClient;
  operations.initialize = InitializeTestClient;
  operations.set_option_string = SetTestOption;
  operations.wait_event = WaitTestEvent;
  operations.command_node = CommandTestNode;
  return operations;
}
@end

@interface ReferenceWindow : NSObject
@end
@implementation ReferenceWindow
// The adapter publishes the observed fullscreen state during initialization.
// This headless window double always represents a windowed host.
- (NSWindowStyleMask)styleMask { return NSWindowStyleMaskBorderless; }
- (BOOL)isMiniaturized { return NO; }
- (NSWindowOcclusionState)occlusionState { return NSWindowOcclusionStateVisible; }
@end

@interface ReferenceMessenger : NSObject <FlutterBinaryMessenger>
@property(nonatomic, copy) FlutterBinaryMessageHandler handler;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL rejected;
@property(nonatomic) BOOL progressed;
@property(nonatomic) PlaybackObservation* playbackObservation;
- (BOOL)call:(NSString*)method arguments:(id)arguments;
- (void)sendEvent:(NSDictionary*)event;
@end

@implementation ReferenceMessenger
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message {
  FlutterMethodCall* call = [FlutterStandardMethodCodec.sharedInstance decodeMethodCall:message];
  if (![call.method isEqualToString:@"event"] ||
      ![call.arguments isKindOfClass:NSDictionary.class]) return;
  NSDictionary* event = call.arguments;
  NSString* state = event[@"state"];
  if ([state isEqual:@"ended"] || [state isEqual:@"stopped"] || [state isEqual:@"error"])
    self.finished = YES;
  // A later ended/stopped event must never erase an earlier error.
  if ([state isEqual:@"error"]) self.rejected = YES;
  if ([event[@"name"] isEqual:@"time-pos"] &&
      [event[@"value"] isKindOfClass:NSNumber.class] &&
      std::isfinite([event[@"value"] doubleValue]) &&
      self.playbackObservation && self.playbackObservation->advanced.load()) self.progressed = YES;
}
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message
         binaryReply:(FlutterBinaryReply)callback {
  [self sendOnChannel:channel message:message];
}
- (FlutterBinaryMessengerConnection)
    setMessageHandlerOnChannel:(NSString*)channel
          binaryMessageHandler:(FlutterBinaryMessageHandler)handler {
  self.handler = handler;
  return 1;
}
- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection { self.handler = nil; }
- (BOOL)call:(NSString*)method arguments:(id)arguments {
  __block BOOL replied = NO;
  __block BOOL success = NO;
  NSData* message = [FlutterStandardMethodCodec.sharedInstance
      encodeMethodCall:[FlutterMethodCall methodCallWithMethodName:method arguments:arguments]];
  self.handler(message, ^(NSData* reply) {
    replied = YES;
    id result = [FlutterStandardMethodCodec.sharedInstance decodeEnvelope:reply];
    success = ![result isKindOfClass:FlutterError.class];
  });
  return replied && success;
}
- (void)sendEvent:(NSDictionary*)event {
  [self sendOnChannel:@"lineup/native_player" message:[FlutterStandardMethodCodec.sharedInstance
      encodeMethodCall:[FlutterMethodCall methodCallWithMethodName:@"event" arguments:event]]];
}
@end

namespace {
bool TerminalStateContractHolds() {
  for (NSString* terminal in @[ @"ended", @"stopped" ]) {
    ReferenceMessenger* clean = [ReferenceMessenger new];
    [clean sendEvent:@{@"state": terminal}];
    if (!clean.finished || clean.rejected || clean.progressed) return false;
    ReferenceMessenger* progressed = [ReferenceMessenger new];
    PlaybackObservation baseline;
    baseline.files_started = 1;
    baseline.loaded = true;
    baseline.Restart(0, false, true);
    baseline.released.store(true);
    baseline.Position(1, false, false);
    progressed.playbackObservation = &baseline;
    [progressed sendEvent:@{@"name": @"time-pos", @"value": @1.0}];
    if (progressed.finished || progressed.rejected || !progressed.progressed) return false;
    [progressed sendEvent:@{@"state": terminal}];
    if (!progressed.finished || progressed.rejected || !progressed.progressed) return false;
    [progressed sendEvent:@{@"state": @"error"}];
    [progressed sendEvent:@{@"state": terminal}];
    if (!progressed.finished || !progressed.rejected || !progressed.progressed) return false;
    ReferenceMessenger* rejected = [ReferenceMessenger new];
    [rejected sendEvent:@{@"state": @"error"}];
    [rejected sendEvent:@{@"state": terminal}];
    if (!rejected.finished || !rejected.rejected || rejected.progressed) return false;
  }
  PlaybackObservation alternate(true);
  ReferenceMessenger* messenger = [ReferenceMessenger new];
  messenger.playbackObservation = &alternate;
  alternate.Restart(3.0, false, true);  // Pre-FILE_LOADED restart cannot seed progress.
  if (alternate.landing.load() >= 0) return false;
  alternate.files_started = 1;
  alternate.loaded = true;
  alternate.Restart(3.0, true, true);
  if (alternate.landing.load() >= 0) return false;
  alternate.Restart(3.0, false, true);
  for (double seconds : {3.0, 3.0, 2.9}) {
    alternate.Position(seconds, false, true);
    [messenger sendEvent:@{@"name": @"time-pos", @"value": @(seconds)}];
    if (messenger.progressed) return false;
  }
  alternate.Position(3.5, true, true);
  if (alternate.advanced.load()) return false;
  alternate.Position(3.25, false, true);
  if (alternate.advanced.load()) return false;
  alternate.released.store(true);
  alternate.Position(3.25, false, false);
  [messenger sendEvent:@{@"name": @"time-pos", @"value": @3.25}];
  for (double wrong : {0.0, 3.5}) {
    PlaybackObservation ignored(true);
    ignored.files_started = 1;
    ignored.loaded = true;
    ignored.Restart(wrong, false, true);
    ignored.released.store(true);
    ignored.Position(4.0, false, false);
    if (ignored.advanced.load()) return false;
  }
  PlaybackObservation moving(true);
  moving.loaded = true;
  moving.Restart(3.0, false, false);
  moving.released.store(true);
  moving.Position(3.3, false, false);
  if (moving.landing.load() >= 0 || moving.advanced.load()) return false;
  return messenger.progressed;
}

void PrintAvailableFormats() {
  mpv_node formats{};
  if (mpv_get_property(observed_client, "demuxer-lavf-list", MPV_FORMAT_NODE, &formats) < 0 ||
      formats.format != MPV_FORMAT_NODE_ARRAY) throw std::runtime_error("format inventory");
  for (const char* name : {"mov", "matroska", "hls", "dash", "concat", "imf", "sdp", "vobsub"}) {
    bool available = false;
    for (int i = 0; i < formats.u.list->num; ++i) {
      const auto& value = formats.u.list->values[i];
      if (value.format != MPV_FORMAT_STRING) continue;
      // FFmpeg exposes aliases as comma-separated names (mov,mp4,...).
      const std::string aliases = std::string(",") + value.u.string + ",";
      if (aliases.find(std::string(",") + name + ",") != std::string::npos) available = true;
    }
    std::cout << "lavf_" << name << "=" << available << " ";
  }
  mpv_free_node_contents(&formats);
}
}  // namespace

int main(int argc, char** argv) {
  if (argc < 3 || argc > 5) return 2;
  @autoreleasepool {
    try {
      test_ca = argv[1];
      bool nonzero_start = false;
      for (int i = 3; i < argc; ++i) {
        if (std::strcmp(argv[i], "--nonzero-start") == 0) {
          if (nonzero_start) return 2;
          nonzero_start = true;
        } else {
          if (!mode.empty()) return 2;
          mode = argv[i];
        }
      }
      if (!mode.empty() && mode != "observe" && mode != "access-references" &&
          mode != "autoload-files" && mode != "control-allow-references" &&
          mode != "control-disable-tls" && mode != "control-late-error" &&
          mode != "control-delayed-start" && mode != "control-ignore-start-delayed") return 2;
      if (!nonzero_start && (mode == "control-delayed-start" || mode == "control-ignore-start-delayed")) return 2;
      NSURL* uri = [NSURL URLWithString:@(argv[2])];
      if (![uri.scheme isEqual:@"https"] || ![uri.host isEqual:@"127.0.0.1"] ||
          uri.user || uri.password || uri.query || uri.fragment) return 2;
      if (!RuntimeBound() || !TerminalStateContractHolds()) return 2;
      PlaybackObservation playback(nonzero_start);
      observation = &playback;
      ReferenceMessenger* messenger = [ReferenceMessenger new];
      messenger.playbackObservation = &playback;
      ReferenceWindow* window = [ReferenceWindow new];
      NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64)];
      ReferenceTestPlayer* player = [[ReferenceTestPlayer alloc]
          initWithMessenger:messenger videoHost:host window:(NSWindow*)window];
      const bool initialized = [messenger call:@"initialize" arguments:nil];
      bool timed_out = false;
      if (initialized) {
        PrintAvailableFormats();
        NSMutableDictionary* load = [@{
            @"uri": @(argv[2]), @"loadId": @1,
            @"plexToken": @"lineup-synthetic-reference-test", @"startPaused": @YES} mutableCopy];
        if (nonzero_start) load[@"startSeconds"] = @3.5;
        if ([messenger call:@"load" arguments:load]) {
          const auto deadline = [NSDate dateWithTimeIntervalSinceNow:mode == "observe" ? 2 : 12];
          while (!messenger.finished && deadline.timeIntervalSinceNow > 0) {
            // Test-only stationary measurement, followed by actual playback.
            if (playback.sampled.load() && playback.initial_paused.load() && !playback.released.load()) {
              if (![messenger call:@"play" arguments:nil]) { messenger.rejected = YES; break; }
              playback.released.store(true);
            }
            @autoreleasepool {
              [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            }
          }
          timed_out = !messenger.finished && mode != "observe";
        } else {
          messenger.rejected = YES;
        }
      } else {
        messenger.rejected = YES;
      }
      // Exercise the positive classifier with a real successful media run,
      // followed by a later error delivered through the same event codec.
      if (mode == "control-late-error") [messenger sendEvent:@{@"state": @"error"}];
      __block BOOL disposed = NO;
      [player beginShutdownWithCompletion:^{ disposed = YES; }];
      NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:6];
      while (!disposed && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
      }
      if (!disposed || !RuntimeBound()) return 2;
      observation = nullptr;
      std::cout << "runtime_bound=1 messenger_contract=1 initialized=" << initialized
                << " start_configured=" << nonzero_start
                << " initial_paused=" << playback.initial_paused.load()
                << " play_released=" << playback.released.load()
                << " delay_exercised=" << delay_exercised
                << " ignored_start=" << ignored_start
                << " landing_confirmed=" << (playback.landing.load() >= 0)
                << " progressed=" << static_cast<bool>(messenger.progressed)
                << " rejected=" << static_cast<bool>(messenger.rejected)
                << " timed_out=" << timed_out << '\n';
      if (mode == "access-references" || mode == "autoload-files") return initialized ? 1 : 0;
      return initialized && !timed_out ? 0 : 1;
    } catch (...) {
      // Never emit an exception, URI, header, or raw mpv diagnostic here.
      std::cout << "harness_prerequisite=failed\n";
      return 2;
    }
  }
}
