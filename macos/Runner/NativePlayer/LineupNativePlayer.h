#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

NS_ASSUME_NONNULL_BEGIN

/// macOS adapter for the shared libmpv player core behind the
/// `lineup/native_player` channel.
///
/// It owns the method channel and codec conversion, the passive
/// CAMetalLayer-backed video view that libmpv renders into (added to
/// `videoHost`, which sits below the transparent FlutterView), the video
/// rectangle, native fullscreen, and the always-unavailable display report.
/// Every method is main-thread only.
@interface LineupNativePlayer : NSObject

/// `videoHost` must be a flipped view that fills the window's content area
/// below the FlutterView. The adapter observes `window` for fullscreen,
/// minimize and occlusion transitions; the video view itself follows
/// backing-scale changes (viewDidChangeBackingProperties).
- (instancetype)initWithMessenger:(id<FlutterBinaryMessenger>)messenger
                        videoHost:(NSView*)videoHost
                           window:(NSWindow*)window NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Permanently stops this adapter for runner shutdown. Returns immediately;
/// completions run on the main queue only after the worker has terminated,
/// been joined, and its presentation has been released. Repeated requests
/// coalesce; an in-flight Dart disposal keeps its original reply. The adapter
/// retains itself and the window/view owners until completion. If the worker
/// misses the five-second deadline, a fixed diagnostic is logged and the
/// process exits with failure without running destructors or releasing output.
- (void)beginShutdownWithCompletion:(dispatch_block_t)completion;

/// Emergency synchronous cleanup for destruction only. Normal close/quit
/// must use beginShutdownWithCompletion: while the main run loop is alive.
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
