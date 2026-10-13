#include "display_guardian.h"
#include "display_recovery.h"

#include <shellapi.h>

#include <array>
#include <condition_variable>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

// Real Win32 processes, inherited handles, pipes, parent death and production
// admission/recovery. Only display effects and the successor's guardian link
// are controlled. This executable never touches the user's DisplayConfig.
namespace {
using namespace lineup;
void Check(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
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
enum Slot {
  mapping,
  predecessor_ready,
  paused_a,
  paused_b,
  continue_a,
  continue_b,
  admission_blocked,
  successor_reported,
  clean_disarm,
  finish_successor,
  slots
};
using Handles = std::array<HANDLE, slots>;
struct Effects {
  LONG state[2]{};
  LONG original[2]{};
  LONG captures = 0;
  LONG captured_state = 0;
  LONG successor_writes = 0;
  LONG guardian_writes = 0;
  LONG successor_unavailable = 0;
  LONG successor_revision = 0;
  LONG reject_recovery = 0;
  LONG target_missing = 0;
  LONG unobserved_attempt = 0;
  DWORD guardian_pid[2]{};
  RecoveryIdentity identity[2]{};
  int targets = 1;
  DisplayState desired = DisplayState::sdr;
};
LONG Read(LONG &value) { return InterlockedCompareExchange(&value, 0, 0); }
void Wait(HANDLE handle, const char *message, DWORD timeout = 6000) {
  Check(WaitForSingleObject(handle, timeout) == WAIT_OBJECT_0, message);
}
class View {
public:
  explicit View(HANDLE mapping_handle) {
    effects = static_cast<Effects *>(MapViewOfFile(
        mapping_handle, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(Effects)));
    Check(effects != nullptr, "map controlled display effects");
  }
  ~View() { UnmapViewOfFile(effects); }
  Effects *effects;
};
enum class Actor { predecessor, guardian, successor };
class Api final : public DisplayConfigApi {
public:
  Api(Effects &effects, Actor actor) : effects_(effects), actor_(actor) {}
  DisplayMapping MapWindow(HWND) override { return {Target(0), nullptr}; }
  DisplayObservation Query(DisplayTarget target, DisplayRoute route) override {
    Check(target.id >= 1 && target.id <= 2, "exact fixture target");
    if (actor_ == Actor::guardian && Read(effects_.target_missing))
      return {};
    const auto state =
        static_cast<DisplayState>(Read(effects_.state[target.id - 1]));
    if (actor_ == Actor::successor && route == DisplayRoute::none) {
      InterlockedIncrement(&effects_.captures);
      InterlockedExchange(&effects_.captured_state, static_cast<LONG>(state));
    }
    return {state, DisplayRoute::hdr_state, true, "unknown"};
  }
  bool Set(DisplayTarget target, DisplayRoute, DisplayState state) override {
    if (actor_ == Actor::predecessor && Read(effects_.unobserved_attempt))
      return true;
    if (actor_ == Actor::guardian) {
      InterlockedIncrement(&effects_.guardian_writes);
      if (Read(effects_.reject_recovery))
        return false;
    }
    if (actor_ == Actor::successor)
      InterlockedIncrement(&effects_.successor_writes);
    InterlockedExchange(&effects_.state[target.id - 1],
                        static_cast<LONG>(state));
    return true;
  }
  static DisplayTarget Target(int index) {
    return {{71, -3}, static_cast<UINT32>(index + 1)};
  }

private:
  Effects &effects_;
  Actor actor_;
};
HANDLE Number(const std::wstring &value) {
  return reinterpret_cast<HANDLE>(static_cast<uintptr_t>(std::stoull(value)));
}
std::wstring Quote(const std::wstring &value) {
  Check(value.find(L'"') == std::wstring::npos, "fixture path excludes quotes");
  return L"\"" + value + L"\"";
}
HANDLE Launch(const std::wstring &role, const std::wstring &journal,
              const std::wstring &gate, const Handles &handles,
              const std::vector<HANDLE> &extra = {}, HANDLE job = nullptr) {
  wchar_t executable[32768]{};
  Check(GetModuleFileNameW(nullptr, executable, 32768) != 0,
        "fixture executable");
  std::wstring args = Quote(executable) + L" --display-admission-test " + role +
                      L" " + Quote(journal) + L" " + Quote(gate);
  std::vector<HANDLE> inherited(handles.begin(), handles.end());
  inherited.insert(inherited.end(), extra.begin(), extra.end());
  for (HANDLE handle : inherited)
    args += L" " + std::to_wstring(reinterpret_cast<uintptr_t>(handle));
  SIZE_T size = 0;
  InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
  std::vector<unsigned char> storage(size);
  auto attributes =
      reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
  Check(InitializeProcThreadAttributeList(attributes, 1, 0, &size) != FALSE,
        "fixture attribute list");
  const bool configured =
      UpdateProcThreadAttribute(
          attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited.data(),
          inherited.size() * sizeof(HANDLE), nullptr, nullptr) != FALSE;
  STARTUPINFOEXW startup{};
  startup.StartupInfo.cb = sizeof(startup);
  startup.lpAttributeList = attributes;
  PROCESS_INFORMATION process{};
  const bool launched =
      configured &&
      CreateProcessW(executable, args.data(), nullptr, nullptr, TRUE,
                     EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW |
                         CREATE_SUSPENDED,
                     nullptr, nullptr, &startup.StartupInfo, &process) != FALSE;
  DeleteProcThreadAttributeList(attributes);
  Check(launched, "launch real fixture child");
  Handle thread(process.hThread);
  if (job && !AssignProcessToJobObject(job, process.hProcess)) {
    TerminateProcess(process.hProcess, EXIT_FAILURE);
    CloseHandle(process.hProcess);
    throw std::runtime_error("isolate fixture process job");
  }
  Check(ResumeThread(thread.Get()) != static_cast<DWORD>(-1),
        "resume fixture child");
  return process.hProcess;
}
void ExitResult(HANDLE process, DWORD expected) {
  Wait(process, "bounded fixture process exit");
  DWORD code = EXIT_FAILURE;
  Check(GetExitCodeProcess(process, &code) && code == expected,
        "fixture child returned expected recovery result");
}
void ExitSuccess(HANDLE process) { ExitResult(process, EXIT_SUCCESS); }
void Send(HANDLE commands, HANDLE acknowledgments,
          const GuardianRecord &record) {
  DWORD written = 0;
  Check(WriteFile(commands, &record, sizeof(record), &written, nullptr) &&
            written == sizeof(record),
        "write real guardian record");
  // Peek before Read keeps failed IPC bounded, as the production link does.
  const auto deadline = GetTickCount64() + 2000;
  DWORD available = 0;
  while (GetTickCount64() < deadline) {
    Check(PeekNamedPipe(acknowledgments, nullptr, 0, nullptr, &available,
                        nullptr),
          "guardian acknowledgment pipe");
    if (available >= sizeof(GuardianAck))
      break;
    // Only an IPC readiness poll, never the test's process-ordering fence.
    Sleep(1);
  }
  Check(available >= sizeof(GuardianAck), "bounded guardian acknowledgment");
  GuardianAck ack{};
  DWORD read = 0;
  Check(ReadFile(acknowledgments, &ack, sizeof(ack), &read, nullptr) &&
            read == sizeof(ack) && ValidGuardianAck(ack, record.sequence),
        "acknowledged production guardian protection");
}
class SuccessorLink final : public DisplayGuardianLink {
public:
  explicit SuccessorLink(std::shared_ptr<DisplayRecoveryCoordinator> recovery)
      : recovery_(std::move(recovery)) {}
  bool Arm(const DisplayOwnership &own) override {
    return recovery_->Register(own, id_);
  }
  bool Update(const DisplayOwnership &own) override {
    return recovery_->Update(id_, own);
  }
  bool Disarm() override { return recovery_->Resolve(id_); }
  bool IsAlive() override { return true; }
  bool Execute(const std::function<bool()> &action) override {
    return recovery_->Execute(id_, action);
  }

private:
  std::shared_ptr<DisplayRecoveryCoordinator> recovery_;
  RecoveryIdentity id_;
};
int Predecessor(const std::wstring &journal, const std::wstring &gate,
                const Handles &handles, Effects &effects) {
  auto recovery = std::make_shared<DisplayRecoveryCoordinator>(journal, gate);
  Check(recovery->Admit(), "predecessor production admission");
  Api api(effects, Actor::predecessor);
  std::array<Handle, 2> commands, acknowledgments, guardians;
  std::array<DisplayOwnership, 2> own{};
  SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
  for (int i = 0; i < effects.targets; ++i) {
    own[i] = {Api::Target(i), DisplayRoute::hdr_state,
              static_cast<DisplayState>(effects.original[i]),
              DisplayState::unknown, DisplayState::unknown};
    Check(recovery->Register(own[i], effects.identity[i]),
          "register before mutation");
    HANDLE read = nullptr, write = nullptr;
    Check(CreatePipe(&read, &write, &security, 4096), "real command pipe");
    Handle child_commands(read);
    commands[i].Reset(write);
    Check(SetHandleInformation(write, HANDLE_FLAG_INHERIT, 0),
          "private command end");
    Check(CreatePipe(&read, &write, &security, 4096),
          "real acknowledgment pipe");
    acknowledgments[i].Reset(read);
    Handle child_ack(write);
    Check(SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0),
          "private ack end");
    HANDLE raw_parent = nullptr;
    Check(DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(),
                          GetCurrentProcess(), &raw_parent, SYNCHRONIZE, TRUE,
                          0),
          "real synchronize-only parent handle");
    Handle parent(raw_parent);
    guardians[i].Reset(
        Launch(i == 0 ? L"guardian-a" : L"guardian-b", journal, gate, handles,
               {child_commands.Get(), child_ack.Get(), parent.Get()}));
    effects.guardian_pid[i] = GetProcessId(guardians[i].Get());
    Send(commands[i].Get(), acknowledgments[i].Get(),
         MakeGuardianRecord(GuardianKind::arm, 1, own[i], effects.identity[i]));
    own[i].attempted = own[i].original == DisplayState::sdr ? DisplayState::hdr
                                                            : DisplayState::sdr;
    Check(recovery->Update(effects.identity[i], own[i]),
          "persist attempted state");
    Send(commands[i].Get(), acknowledgments[i].Get(),
         MakeGuardianRecord(GuardianKind::update, 2, own[i],
                            effects.identity[i]));
    Check(recovery->Execute(effects.identity[i],
                            [&] {
                              return api.Set(own[i].target, own[i].route,
                                             own[i].attempted);
                            }),
          "acknowledged mutation through production recovery gate");
    if (!Read(effects.unobserved_attempt))
      own[i].verified = own[i].attempted;
    Check(recovery->Update(effects.identity[i], own[i]),
          "persist verified state");
    Send(commands[i].Get(), acknowledgments[i].Get(),
         MakeGuardianRecord(GuardianKind::update, 3, own[i],
                            effects.identity[i]));
  }
  Check(SetEvent(handles[predecessor_ready]),
        "predecessor mutated and protected");
  Wait(handles[clean_disarm], "predecessor waits for crash or normal release",
       15000);
  for (int i = 0; i < effects.targets; ++i) {
    Check(recovery->Execute(effects.identity[i],
                            [&] {
                              return api.Set(own[i].target, own[i].route,
                                             own[i].original);
                            }),
          "normal restoration");
    Check(recovery->Resolve(effects.identity[i]),
          "verified normal release resolves journal");
    Send(commands[i].Get(), acknowledgments[i].Get(),
         MakeGuardianRecord(GuardianKind::disarm, 4, own[i],
                            effects.identity[i]));
    ExitSuccess(guardians[i].Get());
  }
  return EXIT_SUCCESS;
}
int Successor(const std::wstring &journal, const std::wstring &gate,
              const Handles &handles, Effects &effects, bool bypass) {
  auto recovery =
      std::make_shared<DisplayRecoveryCoordinator>(journal, gate, [&] {
        Check(SetEvent(handles[admission_blocked]),
              "observed pending admission");
      });
  std::mutex mutex;
  std::condition_variable changed;
  int64_t last_revision = -1;
  DisplayDynamicRange worker(
      nullptr, std::make_unique<Api>(effects, Actor::successor),
      [recovery] { return std::make_unique<SuccessorLink>(recovery); },
      [&](const DisplayReport &report) {
        if (std::string(report.session) == "unavailable") {
          Check(std::string(report.outcome) == "failed" && !report.wrote &&
                    !report.owned && report.reason &&
                    std::string(report.reason) == "guardian_unavailable",
                "public current-revision fail-closed report");
          InterlockedExchange(&effects.successor_unavailable, 1);
        }
        if (std::string(report.outcome) == "matched" ||
            std::string(report.session) == "unavailable") {
          InterlockedExchange(&effects.successor_revision,
                              static_cast<LONG>(report.revision));
          std::lock_guard lock(mutex);
          last_revision = report.revision;
          changed.notify_all();
          SetEvent(handles[successor_reported]);
        }
      },
      [] {}, MakeDisplayClock(),
      [recovery, bypass] {
        // Negative control recreates the former unowned-mutex admission result.
        return bypass || recovery->Admit();
      });
  Check(worker.Submit({1, true, effects.desired}),
        "successor production display request");
  Wait(handles[finish_successor], "successor wait for assertions and release",
       15000);
  if (Read(effects.successor_unavailable)) {
    worker.Notify(true, true);
    worker.ResetRevision();
    Check(worker.Submit({2, true, effects.desired}),
          "request after restart/retry");
    std::unique_lock lock(mutex);
    Check(changed.wait_for(lock, std::chrono::seconds(3),
                           [&] { return last_revision == 2; }),
          "latched admission failure reports current revision after restart");
    Check(Read(effects.captures) == 0 && Read(effects.successor_writes) == 0,
          "restart/retry cannot bypass failed admission");
  }
  worker.EndSessionAndWait(std::chrono::seconds(3));
  Check(worker.ReleaseComplete(),
        "blocked matching preserves bounded shutdown");
  return EXIT_SUCCESS;
}

int UnmutatedPredecessor(const std::wstring &journal, const std::wstring &gate,
                         const Handles &handles, Effects &effects) {
  DisplayRecoveryCoordinator recovery(journal, gate);
  Check(recovery.Admit(), "unmutated predecessor admission");
  DisplayOwnership own{Api::Target(0), DisplayRoute::hdr_state,
                       DisplayState::sdr, DisplayState::unknown,
                       DisplayState::unknown};
  Check(recovery.Register(own, effects.identity[0]),
        "durable registration before helper launch");
  SetEvent(handles[predecessor_ready]);
  Wait(handles[clean_disarm], "wait for unmutated predecessor crash", 15000);
  return EXIT_FAILURE;
}
class Fixture {
public:
  Fixture() {
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    handles_[mapping] =
        CreateFileMappingW(INVALID_HANDLE_VALUE, &security, PAGE_READWRITE, 0,
                           sizeof(Effects), nullptr);
    Check(handles_[mapping] != nullptr, "fixture mapping");
    for (size_t i = 1; i < handles_.size(); ++i) {
      handles_[i] = CreateEventW(&security, TRUE, FALSE, nullptr);
      Check(handles_[i] != nullptr, "fixture ordering event");
    }
    view_ = std::make_unique<View>(handles_[mapping]);
    *view_->effects = Effects{};
    for (int i = 0; i < 2; ++i)
      view_->effects->state[i] = view_->effects->original[i] =
          static_cast<LONG>(DisplayState::sdr);
    wchar_t temp[MAX_PATH]{}, file[MAX_PATH]{};
    Check(GetTempPathW(MAX_PATH, temp) &&
              GetTempFileNameW(temp, L"hdr", 0, file),
          "isolated recovery journal");
    journal = file;
    Check(DeleteFileW(file), "new isolated journal starts absent");
    gate = L"Local\\Lineup.DisplayAdmissionTest-" +
           std::to_wstring(GetCurrentProcessId()) + L"-" +
           std::filesystem::path(journal).filename().wstring();
    job_.Reset(CreateJobObjectW(nullptr, nullptr));
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    Check(job_.Get() && SetInformationJobObject(
                            job_.Get(), JobObjectExtendedLimitInformation,
                            &limits, sizeof(limits)),
          "fixture process cleanup job");
  }
  ~Fixture() {
    // Every failure path kills this fixture's process tree before deleting
    // data.
    TerminateJobObject(job_.Get(), EXIT_FAILURE);
    for (auto &process : processes_)
      WaitForSingleObject(process, 6000);
    for (auto &process : processes_)
      CloseHandle(process);
    job_.Reset();
    view_.reset();
    for (HANDLE handle : handles_)
      if (handle)
        CloseHandle(handle);
    DeleteFileW(journal.c_str());
    DeleteFileW((journal + L".pending").c_str());
  }
  Effects &EffectsState() { return *view_->effects; }
  HANDLE Start(const std::wstring &role) {
    HANDLE process = Launch(role, journal, gate, handles_, {}, job_.Get());
    processes_.push_back(process);
    return process;
  }
  void Ready() { Wait(handles_[predecessor_ready], "predecessor ready"); }
  void Crash(HANDLE predecessor) {
    Check(TerminateProcess(predecessor, 17),
          "crash only predecessor main process");
    Wait(predecessor, "predecessor terminated");
    for (int i = 0; i < EffectsState().targets; ++i)
      Wait(handles_[paused_a + i], "guardian paused before recovery gate");
  }
  void Blocked() {
    Wait(handles_[admission_blocked],
         "successor observed unresolved predecessor record");
    Check(Read(EffectsState().captures) == 0 &&
              Read(EffectsState().successor_writes) == 0,
          "no premature successor original capture or matching write");
  }
  void ContinueGuardian(int index) {
    Check(SetEvent(handles_[continue_a + index]),
          "release deterministic guardian barrier");
  }
  void Reported() {
    Wait(handles_[successor_reported], "public successor display report");
  }
  void Finish(HANDLE successor) {
    SetEvent(handles_[finish_successor]);
    ExitSuccess(successor);
  }
  HANDLE Guardian(int index) {
    HANDLE process = OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE, FALSE,
                                 EffectsState().guardian_pid[index]);
    Check(process != nullptr, "exact fixture guardian process");
    return process;
  }
  void Disarm() { SetEvent(handles_[clean_disarm]); }
  void NextSuccessor() {
    ResetEvent(handles_[admission_blocked]);
    ResetEvent(handles_[successor_reported]);
    ResetEvent(handles_[finish_successor]);
  }
  std::wstring journal, gate;

private:
  Handles handles_{};
  std::unique_ptr<View> view_;
  Handle job_;
  std::vector<HANDLE> processes_;
};
void OrderedRelaunch(DisplayState desired, bool original_hdr = false) {
  Fixture f;
  if (original_hdr)
    f.EffectsState().state[0] = f.EffectsState().original[0] =
        static_cast<LONG>(DisplayState::hdr);
  f.EffectsState().desired = desired;
  HANDLE predecessor = f.Start(L"predecessor");
  f.Ready();
  f.Crash(predecessor);
  HANDLE successor = f.Start(L"successor");
  f.Blocked();
  f.ContinueGuardian(0);
  f.Reported();
  Check(!Read(f.EffectsState().successor_unavailable),
        "resolved predecessor admits successor");
  Check(Read(f.EffectsState().captured_state) == f.EffectsState().original[0],
        "successor captures user's original, never leftover temporary state");
  f.Finish(successor);
  Check(Read(f.EffectsState().state[0]) == f.EffectsState().original[0],
        "successor release preserves user original");
}
void TimeoutAndLoss(bool kill_guardian, bool reject, bool missing,
                    bool unobserved = false) {
  Fixture f;
  f.EffectsState().unobserved_attempt = unobserved;
  HANDLE predecessor = f.Start(L"predecessor");
  f.Ready();
  f.Crash(predecessor);
  Handle guardian(f.Guardian(0));
  HANDLE successor = f.Start(L"successor");
  f.Blocked();
  if (kill_guardian) {
    Check(TerminateProcess(guardian.Get(), 19), "controlled guardian loss");
    Wait(guardian.Get(), "lost guardian exited");
  } else if (reject || missing || unobserved) {
    InterlockedExchange(&f.EffectsState().reject_recovery, reject);
    InterlockedExchange(&f.EffectsState().target_missing, missing);
    f.ContinueGuardian(0);
    ExitResult(guardian.Get(), EXIT_FAILURE);
  }
  f.Reported();
  Check(Read(f.EffectsState().successor_unavailable),
        "uncertainty disables only matching");
  if (!kill_guardian && !reject && !missing && !unobserved) {
    f.ContinueGuardian(0);
    ExitSuccess(guardian.Get());
  }
  f.Finish(successor);
  if (kill_guardian) {
    // All guardian handles can disappear; the unresolved journal still fences
    // a later launch. Process termination is deliberately not safe completion.
    guardian.Reset();
    f.NextSuccessor();
    HANDLE later = f.Start(L"successor");
    f.Blocked();
    f.Reported();
    f.Finish(later);
  }
}
void MultipleTargets() {
  Fixture f;
  f.EffectsState().targets = 2;
  HANDLE predecessor = f.Start(L"predecessor");
  f.Ready();
  f.Crash(predecessor);
  Handle first(f.Guardian(0));
  HANDLE successor = f.Start(L"successor");
  f.Blocked();
  f.ContinueGuardian(0);
  ExitSuccess(first.Get());
  Check(Read(f.EffectsState().captures) == 0,
        "one safe target does not admit successor");
  f.ContinueGuardian(1);
  f.Reported();
  f.Finish(successor);
  Check(Read(f.EffectsState().state[0]) ==
                static_cast<LONG>(DisplayState::sdr) &&
            Read(f.EffectsState().state[1]) ==
                static_cast<LONG>(DisplayState::sdr),
        "both predecessor target originals restored");
}
void CleanDisarmAndExternalChange() {
  {
    Fixture f;
    HANDLE predecessor = f.Start(L"predecessor");
    f.Ready();
    HANDLE successor = f.Start(L"successor");
    f.Blocked();
    f.Disarm();
    ExitSuccess(predecessor);
    f.Reported();
    Check(!Read(f.EffectsState().successor_unavailable) &&
              Read(f.EffectsState().captured_state) ==
                  static_cast<LONG>(DisplayState::sdr),
          "clean disarm admits successor with correct original");
    f.Finish(successor);
    Check(Read(f.EffectsState().guardian_writes) == 0,
          "clean disarm prevents recovery");
  }
  {
    Fixture f;
    HANDLE predecessor = f.Start(L"predecessor");
    f.Ready();
    f.Crash(predecessor);
    HANDLE successor = f.Start(L"successor");
    f.Blocked();
    InterlockedExchange(&f.EffectsState().state[0],
                        static_cast<LONG>(DisplayState::sdr));
    f.ContinueGuardian(0);
    f.Reported();
    Check(!Read(f.EffectsState().successor_unavailable),
          "external safe state admits successor");
    f.Finish(successor);
    Check(Read(f.EffectsState().guardian_writes) == 0,
          "external original respected without writes");
  }
}
void DelayedResolvedGuardian() {
  Fixture f;
  f.EffectsState().desired = DisplayState::hdr;
  HANDLE predecessor = f.Start(L"predecessor");
  f.Ready();
  f.Crash(predecessor);
  // A different native recovery actor explicitly verifies and resolves the
  // hold while the original guardian remains paused with a stale identity.
  DisplayRecoveryCoordinator recovery(f.journal, f.gate);
  Api api(f.EffectsState(), Actor::guardian);
  Check(recovery.Recover(f.EffectsState().identity[0], api),
        "explicit safe recovery claim");
  HANDLE successor = f.Start(L"successor");
  f.Reported();
  Check(!Read(f.EffectsState().successor_unavailable) &&
            Read(f.EffectsState().state[0]) ==
                static_cast<LONG>(DisplayState::hdr),
        "successor HDR session starts after explicit recovery");
  Handle guardian(f.Guardian(0));
  f.ContinueGuardian(0);
  ExitSuccess(guardian.Get());
  Check(Read(f.EffectsState().guardian_writes) == 1 &&
            Read(f.EffectsState().state[0]) ==
                static_cast<LONG>(DisplayState::hdr),
        "stale guardian cannot interrupt successor HDR session");
  f.Finish(successor);
  Check(Read(f.EffectsState().state[0]) == static_cast<LONG>(DisplayState::sdr),
        "successor restores correct original after stale recovery exits");
}
void CorruptJournal() {
  Fixture f;
  DisplayRecoveryCoordinator recovery(f.journal, f.gate);
  Check(recovery.Admit(), "fresh journal admission");
  RecoveryIdentity identity;
  DisplayOwnership own{Api::Target(0), DisplayRoute::hdr_state,
                       DisplayState::sdr, DisplayState::hdr, DisplayState::hdr};
  Check(recovery.Register(own, identity), "durable journal positive control");
  {
    Handle file(CreateFileW(f.journal.c_str(), GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
    DWORD written = 0;
    const unsigned char corrupt = 0;
    Check(file.Get() != INVALID_HANDLE_VALUE &&
              WriteFile(file.Get(), &corrupt, 1, &written, nullptr) &&
              written == 1 && FlushFileBuffers(file.Get()),
          "deliberately corrupt journal fixture");
  }
  Api api(f.EffectsState(), Actor::guardian);
  Check(!recovery.Admit(std::chrono::milliseconds(0)) &&
            !recovery.Recover(identity, api) &&
            Read(f.EffectsState().guardian_writes) == 0,
        "corrupt journal cannot grant admission or recovery writes");
}

void UnmutatedOrphan() {
  Fixture f;
  HANDLE predecessor = f.Start(L"unmutated-predecessor");
  f.Ready();
  Check(TerminateProcess(predecessor, 23),
        "crash between registration and arm");
  Wait(predecessor, "unmutated predecessor terminated");
  HANDLE successor = f.Start(L"successor");
  f.Reported();
  Check(!Read(f.EffectsState().successor_unavailable) &&
            Read(f.EffectsState().captures) == 1 &&
            Read(f.EffectsState().captured_state) ==
                static_cast<LONG>(DisplayState::sdr) &&
            Read(f.EffectsState().guardian_writes) == 0,
        "proven dead unmutated registration resolves without display writes");
  f.Finish(successor);
}

void AbandonedGate() {
  Fixture f;
  HANDLE predecessor = f.Start(L"predecessor");
  f.Ready();
  f.Crash(predecessor);
  // Retain a handle so the owning thread's death leaves an abandoned object,
  // rather than destruction/recreation of the named gate.
  Handle gate(CreateMutexW(nullptr, FALSE, f.gate.c_str()));
  Check(gate.Get() != nullptr, "retain gate across abandoned owner");
  HANDLE owner = f.Start(L"abandon-gate");
  ExitSuccess(owner);
  HANDLE successor = f.Start(L"successor");
  f.Blocked();
  f.ContinueGuardian(0);
  f.Reported();
  Check(!Read(f.EffectsState().successor_unavailable),
        "explicit recovery permits admission after abandoned gate inspection");
  f.Finish(successor);
}
void NegativeControl() {
  Fixture f;
  f.EffectsState().desired = DisplayState::hdr;
  HANDLE predecessor = f.Start(L"predecessor");
  f.Ready();
  f.Crash(predecessor);
  HANDLE successor = f.Start(L"unfenced-successor");
  f.Reported();
  Check(Read(f.EffectsState().captures) == 1 &&
            Read(f.EffectsState().captured_state) ==
                static_cast<LONG>(DisplayState::hdr),
        "negative control detects premature leftover-HDR capture");
  f.Finish(successor);
  f.ContinueGuardian(0);
  Handle guardian(f.Guardian(0));
  ExitSuccess(guardian.Get());
}
} // namespace

std::optional<int> DispatchDisplayAdmissionTestChild(int argc, char **argv) {
  if (argc < 2 || std::string(argv[1]) != "--display-admission-test")
    return std::nullopt;
  int count = 0;
  wchar_t **raw = CommandLineToArgvW(GetCommandLineW(), &count);
  Check(raw != nullptr, "decode fixture child arguments");
  std::vector<std::wstring> args(raw, raw + count);
  LocalFree(raw);
  Check(args.size() == 5 + slots || args.size() == 8 + slots,
        "bounded explicit fixture arguments");
  Handles handles{};
  for (size_t i = 0; i < handles.size(); ++i)
    handles[i] = Number(args[5 + i]);
  View view(handles[mapping]);
  if (args[2] == L"abandon-gate") {
    Handle gate(CreateMutexW(nullptr, FALSE, args[4].c_str()));
    Wait(gate.Get(), "fixture owner acquires recovery gate");
    // Deliberately omit ReleaseMutex: returning ends this process/thread.
    return EXIT_SUCCESS;
  }
  if (args[2] == L"predecessor")
    return Predecessor(args[3], args[4], handles, *view.effects);
  if (args[2] == L"unmutated-predecessor")
    return UnmutatedPredecessor(args[3], args[4], handles, *view.effects);
  if (args[2] == L"successor" || args[2] == L"unfenced-successor")
    return Successor(args[3], args[4], handles, *view.effects,
                     args[2] == L"unfenced-successor");
  Check(args[2] == L"guardian-a" || args[2] == L"guardian-b",
        "known fixture role");
  Check(args.size() == 8 + slots, "guardian pipe and parent handles");
  const int index = args[2] == L"guardian-a" ? 0 : 1;
  Api api(*view.effects, Actor::guardian);
  auto recovery =
      std::make_shared<DisplayRecoveryCoordinator>(args[3], args[4]);
  return RunDisplayGuardian(Number(args[5 + slots]), Number(args[6 + slots]),
                            Number(args[7 + slots]), api, recovery, [&] {
                              SetEvent(handles[paused_a + index]);
                              Wait(handles[continue_a + index],
                                   "deterministic pre-acquisition pause",
                                   15000);
                            });
}
void RunDisplayAdmissionProcessTests() {
  NegativeControl();
  OrderedRelaunch(DisplayState::sdr);
  OrderedRelaunch(DisplayState::hdr);
  OrderedRelaunch(DisplayState::sdr, true);
  TimeoutAndLoss(false, false, false);
  MultipleTargets();
  CleanDisarmAndExternalChange();
  DelayedResolvedGuardian();
  CorruptJournal();
  UnmutatedOrphan();
  AbandonedGate();
  TimeoutAndLoss(true, false, false);
  TimeoutAndLoss(false, true, false);
  TimeoutAndLoss(false, false, true);
  TimeoutAndLoss(false, false, false, true);
  std::cout << "Win32 multiprocess admission/recovery passed (controlled "
               "display effects).\n";
}
