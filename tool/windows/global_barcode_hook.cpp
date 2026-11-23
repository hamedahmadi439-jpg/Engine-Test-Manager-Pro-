#include "global_barcode_hook.h"

#include <algorithm>
#include <vector>

GlobalBarcodeHook* GlobalBarcodeHook::instance_ = nullptr;

GlobalBarcodeHook::GlobalBarcodeHook(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "engine_test_manager/barcode",
      &flutter::StandardMethodCodec::GetInstance());

  instance_ = this;

  hook_ = SetWindowsHookExW(
      WH_KEYBOARD_LL,
      KeyboardProc,
      GetModuleHandleW(nullptr),
      0
  );
}

GlobalBarcodeHook::~GlobalBarcodeHook() {
  if (hook_ != nullptr)
    UnhookWindowsHookEx(hook_);

  if (instance_ == this)
    instance_ = nullptr;
}

LRESULT CALLBACK GlobalBarcodeHook::KeyboardProc(
    int code,
    WPARAM wparam,
    LPARAM lparam) {

  if (instance_ != nullptr)
    return instance_->HandleKeyboard(code, wparam, lparam);

  return CallNextHookEx(nullptr, code, wparam, lparam);
}

LRESULT GlobalBarcodeHook::HandleKeyboard(
    int code,
    WPARAM wparam,
    LPARAM lparam) {

  if (code == HC_ACTION &&
      (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN)) {

    const auto* key =
        reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);

    if (key != nullptr) {

      if (key->vkCode == VK_RETURN ||
          key->vkCode == VK_SEPARATOR) {

        FinishScan();

      } else if (key->vkCode == VK_BACK ||
                 key->vkCode == VK_ESCAPE) {

        buffer_.clear();

      } else {

        const bool ctrl =
            (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;

        const bool alt =
            (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;

        if (!ctrl && !alt) {

          wchar_t ch = 0;

          if (key->vkCode >= 0x30 && key->vkCode <= 0x39) {
            ch = static_cast<wchar_t>(key->vkCode);

          } else if (key->vkCode >= 0x41 && key->vkCode <= 0x5A) {
            ch = static_cast<wchar_t>(key->vkCode);

          } else if (key->vkCode == VK_OEM_MINUS) {
            ch = L'-';

          } else if (key->vkCode == VK_OEM_PERIOD) {
            ch = L'.';

          } else if (key->vkCode == VK_OEM_2) {
            ch = L'/';
          }

          if (ch != 0) {

            const auto now =
                std::chrono::steady_clock::now();

            if (!buffer_.empty()) {

              const auto gap =
                  std::chrono::duration_cast<
                      std::chrono::milliseconds>(
                      now - last_key_).count();

              if (gap > 85)
                buffer_.clear();
            }

            buffer_.push_back(ch);

            last_key_ = now;

            if (buffer_.size() > 64)
              buffer_.clear();
          }
        }
      }
    }
  }

  return CallNextHookEx(hook_, code, wparam, lparam);
}

void GlobalBarcodeHook::FinishScan() {

  if (buffer_.size() >= 5) {

    const int needed =
        WideCharToMultiByte(
            CP_UTF8,
            0,
            buffer_.data(),
            static_cast<int>(buffer_.size()),
            nullptr,
            0,
            nullptr,
            nullptr
        );

    if (needed > 0) {

      std::string value(
          static_cast<size_t>(needed),
          '\0'
      );

      WideCharToMultiByte(
          CP_UTF8,
          0,
          buffer_.data(),
          static_cast<int>(buffer_.size()),
          value.data(),
          needed,
          nullptr,
          nullptr
      );

      channel_->InvokeMethod(
          "barcode",
          std::make_unique<flutter::EncodableValue>(value)
      );
    }
  }

  buffer_.clear();
}
