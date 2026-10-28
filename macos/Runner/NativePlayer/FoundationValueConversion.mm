#import "FoundationValueConversion.h"

#include <string>
#include <type_traits>
#include <utility>
#include <variant>

namespace lineup {

namespace {

player::Value Placeholder() {
  return player::Value(player::ValueList{});
}

player::Value ToNumber(NSNumber* number) {
  const auto ref = (__bridge CFTypeRef)number;
  if (CFGetTypeID(ref) == CFBooleanGetTypeID()) {
    return player::Value(static_cast<bool>(number.boolValue));
  }
  if (CFNumberIsFloatType((__bridge CFNumberRef)number)) {
    return player::Value(number.doubleValue);
  }
  return player::Value(static_cast<int64_t>(number.longLongValue));
}

player::Value ToString(NSString* string) {
  const NSUInteger length = string.length;
  if (length == 0) {
    return player::Value(std::string());
  }
  const NSUInteger capacity =
      [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  if (capacity == 0) {
    return Placeholder();
  }
  std::string bytes(capacity, '\0');
  NSUInteger used = 0;
  NSRange remaining{};
  const BOOL converted = [string getBytes:bytes.data()
                                maxLength:capacity
                               usedLength:&used
                                 encoding:NSUTF8StringEncoding
                                  options:0
                                    range:NSMakeRange(0, length)
                           remainingRange:&remaining];
  if (!converted || remaining.length != 0) {
    return Placeholder();
  }
  bytes.resize(used);
  return player::Value(std::move(bytes));
}

player::ValueMap ConvertMap(NSDictionary* dictionary) {
  player::ValueMap converted;
  for (id key in dictionary) {
    if (![key isKindOfClass:[NSString class]]) {
      continue;
    }
    const auto name = ToString(key);
    if (const auto* text = std::get_if<std::string>(&name)) {
      converted.emplace(*text, ToValue(dictionary[key]));
    }
  }
  return converted;
}

}  // namespace

player::Value ToValue(id object) {
  if (object == nil || object == [NSNull null]) {
    return player::Value();
  }
  if ([object isKindOfClass:[NSNumber class]]) {
    return ToNumber(object);
  }
  if ([object isKindOfClass:[NSString class]]) {
    return ToString(object);
  }
  if ([object isKindOfClass:[NSArray class]]) {
    player::ValueList list;
    list.reserve([object count]);
    for (id item in (NSArray*)object) {
      list.push_back(ToValue(item));
    }
    return player::Value(std::move(list));
  }
  if ([object isKindOfClass:[NSDictionary class]]) {
    return player::Value(ConvertMap(object));
  }
  return Placeholder();
}

std::optional<player::ValueMap> ToValueMap(id object) {
  if (![object isKindOfClass:[NSDictionary class]]) {
    return std::nullopt;
  }
  return ConvertMap(object);
}

id ToFoundation(const player::Value& value) {
  return std::visit([](const auto& entry) -> id {
    using Entry = std::decay_t<decltype(entry)>;
    if constexpr (std::is_same_v<Entry, std::monostate>) {
      return [NSNull null];
    } else if constexpr (std::is_same_v<Entry, bool>) {
      return entry ? (__bridge id)kCFBooleanTrue : (__bridge id)kCFBooleanFalse;
    } else if constexpr (std::is_same_v<Entry, int64_t>) {
      return [NSNumber numberWithLongLong:entry];
    } else if constexpr (std::is_same_v<Entry, double>) {
      return [NSNumber numberWithDouble:entry];
    } else if constexpr (std::is_same_v<Entry, std::string>) {
      NSString* string = [[NSString alloc] initWithBytes:entry.data()
                                                  length:entry.size()
                                                encoding:NSUTF8StringEncoding];
      // The core bounds every string it emits to valid UTF-8.
      return string ? string : (id)[NSNull null];
    } else if constexpr (std::is_same_v<Entry, player::ValueList>) {
      NSMutableArray* list = [NSMutableArray arrayWithCapacity:entry.size()];
      for (const auto& item : entry) {
        [list addObject:ToFoundation(item)];
      }
      return list;
    } else {
      return ToFoundationMap(entry);
    }
  }, static_cast<const player::internal::ValueVariant&>(value));
}

NSDictionary<NSString*, id>* ToFoundationMap(const player::ValueMap& map) {
  NSMutableDictionary<NSString*, id>* converted =
      [NSMutableDictionary dictionaryWithCapacity:map.size()];
  for (const auto& [key, entry] : map) {
    NSString* name = [[NSString alloc] initWithBytes:key.data()
                                              length:key.size()
                                            encoding:NSUTF8StringEncoding];
    if (name) {
      converted[name] = ToFoundation(entry);
    }
  }
  return converted;
}

}  // namespace lineup
