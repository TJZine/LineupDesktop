#import "LineupPlayerLifecycle.h"

#import "LineupNativePlayer.h"

@implementation LineupPlayerLifecycle {
  LineupNativePlayer* _player;
  BOOL _terminationRequested;
  BOOL _terminationReplied;
  BOOL _closeRequested;
  BOOL _closed;
}

- (instancetype)initWithPlayer:(LineupNativePlayer*)player {
  self = [super init];
  if (self) _player = player;
  return self;
}

- (void)beginShutdown:(dispatch_block_t)completion {
  if (_player) {
    [_player beginShutdownWithCompletion:completion];
  } else {
    dispatch_async(dispatch_get_main_queue(), completion);
  }
}

- (NSApplicationTerminateReply)applicationShouldTerminateAfterApproval:
                                  (NSApplicationTerminateReply)approval
                                                               reply:
                                  (void (^)(BOOL))reply {
  // In particular, Flutter's initial cancel means it is asking Dart, which
  // may veto the quit. Native playback must keep running during that decision.
  if (approval != NSTerminateNow) return approval;
  if (_terminationReplied) return NSTerminateNow;
  if (!_terminationRequested) {
    _terminationRequested = YES;
    [self beginShutdown:^{
      if (self->_terminationReplied) return;
      self->_terminationReplied = YES;
      reply(YES);
    }];
  }
  return NSTerminateLater;
}

- (void)closeWhenReady:(dispatch_block_t)close {
  if (_closeRequested) return;
  _closeRequested = YES;
  [self beginShutdown:^{
    if (self->_closed) return;
    self->_closed = YES;
    close();
  }];
}

@end
