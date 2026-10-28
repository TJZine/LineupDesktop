#ifndef LINEUP_PLAYER_CORE_MPV_OPERATIONS_H_
#define LINEUP_PLAYER_CORE_MPV_OPERATIONS_H_

#include <mpv/client.h>

namespace lineup::player {

// Every libmpv entry point the core calls. Tests replace individual
// operations; production uses LibmpvOperations(). The members have no default
// so that a fake set does not require libmpv at link time.
struct MpvOperations {
  decltype(&::mpv_create) create = nullptr;
  decltype(&::mpv_initialize) initialize = nullptr;
  decltype(&::mpv_set_option) set_option = nullptr;
  decltype(&::mpv_set_option_string) set_option_string = nullptr;
  decltype(&::mpv_request_log_messages) request_log_messages = nullptr;
  decltype(&::mpv_observe_property) observe_property = nullptr;
  decltype(&::mpv_get_property) get_property = nullptr;
  decltype(&::mpv_set_property) set_property = nullptr;
  decltype(&::mpv_set_property_string) set_property_string = nullptr;
  decltype(&::mpv_command) command = nullptr;
  decltype(&::mpv_command_node) command_node = nullptr;
  decltype(&::mpv_wait_event) wait_event = nullptr;
  decltype(&::mpv_terminate_destroy) terminate_destroy = nullptr;
  decltype(&::mpv_error_string) error_string = nullptr;
  decltype(&::mpv_client_api_version) client_api_version = nullptr;
};

// The real libmpv functions. Defined in libmpv_operations.cpp, which is the
// only core source that must link against libmpv.
MpvOperations LibmpvOperations();

}  // namespace lineup::player

#endif
