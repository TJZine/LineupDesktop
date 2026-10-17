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

std::optional<VideoRect> ParseVideoRect(const player::ValueMap& arguments) {
  using player::AsNumber;
  using player::Find;
  const auto left = AsNumber(Find(arguments, "left"));
  const auto top = AsNumber(Find(arguments, "top"));
  const auto width = AsNumber(Find(arguments, "width"));
  const auto height = AsNumber(Find(arguments, "height"));
  const auto scale = AsNumber(Find(arguments, "scale"));
  if (!left || !top || !width || !height || !scale ||
      !std::isfinite(*left) || !std::isfinite(*top) ||
      !std::isfinite(*width) || !std::isfinite(*height) ||
      !std::isfinite(*scale) || *width < 0 || *height < 0 || *scale <= 0) {
    return std::nullopt;
  }
  return VideoRect{*left, *top, *width, *height};
}

CGRect VideoFrame(const VideoRect& rect) {
  return CGRectMake(rect.left, rect.top, rect.width, rect.height);
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
