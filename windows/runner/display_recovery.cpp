#include "display_recovery.h"

#include <sddl.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <utility>

namespace lineup {
namespace {
constexpr uint32_t kMagic = 0x4c44524a;
constexpr size_t kCapacity = 32;
struct Entry {
  RecoveryIdentity identity;
  uint32_t adapter_low = 0;
  int32_t adapter_high = 0;
  uint32_t target = 0;
  uint32_t route = 0;
  uint32_t original = 0;
  uint32_t verified = 0;
  uint32_t attempted = 0;
};
static_assert(sizeof(Entry) == 44);
struct Journal {
  uint32_t magic = kMagic;
  uint32_t version = 1;
  uint32_t count = 0;
  uint32_t next_id = 1;
  uint32_t checksum = 0;
  std::array<Entry, kCapacity> entries{};
};
static_assert(sizeof(Journal) == 20 + 44 * kCapacity);
class Handle {
public:
  explicit Handle(HANDLE value) : value_(value) {}
  ~Handle() {
    if (value_ && value_ != INVALID_HANDLE_VALUE)
      CloseHandle(value_);
  }
  Handle(const Handle &) = delete;
  Handle &operator=(const Handle &) = delete;
  HANDLE Get() const { return value_; }

private:
  HANDLE value_;
};
class Gate {
public:
  Gate(const std::wstring &name, DWORD timeout)
      : handle_(name.empty() ? nullptr
                             : CreateMutexW(nullptr, FALSE, name.c_str())) {
    if (!handle_.Get())
      return;
    const DWORD result = WaitForSingleObject(handle_.Get(), timeout);
    locked_ = result == WAIT_OBJECT_0 || result == WAIT_ABANDONED;
    // Abandonment allows journal inspection, never grants admission itself.
  }
  ~Gate() {
    if (locked_)
      ReleaseMutex(handle_.Get());
  }
  bool Locked() const { return locked_; }

private:
  Handle handle_;
  bool locked_ = false;
};
uint32_t Checksum(Journal journal) {
  journal.checksum = 0;
  uint32_t hash = 2166136261u;
  for (size_t i = 0; i < sizeof(journal); ++i)
    hash = (hash ^ reinterpret_cast<const unsigned char *>(&journal)[i]) *
           16777619u;
  return hash;
}
bool Known(uint32_t value) { return value == 1 || value == 2; }
bool ValidOwnership(const DisplayOwnership &own) {
  return Known(static_cast<uint32_t>(own.original)) &&
         (own.route == DisplayRoute::hdr_state ||
          own.route == DisplayRoute::advanced_color) &&
         static_cast<uint32_t>(own.verified) <= 2 &&
         static_cast<uint32_t>(own.attempted) <= 2;
}
bool Valid(const Journal &journal) {
  if (journal.magic != kMagic || journal.version != 1 ||
      journal.count > kCapacity || !journal.next_id ||
      journal.checksum != Checksum(journal))
    return false;
  for (uint32_t i = 0; i < journal.count; ++i) {
    const auto &e = journal.entries[i];
    if (!e.identity.owner_pid || !e.identity.record_id ||
        e.identity.record_id >= journal.next_id ||
        !(e.identity.owner_created_low || e.identity.owner_created_high) ||
        (e.route != 1 && e.route != 2) || !Known(e.original) ||
        e.verified > 2 || e.attempted > 2)
      return false;
    for (uint32_t j = 0; j < i; ++j)
      if (e.identity == journal.entries[j].identity)
        return false;
  }
  return true;
}
bool Load(const std::wstring &path, Journal &journal) {
  if (path.empty())
    return false;
  Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                          OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  if (file.Get() == INVALID_HANDLE_VALUE)
    return GetLastError() == ERROR_FILE_NOT_FOUND;
  LARGE_INTEGER length{};
  DWORD read = 0;
  return GetFileSizeEx(file.Get(), &length) &&
         length.QuadPart == static_cast<LONGLONG>(sizeof(journal)) &&
         ReadFile(file.Get(), &journal, sizeof(journal), &read, nullptr) &&
         read == sizeof(journal) && Valid(journal);
}
bool Save(const std::wstring &path, Journal journal,
          const std::wstring &gate_name) {
  journal.checksum = Checksum(journal);
  const std::wstring pending = path + L".pending";
  {
    Handle file(CreateFileW(pending.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr));
    DWORD written = 0;
    if (file.Get() == INVALID_HANDLE_VALUE ||
        !WriteFile(file.Get(), &journal, sizeof(journal), &written, nullptr) ||
        written != sizeof(journal) || !FlushFileBuffers(file.Get()))
      return false;
  }
  // Old bytes remain authoritative if replacement fails. No mutation follows
  // an unsuccessful registration/update. A crash during recovery leaves the
  // old unresolved record, which safely blocks future capture.
  if (!MoveFileExW(pending.c_str(), path.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
    return false;
  Handle changed(
      CreateEventW(nullptr, FALSE, FALSE, (gate_name + L".changed").c_str()));
  if (changed.Get())
    SetEvent(changed.Get());
  return true;
}
Entry MakeEntry(RecoveryIdentity identity, const DisplayOwnership &own) {
  return {identity,
          own.target.adapter.LowPart,
          own.target.adapter.HighPart,
          own.target.id,
          static_cast<uint32_t>(own.route),
          static_cast<uint32_t>(own.original),
          static_cast<uint32_t>(own.verified),
          static_cast<uint32_t>(own.attempted)};
}
DisplayOwnership Ownership(const Entry &e) {
  return {{{e.adapter_low, e.adapter_high}, e.target},
          static_cast<DisplayRoute>(e.route),
          static_cast<DisplayState>(e.original),
          static_cast<DisplayState>(e.verified),
          static_cast<DisplayState>(e.attempted)};
}
Entry *Find(Journal &journal, RecoveryIdentity identity) {
  for (uint32_t i = 0; i < journal.count; ++i)
    if (journal.entries[i].identity == identity)
      return &journal.entries[i];
  return nullptr;
}
bool Remove(const std::wstring &path, Journal &journal,
            RecoveryIdentity identity, const std::wstring &gate_name) {
  auto *entry = Find(journal, identity);
  if (!entry)
    return true;
  const size_t index = static_cast<size_t>(entry - journal.entries.data());
  for (size_t i = index + 1; i < journal.count; ++i)
    journal.entries[i - 1] = journal.entries[i];
  journal.entries[--journal.count] = {};
  return Save(path, journal, gate_name);
}
bool SameTarget(const Entry &e, const DisplayOwnership &own) {
  return Ownership(e).target == own.target &&
         e.route == static_cast<uint32_t>(own.route) &&
         e.original == static_cast<uint32_t>(own.original);
}
bool OwnerFinished(RecoveryIdentity identity) {
  Handle owner(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                           FALSE, identity.owner_pid));
  if (!owner.Get())
    return GetLastError() == ERROR_INVALID_PARAMETER;
  const DWORD state = WaitForSingleObject(owner.Get(), 0);
  if (state == WAIT_OBJECT_0)
    return true;
  if (state != WAIT_TIMEOUT)
    return false;
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetProcessTimes(owner.Get(), &created, &exited, &kernel, &user))
    return false;
  return created.dwLowDateTime != identity.owner_created_low ||
         created.dwHighDateTime != identity.owner_created_high;
}
bool RetireUnmutatedOrphans(const std::wstring &path,
                            const std::wstring &gate_name, Journal &journal) {
  bool changed = false;
  for (uint32_t i = 0; i < journal.count;) {
    const auto &entry = journal.entries[i];
    // Register may precede helper launch/acknowledgment. No Set can precede a
    // persisted attempted state, so exact dead owners with no intent/verified
    // mutation need no display query. Access denied or a live owner is not
    // safe.
    if (entry.verified || entry.attempted || !OwnerFinished(entry.identity)) {
      ++i;
      continue;
    }
    for (uint32_t j = i + 1; j < journal.count; ++j)
      journal.entries[j - 1] = journal.entries[j];
    journal.entries[--journal.count] = {};
    changed = true;
  }
  return !changed || Save(path, journal, gate_name);
}
std::pair<std::wstring, std::wstring> ProductionScope() {
  HANDLE raw = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &raw))
    return {};
  Handle token(raw);
  TOKEN_STATISTICS statistics{};
  DWORD length = 0;
  if (!GetTokenInformation(raw, TokenStatistics, &statistics,
                           sizeof(statistics), &length))
    return {};
  GetTokenInformation(raw, TokenUser, nullptr, 0, &length);
  std::vector<unsigned char> user(length);
  if (user.empty() ||
      !GetTokenInformation(raw, TokenUser, user.data(), length, &length))
    return {};
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(
          reinterpret_cast<TOKEN_USER *>(user.data())->User.Sid, &sid))
    return {};
  std::wstring scope = std::wstring(sid) + L"-" +
                       std::to_wstring(statistics.AuthenticationId.HighPart) +
                       L"-" +
                       std::to_wstring(statistics.AuthenticationId.LowPart);
  LocalFree(sid);
  wchar_t folder[MAX_PATH]{};
  if (FAILED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr,
                              SHGFP_TYPE_CURRENT, folder)))
    return {};
  std::wstring directory = std::wstring(folder) + L"\\LineupDesktop";
  if (!CreateDirectoryW(directory.c_str(), nullptr) &&
      GetLastError() != ERROR_ALREADY_EXISTS)
    return {};
  return {directory + L"\\display-recovery-" + scope + L".bin",
          L"Local\\TJZine.LineupDesktop.DisplayRecovery-" + scope};
}
} // namespace
bool RestoreDisplayOwnership(const DisplayOwnership &own,
                             DisplayConfigApi &api) {
  const auto observed = api.Query(own.target, own.route);
  if (observed.state == DisplayState::unknown ||
      (observed.state == own.original &&
       own.attempted != DisplayState::unknown &&
       own.attempted != own.original && own.verified != own.attempted))
    return false;
  if (observed.state == own.original ||
      (observed.state != own.verified && observed.state != own.attempted))
    return true;
  api.Set(own.target, own.route, own.original);
  return api.Query(own.target, own.route).state == own.original;
}

DisplayRecoveryCoordinator::DisplayRecoveryCoordinator(
    std::wstring path, std::wstring gate,
    std::function<void()> admission_blocked)
    : journal_path_(std::move(path)), gate_name_(std::move(gate)),
      admission_blocked_(std::move(admission_blocked)) {
  FILETIME created{}, exited{}, kernel{}, user{};
  process_.owner_pid = GetCurrentProcessId();
  if (GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user)) {
    process_.owner_created_low = created.dwLowDateTime;
    process_.owner_created_high = created.dwHighDateTime;
  } else
    disabled_ = true;
}
bool DisplayRecoveryCoordinator::Admit(std::chrono::milliseconds timeout) {
  if (disabled_)
    return false;
  const auto bounded = std::min(timeout, std::chrono::milliseconds(3000));
  const ULONGLONG deadline =
      GetTickCount64() +
      static_cast<ULONGLONG>(std::max<int64_t>(0, bounded.count()));
  Handle changed(gate_name_.empty()
                     ? nullptr
                     : CreateEventW(nullptr, FALSE, FALSE,
                                    (gate_name_ + L".changed").c_str()));
  if (!changed.Get()) {
    disabled_ = true;
    return false;
  }
  bool notified = false;
  while (true) {
    {
      const ULONGLONG inspected_at = GetTickCount64();
      const auto remaining =
          deadline > inspected_at ? deadline - inspected_at : 0;
      Gate gate(gate_name_, static_cast<DWORD>(remaining));
      Journal journal;
      if (!gate.Locked() || !Load(journal_path_, journal) ||
          !RetireUnmutatedOrphans(journal_path_, gate_name_, journal) ||
          GetTickCount64() > deadline)
        break;
      if (!journal.count) {
        admitted_ = true;
        return true;
      }
    }
    if (!notified && admission_blocked_) {
      notified = true;
      admission_blocked_();
    }
    // The event only wakes admission; explicit journal resolution grants it.
    // Creating it before inspection avoids losing a resolution notification.
    const ULONGLONG now = GetTickCount64();
    if (now >= deadline)
      break;
    const DWORD result =
        WaitForSingleObject(changed.Get(), static_cast<DWORD>(deadline - now));
    if (result != WAIT_OBJECT_0 && result != WAIT_TIMEOUT)
      break;
    // Reinspect even at timeout: no scheduling delay substitutes for proof.
  }
  disabled_ = true;
  return false;
}
bool DisplayRecoveryCoordinator::Register(const DisplayOwnership &own,
                                          RecoveryIdentity &identity) {
  if (disabled_ || !admitted_)
    return false;
  Gate gate(gate_name_, 2000);
  Journal journal;
  if (!gate.Locked() || !Load(journal_path_, journal) ||
      journal.count == kCapacity || journal.next_id == UINT32_MAX ||
      !ValidOwnership(own))
    return false;
  for (uint32_t i = 0; i < journal.count; ++i) {
    const auto &e = journal.entries[i];
    if (e.identity.owner_pid != process_.owner_pid ||
        e.identity.owner_created_low != process_.owner_created_low ||
        e.identity.owner_created_high != process_.owner_created_high ||
        Ownership(e).target == own.target)
      return false;
  }
  identity = process_;
  identity.record_id = journal.next_id++;
  journal.entries[journal.count++] = MakeEntry(identity, own);
  return Save(journal_path_, journal, gate_name_);
}
bool DisplayRecoveryCoordinator::Update(RecoveryIdentity identity,
                                        const DisplayOwnership &own) {
  Gate gate(gate_name_, 2000);
  Journal journal;
  if (!gate.Locked() || !Load(journal_path_, journal))
    return false;
  auto *entry = Find(journal, identity);
  if (!entry || !SameTarget(*entry, own) || !ValidOwnership(own))
    return false;
  *entry = MakeEntry(identity, own);
  return Save(journal_path_, journal, gate_name_);
}
bool DisplayRecoveryCoordinator::Resolve(RecoveryIdentity identity) {
  Gate gate(gate_name_, 2000);
  Journal journal;
  return gate.Locked() && Load(journal_path_, journal) &&
         Remove(journal_path_, journal, identity, gate_name_);
}
bool DisplayRecoveryCoordinator::Contains(RecoveryIdentity identity,
                                          const DisplayOwnership &own) {
  Gate gate(gate_name_, 2000);
  Journal journal;
  if (!gate.Locked() || !Load(journal_path_, journal))
    return false;
  auto *e = Find(journal, identity);
  return e && SameTarget(*e, own) &&
         e->verified == static_cast<uint32_t>(own.verified) &&
         e->attempted == static_cast<uint32_t>(own.attempted);
}
bool DisplayRecoveryCoordinator::Execute(RecoveryIdentity identity,
                                         const std::function<bool()> &action) {
  Gate gate(gate_name_, 2000);
  Journal journal;
  return gate.Locked() && Load(journal_path_, journal) &&
         Find(journal, identity) && action();
}
bool DisplayRecoveryCoordinator::Recover(RecoveryIdentity identity,
                                         DisplayConfigApi &api) {
  Gate gate(gate_name_, 3000);
  Journal journal;
  if (!gate.Locked() || !Load(journal_path_, journal))
    return false;
  auto *entry = Find(journal, identity);
  if (!entry)
    return true;
  if (!RestoreDisplayOwnership(Ownership(*entry), api))
    return false;
  // Original restored, or a known external state has relinquished our hold.
  return Remove(journal_path_, journal, identity, gate_name_);
}
std::shared_ptr<DisplayRecoveryCoordinator> ProductionDisplayRecovery() {
  static const auto shared = [] {
    auto scope = ProductionScope();
    return std::make_shared<DisplayRecoveryCoordinator>(
        std::move(scope.first), std::move(scope.second));
  }();
  return shared;
}
} // namespace lineup
