#ifndef RUNNER_DISPLAY_GUARDIAN_H_
#define RUNNER_DISPLAY_GUARDIAN_H_

#include "display_dynamic_range.h"
#include "display_recovery.h"

namespace lineup {
enum class GuardianKind : uint32_t { arm = 1, update = 2, disarm = 3 };
// All fields have fixed width; there are no native pointers or implicit
// padding.
struct GuardianRecord {
  uint32_t magic = 0x4c484452;
  uint32_t version = 2;
  uint32_t sequence = 0;
  uint32_t kind = 0;
  uint32_t adapter_low = 0;
  int32_t adapter_high = 0;
  uint32_t target = 0;
  uint32_t route = 0;
  uint32_t original = 0;
  uint32_t verified = 0;
  uint32_t attempted = 0;
  RecoveryIdentity identity;
};
static_assert(sizeof(GuardianRecord) == 60);
struct GuardianAck {
  uint32_t magic = 0x4c484441;
  uint32_t version = 2;
  uint32_t sequence = 0;
};
static_assert(sizeof(GuardianAck) == 12);
GuardianRecord MakeGuardianRecord(GuardianKind kind, uint32_t sequence,
                                  const DisplayOwnership &ownership,
                                  RecoveryIdentity identity = {});
bool ValidGuardianAck(const GuardianAck &ack, uint32_t sequence);

// Production protocol and recovery policy, shared with fake-backed CTest.
class GuardianSession {
public:
  std::optional<GuardianAck> Accept(const GuardianRecord &record);
  void Malformed();
  bool Finished() const { return invalid_ || disarmed_; }
  // Called on either pipe loss or parent loss. At most one recovery attempt.
  bool ParentLost(DisplayConfigApi &api);
  const std::optional<DisplayOwnership> &Ownership() const {
    return ownership_;
  }
  RecoveryIdentity Identity() const { return identity_; }

private:
  uint32_t sequence_ = 0;
  RecoveryIdentity identity_;
  std::optional<DisplayOwnership> ownership_;
  bool invalid_ = false;
  bool disarmed_ = false;
  bool recovered_ = false;
};
DisplayGuardianFactory MakeDisplayGuardianFactory(
    std::shared_ptr<DisplayRecoveryCoordinator> recovery = {});
// Takes ownership of all three handles. Tests use pipes, an event in place of
// the parent process, and a fake API; production supplies the same real API.
int RunDisplayGuardian(
    HANDLE commands, HANDLE acknowledgments, HANDLE parent,
    DisplayConfigApi &api,
    std::shared_ptr<DisplayRecoveryCoordinator> recovery = {},
    std::function<void()> before_recovery = {});
// nullopt means ordinary app startup; invalid guardian arguments fail closed.
std::optional<int> DispatchDisplayGuardian(const wchar_t *command_line);
} // namespace lineup
#endif
