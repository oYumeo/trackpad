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

enum ConnectionMode { wifi, usb, adbP2P }

class _MobileDiscoveryState extends State<MobileDiscovery> {
  final TextEditingController _ipController = TextEditingController();
  Discovery? _discovery;
  List<Service> _discoveredServices = [];
  ConnectionMode _mode = ConnectionMode.wifi;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadSavedIp();
    if (_mode == ConnectionMode.wifi) {
      _startDiscovery();
    }
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('last_ip');
    if (savedIp != null) setState(() => _ipController.text = savedIp);
    final modeIndex = prefs.getInt('connection_mode') ?? 0;
    setState(() => _mode = ConnectionMode.values[modeIndex]);
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
    if (_mode == ConnectionMode.wifi && ip.isEmpty) return;

    if (_mode == ConnectionMode.wifi) {
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
    await prefs.setInt('connection_mode', _mode.index);
    
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrackpadControl(
          ip: ip, 
          isUsbMode: _mode == ConnectionMode.usb,
          isP2PMode: _mode == ConnectionMode.adbP2P,
        ),
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
                      selected: _mode == ConnectionMode.wifi,
                      onTap: () {
                        setState(() => _mode = ConnectionMode.wifi);
                        if (_discovery == null) _startDiscovery();
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildModeButton(
                      title: "USB Tunnel",
                      icon: Icons.usb_rounded,
                      selected: _mode == ConnectionMode.usb,
                      onTap: () {
                        setState(() {
                          _mode = ConnectionMode.usb;
                          _ipController.text = "127.0.0.1";
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: _buildModeButton(
                      title: "ADB P2P",
                      icon: Icons.usb_off_rounded,
                      selected: _mode == ConnectionMode.adbP2P,
                      onTap: () {
                        setState(() {
                          _mode = ConnectionMode.adbP2P;
                          _ipController.text = "P2P";
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            if (_mode == ConnectionMode.wifi) ...[
              const Icon(Icons.wifi_rounded, size: 80, color: Colors.blue),
              const SizedBox(height: 10),
              const Text("Looking for devices automatically...", style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              if (_discoveredServices.isNotEmpty) ...[
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
                      onTap: () => _connect(context, s.host!),
                      tileColor: Colors.white.withOpacity(0.05),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
              TextField(
                controller: _ipController,
                decoration: InputDecoration(labelText: "Manual IP", border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))),
                onSubmitted: (ip) => _connect(context, ip),
              ),
            ] else if (_mode == ConnectionMode.usb) ...[
              const Icon(Icons.usb_rounded, size: 80, color: Colors.green),
              const SizedBox(height: 10),
              const Text("USB Tunnel Mode (TCP via ADB/iproxy)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _buildGuide("1. Connect USB cable\n2. Run 'ADB Reverse' or 'iproxy' on PC\n3. Press connect below"),
            ] else ...[
              const Icon(Icons.usb_off_rounded, size: 80, color: Colors.orange),
              const SizedBox(height: 10),
              const Text("ADB P2P Mode (No-TCP)", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              _buildGuide("1. Connect USB cable\n2. Click 'Start ADB P2P' on PC app\n3. No network ports will be opened\n4. Perfect for bypassing virus protectors"),
            ],
            
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _mode == ConnectionMode.adbP2P ? Colors.orange.withOpacity(0.8) : (_mode == ConnectionMode.usb ? Colors.green.withOpacity(0.8) : Colors.blue.withOpacity(0.8)),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () => _connect(context, _ipController.text),
              child: Text("Connect / Start Control", style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuide(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
    );
  }

  Widget _buildModeButton({required String title, required IconData icon, required bool selected, required VoidCallback onTap}) {
    Color color = title.contains("USB") ? Colors.green : (title.contains("P2P") ? Colors.orange : Colors.blue);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: selected ? color.withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : Colors.white38),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: selected ? Colors.white : Colors.white38, fontSize: 10, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
