#ifndef RUNNER_GLOBAL_BARCODE_HOOK_H_
#define RUNNER_GLOBAL_BARCODE_HOOK_H_

#include <windows.h>

#include <chrono>
#include <memory>
#include <string>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

class GlobalBarcodeHook {

 public:

  explicit GlobalBarcodeHook(
      flutter::BinaryMessenger* messenger
  );

  ~GlobalBarcodeHook();

  GlobalBarcodeHook(
      const GlobalBarcodeHook&
  ) = delete;

  GlobalBarcodeHook& operator=(
      const GlobalBarcodeHook&
  ) = delete;

 private:

  static LRESULT CALLBACK KeyboardProc(
      int code,
      WPARAM wparam,
      LPARAM lparam
  );

  LRESULT HandleKeyboard(
      int code,
      WPARAM wparam,
      LPARAM lparam
  );

  void FinishScan();

  static GlobalBarcodeHook* instance_;

  HHOOK hook_ = nullptr;

  std::unique_ptr<
      flutter::MethodChannel<flutter::EncodableValue>
  > channel_;

  std::wstring buffer_;

  std::chrono::steady_clock::time_point last_key_{};
};

#endif  // RUNNER_GLOBAL_BARCODE_HOOK_H_
