# Trackpad

**Trackpad** turns your Android or iOS device into a high-precision, low-latency touchpad for Mac or Windows. By leveraging low-level USB protocols (ADB and libimobiledevice), it bypasses standard network interference for a smooth, professional experience.

---

## 🚀 Features
* **Cross-Platform:** Full support for Android/iOS connecting to macOS/Windows.
* **USB P2P Mode:** Uses USB-to-TCP tunneling to eliminate lag and bypass aggressive antivirus monitoring (like Trend Micro).
* **Wireless Mode:** Connect instantly over the same Wi-Fi network for maximum convenience.
* **Secure:** Physical cable data remains local, invisible to network sniffers.

---

## 🛠 Prerequisites & Installation

### 1. iOS Connectivity (Windows)
To bridge iOS to Windows, you need the Apple driver stack and the mobile interface toolkit.

1.  **Install iTunes:** Download [iTunes](https://www.apple.com/itunes/) to ensure the correct USB drivers are active.
2.  **Setup libimobiledevice:**
    * Download the binaries from [imobiledevice-net v1.3.17](https://github.com/libimobiledevice-win32/imobiledevice-net/releases/tag/v1.3.17).
    * Extract to `C:\libimobiledevice`.
3.  **Update Environment Path:**
    * Search Windows for **"Edit the system environment variables"**.
    * Click **Environment Variables** > Select **Path** > **Edit** > **New**.
    * Add `C:\libimobiledevice`.

### 2. iOS Connectivity (macOS)
Standard macOS users can install the toolkit via Homebrew:
```bash
brew install libimobiledevice
```

### 3. Android Connectivity
Ensure **Platform Tools (ADB)** is available in your terminal path.
* **macOS:** `brew install android-platform-tools`
* **Windows:** Ensure `adb.exe` is in your System Path.

---

## 🔍 Connection Verification

Before launching the app, verify the hardware handshake:

### **For iOS**
Run the following in your terminal:
```bash
idevice_id -l
```
*A successful connection will return your device's Unique Device ID (UDID).*

### **For Android**
Run the following in your terminal:
```bash
adb devices
```
*Verify your device is listed as `device`. If it says `unauthorized`, check your phone screen for the RSA prompt.*

---

## ⌨️ How to Use

1.  **Physical Link:** Plug your phone into your computer via USB.
2.  **Host Launch:** Open the **Trackpad Desktop Host** on your Mac or Windows.
3.  **App Launch:** Open the **Trackpad App** on your mobile device.
4.  **Establish Tunnel:**
    * **Android:** The app automatically triggers `adb reverse tcp:50010 tcp:50010`. If blocked by security software, it will fail-over to **Logcat P2P Mode**.
    * **iOS:** For Windows/Mac, run `iproxy 50010 50010` in the background to map the USB port to your local machine.
    * **Wireless:** Simply ensure both devices are on the same SSID and select the host from the mobile app's discovery list.

---

## ⚠️ Troubleshooting

* **SocketException / Broken Pipe:** This usually means an antivirus (like Trend Micro) has severed the TCP tunnel. Try switching the Android connection to **Logcat P2P Mode** in the app settings.
* **Device Not Found:** * **Android:** Ensure "USB Debugging" is enabled in Developer Options.
    * **iOS:** Ensure you have clicked "Trust" on the "Trust this Computer?" popup on your iPhone/iPad.
* **iproxy issues:** Ensure no other service is using port `50010` on your computer.
