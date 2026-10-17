#ifndef RUNNER_ENCODABLE_VALUE_CONVERSION_H_
#define RUNNER_ENCODABLE_VALUE_CONVERSION_H_

#include <flutter/encodable_value.h>

#include <optional>

#include "player_core/value.h"

namespace lineup {

// Converts a decoded method-call argument for the player core. Returns
// std::nullopt when the argument is not a map. Non-string keys are dropped
// because no protocol lookup can match them. int32 values become int64 and
// typed lists become lists, so a type check fails exactly as it did against
// the Flutter value.
std::optional<player::ValueMap> ToValueMap(const flutter::EncodableValue* value);
player::Value ToValue(const flutter::EncodableValue& value);

// Converts a core value for the standard codec. Integers stay int64.
flutter::EncodableValue ToEncodableValue(const player::Value& value);
flutter::EncodableMap ToEncodableMap(const player::ValueMap& map);

}  // namespace lineup

#endif
