// Only this translation unit exposes newer SDK declarations. Runtime queries
// select the legacy route on Windows 10; no newer imported entry point is used.
#ifdef NTDDI_VERSION
#undef NTDDI_VERSION
#endif
#define NTDDI_VERSION 0x0A00000F
#include "display_dynamic_range.h"

#include <algorithm>
#include <exception>
#include <iostream>

namespace lineup {
namespace {
template <typename T>
T DeviceInfo(DISPLAYCONFIG_DEVICE_INFO_TYPE type, DisplayTarget target) {
  T info{};
  info.header.type = type;
  info.header.size = sizeof(T);
  info.header.adapterId = target.adapter;
  info.header.id = target.id;
  return info;
}
class WindowsDisplayConfig final : public DisplayConfigApi {
 public:
  DisplayMapping MapWindow(HWND window) override {
    MONITORINFOEXW monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                         &monitor))
      return {};
    // Topology can change between sizing and query. Retry a bounded number.
    for (int retry = 0; retry < 3; ++retry) {
      UINT32 paths_count = 0, modes_count = 0;
      if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &paths_count,
                                      &modes_count) != ERROR_SUCCESS)
        return {};
      std::vector<DISPLAYCONFIG_PATH_INFO> paths(paths_count);
      std::vector<DISPLAYCONFIG_MODE_INFO> modes(modes_count);
      LONG status =
          QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &paths_count, paths.data(),
                             &modes_count, modes.data(), nullptr);
      if (status == ERROR_INSUFFICIENT_BUFFER) continue;
      if (status != ERROR_SUCCESS) return {};
      std::optional<DisplayTarget> found;
      for (UINT32 i = 0; i < paths_count; ++i) {
        const auto& path = paths[i];
        auto source = DeviceInfo<DISPLAYCONFIG_SOURCE_DEVICE_NAME>(
            DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
            {path.sourceInfo.adapterId, path.sourceInfo.id});
        if (DisplayConfigGetDeviceInfo(&source.header) == ERROR_SUCCESS &&
            wcscmp(source.viewGdiDeviceName, monitor.szDevice) == 0) {
          if (found) return {std::nullopt, "ambiguous_target"};
          found = DisplayTarget{path.targetInfo.adapterId, path.targetInfo.id};
        }
      }
      return {found, found ? nullptr : "target_lost"};
    }
    return {};
  }
  DisplayObservation Query(DisplayTarget target, DisplayRoute route) override {
    if (route != DisplayRoute::advanced_color) {
      auto info = DeviceInfo<DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO_2>(
          DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO_2, target);
      if (DisplayConfigGetDeviceInfo(&info.header) == ERROR_SUCCESS) {
        const char* mode = "unknown";
        switch (info.activeColorMode) {
          case DISPLAYCONFIG_ADVANCED_COLOR_MODE_SDR:
            mode = "sdr";
            break;
          case DISPLAYCONFIG_ADVANCED_COLOR_MODE_WCG:
            mode = "wcg";
            break;
          case DISPLAYCONFIG_ADVANCED_COLOR_MODE_HDR:
            mode = "hdr";
            break;
        }
        return {info.highDynamicRangeUserEnabled ? DisplayState::hdr
                                                 : DisplayState::sdr,
                DisplayRoute::hdr_state, info.highDynamicRangeSupported != 0,
                mode};
      }
      if (route == DisplayRoute::hdr_state) return {};
    }
    auto info = DeviceInfo<DISPLAYCONFIG_GET_ADVANCED_COLOR_INFO>(
        DISPLAYCONFIG_DEVICE_INFO_GET_ADVANCED_COLOR_INFO, target);
    if (DisplayConfigGetDeviceInfo(&info.header) != ERROR_SUCCESS) return {};
    return {info.advancedColorEnabled ? DisplayState::hdr : DisplayState::sdr,
            DisplayRoute::advanced_color, info.advancedColorSupported != 0,
            "unknown"};
  }
  bool Set(DisplayTarget target, DisplayRoute route,
           DisplayState state) override {
    if (state == DisplayState::unknown) return false;
    if (route == DisplayRoute::hdr_state) {
      auto info = DeviceInfo<DISPLAYCONFIG_SET_HDR_STATE>(
          DISPLAYCONFIG_DEVICE_INFO_SET_HDR_STATE, target);
      info.enableHdr = state == DisplayState::hdr;
      return DisplayConfigSetDeviceInfo(&info.header) == ERROR_SUCCESS;
    }
    if (route == DisplayRoute::advanced_color) {
      auto info = DeviceInfo<DISPLAYCONFIG_SET_ADVANCED_COLOR_STATE>(
          DISPLAYCONFIG_DEVICE_INFO_SET_ADVANCED_COLOR_STATE, target);
      info.enableAdvancedColor = state == DisplayState::hdr;
      return DisplayConfigSetDeviceInfo(&info.header) == ERROR_SUCCESS;
    }
    return false;
  }
  bool WaitForStartupRestore() override {
    HANDLE mutex = CreateMutexW(
        nullptr, FALSE, L"Local\\TJZine.LineupDesktop.DisplayGuardianRestore");
    if (!mutex) return false;
    DWORD result = WaitForSingleObject(mutex, 3000);
    if (result == WAIT_OBJECT_0 || result == WAIT_ABANDONED)
      ReleaseMutex(mutex);
    CloseHandle(mutex);
    return result == WAIT_OBJECT_0 || result == WAIT_ABANDONED;
  }
};
class SteadyDisplayClock final : public DisplayClock {
 public:
  std::chrono::steady_clock::time_point Now() override {
    return std::chrono::steady_clock::now();
  }
  void Sleep(std::chrono::milliseconds duration) override {
    std::this_thread::sleep_for(duration);
  }
};
bool IsOurState(const DisplayOwnership& own, DisplayState state) {
  return state != DisplayState::unknown &&
         (state == own.attempted || state == own.verified);
}
}  // namespace
const char* DisplayStateName(DisplayState state) {
  switch (state) {
    case DisplayState::sdr:
      return "sdr";
    case DisplayState::hdr:
      return "hdr";
    default:
      return "unknown";
  }
}
const char* DisplayRouteName(DisplayRoute route) {
  switch (route) {
    case DisplayRoute::hdr_state:
      return "hdr_state";
    case DisplayRoute::advanced_color:
      return "advanced_color";
    default:
      return "none";
  }
}
std::unique_ptr<DisplayConfigApi> MakeDisplayConfigApi() {
  return std::make_unique<WindowsDisplayConfig>();
}
std::unique_ptr<DisplayClock> MakeDisplayClock() {
  return std::make_unique<SteadyDisplayClock>();
}
DisplayGuardianFactory UnavailableDisplayGuardian() {
  return [] { return std::unique_ptr<DisplayGuardianLink>(); };
}
DisplayMatchingEngine::DisplayMatchingEngine(
    HWND window, DisplayConfigApi& api, DisplayGuardianFactory guardian,
    DisplayClock& clock, Reporter report, std::function<bool()> restart_pending)
    : window_(window),
      api_(api),
      guardian_(std::move(guardian)),
      clock_(clock),
      report_(std::move(report)),
      restart_pending_(std::move(restart_pending)) {}
DisplayMatchingEngine::Record* DisplayMatchingEngine::Find(
    DisplayTarget target) {
  for (auto& record : records_)
    if (record->ownership.target == target) return record.get();
  return nullptr;
}
bool DisplayMatchingEngine::HasOwnership() const {
  for (const auto& record : records_)
    if (record->owned) return true;
  return false;
}
void DisplayMatchingEngine::Report(Record* record, const char* outcome,
                                   bool wrote, const char* reason) {
  DisplayReport report;
  report.revision = request_.revision;
  report.session = session_;
  report.outcome = outcome;
  report.wrote = wrote;
  report.reason = reason;
  if (record) {
    report.wrote = wrote || record->write_revision == request_.revision;
    report.observed = record->observed.state;
    report.route = record->ownership.route;
    report.active_color_mode = record->observed.active_color_mode;
    report.owned = record->owned;
  }
  report_(report);
}
void DisplayMatchingEngine::Process(DisplayRequest request, bool remap) {
  const bool was_active = request_.session;
  request_ = request;
  if (!request.session) {
    Record* ending = active_ ? Find(*active_) : nullptr;
    session_ = "inactive";
    active_.reset();
    ReleaseAll();
    Report(ending, HasOwnership() ? "failed" : "idle", false,
           HasOwnership() ? "restore_failed" : nullptr);
  } else if (!was_active) {
    Start();
  } else if (remap) {
    Poll(true);
  } else if (session_ == std::string("active")) {
    Reconcile();
  } else {
    Report(active_ ? Find(*active_) : nullptr, "idle", false, session_reason_);
  }
}
void DisplayMatchingEngine::Start() {
  const auto mapping = api_.MapWindow(window_);
  if (!mapping.target) {
    session_ = "unavailable";
    session_reason_ = mapping.reason;
    Report(nullptr, "idle", false, mapping.reason);
    return;
  }
  active_ = mapping.target;
  Record* record = Find(*active_);
  if (!record || !record->owned) {
    const auto observation = api_.Query(*active_, DisplayRoute::none);
    if (observation.route == DisplayRoute::none || !observation.capable ||
        observation.state == DisplayState::unknown) {
      session_ = "unavailable";
      session_reason_ = observation.route == DisplayRoute::none
                            ? "unsupported_api"
                        : !observation.capable ? "not_hdr_capable"
                                               : "state_unknown";
      Record unavailable;
      unavailable.observed = observation;
      unavailable.ownership.route = observation.route;
      Report(&unavailable, "idle", false,
             observation.route == DisplayRoute::none ? "unsupported_api"
             : !observation.capable                  ? "not_hdr_capable"
                                                     : "state_unknown");
      return;
    }
    if (!record) {
      records_.push_back(std::make_unique<Record>());
      record = records_.back().get();
    }
    record->ownership = {*active_, observation.route, observation.state,
                         DisplayState::unknown, DisplayState::unknown};
    record->observed = observation;
    record->guardian_lost = false;
    record->unobserved_attempt = false;
    record->write_revision = -1;
  }
  session_ = "active";
  session_reason_ = nullptr;
  Reconcile();
}
void DisplayMatchingEngine::Suspend(Record& record) {
  if (record.guardian) record.guardian->Disarm();
  record.guardian.reset();
  record.owned = false;
  session_ = "suspended";
  session_reason_ = "external_change";
  Report(&record, "idle", false, "external_change");
}
bool DisplayMatchingEngine::Write(Record& record, DisplayState desired,
                                  bool restore) {
  auto& own = record.ownership;
  if (!restore && (!record.guardian || !record.guardian->IsAlive() ||
                   record.guardian_lost)) {
    record.guardian_lost = true;
    Report(&record, "failed", false, "guardian_unavailable");
    return false;
  }
  const auto previous_attempt = own.attempted;
  own.attempted = desired;
  // Restoration remains best-effort after guardian loss. New matching writes
  // require an acknowledged attempted-state update before touching Windows.
  if (record.guardian && !record.guardian->Update(own)) {
    record.guardian_lost = true;
    if (!restore) {
      own.attempted = previous_attempt;
      Report(&record, "failed", false, "guardian_unavailable");
      return false;
    }
  }
  record.owned = true;
  record.unobserved_attempt = true;
  record.write_revision = request_.revision;
  Report(&record, "pending", true);
  const bool accepted = api_.Set(own.target, own.route, desired);
  bool verified = false;
  const auto deadline = clock_.Now() + std::chrono::seconds(3);
  do {
    record.observed = api_.Query(own.target, own.route);
    if (record.observed.state == desired) {
      verified = true;
      break;
    }
    if (!accepted || clock_.Now() >= deadline) break;
    clock_.Sleep(std::chrono::milliseconds(50));
  } while (true);
  if (verified) {
    own.verified = desired;
    record.unobserved_attempt = false;
  }
  // Never erase attempted on timeout: Windows may finish after our deadline.
  if (record.guardian && !record.guardian->Update(own))
    record.guardian_lost = true;
  Report(&record, verified && !record.guardian_lost ? "matched" : "failed",
         true,
         record.guardian_lost ? "guardian_unavailable"
         : verified           ? nullptr
         : restore            ? "restore_failed"
         : accepted           ? "not_observed"
                              : "set_rejected");
  return verified;
}
void DisplayMatchingEngine::Reconcile() {
  if (!active_) return;
  Record* record = Find(*active_);
  if (!record) return;
  record->observed = api_.Query(*active_, record->ownership.route);
  if (record->observed.state == DisplayState::unknown) {
    session_ = "unavailable";
    session_reason_ = "target_lost";
    Report(record, "failed", false, "target_lost");
    active_.reset();
    return;
  }
  auto& own = record->ownership;
  if (!(record->owned ? IsOurState(own, record->observed.state) ||
                            (record->unobserved_attempt &&
                             record->observed.state == own.original)
                      : record->observed.state == own.original)) {
    Suspend(*record);
    return;
  }
  if (record->unobserved_attempt && record->observed.state == own.attempted) {
    record->unobserved_attempt = false;
    own.verified = own.attempted;
    if (record->guardian && !record->guardian->Update(own))
      record->guardian_lost = true;
  }
  // Before any attempted change, even the original is the expected state.
  if (record->owned && record->guardian && !record->guardian->IsAlive()) {
    record->guardian_lost = true;
  }
  if (record->guardian_lost) {
    Report(record, "failed", false, "guardian_unavailable");
    return;
  }
  if (request_.desired == DisplayState::unknown) {
    Report(record, "idle", false);
    return;
  }
  if (record->observed.state == request_.desired) {
    Report(record, "matched", false);
    return;
  }
  if (!record->owned) {
    record->guardian = guardian_();
    if (!record->guardian || !record->guardian->Arm(record->ownership)) {
      record->guardian_lost = true;
      Report(record, "failed", false, "guardian_unavailable");
      return;
    }
  }
  Write(*record, request_.desired, false);
}
void DisplayMatchingEngine::Release(Record& record) {
  if (!record.owned) return;
  auto& own = record.ownership;
  record.observed = api_.Query(own.target, own.route);
  if (record.observed.state == DisplayState::unknown) {
    Report(&record, "failed", false, "target_lost");
    return;
  }
  if (record.unobserved_attempt && record.observed.state == own.original &&
      own.attempted != own.original) {
    Report(&record, "failed", false, "restore_failed");
    return;
  }
  if (record.observed.state != own.original &&
      !IsOurState(own, record.observed.state)) {
    if (record.guardian) record.guardian->Disarm();
    record.guardian.reset();
    record.owned = false;
    return;
  }
  if (record.observed.state != own.original &&
      !Write(record, own.original, true))
    return;
  // A queued restart inherits the original even if it arrived during Set.
  if (restart_pending_ && restart_pending_()) return;
  if (record.guardian && !record.guardian->Disarm()) {
    record.guardian_lost = true;
    Report(&record, "failed", false, "restore_failed");
    return;
  }
  record.guardian.reset();
  record.owned = false;
}
void DisplayMatchingEngine::ReleaseAll() {
  for (auto& record : records_) Release(*record);
}
void DisplayMatchingEngine::Poll(bool remap) {
  if (request_.session && (remap || !active_)) {
    const auto mapping = api_.MapWindow(window_);
    if (!mapping.target || !active_ || !(*mapping.target == *active_)) {
      Record* retiring = active_ ? Find(*active_) : nullptr;
      // The same Dart revision can span a native target change. Publish the
      // session edge before restoration or starting the incoming target, so
      // the coordinator can distinguish it from ordinary active polling.
      if (active_) {
        session_ = "inactive";
        Report(retiring, "idle", false);
      }
      active_.reset();
      // The incoming target may already be owned from a disappearance or a
      // failed release. It must inherit its record, not restore and recapture.
      for (auto& record : records_) {
        if (!mapping.target || !(record->ownership.target == *mapping.target))
          Release(*record);
      }
      Start();
      return;
    }
  }
  if (request_.session && session_ == std::string("active")) Reconcile();
  for (auto& record : records_) {
    if (record->owned && (!active_ || !(record->ownership.target == *active_)))
      Release(*record);
  }
}

DisplayDynamicRange::DisplayDynamicRange(
    HWND window, std::unique_ptr<DisplayConfigApi> api,
    DisplayGuardianFactory guardian, DisplayMatchingEngine::Reporter reporter,
    std::function<void()> wakeup, std::unique_ptr<DisplayClock> clock)
    : window_(window),
      api_(std::move(api)),
      guardian_(std::move(guardian)),
      reporter_(std::move(reporter)),
      wakeup_(std::move(wakeup)),
      clock_(std::move(clock)),
      worker_([this] { Run(); }) {}
DisplayDynamicRange::~DisplayDynamicRange() {
  {
    std::lock_guard lock(mutex_);
    stopping_ = true;
    requests_.clear();
  }
  changed_.notify_one();
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!finished_ && std::chrono::steady_clock::now() < deadline) ::Sleep(10);
  if (!finished_) std::terminate();
  worker_.join();
}
bool DisplayDynamicRange::Submit(DisplayRequest request) {
  std::lock_guard lock(mutex_);
  if (stopping_ || request.revision <= revision_) return false;
  revision_ = request.revision;
  // Preserve edges; coalesce only consecutive desires within one session.
  if (!requests_.empty() && request.session && requests_.back().request.session)
    requests_.back() = {request, epoch_.load()};
  else
    requests_.push_back({request, epoch_.load()});
  released_ = false;
  changed_.notify_one();
  return true;
}
void DisplayDynamicRange::ResetRevision() {
  std::lock_guard lock(mutex_);
  revision_ = -1;
  epoch_.fetch_add(1);
  requests_.clear();
  requests_.push_back({{0, false, DisplayState::unknown}, epoch_.load()});
  released_ = false;
  changed_.notify_one();
}
void DisplayDynamicRange::Notify(bool remap) {
  std::lock_guard lock(mutex_);
  notified_ = true;
  remap_ = remap_ || remap;
  changed_.notify_one();
}
void DisplayDynamicRange::EndSession() {
  std::lock_guard lock(mutex_);
  requests_.push_back(
      {{std::max<int64_t>(revision_, 0), false, DisplayState::unknown},
       epoch_.load()});
  released_ = false;
  changed_.notify_one();
}
void DisplayDynamicRange::EndSessionAndWait(std::chrono::milliseconds timeout) {
  EndSession();
  std::unique_lock lock(mutex_);
  changed_.wait_for(lock, timeout, [this] { return released_.load(); });
}
void DisplayDynamicRange::Run() {
  if (!api_->WaitForStartupRestore()) {
    std::cerr << "[lineup-display] startup_restore_wait_timeout" << std::endl;
  }
  uint64_t processing_epoch = epoch_.load();
  DisplayMatchingEngine engine(
      window_, *api_, guardian_, *clock_,
      [this, &processing_epoch](const DisplayReport& report) {
        std::lock_guard lock(mutex_);
        if (processing_epoch == epoch_.load()) reporter_(report);
      },
      [this] {
        std::lock_guard lock(mutex_);
        return std::any_of(requests_.begin(), requests_.end(),
                           [](const auto& r) { return r.request.session; });
      });
  while (true) {
    std::optional<Pending> request;
    bool remap = false;
    bool stop = false;
    {
      std::unique_lock lock(mutex_);
      changed_.wait_for(lock, std::chrono::seconds(2), [this] {
        return stopping_ || notified_ || !requests_.empty();
      });
      stop = stopping_;
      remap = remap_;
      notified_ = remap_ = false;
      if (!requests_.empty()) {
        request = requests_.front();
        requests_.pop_front();
      }
    }
    if (stop) {
      engine.Process({0, false, DisplayState::unknown});
      break;
    }
    if (request) {
      processing_epoch = request->epoch;
      engine.Process(request->request, remap);
    } else if (engine.SessionActive() || engine.HasOwnership())
      engine.Poll(remap);
    {
      std::lock_guard lock(mutex_);
      released_ = requests_.empty() && !engine.SessionActive() &&
                  !engine.HasOwnership();
    }
    changed_.notify_all();
    wakeup_();
  }
  finished_ = true;
  changed_.notify_all();
}
}  // namespace lineup
