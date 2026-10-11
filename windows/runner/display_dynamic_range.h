#ifndef RUNNER_DISPLAY_DYNAMIC_RANGE_H_
#define RUNNER_DISPLAY_DYNAMIC_RANGE_H_

#include <windows.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace lineup {
enum class DisplayState { unknown, sdr, hdr };
enum class DisplayRoute { none, hdr_state, advanced_color };
const char* DisplayStateName(DisplayState state);
const char* DisplayRouteName(DisplayRoute route);

struct DisplayTarget {
  LUID adapter{};
  UINT32 id = 0;
  bool operator==(const DisplayTarget& other) const {
    return adapter.HighPart == other.adapter.HighPart &&
           adapter.LowPart == other.adapter.LowPart && id == other.id;
  }
};
struct DisplayObservation {
  DisplayState state = DisplayState::unknown;
  DisplayRoute route = DisplayRoute::none;
  bool capable = false;
  const char* active_color_mode = "unknown";
};
struct DisplayMapping {
  std::optional<DisplayTarget> target;
  const char* reason = "target_lost";
};
// These operations are called only on the display worker (or guardian).
// Query(none) detects a route; subsequent queries retain the captured route.
class DisplayConfigApi {
 public:
  virtual ~DisplayConfigApi() = default;
  virtual DisplayMapping MapWindow(HWND window) = 0;
  virtual DisplayObservation Query(DisplayTarget target,
                                   DisplayRoute route) = 0;
  virtual bool Set(DisplayTarget target, DisplayRoute route,
                   DisplayState state) = 0;
  virtual bool WaitForStartupRestore() = 0;
};
std::unique_ptr<DisplayConfigApi> MakeDisplayConfigApi();

struct DisplayOwnership {
  DisplayTarget target;
  DisplayRoute route = DisplayRoute::none;
  DisplayState original = DisplayState::unknown;
  DisplayState verified = DisplayState::unknown;
  DisplayState attempted = DisplayState::unknown;
};
// One link per owned target. Each operation includes an acknowledgment and
// bounded IPC wait; Arm must return within two seconds. Disarm is acknowledged.
class DisplayGuardianLink {
 public:
  virtual ~DisplayGuardianLink() = default;
  virtual bool Arm(const DisplayOwnership& ownership) = 0;
  virtual bool Update(const DisplayOwnership& ownership) = 0;
  virtual bool Disarm() = 0;
  virtual bool IsAlive() = 0;
};
using DisplayGuardianFactory =
    std::function<std::unique_ptr<DisplayGuardianLink>()>;
DisplayGuardianFactory UnavailableDisplayGuardian();

class DisplayClock {
 public:
  virtual ~DisplayClock() = default;
  virtual std::chrono::steady_clock::time_point Now() = 0;
  virtual void Sleep(std::chrono::milliseconds duration) = 0;
};
std::unique_ptr<DisplayClock> MakeDisplayClock();
struct DisplayRequest {
  int64_t revision = 0;
  bool session = false;
  DisplayState desired = DisplayState::unknown;
};
struct DisplayReport {
  int64_t revision = 0;
  const char* session = "inactive";
  DisplayState observed = DisplayState::unknown;
  const char* outcome = "idle";
  bool wrote = false;
  bool owned = false;
  const char* reason = nullptr;
  DisplayRoute route = DisplayRoute::none;
  const char* active_color_mode = "unknown";
};

// Worker-confined policy, also exercised directly by deterministic CTest.
class DisplayMatchingEngine {
 public:
  using Reporter = std::function<void(const DisplayReport&)>;
  DisplayMatchingEngine(HWND window, DisplayConfigApi& api,
                        DisplayGuardianFactory guardian, DisplayClock& clock,
                        Reporter report,
                        std::function<bool()> restart_pending = {});
  void Process(DisplayRequest request, bool remap = false, bool retry = false);
  void Poll(bool remap, bool retry = false);
  void ReleaseAll();
  bool HasOwnership() const;
  bool SessionActive() const { return request_.session; }

 private:
  struct Record {
    struct Failure {
      DisplayRequest request;
      const char *reason;
    };
    DisplayOwnership ownership;
    DisplayObservation observed;
    std::unique_ptr<DisplayGuardianLink> guardian;
    bool owned = false;
    bool guardian_lost = false;
    bool unobserved_attempt = false;
    int64_t write_revision = -1;
    std::optional<Failure> failure;
  };
  Record* Find(DisplayTarget target);
  void Start();
  void Reconcile();
  bool Write(Record& record, DisplayState desired, bool restore);
  void Release(Record& record);
  void Suspend(Record& record);
  void Report(Record* record, const char* outcome, bool wrote,
              const char* reason = nullptr);
  HWND window_;
  DisplayConfigApi& api_;
  DisplayGuardianFactory guardian_;
  DisplayClock& clock_;
  Reporter report_;
  std::function<bool()> restart_pending_;
  DisplayRequest request_;
  std::optional<DisplayTarget> active_;
  const char* session_ = "inactive";
  const char* session_reason_ = nullptr;
  std::vector<std::unique_ptr<Record>> records_;
};

class DisplayDynamicRange {
 public:
  DisplayDynamicRange(HWND window, std::unique_ptr<DisplayConfigApi> api,
                      DisplayGuardianFactory guardian,
                      DisplayMatchingEngine::Reporter reporter,
                      std::function<void()> wakeup,
                      std::unique_ptr<DisplayClock> clock = MakeDisplayClock());
  ~DisplayDynamicRange();
  bool Submit(DisplayRequest request);
  void ResetRevision();
  void Notify(bool remap, bool retry = false);
  void EndSession();
  bool ReleaseComplete() const { return released_.load(); }
  void EndSessionAndWait(std::chrono::milliseconds timeout);

 private:
  void Run();
  HWND window_;
  std::unique_ptr<DisplayConfigApi> api_;
  DisplayGuardianFactory guardian_;
  DisplayMatchingEngine::Reporter reporter_;
  std::function<void()> wakeup_;
  std::unique_ptr<DisplayClock> clock_;
  std::mutex mutex_;
  std::condition_variable changed_;
  struct Pending {
    DisplayRequest request;
    uint64_t epoch;
  };
  std::deque<Pending> requests_;
  std::atomic<uint64_t> epoch_{0};
  int64_t revision_ = -1;
  bool notified_ = false;
  bool remap_ = false;
  bool retry_ = false;
  bool stopping_ = false;
  std::atomic<bool> released_{true};
  std::atomic<bool> finished_{false};
  std::thread worker_;
};
}  // namespace lineup
#endif
