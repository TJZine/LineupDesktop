#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

#include <mach-o/dyld.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <atomic>
#include <csignal>
#include <chrono>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#import "LineupNativePlayer.h"
#include "player_core/mpv_operations.h"
#include "player_core/session_playlist.h"
#include "../authenticated-reference/session_policy_test.h"

namespace {
using Clock = std::chrono::steady_clock;
const char* test_ca = nullptr;
mpv_handle* observed_client = nullptr;
std::string policy_status_path;
std::atomic<bool> policy_status_attempted{false};
std::atomic<bool> policy_status_written{false};
Clock::time_point origin;
std::atomic<int> load_commands{0};
std::atomic<int> seek_commands{0};
std::atomic<bool> load_map_valid{true};
std::atomic<bool> force_hls{false};
std::atomic<bool> destroyed{false};
std::atomic<int> nested_forbidden_logs{0};
std::atomic<int> redirect_count{0};
std::atomic<int> curl_redirect_refused_logs{0};
enum class StructuralFailure {
  none, event_queue_overflow, event_bound, status_write_failed, core_correlation,
  core_command, core_unknown_failure, command_rejected, event_shape, clock_event_shape, invalid_load_map,
  global_selector, unexpected_seek,
};
std::atomic<StructuralFailure> structural_failure{StructuralFailure::none};
std::atomic<int> end_file_errors{0};
void Structural(StructuralFailure code) {
  auto expected = StructuralFailure::none;
  structural_failure.compare_exchange_strong(expected, code);
}
const char* StructuralCode(StructuralFailure value) {
  switch (value) {
    case StructuralFailure::none: return "none";
    case StructuralFailure::event_queue_overflow: return "event_queue_overflow";
    case StructuralFailure::event_bound: return "event_bound";
    case StructuralFailure::status_write_failed: return "status_write_failed";
    case StructuralFailure::core_correlation: return "core_correlation";
    case StructuralFailure::core_command: return "core_command";
    case StructuralFailure::core_unknown_failure: return "core_unknown_failure";
    case StructuralFailure::command_rejected: return "command_rejected";
    case StructuralFailure::event_shape: return "event_shape";
    case StructuralFailure::clock_event_shape: return "clock_event_shape";
    case StructuralFailure::invalid_load_map: return "invalid_load_map";
    case StructuralFailure::global_selector: return "global_selector";
    case StructuralFailure::unexpected_seek: return "unexpected_seek";
  }
  return "event_shape";
}
volatile std::sig_atomic_t stop_requested = 0;
void StopRequested(int) { stop_requested = 1; }

struct Snapshot {
  std::optional<double> position;
  std::optional<double> demuxer_start;
  std::optional<double> audio;
  std::optional<double> duration;
  std::optional<double> decoded_width;
  std::optional<double> decoded_height;
  std::optional<double> output_width;
  std::optional<double> output_height;
  bool vo = false;
  bool paused = false;
  bool seeking = true;
  bool rebase = false;
  bool format_whitelist = false;
  bool protocol_whitelist = false;
  bool lavf_selected = false;
  bool reference_access = false;
  bool redirect_zero = false;
  bool tls_verify = false;
  int picture_type = 0;
  double elapsed = 0;
  bool Qualified() const {
    return position && demuxer_start && vo && rebase && format_whitelist && protocol_whitelist && lavf_selected && reference_access && redirect_zero && tls_verify && !seeking &&
        decoded_width == 96 && decoded_height == 54 &&
        output_width == 96 && output_height == 54 && picture_type != 0;
  }
};
struct Observations {
  std::mutex mutex;
  std::optional<Snapshot> loaded;
  std::optional<Snapshot> first_restart;
  std::optional<Snapshot> latest;
  int event_count = 0;
  int restart_count = 0;
  bool ended = false;
  int64_t entry_id = -1;
  bool end_fence = false;
  int end_reason = -1;
  bool failed = false;
  bool format_whitelist_observed = false;
  bool protocol_whitelist_observed = false;
  bool lavf_selected_observed = false;
  bool reference_access_observed = false;
  bool redirect_zero_observed = false;
  bool tls_verify_observed = false;
};
Observations observation;

double Elapsed() {
  return std::chrono::duration<double>(Clock::now() - origin).count();
}
std::optional<double> Number(mpv_handle* client, const char* name) {
  double value = 0;
  if (mpv_get_property(client, name, MPV_FORMAT_DOUBLE, &value) < 0 || !std::isfinite(value))
    return std::nullopt;
  return value;
}
bool Flag(mpv_handle* client, const char* name) {
  int value = 0;
  return mpv_get_property(client, name, MPV_FORMAT_FLAG, &value) >= 0 && value;
}
Snapshot ReadSnapshot(mpv_handle* client) {
  Snapshot value;
  value.position = Number(client, "time-pos");
  value.demuxer_start = Number(client, "demuxer-start-time");
  value.audio = Number(client, "audio-pts");
  value.duration = Number(client, "duration");
  value.decoded_width = Number(client, "video-dec-params/w");
  value.decoded_height = Number(client, "video-dec-params/h");
  value.output_width = Number(client, "video-out-params/w");
  value.output_height = Number(client, "video-out-params/h");
  value.vo = Flag(client, "vo-configured");
  value.paused = Flag(client, "pause");
  value.seeking = Flag(client, "seeking");
  value.rebase = Flag(client, "options/rebase-start-time");
  char* picture = nullptr;
  if (mpv_get_property(client, "video-frame-info/picture-type", MPV_FORMAT_STRING, &picture) >= 0 && picture) {
    if (std::strcmp(picture, "I") == 0) value.picture_type = 1;
    if (std::strcmp(picture, "P") == 0) value.picture_type = 2;
    if (std::strcmp(picture, "B") == 0) value.picture_type = 3;
    mpv_free(picture);
  }
  mpv_node options{};
  if (mpv_get_property(client, "options/demuxer-lavf-o", MPV_FORMAT_NODE, &options) >= 0) {
    if (options.format == MPV_FORMAT_NODE_MAP && options.u.list && options.u.list->num == 2) {
      for (int index = 0; index < options.u.list->num; ++index) {
        const auto& item = options.u.list->values[index];
        const char* key = options.u.list->keys ? options.u.list->keys[index] : nullptr;
        if (!key || item.format != MPV_FORMAT_STRING || !item.u.string) continue;
        if (std::strcmp(key, "format_whitelist") == 0 && std::strcmp(item.u.string, "hls,mov") == 0)
          value.format_whitelist = true;
        if (std::strcmp(key, "protocol_whitelist") == 0 && std::strcmp(item.u.string, "https,tls,tcp") == 0)
          value.protocol_whitelist = true;
      }
    }
    mpv_free_node_contents(&options);
  }
  char* demuxer = nullptr;
  if (mpv_get_property(client, "options/demuxer", MPV_FORMAT_STRING, &demuxer) >= 0 && demuxer) {
    value.lavf_selected = std::strcmp(demuxer, "lavf") == 0;
    mpv_free(demuxer);
  }
  value.reference_access = Flag(client, "options/access-references");
  value.redirect_zero = Number(client, "options/curl-max-redirects") == 0;
  value.tls_verify = Flag(client, "options/tls-verify");
  value.elapsed = Elapsed();
  return value;
}

struct RestorationSnapshot {
  bool references_checked = false, references_restored = false;
  bool redirects_checked = false, redirects_restored = false;
  bool demuxer_checked = false, demuxer_restored = false;
  bool lavf_checked = false, lavf_restored = false;
  bool end_fence = false;
  int end_reason = -1;
  bool idle_checked = false, idle = false;
  bool count_checked = false;
  int64_t count = -1;
  bool Checked() const {
    return references_checked && redirects_checked && demuxer_checked && lavf_checked;
  }
  bool Restored() const {
    return Checked() && references_restored && redirects_restored && demuxer_restored && lavf_restored;
  }
  bool Complete(bool expected_error, double elapsed) const {
    return elapsed <= 1 && end_fence &&
        end_reason == (expected_error ? MPV_END_FILE_REASON_ERROR : MPV_END_FILE_REASON_STOP) &&
        idle_checked && idle && count_checked && count == 0 && Restored();
  }
};
RestorationSnapshot ReadRestoration(mpv_handle* client, const lineup::fixture::SessionPolicy& baseline) {
  RestorationSnapshot value;
  if (!client) return value;
  {
    std::lock_guard<std::mutex> lock(observation.mutex);
    value.end_fence = observation.end_fence;
    value.end_reason = observation.end_reason;
  }
  int references = 0, idle = 0;
  int64_t redirects = 0;
  value.references_checked = baseline.valid && mpv_get_property(client, "options/access-references", MPV_FORMAT_FLAG, &references) >= 0;
  value.references_restored = value.references_checked && references == baseline.references;
  value.redirects_checked = baseline.valid && mpv_get_property(client, "options/curl-max-redirects", MPV_FORMAT_INT64, &redirects) >= 0;
  value.redirects_restored = value.redirects_checked && redirects == baseline.redirects;
  char* selector = nullptr;
  value.demuxer_checked = baseline.valid && mpv_get_property(client, "options/demuxer", MPV_FORMAT_STRING, &selector) >= 0;
  value.demuxer_restored = value.demuxer_checked && std::string(selector ? selector : "") == baseline.demuxer;
  if (selector) mpv_free(selector);
  mpv_node node{};
  if (baseline.valid && mpv_get_property(client, "options/demuxer-lavf-o", MPV_FORMAT_NODE, &node) >= 0) {
    std::map<std::string, std::string> options;
    value.lavf_checked = node.format == MPV_FORMAT_NODE_MAP && node.u.list && node.u.list->num >= 0 && node.u.list->num <= 64;
    if (value.lavf_checked) for (int index = 0; index < node.u.list->num; ++index) {
      const auto& list = *node.u.list;
      if (!list.keys || !list.keys[index] || !list.values || list.values[index].format != MPV_FORMAT_STRING ||
          !list.values[index].u.string || !options.emplace(list.keys[index], list.values[index].u.string).second) {
        value.lavf_checked = false;
        break;
      }
    }
    value.lavf_restored = value.lavf_checked && options == baseline.lavf;
    mpv_free_node_contents(&node);
  }
  value.idle_checked = mpv_get_property(client, "idle-active", MPV_FORMAT_FLAG, &idle) >= 0;
  value.idle = value.idle_checked && idle;
  value.count_checked = mpv_get_property(client, "playlist-count", MPV_FORMAT_INT64, &value.count) >= 0;
  return value;
}
const char* EndReason(int reason) {
  switch (reason) {
    case MPV_END_FILE_REASON_STOP: return "stop";
    case MPV_END_FILE_REASON_ERROR: return "error";
    case MPV_END_FILE_REASON_EOF: return "eof";
    case -1: return "none";
    default: return "other";
  }
}
NSDictionary* JsonRestoration(const RestorationSnapshot& value) {
  return @{@"referencesChecked": @(value.references_checked), @"referencesRestored": @(value.references_restored),
      @"redirectsChecked": @(value.redirects_checked), @"redirectsRestored": @(value.redirects_restored),
      @"demuxerChecked": @(value.demuxer_checked), @"demuxerRestored": @(value.demuxer_restored),
      @"lavfChecked": @(value.lavf_checked), @"lavfRestored": @(value.lavf_restored),
      @"endFenceSeen": @(value.end_fence), @"endReason": @(EndReason(value.end_reason)),
      @"idleChecked": @(value.idle_checked), @"idle": value.idle_checked ? (id)@(value.idle) : [NSNull null],
      @"playlistCountChecked": @(value.count_checked), @"playlistCount": value.count_checked ? (id)@(value.count) : [NSNull null]};
}

bool IsSessionLoadMap(const mpv_node* command) {
  if (!command || command->format != MPV_FORMAT_NODE_ARRAY || !command->u.list || command->u.list->num != 5)
    return false;
  const auto* args = command->u.list->values;
  if (args[0].format != MPV_FORMAT_STRING || !args[0].u.string || std::strcmp(args[0].u.string, "loadfile") != 0 ||
      args[1].format != MPV_FORMAT_STRING || !args[1].u.string ||
      args[4].format != MPV_FORMAT_NODE_MAP || !args[4].u.list || args[4].u.list->num != 4)
    return false;
  const std::string uri = args[1].u.string;
  constexpr std::string_view prefix = "lineup-session://";
  if (uri.size() != prefix.size() + 32 + 5 || uri.rfind(prefix, 0) != 0 ||
      uri.substr(uri.size() - 5) != ".m3u8") return false;
  for (size_t index = prefix.size(); index < prefix.size() + 32; ++index)
    if (!((uri[index] >= '0' && uri[index] <= '9') || (uri[index] >= 'a' && uri[index] <= 'f'))) return false;
  bool references = false, redirects = false, restricted = false, selected = false;
  const auto& options = *args[4].u.list;
  for (int i = 0; i < options.num; ++i) {
    if (!options.keys || !options.keys[i] || options.values[i].format != MPV_FORMAT_STRING || !options.values[i].u.string)
      return false;
    if (std::strcmp(options.keys[i], "access-references") == 0 &&
        std::strcmp(options.values[i].u.string, "yes") == 0 && !references) references = true;
    else if (std::strcmp(options.keys[i], "curl-max-redirects") == 0 &&
             std::strcmp(options.values[i].u.string, "0") == 0 && !redirects) redirects = true;
    else if (std::strcmp(options.keys[i], "demuxer") == 0 &&
             std::strcmp(options.values[i].u.string, "lavf") == 0 && !selected) selected = true;
    else if (std::strcmp(options.keys[i], "demuxer-lavf-o") == 0 &&
             std::strcmp(options.values[i].u.string, "format_whitelist=%7%hls,mov,protocol_whitelist=%13%https,tls,tcp") == 0 && !restricted)
      restricted = true;
    else return false;
  }
  return references && redirects && restricted && selected;
}
int CommandNode(mpv_handle* client, mpv_node* command, mpv_node* result) {
  ++load_commands;
  if (!IsSessionLoadMap(command)) { load_map_valid.store(false); Structural(StructuralFailure::invalid_load_map); }
  return mpv_command_node(client, command, result);
}
int Command(mpv_handle* client, const char** args) {
  if (args && args[0] && std::strcmp(args[0], "seek") == 0) { ++seek_commands; Structural(StructuralFailure::unexpected_seek); }
  return mpv_command(client, args);
}
int SetOption(mpv_handle* client, const char* name, const char* value) {
  if (std::strcmp(name, "demuxer-lavf-format") == 0 || std::strcmp(name, "demuxer") == 0) {
    force_hls.store(true);
    Structural(StructuralFailure::global_selector);
  }
  return mpv_set_option_string(client, name, value);
}
mpv_handle* Create() {
  auto* client = mpv_create();
  if (client && mpv_set_option_string(client, "tls-ca-file", test_ca) < 0) {
    mpv_terminate_destroy(client);
    return nullptr;
  }
  observed_client = client;
  return client;
}
int Initialize(mpv_handle* client) {
  for (const char* name : {"vo", "ao"}) {
    const int status = mpv_set_option_string(client, name, "null");
    if (status < 0) return status;
  }
  return mpv_initialize(client);
}
void Destroy(mpv_handle* client) {
  mpv_terminate_destroy(client);
  destroyed.store(true);
}
bool PrivatePolicyMatches(const Snapshot& value) {
  return value.format_whitelist && value.protocol_whitelist && value.lavf_selected &&
      value.reference_access && value.redirect_zero && value.tls_verify;
}
void RememberPolicy(const Snapshot& value) {
  observation.format_whitelist_observed |= value.format_whitelist;
  observation.protocol_whitelist_observed |= value.protocol_whitelist;
  observation.lavf_selected_observed |= value.lavf_selected;
  observation.reference_access_observed |= value.reference_access;
  observation.redirect_zero_observed |= value.redirect_zero;
  observation.tls_verify_observed |= value.tls_verify;
  if (!policy_status_path.empty() && PrivatePolicyMatches(value) && !policy_status_attempted.exchange(true)) {
    const int descriptor = open(policy_status_path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    constexpr char marker[] = "policy_ready\n";
    bool success = false;
    if (descriptor >= 0) {
      success = write(descriptor, marker, sizeof(marker) - 1) == static_cast<ssize_t>(sizeof(marker) - 1);
      success = close(descriptor) == 0 && success;
    }
    policy_status_written.store(success);
    if (!success) { observation.failed = true; Structural(StructuralFailure::status_write_failed); }
  }
}

mpv_event* WaitEvent(mpv_handle* client, double timeout) {
  auto* event = mpv_wait_event(client, timeout);
  if (!event) return event;
  if (event->event_id == MPV_EVENT_NONE) {
    if (!policy_status_path.empty() && !policy_status_attempted.load()) {
      const auto value = ReadSnapshot(client);
      std::lock_guard<std::mutex> lock(observation.mutex);
      RememberPolicy(value);
    }
    return event;
  }
  if (event->event_id == MPV_EVENT_LOG_MESSAGE && event->data) {
    const auto* message = static_cast<mpv_event_log_message*>(event->data);
    if (message->text && std::strstr(message->text, "Opening this file was forbidden for security reasons"))
      ++nested_forbidden_logs;  // Keep only the fixed marker count, never raw text/URIs.
    if (message->text && std::strstr(message->text, "Number of redirects hit maximum amount"))
      ++curl_redirect_refused_logs;
  }
  std::lock_guard<std::mutex> lock(observation.mutex);
  if (++observation.event_count > 4096) { observation.failed = true; Structural(StructuralFailure::event_bound); }
  if (event->event_id == MPV_EVENT_START_FILE) {
    const auto* start = static_cast<mpv_event_start_file*>(event->data);
    if (!start || client != observed_client || observation.entry_id != -1) {
      Structural(StructuralFailure::core_correlation);
    } else observation.entry_id = start->playlist_entry_id;
  }
  if (event->event_id == MPV_EVENT_END_FILE) {
    const auto* end = static_cast<mpv_event_end_file*>(event->data);
    if (!end || client != observed_client || observation.entry_id < 0 ||
        end->playlist_entry_id != observation.entry_id || observation.end_fence) {
      Structural(StructuralFailure::core_correlation);
    } else {
      observation.end_fence = true;
      observation.end_reason = end->reason;
    }
    observation.ended = true;
    if (event->data && static_cast<mpv_event_end_file*>(event->data)->reason == MPV_END_FILE_REASON_REDIRECT)
      ++redirect_count;
    if (event->data && static_cast<mpv_event_end_file*>(event->data)->reason == MPV_END_FILE_REASON_ERROR) {
      ++end_file_errors;
      observation.failed = true;  // Ordinary expected-negative media failure.
    }
  }
  if (event->event_id == MPV_EVENT_QUEUE_OVERFLOW) { observation.failed = true; Structural(StructuralFailure::event_queue_overflow); }
  if (event->event_id == MPV_EVENT_START_FILE || event->event_id == MPV_EVENT_LOG_MESSAGE ||
      event->event_id == MPV_EVENT_END_FILE || event->event_id == MPV_EVENT_FILE_LOADED ||
      event->event_id == MPV_EVENT_PLAYBACK_RESTART || event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
    auto value = ReadSnapshot(client);
    RememberPolicy(value);
    observation.latest = value;
    if (event->event_id == MPV_EVENT_FILE_LOADED) observation.loaded = value;
    if (event->event_id == MPV_EVENT_PLAYBACK_RESTART) {
      ++observation.restart_count;
      if (!observation.first_restart && value.Qualified()) observation.first_restart = value;
    }
  }
  return event;
}
bool RuntimeBound() {
  namespace fs = std::filesystem;
  const fs::path runtime = fs::canonical(LINEUP_REFERENCE_RUNTIME);
  const fs::path flutter = fs::canonical(LINEUP_REFERENCE_FLUTTER);
  bool found = false;
  for (uint32_t i = 1; i < _dyld_image_count(); ++i) {
    const std::string image = _dyld_get_image_name(i);
    if (image.rfind("/System/Library/", 0) == 0 || image.rfind("/usr/lib/", 0) == 0) continue;
    const auto path = fs::canonical(image);
    if (path.parent_path() == runtime) {
      if (path.filename() == "libmpv.2.dylib") found = true;
    } else if (path.string().rfind(flutter.string() + "/", 0) != 0) return false;
  }
  return found;
}
id JsonNumber(const std::optional<double>& value) {
  return value ? (id)@(*value) : [NSNull null];
}
NSDictionary* JsonSnapshot(const Snapshot& value) {
  return @{@"P": JsonNumber(value.position), @"D": JsonNumber(value.demuxer_start),
           @"audioPts": JsonNumber(value.audio), @"duration": JsonNumber(value.duration),
           @"decodedWidth": JsonNumber(value.decoded_width), @"decodedHeight": JsonNumber(value.decoded_height),
           @"outputWidth": JsonNumber(value.output_width), @"outputHeight": JsonNumber(value.output_height),
           @"voConfigured": @(value.vo), @"paused": @(value.paused), @"seeking": @(value.seeking),
           @"rebase": @(value.rebase), @"formatWhitelist": @(value.format_whitelist),
           @"protocolWhitelist": @(value.protocol_whitelist), @"lavfSelected": @(value.lavf_selected),
           @"referenceAccess": @(value.reference_access), @"redirectZero": @(value.redirect_zero), @"tlsVerify": @(value.tls_verify), @"pictureType": @(value.picture_type),
           @"elapsedSeconds": @(value.elapsed), @"qualified": @(value.Qualified())};
}
bool ContainsCanary(id value, NSArray<NSString*>* canaries) {
  if ([value isKindOfClass:NSString.class]) {
    NSString* text = value;
    if ([text containsString:@"://"] || [text containsString:@"#EXTM3U"] || [text containsString:@"#EXT-X-"]) return true;
    for (NSString* canary in canaries) if (canary.length && [text containsString:canary]) return true;
  } else if ([value isKindOfClass:NSArray.class]) {
    for (id item in value) if (ContainsCanary(item, canaries)) return true;
  } else if ([value isKindOfClass:NSDictionary.class]) {
    for (id key in value) if (ContainsCanary(key, canaries) || ContainsCanary(value[key], canaries)) return true;
  }
  return false;
}
}  // namespace

@interface LineupNativePlayer (ClockTestOperations)
- (lineup::player::MpvOperations)mpvOperations;
@end
@interface SessionClockPlayer : LineupNativePlayer
@end
@implementation SessionClockPlayer
- (lineup::player::MpvOperations)mpvOperations {
  auto operations = lineup::player::LibmpvOperations();
  operations.create = Create;
  operations.initialize = Initialize;
  operations.set_option_string = SetOption;
  operations.wait_event = WaitEvent;
  operations.command_node = CommandNode;
  operations.command = Command;
  operations.terminate_destroy = Destroy;
  return operations;
}
@end
@interface ClockWindow : NSObject
@end
@implementation ClockWindow
- (NSWindowStyleMask)styleMask { return NSWindowStyleMaskBorderless; }
- (BOOL)isMiniaturized { return NO; }
- (NSWindowOcclusionState)occlusionState { return NSWindowOcclusionStateVisible; }
@end

@interface ClockMessenger : NSObject <FlutterBinaryMessenger>
@property(nonatomic, copy) FlutterBinaryMessageHandler handler;
@property(nonatomic, strong) NSArray<NSString*>* canaries;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* demuxerEvents;
@property(nonatomic, strong) NSMutableArray<NSDictionary*>* positionEvents;
@property(nonatomic, strong) NSNumber* latestP;
@property(nonatomic, strong) NSNumber* latestD;
@property(nonatomic) double latestPTime;
@property(nonatomic) double latestDTime;
@property(nonatomic) BOOL leaked;
@property(nonatomic) BOOL rejected;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL finished;
@property(nonatomic) BOOL stopConfirmed;
@property(nonatomic) int eventCount;
- (BOOL)call:(NSString*)method arguments:(id)arguments;
@end
@implementation ClockMessenger
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message {
  FlutterMethodCall* call = [FlutterStandardMethodCodec.sharedInstance decodeMethodCall:message];
  if (![call.method isEqual:@"event"] || ![call.arguments isKindOfClass:NSDictionary.class]) {
    Structural(StructuralFailure::event_shape);
    self.rejected = YES;
    return;
  }
  NSDictionary* event = call.arguments;
  if ([event[@"type"] isEqual:@"stopResult"] && [event[@"stopId"] longLongValue] == 1 && [event[@"success"] boolValue])
    self.stopConfirmed = YES;
  self.leaked |= ContainsCanary(event, self.canaries);
  if (++self.eventCount > 4096) { self.rejected = YES; Structural(StructuralFailure::event_bound); }
  if ([event[@"state"] isEqual:@"playing"]) self.playing = YES;
  if ([event[@"state"] isEqual:@"error"]) {
    self.rejected = YES;
    if ([event[@"failureCode"] isEqual:@"correlation_error"]) Structural(StructuralFailure::core_correlation);
    if ([event[@"failureCode"] isEqual:@"event_queue_overflow"]) Structural(StructuralFailure::event_queue_overflow);
    if ([event[@"failureCode"] isEqual:@"command_error"] || [event[@"failureCode"] isEqual:@"command_queue_full"])
      Structural(StructuralFailure::core_command);
    id code = event[@"failureCode"];
    const bool ordinary = [code isKindOfClass:NSString.class] &&
        [@[ @"mpv_error", @"http_error", @"network_error", @"audio_decode_error", @"video_decode_error",
            @"audio_output_error", @"video_output_error", @"source_open_error", @"container_error" ] containsObject:code];
    if (!ordinary) Structural(StructuralFailure::core_unknown_failure);
  }
  if ([event[@"state"] isEqual:@"ended"] || [event[@"state"] isEqual:@"stopped"] || [event[@"state"] isEqual:@"error"])
    self.finished = YES;
  const bool demuxer = [event[@"name"] isEqual:@"demuxer-start-time"];
  if (demuxer || [event[@"name"] isEqual:@"time-pos"]) {
    id value = event[@"value"];
    id load = event[@"loadId"];
    const bool clear = value == [NSNull null];
    const bool numbered = [value isKindOfClass:NSNumber.class] &&
        CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() && std::isfinite([value doubleValue]);
    const bool own_load = [load isKindOfClass:NSNumber.class] && [load longLongValue] == 1;
    const bool no_load = !load || load == [NSNull null];
    if (!(numbered && own_load) && !(clear && (own_load || no_load))) { self.rejected = YES; Structural(StructuralFailure::clock_event_shape); }
    else {
      const double elapsed = Elapsed();
      NSMutableArray* series = demuxer ? self.demuxerEvents : self.positionEvents;
      [series addObject:@{@"value": value, @"loadId": own_load ? load : (id)[NSNull null], @"elapsedSeconds": @(elapsed)}];
      if (demuxer) { self.latestD = numbered ? value : nil; self.latestDTime = elapsed; }
      else { self.latestP = numbered ? value : nil; self.latestPTime = elapsed; }
    }
  }
}
- (void)sendOnChannel:(NSString*)channel message:(NSData*)message binaryReply:(FlutterBinaryReply)callback {
  [self sendOnChannel:channel message:message];
}
- (FlutterBinaryMessengerConnection)setMessageHandlerOnChannel:(NSString*)channel binaryMessageHandler:(FlutterBinaryMessageHandler)handler {
  self.handler = handler;
  return 1;
}
- (void)cleanUpConnection:(FlutterBinaryMessengerConnection)connection { self.handler = nil; }
- (BOOL)call:(NSString*)method arguments:(id)arguments {
  __block BOOL replied = NO, success = NO;
  NSData* data = [FlutterStandardMethodCodec.sharedInstance encodeMethodCall:
      [FlutterMethodCall methodCallWithMethodName:method arguments:arguments]];
  self.handler(data, ^(NSData* reply) {
    replied = YES;
    id value = [FlutterStandardMethodCodec.sharedInstance decodeEnvelope:reply];
    success = ![value isKindOfClass:FlutterError.class];
  });
  if (!replied || !success) Structural(StructuralFailure::command_rejected);
  return replied && success;
}
@end

namespace {
void Pump(double seconds) {
  [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}
bool SelfTest() {
  NSArray* canaries = @[@"child-canary.m4s", @"whole-manifest-canary"];
  if (!ContainsCanary(@{@"nested": @[@"child-canary.m4s"]}, canaries)) return false;
  if (!ContainsCanary(@{@"diagnostic": @"https://synthetic.invalid/segment"}, canaries)) return false;
  if (!ContainsCanary(@"whole-manifest-canary", canaries)) return false;
  if (ContainsCanary(@{@"name": @"demuxer-start-time", @"value": @12.5, @"loadId": @1}, canaries)) return false;
  mpv_node option_values[4]{};
  option_values[0].format = option_values[1].format = option_values[2].format = option_values[3].format = MPV_FORMAT_STRING;
  option_values[0].u.string = const_cast<char*>("yes");
  option_values[1].u.string = const_cast<char*>("0");
  option_values[2].u.string = const_cast<char*>("format_whitelist=%7%hls,mov,protocol_whitelist=%13%https,tls,tcp");
  option_values[3].u.string = const_cast<char*>("lavf");
  char* option_keys[] = {const_cast<char*>("access-references"), const_cast<char*>("curl-max-redirects"), const_cast<char*>("demuxer-lavf-o"), const_cast<char*>("demuxer")};
  mpv_node_list options{4, option_values, option_keys};
  mpv_node args[5]{};
  args[0].format = args[1].format = MPV_FORMAT_STRING;
  args[0].u.string = const_cast<char*>("loadfile");
  args[1].u.string = const_cast<char*>("lineup-session://00000000000000000000000000000000.m3u8");
  args[4].format = MPV_FORMAT_NODE_MAP;
  args[4].u.list = &options;
  mpv_node_list list{5, args, nullptr};
  mpv_node command{};
  command.format = MPV_FORMAT_NODE_ARRAY;
  command.u.list = &list;
  if (!IsSessionLoadMap(&command)) return false;
  args[1].u.string = const_cast<char*>("file:///private.m3u8");
  if (IsSessionLoadMap(&command)) return false;
  args[1].u.string = const_cast<char*>("lineup-session://0000000000000000000000000000000A.m3u8");
  if (IsSessionLoadMap(&command)) return false;
  args[1].u.string = const_cast<char*>("https://synthetic.invalid/index.m3u8");
  if (IsSessionLoadMap(&command)) return false;
  args[1].u.string = const_cast<char*>("lineup-session://00000000000000000000000000000000");
  if (IsSessionLoadMap(&command)) return false;
  args[1].u.string = const_cast<char*>("lineup-session://00000000000000000000000000000000.m3u8");
  option_keys[1] = const_cast<char*>("start");
  if (IsSessionLoadMap(&command)) return false;
  lineup::fixture::SessionPolicy baseline;
  baseline.valid = true;
  auto altered = baseline;
  if (!lineup::fixture::SameSessionPolicy(baseline, altered)) return false;
  altered.references = 1;
  if (lineup::fixture::SameSessionPolicy(baseline, altered)) return false;
  altered = baseline;
  altered.redirects = 1;
  if (lineup::fixture::SameSessionPolicy(baseline, altered)) return false;
  altered = baseline;
  altered.demuxer = "lavf";
  if (lineup::fixture::SameSessionPolicy(baseline, altered)) return false;
  altered = baseline;
  altered.lavf.emplace("format_whitelist", "hls,mov");
  if (lineup::fixture::SameSessionPolicy(baseline, altered)) return false;
  RestorationSnapshot restored;
  restored.references_checked = restored.references_restored = restored.redirects_checked = restored.redirects_restored = true;
  restored.demuxer_checked = restored.demuxer_restored = restored.lavf_checked = restored.lavf_restored = true;
  restored.end_fence = restored.idle_checked = restored.idle = restored.count_checked = true;
  restored.count = 0; restored.end_reason = MPV_END_FILE_REASON_STOP;
  if (!restored.Complete(false, .9) || restored.Complete(false, 1.000001) || restored.Complete(true, .9)) return false;
  auto waiting = restored; waiting.end_fence = false;
  if (waiting.Complete(false, .1)) return false;
  waiting = restored; waiting.end_reason = MPV_END_FILE_REASON_ERROR;
  if (!waiting.Complete(true, .9) || waiting.Complete(false, .9)) return false;
  for (bool RestorationSnapshot::*member : {&RestorationSnapshot::references_checked, &RestorationSnapshot::references_restored,
      &RestorationSnapshot::redirects_checked, &RestorationSnapshot::redirects_restored, &RestorationSnapshot::demuxer_checked,
      &RestorationSnapshot::demuxer_restored, &RestorationSnapshot::lavf_checked, &RestorationSnapshot::lavf_restored,
      &RestorationSnapshot::idle_checked, &RestorationSnapshot::idle, &RestorationSnapshot::count_checked}) {
    waiting = restored; waiting.*member = false;
    if (waiting.Complete(false, .5)) return false;
    waiting = restored;  // Delayed restoration becomes valid within same budget.
    if (!waiting.Complete(false, .8) || waiting.Complete(false, 1.01)) return false;
  }
  waiting = restored; waiting.count = 1;
  if (waiting.Complete(false, .9)) return false;
  Snapshot value;
  if (value.Qualified()) return false;
  value.position = 0; value.demuxer_start = 12; value.vo = value.rebase = value.format_whitelist = value.protocol_whitelist = value.lavf_selected = true;
  value.reference_access = value.redirect_zero = value.tls_verify = true;
  value.seeking = false; value.decoded_width = value.output_width = 96;
  value.decoded_height = value.output_height = 54; value.picture_type = 1;
  if (!value.Qualified() || !PrivatePolicyMatches(value)) return false;
  for (bool Snapshot::*member : {&Snapshot::format_whitelist, &Snapshot::protocol_whitelist, &Snapshot::lavf_selected,
                                &Snapshot::reference_access, &Snapshot::redirect_zero, &Snapshot::tls_verify}) {
    auto incorrect = value;
    incorrect.*member = false;
    if (PrivatePolicyMatches(incorrect)) return false;
  }
  return true;
}
}  // namespace

int main(int argc, char** argv) {
  @autoreleasepool {
    if (argc == 2 && std::strcmp(argv[1], "--self-test") == 0) {
      std::cout << (SelfTest() ? "self_test=pass\n" : "self_test=fail\n");
      return SelfTest() ? 0 : 1;
    }
    if (argc != 2) return 2;
    try {
      test_ca = argv[1];
      std::string bytes;
      char block[4096];
      while (std::cin.good() && bytes.size() <= 2 * 1024 * 1024) {
        std::cin.read(block, sizeof(block));
        bytes.append(block, static_cast<size_t>(std::cin.gcount()));
      }
      if (bytes.size() > 2 * 1024 * 1024 || !RuntimeBound()) return 2;
      NSData* input = [NSData dataWithBytes:bytes.data() length:bytes.size()];
      NSDictionary* config = [NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
      if (![config isKindOfClass:NSDictionary.class] || ![config[@"load"] isKindOfClass:NSDictionary.class] ||
          ![config[@"canaries"] isKindOfClass:NSArray.class] || [config[@"canaries"] count] < 3 ||
          [config[@"canaries"] count] > 8) return 2;
      for (id canary in config[@"canaries"]) if (![canary isKindOfClass:NSString.class]) return 2;
      NSMutableDictionary* load = [config[@"load"] mutableCopy];
      if (![load[@"kind"] isEqual:@"plexSession"] || [load[@"loadId"] longLongValue] != 1 ||
          load[@"startSeconds"] || load[@"startPosition"] || load[@"plexToken"] ||
          ![load[@"sessionPlaylist"] isKindOfClass:NSDictionary.class]) return 2;
      if (std::strcmp(argv[1], "--validate-playlist") == 0) {
        NSDictionary* input_playlist = load[@"sessionPlaylist"];
        NSString* text = input_playlist[@"text"];
        NSString* variant = load[@"uri"];
        NSNumber* offset = input_playlist[@"offsetMicroseconds"];
        if (![text isKindOfClass:NSString.class] || ![variant isKindOfClass:NSString.class] ||
            ![offset isKindOfClass:NSNumber.class] || CFNumberIsFloatType((__bridge CFNumberRef)offset) ||
            CFGetTypeID((__bridge CFTypeRef)offset) == CFBooleanGetTypeID()) return 2;
        const auto parsed = lineup::player::SessionPlaylist::Parse(text.UTF8String, variant.UTF8String, offset.longLongValue);
        const bool valid = parsed && parsed->byte_size() > 0;
        std::cout << (valid ? "playlist_validation=pass\n" : "playlist_validation=fail\n");
        return valid ? 0 : 1;
      }
      if (id status_path = config[@"policyStatusPath"]) {
        if (![status_path isKindOfClass:NSString.class]) return 2;
        policy_status_path = [status_path UTF8String];
        const std::filesystem::path path(policy_status_path);
        if (policy_status_path.size() > 4096 || !path.is_absolute() ||
            (path.filename() != "cell-1-policy-ready.status" && path.filename() != "cell-2-policy-ready.status")) return 2;
      }
      std::signal(SIGINT, StopRequested);
      std::signal(SIGTERM, StopRequested);
      origin = Clock::now();
      ClockMessenger* messenger = [ClockMessenger new];
      messenger.canaries = config[@"canaries"];
      messenger.demuxerEvents = [NSMutableArray array];
      messenger.positionEvents = [NSMutableArray array];
      ClockWindow* window = [ClockWindow new];
      NSView* host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64)];
      SessionClockPlayer* player = [[SessionClockPlayer alloc] initWithMessenger:messenger videoHost:host window:(NSWindow*)window];
      const bool initialized = [messenger call:@"initialize" arguments:nil];
      const auto baseline_policy = initialized ? lineup::fixture::ReadSessionPolicy(observed_client) : lineup::fixture::SessionPolicy{};
      const bool accepted = initialized && [messenger call:@"load" arguments:load];
      bool play_sent = false, complete = false;
      NSMutableArray* samples = [NSMutableArray array];
      std::optional<Snapshot> first;
      double sample_origin = 0;
      while (accepted && Elapsed() < 25 && !messenger.rejected && !messenger.finished && !stop_requested) {
        std::optional<Snapshot> latest;
        bool failed = false;
        {
          std::lock_guard<std::mutex> lock(observation.mutex);
          if (!first && observation.first_restart) first = observation.first_restart;
          latest = observation.latest;
          failed = observation.failed;
        }
        if (messenger.leaked) break;
        if (failed || structural_failure.load() != StructuralFailure::none) { if (Elapsed() > 15) break; Pump(0.01); continue; }
        if (!play_sent && Elapsed() > 15) break;
        if (first && messenger.latestP && messenger.latestD && !play_sent) {
          if (!first->paused || ![messenger call:@"play" arguments:nil]) break;
          play_sent = true;
          sample_origin = Elapsed();
        }
        if (play_sent && latest && Elapsed() >= sample_origin + samples.count * 0.25) {
          if (Elapsed() - latest->elapsed > 0.5 || !messenger.latestP || Elapsed() - messenger.latestPTime > 0.5) break;
          NSMutableDictionary* sample = [JsonSnapshot(*latest) mutableCopy];
          sample[@"sampleIndex"] = @(samples.count);
          sample[@"sampleAgeSeconds"] = @(std::max(0.0, Elapsed() - latest->elapsed));
          sample[@"observationSeconds"] = @(Elapsed() - sample_origin);
          sample[@"productionP"] = messenger.latestP ?: (id)[NSNull null];
          sample[@"productionD"] = messenger.latestD ?: (id)[NSNull null];
          sample[@"productionPAgeSeconds"] = messenger.latestP ? @(std::max(0.0, Elapsed() - messenger.latestPTime)) : (id)[NSNull null];
          sample[@"productionDAgeSeconds"] = messenger.latestD ? @(std::max(0.0, Elapsed() - messenger.latestDTime)) : (id)[NSNull null];
          [samples addObject:sample];
          if (samples.count == 25) { complete = true; break; }
        }
        Pump(0.01);
      }
      // stopResult observes core idle/count, which can precede mpv's unload and
      // per-file option restoration. Keep one budget starting before stop.
      const double stop_started = Elapsed();
      const bool stop_accepted = accepted && [messenger call:@"stop" arguments:@{@"stopId": @1}];
      const bool expected_error = end_file_errors.load() > 0;
      while (stop_accepted && !messenger.stopConfirmed && Elapsed() - stop_started < 1) Pump(0.01);
      const bool stop_result_in_budget = messenger.stopConfirmed && Elapsed() - stop_started < 1;
      // The method reply only accepts the queued stop. Capture the immediate
      // policy comparison after the correlated asynchronous stopResult instead.
      const auto immediate_restoration = stop_result_in_budget
          ? ReadRestoration(observed_client, baseline_policy) : RestorationSnapshot{};
      auto final_restoration = immediate_restoration;
      double restoration_wait = Elapsed() - stop_started;
      bool restoration_complete = stop_accepted && messenger.stopConfirmed && final_restoration.Complete(expected_error, restoration_wait);
      while (stop_accepted && !restoration_complete && Elapsed() - stop_started < 1) {
        Pump(0.01);
        if (Elapsed() - stop_started >= 1) break;
        final_restoration = ReadRestoration(observed_client, baseline_policy);
        // Getters are synchronous: completion after the deadline cannot pass.
        restoration_wait = Elapsed() - stop_started;
        restoration_complete = messenger.stopConfirmed && final_restoration.Complete(expected_error, restoration_wait);
      }
      restoration_wait = Elapsed() - stop_started;
      restoration_complete = restoration_complete && restoration_wait <= 1;
      const bool policy_checked = final_restoration.Checked();
      const bool policy_restored = final_restoration.Restored();
      __block BOOL disposed = NO;
      [player beginShutdownWithCompletion:^{ disposed = YES; }];
      const double cleanup_started = Elapsed();
      while (!disposed && Elapsed() - cleanup_started < 6) Pump(0.01);
      NSDictionary* loaded = nil;
      int restarts = 0;
      bool worker_failed = false, format_observed = false, protocol_observed = false, lavf_observed = false;
      bool references_observed = false, redirects_observed = false, tls_observed = false;
      {
        std::lock_guard<std::mutex> lock(observation.mutex);
        if (observation.loaded) loaded = JsonSnapshot(*observation.loaded);
        restarts = observation.restart_count;
        worker_failed = observation.failed;
        format_observed = observation.format_whitelist_observed;
        protocol_observed = observation.protocol_whitelist_observed;
        lavf_observed = observation.lavf_selected_observed;
        references_observed = observation.reference_access_observed;
        redirects_observed = observation.redirect_zero_observed;
        tls_observed = observation.tls_verify_observed;
      }
      bool has_d = false, has_p = false;
      for (NSDictionary* event in messenger.demuxerEvents)
        if ([event[@"value"] isKindOfClass:NSNumber.class]) has_d = true;
      for (NSDictionary* event in messenger.positionEvents)
        if ([event[@"value"] isKindOfClass:NSNumber.class]) has_p = true;
      const bool pass = structural_failure.load() == StructuralFailure::none && !stop_requested && initialized && accepted && complete && first && first->Qualified() && play_sent &&
          messenger.playing && has_d && has_p && !messenger.rejected && !messenger.leaked && !worker_failed &&
          stop_accepted && messenger.stopConfirmed && restoration_complete && policy_checked && policy_restored && disposed && destroyed.load() && load_commands.load() == 1 &&
          load_map_valid.load() && seek_commands.load() == 0 && redirect_count.load() == 0 && !force_hls.load() && RuntimeBound();
      NSDictionary* output = @{@"pass": @(pass), @"initialized": @(initialized), @"loadAccepted": @(accepted),
          @"complete": @(complete), @"fileLoaded": loaded ?: (id)[NSNull null],
          @"firstRestart": first ? JsonSnapshot(*first) : (id)[NSNull null], @"samples": samples,
          @"productionDemuxerEvents": messenger.demuxerEvents, @"productionPositionEvents": messenger.positionEvents, @"playing": @(messenger.playing),
          @"rejected": @(messenger.rejected), @"canaryLeak": @(messenger.leaked), @"workerFailed": @(worker_failed),
          @"structuralFailure": @(structural_failure.load() != StructuralFailure::none),
          @"structuralFailureCode": @(StructuralCode(structural_failure.load())), @"endFileErrorCount": @(end_file_errors.load()),
          @"restartCount": @(restarts), @"redirectCount": @(redirect_count.load()), @"nestedForbiddenCount": @(nested_forbidden_logs.load()), @"curlRedirectRefusedCount": @(curl_redirect_refused_logs.load()), @"loadCommands": @(load_commands.load()), @"seekCommands": @(seek_commands.load()),
          @"loadMapExact": @(load_map_valid.load()), @"globalForceHls": @(force_hls.load()),
          @"formatWhitelistObserved": @(format_observed), @"protocolWhitelistObserved": @(protocol_observed), @"lavfSelectedObserved": @(lavf_observed),
          @"referenceAccessObserved": @(references_observed), @"redirectZeroObserved": @(redirects_observed), @"tlsVerifyObserved": @(tls_observed),
          @"stopAccepted": @(stop_accepted), @"stopConfirmed": @(messenger.stopConfirmed),
          @"policyChecked": @(policy_checked), @"policyRestored": @(policy_restored),
          @"restoration": @{@"immediate": JsonRestoration(immediate_restoration), @"final": JsonRestoration(final_restoration),
              @"complete": @(restoration_complete), @"waitSeconds": @(restoration_wait), @"maximumWaitSeconds": @1,
              @"timedOut": @(!restoration_complete && restoration_wait >= 1)},
          @"policyHandshakeWritten": @(policy_status_written.load()), @"disposed": @(disposed), @"nativeDestroyed": @(destroyed.load()),
          @"runtimeBound": @(RuntimeBound()), @"operatorStopped": @(static_cast<bool>(stop_requested)), @"elapsedSeconds": @(Elapsed())};
      NSData* encoded = [NSJSONSerialization dataWithJSONObject:output options:0 error:nil];
      if (!encoded || encoded.length > 128 * 1024) return 2;
      std::cout.write(static_cast<const char*>(encoded.bytes), encoded.length);
      std::cout << '\n';
      return pass ? 0 : 1;
    } catch (...) {
      std::cout << "{\"pass\":false,\"fixedError\":\"harness_prerequisite\"}\n";
      return 2;
    }
  }
}
