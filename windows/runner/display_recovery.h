#ifndef RUNNER_DISPLAY_RECOVERY_H_
#define RUNNER_DISPLAY_RECOVERY_H_

#include "display_dynamic_range.h"

namespace lineup {
enum class RestorationDecision {
  target_unknown,
  unresolved_attempt,
  already_original,
  external_change,
  restore_original,
};
// Live history uses unobserved_attempt; durable history derives uncertainty
// from the journal. They can diverge when Execute refuses after journaling,
// Update journals but its pipe send fails and memory rolls attempted back, or
// Reconcile observes the attempt but its guardian Update fails.
struct RestorationHistory {
  DisplayOwnership ownership;
  bool attempt_may_land_late;
};
constexpr bool DurableAttemptMayLandLate(const DisplayOwnership& own) {
  return own.attempted != DisplayState::unknown &&
         own.attempted != own.original && own.verified != own.attempted;
}
constexpr RestorationDecision ClassifyRestoration(
    const RestorationHistory& history, DisplayState observed) {
  const auto& own = history.ownership;
  if (observed == DisplayState::unknown)
    return RestorationDecision::target_unknown;
  if (observed == own.original) {
    if (history.attempt_may_land_late && own.attempted != own.original)
      return RestorationDecision::unresolved_attempt;
    return RestorationDecision::already_original;
  }
  if (observed != own.verified && observed != own.attempted)
    return RestorationDecision::external_change;
  return RestorationDecision::restore_original;
}

struct RecoveryIdentity {
  uint32_t owner_pid = 0;
  uint32_t owner_created_low = 0;
  uint32_t owner_created_high = 0;
  uint32_t record_id = 0;
  bool operator==(const RecoveryIdentity &other) const {
    return owner_pid == other.owner_pid &&
           owner_created_low == other.owner_created_low &&
           owner_created_high == other.owner_created_high &&
           record_id == other.record_id;
  }
};

// Shared conditional restoration policy. True establishes a known safe state;
// false retains unknown state, failed verification and possible late writes.
bool RestoreDisplayOwnership(const DisplayOwnership &ownership,
                             DisplayConfigApi &api);

// Native process admission and durable recovery authority. The short gate is
// held only for journal/display transactions, never across an IPC wait or the
// lifetime of a guardian. A missing helper/mutex is not a resolved target.
class DisplayRecoveryCoordinator {
public:
  DisplayRecoveryCoordinator(std::wstring journal_path, std::wstring gate_name,
                             std::function<void()> admission_blocked = {});
  bool Admit(std::chrono::milliseconds timeout = std::chrono::seconds(3));
  bool Register(const DisplayOwnership &ownership, RecoveryIdentity &identity);
  bool Update(RecoveryIdentity identity, const DisplayOwnership &ownership);
  bool Resolve(RecoveryIdentity identity);
  bool Contains(RecoveryIdentity identity, const DisplayOwnership &ownership);
  // The display action runs only while this unresolved record still exists.
  // This serializes parent restoration with guardian recovery after pipe loss.
  bool Execute(RecoveryIdentity identity, const std::function<bool()> &action);
  // Safe absence is idempotent: a delayed old guardian must not touch Windows.
  // Unknown state/failed verification retains the durable record.
  bool Recover(RecoveryIdentity identity, DisplayConfigApi &api);

private:
  std::wstring journal_path_;
  std::wstring gate_name_;
  RecoveryIdentity process_;
  std::atomic<bool> disabled_{false};
  std::atomic<bool> admitted_{false};
  std::function<void()> admission_blocked_;
};
std::shared_ptr<DisplayRecoveryCoordinator> ProductionDisplayRecovery();
}
#endif
