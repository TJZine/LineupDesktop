#include "display_guardian.h"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <thread>

namespace {
using namespace lineup;
void Check(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}
const DisplayOwnership owned{{{42, -7}, 5},
                             DisplayRoute::hdr_state,
                             DisplayState::sdr,
                             DisplayState::hdr,
                             DisplayState::hdr};
struct FakeApi final : DisplayConfigApi {
  DisplayState observed = DisplayState::hdr;
  DisplayState requested = DisplayState::unknown;
  bool accept = true;
  int queries = 0, writes = 0;
  DisplayMapping MapWindow(HWND) override {
    throw std::runtime_error("mapping forbidden");
  }
  bool WaitForStartupRestore() override {
    throw std::runtime_error("startup wait forbidden");
  }
  DisplayObservation Query(DisplayTarget target, DisplayRoute route) override {
    Check(target == owned.target, "query exact target");
    Check(route == owned.route, "query captured route");
    ++queries;
    return {observed, route, true, "unknown"};
  }
  bool Set(DisplayTarget target, DisplayRoute route,
           DisplayState state) override {
    Check(target == owned.target && route == owned.route,
          "set exact target and route");
    ++writes;
    requested = state;
    if (accept)
      observed = state;
    return accept;
  }
};
GuardianRecord Arm() { return MakeGuardianRecord(GuardianKind::arm, 1, owned); }
void RestoreCases() {
  // Both EOF/broken command pipe and parent-handle signal enter this same
  // production recovery method. No processes or real display APIs are used.
  {
    GuardianSession session;
    Check(session.Accept(Arm()).has_value(), "arm ack");
    FakeApi api;
    session.ParentLost(api);
    Check(api.writes == 1 && api.queries == 2 &&
              api.requested == owned.original,
          "loss restores and verifies once");
    session.ParentLost(api);
    Check(api.writes == 1 && api.queries == 2, "loss never repeats restore");
  }
  GuardianSession attempted;
  auto in_flight = owned;
  in_flight.verified = DisplayState::unknown;
  Check(attempted.Accept(MakeGuardianRecord(GuardianKind::arm, 1, in_flight))
            .has_value(),
        "in-flight arm");
  FakeApi api;
  attempted.ParentLost(api);
  Check(api.writes == 1, "in-flight state qualifies for restore");

  GuardianSession verified;
  in_flight.verified = DisplayState::hdr;
  in_flight.attempted = DisplayState::unknown;
  Check(verified.Accept(MakeGuardianRecord(GuardianKind::arm, 1, in_flight))
            .has_value(),
        "verified arm");
  FakeApi failed;
  failed.accept = false;
  verified.ParentLost(failed);
  Check(failed.writes == 1 && failed.queries == 2,
        "rejected restore verifies once");
}
void NoActionCases() {
  for (DisplayState state : {DisplayState::sdr, DisplayState::unknown}) {
    GuardianSession session;
    Check(session.Accept(Arm()).has_value(), "arm");
    FakeApi api;
    api.observed = state;
    session.ParentLost(api);
    Check(api.queries == 1 && api.writes == 0,
          "original or unknown is never changed");
  }
  GuardianSession other;
  auto unchanged = owned;
  unchanged.verified = unchanged.attempted = DisplayState::unknown;
  Check(other.Accept(MakeGuardianRecord(GuardianKind::arm, 1, unchanged))
            .has_value(),
        "arm no writes");
  FakeApi api;
  other.ParentLost(api);
  Check(api.queries == 1 && api.writes == 0,
        "unowned observed state is not changed");

  GuardianSession disarmed;
  Check(disarmed.Accept(Arm()).has_value(), "arm before disarm");
  auto ack =
      disarmed.Accept(MakeGuardianRecord(GuardianKind::disarm, 2, owned));
  Check(ack && ValidGuardianAck(*ack, 2) && disarmed.Finished(),
        "disarm acknowledged");
  FakeApi after;
  disarmed.ParentLost(after);
  Check(after.queries == 0 && after.writes == 0, "disarm prohibits recovery");
  GuardianSession unarmed;
  unarmed.ParentLost(after);
  Check(after.queries == 0, "loss before arm has no target");
}
void ValidationCases() {
  for (int corruption = 0; corruption < 14; ++corruption) {
    GuardianSession session;
    Check(session.Accept(Arm()).has_value(), "valid initial arm");
    auto record = MakeGuardianRecord(GuardianKind::update, 2, owned);
    switch (corruption) {
    case 0:
      record.magic = 0;
      break;
    case 1:
      record.version = 2;
      break;
    case 2:
      record.sequence = 1;
      break;
    case 3:
      record.sequence = 3;
      break;
    case 4:
      record.kind = 9;
      break;
    case 5:
      record.route = 0;
      break;
    case 6:
      record.original = 0;
      break;
    case 7:
      record.verified = 99;
      break;
    case 8:
      record.attempted = 99;
      break;
    case 9:
      ++record.target;
      break;
    case 10:
      record.original = static_cast<uint32_t>(DisplayState::hdr);
      break;
    case 11:
      ++record.adapter_low;
      break;
    case 12:
      ++record.adapter_high;
      break;
    case 13:
      record.route = static_cast<uint32_t>(DisplayRoute::advanced_color);
      break;
    }
    Check(!session.Accept(record) && session.Finished(),
          "malformed record rejected");
    FakeApi api;
    session.ParentLost(api);
    Check(api.queries == 0 && api.writes == 0, "malformed never recovers");
  }
  GuardianSession partial;
  Check(partial.Accept(Arm()).has_value(), "arm before truncated record");
  partial.Malformed();
  FakeApi api;
  partial.ParentLost(api);
  Check(api.queries == 0, "partial record poisons session");
  for (GuardianKind kind : {GuardianKind::update, GuardianKind::disarm}) {
    GuardianSession session;
    Check(!session.Accept(MakeGuardianRecord(kind, 1, owned)),
          "arm must be first");
  }
  GuardianSession duplicate;
  Check(duplicate.Accept(Arm()).has_value(), "initial arm");
  Check(!duplicate.Accept(MakeGuardianRecord(GuardianKind::arm, 2, owned)),
        "second arm forbidden");
}
void AcknowledgmentCases() {
  GuardianSession session;
  auto ack = session.Accept(Arm());
  Check(ack && ValidGuardianAck(*ack, 1), "arm sequence acknowledged");
  auto update = owned;
  update.verified = DisplayState::unknown;
  ack = session.Accept(MakeGuardianRecord(GuardianKind::update, 2, update));
  Check(ack && ValidGuardianAck(*ack, 2), "update sequence acknowledged");
  Check(!ValidGuardianAck(*ack, 1), "stale ack rejected");
  ack->version = 2;
  Check(!ValidGuardianAck(*ack, 2), "wrong ack version rejected");
  ack->version = 1;
  ack->magic = 0;
  Check(!ValidGuardianAck(*ack, 2), "wrong ack magic rejected");
  FakeApi api;
  session.ParentLost(api);
  Check(api.writes == 1,
        "update retains attempted state through verification failure");
  Check(DispatchDisplayGuardian(L"--display-guardian") == EXIT_FAILURE,
        "invalid guardian arguments fail closed");
  Check(!DispatchDisplayGuardian(L"--media test").has_value(),
        "ordinary startup passes through");
}
void PipeLoopCases() {
  // Exercise the production loop with real local pipes, but no process launch
  // and no DisplayConfig calls. Parent death is a signaled event.
  for (int scenario = 0; scenario < 7; ++scenario) {
    HANDLE commands = nullptr, command_write = nullptr;
    HANDLE ack_read = nullptr, acknowledgments = nullptr;
    Check(CreatePipe(&commands, &command_write, nullptr, 4096) != FALSE,
          "command pipe");
    Check(CreatePipe(&ack_read, &acknowledgments, nullptr, 4096) != FALSE,
          "ack pipe");
    HANDLE parent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    Check(parent != nullptr, "parent signal seam");
    HANDLE signal = nullptr;
    Check(DuplicateHandle(GetCurrentProcess(), parent, GetCurrentProcess(),
                          &signal, EVENT_MODIFY_STATE, FALSE, 0) != FALSE,
          "duplicate signal");
    FakeApi api;
    std::thread worker(
        [&] { RunDisplayGuardian(commands, acknowledgments, parent, api); });
    auto send = [&](const GuardianRecord &record, bool expect_ack) {
      DWORD written = 0;
      Check(WriteFile(command_write, &record, sizeof(record), &written,
                      nullptr) &&
                written == sizeof(record),
            "send record");
      if (!expect_ack)
        return;
      DWORD available = 0;
      const auto deadline = GetTickCount64() + 2000;
      while (GetTickCount64() < deadline) {
        Check(PeekNamedPipe(ack_read, nullptr, 0, nullptr, &available,
                            nullptr) != FALSE,
              "ack pipe alive");
        if (available >= sizeof(GuardianAck))
          break;
        Sleep(5);
      }
      Check(available >= sizeof(GuardianAck), "bounded ack received");
      GuardianAck ack;
      DWORD read = 0;
      Check(ReadFile(ack_read, &ack, sizeof(ack), &read, nullptr) &&
                read == sizeof(ack) && ValidGuardianAck(ack, record.sequence),
            "production ack");
    };
    // Ensure assertion failures also close the pipe and join the worker.
    try {
      send(Arm(), true);
      if (scenario == 1)
        SetEvent(signal);
      if (scenario == 2)
        send(MakeGuardianRecord(GuardianKind::disarm, 2, owned), true);
      if (scenario == 3) {
        auto malformed = MakeGuardianRecord(GuardianKind::update, 3, owned);
        send(malformed, false);
      }
      if (scenario == 4) {
        auto partial = MakeGuardianRecord(GuardianKind::update, 2, owned);
        DWORD written = 0;
        Check(WriteFile(command_write, &partial, 5, &written, nullptr) &&
                  written == 5,
              "truncated record sent");
      }
      if (scenario == 5) {
        send(MakeGuardianRecord(GuardianKind::disarm, 2, owned), false);
        SetEvent(signal);
      }
      if (scenario == 6) {
        CloseHandle(ack_read);
        ack_read = nullptr;
        send(MakeGuardianRecord(GuardianKind::update, 2, owned), false);
      }
      // Keep commands open in the parent-signal and failed-ack cases to prove
      // that those triggers alone end the guardian.
      if (scenario != 1 && scenario != 6) {
        CloseHandle(command_write);
        command_write = nullptr;
      }
      worker.join();
      if (command_write) {
        CloseHandle(command_write);
        command_write = nullptr;
      }
      const bool restores = scenario < 2 || scenario == 6;
      Check(api.writes == (restores ? 1 : 0), "loop conditional restore");
      Check(api.queries == (restores ? 2 : 0),
            "loop query and verification counts");
    } catch (...) {
      if (command_write)
        CloseHandle(command_write);
      if (worker.joinable())
        worker.join();
      if (ack_read)
        CloseHandle(ack_read);
      CloseHandle(signal);
      throw;
    }
    if (ack_read)
      CloseHandle(ack_read);
    CloseHandle(signal);
  }
}
} // namespace
int main() {
  try {
    RestoreCases();
    NoActionCases();
    ValidationCases();
    AcknowledgmentCases();
    PipeLoopCases();
    std::cout << "Guardian protocol and conditional recovery passed (fake "
                 "DisplayConfig).\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
