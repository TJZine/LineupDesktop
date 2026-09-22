#ifndef RUNNER_TRACK_LIST_ENCODER_H_
#define RUNNER_TRACK_LIST_ENCODER_H_

#include <flutter/encodable_value.h>
#include <mpv/client.h>

#include <cstddef>
#include <string>

namespace lineup {

flutter::EncodableValue EncodeTrackList(const mpv_node& node);

// Telemetry retains replacement-character handling. Track metadata supplies
// valid_utf8 to reject malformed strings instead; only the bounded prefix is
// read.
std::string BoundedUtf8(const char* input, size_t limit,
                        bool* valid_utf8 = nullptr);

}  // namespace lineup

#endif  // RUNNER_TRACK_LIST_ENCODER_H_
