import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nsd/nsd.dart';
import 'dart:io';
import 'trackpad_control.dart';

class MobileDiscovery extends StatefulWidget {
  const MobileDiscovery({super.key});

  @override
  State<MobileDiscovery> createState() => _MobileDiscoveryState();
}

class _MobileDiscoveryState extends State<MobileDiscovery> {
  final TextEditingController _ipController = TextEditingController();
  Discovery? _discovery;
  List<Service> _discoveredServices = [];
  bool _isUsbMode = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadSavedIp();
    if (!_isUsbMode) {
      _startDiscovery();
    }
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('last_ip');
    if (savedIp != null) setState(() => _ipController.text = savedIp);
    setState(() => _isUsbMode = prefs.getBool('usb_mode') ?? false);
  }

  Future<void> _startDiscovery() async {
    try {
      _discovery = await startDiscovery('_trackpad._tcp');
      _discovery?.addServiceListener((service, status) {
        if (status == ServiceStatus.found) {
          setState(() => _discoveredServices.add(service));
        } else {
          setState(() =>
              _discoveredServices.removeWhere((s) => s.name == service.name));
        }
      });
    } catch (e) {
      debugPrint("NSD Discovery Error: $e");
    }
  }

  @override
  void dispose() {
    if (_discovery != null) stopDiscovery(_discovery!);
    super.dispose();
  }

  void _connect(BuildContext context, String ip) async {
    if (ip.isEmpty) return;

    if (!_isUsbMode) {
      try {
        InternetAddress(ip);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Invalid IP address: $ip'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', ip);
    await prefs.setBool('usb_mode', _isUsbMode);
    
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrackpadControl(ip: ip, isUsbMode: _isUsbMode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Mac/PC'),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Mode Selector
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildModeButton(
                      title: "WiFi",
                      icon: Icons.wifi_rounded,
                      selected: !_isUsbMode,
                      onTap: () {
                        setState(() => _isUsbMode = false);
                        if (_discovery == null) _startDiscovery();
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildModeButton(
                      title: "Direct USB",
                      icon: Icons.usb_rounded,
                      selected: _isUsbMode,
                      onTap: () {
                        setState(() {
                          _isUsbMode = true;
                          _ipController.text = "localhost";
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            if (!_isUsbMode) ...[
              const Icon(Icons.wifi_rounded, size: 80, color: Colors.blue),
              const SizedBox(height: 10),
              const Text(
                "Looking for your device automatically...",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              if (_discoveredServices.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Found Devices:",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _discoveredServices.length,
                  itemBuilder: (context, i) {
                    final s = _discoveredServices[i];
                    return ListTile(
                      leading: const Icon(Icons.laptop_mac, color: Colors.blue),
                      title: Text(s.name ?? "Unknown Device"),
                      subtitle: Text(s.host ?? ""),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _connect(context, s.host!),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      tileColor: Colors.white.withOpacity(0.05),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),
              ],
              const Text(
                "Or enter IP manually:",
                style: TextStyle(fontSize: 14, color: Colors.white38),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Host IP Address",
                  hintText: "e.g. 192.168.1.5",
                  prefixIcon: const Icon(Icons.computer),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                ),
                onSubmitted: (ip) => _connect(context, ip),
              ),
            ] else ...[
              const Icon(Icons.usb_rounded, size: 80, color: Colors.green),
              const SizedBox(height: 10),
              const Text(
                "Direct USB Connection (No WiFi)",
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Setup Guide:",
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "1. Connect phone to PC via USB cable\n"
                      "2. Enable USB Debugging in phone developer settings\n"
                      "3. On your Mac/PC, click the 'Setup Android USB' button\n"
                      "4. Press connect below",
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
            
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isUsbMode ? Colors.green.withOpacity(0.8) : Colors.blue.withOpacity(0.8),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () => _connect(context, _ipController.text),
              child: Text(_isUsbMode ? "Connect via USB Tunnel" : "Connect Manually",
                  style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required String title,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? (title.contains("USB") ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2)) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? (title.contains("USB") ? Colors.green : Colors.blue) : Colors.white38),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white38,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
