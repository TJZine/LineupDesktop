#import <XCTest/XCTest.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#import "LineupNativePlayer.h"
#import "LineupPlayerLifecycle.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <memory>
#include <future>
#include <string>
#include <vector>
#include <mutex>
#include <thread>

#include "player_core/mpv_operations.h"

namespace {
struct ControlledWorker {
  std::atomic<bool> terminating{false};
  std::atomic<bool> terminatedOnMain{false};
  std::mutex mutex;
  std::condition_variable condition;
  bool released = false;

  void Release() {
    std::lock_guard lock(mutex);
    released = true;
    condition.notify_all();
  }
};
std::shared_ptr<ControlledWorker> worker;

lineup::player::MpvOperations ControlledOperations() {
  lineup::player::MpvOperations operations;
  operations.create = [] { return reinterpret_cast<mpv_handle*>(worker.get()); };
  operations.initialize = [](mpv_handle*) { return 0; };
  operations.set_option = [](mpv_handle*, const char*, mpv_format, void*) { return 0; };
  operations.set_option_string = [](mpv_handle*, const char*, const char*) { return 0; };
  operations.request_log_messages = [](mpv_handle*, const char*) { return 0; };
  operations.observe_property = [](mpv_handle*, uint64_t, const char*, mpv_format) { return 0; };
  operations.client_api_version = [] { return static_cast<unsigned long>(MPV_CLIENT_API_VERSION); };
  operations.wait_event = [](mpv_handle*, double) -> mpv_event* {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
    static thread_local mpv_event event{};
    return &event;
  };
  operations.terminate_destroy = [](mpv_handle* handle) {
    auto* controlled = reinterpret_cast<ControlledWorker*>(handle);
    controlled->terminatedOnMain = NSThread.isMainThread;
    controlled->terminating = true;
    std::unique_lock lock(controlled->mutex);
    controlled->condition.wait(lock, [&] { return controlled->released; });
  };
  return operations;
}

// Observe framework calls at the real owned-layer boundary. Only the selected
// test thread substitutes these methods; unrelated AppKit calls still use the
// original implementations. This proves publication ordering, not GPU output.
struct LayerPublicationTrace {
  std::vector<std::string> calls;
  CGColorSpaceRef colorspace = nullptr;
  BOOL edr = NO;
  __unsafe_unretained CAEDRMetadata* metadata = nil;
  MTLPixelFormat format = MTLPixelFormatInvalid;
  CGSize size = CGSizeZero;
  __unsafe_unretained id drawable = nil;
};
thread_local LayerPublicationTrace* layerTrace = nullptr;
std::atomic<IMP> originalLayerCalls[7];
void TraceColorspace(id object, SEL selector, CGColorSpaceRef value) {
  if (layerTrace) { layerTrace->calls.push_back("colorspace"); layerTrace->colorspace = value; }
  else reinterpret_cast<void (*)(id, SEL, CGColorSpaceRef)>(originalLayerCalls[0].load())(object, selector, value);
}
void TraceEDR(id object, SEL selector, BOOL value) {
  if (layerTrace) { layerTrace->calls.push_back("edr"); layerTrace->edr = value; }
  else reinterpret_cast<void (*)(id, SEL, BOOL)>(originalLayerCalls[1].load())(object, selector, value);
}
void TraceMetadata(id object, SEL selector, CAEDRMetadata* value) {
  if (layerTrace) { layerTrace->calls.push_back("metadata"); layerTrace->metadata = value; }
  else reinterpret_cast<void (*)(id, SEL, CAEDRMetadata*)>(originalLayerCalls[2].load())(object, selector, value);
}
void TraceFormat(id object, SEL selector, MTLPixelFormat value) {
  if (layerTrace) { layerTrace->calls.push_back("format"); layerTrace->format = value; }
  else reinterpret_cast<void (*)(id, SEL, MTLPixelFormat)>(originalLayerCalls[3].load())(object, selector, value);
}
void TraceSize(id object, SEL selector, CGSize value) {
  if (layerTrace) { layerTrace->calls.push_back("size"); layerTrace->size = value; }
  else reinterpret_cast<void (*)(id, SEL, CGSize)>(originalLayerCalls[4].load())(object, selector, value);
}
void TraceFlush(id object, SEL selector) {
  if (layerTrace) layerTrace->calls.push_back("flush");
  else reinterpret_cast<void (*)(id, SEL)>(originalLayerCalls[5].load())(object, selector);
}
id TraceAcquisition(id object, SEL selector) {
  if (layerTrace) { layerTrace->calls.push_back("acquire"); return layerTrace->drawable; }
  return reinterpret_cast<id (*)(id, SEL)>(originalLayerCalls[6].load())(object, selector);
}
struct LayerPublicationHooks {
  Method methods[7];
  LayerPublicationHooks() {
    SEL selectors[] = {@selector(setColorspace:), @selector(setWantsExtendedDynamicRangeContent:),
        @selector(setEDRMetadata:), @selector(setPixelFormat:), @selector(setDrawableSize:),
        @selector(flush), @selector(nextDrawable)};
    IMP replacements[] = {reinterpret_cast<IMP>(TraceColorspace), reinterpret_cast<IMP>(TraceEDR),
        reinterpret_cast<IMP>(TraceMetadata), reinterpret_cast<IMP>(TraceFormat),
        reinterpret_cast<IMP>(TraceSize), reinterpret_cast<IMP>(TraceFlush),
        reinterpret_cast<IMP>(TraceAcquisition)};
    for (size_t i = 0; i < 7; ++i) {
      methods[i] = i == 5 ? class_getClassMethod(CATransaction.class, selectors[i])
                          : class_getInstanceMethod(CAMetalLayer.class, selectors[i]);
      originalLayerCalls[i].store(method_getImplementation(methods[i]));
      method_setImplementation(methods[i], replacements[i]);
    }
  }
  ~LayerPublicationHooks() {
    for (size_t i = 0; i < 7; ++i) method_setImplementation(methods[i], originalLayerCalls[i].load());
  }
};
struct ScopedLayerTrace {
  LayerPublicationTrace* previous;
  explicit ScopedLayerTrace(LayerPublicationTrace& trace) : previous(layerTrace) { layerTrace = &trace; }
  ~ScopedLayerTrace() { layerTrace = previous; }
};
}  // namespace

@interface LineupNativePlayer (LifecycleTests)
- (lineup::player::MpvOperations)mpvOperations;
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result;
- (void)processWakeup;
- (void)shutdownTimedOut;
- (void)completeShutdownIfReady;
- (void)fullscreenToggleStartTimedOut:(uint64_t)toggle;
- (void)fullscreenRequestTimedOut:(uint64_t)requestId;
- (void)terminateAfterShutdownTimeout;
@end

// The real adapter and core run throughout. Lifecycle cases control libmpv
// operations and terminal exit; layer cases also observe framework boundaries.
@interface ShutdownTestPlayer : LineupNativePlayer
@property(nonatomic) NSUInteger timeoutCount;
@property(nonatomic) NSUInteger emergencyShutdownCount;
@property(nonatomic) BOOL useRealTimeoutExit;
@property(nonatomic) BOOL deferRunnerCompletion;
@end
@implementation ShutdownTestPlayer
- (lineup::player::MpvOperations)mpvOperations { return ControlledOperations(); }
- (void)completeShutdownIfReady {
  if (!self.deferRunnerCompletion) [super completeShutdownIfReady];
}
- (void)terminateAfterShutdownTimeout {
  self.timeoutCount += 1;
  if (self.useRealTimeoutExit) [super terminateAfterShutdownTimeout];
}
- (void)shutdown {
  self.emergencyShutdownCount += 1;
  [super shutdown];
}
@end

@interface ShutdownTestMessenger : NSObject <FlutterBinaryMessenger>
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* fullscreenEvents;
@end
@implementation ShutdownTestMessenger
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message {
  if (!message) return;
  FlutterMethodCall* call = [FlutterStandardMethodCodec.sharedInstance decodeMethodCall:message];
  NSDictionary* event = [call.arguments isKindOfClass:NSDictionary.class] ? call.arguments : nil;
  if (event && [call.method isEqualToString:@"event"] &&
      [event[@"type"] isEqual:@"fullscreen"]) {
    if (!self.fullscreenEvents) self.fullscreenEvents = [NSMutableArray array];
    [self.fullscreenEvents addObject:event];
  }
}
- (void)sendOnChannel:(NSString*)channel
             message:(NSData*)message
         binaryReply:(FlutterBinaryReply)callback {}
- (FlutterBinaryMessengerConnection)
    setMessageHandlerOnChannel:(NSString*)channel
          binaryMessageHandler:(FlutterBinaryMessageHandler)handler { return 1; }
- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection {}
@end

@interface ShutdownTestWindow : NSObject
@property(nonatomic) NSWindowStyleMask styleMask;
@property(nonatomic) NSUInteger toggleCount;
- (void)toggleFullScreen:(id)sender;
@end
@implementation ShutdownTestWindow
- (void)toggleFullScreen:(id)sender { self.toggleCount += 1; }
- (BOOL)isMiniaturized { return NO; }
- (NSWindowOcclusionState)occlusionState { return NSWindowOcclusionStateVisible; }
@end

@interface NativeShutdownTests : XCTestCase
@property(nonatomic, strong) ShutdownTestPlayer* player;
@property(nonatomic, strong) NSView* videoHost;
@property(nonatomic, strong) ShutdownTestWindow* window;
@property(nonatomic, strong) ShutdownTestMessenger* messenger;
@end

@implementation NativeShutdownTests
- (void)setUp {
  [super setUp];
  XCTAssertTrue(NSThread.isMainThread);
  worker = std::make_shared<ControlledWorker>();
  self.videoHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 180)];
  self.window = [ShutdownTestWindow new];
  self.messenger = [ShutdownTestMessenger new];
  self.player = [[ShutdownTestPlayer alloc]
      initWithMessenger:self.messenger
              videoHost:self.videoHost
                 window:(NSWindow*)self.window];
}

- (void)tearDown {
  // Always release the controlled worker, even after a failed assertion.
  worker->Release();
  if (self.player.timeoutCount == 0) {
    XCTestExpectation* disposed = [self expectationWithDescription:@"fixture disposed"];
    [self.player beginShutdownWithCompletion:^{ [disposed fulfill]; }];
    [self waitForExpectations:@[ disposed ] timeout:2];
  } else {
    [self waitUntil:^BOOL { return self.videoHost.subviews.count == 0; }];
  }
  self.player = nil;
  self.videoHost = nil;
  self.window = nil;
  worker.reset();
  [super tearDown];
}

- (void)waitUntil:(BOOL (^)(void))condition {
  XCTNSPredicateExpectation* reached = [[XCTNSPredicateExpectation alloc]
      initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary* bindings) {
        return condition();
      }]
                 object:nil];
  [self waitForExpectations:@[ reached ] timeout:2];
}

- (void)initializePlayer {
  [self.player handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"initialize"
                                                                arguments:nil]
                        result:^(id result) { XCTAssertTrue([result isKindOfClass:NSDictionary.class]); }];
  XCTAssertEqual(self.videoHost.subviews.count, 1u);
}

- (void)testOwnedLayerPublishesEveryOffMainSetterBeforeItReturnsWithoutAcquisition {
  [self initializePlayer];
  CAMetalLayer* layer = (CAMetalLayer*)self.videoHost.subviews.firstObject.layer;
  CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
  CAEDRMetadata* metadata = [CAEDRMetadata HDR10MetadataWithMinLuminance:0.01
                                                       maxLuminance:1000
                                                 opticalOutputScale:1];
  LayerPublicationHooks hooks;
  LayerPublicationTrace trace;
  std::thread setter([&] {
    @autoreleasepool {
      ScopedLayerTrace observing(trace);
      layer.colorspace = colorspace;
      layer.wantsExtendedDynamicRangeContent = YES;
      layer.EDRMetadata = metadata;
      layer.pixelFormat = MTLPixelFormatRGB10A2Unorm;
      // MoltenVK also makes this teardown mutation without acquiring again.
      layer.drawableSize = CGSizeMake(1, 1);
    }
  });
  setter.join();
  XCTAssertTrue((trace.calls == std::vector<std::string>{"colorspace", "flush", "edr", "flush",
      "metadata", "flush", "format", "flush", "size", "flush"}));
  XCTAssertEqual(trace.colorspace, colorspace);
  XCTAssertTrue(trace.edr);
  XCTAssertEqual(trace.metadata, metadata);
  XCTAssertEqual(trace.format, MTLPixelFormatRGB10A2Unorm);
  XCTAssertTrue(CGSizeEqualToSize(trace.size, CGSizeMake(1, 1)));
  CGColorSpaceRelease(colorspace);
}

- (void)testOwnedLayerKeepsMainThreadTransactionsAndOriginalAcquisition {
  [self initializePlayer];
  CAMetalLayer* layer = (CAMetalLayer*)self.videoHost.subviews.firstObject.layer;
  NSObject* token = [NSObject new];
  LayerPublicationHooks hooks;
  LayerPublicationTrace trace;
  trace.drawable = token;
  {
    ScopedLayerTrace observing(trace);
    layer.colorspace = nullptr;
    layer.wantsExtendedDynamicRangeContent = NO;
    layer.EDRMetadata = nil;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.drawableSize = CGSizeMake(640, 360);
    XCTAssertEqual((id)[layer nextDrawable], token);
  }
  XCTAssertTrue((trace.calls == std::vector<std::string>{"colorspace", "edr", "metadata",
      "format", "size", "acquire"}));
}

- (void)testDifferentAcquisitionThreadCannotConsumeSetterThreadPublication {
  [self initializePlayer];
  CAMetalLayer* layer = (CAMetalLayer*)self.videoHost.subviews.firstObject.layer;
  NSObject* token = [NSObject new];
  LayerPublicationHooks hooks;
  LayerPublicationTrace setterTrace;
  LayerPublicationTrace otherTrace;
  setterTrace.drawable = token;
  otherTrace.drawable = token;
  std::promise<void> setterReturned;
  std::promise<void> allowAcquisition;
  auto release = allowAcquisition.get_future();
  std::thread setter([&] {
    @autoreleasepool {
      ScopedLayerTrace observing(setterTrace);
      layer.drawableSize = CGSizeMake(1, 1);
      setterReturned.set_value();
      release.wait(); // A remains alive and has not acquired yet.
      [layer nextDrawable];
    }
  });
  setterReturned.get_future().wait();
  XCTAssertTrue((setterTrace.calls == std::vector<std::string>{"size", "flush"}));
  std::thread other([&] {
    @autoreleasepool {
      ScopedLayerTrace observing(otherTrace);
      [layer nextDrawable];
    }
  });
  other.join();
  allowAcquisition.set_value();
  setter.join();
  XCTAssertTrue((otherTrace.calls == std::vector<std::string>{"acquire"}));
  XCTAssertTrue((setterTrace.calls == std::vector<std::string>{"size", "flush", "acquire"}));
}

- (void)testFullscreenSnapshotAndNativeNotificationsUseProductionEventPath {
  self.window.styleMask = NSWindowStyleMaskFullScreen;
  [self initializePlayer];
  // No explicit pump: publish the snapshot before the initialize reply, so
  // Dart's next serialized toggle starts from the observed window state.
  XCTAssertEqual(self.messenger.fullscreenEvents.count, 1u);
  [self.player processWakeup];
  XCTAssertEqualObjects(self.messenger.fullscreenEvents,
                        (@[ @{@"type": @"fullscreen", @"fullscreen": @YES} ]));
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillExitFullScreenNotification
                                                    object:self.window];
  self.window.styleMask = 0;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification
                                                    object:self.window];
  XCTAssertEqual(self.messenger.fullscreenEvents.count, 2u);
  [self.player processWakeup];
  XCTAssertEqual(self.messenger.fullscreenEvents.count, 2u);
  NSDictionary* event = self.messenger.fullscreenEvents.lastObject;
  XCTAssertEqual(event.count, 2u);
  XCTAssertEqualObjects(event[@"fullscreen"], @NO);
  NSNumber* observed = event[@"fullscreen"];
  XCTAssertNotNil(observed);
  if (observed) {
    XCTAssertEqual(CFGetTypeID((__bridge CFTypeRef)observed), CFBooleanGetTypeID());
  }

  __block BOOL disposed = NO;
  [self.player handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"dispose" arguments:nil]
                        result:^(id result) { XCTAssertNil(result); disposed = YES; }];
  worker->Release();
  [self waitUntil:^BOOL { return disposed; }];
  self.window.styleMask = NSWindowStyleMaskFullScreen;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidEnterFullScreenNotification
                                                    object:self.window];
  [self.player processWakeup];
  XCTAssertEqual(self.messenger.fullscreenEvents.count, 2u);
  [self initializePlayer];
  [self.player processWakeup];
  XCTAssertEqual(self.messenger.fullscreenEvents.count, 3u);
  XCTAssertEqualObjects(self.messenger.fullscreenEvents.lastObject[@"fullscreen"], @YES);
}

- (void)testCompletedNativeStateSettlesOppositeRequestWithoutReversing {
  [self initializePlayer];
  [self.player processWakeup];
  __block NSUInteger replies = 0;
  [self.player handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"setFullscreen"
                                                                arguments:@{@"fullscreen": @YES}]
                        result:^(id result) { XCTAssertNil(result); replies += 1; }];
  XCTAssertEqual(self.window.toggleCount, 1u);
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillEnterFullScreenNotification
                                                    object:self.window];
  // Controlled AppKit boundary: a user change finishes in the opposite state.
  self.window.styleMask = 0;
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillExitFullScreenNotification
                                                    object:self.window];
  [NSNotificationCenter.defaultCenter postNotificationName:NSWindowDidExitFullScreenNotification
                                                    object:self.window];
  [self.player processWakeup];
  XCTAssertEqual(replies, 1u);
  XCTAssertEqual(self.window.toggleCount, 1u);
  XCTAssertEqualObjects(self.messenger.fullscreenEvents.lastObject[@"fullscreen"], @NO);
  [self.player processWakeup];
  XCTAssertEqual(replies, 1u);
}

- (void)testFullscreenDeadlinesStillFailWithoutInventingState {
  [self initializePlayer];
  for (NSNumber* started in @[ @NO, @YES ]) {
    __block NSUInteger replies = 0;
    [self.player handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"setFullscreen"
                                                                  arguments:@{@"fullscreen": @YES}]
                          result:^(id result) {
      XCTAssertTrue([result isKindOfClass:FlutterError.class]);
      XCTAssertEqualObjects(((FlutterError*)result).code, @"window_error");
      replies += 1;
    }];
    if (started.boolValue) {
      [NSNotificationCenter.defaultCenter postNotificationName:NSWindowWillEnterFullScreenNotification
                                                      object:self.window];
      uint64_t request = [[self.player valueForKey:@"nextFullscreenRequest"] unsignedLongLongValue];
      [self.player fullscreenRequestTimedOut:request];
      [self.player fullscreenRequestTimedOut:request];
    } else {
      uint64_t toggle = [[self.player valueForKey:@"pendingFullscreenToggle"] unsignedLongLongValue];
      [self.player fullscreenToggleStartTimedOut:toggle];
      [self.player fullscreenToggleStartTimedOut:toggle];
    }
    XCTAssertEqual(replies, 1u);
    XCTAssertEqual(self.messenger.fullscreenEvents.count, 1u);
    XCTAssertEqualObjects(self.messenger.fullscreenEvents.lastObject[@"fullscreen"], @NO);
  }
}

- (void)testQuitWaitsForFlutterApprovalAndKeepsMainLoopAndOwnersAlive {
  [self initializePlayer];
  LineupPlayerLifecycle* lifecycle = [[LineupPlayerLifecycle alloc] initWithPlayer:self.player];
  __block NSUInteger replies = 0;
  void (^reply)(BOOL) = ^(BOOL accepted) { XCTAssertTrue(accepted); replies += 1; };
  XCTAssertEqual([lifecycle applicationShouldTerminateAfterApproval:NSTerminateCancel reply:reply],
                 NSTerminateCancel);
  XCTAssertEqual([lifecycle applicationShouldTerminateAfterApproval:NSTerminateLater reply:reply],
                 NSTerminateLater);
  XCTAssertFalse(worker->terminating);
  XCTAssertEqual([lifecycle applicationShouldTerminateAfterApproval:NSTerminateNow reply:reply],
                 NSTerminateLater);
  XCTAssertEqual([lifecycle applicationShouldTerminateAfterApproval:NSTerminateNow reply:reply],
                 NSTerminateLater);
  XCTAssertEqual(replies, 0u);
  [self waitUntil:^BOOL { return worker->terminating; }];
  XCTAssertFalse(worker->terminatedOnMain);
  XCTAssertEqual(self.videoHost.subviews.count, 1u);
  XCTAssertEqual(self.player.emergencyShutdownCount, 0u);

  // The retained window and host survive loss of the runner's external refs.
  __weak NSObject* window = self.window;
  __weak NSView* host = self.videoHost;
  self.window = nil;
  self.videoHost = nil;
  XCTAssertNotNil(window);
  {
    NSView* retainedHost = host;
    XCTAssertNotNil(retainedHost);
  }
  XCTestExpectation* mainLoop = [self expectationWithDescription:@"main loop services work"];
  dispatch_async(dispatch_get_main_queue(), ^{ [mainLoop fulfill]; });
  [self waitForExpectations:@[ mainLoop ] timeout:1];
  XCTAssertEqual(replies, 0u);
  {
    NSView* retainedHost = host;
    XCTAssertNotNil(retainedHost);
    XCTAssertEqual(retainedHost.subviews.count, 1u);
  }

  worker->Release();
  [self waitUntil:^BOOL { return replies == 1; }];
  XCTAssertEqual(self.player.emergencyShutdownCount, 0u);
  [self.player processWakeup];
  [self.player shutdownTimedOut];
  XCTAssertEqual(replies, 1u);
  XCTAssertEqual(self.player.timeoutCount, 0u);
}

- (void)testCloseQuitAndDartDisposeShareWorkerAndCompleteExactlyOnce {
  [self initializePlayer];
  LineupPlayerLifecycle* lifecycle = [[LineupPlayerLifecycle alloc] initWithPlayer:self.player];
  __block NSUInteger dartReplies = 0;
  FlutterMethodCall* dispose = [FlutterMethodCall methodCallWithMethodName:@"dispose" arguments:nil];
  [self.player handleMethodCall:dispose result:^(id result) {
    XCTAssertNil(result);
    dartReplies += 1;
  }];
  __block NSUInteger closes = 0;
  __block NSUInteger quits = 0;
  dispatch_block_t close = ^{ XCTAssertEqual(self.videoHost.subviews.count, 0u); closes += 1; };
  [lifecycle closeWhenReady:close];
  [lifecycle closeWhenReady:close];
  XCTAssertEqual([lifecycle applicationShouldTerminateAfterApproval:NSTerminateNow reply:^(BOOL accepted) {
    XCTAssertTrue(accepted);
    XCTAssertEqual(self.videoHost.subviews.count, 0u);
    quits += 1;
  }], NSTerminateLater);
  [self.player handleMethodCall:dispose result:^(id result) {
    XCTAssertTrue([result isKindOfClass:FlutterError.class]);
    XCTAssertEqualObjects(((FlutterError*)result).code, @"dispose_in_progress");
  }];
  [self.player handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"initialize" arguments:nil]
                        result:^(id result) {
    XCTAssertTrue([result isKindOfClass:FlutterError.class]);
    XCTAssertEqualObjects(((FlutterError*)result).code, @"not_initialized");
  }];
  [self waitUntil:^BOOL { return worker->terminating; }];
  XCTAssertEqual(closes + quits + dartReplies, 0u);
  XCTAssertEqual(self.videoHost.subviews.count, 1u);
  worker->Release();
  [self waitUntil:^BOOL { return closes == 1 && quits == 1 && dartReplies == 1; }];
  [self.player processWakeup];
  [self.player processWakeup];
  [self.player shutdownTimedOut];
  [lifecycle closeWhenReady:close];
  XCTAssertEqual([lifecycle applicationShouldTerminateAfterApproval:NSTerminateNow reply:^(BOOL accepted) {
    XCTFail(@"termination already replied");
  }], NSTerminateNow);
  XCTAssertEqual(closes + quits + dartReplies, 3u);
  XCTAssertEqual(self.player.emergencyShutdownCount, 0u);
  XCTAssertEqual(self.player.timeoutCount, 0u);
}

- (void)testUnusedPlayerAndMissingPlayerCompleteOnLaterMainQueueTurn {
  __block NSUInteger completions = 0;
  [self.player beginShutdownWithCompletion:^{ completions += 1; }];
  [self.player beginShutdownWithCompletion:^{ completions += 1; }];
  LineupPlayerLifecycle* lifecycle = [[LineupPlayerLifecycle alloc] initWithPlayer:nil];
  [lifecycle closeWhenReady:^{ completions += 1; }];
  XCTAssertEqual([lifecycle applicationShouldTerminateAfterApproval:NSTerminateNow reply:^(BOOL accepted) {
    XCTAssertTrue(accepted);
    completions += 1;
  }], NSTerminateLater);
  XCTAssertEqual(completions, 0u);
  [self waitUntil:^BOOL { return completions == 4; }];
  XCTAssertEqual(self.player.emergencyShutdownCount, 0u);
}

- (void)testAlreadyDisposedPlayerStillDefersRunnerReply {
  [self initializePlayer];
  __block BOOL dartDisposed = NO;
  [self.player handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"dispose" arguments:nil]
                        result:^(id result) { XCTAssertNil(result); dartDisposed = YES; }];
  worker->Release();
  [self waitUntil:^BOOL { return dartDisposed; }];
  __block BOOL completed = NO;
  [self.player beginShutdownWithCompletion:^{ completed = YES; }];
  XCTAssertFalse(completed);
  [self waitUntil:^BOOL { return completed; }];
  XCTAssertEqual(self.videoHost.subviews.count, 0u);
}

- (void)testTimeoutWinsWithoutReleasingLiveLayerOrReplyingSuccess {
  [self initializePlayer];
  __block NSUInteger replies = 0;
  [self.player beginShutdownWithCompletion:^{ replies += 1; }];
  [self waitUntil:^BOOL { return worker->terminating; }];
  [self.player shutdownTimedOut];
  [self.player shutdownTimedOut];
  XCTAssertEqual(self.player.timeoutCount, 1u);
  XCTAssertEqual(replies, 0u);
  XCTAssertEqual(self.videoHost.subviews.count, 1u);
  XCTAssertEqual(self.player.emergencyShutdownCount, 0u);
  // Only the test's exit action returns; production has already _Exit'ed.
  worker->Release();
  [self waitUntil:^BOOL { return self.videoHost.subviews.count == 0; }];
  [self.player processWakeup];
  XCTAssertEqual(replies, 0u);
  XCTAssertEqual(self.player.timeoutCount, 1u);
}

- (void)testCompletedCoreWinsLateDeadlineBeforeDeferredRunnerReply {
  [self initializePlayer];
  self.player.deferRunnerCompletion = YES;
  __block BOOL dartDisposed = NO;
  [self.player handleMethodCall:[FlutterMethodCall methodCallWithMethodName:@"dispose" arguments:nil]
                        result:^(id result) { XCTAssertNil(result); dartDisposed = YES; }];
  __block NSUInteger runnerReplies = 0;
  [self.player beginShutdownWithCompletion:^{ runnerReplies += 1; }];
  worker->Release();
  [self waitUntil:^BOOL { return dartDisposed; }];
  XCTAssertEqual(self.videoHost.subviews.count, 0u);
  XCTAssertEqual(runnerReplies, 0u);
  self.player.deferRunnerCompletion = NO;
  [self.player shutdownTimedOut];
  XCTAssertEqual(runnerReplies, 1u);
  XCTAssertEqual(self.player.timeoutCount, 0u);
  [self.player shutdownTimedOut];
  [self.player processWakeup];
  XCTAssertEqual(runnerReplies, 1u);
}

- (void)testRealTimeoutExitProbe {
  XCTSkipUnless(getenv("LINEUP_SHUTDOWN_TIMEOUT_PROBE"), @"Run explicitly in a child xctest process.");
  [self initializePlayer];
  self.player.useRealTimeoutExit = YES;
  [self.player beginShutdownWithCompletion:^{ XCTFail(@"Blocked worker must not complete."); }];
  XCTestExpectation* unexpectedReturn = [self expectationWithDescription:@"process must exit first"];
  [self waitForExpectations:@[ unexpectedReturn ] timeout:8];
}
@end
