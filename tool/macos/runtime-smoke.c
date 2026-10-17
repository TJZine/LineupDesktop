// Smoke test for the macOS libmpv runtime built by tool/macos/build-mpv.sh.
//
// It links the runtime's dylibs through @rpath (as the app does), reports the
// FFmpeg license strings and the libraries actually loaded, then plays one
// target headlessly and checks the outcome.
//
// Usage:
//   runtime-smoke [--layer] [-o name=value]... [-p property]...
//                 [-e property=value]... --expect load|reject TARGET
//   runtime-smoke --licenses
//
//   --layer          Render with the production route C output (vo=gpu-next,
//                    gpu-api=vulkan, gpu-context=macvk) into an off-screen
//                    host CAMetalLayer passed through --wid, instead of
//                    vo=null. Hardware decode interop needs a real VO.
//   -o name=value    mpv option set before initialization (repeatable).
//   -p property      property printed once playback starts (repeatable).
//   -e property=value
//                    assertion: once playback starts, the property's string
//                    value must equal value (repeatable). Values are polled
//                    for up to 3 seconds, for properties such as sub-text
//                    that appear shortly after the first frame.
//   --expect load    TARGET must load without a fatal error and, with -p or
//                    -e, start playback with every assertion holding.
//   --expect reject  TARGET must fail to load with a TLS certificate
//                    verification error (not any other TLS failure).
//
// Exit status 0 means the expectation held. Build: see docs/macos-runtime.md.

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
#define ASSERT_TIMEOUT_POLLS 30  // 30 x 0.1 s

// runtime-smoke-layer.m
int64_t runtime_smoke_create_layer(int width, int height);

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

// Certificate verification failures only: curl's peer-verification error and
// mpv's explanation of it, and OpenSSL's verify failure as FFmpeg reports it.
// Other TLS failures (protocol version, handshake) do not count.
static bool is_certificate_rejection(const char *text) {
  return strstr(text, "SSL peer certificate or SSH remote key was not OK") ||
         strstr(text, "TLS certificate verification failed") ||
         strstr(text, "certificate verify failed");
}

struct assertion {
  char property[256];
  const char *expected;
};

// Prints each assertion's current value; returns true when all hold.
static bool check_assertions(mpv_handle *mpv, struct assertion *assertions,
                             int count, bool print) {
  bool all = true;
  for (int i = 0; i < count; i++) {
    char *value = mpv_get_property_string(mpv, assertions[i].property);
    bool ok = value && !strcmp(value, assertions[i].expected);
    if (print)
      printf("assert %s == %s: %s (actual: %s)\n", assertions[i].property,
             assertions[i].expected, ok ? "ok" : "FAILED",
             value ? value : "(unavailable)");
    all = all && ok;
    mpv_free(value);
  }
  return all;
}

struct run_state {
  bool loaded, played, ended, certificate_rejected, fatal;
  int end_error;
};

// Applies one mpv event to the run state; used by the main loop and while
// polling assertions.
static void handle_event(mpv_event *event, struct run_state *state) {
  switch (event->event_id) {
  case MPV_EVENT_LOG_MESSAGE: {
    mpv_event_log_message *message = event->data;
    printf("log[%s] %s: %s", message->level, message->prefix, message->text);
    if (is_certificate_rejection(message->text))
      state->certificate_rejected = true;
    if (!strcmp(message->level, "fatal"))
      state->fatal = true;
    break;
  }
  case MPV_EVENT_FILE_LOADED:
    state->loaded = true;
    printf("event: file-loaded\n");
    break;
  case MPV_EVENT_END_FILE: {
    mpv_event_end_file *end = event->data;
    state->end_error = end->reason == MPV_END_FILE_REASON_ERROR ? end->error : 0;
    printf("event: end-file reason=%d error=%s\n", end->reason,
           state->end_error ? mpv_error_string(state->end_error) : "none");
    state->ended = true;
    break;
  }
  default:
    break;
  }
}

int main(int argc, char **argv) {
  const char *options[MAX_ITEMS];
  const char *properties[MAX_ITEMS];
  struct assertion assertions[MAX_ITEMS];
  int option_count = 0, property_count = 0, assertion_count = 0;
  const char *expect = NULL, *target = NULL;
  bool use_layer = false;

  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--layer")) {
      use_layer = true;
    } else if (!strcmp(argv[i], "--licenses")) {
      print_ffmpeg_licenses();
      print_loaded_runtime();
      return 0;
    } else if (!strcmp(argv[i], "-o") && i + 1 < argc && option_count < MAX_ITEMS) {
      options[option_count++] = argv[++i];
    } else if (!strcmp(argv[i], "-p") && i + 1 < argc && property_count < MAX_ITEMS) {
      properties[property_count++] = argv[++i];
    } else if (!strcmp(argv[i], "-e") && i + 1 < argc && assertion_count < MAX_ITEMS) {
      const char *spec = argv[++i];
      const char *equals = strchr(spec, '=');
      if (!equals || (size_t)(equals - spec) >= sizeof(assertions[0].property)) {
        fprintf(stderr, "assertion must be property=value: %s\n", spec);
        return 2;
      }
      struct assertion *assertion = &assertions[assertion_count++];
      snprintf(assertion->property, sizeof(assertion->property), "%.*s",
               (int)(equals - spec), spec);
      assertion->expected = equals + 1;
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
    fprintf(stderr, "usage: runtime-smoke [--layer] [-o name=value]... "
                    "[-p property]... [-e property=value]... "
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
  mpv_set_option_string(mpv, "ao", "null");
  if (use_layer) {
    int64_t wid = runtime_smoke_create_layer(1280, 720);
    mpv_set_option_string(mpv, "vo", "gpu-next");
    mpv_set_option_string(mpv, "gpu-api", "vulkan");
    mpv_set_option_string(mpv, "gpu-context", "macvk");
    mpv_set_option_string(mpv, "target-colorspace-hint", "yes");
    mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &wid);
  } else {
    mpv_set_option_string(mpv, "vo", "null");
  }
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

  bool wait_for_playback = property_count > 0 || assertion_count > 0;
  struct run_state state = {0};
  bool assertions_hold = true;
  while (!state.ended) {
    mpv_event *event = mpv_wait_event(mpv, 60);
    if (event->event_id == MPV_EVENT_NONE) {
      printf("result: timeout\n");
      break;
    }
    handle_event(event, &state);
    if (event->event_id == MPV_EVENT_FILE_LOADED && !wait_for_playback)
      break;
    if (event->event_id == MPV_EVENT_PLAYBACK_RESTART && !state.played) {
      state.played = true;
      // Poll for late-arriving values; events that arrive meanwhile (a fatal
      // error, the end of the file) are handled like any other and end it.
      for (int polls = 0; polls < ASSERT_TIMEOUT_POLLS; polls++) {
        if (check_assertions(mpv, assertions, assertion_count, false))
          break;
        handle_event(mpv_wait_event(mpv, 0.1), &state);
        if (state.ended || state.fatal)
          break;
      }
      for (int i = 0; i < property_count; i++) {
        char *value = mpv_get_property_string(mpv, properties[i]);
        printf("%s: %s\n", properties[i], value ? value : "(unavailable)");
        mpv_free(value);
      }
      assertions_hold = check_assertions(mpv, assertions, assertion_count, true);
      break;
    }
  }
  print_loaded_runtime();
  mpv_terminate_destroy(mpv);

  bool pass;
  if (expect_load)
    pass = state.loaded && !state.fatal && state.end_error == 0 &&
           (!wait_for_playback || state.played) && assertions_hold;
  else
    pass = !state.loaded && state.end_error < 0 && state.certificate_rejected;
  printf("result: %s (expected %s)\n", pass ? "PASS" : "FAIL", expect);
  return pass ? 0 : 1;
}
