#ifndef RUNNER_NATIVE_PLAYER_FOUNDATION_VALUE_CONVERSION_H_
#define RUNNER_NATIVE_PLAYER_FOUNDATION_VALUE_CONVERSION_H_

#import <Foundation/Foundation.h>

#include <optional>

#include "player_core/value.h"

namespace lineup {

// Converts between the Foundation objects that Flutter's standard method
// codec produces on macOS and the core's neutral value tree.
//
// Decoding rules:
// - nil and NSNull become null.
// - An NSNumber backed by CFBoolean becomes bool; a floating-point NSNumber
//   becomes double; every other NSNumber becomes int64. The codec decodes
//   Dart bool, int, and double into exactly these three kinds.
// - NSString becomes its UTF-8 bytes, written directly into the result so no
//   extra un-wiped copy of a token is created. A string that cannot be
//   represented as UTF-8 becomes the non-null placeholder below.
// - NSArray and NSDictionary convert recursively; dictionary entries whose
//   key is not an NSString are dropped, as on Windows.
// - Any other object (for example FlutterStandardTypedData, which no protocol
//   argument uses) becomes an empty list: a non-null placeholder that fails
//   every typed lookup.
player::Value ToValue(id _Nullable object);

// The map argument of a method call, or nullopt when it is not a dictionary.
std::optional<player::ValueMap> ToValueMap(id _Nullable object);

// Encoding: null becomes NSNull, bool a CFBoolean NSNumber, int64 and double
// NSNumbers of those types, strings NSString, and lists and maps NSArray and
// NSDictionary. Null map entries are kept so that required keys stay present.
id _Nonnull ToFoundation(const player::Value& value);
NSDictionary<NSString*, id>* _Nonnull ToFoundationMap(
    const player::ValueMap& map);

}  // namespace lineup

#endif
