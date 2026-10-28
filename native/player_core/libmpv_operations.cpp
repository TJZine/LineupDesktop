#include "player_core/mpv_operations.h"

namespace lineup::player {

MpvOperations LibmpvOperations() {
  MpvOperations operations;
  operations.create = &::mpv_create;
  operations.initialize = &::mpv_initialize;
  operations.set_option = &::mpv_set_option;
  operations.set_option_string = &::mpv_set_option_string;
  operations.request_log_messages = &::mpv_request_log_messages;
  operations.observe_property = &::mpv_observe_property;
  operations.get_property = &::mpv_get_property;
  operations.set_property = &::mpv_set_property;
  operations.set_property_string = &::mpv_set_property_string;
  operations.command = &::mpv_command;
  operations.command_node = &::mpv_command_node;
  operations.wait_event = &::mpv_wait_event;
  operations.terminate_destroy = &::mpv_terminate_destroy;
  operations.error_string = &::mpv_error_string;
  operations.client_api_version = &::mpv_client_api_version;
  return operations;
}

}  // namespace lineup::player
