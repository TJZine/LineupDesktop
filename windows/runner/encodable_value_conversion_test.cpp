#include "encodable_value_conversion.h"

#include <flutter/method_call.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using lineup::player::Value;
using lineup::player::ValueList;
using lineup::player::ValueMap;

void Check(bool condition, const char* obligation) {
  if (!condition) {
    std::cerr << obligation << '\n';
    std::exit(1);
  }
}

std::vector<uint8_t> EncodeEvent(const EncodableMap& event) {
  const auto encoded = flutter::StandardMethodCodec::GetInstance().EncodeMethodCall(
      flutter::MethodCall<EncodableValue>(
          "event", std::make_unique<EncodableValue>(event)));
  return *encoded;
}

// Decodes arguments as the channel does, so small Dart ints arrive as int32.
std::optional<ValueMap> DecodeArguments(const EncodableMap& arguments) {
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  const auto encoded = codec.EncodeMethodCall(flutter::MethodCall<EncodableValue>(
      "load", std::make_unique<EncodableValue>(arguments)));
  const auto call = codec.DecodeMethodCall(*encoded);
  return lineup::ToValueMap(call->arguments());
}

void Arguments() {
  Check(!lineup::ToValueMap(nullptr), "missing arguments are not a map");
  const EncodableValue list{EncodableList{}};
  Check(!lineup::ToValueMap(&list), "a list argument is not a map");

  const auto decoded = DecodeArguments({
      {EncodableValue("loadId"), EncodableValue(int32_t{7})},
      {EncodableValue("big"), EncodableValue(int64_t{1} << 40)},
      {EncodableValue("seconds"), EncodableValue(1.5)},
      {EncodableValue("uri"), EncodableValue("https://media.invalid")},
      {EncodableValue("startPaused"), EncodableValue(true)},
      {EncodableValue("plexToken"), EncodableValue()},
      {EncodableValue(int32_t{3}), EncodableValue("non-string key")},
      {EncodableValue("bytes"), EncodableValue(std::vector<uint8_t>{1, 2})},
      {EncodableValue("doubles"), EncodableValue(std::vector<double>{0.5})},
      {EncodableValue("nested"),
       EncodableValue(EncodableMap{{EncodableValue("id"), EncodableValue(int32_t{2})}})},
      {EncodableValue("items"), EncodableValue(EncodableList{EncodableValue(int32_t{4})})},
  });
  Check(decoded.has_value() && decoded->size() == 10, "string keys are kept, others dropped");
  const auto& map = *decoded;
  Check(map.at("loadId") == Value(int64_t{7}), "wire int32 becomes int64");
  Check(map.at("big") == Value(int64_t{1} << 40), "wire int64 stays int64");
  Check(map.at("seconds") == Value(1.5), "double is kept");
  Check(map.at("uri") == Value("https://media.invalid"), "string is kept");
  Check(map.at("startPaused") == Value(true), "bool is kept");
  Check(std::holds_alternative<std::monostate>(map.at("plexToken")), "null is kept as null");
  Check(map.at("bytes") == Value(ValueList{Value(int64_t{1}), Value(int64_t{2})}),
        "typed list becomes a non-null list");
  Check(map.at("doubles") == Value(ValueList{Value(0.5)}), "float list becomes a list");
  Check(map.at("nested") == Value(ValueMap{{"id", Value(int64_t{2})}}), "nested map converts");
  Check(map.at("items") == Value(ValueList{Value(int64_t{4})}), "nested list converts");
}

void Events() {
  // Each event must serialize to the same bytes as the map the previous
  // Flutter-typed implementation built directly.
  const ValueMap state{{"type", Value("state")}, {"state", Value("error")},
                       {"message", Value("Media playback failed")},
                       {"loadId", Value(int64_t{3})},
                       {"failureCode", Value("http_error")},
                       {"httpStatus", Value(int64_t{404})}};
  const EncodableMap expected_state{
      {EncodableValue("type"), EncodableValue("state")},
      {EncodableValue("state"), EncodableValue("error")},
      {EncodableValue("message"), EncodableValue("Media playback failed")},
      {EncodableValue("loadId"), EncodableValue(int64_t{3})},
      {EncodableValue("failureCode"), EncodableValue("http_error")},
      {EncodableValue("httpStatus"), EncodableValue(int64_t{404})}};
  Check(EncodeEvent(lineup::ToEncodableMap(state)) == EncodeEvent(expected_state),
        "state event bytes are unchanged");

  const ValueMap property{
      {"type", Value("property")}, {"name", Value("track-list")},
      {"value", Value(ValueList{Value(ValueMap{{"id", Value(int64_t{1})},
                                               {"type", Value("sub")},
                                               {"selected", Value(false)}})})},
      {"loadId", Value(int64_t{2})}};
  const EncodableMap expected_property{
      {EncodableValue("type"), EncodableValue("property")},
      {EncodableValue("name"), EncodableValue("track-list")},
      {EncodableValue("value"),
       EncodableValue(EncodableList{EncodableValue(EncodableMap{
           {EncodableValue("id"), EncodableValue(int64_t{1})},
           {EncodableValue("type"), EncodableValue("sub")},
           {EncodableValue("selected"), EncodableValue(false)}})})},
      {EncodableValue("loadId"), EncodableValue(int64_t{2})}};
  Check(EncodeEvent(lineup::ToEncodableMap(property)) == EncodeEvent(expected_property),
        "property event bytes are unchanged");

  const ValueMap display{{"type", Value("display")}, {"reason", Value()},
                         {"revision", Value(int64_t{0})}, {"wrote", Value(true)},
                         {"time", Value(42.0)}};
  const EncodableMap expected_display{
      {EncodableValue("type"), EncodableValue("display")},
      {EncodableValue("reason"), EncodableValue()},
      {EncodableValue("revision"), EncodableValue(int64_t{0})},
      {EncodableValue("wrote"), EncodableValue(true)},
      {EncodableValue("time"), EncodableValue(42.0)}};
  Check(EncodeEvent(lineup::ToEncodableMap(display)) == EncodeEvent(expected_display),
        "null, bool, and double event values are unchanged");
  Check(std::holds_alternative<int64_t>(lineup::ToEncodableValue(Value(int64_t{5}))),
        "integers are not narrowed");
}

}  // namespace

int main() {
  Arguments();
  Events();
  return 0;
}
