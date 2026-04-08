import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nsd/nsd.dart';

class DesktopServer extends StatefulWidget {
  const DesktopServer({super.key});

  @override
  State<DesktopServer> createState() => _DesktopServerState();
}

class _DesktopServerState extends State<DesktopServer> {
  Registration? _registration;
  static const platform = MethodChannel('com.example.trackpad/mouse');
  final List<String> _logs = [];
  String _myIp = "Finding IP...";
  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  
  final List<Socket> _connectedClients = [];
  bool _androidUsbActive = false;
  bool _iosUsbActive = false;
  Process? _iproxyProcess;

  @override
  void initState() {
    super.initState();
    _fetchIp();
    _startServer();
  }

  void _fetchIp() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          setState(() => _myIp = addr.address);
          return;
        }
      }
    }
  }

  void _startServer() async {
    try {
      // WiFi UDP Listener
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 50005);
      _log("WiFi (UDP) ready on 50005");

      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = _udpSocket!.receive();
          if (dg != null) _processMessage(utf8.decode(dg.data));
        }
      });

      // USB/TCP Listener - Moved to 50010 to avoid conflict
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, 50010);
      _log("USB Tunnel (TCP) ready on 50010");
      _tcpServer!.listen(_onNewConnection);

      // Discovery for WiFi
      _registration = await register(
        Service(
          name: 'MagicTrackpad-${Platform.localHostname}',
          type: '_trackpad._tcp',
          port: 50005,
        ),
      );
    } catch (e) {
      _log("Server Error: $e");
    }
  }

  void _onNewConnection(Socket client) {
    setState(() => _connectedClients.add(client));
    _log("Connected: ${client.remoteAddress.address}");
    
    utf8.decoder.bind(client).transform(const LineSplitter()).listen(
      (line) => _processMessage(line),
      onDone: () {
        setState(() => _connectedClients.remove(client));
        _log("Disconnected: ${client.remoteAddress.address}");
      },
      onError: (e) {
        setState(() => _connectedClients.remove(client));
        _log("Connection Error: $e");
      },
    );
  }

  void _processMessage(String data) {
    try {
      for (var line in data.split("\n")) {
        if (line.trim().isEmpty) continue;
        final msg = jsonDecode(line);
        platform.invokeMethod('simulate', msg);
      }
    } catch (e) {
      debugPrint("Decoding error: $e");
    }
  }

  Future<void> _setupAndroidUsb() async {
    try {
      String adbPath = 'adb';
      
      // Try to find ADB in common Windows locations if the simple command fails
      if (Platform.isWindows) {
        final homeDir = Platform.environment['USERPROFILE'];
        if (homeDir != null) {
          final commonAdbPath = "$homeDir\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe";
          if (await File(commonAdbPath).exists()) {
            adbPath = commonAdbPath;
          }
        }
      }

      _log("Running ADB reverse...");
      // Maps Device:50010 -> Mac/PC:50010
      final result = await Process.run(adbPath, ['reverse', 'tcp:50010', 'tcp:50010']);
      
      if (result.exitCode == 0) {
        setState(() => _androidUsbActive = true);
        _log("Android USB: Port 50010 reversed");
      } else {
        _log("ADB Error (Exit ${result.exitCode}): ${result.stderr}");
        if (result.stderr.toString().contains("not found")) {
          _log("Tip: Ensure ADB is in PATH or Android SDK is installed.");
        }
      }
    } catch (e) {
      _log("ADB Process Error: $e");
      _log("Make sure Android SDK Platform-Tools are installed.");
    }
  }

  Future<void> _setupIosUsb() async {
    String iproxyPath = 'iproxy';
    
    if (Platform.isWindows) {
      iproxyPath = 'iproxy.exe';
      // Check common locations on Windows
      final possiblePaths = [
        'tools/iproxy.exe',
        'C:\\libimobiledevice\\iproxy.exe',
        'C:\\libimobiledevice-win32\\iproxy.exe',
      ];
      for (var path in possiblePaths) {
        if (await File(path).exists()) {
          iproxyPath = path;
          break;
        }
      }
    } else if (Platform.isMacOS) {
      iproxyPath = 'iproxy';
      final possiblePaths = [
        '/opt/homebrew/bin/iproxy',
        '/usr/local/bin/iproxy',
      ];
      for (var path in possiblePaths) {
        if (await File(path).exists()) {
          iproxyPath = path;
          break;
        }
      }
    } else {
      _log("iOS USB not supported on this platform");
      return;
    }
    
    _log("iOS USB: Starting $iproxyPath...");
    try {
      _iproxyProcess?.kill();
      
      // Port 50011 (PC) -> Port 50010 (iPhone)
      _iproxyProcess = await Process.start(iproxyPath, ['50011', '50010']);
      
      setState(() => _iosUsbActive = true);
      await Future.delayed(const Duration(seconds: 2));
      
      _log("Connecting to iOS tunnel (127.0.0.1:50011)...");
      final socket = await Socket.connect('127.0.0.1', 50011, timeout: const Duration(seconds: 5));
      _onNewConnection(socket);
      _log("iOS USB Tunnel established!");
      
    } catch (e) {
      _log("iOS USB Failed: $e");
      if (Platform.isWindows) {
        _log("Tip: Ensure iproxy.exe is in PATH or C:\\libimobiledevice");
      }
    }
  }

  @override
  void dispose() {
    if (_registration != null) unregister(_registration!);
    _udpSocket?.close();
    _iproxyProcess?.kill();
    for (var c in _connectedClients) { c.destroy(); }
    _tcpServer?.close();
    super.dispose();
  }

  void _log(String m) => setState(() => _logs.insert(0, m));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.computer_rounded, size: 80, color: Colors.blue),
            const SizedBox(height: 10),
            const Text("TRACKPAD RECEIVER", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _connectedClients.isEmpty ? Colors.grey.withOpacity(0.1) : Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _connectedClients.isEmpty ? "No Clients Connected" : "${_connectedClients.length} Client(s) Connected",
                style: TextStyle(color: _connectedClients.isEmpty ? Colors.grey : Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusCard("WiFi IP", _myIp, Colors.blue),
                const SizedBox(width: 12),
                _buildStatusCard("Android USB", _androidUsbActive ? "Active" : "Ready", _androidUsbActive ? Colors.green : Colors.grey),
                const SizedBox(width: 12),
                _buildStatusCard("iOS USB", _iosUsbActive ? "Active" : "Ready", _iosUsbActive ? Colors.green : Colors.grey),
              ],
            ),
            
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _setupAndroidUsb,
                  icon: const Icon(Icons.android),
                  label: const Text("Setup Android USB"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1), foregroundColor: Colors.green),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _setupIosUsb,
                  icon: const Icon(Icons.apple),
                  label: const Text("Setup iOS USB"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), foregroundColor: Colors.white70),
                ),
              ],
            ),

            const SizedBox(height: 30),
            const SizedBox(width: 500, child: Divider(color: Colors.white10)),
            SizedBox(
              height: 120,
              width: 500,
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (context, i) => Text(_logs[i], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white24, fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(String title, String value, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14, fontFamily: 'Courier')),
        ],
      ),
    );
  }
}
