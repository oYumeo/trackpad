import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let mouseChannel = FlutterMethodChannel(name: "com.example.trackpad/mouse",
                                            binaryMessenger: flutterViewController.engine.binaryMessenger)
    mouseChannel.setMethodCallHandler { (call, result) in
        if call.method == "simulate" {
            guard let args = call.arguments as? [String: Any],
                  let type = args["type"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                return
            }

            let mouseLocation = NSEvent.mouseLocation
            let screenHeight = NSScreen.main?.frame.height ?? 0
            let point = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)

            if type == "move" {
                let dx = args["dx"] as? Double ?? 0
                let dy = args["dy"] as? Double ?? 0
                let newLocation = CGPoint(x: point.x + CGFloat(dx), y: point.y + CGFloat(dy))
                let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: newLocation, mouseButton: .left)
                moveEvent?.post(tap: .cghidEventTap)
            }
            else if type == "drag" {
                let dx = args["dx"] as? Double ?? 0
                let dy = args["dy"] as? Double ?? 0
                let clickCount = args["clickCount"] as? Int ?? 1
                let newLocation = CGPoint(x: point.x + CGFloat(dx), y: point.y + CGFloat(dy))
                let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: newLocation, mouseButton: .left)
                dragEvent?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
                dragEvent?.post(tap: .cghidEventTap)
            }
            else if type == "mouseDown" {
                let button = args["button"] as? String ?? "left"
                let clickCount = args["clickCount"] as? Int ?? 1
                let downType = (button == "right") ? CGEventType.rightMouseDown : CGEventType.leftMouseDown
                let cgButton = (button == "right") ? CGMouseButton.right : CGMouseButton.left
                let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: cgButton)
                down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
                down?.post(tap: .cghidEventTap)
            }
            else if type == "mouseUp" {
                let button = args["button"] as? String ?? "left"
                let clickCount = args["clickCount"] as? Int ?? 1
                let upType = (button == "right") ? CGEventType.rightMouseUp : CGEventType.leftMouseUp
                let cgButton = (button == "right") ? CGMouseButton.right : CGMouseButton.left
                let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: cgButton)
                up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
                up?.post(tap: .cghidEventTap)
            }
            else if type == "click" {
                let button = args["button"] as? String ?? "left"
                let clickCount = args["clickCount"] as? Int ?? 1
                let downType = (button == "right") ? CGEventType.rightMouseDown : CGEventType.leftMouseDown
                let upType = (button == "right") ? CGEventType.rightMouseUp : CGEventType.leftMouseUp
                let cgButton = (button == "right") ? CGMouseButton.right : CGMouseButton.left

                let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: cgButton)
                let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: cgButton)

                down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
                up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))

                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
            }
            else if type == "scroll" {
                let dx = args["dx"] as? Double ?? 0
                let dy = args["dy"] as? Double ?? 0
                let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0)
                scroll?.post(tap: .cghidEventTap)
            }
            else if type == "zoom" {

                let src = CGEventSource(stateID: .hidSystemState)

                // Field raw values
                let zoomField = CGEventField(rawValue: 113)!   // zoom/magnification value
                let phaseField = CGEventField(rawValue: 132)!  // gesture phase

                // Begin
                let begin = CGEvent(source: src)!
                begin.type = CGEventType(rawValue: 29)!
                begin.setDoubleValueField(zoomField, value: 0)
                begin.setIntegerValueField(phaseField, value: 1)
                begin.post(tap: .cghidEventTap)

                // Change — zoom in
                for _ in 1...10 {
                    let change = CGEvent(source: src)!
                    change.type = CGEventType(rawValue: 29)!
                    change.setDoubleValueField(zoomField, value: 0.05)
                    change.setIntegerValueField(phaseField, value: 4)
                    change.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.016)
                }

                // End
                let end = CGEvent(source: src)!
                end.type = CGEventType(rawValue: 29)!
                end.setDoubleValueField(zoomField, value: 0)
                end.setIntegerValueField(phaseField, value: 8)
                end.post(tap: .cghidEventTap)
            }
            else if type == "lookup" {
                guard let source = CGEventSource(stateID: .hidSystemState) else {
                    result(nil)
                    return
                }
                let keyCodeD: CGKeyCode = 2 // kVK_ANSI_D
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeD, keyDown: true)
                keyDown?.flags = [.maskCommand, .maskControl]
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeD, keyDown: false)
                keyUp?.flags = [.maskCommand, .maskControl]

                keyDown?.post(tap: .cghidEventTap)
                usleep(50000)
                keyUp?.post(tap: .cghidEventTap)
            }
            else if type == "workspace" {
                let direction = args["direction"] as? String ?? "right"

                if direction == "up" || direction == "down" {
                    let mcPath = "/System/Applications/Mission Control.app"
                    if FileManager.default.fileExists(atPath: mcPath) {
                        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: mcPath), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                        result(nil)
                        return
                    }
                }

                let keyCode: CGKeyCode
                switch direction {
                case "left":  keyCode = 123
                case "right": keyCode = 124
                case "down":  keyCode = 125
                case "up":    keyCode = 126
                default:      keyCode = 124
                }

                guard let source = CGEventSource(stateID: .hidSystemState) else {
                    result(nil)
                    return
                }

                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
                keyDown?.flags = .maskControl

                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
                keyUp?.flags = .maskControl

                keyDown?.post(tap: .cghidEventTap)
                usleep(50000)
                keyUp?.post(tap: .cghidEventTap)
            }
            result(nil)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }

    super.awakeFromNib()
  }
}
