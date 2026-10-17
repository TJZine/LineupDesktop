#import <XCTest/XCTest.h>

#import "LineupNativePlayer.h"
#import "LineupPlayerLifecycle.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <memory>
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
}  // namespace

@interface LineupNativePlayer (LifecycleTests)
- (lineup::player::MpvOperations)mpvOperations;
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result;
- (void)processWakeup;
- (void)shutdownTimedOut;
- (void)completeShutdownIfReady;
- (void)terminateAfterShutdownTimeout;
@end

// The real adapter and real core run throughout these tests. Only libmpv's
// operations and the terminal process-exit action are controlled boundaries.
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
@end
@implementation ShutdownTestMessenger
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message {}
- (void)sendOnChannel:(NSString*)channel
             message:(NSData*)message
         binaryReply:(FlutterBinaryReply)callback {}
- (FlutterBinaryMessengerConnection)
    setMessageHandlerOnChannel:(NSString*)channel
          binaryMessageHandler:(FlutterBinaryMessageHandler)handler { return 1; }
- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection {}
@end

@interface ShutdownTestWindow : NSObject
@end
@implementation ShutdownTestWindow
- (BOOL)isMiniaturized { return NO; }
- (NSWindowOcclusionState)occlusionState { return NSWindowOcclusionStateVisible; }
@end

@interface NativeShutdownTests : XCTestCase
@property(nonatomic, strong) ShutdownTestPlayer* player;
@property(nonatomic, strong) NSView* videoHost;
@property(nonatomic, strong) NSObject* window;
@end

@implementation NativeShutdownTests
- (void)setUp {
  [super setUp];
  XCTAssertTrue(NSThread.isMainThread);
  worker = std::make_shared<ControlledWorker>();
  self.videoHost = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 180)];
  self.window = [ShutdownTestWindow new];
  self.player = [[ShutdownTestPlayer alloc]
      initWithMessenger:[ShutdownTestMessenger new]
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
