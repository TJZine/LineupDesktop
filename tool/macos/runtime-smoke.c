// Smoke test for the macOS libmpv runtime built by tool/macos/build-mpv.sh.
//
// It links the runtime's dylibs through @rpath (as the app does), reports the
// FFmpeg license strings and the libraries actually loaded, then plays one
// target headlessly and checks the outcome.
//
// Usage:
//   runtime-smoke [-o name=value]... [-p property]... --expect load|reject TARGET
//   runtime-smoke --licenses
//
//   -o name=value    mpv option set before initialization (repeatable).
//   -p property      property printed after the first video frame
//                    (repeatable); with -p the run waits for playback.
//   --expect load    TARGET must load (and, with -p, start playback).
//   --expect reject  TARGET must fail to load with a TLS certificate error.
//
// Exit status 0 means the expectation held. Build: see docs/macos-runtime.md.

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <libavcodec/avcodec.h>
#include <libavfilter/avfilter.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <mpv/client.h>

#define MAX_ITEMS 32

static void print_ffmpeg_licenses(void) {
  printf("avutil_license: %s\n", avutil_license());
  printf("avcodec_license: %s\n", avcodec_license());
  printf("avformat_license: %s\n", avformat_license());
  printf("avfilter_license: %s\n", avfilter_license());
  printf("swscale_license: %s\n", swscale_license());
  printf("swresample_license: %s\n", swresample_license());
  printf("avcodec_configuration: %s\n", avcodec_configuration());
}

static void print_loaded_runtime(void) {
  uint32_t count = _dyld_image_count();
  for (uint32_t i = 0; i < count; i++) {
    const char *name = _dyld_get_image_name(i);
    if (strstr(name, "/usr/lib/") == name || strstr(name, "/System/") == name)
      continue;
    printf("loaded: %s\n", name);
  }
}

static bool mentions_certificate_error(const char *text) {
  return strstr(text, "certificate") || strstr(text, "SSL") ||
         strstr(text, "tls-verify");
}

int main(int argc, char **argv) {
  const char *options[MAX_ITEMS];
  const char *properties[MAX_ITEMS];
  int option_count = 0, property_count = 0;
  const char *expect = NULL, *target = NULL;

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--licenses")) {
      print_ffmpeg_licenses();
      print_loaded_runtime();
      return 0;
    } else if (!strcmp(argv[i], "-o") && i + 1 < argc && option_count < MAX_ITEMS) {
      options[option_count++] = argv[++i];
    } else if (!strcmp(argv[i], "-p") && i + 1 < argc && property_count < MAX_ITEMS) {
      properties[property_count++] = argv[++i];
    } else if (!strcmp(argv[i], "--expect") && i + 1 < argc) {
      expect = argv[++i];
    } else if (!target && argv[i][0] != '-') {
      target = argv[i];
    } else {
      fprintf(stderr, "unrecognized argument: %s\n", argv[i]);
      return 2;
    }
  }
  bool expect_load = expect && !strcmp(expect, "load");
  bool expect_reject = expect && !strcmp(expect, "reject");
  if (!target || (!expect_load && !expect_reject)) {
    fprintf(stderr, "usage: runtime-smoke [-o name=value]... [-p property]... "
                    "--expect load|reject TARGET\n");
    return 2;
  }

  mpv_handle *mpv = mpv_create();
  if (!mpv) {
    fprintf(stderr, "mpv_create failed\n");
    return 1;
  }
  // Headless defaults; -o may override them.
  mpv_set_option_string(mpv, "config", "no");
  mpv_set_option_string(mpv, "terminal", "no");
  mpv_set_option_string(mpv, "vo", "null");
  mpv_set_option_string(mpv, "ao", "null");
  for (int i = 0; i < option_count; i++) {
    char buffer[1024];
    snprintf(buffer, sizeof(buffer), "%s", options[i]);
    char *value = strchr(buffer, '=');
    if (!value) {
      fprintf(stderr, "option without '=': %s\n", options[i]);
      return 2;
    }
    *value++ = '\0';
    int error = mpv_set_option_string(mpv, buffer, value);
    if (error < 0) {
      fprintf(stderr, "option %s: %s\n", buffer, mpv_error_string(error));
      return 1;
    }
  }
  int error = mpv_initialize(mpv);
  if (error < 0) {
    fprintf(stderr, "mpv_initialize: %s\n", mpv_error_string(error));
    return 1;
  }
  mpv_request_log_messages(mpv, "warn");

  char *version = mpv_get_property_string(mpv, "mpv-version");
  char *ffmpeg = mpv_get_property_string(mpv, "ffmpeg-version");
  printf("mpv-version: %s\nffmpeg-version: %s\n", version, ffmpeg);
  mpv_free(version);
  mpv_free(ffmpeg);

  const char *command[] = {"loadfile", target, NULL};
  error = mpv_command(mpv, command);
  if (error < 0) {
    fprintf(stderr, "loadfile: %s\n", mpv_error_string(error));
    return 1;
  }

  bool loaded = false, played = false, ended = false, tls_error = false;
  int end_error = 0;
  while (!ended) {
    mpv_event *event = mpv_wait_event(mpv, 60);
    if (event->event_id == MPV_EVENT_NONE) {
      printf("result: timeout\n");
      break;
    }
    if (event->event_id == MPV_EVENT_LOG_MESSAGE) {
      mpv_event_log_message *message = event->data;
      printf("log[%s] %s: %s", message->level, message->prefix, message->text);
      if (mentions_certificate_error(message->text))
        tls_error = true;
    } else if (event->event_id == MPV_EVENT_FILE_LOADED) {
      loaded = true;
      printf("event: file-loaded\n");
      if (property_count == 0)
        break;
    } else if (event->event_id == MPV_EVENT_PLAYBACK_RESTART && !played) {
      played = true;
      for (int i = 0; i < property_count; i++) {
        char *value = mpv_get_property_string(mpv, properties[i]);
        printf("%s: %s\n", properties[i], value ? value : "(unavailable)");
        mpv_free(value);
      }
      break;
    } else if (event->event_id == MPV_EVENT_END_FILE) {
      mpv_event_end_file *end = event->data;
      end_error = end->reason == MPV_END_FILE_REASON_ERROR ? end->error : 0;
      printf("event: end-file reason=%d error=%s\n", end->reason,
             end_error ? mpv_error_string(end_error) : "none");
      ended = true;
    }
  }
  print_loaded_runtime();
  mpv_terminate_destroy(mpv);

  bool pass;
  if (expect_load)
    pass = loaded && (property_count == 0 || played);
  else
    pass = !loaded && end_error < 0 && tls_error;
  printf("result: %s (expected %s)\n", pass ? "PASS" : "FAIL", expect);
  return pass ? 0 : 1;
}
