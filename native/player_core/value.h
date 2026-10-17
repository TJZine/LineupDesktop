#ifndef LINEUP_PLAYER_CORE_VALUE_H_
#define LINEUP_PLAYER_CORE_VALUE_H_

#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace lineup::player {

// Platform-neutral replacement for a platform codec value. Each platform
// adapter converts between this tree and its own Flutter codec type. Map keys
// are strings because every protocol key is a string; an adapter drops other
// key types, which no protocol lookup could match.
class Value;
using ValueList = std::vector<Value>;
using ValueMap = std::map<std::string, Value, std::less<>>;

namespace internal {
using ValueVariant = std::variant<std::monostate, bool, int64_t, double,
                                  std::string, ValueList, ValueMap>;
}

class Value : public internal::ValueVariant {
 public:
  using internal::ValueVariant::ValueVariant;
  using internal::ValueVariant::operator=;

  Value() = default;
  // Without these overloads a string literal would select the bool
  // alternative and an int literal would be ambiguous.
  Value(const char* string) : internal::ValueVariant(std::string(string)) {}
  Value(int32_t number) : internal::ValueVariant(int64_t{number}) {}
  Value& operator=(const char* string) {
    internal::ValueVariant::operator=(std::string(string));
    return *this;
  }
};

inline const Value* Find(const ValueMap& map, const char* key) {
  const auto found = map.find(key);
  return found == map.end() ? nullptr : &found->second;
}

inline const ValueMap* AsMap(const Value* value) {
  return value ? std::get_if<ValueMap>(value) : nullptr;
}

inline const std::string* FindString(const ValueMap* map, const char* key) {
  const auto* value = map ? Find(*map, key) : nullptr;
  return value ? std::get_if<std::string>(value) : nullptr;
}

inline const bool* FindBool(const ValueMap* map, const char* key) {
  const auto* value = map ? Find(*map, key) : nullptr;
  return value ? std::get_if<bool>(value) : nullptr;
}

inline std::optional<double> AsNumber(const Value* value) {
  if (!value) {
    return std::nullopt;
  }
  if (const auto* number = std::get_if<double>(value)) {
    return *number;
  }
  if (const auto* number = std::get_if<int64_t>(value)) {
    return static_cast<double>(*number);
  }
  return std::nullopt;
}

inline std::optional<int64_t> AsInt(const Value* value) {
  if (const auto* number = value ? std::get_if<int64_t>(value) : nullptr) {
    return *number;
  }
  return std::nullopt;
}

}  // namespace lineup::player

#endif
