#include "display_guardian.h"

#include <shellapi.h>

#include <array>
#include <cerrno>
#include <cstdlib>
#include <limits>

namespace lineup {
namespace {
class Handle {
public:
  explicit Handle(HANDLE value = nullptr) : value_(value) {}
  ~Handle() { Reset(); }
  Handle(const Handle &) = delete;
  Handle &operator=(const Handle &) = delete;
  HANDLE Get() const { return value_; }
  void Reset(HANDLE value = nullptr) {
    if (value_ && value_ != INVALID_HANDLE_VALUE)
      CloseHandle(value_);
    value_ = value;
  }

private:
  HANDLE value_;
};
bool KnownState(uint32_t state) {
  return state == static_cast<uint32_t>(DisplayState::sdr) ||
         state == static_cast<uint32_t>(DisplayState::hdr);
}
bool OptionalState(uint32_t state) {
  return state == static_cast<uint32_t>(DisplayState::unknown) ||
         KnownState(state);
}
template <typename T> bool WriteRecord(HANDLE pipe, const T &record) {
  DWORD written = 0;
  return WriteFile(pipe, &record, sizeof(record), &written, nullptr) &&
         written == sizeof(record);
}
enum class PipeRead { waiting, complete, broken, malformed };
template <typename T>
PipeRead ReadRecord(HANDLE pipe, T &record, size_t &received) {
  DWORD available = 0;
  if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr))
    return received ? PipeRead::malformed : PipeRead::broken;
  if (!available)
    return PipeRead::waiting;
  DWORD count = 0;
  const DWORD needed = static_cast<DWORD>(sizeof(record) - received);
  if (!ReadFile(pipe, reinterpret_cast<char *>(&record) + received,
                available < needed ? available : needed, &count, nullptr) ||
      !count)
    return received ? PipeRead::malformed : PipeRead::broken;
  received += count;
  return received == sizeof(record) ? PipeRead::complete : PipeRead::waiting;
}
class WindowsGuardianLink final : public DisplayGuardianLink {
public:
  explicit WindowsGuardianLink(
      std::shared_ptr<DisplayRecoveryCoordinator> recovery)
      : recovery_(std::move(recovery)) {}
  bool Arm(const DisplayOwnership &ownership) override {
    if (started_ || lost_)
      return false;
    const ULONGLONG deadline = GetTickCount64() + 2000;
    started_ = true;
    ownership_ = ownership;
    if (!recovery_ || !recovery_->Register(ownership, identity_))
      return Fail();
    if (!Launch() || !Send(GuardianKind::arm, ownership, deadline)) {
      recovery_->Resolve(identity_);
      return Fail();
    }
    return true;
  }
  bool Update(const DisplayOwnership &ownership) override {
    return recovery_->Update(identity_, ownership) &&
           Send(GuardianKind::update, ownership);
  }
  bool Disarm() override {
    if (!recovery_->Resolve(identity_))
      return false;
    if (IsAlive())
      Send(GuardianKind::disarm, ownership_);
    disarmed_ = true;
    commands_.Reset();
    acknowledgments_.Reset();
    return true;
  }
  bool IsAlive() override {
    return !lost_ && !disarmed_ && process_.Get() &&
           WaitForSingleObject(process_.Get(), 0) == WAIT_TIMEOUT;
  }

  bool Execute(const std::function<bool()> &action) override {
    return recovery_->Execute(identity_, action);
  }

private:
  bool Launch() {
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    HANDLE read = nullptr, write = nullptr;
    if (!CreatePipe(&read, &write, &security, 4096))
      return false;
    Handle child_commands(read);
    commands_.Reset(write);
    if (!SetHandleInformation(write, HANDLE_FLAG_INHERIT, 0))
      return false;
    if (!CreatePipe(&read, &write, &security, 4096))
      return false;
    acknowledgments_.Reset(read);
    Handle child_ack(write);
    if (!SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0))
      return false;
    HANDLE parent = nullptr;
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(),
                         GetCurrentProcess(), &parent, SYNCHRONIZE, TRUE, 0))
      return false;
    Handle child_parent(parent);
    std::array<HANDLE, 3> inherited{child_commands.Get(), child_ack.Get(),
                                    parent};
    SIZE_T bytes = 0;
    InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
    std::vector<unsigned char> storage(bytes);
    auto *attributes =
        reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &bytes))
      return false;
    const bool configured =
        UpdateProcThreadAttribute(
            attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited.data(),
            sizeof(inherited), nullptr, nullptr) != FALSE;
    wchar_t executable[32768]{};
    DWORD length = GetModuleFileNameW(nullptr, executable, 32768);
    bool launched = false;
    if (configured && length && length < 32768) {
      std::wstring arguments =
          L"\"" + std::wstring(executable) + L"\" --display-guardian";
      for (HANDLE handle : inherited)
        arguments +=
            L" " + std::to_wstring(reinterpret_cast<uintptr_t>(handle));
      STARTUPINFOEXW startup{};
      startup.StartupInfo.cb = sizeof(startup);
      startup.StartupInfo.dwFlags = STARTF_USESHOWWINDOW;
      startup.StartupInfo.wShowWindow = SW_HIDE;
      startup.lpAttributeList = attributes;
      PROCESS_INFORMATION process{};
      launched = CreateProcessW(
                     executable, arguments.data(), nullptr, nullptr, TRUE,
                     EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW, nullptr,
                     nullptr, &startup.StartupInfo, &process) != FALSE;
      if (launched) {
        process_.Reset(process.hProcess);
        CloseHandle(process.hThread);
      }
    }
    DeleteProcThreadAttributeList(attributes);
    return launched;
  }
  bool Send(GuardianKind kind, const DisplayOwnership &ownership,
            ULONGLONG deadline = 0) {
    if (!deadline)
      deadline = GetTickCount64() + 2000;
    if (GetTickCount64() >= deadline)
      return Fail();
    if (!IsAlive() || sequence_ == UINT32_MAX)
      return Fail();
    auto record = MakeGuardianRecord(kind, ++sequence_, ownership, identity_);
    if (!WriteRecord(commands_.Get(), record))
      return Fail();
    GuardianAck ack{};
    size_t received = 0;
    do {
      auto result = ReadRecord(acknowledgments_.Get(), ack, received);
      if (result == PipeRead::complete) {
        if (!ValidGuardianAck(ack, sequence_))
          return Fail();
        ownership_ = ownership;
        return true;
      }
      if (result != PipeRead::waiting || !IsAlive())
        return Fail();
      Sleep(5);
    } while (GetTickCount64() < deadline);
    return Fail();
  }
  bool Fail() {
    lost_ = true;
    commands_.Reset();
    acknowledgments_.Reset();
    return false;
  }
  Handle commands_, acknowledgments_, process_;
  DisplayOwnership ownership_;
  std::shared_ptr<DisplayRecoveryCoordinator> recovery_;
  RecoveryIdentity identity_;
  uint32_t sequence_ = 0;
  bool started_ = false, lost_ = false, disarmed_ = false;
};
}
int RunDisplayGuardian(HANDLE commands, HANDLE acknowledgments, HANDLE parent,
                       DisplayConfigApi &api,
                       std::shared_ptr<DisplayRecoveryCoordinator> recovery,
                       std::function<void()> before_recovery) {
  Handle command_owner(commands), ack_owner(acknowledgments),
      parent_owner(parent);
  GuardianSession session;
  GuardianRecord record{};
  size_t received = 0;
  bool recover = false;
  while (!session.Finished()) {
    auto result = ReadRecord(commands, record, received);
    if (result == PipeRead::malformed) {
      session.Malformed();
      break;
    }
    if (result == PipeRead::broken) {
      recover = true;
      break;
    }
    if (result == PipeRead::complete) {
      auto ack = session.Accept(record);
      if (!ack)
        break;
      if (recovery &&
          record.kind != static_cast<uint32_t>(GuardianKind::disarm) &&
          !recovery->Contains(session.Identity(), *session.Ownership())) {
        session.Malformed();
        break;
      }
      received = 0;
      if (!WriteRecord(acknowledgments, *ack)) {
        recover = true;
        break;
      }
      if (session.Finished())
        break;
    }
    const DWORD parent_state = WaitForSingleObject(parent, 10);
    if (parent_state == WAIT_OBJECT_0) {
      DWORD available = 0;
      if (PeekNamedPipe(commands, nullptr, 0, nullptr, &available, nullptr) &&
          available)
        continue;
      if (received)
        session.Malformed();
      else
        recover = true;
      break;
    }
    if (parent_state != WAIT_TIMEOUT) {
      session.Malformed();
      break;
    }
  }
  if (recover && !session.Finished()) {
    if (before_recovery)
      before_recovery();
    const bool safe = recovery ? recovery->Recover(session.Identity(), api)
                               : session.ParentLost(api);
    if (!safe)
      return EXIT_FAILURE;
  }

  return 0;
}
GuardianRecord MakeGuardianRecord(GuardianKind kind, uint32_t sequence,
                                  const DisplayOwnership &ownership,
                                  RecoveryIdentity identity) {
  GuardianRecord record;
  record.sequence = sequence;
  record.kind = static_cast<uint32_t>(kind);
  record.adapter_low = ownership.target.adapter.LowPart;
  record.adapter_high = ownership.target.adapter.HighPart;
  record.target = ownership.target.id;
  record.route = static_cast<uint32_t>(ownership.route);
  record.original = static_cast<uint32_t>(ownership.original);
  record.verified = static_cast<uint32_t>(ownership.verified);
  record.attempted = static_cast<uint32_t>(ownership.attempted);
  record.identity = identity;
  return record;
}
bool ValidGuardianAck(const GuardianAck &ack, uint32_t sequence) {
  return ack.magic == GuardianAck{}.magic &&
         ack.version == GuardianAck{}.version && ack.sequence == sequence;
}
std::optional<GuardianAck>
GuardianSession::Accept(const GuardianRecord &record) {
  if (Finished() || recovered_ || sequence_ == UINT32_MAX ||
      record.magic != GuardianRecord{}.magic ||
      record.version != GuardianRecord{}.version ||
      record.sequence != sequence_ + 1 || record.kind < 1 || record.kind > 3 ||
      (record.route != static_cast<uint32_t>(DisplayRoute::hdr_state) &&
       record.route != static_cast<uint32_t>(DisplayRoute::advanced_color)) ||
      !KnownState(record.original) || !OptionalState(record.verified) ||
      !OptionalState(record.attempted)) {
    Malformed();
    return std::nullopt;
  }
  DisplayOwnership ownership{
      {{record.adapter_low, record.adapter_high}, record.target},
      static_cast<DisplayRoute>(record.route),
      static_cast<DisplayState>(record.original),
      static_cast<DisplayState>(record.verified),
      static_cast<DisplayState>(record.attempted)};
  if ((!ownership_ &&
       record.kind != static_cast<uint32_t>(GuardianKind::arm)) ||
      (ownership_ && (record.kind == static_cast<uint32_t>(GuardianKind::arm) ||
                      !(ownership.target == ownership_->target) ||
                      ownership.route != ownership_->route ||
                      ownership.original != ownership_->original ||
                      !(record.identity == identity_)))) {
    Malformed();
    return std::nullopt;
  }
  ownership_ = ownership;
  identity_ = record.identity;
  sequence_ = record.sequence;
  disarmed_ = record.kind == static_cast<uint32_t>(GuardianKind::disarm);
  GuardianAck ack;
  ack.sequence = sequence_;
  return ack;
}
void GuardianSession::Malformed() { invalid_ = true; }
bool GuardianSession::ParentLost(DisplayConfigApi &api) {
  if (Finished() || recovered_ || !ownership_)
    return false;
  recovered_ = true;
  return RestoreDisplayOwnership(*ownership_, api);
}
DisplayGuardianFactory MakeDisplayGuardianFactory(
    std::shared_ptr<DisplayRecoveryCoordinator> recovery) {
  return [recovery = std::move(recovery)] {
    return std::make_unique<WindowsGuardianLink>(
        recovery ? recovery : ProductionDisplayRecovery());
  };
}
std::optional<int> DispatchDisplayGuardian(const wchar_t *command_line) {
  int count = 0;
  // Prefix an executable because CommandLineToArgvW treats its first token
  // specially.
  std::wstring arguments = L"lineup_desktop.exe " + std::wstring(command_line);
  wchar_t **values = CommandLineToArgvW(arguments.c_str(), &count);
  if (!values)
    return EXIT_FAILURE;
  bool guardian = count > 1 && wcscmp(values[1], L"--display-guardian") == 0;
  if (!guardian) {
    LocalFree(values);
    return std::nullopt;
  }
  std::array<HANDLE, 3> handles{};
  bool valid = count == 5;
  for (int i = 0; valid && i < 3; ++i) {
    wchar_t *end = nullptr;
    errno = 0;
    const auto value = wcstoull(values[i + 2], &end, 10);
    valid = values[i + 2][0] >= L'0' && values[i + 2][0] <= L'9' && end &&
            *end == 0 && errno != ERANGE && value &&
            value <= std::numeric_limits<uintptr_t>::max();
    handles[i] = reinterpret_cast<HANDLE>(static_cast<uintptr_t>(value));
  }
  LocalFree(values);
  if (!valid || handles[0] == handles[1] || handles[0] == handles[2] ||
      handles[1] == handles[2] || GetFileType(handles[0]) != FILE_TYPE_PIPE ||
      GetFileType(handles[1]) != FILE_TYPE_PIPE ||
      WaitForSingleObject(handles[2], 0) == WAIT_FAILED)
    return EXIT_FAILURE;
  auto api = MakeDisplayConfigApi();
  return RunDisplayGuardian(handles[0], handles[1], handles[2], *api,
                            ProductionDisplayRecovery());
}
}
