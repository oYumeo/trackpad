import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/mobile_discovery.dart';
import 'screens/desktop_server.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Set immersive mode for the whole app if desired, 
  // though TrackpadControl handles it specifically.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TrackpadApp());
}

class TrackpadApp extends StatelessWidget {
  const TrackpadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
          surface: Colors.black,
        ),
        useMaterial3: true,
      ),
      home: const PlatformSwitch(),
    );
  }
}

class PlatformSwitch extends StatelessWidget {
  const PlatformSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid || Platform.isIOS) {
      return const MobileDiscovery();
    } else {
      return const DesktopServer();
    }
  }
}
