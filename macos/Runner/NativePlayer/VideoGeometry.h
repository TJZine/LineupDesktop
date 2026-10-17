#ifndef RUNNER_NATIVE_PLAYER_VIDEO_GEOMETRY_H_
#define RUNNER_NATIVE_PLAYER_VIDEO_GEOMETRY_H_

#include <CoreGraphics/CoreGraphics.h>

#include <optional>

#include "player_core/value.h"

namespace lineup {

// The `setVideoRect` rectangle in logical points with a top-left origin.
// The protocol's `scale` is validated but not kept: AppKit views already work
// in points, and the backing scale is applied to the layer instead.
struct VideoRect {
  double left = 0;
  double top = 0;
  double width = 0;
  double height = 0;
};

// Validates `setVideoRect` arguments exactly as the protocol documents:
// finite left, top, width, height, and scale; width >= 0, height >= 0, and
// scale > 0. Returns nullopt for anything else.
std::optional<VideoRect> ParseVideoRect(const player::ValueMap& arguments);

// The video view frame inside a flipped (top-left origin) host view.
CGRect VideoFrame(const VideoRect& rect);

// The frame to keep while video may be hidden: the rectangle's frame when it
// has area, otherwise the previous frame when that has area, otherwise a
// 1x1 point frame at the origin. It is never empty, because the swapchain
// extent comes from the layer bounds even while the layer is hidden.
CGRect RetainedVideoFrame(const std::optional<VideoRect>& rect,
                          CGRect previous);

// Video is visible only with a non-empty rectangle while the window is
// neither minimized nor occluded. Without a rectangle it stays hidden.
bool VideoVisible(const std::optional<VideoRect>& rect, bool minimized,
                  bool occluded);

// The CAMetalLayer drawable size in pixels for view bounds in points: each
// dimension is rounded and clamped to [1, kMaxDrawableDimension] (the Metal
// texture limit), because the patched mpv context renders at this size.
constexpr CGFloat kMaxDrawableDimension = 16384;
CGSize DrawableSize(CGSize bounds, CGFloat backing_scale);

}  // namespace lineup

#endif
