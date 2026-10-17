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
/// minimize, occlusion, and close transitions; the video view itself follows
/// backing-scale changes (viewDidChangeBackingProperties).
- (instancetype)initWithMessenger:(id<FlutterBinaryMessenger>)messenger
                        videoHost:(NSView*)videoHost
                           window:(NSWindow*)window NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Synchronously completes disposal in the documented order: stop accepting
/// commands, terminate libmpv on its worker (which releases the swapchain),
/// then remove the video view. Pending Dart calls are not answered. Safe to
/// call repeatedly; the window-close and application-terminate observers call
/// it automatically.
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
