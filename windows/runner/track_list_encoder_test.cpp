#include "track_list_encoder.h"

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

void Check(bool condition, const char* obligation) {
  if (!condition) {
    std::cerr << obligation << '\n';
    std::exit(1);
  }
}

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

mpv_node String(const char* value) {
  mpv_node node{};
  node.format = MPV_FORMAT_STRING;
  node.u.string = const_cast<char*>(value);
  return node;
}

mpv_node Int(int64_t value) {
  mpv_node node{};
  node.format = MPV_FORMAT_INT64;
  node.u.int64 = value;
  return node;
}

mpv_node Flag(bool value) {
  mpv_node node{};
  node.format = MPV_FORMAT_FLAG;
  node.u.flag = value ? 1 : 0;
  return node;
}

mpv_node List(mpv_node_list* value, mpv_format format) {
  mpv_node node{};
  node.format = format;
  node.u.list = value;
  return node;
}

EncodableList Encode(std::vector<mpv_node> entries) {
  mpv_node_list list{static_cast<int>(entries.size()), entries.data(), nullptr};
  return std::get<EncodableList>(
      lineup::EncodeTrackList(List(&list, MPV_FORMAT_NODE_ARRAY)));
}

const EncodableValue& At(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(key));
  Check(found != map.end(),
        "found != map.end()");
  return found->second;
}

void CheckIdentity(const EncodableMap& map, int64_t id, const char* type,
                   bool selected) {
  Check(std::get<int64_t>(At(map, "id")) == id,
        "std::get<int64_t>(At(map, \"id\")) == id");
  Check(std::get<std::string>(At(map, "type")) == type,
        "std::get<std::string>(At(map, \"type\")) == type");
  Check(std::get<bool>(At(map, "selected")) == selected,
        "std::get<bool>(At(map, \"selected\")) == selected");
}

void CheckBounds() {
  std::string oversized(8192, 'x');
  char* keys[] = {const_cast<char*>("id"),
                  const_cast<char*>("type"),
                  const_cast<char*>("selected"),
                  const_cast<char*>("title"),
                  const_cast<char*>("lang"),
                  const_cast<char*>("codec"),
                  const_cast<char*>("demux-channels"),
                  const_cast<char*>("demux-channel-count"),
                  const_cast<char*>("forced"),
                  const_cast<char*>("external"),
                  const_cast<char*>("hearing-impaired"),
                  const_cast<char*>("visual-impaired"),
                  const_cast<char*>("commentary")};
  mpv_node values[] = {Int(1),
                       String("audio"),
                       Flag(false),
                       String(oversized.c_str()),
                       String(oversized.c_str()),
                       String(oversized.c_str()),
                       String(oversized.c_str()),
                       Int(6),
                       Flag(true),
                       Flag(false),
                       Flag(true),
                       Flag(false),
                       Flag(true)};
  mpv_node_list map{13, values, keys};
  const auto track = List(&map, MPV_FORMAT_NODE_MAP);
  mpv_node late_values[] = {
      Int(256),      String("sub"),    Flag(true),       String("synthetic"),
      String("eng"), String("subrip"), String("stereo"), Int(2),
      Flag(false),   Flag(true),       Flag(false),      Flag(true),
      Flag(false)};
  mpv_node_list late_map{13, late_values, keys};
  std::vector<mpv_node> entries(256, track);
  entries.back() = List(&late_map, MPV_FORMAT_NODE_MAP);
  for (const int size : {256, 257}) {
    entries.resize(size, track);
    const auto result = Encode(entries);
    Check(result.size() == 256,
          "result.size() == 256");
    CheckIdentity(std::get<EncodableMap>(result.front()), 1, "audio", false);
    size_t bytes = 0;
    for (size_t i = 0; i < result.size(); ++i) {
      const auto& encoded = std::get<EncodableMap>(result[i]);
      for (const char* key : {"title", "lang", "codec", "demux-channels"}) {
        const auto found = encoded.find(EncodableValue(key));
        if (i < 4) {
          Check(found != encoded.end(),
                "found != encoded.end()");
          const auto& text = std::get<std::string>(found->second);
          Check(text.size() == 4096,
                "text.size() == 4096");
          bytes += text.size();
        } else {
          Check(found == encoded.end(),
                "found == encoded.end()");
        }
      }
    }
    Check(bytes == 64 * 1024,
          "bytes == 64 * 1024");
    const auto& late = std::get<EncodableMap>(result.back());
    CheckIdentity(late, 256, "sub", true);
    Check(late.size() == 9,
          "late.size() == 9");
    Check(std::get<int64_t>(At(late, "demux-channel-count")) == 2,
          "std::get<int64_t>(At(late, \"demux-channel-count\")) == 2");
    Check(!std::get<bool>(At(late, "forced")),
          "!std::get<bool>(At(late, \"forced\"))");
    Check(std::get<bool>(At(late, "external")),
          "std::get<bool>(At(late, \"external\"))");
    Check(!std::get<bool>(At(late, "hearing-impaired")),
          "!std::get<bool>(At(late, \"hearing-impaired\"))");
    Check(std::get<bool>(At(late, "visual-impaired")),
          "std::get<bool>(At(late, \"visual-impaired\"))");
    Check(!std::get<bool>(At(late, "commentary")),
          "!std::get<bool>(At(late, \"commentary\"))");
  }
  entries.assign(257, mpv_node{});
  entries.back() = track;
  Check(Encode(entries).empty(),
        "Encode(entries).empty()");

  late_values[0] = Int(0);
  entries.assign(20, List(&late_map, MPV_FORMAT_NODE_MAP));
  entries.insert(entries.end(), 4, track);
  const auto accepted = Encode(entries);
  Check(accepted.size() == 4,
        "accepted.size() == 4");
  Check(std::get<std::string>(
             At(std::get<EncodableMap>(accepted.back()), "demux-channels"))
             .size() == 4096,
        "std::get<std::string>( At(std::get<EncodableMap>(accepted.back()), \"demux-channels\")) .size() == 4096");
}

void CheckStrings() {
  char* keys[] = {const_cast<char*>("id"), const_cast<char*>("type"),
                  const_cast<char*>("selected"), const_cast<char*>("title")};
  mpv_node values[] = {Int(1), String("video"), Flag(true), String("")};
  mpv_node_list map{4, values, keys};
  auto track = List(&map, MPV_FORMAT_NODE_MAP);
  for (const std::string sequence :
       {std::string("\xC2\xA2"), std::string("\xE2\x82\xAC"),
        std::string("\xF0\x9F\x98\x80")}) {
    for (size_t room = 0; room <= sequence.size(); ++room) {
      const std::string prefix(4096 - room, 'a');
      const std::string input = prefix + sequence + "z";
      values[3] = String(input.c_str());
      const auto result = Encode({track});
      const auto& encoded = std::get<EncodableMap>(result.front());
      Check(std::get<std::string>(At(encoded, "title")) ==
             (room == sequence.size() ? prefix + sequence : prefix),
            "std::get<std::string>(At(encoded, \"title\")) == (room == sequence.size() ? prefix + sequence : prefix)");
    }
  }
  for (const char* invalid :
       {"\x80", "\xC0\xAF", "\xE0\x80\xAF", "\xED\xA0\x80", "\xF0\x80\x80\xAF",
        "\xF4\x90\x80\x80", "\xF5\x80\x80\x80", "\xC2", "\xE2\x82",
        "\xF0\x9F\x98", "a\xC2z"}) {
    values[3] = String(invalid);
    Check(std::get<EncodableMap>(Encode({track}).front()).size() == 3,
          "std::get<EncodableMap>(Encode({track}).front()).size() == 3");
  }
  const std::string invalid_at_cap = std::string(4095, 'a') + "\x80";
  values[3] = String(invalid_at_cap.c_str());
  Check(std::get<EncodableMap>(Encode({track}).front()).size() == 3,
        "std::get<EncodableMap>(Encode({track}).front()).size() == 3");
  values[3] = String("");
  Check(std::get<std::string>(
             At(std::get<EncodableMap>(Encode({track}).front()), "title"))
             .empty(),
        "std::get<std::string>( At(std::get<EncodableMap>(Encode({track}).front()), \"title\")) .empty()");

  const std::string full(4096, 'a');
  const std::string almost_full(4095, 'a');
  values[3] = String(full.c_str());
  std::vector<mpv_node> entries(15, track);
  mpv_node tail_values[] = {Int(2), String("audio"), Flag(true),
                            String(almost_full.c_str())};
  mpv_node_list tail_map{4, tail_values, keys};
  entries.push_back(List(&tail_map, MPV_FORMAT_NODE_MAP));
  mpv_node unicode_values[] = {Int(3), String("sub"), Flag(true),
                               String("\xC2\xA2")};
  mpv_node_list unicode_map{4, unicode_values, keys};
  entries.push_back(List(&unicode_map, MPV_FORMAT_NODE_MAP));
  mpv_node ascii_values[] = {Int(4), String("audio"), Flag(false), String("b")};
  mpv_node_list ascii_map{4, ascii_values, keys};
  entries.push_back(List(&ascii_map, MPV_FORMAT_NODE_MAP));
  const auto result = Encode(entries);
  Check(std::get<EncodableMap>(result[16]).size() == 3,
        "std::get<EncodableMap>(result[16]).size() == 3");
  Check(std::get<std::string>(
             At(std::get<EncodableMap>(result[17]), "title")) == "b",
        "std::get<std::string>( At(std::get<EncodableMap>(result[17]), \"title\")) == \"b\"");

  unicode_values[3] = String(invalid_at_cap.c_str());
  entries.assign(20, List(&unicode_map, MPV_FORMAT_NODE_MAP));
  entries.insert(entries.end(), 16, track);
  const auto uncharged = Encode(entries);
  Check(std::get<EncodableMap>(uncharged.front()).size() == 3,
        "std::get<EncodableMap>(uncharged.front()).size() == 3");
  Check(std::get<std::string>(
             At(std::get<EncodableMap>(uncharged.back()), "title"))
             .size() == 4096,
        "std::get<std::string>( At(std::get<EncodableMap>(uncharged.back()), \"title\")) .size() == 4096");
}

void CheckMalformed() {
  char* keys[] = {const_cast<char*>("id"), const_cast<char*>("type"),
                  const_cast<char*>("selected"), const_cast<char*>("title")};
  mpv_node values[] = {Int(1), String("audio"), Flag(true),
                       String("synthetic")};
  mpv_node_list map{4, values, keys};
  auto track = List(&map, MPV_FORMAT_NODE_MAP);
  mpv_node floating{};
  floating.format = MPV_FORMAT_DOUBLE;
  floating.u.double_ = 1.0;
  for (const auto invalid :
       {Int(0), Int(-1), String("1"), floating, Flag(true), mpv_node{}}) {
    values[0] = invalid;
    Check(Encode({track}).empty(),
          "Encode({track}).empty()");
  }
  values[0] = Int(1);
  for (const auto invalid :
       {String("Audio"), String("subtitle"), String("audio "), String(""),
        String(nullptr), Int(1), mpv_node{}}) {
    values[1] = invalid;
    Check(Encode({track}).empty(),
          "Encode({track}).empty()");
  }
  values[1] = String("audio");
  for (const auto invalid : {Int(1), String("true"), floating, mpv_node{}}) {
    values[2] = invalid;
    Check(Encode({track}).empty(),
          "Encode({track}).empty()");
  }
  values[2] = Flag(true);
  for (int i = 0; i < 3; ++i) {
    char* saved = keys[i];
    keys[i] = nullptr;
    Check(Encode({track}).empty(),
          "Encode({track}).empty()");
    keys[i] = saved;
  }
  for (const char* key :
       {"title", "lang", "codec", "demux-channels", "demux-channel-count",
        "forced", "external", "hearing-impaired", "visual-impaired",
        "commentary"}) {
    keys[3] = const_cast<char*>(key);
    for (const auto invalid : {mpv_node{}, floating, String(nullptr)}) {
      values[3] = invalid;
      Check(std::get<EncodableMap>(Encode({track}).front()).size() == 3,
            "std::get<EncodableMap>(Encode({track}).front()).size() == 3");
    }
  }
  for (const char* key : {"title", "lang", "codec", "demux-channels"}) {
    keys[3] = const_cast<char*>(key);
    for (const auto invalid : {Int(1), Flag(false)}) {
      values[3] = invalid;
      Check(std::get<EncodableMap>(Encode({track}).front()).size() == 3,
            "std::get<EncodableMap>(Encode({track}).front()).size() == 3");
    }
  }
  keys[3] = const_cast<char*>("demux-channel-count");
  for (const auto invalid : {Int(0), Int(-1), String("2"), Flag(true)}) {
    values[3] = invalid;
    Check(std::get<EncodableMap>(Encode({track}).front()).size() == 3,
          "std::get<EncodableMap>(Encode({track}).front()).size() == 3");
  }
  for (const char* key : {"forced", "external", "hearing-impaired",
                          "visual-impaired", "commentary"}) {
    keys[3] = const_cast<char*>(key);
    for (const auto invalid : {Int(0), Int(1), String("false")}) {
      values[3] = invalid;
      Check(std::get<EncodableMap>(Encode({track}).front()).size() == 3,
            "std::get<EncodableMap>(Encode({track}).front()).size() == 3");
    }
    for (const bool flag : {false, true}) {
      values[3] = Flag(flag);
      Check(std::get<bool>(At(std::get<EncodableMap>(Encode({track}).front()),
                               key)) == flag,
            "std::get<bool>(At(std::get<EncodableMap>(Encode({track}).front()), key)) == flag");
    }
  }
  for (const char* key :
       {"codec-desc", "codec-profile", "default", "external-filename",
        "ff-index", "src-id", "program-id", "demux-bitrate", "demux-samplerate",
        "decoder", "unlisted-sentinel"}) {
    keys[3] = const_cast<char*>(key);
    values[3] = String("excluded-sentinel");
    Check(std::get<EncodableMap>(Encode({track}).front()).size() == 3,
          "std::get<EncodableMap>(Encode({track}).front()).size() == 3");
  }
  mpv_node_list no_keys{4, values, nullptr};
  mpv_node_list no_values{4, nullptr, keys};
  mpv_node_list negative{-1, values, keys};
  mpv_node_list empty{0, nullptr, nullptr};
  const auto result =
      Encode({mpv_node{}, String("invalid"), List(nullptr, MPV_FORMAT_NODE_MAP),
              List(&no_keys, MPV_FORMAT_NODE_MAP),
              List(&no_values, MPV_FORMAT_NODE_MAP),
              List(&negative, MPV_FORMAT_NODE_MAP), track});
  Check(result.size() == 1,
        "result.size() == 1");
  CheckIdentity(std::get<EncodableMap>(result.front()), 1, "audio", true);
  for (const auto invalid :
       {mpv_node{}, track, List(nullptr, MPV_FORMAT_NODE_ARRAY),
        List(&empty, MPV_FORMAT_NODE_ARRAY),
        List(&no_values, MPV_FORMAT_NODE_ARRAY),
        List(&negative, MPV_FORMAT_NODE_ARRAY)}) {
    Check(std::get<EncodableList>(lineup::EncodeTrackList(invalid)).empty(),
          "std::get<EncodableList>(lineup::EncodeTrackList(invalid)).empty()");
  }
}

}

int main() {
  CheckBounds();
  CheckStrings();
  CheckMalformed();
  return 0;
}
