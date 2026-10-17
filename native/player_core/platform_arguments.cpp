#include "player_core/platform_arguments.h"

#include <cmath>
#include <string>

namespace lineup::player {

namespace {

std::optional<DisplayDesire> ParseDesire(const std::string* desired) {
  if (!desired) return std::nullopt;
  if (*desired == "hdr") return DisplayDesire::hdr;
  if (*desired == "sdr") return DisplayDesire::sdr;
  if (*desired == "unknown") return DisplayDesire::unknown;
  return std::nullopt;
}

}  // namespace

std::optional<DisplayMatchingArguments> ParseDisplayMatchingArguments(
    const ValueMap* arguments) {
  const auto revision =
      arguments ? AsInt(Find(*arguments, "revision")) : std::nullopt;
  const bool* session = FindBool(arguments, "session");
  const auto desired = ParseDesire(FindString(arguments, "desired"));
  if (!revision || *revision < 0 || !session || !desired) {
    return std::nullopt;
  }
  return DisplayMatchingArguments{*revision, *session, *desired};
}

bool DisplayRevisionOrder::Admit(int64_t revision) {
  if (revision <= last_) {
    return false;
  }
  last_ = revision;
  return true;
}

std::optional<VideoRectArguments> ParseVideoRectArguments(
    const ValueMap& arguments) {
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
  return VideoRectArguments{*left, *top, *width, *height, *scale};
}

}  // namespace lineup::player
