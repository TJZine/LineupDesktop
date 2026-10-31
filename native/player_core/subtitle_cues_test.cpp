#include "player_core/subtitle_cues.h"

#include <cstdlib>
#include <iostream>
#include <string>

using namespace lineup::player;
namespace {
void Check(bool ok, const char* reason) {
  if (!ok) { std::cerr << reason << '\n'; std::exit(1); }
}
const ValueMap& Map(const Value& v) { return std::get<ValueMap>(v); }
const ValueList& List(const Value& v) { return std::get<ValueList>(v); }
const ValueList& Lines(const Value& cue) { return List(Map(cue).at("lines")); }
const ValueMap& Segment(const Value& cue, size_t line = 0, size_t segment = 0) {
  return Map(List(Lines(cue)[line])[segment]);
}
std::string Text(const ValueList& cues) {
  std::string result;
  for (const auto& cue : cues) for (const auto& line : Lines(cue))
    for (const auto& segment : List(line)) result += std::get<std::string>(Map(segment).at("text"));
  return result;
}
}
int main() {
  Check(ClassifySubtitleCodec("") == SubtitleCodec::none, "no selection");
  Check(ClassifySubtitleCodec("ass") == SubtitleCodec::ass, "native ASS");
  for (auto name : {"hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub", "dvb_teletext", "arib_caption"})
    Check(ClassifySubtitleCodec(name) == SubtitleCodec::image, "image/default bitmap codec");
  for (auto name : {"ssa", "subrip", "webvtt", "mov_text", "eia_608", "unknown-text"})
    Check(ClassifySubtitleCodec(name) == SubtitleCodec::text, "converted text including lavf SSA");
  auto cues = ParseSubtitleCues(R"(one\N{\i1}two\hwords{\i0\b1}bold{\b0\u1}under{\u0}end)", false);
  Check(cues.size() == 1 && Lines(cues[0]).size() == 2, "line breaks");
  Check(Text(cues) == "onetwo wordsboldunderend", "escapes and blocks");
  Check(Segment(cues[0], 1).at("italic") == Value(true), "italic flag");
  Check(Segment(cues[0], 1, 1).at("bold") == Value(true), "bold flag");
  Check(Segment(cues[0], 1, 2).at("underline") == Value(true), "underline flag");
  Check(Segment(cues[0], 1, 3).size() == 1, "style toggles off");
  for (int n = 1; n <= 9; ++n) {
    cues = ParseSubtitleCues("{\\an" + std::to_string(n) + "}fixture", false);
    Check(Map(cues[0]).at("align") == Value(n), "all keypad alignments");
  }
  cues = ParseSubtitleCues("a{nested{\\b1}bad}b{\\unknown tag}c{unfinished", false);
  Check(Text(cues) == "abc" && Segment(cues[0]).size() == 1, "nested/malformed/unknown blocks removed");
  Check(Text(ParseSubtitleCues("a\\nb\nc", false)) == "abc", "soft and event newlines");
  for (auto tag : {"\\pos(1,2)", "\\move(1,2,3,4)", "\\org(1,2)", "\\clip(1,2,3,4)", "\\iclip(1,2,3,4)", "\\p1"}) {
    const std::string event = std::string("{ ") + tag + "}sign";
    Check(ParseSubtitleCues(event, true).empty(), "ASS signs and drawing events excluded");
    Check(!ParseSubtitleCues(event, false).empty(), "converted text retained despite positioning tags");
  }
  Check(Text(ParseSubtitleCues("{\\pos(1,2)}sign\n{\\i1}dialogue\n{\\p1}m 0 0 l 1 1", true)) == "dialogue", "ASS mixed event filtering");
  for (auto tag : {R"(\p0)", R"(\p000)", R"(\p+0)", R"(\p-0)",
                   R"(\p-1)", R"(\p)", R"(\pbo2)", R"(\painter1)",
                   R"(\position(1,2))", R"(\movements)", R"(\rpos)",
                   R"(\fnposition)"}) {
    const std::string event = std::string("{") + tag + "}dialogue";
    Check(Text(ParseSubtitleCues(event, true)) == "dialogue",
          "nonpositive drawing resets and unrelated tag/style names retain dialogue");
  }
  cues = ParseSubtitleCues(R"({\p0\an8\i1\b1\u1}dialogue)", true);
  Check(cues.size() == 1 && Map(cues[0]).at("align") == Value(8) &&
        Text(cues) == "dialogue" && Segment(cues[0]).at("italic") == Value(true) &&
        Segment(cues[0]).at("bold") == Value(true) &&
        Segment(cues[0]).at("underline") == Value(true),
        "p0 preserves dialogue emphasis and alignment");
  for (auto event : {R"({\p1}drawing{\p0}dialogue)",
                     R"(dialogue{\p0\p2}drawing{\p0}tail)",
                     R"({\p+1}drawing)", R"({\p 2}drawing)",
                     R"({\p0001}drawing)",
                     R"({\p999999999999999999999999999999}drawing)"}) {
    Check(ParseSubtitleCues(event, true).empty(),
          "any positive drawing mode excludes the whole event despite later resets");
  }
  const std::string literal = R"(literal \p1 and \pos(1,2) outside overrides)";
  Check(Text(ParseSubtitleCues(literal, true)) == literal,
        "literal backslashes outside override blocks are dialogue");
  Check(Text(ParseSubtitleCues("{\\p1}drawing{\\p0}tail\n{\\p0\\i1}dialogue", true)) == "dialogue",
        "drawing exclusion stays event-scoped and preserves adjacent reset dialogue");
  Check(Text(ParseSubtitleCues("Fixture café 日本語 😀", false)) == "Fixture café 日本語 😀", "UTF-8 kept");
  cues = ParseSubtitleCues(std::string(4095, 'a') + "😀tail", false);
  Check(Text(cues).size() == 4095, "truncation never splits scalar");
  Check(Text(ParseSubtitleCues(std::string(5000, 'a'), false)).size() == 4096, "4KiB text cap");
  std::string many;
  for (int i = 0; i < 20; ++i) many += "line\n";
  Check(ParseSubtitleCues(many, false).size() == 8, "eight cue cap");
  many.clear();
  for (int i = 0; i < 20; ++i) many += "line\\N";
  cues = ParseSubtitleCues(many, false);
  Check(Lines(cues[0]).size() == 8, "eight line cap");
  many.clear();
  for (int i = 0; i < 100; ++i) many += i % 2 ? "{\\i1}x" : "{\\i0}x";
  cues = ParseSubtitleCues(many, false);
  Check(List(Lines(cues[0])[0]).size() == 32, "32 segment cap");
  Check(Text(ParseSubtitleCues(std::string("a\xc0\xaf\xed\xa0\x80") + "b", false)) == "ab", "invalid UTF-8 discarded");
  Check(ParseSubtitleCues("{\\b1}", false).empty(), "empty override-only cues omitted");
}
