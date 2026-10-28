#import <Cocoa/Cocoa.h>

@class LineupNativePlayer;

NS_ASSUME_NONNULL_BEGIN

/// Runner close/quit sequencing. All calls are on the main thread. The caller
/// supplies Flutter's termination decision before native disposal can begin.
@interface LineupPlayerLifecycle : NSObject
- (instancetype)initWithPlayer:(nullable LineupNativePlayer*)player;
- (NSApplicationTerminateReply)applicationShouldTerminateAfterApproval:
                                  (NSApplicationTerminateReply)approval
                                                               reply:
                                  (void (^)(BOOL))reply;
/// Called from NSWindow.close, after performClose has consulted the existing
/// window delegate. Repeated close requests produce one actual close.
- (void)closeWhenReady:(dispatch_block_t)close;
@end

NS_ASSUME_NONNULL_END
