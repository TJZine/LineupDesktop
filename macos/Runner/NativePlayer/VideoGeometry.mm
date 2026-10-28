#include "VideoGeometry.h"

#include <algorithm>
#include <cmath>

namespace lineup {

namespace {

CGFloat DrawableDimension(CGFloat points, CGFloat scale) {
  const CGFloat pixels = std::round(points * scale);
  if (!std::isfinite(pixels)) {
    return 1;
  }
  return std::clamp<CGFloat>(pixels, 1, kMaxDrawableDimension);
}

}  // namespace

CGRect VideoFrame(const VideoRect& rect) {
  return CGRectMake(rect.left, rect.top, rect.width, rect.height);
}

CGRect RetainedVideoFrame(const std::optional<VideoRect>& rect,
                          CGRect previous) {
  if (rect && rect->width > 0 && rect->height > 0) {
    return VideoFrame(*rect);
  }
  if (previous.size.width > 0 && previous.size.height > 0) {
    return previous;
  }
  return CGRectMake(0, 0, 1, 1);
}

bool VideoVisible(const std::optional<VideoRect>& rect, bool minimized,
                  bool occluded) {
  return rect && rect->width > 0 && rect->height > 0 && !minimized &&
         !occluded;
}

CGSize DrawableSize(CGSize bounds, CGFloat backing_scale) {
  const CGFloat scale =
      std::isfinite(backing_scale) && backing_scale > 0 ? backing_scale : 1;
  return CGSizeMake(DrawableDimension(bounds.width, scale),
                    DrawableDimension(bounds.height, scale));
}

}  // namespace lineup
