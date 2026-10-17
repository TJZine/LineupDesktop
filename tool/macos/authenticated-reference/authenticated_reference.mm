#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

#include <mach-o/dyld.h>
#include <limits.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>

#import "LineupNativePlayer.h"
#include "player_core/mpv_operations.h"

namespace {
const char* test_ca = nullptr;
std::string mode;
mpv_handle* observed_client = nullptr;

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
  return operations;
}
@end

@interface ReferenceWindow : NSObject
@end
@implementation ReferenceWindow
- (BOOL)isMiniaturized { return NO; }
- (NSWindowOcclusionState)occlusionState { return NSWindowOcclusionStateVisible; }
@end

@interface ReferenceMessenger : NSObject <FlutterBinaryMessenger>
@property(nonatomic, copy) FlutterBinaryMessageHandler handler;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL rejected;
@property(nonatomic) BOOL progressed;
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
      [event[@"value"] doubleValue] > 0.1) self.progressed = YES;
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
  return true;
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
  if (argc < 3 || argc > 4) return 2;
  @autoreleasepool {
    try {
      test_ca = argv[1];
      if (argc == 4) mode = argv[3];
      if (!mode.empty() && mode != "observe" && mode != "access-references" &&
          mode != "autoload-files" && mode != "control-allow-references" &&
          mode != "control-disable-tls" && mode != "control-late-error") return 2;
      NSURL* uri = [NSURL URLWithString:@(argv[2])];
      if (![uri.scheme isEqual:@"https"] || ![uri.host isEqual:@"127.0.0.1"] ||
          uri.user || uri.password || uri.query || uri.fragment) return 2;
      if (!RuntimeBound() || !TerminalStateContractHolds()) return 2;
      ReferenceMessenger* messenger = [ReferenceMessenger new];
      ReferenceWindow* window = [ReferenceWindow new];
      NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64)];
      ReferenceTestPlayer* player = [[ReferenceTestPlayer alloc]
          initWithMessenger:messenger videoHost:host window:(NSWindow*)window];
      const bool initialized = [messenger call:@"initialize" arguments:nil];
      bool timed_out = false;
      if (initialized) {
        PrintAvailableFormats();
        if ([messenger call:@"load" arguments:@{
              @"uri": @(argv[2]), @"loadId": @1,
              @"plexToken": @"lineup-synthetic-reference-test"}]) {
          const auto deadline = [NSDate dateWithTimeIntervalSinceNow:mode == "observe" ? 2 : 12];
          while (!messenger.finished && deadline.timeIntervalSinceNow > 0) {
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
      std::cout << "runtime_bound=1 messenger_contract=1 initialized=" << initialized
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
