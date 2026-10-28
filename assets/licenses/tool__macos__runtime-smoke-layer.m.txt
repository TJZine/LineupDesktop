// Off-screen CAMetalLayer for runtime-smoke.c's --layer mode: the host-owned
// layer that the route C embedding patch accepts through --wid.

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <stdint.h>

int64_t runtime_smoke_create_layer(int width, int height) {
  // mpv's macvk context requires an NSApplication, as the app always has.
  [NSApplication sharedApplication];
  CAMetalLayer *layer = [[CAMetalLayer alloc] init];
  layer.device = MTLCreateSystemDefaultDevice();
  layer.frame = CGRectMake(0, 0, width, height);
  layer.drawableSize = CGSizeMake(width, height);
  layer.contentsScale = 1;
  return (int64_t)(intptr_t)layer;  // Retained for the process lifetime.
}
