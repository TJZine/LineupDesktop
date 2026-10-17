#import "LineupNativePlayer.h"

#import <QuartzCore/QuartzCore.h>

#include <cstdint>
#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "FoundationValueConversion.h"
#include "VideoGeometry.h"
#include "player_core/player_core.h"

namespace {

using lineup::player::CallError;
using lineup::player::CallResult;
using lineup::player::OutputConfig;
using lineup::player::PlayerCore;
using lineup::player::Value;
using lineup::player::ValueMap;

NSString* const kChannelName = @"lineup/native_player";
// A native fullscreen animation takes well under a second; a transition that
// has not completed by then is reported as a window error.
constexpr int64_t kFullscreenTimeoutSeconds = 5;

void SendResult(FlutterResult result, const CallResult& outcome) {
  if (outcome.error) {
    result([FlutterError
        errorWithCode:[NSString stringWithUTF8String:outcome.error->code.c_str()]
                          ?: @"native_command_error"
              message:[NSString
                          stringWithUTF8String:outcome.error->message.c_str()]
              details:nil]);
  } else if (std::holds_alternative<std::monostate>(outcome.value)) {
    result(nil);
  } else {
    result(lineup::ToFoundation(outcome.value));
  }
}

FlutterError* ArgumentError(NSString* message) {
  return [FlutterError errorWithCode:@"invalid_argument"
                             message:message
                             details:nil];
}

FlutterError* WindowError(NSString* message) {
  return [FlutterError errorWithCode:@"window_error"
                             message:message
                             details:nil];
}

struct FullscreenRequest {
  uint64_t id;
  bool fullscreen;
  FlutterResult result;
};

}  // namespace

@interface LineupNativePlayer ()
- (std::optional<CallError>)prepareOutput:(OutputConfig&)output;
- (void)removeOutput;
- (void)processWakeup;
@end

namespace {

// Bridges the core's host interface to the adapter. Platform-thread calls go
// straight to the adapter, which owns the core and therefore outlives every
// such call. Wakeups from the worker hop to the main queue through a weak
// reference, so a wakeup that arrives after the adapter is gone is dropped.
class MacCoreHost final : public lineup::player::CoreHost {
 public:
  explicit MacCoreHost(LineupNativePlayer* adapter)
      : adapter_(adapter), weak_adapter_(adapter) {}

  bool PostWakeup() override {
    ScheduleWakeup();
    return true;
  }

  // dispatch_async never blocks and always posts, so the main queue will
  // call ProcessWakeup unless the adapter has been destroyed, in which case
  // Shutdown() has already completed the disposal synchronously.
  void PostWorkerFinished() override { ScheduleWakeup(); }

  std::optional<CallError> PrepareOutput(OutputConfig& output) override {
    return [adapter_ prepareOutput:output];
  }

  void CancelOutput() override { [adapter_ removeOutput]; }

  void ReleaseOutput() override { [adapter_ removeOutput]; }

 private:
  void ScheduleWakeup() {
    __weak LineupNativePlayer* adapter = weak_adapter_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [adapter processWakeup];
    });
  }

  __unsafe_unretained LineupNativePlayer* adapter_;
  __weak LineupNativePlayer* weak_adapter_;
};

}  // namespace

// The passive view whose CAMetalLayer libmpv renders into. It never takes
// hit-testing, focus, or an accessibility role (protocol obligation 4). The
// host sets its frame; the view keeps the layer's contentsScale and
// drawableSize in step, and the patched mpv context resizes its swapchain
// from drawableSize on the next frame.
@interface LineupVideoView : NSView
@property(nonatomic, readonly) CAMetalLayer* metalLayer;
- (void)updateDrawableSize;
@end

@implementation LineupVideoView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self) {
    self.wantsLayer = YES;
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
  }
  return self;
}

- (CALayer*)makeBackingLayer {
  CAMetalLayer* layer = [CAMetalLayer layer];
  layer.framebufferOnly = YES;
  layer.backgroundColor = NSColor.blackColor.CGColor;
  return layer;
}

- (CAMetalLayer*)metalLayer {
  return (CAMetalLayer*)self.layer;
}

- (BOOL)isFlipped {
  return YES;
}

- (NSView*)hitTest:(NSPoint)point {
  return nil;
}

- (BOOL)acceptsFirstResponder {
  return NO;
}

- (BOOL)isAccessibilityElement {
  return NO;
}

- (NSArray*)accessibilityChildren {
  return @[];
}

- (void)setFrameSize:(NSSize)newSize {
  [super setFrameSize:newSize];
  [self updateDrawableSize];
}

- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  [self updateDrawableSize];
}

- (void)updateDrawableSize {
  NSWindow* window = self.window;
  const CGFloat scale = window ? window.backingScaleFactor
                               : NSScreen.mainScreen.backingScaleFactor;
  CAMetalLayer* layer = self.metalLayer;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  layer.contentsScale = scale;
  layer.drawableSize = lineup::DrawableSize(self.bounds.size, scale);
  [CATransaction commit];
}

@end

@implementation LineupNativePlayer {
  FlutterMethodChannel* _channel;
  __weak NSView* _videoHost;
  __weak NSWindow* _window;
  std::unique_ptr<MacCoreHost> _host;
  std::unique_ptr<PlayerCore> _core;
  LineupVideoView* _videoView;
  std::optional<lineup::VideoRect> _videoRect;
  int64_t _displayRevision;
  std::vector<FullscreenRequest> _fullscreenRequests;
  uint64_t _nextFullscreenRequest;
  BOOL _fullscreenTransitioning;
  NSMutableArray<id>* _observers;
  NSTimer* _presentationLogTimer;
  NSString* _lastPresentationFacts;
}

- (instancetype)initWithMessenger:(id<FlutterBinaryMessenger>)messenger
                        videoHost:(NSView*)videoHost
                           window:(NSWindow*)window {
  self = [super init];
  if (self) {
    _videoHost = videoHost;
    _window = window;
    _displayRevision = -1;
    _host = std::make_unique<MacCoreHost>(self);
    _core = std::make_unique<PlayerCore>(lineup::player::LibmpvOperations(),
                                         *_host);
    _channel = [FlutterMethodChannel methodChannelWithName:kChannelName
                                           binaryMessenger:messenger];
    __weak LineupNativePlayer* weakSelf = self;
    [_channel setMethodCallHandler:^(FlutterMethodCall* call,
                                     FlutterResult result) {
      LineupNativePlayer* strongSelf = weakSelf;
      if (strongSelf) {
        [strongSelf handleMethodCall:call result:result];
      } else {
        result(FlutterMethodNotImplemented);
      }
    }];
    [self observeWindow:window];
  }
  return self;
}

- (void)dealloc {
  for (id observer in _observers) {
    [NSNotificationCenter.defaultCenter removeObserver:observer];
  }
  [_channel setMethodCallHandler:nil];
  [self shutdown];
}

- (void)shutdown {
  [self failFullscreenRequests:@"The player window closed."];
  // Joins the worker after mpv_terminate_destroy, then releases the output.
  // A pending dispose result is dropped without a reply.
  _core->Shutdown();
}

#pragma mark - Method channel

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* method = call.method;
  if ([method isEqualToString:@"initialize"]) {
    _displayRevision = -1;
    _core->DiscardQueuedEvents("display");
    SendResult(result, _core->Initialize());
    return;
  }
  if ([method isEqualToString:@"dispose"]) {
    _core->Dispose([result](const CallResult& outcome) {
      SendResult(result, outcome);
    });
    return;
  }

  auto arguments = lineup::ToValueMap(call.arguments);
  ValueMap* argumentMap = arguments ? &*arguments : nullptr;
  const std::string name = method.UTF8String ?: "";
  if (const auto outcome = _core->HandleCommand(name, argumentMap)) {
    SendResult(result, *outcome);
    return;
  }

  // The core has checked initialization and does not own this method.
  if ([method isEqualToString:@"setDisplayMatching"]) {
    [self setDisplayMatching:argumentMap result:result];
  } else if ([method isEqualToString:@"setVideoRect"]) {
    const auto rect = argumentMap ? lineup::ParseVideoRect(*argumentMap)
                                  : std::nullopt;
    if (!rect) {
      result(ArgumentError(@"Valid finite video bounds are required."));
      return;
    }
    _videoRect = rect;
    [self applyVideoPresentation];
    result(nil);
  } else if ([method isEqualToString:@"setFullscreen"]) {
    const bool* fullscreen =
        lineup::player::FindBool(argumentMap, "fullscreen");
    if (!fullscreen) {
      result(ArgumentError(@"Fullscreen must be a boolean."));
      return;
    }
    [self setFullscreen:*fullscreen result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)processWakeup {
  _core->ProcessWakeup([self](const ValueMap& event) {
    [_channel invokeMethod:@"event" arguments:lineup::ToFoundationMap(event)];
  });
}

#pragma mark - Display matching

// macOS has no public API to switch a display's HDR mode; HDR output is a
// property of the video layer (EDR) instead. Requests are validated as the
// protocol requires and always answered with an unavailable report for the
// request's revision.
- (void)setDisplayMatching:(const ValueMap*)arguments
                    result:(FlutterResult)result {
  using lineup::player::AsInt;
  using lineup::player::Find;
  const auto revision =
      arguments ? AsInt(Find(*arguments, "revision")) : std::nullopt;
  const bool* session = lineup::player::FindBool(arguments, "session");
  const std::string* desired =
      lineup::player::FindString(arguments, "desired");
  if (!revision || *revision < 0 || !session || !desired ||
      (*desired != "hdr" && *desired != "sdr" && *desired != "unknown")) {
    result(ArgumentError(@"A valid display matching request is required."));
    return;
  }
  if (*revision <= _displayRevision) {
    result(ArgumentError(@"Display revision must strictly increase."));
    return;
  }
  _displayRevision = *revision;
  _core->QueuePlatformEvent({
      {"type", Value("display")},
      {"revision", Value(*revision)},
      {"session", Value("unavailable")},
      {"observed", Value("unknown")},
      {"outcome", Value("failed")},
      {"wrote", Value(false)},
      {"owned", Value(false)},
      {"reason", Value("unsupported_api")},
      {"route", Value("none")},
      {"activeColorMode", Value()},
  });
  result(nil);
}

#pragma mark - Presentation

- (std::optional<CallError>)prepareOutput:(OutputConfig&)output {
  NSView* host = _videoHost;
  if (!host) {
    return CallError{"initialize_failed",
                     "The video presentation view is unavailable."};
  }
  // MoltenVK writes informational messages to stderr unless told otherwise;
  // keep errors only. An explicit developer setting wins.
  setenv("MVK_CONFIG_LOG_LEVEL", "1", 0);

  _videoView = [[LineupVideoView alloc] initWithFrame:NSZeroRect];
  _videoView.hidden = YES;
  [host addSubview:_videoView positioned:NSWindowBelow relativeTo:nil];
  [_videoView updateDrawableSize];
  [self applyVideoPresentation];
  [self startPresentationLog];

  output.window_id = static_cast<int64_t>(
      reinterpret_cast<intptr_t>((__bridge void*)_videoView.metalLayer));
  output.options = {
      {"vo", "gpu-next"},
      {"gpu-api", "vulkan"},
      {"gpu-context", "macvk"},
      // Lets libplacebo pick the HDR10/PQ swapchain for HDR content; MoltenVK
      // then sets the layer's color space, EDR, and HDR metadata.
      {"target-colorspace-hint", "yes"},
  };
  return std::nullopt;
}

// The core calls this only after libmpv has been terminated (or was never
// created), so the swapchain no longer references the layer.
- (void)removeOutput {
  [_presentationLogTimer invalidate];
  _presentationLogTimer = nil;
  _lastPresentationFacts = nil;
  [_videoView removeFromSuperview];
  _videoView = nil;
  _videoRect.reset();
}

- (void)applyVideoPresentation {
  if (!_videoView) {
    return;
  }
  NSWindow* window = _window;
  const bool minimized = window == nil || window.isMiniaturized;
  const bool occluded =
      window == nil ||
      (window.occlusionState & NSWindowOcclusionStateVisible) == 0;
  const bool visible = lineup::VideoVisible(_videoRect, minimized, occluded);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (visible) {
    _videoView.frame = lineup::VideoFrame(*_videoRect);
  }
  // A hidden layer also stops the patched mpv context from rendering.
  _videoView.hidden = !visible;
  [CATransaction commit];
}

#pragma mark - Fullscreen

- (BOOL)windowIsFullscreen {
  return (_window.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

// Completes only after AppKit reports the transition (protocol obligation 5).
- (void)setFullscreen:(bool)fullscreen result:(FlutterResult)result {
  if (!_window) {
    result(WindowError(@"The player window is unavailable."));
    return;
  }
  if (!_fullscreenTransitioning && _fullscreenRequests.empty() &&
      static_cast<bool>([self windowIsFullscreen]) == fullscreen) {
    result(nil);
    return;
  }
  const uint64_t requestId = ++_nextFullscreenRequest;
  _fullscreenRequests.push_back({requestId, fullscreen, result});
  __weak LineupNativePlayer* weakSelf = self;
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, kFullscreenTimeoutSeconds * NSEC_PER_SEC),
      dispatch_get_main_queue(), ^{
        [weakSelf fullscreenRequestTimedOut:requestId];
      });
  [self advanceFullscreen];
}

// Settles requests that the window's current state satisfies, then starts
// one transition toward any request that remains.
- (void)advanceFullscreen {
  if (_fullscreenTransitioning) {
    return;
  }
  const bool current = [self windowIsFullscreen];
  std::vector<FlutterResult> settled;
  std::vector<FullscreenRequest> remaining;
  for (auto& request : _fullscreenRequests) {
    if (request.fullscreen == current) {
      settled.push_back(request.result);
    } else {
      remaining.push_back(std::move(request));
    }
  }
  _fullscreenRequests = std::move(remaining);
  if (!_fullscreenRequests.empty()) {
    _fullscreenTransitioning = YES;
    [_window toggleFullScreen:nil];
  }
  for (FlutterResult result : settled) {
    result(nil);
  }
}

- (void)fullscreenTransitionCompleted {
  _fullscreenTransitioning = NO;
  [self advanceFullscreen];
}

- (void)fullscreenRequestTimedOut:(uint64_t)requestId {
  for (auto it = _fullscreenRequests.begin(); it != _fullscreenRequests.end();
       ++it) {
    if (it->id == requestId) {
      FlutterResult result = it->result;
      _fullscreenRequests.erase(it);
      if (_fullscreenRequests.empty()) {
        // AppKit never reported the transition (for example, the window is
        // minimized); allow a later request to try again.
        _fullscreenTransitioning = NO;
      }
      result(WindowError(@"The fullscreen transition did not complete."));
      return;
    }
  }
}

- (void)failFullscreenRequests:(NSString*)message {
  auto requests = std::move(_fullscreenRequests);
  _fullscreenRequests.clear();
  for (auto& request : requests) {
    request.result(WindowError(message));
  }
}

#pragma mark - Window observation

- (void)observeWindow:(NSWindow*)window {
  _observers = [NSMutableArray array];
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  __weak LineupNativePlayer* weakSelf = self;
  const auto observe = ^(NSNotificationName name, id object,
                         void (^handler)(LineupNativePlayer*)) {
    [self->_observers
        addObject:[center addObserverForName:name
                                      object:object
                                       queue:NSOperationQueue.mainQueue
                                  usingBlock:^(NSNotification*) {
                                    LineupNativePlayer* strongSelf = weakSelf;
                                    if (strongSelf) handler(strongSelf);
                                  }]];
  };

  for (NSNotificationName name in @[
         NSWindowWillEnterFullScreenNotification,
         NSWindowWillExitFullScreenNotification
       ]) {
    observe(name, window, ^(LineupNativePlayer* player) {
      player->_fullscreenTransitioning = YES;
    });
  }
  for (NSNotificationName name in @[
         NSWindowDidEnterFullScreenNotification,
         NSWindowDidExitFullScreenNotification
       ]) {
    observe(name, window, ^(LineupNativePlayer* player) {
      [player fullscreenTransitionCompleted];
    });
  }
  for (NSNotificationName name in @[
         NSWindowDidMiniaturizeNotification,
         NSWindowDidDeminiaturizeNotification,
         NSWindowDidChangeOcclusionStateNotification
       ]) {
    observe(name, window, ^(LineupNativePlayer* player) {
      [player applyVideoPresentation];
    });
  }
  // Closing the window or quitting stops libmpv before AppKit tears down the
  // views and the process exits.
  observe(NSWindowWillCloseNotification, window,
          ^(LineupNativePlayer* player) {
            [player shutdown];
          });
  observe(NSApplicationWillTerminateNotification, nil,
          ^(LineupNativePlayer* player) {
            [player shutdown];
          });
}

#pragma mark - Presentation diagnostics

// Opt-in developer diagnostics: with LINEUP_PRESENTATION_LOG set, logs the
// video layer's HDR presentation facts whenever they change. Contains no
// media identity.
- (void)startPresentationLog {
  if (getenv("LINEUP_PRESENTATION_LOG") == nullptr) {
    return;
  }
  __weak LineupNativePlayer* weakSelf = self;
  _presentationLogTimer =
      [NSTimer scheduledTimerWithTimeInterval:1.0
                                      repeats:YES
                                        block:^(NSTimer*) {
                                          [weakSelf logPresentationFacts];
                                        }];
}

- (void)logPresentationFacts {
  CAMetalLayer* layer = _videoView.metalLayer;
  if (!layer) {
    return;
  }
  NSScreen* screen = _window.screen;
  CGColorSpaceRef colorspace = layer.colorspace;
  NSString* colorspaceName =
      colorspace ? (__bridge NSString*)CGColorSpaceGetName(colorspace) : nil;
  NSString* facts = [NSString
      stringWithFormat:
          @"colorspace=%@ edr=%d edrMetadata=%d pixelFormat=%lu "
          @"drawable=%.0fx%.0f scale=%.1f hidden=%d headroom=%.2f "
          @"potentialHeadroom=%.2f",
          colorspaceName ?: @"none", layer.wantsExtendedDynamicRangeContent,
          layer.EDRMetadata != nil, (unsigned long)layer.pixelFormat,
          layer.drawableSize.width, layer.drawableSize.height,
          layer.contentsScale, layer.hidden,
          screen.maximumExtendedDynamicRangeColorComponentValue,
          screen.maximumPotentialExtendedDynamicRangeColorComponentValue];
  if (![facts isEqualToString:_lastPresentationFacts]) {
    _lastPresentationFacts = facts;
    NSLog(@"[lineup-presentation] %@", facts);
  }
}

@end
