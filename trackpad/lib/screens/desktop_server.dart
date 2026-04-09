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
  bool _androidP2PActive = false;
  bool _isServerRunning = false;
  Process? _iproxyProcess;
  Process? _p2pProcess;

  bool get _isActive => _isServerRunning || _androidP2PActive;

  @override
  void initState() {
    super.initState();
  }

  void _fetchIp() async {
    List<String> ips = [];
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            if (addr.address.startsWith('192.168.') || addr.address.startsWith('10.')) {
              ips.insert(0, addr.address);
            } else {
              ips.add(addr.address);
            }
          }
        }
      }
    } catch (e) {
      _log("IP Fetch Error: $e");
    }
    setState(() {
      _myIp = ips.isNotEmpty ? ips.join("\n") : "No IP Found";
    });
  }

  void _startServer() async {
    _fetchIp();
    try {
      _log("Starting network server...");
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 50005);
      _udpSocket!.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = _udpSocket!.receive();
          if (dg != null) _processMessage(utf8.decode(dg.data));
        }
      });

      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, 50010);
      _tcpServer!.listen(_onNewConnection);

      _registration = await register(
        Service(
          name: 'MagicTrackpad-${Platform.localHostname}',
          type: '_trackpad._tcp',
          port: 50005,
        ),
      );
      
      setState(() => _isServerRunning = true);
      _log("Network Server Live (WiFi/USB TCP)");
    } catch (e) {
      _log("Server Error: $e");
      _stopServer();
    }
  }

  Future<void> _setupAndroidP2P() async {
    _log("Starting Android ADB P2P (No TCP)...");
    try {
      String adbPath = 'adb';
      if (Platform.isWindows) {
        final homeDir = Platform.environment['USERPROFILE'];
        if (homeDir != null) {
          final commonAdbPath = "$homeDir\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe";
          if (await File(commonAdbPath).exists()) adbPath = commonAdbPath;
        }
      } else if (Platform.isMacOS) {
        adbPath = await getAdbPath();
      }

      _p2pProcess?.kill();
      // Clear logs first so we don't process old movements
      await Process.run(adbPath, ['logcat', '-c']);
      
      // Listen specifically for the 'flutter' tag where print() output goes
      _p2pProcess = await Process.start(adbPath, ['logcat', '-s', 'flutter']);
      
      setState(() {
        _androidP2PActive = true;
      });

      _p2pProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        // Look for our prefix 'TP:' inside the flutter log line
        final tpIndex = line.indexOf('TP:');
        if (tpIndex != -1) {
          _processMessage(line.substring(tpIndex + 3));
        }
      }, onDone: () {
        if (mounted) setState(() => _androidP2PActive = false);
      }, onError: (e) => _log("P2P Error: $e"));
      
      _log("ADB P2P Active. Waiting for phone logs...");
    } catch (e) {
      _log("P2P Setup Failed: $e");
    }
  }

  void _stopServer() async {
    _log("Stopping all services...");
    if (_registration != null) await unregister(_registration!);
    _registration = null;
    _udpSocket?.close();
    _udpSocket = null;
    _tcpServer?.close();
    _tcpServer = null;
    _iproxyProcess?.kill();
    _iproxyProcess = null;
    _p2pProcess?.kill();
    _p2pProcess = null;
    
    for (var c in _connectedClients) { c.destroy(); }
    _connectedClients.clear();
    
    setState(() {
      _isServerRunning = false;
      _androidUsbActive = false;
      _iosUsbActive = false;
      _androidP2PActive = false;
    });
  }

  void _onNewConnection(Socket client) {
    setState(() => _connectedClients.add(client));
    utf8.decoder.bind(client).transform(const LineSplitter()).listen(
      (line) => _processMessage(line),
      onDone: () => setState(() => _connectedClients.remove(client)),
      onError: (e) => setState(() => _connectedClients.remove(client)),
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
      if (Platform.isWindows) {
        final homeDir = Platform.environment['USERPROFILE'];
        if (homeDir != null) {
          final commonAdbPath = "$homeDir\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe";
          if (await File(commonAdbPath).exists()) adbPath = commonAdbPath;
        }
      } else if (Platform.isMacOS) {
        adbPath = await getAdbPath();
      }
      final result = await Process.run(adbPath, ['reverse', 'tcp:50010', 'tcp:50010']);
      if (result.exitCode == 0) {
        setState(() => _androidUsbActive = true);
        _log("Android USB: Port 50010 reversed");
      } else {
        _log("ADB Error: ${result.stderr}");
      }
    } catch (e) {
      _log("ADB Error: $e");
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
      _iproxyProcess = await Process.start(iproxyPath, ['50011', '50010']);
      setState(() => _iosUsbActive = true);
      await Future.delayed(const Duration(seconds: 2));
      final socket = await Socket.connect('127.0.0.1', 50011, timeout: const Duration(seconds: 5));
      _onNewConnection(socket);
      _log("iOS USB Tunnel established!");
    } catch (e) {
      _log("iOS USB Failed: $e");
    }
  }

  Future<String> getAdbPath() async {
    final home = Platform.environment['HOME'];

    final candidates = [
      'adb', // try PATH first
      '$home/Library/Android/sdk/platform-tools/adb',
      '/opt/homebrew/bin/adb',
      '/usr/local/bin/adb',
    ];

    for (final path in candidates) {
      try {
        final result = await Process.run(path, ['version']);
        if (result.exitCode == 0) return path;
      } catch (_) {}
    }

    throw Exception('ADB not found');
  }

  @override
  void dispose() {
    _stopServer();
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
            _buildStatusHeader(),

            const SizedBox(height: 30),
            if (!_isActive)
              _buildStartButtons()
            else
              _buildControlPanel(),

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

  Widget _buildStatusHeader() {
    bool isLive = _isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: !isLive ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        !isLive ? "Offline" : (_androidP2PActive ? "ADB P2P Mode Active (No TCP)" : "${_connectedClients.length} Connected"),
        style: TextStyle(color: !isLive ? Colors.redAccent : Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildStartButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _startServer,
          icon: const Icon(Icons.network_check),
          label: const Text("Start Network Server (WiFi/USB)", style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), backgroundColor: Colors.blue.withOpacity(0.2), foregroundColor: Colors.blue),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _setupAndroidP2P,
          icon: const Icon(Icons.usb_off_rounded),
          label: const Text("Start ADB P2P (No-TCP)", style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), backgroundColor: Colors.orange.withOpacity(0.2), foregroundColor: Colors.orange),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_androidP2PActive)
                _buildStatusCard("ADB P2P", "Log-based\nNo TCP", Colors.orange)
              else ...[
                _buildStatusCard("WiFi IP", _myIp, Colors.blue),
                const SizedBox(width: 12),
                _buildStatusCard("Android USB", _androidUsbActive ? "Active" : "Ready", Colors.green),
                const SizedBox(width: 12),
                _buildStatusCard("iOS USB", _iosUsbActive ? "Active" : "Ready", Colors.grey),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!_androidP2PActive) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(onPressed: _setupAndroidUsb, icon: const Icon(Icons.android), label: const Text("ADB Reverse"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1), foregroundColor: Colors.green)),
              const SizedBox(width: 16),
              ElevatedButton.icon(onPressed: _setupIosUsb, icon: const Icon(Icons.apple), label: const Text("iOS USB"), style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), foregroundColor: Colors.white70)),
            ],
          ),
          const SizedBox(height: 20),
        ],
        TextButton.icon(onPressed: _stopServer, icon: const Icon(Icons.stop, size: 16), label: const Text("Stop All"), style: TextButton.styleFrom(foregroundColor: Colors.redAccent)),
      ],
    );
  }

  Widget _buildStatusCard(String title, String value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontFamily: 'Courier')),
        ],
      ),
    );
  }
}
