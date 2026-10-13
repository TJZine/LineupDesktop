#include "display_dynamic_range.h"

#include <cstdlib>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>

namespace {
using namespace lineup;
void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
bool Text(const char* actual, const char* expected) {
  return actual && std::string(actual) == expected;
}
const DisplayTarget a{{1, 0}, 1};
const DisplayTarget b{{1, 0}, 2};
struct FakeClock : DisplayClock {
  std::chrono::steady_clock::time_point now{};
  std::function<void()> on_sleep;
  std::chrono::steady_clock::time_point Now() override { return now; }
  void Sleep(std::chrono::milliseconds duration) override {
    now += duration;
    if (on_sleep) on_sleep();
  }
};
struct GuardianFacts {
  bool arm = true, update = true, alive = true, disarm = true;
  int arms = 0, updates = 0, disarms = 0;
  DisplayOwnership last;
};
struct FakeGuardian : DisplayGuardianLink {
  explicit FakeGuardian(std::shared_ptr<GuardianFacts> facts) : facts(facts) {}
  std::shared_ptr<GuardianFacts> facts;
  bool Arm(const DisplayOwnership& ownership) override {
    ++facts->arms;
    facts->last = ownership;
    return facts->arm;
  }
  bool Update(const DisplayOwnership& ownership) override {
    ++facts->updates;
    facts->last = ownership;
    return facts->update;
  }
  bool Disarm() override {
    ++facts->disarms;
    return facts->disarm;
  }
  bool IsAlive() override { return facts->alive; }
};
struct FakeApi : DisplayConfigApi {
  DisplayMapping mapping{a, nullptr};
  std::map<UINT32, DisplayObservation> displays{
      {1, {DisplayState::sdr, DisplayRoute::hdr_state, true, "sdr"}},
      {2, {DisplayState::hdr, DisplayRoute::advanced_color, true, "unknown"}}};
  bool accept = true, apply = true;
  int queries = 0, startup = 0;
  std::vector<std::pair<UINT32, DisplayState>> writes;
  std::function<void(DisplayTarget, DisplayState)> on_set;
  std::vector<std::thread::id> threads;
  DisplayMapping MapWindow(HWND) override {
    threads.push_back(std::this_thread::get_id());
    return mapping;
  }
  DisplayObservation Query(DisplayTarget target, DisplayRoute route) override {
    ++queries;
    threads.push_back(std::this_thread::get_id());
    auto observation = displays[target.id];
    if (route != DisplayRoute::none && observation.route != route) return {};
    return observation;
  }
  bool Set(DisplayTarget target, DisplayRoute, DisplayState state) override {
    threads.push_back(std::this_thread::get_id());
    writes.emplace_back(target.id, state);
    if (accept && apply) displays[target.id].state = state;
    if (on_set) on_set(target, state);
    return accept;
  }
  bool WaitForStartupRestore() override {
    ++startup;
    threads.push_back(std::this_thread::get_id());
    return true;
  }
};
struct Fixture {
  FakeApi api;
  FakeClock clock;
  std::shared_ptr<GuardianFacts> guardian = std::make_shared<GuardianFacts>();
  std::vector<DisplayReport> reports;
  bool restart = false;
  DisplayMatchingEngine engine{
      nullptr,
      api,
      [this] { return std::make_unique<FakeGuardian>(guardian); },
      clock,
      [this](const auto& report) { reports.push_back(report); },
      [this] { return restart; }};
  DisplayReport Last() const { return reports.back(); }
  void Request(int64_t revision, bool session, DisplayState desired) {
    engine.Process({revision, session, desired});
  }
};
void MatchingAndRestore() {
  Fixture f;
  f.Request(1, true, DisplayState::sdr);
  Check(f.api.writes.empty() && !f.Last().owned && !f.Last().wrote,
        "already matching capture");
  f.Request(2, true, DisplayState::hdr);
  Check(f.Last().owned && f.Last().wrote && Text(f.Last().outcome, "matched"),
        "SDR to HDR");
  Check(f.guardian->last.original == DisplayState::sdr && f.guardian->arms == 1,
        "original captured once");
  f.engine.Poll(false);
  Check(f.Last().revision == 2 && f.Last().wrote &&
            Text(f.Last().outcome, "matched"),
        "same revision notification preserves wrote for settle");
  f.Request(3, true, DisplayState::hdr);
  Check(f.api.writes.size() == 1 && !f.Last().wrote, "HDR to HDR no write");
  f.Request(4, true, DisplayState::sdr);
  Check(f.api.writes.size() == 2 && f.Last().observed == DisplayState::sdr,
        "HDR to SDR");
  f.Request(5, false, DisplayState::unknown);
  Check(!f.engine.HasOwnership() && f.guardian->disarms == 1,
        "release disarms");
  Fixture original_hdr;
  original_hdr.api.displays[1].state = DisplayState::hdr;
  original_hdr.Request(1, true, DisplayState::sdr);
  original_hdr.Request(2, false, DisplayState::unknown);
  Check(original_hdr.api.displays[1].state == DisplayState::hdr,
        "restore original HDR");
}
void FailedAndLateWrites() {
  Fixture rejected;
  rejected.api.accept = false;
  rejected.Request(1, true, DisplayState::hdr);
  Check(Text(rejected.Last().reason, "set_rejected") &&
            rejected.Last().observed == DisplayState::sdr,
        "rejected set observed state");
  Check(rejected.engine.HasOwnership() &&
            rejected.guardian->last.attempted == DisplayState::hdr,
        "rejected attempt retained");
  Fixture late;
  late.api.apply = false;
  late.Request(1, true, DisplayState::hdr);
  Check(Text(late.Last().reason, "not_observed") &&
            late.clock.now.time_since_epoch() == std::chrono::seconds(3),
        "three second verification deadline");
  Check(late.guardian->last.attempted == DisplayState::hdr &&
            late.engine.HasOwnership(),
        "timeout ownership retained");
  late.engine.Poll(false);
  Check(!Text(late.Last().session, "suspended"),
        "unobserved attempt not external");
  late.api.displays[1].state = DisplayState::hdr;
  late.engine.Poll(false);
  Check(Text(late.Last().session, "active"), "late observation accepted");
  Check(late.guardian->last.verified == DisplayState::hdr,
        "late verified success recorded in guardian");
  late.api.apply = true;
  late.Request(2, false, DisplayState::unknown);
  Check(late.api.displays[1].state == DisplayState::sdr &&
            !late.engine.HasOwnership(),
        "late success restored");
  Fixture stale;
  stale.Request(1, true, DisplayState::hdr);
  stale.Request(3, true, DisplayState::sdr);
  Check(stale.api.writes.size() == 2 && stale.Last().revision == 3 &&
            stale.Last().observed == DisplayState::sdr,
        "stale success reconciled newest desired");
}
void FailedIntentRetryGates() {
  for (bool accepted : {false, true}) {
    Fixture f;
    f.api.accept = accepted;
    f.api.apply = false;
    f.Request(1, true, DisplayState::hdr);
    for (int i = 0; i < 4; ++i)
      f.engine.Poll(false);
    Check(f.api.writes.size() == 1 && f.Last().observed == DisplayState::sdr &&
              Text(f.Last().outcome, "failed") &&
              Text(f.Last().reason, accepted ? "not_observed" : "set_rejected"),
          "failed intent polls observe without repeating Set");
    f.Request(2, true, DisplayState::hdr);
    f.engine.Poll(true);
    Check(f.api.writes.size() == 1,
          "same intent new revision and same-target movement do not retry");
    f.engine.Poll(false, true);
    for (int i = 0; i < 3; ++i)
      f.engine.Poll(false);
    Check(f.api.writes.size() == 2,
          "settings notification permits exactly one more attempt");
    f.engine.Process({3, true, DisplayState::hdr}, true, true);
    f.engine.Poll(false);
    Check(f.api.writes.size() == 3,
          "display notification with queued same intent permits one attempt");
    f.Request(4, true, DisplayState::unknown);
    f.Request(5, true, DisplayState::hdr);
    f.engine.Poll(false);
    Check(f.api.writes.size() == 4,
          "changed desired state permits one fresh attempt");
    f.Request(6, false, DisplayState::unknown);
    f.Request(7, true, DisplayState::hdr);
    f.engine.Poll(false);
    Check(f.api.writes.size() == 5,
          "new session permits one fresh attempt and inherits ownership");
  }
  Fixture late;
  late.api.apply = false;
  late.Request(1, true, DisplayState::hdr);
  late.api.displays[1].state = DisplayState::hdr;
  late.engine.Poll(false);
  Check(late.api.writes.size() == 1 && Text(late.Last().outcome, "matched") &&
            late.guardian->last.verified == DisplayState::hdr,
        "blocked retry still observes and records late success");
  late.Request(2, true, DisplayState::sdr);
  late.engine.Poll(false);
  Check(late.api.writes.size() == 2 && Text(late.Last().reason, "not_observed"),
        "opposite desired state permits one attempt after late success");
}
void ExternalChanges() {
  Fixture before;
  before.Request(1, true, DisplayState::unknown);
  before.api.displays[1].state = DisplayState::hdr;
  before.engine.Poll(false);
  Check(Text(before.Last().session, "suspended") && before.api.writes.empty(),
        "external before write suspended");
  before.Request(2, true, DisplayState::sdr);
  Check(before.api.writes.empty(), "suspension does not reverse user change");
  Fixture after;
  after.Request(1, true, DisplayState::hdr);
  after.api.displays[1].state = DisplayState::sdr;
  after.engine.Poll(false);
  Check(Text(after.Last().reason, "external_change") &&
            !after.engine.HasOwnership() && after.guardian->disarms == 1,
        "external after write relinquishes ownership");
  after.Request(2, false, DisplayState::unknown);
  Check(after.api.writes.size() == 1, "no restore after external change");
  Fixture release_external;
  release_external.Request(1, true, DisplayState::hdr);
  release_external.api.displays[1].state = DisplayState::sdr;
  release_external.Request(2, false, DisplayState::unknown);
  Check(release_external.api.writes.size() == 1 &&
            !release_external.engine.HasOwnership(),
        "release does not reverse an already restored external state");
}
void RestoreFailureAndInheritance() {
  Fixture queued;
  queued.Request(1, true, DisplayState::hdr);
  queued.restart = true;
  queued.Request(2, false, DisplayState::unknown);
  Check(queued.api.writes.size() == 1 && queued.engine.HasOwnership() &&
            queued.guardian->disarms == 0,
        "already queued same-target restart skips restoration");
  queued.Request(3, true, DisplayState::hdr);
  Check(queued.api.writes.size() == 1 && queued.guardian->arms == 1 &&
            queued.guardian->last.original == DisplayState::sdr,
        "queued restart inherits original and matching state without writes");
  queued.restart = false;
  queued.Request(4, false, DisplayState::unknown);
  Check(queued.api.writes.size() == 2 && !queued.engine.HasOwnership() &&
            queued.api.displays[1].state == DisplayState::sdr,
        "queued restart eventually releases the inherited original");
  Fixture moved;
  moved.Request(1, true, DisplayState::hdr);
  moved.restart = true;
  moved.api.mapping = {b, nullptr};
  moved.Request(2, false, DisplayState::unknown);
  Check(moved.api.writes.size() == 2 &&
            moved.api.displays[1].state == DisplayState::sdr,
        "queued restart on another target does not skip old-target restore");

  Fixture failed;
  failed.Request(1, true, DisplayState::hdr);
  failed.api.accept = false;
  failed.Request(2, false, DisplayState::unknown);
  Check(failed.engine.HasOwnership() && failed.guardian->disarms == 0 &&
            Text(failed.Last().reason, "restore_failed"),
        "failed restore remains armed");
  failed.api.accept = true;
  failed.engine.Poll(false);
  Check(!failed.engine.HasOwnership() && failed.guardian->disarms == 1,
        "restore retry");
  Fixture inherit;
  inherit.Request(1, true, DisplayState::hdr);
  // A start arrives while a restore is blocked in the Windows setter.
  inherit.api.on_set = [&inherit](auto, auto) { inherit.restart = true; };
  inherit.Request(2, false, DisplayState::unknown);
  Check(inherit.api.writes.size() == 2 && inherit.engine.HasOwnership() &&
            inherit.guardian->disarms == 0,
        "inflight restart retains original");
  inherit.Request(3, true, DisplayState::hdr);
  Check(inherit.api.writes.size() == 3 && inherit.guardian->arms == 1 &&
            inherit.guardian->last.original == DisplayState::sdr,
        "restart inherits guardian and original");
  inherit.restart = false;
  inherit.api.on_set = {};
  inherit.Request(4, false, DisplayState::unknown);
  Check(inherit.api.displays[1].state == DisplayState::sdr &&
            !inherit.engine.HasOwnership(),
        "inherited restore");
}
void TargetLossAndChange() {
  Fixture lost;
  lost.Request(1, true, DisplayState::hdr);
  lost.api.mapping = {};
  lost.api.displays[1].state = DisplayState::unknown;
  lost.engine.Poll(true);
  Check(lost.engine.HasOwnership() && Text(lost.Last().session, "unavailable"),
        "lost target retains ownership");
  lost.Request(2, false, DisplayState::unknown);
  lost.api.displays[1].state = DisplayState::hdr;
  lost.engine.Poll(false);
  Check(lost.api.displays[1].state == DisplayState::sdr &&
            !lost.engine.HasOwnership(),
        "reappeared target restored");
  Fixture inherit;
  inherit.Request(1, true, DisplayState::hdr);
  inherit.api.mapping = {};
  inherit.api.displays[1].state = DisplayState::unknown;
  inherit.engine.Poll(true);
  inherit.api.mapping = {a, nullptr};
  inherit.api.displays[1].state = DisplayState::hdr;
  inherit.engine.Poll(true);
  Check(inherit.guardian->arms == 1 && Text(inherit.Last().session, "active"),
        "reappeared session inherits");
  Fixture moved;
  moved.Request(1, true, DisplayState::hdr);
  moved.api.mapping = {b, nullptr};
  moved.engine.Poll(true);
  Check(moved.api.displays[1].state == DisplayState::sdr &&
            moved.guardian->disarms == 1 &&
            moved.Last().route == DisplayRoute::advanced_color,
        "target move releases old starts new");
}
void TargetSessionReportEdges() {
  constexpr int64_t revision = 7;
  for (bool owned : {false, true}) {
    Fixture moved;
    moved.Request(revision, true,
                  owned ? DisplayState::hdr : DisplayState::sdr);
    Check(moved.engine.HasOwnership() == owned, "target edge ownership setup");
    moved.reports.clear();
    moved.engine.Poll(true);
    for (const auto& report : moved.reports) {
      Check(report.revision == revision && !Text(report.session, "inactive"),
            "same-target polling does not retire session");
    }
    moved.reports.clear();
    moved.api.mapping = {b, nullptr};
    moved.api.on_set = [&moved](auto, auto) {
      Check(!moved.reports.empty() &&
                Text(moved.reports.front().session, "inactive"),
            "inactive edge precedes target restoration and new-target writes");
    };
    moved.engine.Poll(true);
    Check(!moved.reports.empty() &&
              Text(moved.reports.front().session, "inactive") &&
              Text(moved.reports.back().session, "active"),
          "capable target remap publishes ordered inactive then active");
    bool saw_active = false;
    for (const auto& report : moved.reports) {
      Check(report.revision == revision,
            "target remap retains request revision");
      if (Text(report.session, "active")) saw_active = true;
      Check(!saw_active || !Text(report.session, "inactive"),
            "retirement reports precede all new-session active reports");
    }

    Fixture lost;
    lost.Request(revision, true, owned ? DisplayState::hdr : DisplayState::sdr);
    lost.reports.clear();
    lost.api.mapping = {};
    lost.api.displays[1].state = DisplayState::unknown;
    lost.engine.Poll(true);
    Check(!lost.reports.empty() &&
              Text(lost.reports.front().session, "inactive") &&
              Text(lost.reports.back().session, "unavailable"),
          "target disappearance publishes ordered inactive then unavailable");
    for (const auto& report : lost.reports)
      Check(report.revision == revision,
            "disappearance retains request revision");
    // Repeated failure to map has no further target/session to retire.
    lost.reports.clear();
    lost.engine.Poll(true);
    for (const auto& report : lost.reports)
      Check(!Text(report.session, "inactive"),
            "missing target does not repeat retirement edge");
  }
}
void AvailabilityAndRoutes() {
  Fixture ambiguous;
  ambiguous.api.mapping = {std::nullopt, "ambiguous_target"};
  ambiguous.Request(1, true, DisplayState::hdr);
  Check(Text(ambiguous.Last().reason, "ambiguous_target") &&
            ambiguous.api.writes.empty(),
        "ambiguous mapping");
  Fixture unsupported;
  unsupported.api.displays[1] = {};
  unsupported.Request(1, true, DisplayState::hdr);
  Check(Text(unsupported.Last().reason, "unsupported_api") &&
            unsupported.api.writes.empty(),
        "unsupported API");
  Fixture incapable;
  incapable.api.displays[1].capable = false;
  incapable.Request(1, true, DisplayState::hdr);
  Check(Text(incapable.Last().reason, "not_hdr_capable") &&
            incapable.api.writes.empty(),
        "incapable target");
  Fixture unknown;
  unknown.api.displays[1].state = DisplayState::unknown;
  unknown.Request(1, true, DisplayState::hdr);
  Check(Text(unknown.Last().reason, "state_unknown") &&
            unknown.api.writes.empty(),
        "unknown state");
  Fixture policy;
  policy.api.displays[1].state = DisplayState::hdr;
  policy.api.displays[1].active_color_mode = "sdr";
  policy.Request(1, true, DisplayState::hdr);
  Check(policy.api.writes.empty() &&
            policy.Last().observed == DisplayState::hdr &&
            Text(policy.Last().active_color_mode, "sdr"),
        "user enabled separate from active mode");
  Fixture legacy;
  legacy.api.mapping = {b, nullptr};
  legacy.Request(1, true, DisplayState::sdr);
  Check(legacy.Last().route == DisplayRoute::advanced_color &&
            legacy.Last().wrote,
        "legacy route");
}
void UnavailableTargetRecovery() {
  const DisplayObservation unavailable[] = {
      {},
      {DisplayState::sdr, DisplayRoute::hdr_state, false, "sdr"},
      {DisplayState::unknown, DisplayRoute::hdr_state, true, "unknown"}};
  for (const auto& observation : unavailable) {
    for (bool remap : {false, true}) {
      Fixture f;
      f.api.displays[1] = observation;
      f.Request(1, true, DisplayState::hdr);
      Check(Text(f.Last().session, "unavailable") && f.api.writes.empty(),
            "unavailable target starts without ownership");
      const int queries = f.api.queries;
      f.api.displays[1] =
          {DisplayState::sdr, DisplayRoute::hdr_state, true, "sdr"};
      f.engine.Poll(false);
      f.engine.Poll(true);
      f.Request(2, true, DisplayState::hdr);
      Check(f.api.queries == queries && f.api.writes.empty(),
            "ordinary polling, movement and revisions do not retry availability");
      if (remap)
        f.engine.Process({2, true, DisplayState::hdr}, true, true);
      else
        f.engine.Poll(false, true);
      Check(Text(f.Last().session, "active") &&
                Text(f.Last().outcome, "matched") &&
                f.Last().revision == 2 && f.api.writes.size() == 1 &&
                f.guardian->arms == 1 &&
                f.guardian->last.original == DisplayState::sdr,
            "display/settings notice recovers the same target and captures once");
      f.engine.Poll(false);
      Check(f.api.writes.size() == 1, "recovered match does not repeat writes");
      f.Request(3, false, DisplayState::unknown);
      Check(f.api.displays[1].state == DisplayState::sdr &&
                !f.engine.HasOwnership(),
            "recovered session restores its captured original");
    }
  }
  Fixture still_unavailable;
  still_unavailable.api.displays[1] = {};
  still_unavailable.Request(1, true, DisplayState::hdr);
  still_unavailable.engine.Poll(false, true);
  const int queries = still_unavailable.api.queries;
  still_unavailable.engine.Poll(false);
  Check(Text(still_unavailable.Last().session, "unavailable") &&
            still_unavailable.api.queries == queries &&
            still_unavailable.api.writes.empty(),
        "unsuccessful availability retry does not enable polling retries");
  still_unavailable.Request(2, false, DisplayState::unknown);
  still_unavailable.engine.Poll(true, true);
  Check(Text(still_unavailable.Last().session, "inactive"),
        "notice does not start an ended session");
  Fixture suspended;
  suspended.Request(1, true, DisplayState::hdr);
  suspended.api.displays[1].state = DisplayState::sdr;
  suspended.engine.Poll(false);
  suspended.engine.Poll(false, true);
  suspended.engine.Poll(true, true);
  Check(Text(suspended.Last().session, "suspended") &&
            suspended.api.writes.size() == 1 && !suspended.engine.HasOwnership(),
        "availability retry never overrides an external user change");
}
void GuardianGates() {
  Fixture arm;
  arm.guardian->arm = false;
  arm.Request(1, true, DisplayState::hdr);
  Check(Text(arm.Last().reason, "guardian_unavailable") &&
            arm.api.writes.empty() && !arm.engine.HasOwnership(),
        "missing arm acknowledgment fail closed");
  Fixture update;
  update.guardian->update = false;
  update.Request(1, true, DisplayState::hdr);
  Check(update.api.writes.empty() &&
            Text(update.Last().reason, "guardian_unavailable"),
        "update gate");
  Fixture lost;
  lost.Request(1, true, DisplayState::hdr);
  lost.guardian->alive = false;
  lost.Request(2, true, DisplayState::sdr);
  Check(lost.api.writes.size() == 1 &&
            Text(lost.Last().reason, "guardian_unavailable"),
        "lost guardian blocks writes");
  lost.Request(3, false, DisplayState::unknown);
  Check(lost.api.displays[1].state == DisplayState::sdr,
        "normal restore after guardian loss");
  Fixture acknowledgment;
  acknowledgment.api.on_set = [&acknowledgment](auto, auto) {
    acknowledgment.guardian->update = false;
  };
  acknowledgment.Request(1, true, DisplayState::hdr);
  Check(Text(acknowledgment.Last().reason, "guardian_unavailable") &&
            acknowledgment.engine.HasOwnership(),
        "post-write acknowledgment failure retains ownership");
  acknowledgment.Request(2, true, DisplayState::sdr);
  Check(acknowledgment.api.writes.size() == 1,
        "post-write acknowledgment loss blocks future matching writes");
}
void WorkerOrderingAndIsolation(bool remap) {
  auto api = std::make_unique<FakeApi>();
  auto* facts = api.get();
  auto guardian = std::make_shared<GuardianFacts>();
  std::mutex mutex;
  std::condition_variable changed;
  std::vector<DisplayReport> reports;
  DisplayDynamicRange* controller = nullptr;
  int sets = 0;
  facts->on_set = [&](auto, auto) {
    if (++sets == 1) {
      Check(controller->Submit({2, true, DisplayState::hdr}),
            "enqueue desired");
      Check(controller->Submit({3, true, DisplayState::sdr}),
            "coalesce newest desired");
      if (remap) {
        facts->mapping = {b, nullptr};
        controller->Notify(true);
      }
    }
  };
  {
    DisplayDynamicRange worker(
        nullptr, std::move(api),
        [guardian] { return std::make_unique<FakeGuardian>(guardian); },
        [&](const auto& report) {
          std::lock_guard lock(mutex);
          reports.push_back(report);
          changed.notify_all();
        },
        [] {}, std::make_unique<FakeClock>());
    controller = &worker;
    Check(worker.Submit({1, true, DisplayState::hdr}),
          "initial worker request");
    Check(!worker.Submit({1, true, DisplayState::sdr}),
          "stale revision rejected");
    std::unique_lock lock(mutex);
    Check(changed.wait_for(lock, std::chrono::seconds(3),
                           [&] {
                             return !reports.empty() &&
                                    reports.back().revision == 3 &&
                                    Text(reports.back().session, "active") &&
                                    Text(reports.back().outcome, "matched");
                           }),
          "worker newest revision completes");
    Check(reports.back().observed == DisplayState::sdr,
          "worker reconciled stale success");
    if (remap)
      Check(reports.back().route == DisplayRoute::advanced_color,
            "queued request plus remap uses new target");
    lock.unlock();
    worker.EndSessionAndWait(std::chrono::seconds(3));
    Check(worker.ReleaseComplete(), "worker ordered release");
    worker.ResetRevision();
    Check(worker.Submit({1, true, DisplayState::unknown}),
          "hot restart accepts reset revision");
    worker.EndSessionAndWait(std::chrono::seconds(3));
    Check(facts->startup == 1, "one startup restoration wait");
    for (auto thread : facts->threads)
      Check(thread != std::this_thread::get_id(),
            "all API calls worker confined");
    Check(facts->writes.size() == (remap ? 4u : 2u),
          "only latest desired writes and required restores");
    if (remap)
      Check(facts->writes[1].first == a.id &&
                facts->writes[1].second == DisplayState::sdr &&
                facts->writes[2].first == b.id,
            "queued remap restores old target then matches new");
  }
}
}  // namespace
int main() {
  try {
    MatchingAndRestore();
    FailedAndLateWrites();
    FailedIntentRetryGates();
    ExternalChanges();
    RestoreFailureAndInheritance();
    TargetLossAndChange();
    TargetSessionReportEdges();
    AvailabilityAndRoutes();
    UnavailableTargetRecovery();
    GuardianGates();
    WorkerOrderingAndIsolation(false);
    WorkerOrderingAndIsolation(true);
    std::cout
        << "display_dynamic_range: all fake API/guardian/clock checks passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception& error) {
    std::cerr << "display_dynamic_range: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
