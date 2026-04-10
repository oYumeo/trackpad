# Trackpad P2P

**Trackpad P2P** allows you to simulate a high-precision trackpad or touchpad experience by connecting your Android or iOS device to a Mac or Windows machine via USB. By leveraging low-level device protocols (ADB and libimobiledevice), this tool bypasses standard network limitations to ensure a lag-free, secure connection.

---

## 🚀 Features
* **Cross-Platform Support:** Connect Android/iOS to macOS/Windows.
* **Low Latency:** Uses USB-to-TCP tunneling instead of Wi-Fi to eliminate lag.
* **Secure:** Data remains on the physical cable, bypassing standard network sniffers and aggressive antivirus monitoring.

---

## 🛠 Prerequisites & Installation

### 1. iOS Connectivity (Windows)
To bridge an iOS device to a Windows machine, you must install the native Apple drivers and the mobile device interface toolkit.

1.  **Install iTunes:** Download and install the latest version of [iTunes](https://www.apple.com/itunes/) (this provides the necessary USB drivers).
2.  **Setup libimobiledevice:**
    * Download the binary from [imobiledevice-net Releases](https://github.com/libimobiledevice-win32/imobiledevice-net/releases/tag/v1.3.17).
    * Extract the files to `C:\libimobiledevice`.
    * **Add to Environment Path:** * Search for "Edit the system environment variables" in Windows.
        * Click **Environment Variables** > Select **Path** > **Edit** > **New**.
        * Add `C:\libimobiledevice`.

### 2. iOS Connectivity (macOS)
macOS users can install the necessary libraries via Homebrew.

```bash
brew install libimobiledevice
```

### 3. Android Connectivity
Ensure you have **Platform Tools (ADB)** installed on your system.
* **macOS:** `brew install android-platform-tools`
* **Windows:** Ensure `adb.exe` is in your System Path.

---

## 🔍 Connection Verification

Before running the application, verify that your computer recognizes the mobile device over the USB interface.

### For iOS:
Open your terminal/command prompt and run:
```bash
idevice_id -l
```
*If a Unique Device ID (UDID) appears, the connection is successful.*

### For Android:
```bash
adb devices
```
*Verify your device appears in the list and shows "device" (not "unauthorized").*

---

## ⌨️ How to Use

1.  **Connect Device:** Plug your phone into your computer via a high-quality USB cable.
2.  **Start the Desktop Host:** Run the desktop application on your Mac or Windows machine.
3.  **Launch Mobile App:** Open the Trackpad app on your Android or iOS device.
4.  **Initialize Connection:**
    * On Android, the app will automatically attempt an `adb reverse` tunnel on port **50010** (or use the Logcat P2P fallback).
    * On iOS, ensure the "Trust this Computer" prompt has been accepted on the device.

---

## ⚠️ Troubleshooting
* **Broken Pipe Error:** If using Windows, ensure Trend Micro or other Antivirus software is not blocking `adb.exe` or `iproxy.exe`.
* **Device Not Found:** Try a different USB port (preferably directly into the motherboard/Mac) and ensure "USB Debugging" is on for Android.
