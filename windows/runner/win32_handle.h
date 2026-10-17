#ifndef RUNNER_WIN32_HANDLE_H_
#define RUNNER_WIN32_HANDLE_H_

#include <windows.h>

namespace lineup {
// Owns a kernel handle; nullptr and INVALID_HANDLE_VALUE are both empty.
class Handle {
 public:
  explicit Handle(HANDLE value = nullptr) : value_(value) {}
  ~Handle() { Reset(); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  HANDLE Get() const { return value_; }
  void Reset(HANDLE value = nullptr) {
    if (value_ && value_ != INVALID_HANDLE_VALUE) CloseHandle(value_);
    value_ = value;
  }

 private:
  HANDLE value_;
};
}
#endif
