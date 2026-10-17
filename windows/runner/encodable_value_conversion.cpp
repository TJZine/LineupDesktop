#include "encodable_value_conversion.h"

#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace lineup {

namespace {

template <typename Number>
player::Value ToNumberList(const std::vector<Number>& numbers) {
  player::ValueList list;
  list.reserve(numbers.size());
  for (const Number number : numbers) {
    if constexpr (std::is_floating_point_v<Number>) {
      list.emplace_back(static_cast<double>(number));
    } else {
      list.emplace_back(static_cast<int64_t>(number));
    }
  }
  return player::Value(std::move(list));
}

player::ValueMap ConvertMap(const flutter::EncodableMap& map) {
  player::ValueMap converted;
  for (const auto& [key, entry] : map) {
    if (const auto* text = std::get_if<std::string>(&key)) {
      converted.emplace(*text, ToValue(entry));
    }
  }
  return converted;
}

}  // namespace

std::optional<player::ValueMap> ToValueMap(const flutter::EncodableValue* value) {
  const auto* map = value ? std::get_if<flutter::EncodableMap>(value) : nullptr;
  if (!map) {
    return std::nullopt;
  }
  return ConvertMap(*map);
}

player::Value ToValue(const flutter::EncodableValue& value) {
  return std::visit([](const auto& entry) -> player::Value {
    using Entry = std::decay_t<decltype(entry)>;
    if constexpr (std::is_same_v<Entry, std::monostate>) {
      return player::Value();
    } else if constexpr (std::is_same_v<Entry, bool> ||
                         std::is_same_v<Entry, int64_t> ||
                         std::is_same_v<Entry, double> ||
                         std::is_same_v<Entry, std::string>) {
      return player::Value(entry);
    } else if constexpr (std::is_same_v<Entry, int32_t>) {
      return player::Value(static_cast<int64_t>(entry));
    } else if constexpr (std::is_same_v<Entry, flutter::EncodableList>) {
      player::ValueList list;
      list.reserve(entry.size());
      for (const auto& item : entry) {
        list.push_back(ToValue(item));
      }
      return player::Value(std::move(list));
    } else if constexpr (std::is_same_v<Entry, flutter::EncodableMap>) {
      return player::Value(ConvertMap(entry));
    } else if constexpr (std::is_same_v<Entry, std::vector<uint8_t>> ||
                         std::is_same_v<Entry, std::vector<int32_t>> ||
                         std::is_same_v<Entry, std::vector<int64_t>> ||
                         std::is_same_v<Entry, std::vector<float>> ||
                         std::is_same_v<Entry, std::vector<double>>) {
      return ToNumberList(entry);
    } else {
      // CustomEncodableValue is never produced by standard codec decoding.
      // A non-null placeholder keeps every typed lookup failing.
      return player::Value(player::ValueList{});
    }
  }, static_cast<const flutter::EncodableValue::super&>(value));
}

flutter::EncodableValue ToEncodableValue(const player::Value& value) {
  return std::visit([](const auto& entry) -> flutter::EncodableValue {
    using Entry = std::decay_t<decltype(entry)>;
    if constexpr (std::is_same_v<Entry, std::monostate>) {
      return flutter::EncodableValue();
    } else if constexpr (std::is_same_v<Entry, player::ValueList>) {
      flutter::EncodableList list;
      list.reserve(entry.size());
      for (const auto& item : entry) {
        list.push_back(ToEncodableValue(item));
      }
      return flutter::EncodableValue(std::move(list));
    } else if constexpr (std::is_same_v<Entry, player::ValueMap>) {
      return flutter::EncodableValue(ToEncodableMap(entry));
    } else {
      return flutter::EncodableValue(entry);
    }
  }, static_cast<const player::internal::ValueVariant&>(value));
}

flutter::EncodableMap ToEncodableMap(const player::ValueMap& map) {
  flutter::EncodableMap converted;
  for (const auto& [key, entry] : map) {
    converted.emplace(flutter::EncodableValue(key), ToEncodableValue(entry));
  }
  return converted;
}

}  // namespace lineup
