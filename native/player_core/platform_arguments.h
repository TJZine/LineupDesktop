#ifndef LINEUP_PLAYER_CORE_PLATFORM_ARGUMENTS_H_
#define LINEUP_PLAYER_CORE_PLATFORM_ARGUMENTS_H_

#include <cstdint>
#include <optional>

#include "player_core/value.h"

namespace lineup::player {

// Protocol validation for the methods that platform adapters implement
// (`setDisplayMatching`, `setVideoRect`). The bounds and error messages are
// the protocol's; each adapter maps a valid request to its own mechanism and
// reports `invalid_argument` with these messages otherwise.

enum class DisplayDesire { hdr, sdr, unknown };

struct DisplayMatchingArguments {
  int64_t revision;
  bool session;
  DisplayDesire desired;
};

inline constexpr char kInvalidDisplayMatchingMessage[] =
    "A valid display matching request is required.";
inline constexpr char kStaleDisplayRevisionMessage[] =
    "Display revision must strictly increase.";

// `revision`: integer >= 0; `session`: bool; `desired`: "hdr", "sdr", or
// "unknown". Returns nullopt for a missing map or any other value.
std::optional<DisplayMatchingArguments> ParseDisplayMatchingArguments(
    const ValueMap* arguments);

// The protocol's strictly increasing native display revision, reset by
// `initialize`. (The Windows display controller keeps this ordering inside
// its own locked request state, so only adapters without one use this.)
class DisplayRevisionOrder {
 public:
  // Accepts and records a revision newer than every accepted one.
  bool Admit(int64_t revision);
  void Reset() { last_ = -1; }

 private:
  int64_t last_ = -1;
};

struct VideoRectArguments {
  double left;
  double top;
  double width;
  double height;
  double scale;
};

inline constexpr char kInvalidVideoRectMessage[] =
    "Valid finite video bounds are required.";

// `left`, `top`, `width`, `height`, and `scale` are finite numbers (integer
// or double); `width >= 0`, `height >= 0`, and `scale > 0`.
std::optional<VideoRectArguments> ParseVideoRectArguments(
    const ValueMap& arguments);

}  // namespace lineup::player

#endif
