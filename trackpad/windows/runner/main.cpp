#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <vector>
#include <string>
#include <variant>

#include "flutter_window.h"
#include "utils.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

/**
 * InputSimulator: A production-ready utility class to handle native Windows input simulation.
 * This encapsulates mouse movement, clicks, scrolling, and complex keyboard gestures.
 */
class InputSimulator {
 public:
  static void HandleSimulate(const flutter::EncodableMap& args) {
    std::string type = GetString(args, "type");

    if (type == "move" || type == "drag") {
      MoveMouse(GetDouble(args, "dx"), GetDouble(args, "dy"));
    } else if (type == "click" || type == "mouseDown" || type == "mouseUp") {
      HandleClick(type, GetString(args, "button"), GetInt(args, "clickCount"));
    } else if (type == "scroll") {
      HandleScroll(GetDouble(args, "dx"), GetDouble(args, "dy"));
    } else if (type == "zoom") {
      HandleZoom(GetDouble(args, "scale"));
    } else if (type == "lookup" || type == "workspace" || type == "gesture") {
      HandleGestures(type, args);
    }
  }

 private:
  static void MoveMouse(double dx, double dy) {
    POINT p;
    if (GetCursorPos(&p)) {
      // Relative movement
      SetCursorPos(p.x + static_cast<int>(dx), p.y + static_cast<int>(dy));
    }
  }

  static void HandleClick(const std::string& type, std::string button, int count) {
    if (button.empty()) button = "left";

    DWORD downFlag = (button == "right") ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
    DWORD upFlag = (button == "right") ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP;

    for (int i = 0; i < count; ++i) {
      if (type == "mouseDown" || type == "click") {
        SendMouseInput(downFlag);
      }
      if (type == "mouseUp" || type == "click") {
        SendMouseInput(upFlag);
      }
      // Delay between clicks for system double-click detection
      if (count > 1 && i < count - 1) Sleep(15);
    }
  }

  static void HandleScroll(double dx, double dy) {
    // Windows WHEEL_DELTA is 120. Scale Flutter pixels accordingly.
    if (dy != 0) {
      SendMouseInput(MOUSEEVENTF_WHEEL, static_cast<DWORD>(-dy));
    }
    if (dx != 0) {
      SendMouseInput(MOUSEEVENTF_HWHEEL, static_cast<DWORD>(dx));
    }
  }

  static void HandleZoom(double scale) {
    // Windows equivalent for pinch-to-zoom is Ctrl + Mouse Wheel
    INPUT inputs[3] = {0};

    // Ctrl Down
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = VK_CONTROL;

    // Wheel
    inputs[1].type = INPUT_MOUSE;
    inputs[1].mi.dwFlags = MOUSEEVENTF_WHEEL;
    inputs[1].mi.mouseData = (scale > 1.0) ? WHEEL_DELTA : -WHEEL_DELTA;

    // Ctrl Up
    inputs[2].type = INPUT_KEYBOARD;
    inputs[2].ki.wVk = VK_CONTROL;
    inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;

    SendInput(3, inputs, sizeof(INPUT));
  }

  static void HandleGestures(const std::string& type, const flutter::EncodableMap& args) {
    std::string action = GetString(args, "action");
    std::string direction = GetString(args, "direction");

    if (type == "lookup" || action == "search") {
      SendKeyCombination({VK_LWIN, 'S'}); // Windows Search
    } else if (type == "workspace" || action == "taskView") {
      if (direction == "up" || direction == "down" || action == "taskView") {
        SendKeyCombination({VK_LWIN, VK_TAB}); // Task View
      } else if (direction == "left") {
        SendKeyCombination({VK_LWIN, VK_CONTROL, VK_LEFT}); // Previous Desktop
      } else if (direction == "right") {
        SendKeyCombination({VK_LWIN, VK_CONTROL, VK_RIGHT}); // Next Desktop
      }
    } else if (action == "showDesktop") {
      SendKeyCombination({VK_LWIN, 'D'}); // Toggle Desktop
    } else if (action == "actionCenter") {
      SendKeyCombination({VK_LWIN, 'A'}); // Quick Settings / Action Center
    } else if (action == "switchApp") {
      if (direction == "left") {
        SendKeyCombination({VK_MENU, VK_SHIFT, VK_TAB}); // Alt+Shift+Tab
      } else {
        SendKeyCombination({VK_MENU, VK_TAB}); // Alt+Tab
      }
    }
  }

  // --- Utility Methods for Robust Argument Handling ---

  static std::string GetString(const flutter::EncodableMap& map, const char* key) {
    auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end() && std::holds_alternative<std::string>(it->second)) {
      return std::get<std::string>(it->second);
    }
    return "";
  }

  static double GetDouble(const flutter::EncodableMap& map, const char* key) {
    auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end()) {
      if (std::holds_alternative<double>(it->second)) {
        return std::get<double>(it->second);
      }
      if (std::holds_alternative<int32_t>(it->second)) {
        return static_cast<double>(std::get<int32_t>(it->second));
      }
    }
    return 0.0;
  }

  static int GetInt(const flutter::EncodableMap& map, const char* key) {
    auto it = map.find(flutter::EncodableValue(key));
    if (it != map.end()) {
      if (std::holds_alternative<int32_t>(it->second)) {
        return std::get<int32_t>(it->second);
      }
    }
    return 1;
  }

  static void SendMouseInput(DWORD flags, DWORD data = 0) {
    INPUT input = {0};
    input.type = INPUT_MOUSE;
    input.mi.dwFlags = flags;
    input.mi.mouseData = data;
    SendInput(1, &input, sizeof(INPUT));
  }

  static void SendKeyCombination(const std::vector<BYTE>& keys) {
    std::vector<INPUT> inputs;
    // Press keys
    for (BYTE key : keys) {
      INPUT input = {0};
      input.type = INPUT_KEYBOARD;
      input.ki.wVk = key;
      inputs.push_back(input);
    }
    // Release keys in reverse
    for (auto it = keys.rbegin(); it != keys.rend(); ++it) {
      INPUT input = {0};
      input.type = INPUT_KEYBOARD;
      input.ki.wVk = *it;
      input.ki.dwFlags = KEYEVENTF_KEYUP;
      inputs.push_back(input);
    }
    SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
  }
};

void RegisterMouseSimulation(flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine->messenger(), "com.example.trackpad/mouse",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name().compare("simulate") == 0) {
          if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
            InputSimulator::HandleSimulate(*args);
            result->Success();
          } else {
            result->Error("INVALID_ARGS", "Expected a map of arguments");
          }
        } else {
          result->NotImplemented();
        }
      });
}

int APIENTRY wWinMain(_In_ HINSTANCE hInstance, _In_opt_ HINSTANCE hPrevInstance,
                     _In_ PWSTR lpCmdLine, _In_ int nShowCmd) {
  if (!Utils::GetSystemColors()) {
    return EXIT_FAILURE;
  }

  if (::HeapSetInformation(NULL, HeapEnableTerminationOnCorruption, NULL, 0) == 0) {
    return EXIT_FAILURE;
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments;
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"trackpad", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  RegisterMouseSimulation(window.GetRenderSurface()->GetEngine());

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  return EXIT_SUCCESS;
}
