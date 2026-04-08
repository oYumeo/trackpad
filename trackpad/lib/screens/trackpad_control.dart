import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/ripple_widget.dart';
import '../widgets/grid_painter.dart';

class TrackpadControl extends StatefulWidget {
  final String ip;
  final bool isUsbMode;
  const TrackpadControl({super.key, required this.ip, this.isUsbMode = false});

  @override
  State<TrackpadControl> createState() => _TrackpadControlState();
}

class _TrackpadControlState extends State<TrackpadControl> with TickerProviderStateMixin {
  RawDatagramSocket? _udpSender;
  Socket? _tcpSocket; // This will be either the client or the connected server socket
  ServerSocket? _iosUsbServer;
  bool _connected = false;
  bool _connecting = true;
  InternetAddress? _targetAddress;

  double _sensitivity = 4.0;
  bool _showSensitivity = false;
  Timer? _sensitivityHideTimer;

  final Map<int, Offset> _pointerPositions = {};
  final Map<int, int> _pointerDownTimes = {};
  int _maxPointers = 0;

  Offset _lastFocalPoint = Offset.zero;
  bool _isDragging = false;
  double _totalScrollDistance = 0.0;
  double _totalDragDistance = 0.0;

  Offset _tapPosition = Offset.zero;
  int _lastTapTime = 0;
  int _lastClickTime = 0;
  int _clickCount = 1;

  bool _isDoubleTapDragging = false;
  bool _isHoldDragging = false;
  Timer? _longPressTimer;

  bool _selectionMode = false;

  Offset _scrollVelocity = Offset.zero;
  Timer? _inertiaTimer;

  final List<RippleEffect> _ripples = [];
  late final AnimationController _rippleController;
  String _gestureLabel = '';
  Timer? _labelTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat();
    _connect();
  }

  void _connect() async {
    setState(() {
      _connecting = true;
      _connected = false;
    });

    try {
      if (widget.isUsbMode) {
        if (Platform.isIOS) {
          // iOS USB MODE: The iPhone acts as the SERVER on port 50010.
          // iproxy on Mac (port 50011) will connect to this server.
          _iosUsbServer = await ServerSocket.bind(InternetAddress.anyIPv4, 50010);
          _showLabel("iOS USB: Waiting for Mac...");
          
          _iosUsbServer!.listen((Socket client) {
            setState(() {
              _tcpSocket = client;
              _connected = true;
              _connecting = false;
            });
            _showLabel("Connected to Mac via USB");
            HapticFeedback.heavyImpact();
            
            client.done.then((_) {
              if (mounted) setState(() => _connected = false);
            });
          });
        } else {
          // ANDROID USB MODE: The Phone acts as a CLIENT (connects to Mac via adb reverse)
          // Mac runs 'adb reverse tcp:50010 tcp:50010'
          final targetIp = (widget.ip == "localhost" || widget.ip == "127.0.0.1") ? "127.0.0.1" : widget.ip;
          _tcpSocket = await Socket.connect(targetIp, 50010, timeout: const Duration(seconds: 5));
          _tcpSocket!.setOption(SocketOption.tcpNoDelay, true);
          
          setState(() {
            _connected = true;
            _connecting = false;
          });
        }
      } else {
        // WIFI MODE: UDP
        _targetAddress = InternetAddress(widget.ip);
        _udpSender = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        setState(() {
          _connected = true;
          _connecting = false;
        });
      }

      if (_connected) {
        HapticFeedback.mediumImpact();
        _showLabel(widget.isUsbMode ? "USB (TCP) Active" : "WiFi (UDP) Active");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Connection failed: $e")),
        );
        Navigator.pop(context);
      }
    }
  }

  void _send(Map<String, dynamic> data) {
    if (!_connected) return;

    final message = jsonEncode(data) + "\n";

    if (widget.isUsbMode && _tcpSocket != null) {
      _tcpSocket!.write(message);
    } else if (_udpSender != null && _targetAddress != null) {
      final bytes = utf8.encode(message);
      _udpSender!.send(bytes, _targetAddress!, 50005);
    }
  }

  void _showLabel(String label) {
    _labelTimer?.cancel();
    setState(() => _gestureLabel = label);
    _labelTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _gestureLabel = '');
    });
  }

  void _triggerSensitivityShow() {
    _sensitivityHideTimer?.cancel();
    setState(() => _showSensitivity = true);
    _sensitivityHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSensitivity = false);
    });
  }

  void _addRipple(Offset position) {
    setState(() {
      _ripples.add(RippleEffect(position: position));
      if (_ripples.length > 5) _ripples.removeAt(0);
    });
  }

  void _handleTap(Size size) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastClickTime < 400) {
      _clickCount++;
    } else {
      _clickCount = 1;
    }
    _lastClickTime = now;

    final isBottomRight = _tapPosition.dx > size.width * 0.75 && _tapPosition.dy > size.height * 0.75;

    if (_maxPointers == 2 || (_maxPointers == 1 && isBottomRight)) {
      if (_maxPointers == 2 && _totalScrollDistance > 40) return;
      HapticFeedback.mediumImpact();
      _send({'type': 'click', 'button': 'right', 'clickCount': _clickCount});
      _showLabel(_clickCount > 1 ? 'Right Double Click' : 'Right Click');
    } else if (_maxPointers == 3) {
      if (_totalDragDistance > 40) return;
      HapticFeedback.heavyImpact();
      _send({'type': 'lookup'});
      _showLabel('Look Up');
    } else if (_maxPointers == 1) {
      HapticFeedback.lightImpact();
      _send({'type': 'click', 'button': 'left', 'clickCount': _clickCount});
      _showLabel(_clickCount > 1 ? 'Double Click' : 'Click');
    }
  }

  void _startInertia() {
    _inertiaTimer?.cancel();
    _inertiaTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_scrollVelocity.distance < 0.5) {
        timer.cancel();
        return;
      }
      _send({
        'type': 'scroll',
        'dx': _scrollVelocity.dx * 2,
        'dy': _scrollVelocity.dy * 2,
      });
      _scrollVelocity *= 0.92;
    });
  }

  @override
  void dispose() {
    _udpSender?.close();
    _tcpSocket?.destroy();
    _iosUsbServer?.close();
    _inertiaTimer?.cancel();
    _labelTimer?.cancel();
    _sensitivityHideTimer?.cancel();
    _longPressTimer?.cancel();
    _rippleController.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final surfaceSize = Size(constraints.maxWidth, constraints.maxHeight);
                    return _buildTrackpadSurface(surfaceSize);
                  },
                ),
              ),
              _buildRightPanel(),
            ],
          ),
          _buildStatusBar(),
          if (_gestureLabel.isNotEmpty) _buildGestureLabel(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final statusColor = _connecting 
        ? Colors.orange 
        : _connected 
            ? (widget.isUsbMode ? Colors.green : Colors.blue) 
            : Colors.red;

    return Positioned(
      top: 0,
      left: 0,
      right: 160,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withOpacity(0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _connecting
                    ? (Platform.isIOS && widget.isUsbMode ? 'Waiting for Mac USB...' : 'Connecting...')
                    : _connected
                        ? '${widget.isUsbMode ? "Direct USB" : "WiFi"}: ${widget.ip}'
                        : 'Disconnected — retrying',
                style: TextStyle(fontSize: 12, color: _connected ? Colors.white54 : Colors.red.shade300),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectionMode = !_selectionMode;
                  if (_selectionMode) {
                    _send({'type': 'mouseDown', 'button': 'left'});
                    HapticFeedback.heavyImpact();
                  } else {
                    _send({'type': 'mouseUp', 'button': 'left'});
                    HapticFeedback.mediumImpact();
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _selectionMode ? Colors.blue.withOpacity(0.25) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _selectionMode ? Colors.blue : Colors.white38.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_selectionMode ? Icons.select_all : Icons.deselect, size: 14, color: _selectionMode ? Colors.blue : Colors.white38),
                    const SizedBox(width: 4),
                    Text(_selectionMode ? 'Selecting' : 'Select', style: TextStyle(fontSize: 11, color: _selectionMode ? Colors.blue : Colors.white38)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(6),
                child: const Icon(Icons.close, size: 16, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGestureLabel() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 160,
      child: Center(
        child: AnimatedOpacity(
          opacity: _gestureLabel.isNotEmpty ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(_gestureLabel, style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 1)),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackpadSurface(Size surfaceSize) {
    return Listener(
      onPointerDown: (e) {
        if (_pointerPositions.length >= 4) return;
        _inertiaTimer?.cancel();
        _tapPosition = e.localPosition;
        _addRipple(e.localPosition);
        final now = DateTime.now().millisecondsSinceEpoch;
        setState(() {
          if (_pointerPositions.isEmpty) {
            _maxPointers = 0;
            _isDragging = false;
            _isHoldDragging = false;
            _totalScrollDistance = 0.0;
            _totalDragDistance = 0.0;
          }
          _pointerPositions[e.pointer] = e.localPosition;
          _pointerDownTimes[e.pointer] = now;
          if (_pointerPositions.length > _maxPointers) _maxPointers = _pointerPositions.length;
          if (_pointerPositions.length > 1) {
            _longPressTimer?.cancel();
            if (_isHoldDragging) {
              _send({'type': 'mouseUp', 'button': 'left'});
              _isHoldDragging = false;
              _showLabel('Drag Released');
            }
          }
          if (_pointerPositions.length == 1) {
            _longPressTimer?.cancel();
            _longPressTimer = Timer(const Duration(milliseconds: 250), () {
              if (mounted && _pointerPositions.length == 1 && !_isDragging) {
                setState(() {
                  _isHoldDragging = true;
                  _send({'type': 'mouseDown', 'button': 'left'});
                  HapticFeedback.heavyImpact();
                  _showLabel('Hold Drag');
                });
              }
            });
          }
          if (now - _lastTapTime < 250 && _pointerPositions.length == 1) {
            _isDoubleTapDragging = true;
            _send({'type': 'mouseDown', 'button': 'left', 'clickCount': 2});
            HapticFeedback.heavyImpact();
            _showLabel('Double Tap Drag');
          }
          _lastTapTime = now;
        });
      },
      onPointerMove: (e) {
        if (!_pointerPositions.containsKey(e.pointer)) return;
        if (!_isHoldDragging && (e.localPosition - _tapPosition).distance > 20) _longPressTimer?.cancel();
        setState(() => _pointerPositions[e.pointer] = e.localPosition);
      },
      onPointerUp: (e) {
        if (!_pointerPositions.containsKey(e.pointer)) return;
        _longPressTimer?.cancel();
        final now = DateTime.now().millisecondsSinceEpoch;
        final duration = now - (_pointerDownTimes[e.pointer] ?? now);
        setState(() {
          _pointerPositions.remove(e.pointer);
          _pointerDownTimes.remove(e.pointer);
          if (_pointerPositions.isEmpty) {
            if (_isHoldDragging) {
              _send({'type': 'mouseUp', 'button': 'left'});
              _isHoldDragging = false;
            } else if (_isDoubleTapDragging) {
              _send({'type': 'mouseUp', 'button': 'left', 'clickCount': 2});
              _isDoubleTapDragging = false;
            } else if (!_isDragging && !_selectionMode && _maxPointers <= 2 && duration < 300) {
              _handleTap(surfaceSize);
            }
          }
        });
      },
      onPointerCancel: (e) {
        if (!_pointerPositions.containsKey(e.pointer)) return;
        _longPressTimer?.cancel();
        setState(() {
          _pointerPositions.remove(e.pointer);
          _pointerDownTimes.remove(e.pointer);
          if (_pointerPositions.isEmpty) {
            _maxPointers = 0;
            _isDragging = false;
            _isHoldDragging = false;
          }
        });
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _lastFocalPoint = details.focalPoint;
          _isDragging = false;
          _scrollVelocity = Offset.zero;
          _totalScrollDistance = 0.0;
          _totalDragDistance = 0.0;
          _inertiaTimer?.cancel();
        },
        onScaleUpdate: (details) {
          final delta = details.focalPoint - _lastFocalPoint;
          _lastFocalPoint = details.focalPoint;
          final pCount = details.pointerCount;
          if (delta.distance > 200) return;
          if (delta.distance > 0.5) _isDragging = true;
          if (pCount == 1) {
            final type = (_selectionMode || _isDoubleTapDragging || _isHoldDragging) ? 'drag' : 'move';
            _send({'type': type, 'dx': delta.dx * _sensitivity, 'dy': delta.dy * _sensitivity, if (_isDoubleTapDragging) 'clickCount': 2});
          } else if (pCount == 2) {
            // if (details.scale != 1.2) {
            //   _send({'type': 'zoom', 'scale': details.scale - 0.2});
            //   _showLabel(details.scale > 1.0 ? 'Zoom In' : 'Zoom Out');
            // } else {
              _totalScrollDistance += delta.distance;
              _scrollVelocity = delta;
              _send({
                'type': 'scroll',
                'dx': delta.dx * -2,
                'dy': delta.dy * -2,
              });

            // }
          } else if (pCount == 3) {
            _totalDragDistance += delta.distance;
          }
        },
        onScaleEnd: (details) {
          if (_pointerPositions.isEmpty && _maxPointers == 2 && _isDragging) _startInertia();
          if (_isDragging) {
            final vx = details.velocity.pixelsPerSecond.dx;
            final vy = details.velocity.pixelsPerSecond.dy;
            if (_maxPointers == 3 && _totalDragDistance > 40) {
              if (vx > 400) {
                _send({'type': 'workspace', 'direction': 'left'});
                _showLabel('← Space');
              } else if (vx < -400) {
                _send({'type': 'workspace', 'direction': 'right'});
                _showLabel('Space →');
              } else if (vy < -400) {
                _send({'type': 'workspace', 'direction': 'up'});
                _showLabel('Mission Control');
              } else if (vy > 400) {
                _send({'type': 'workspace', 'direction': 'down'});
                _showLabel('Close Mission Control');
              }
            }
          }
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 44, 10, 20),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _selectionMode ? Colors.blue : (_isDoubleTapDragging || _isHoldDragging) ? Colors.blue.withOpacity(0.7) : Colors.blue.withOpacity(0.18),
              width: _selectionMode ? 2 : 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28.5),
            child: Stack(
              children: [
                CustomPaint(painter: GridPainter(), size: Size.infinite),
                ..._ripples.map((r) => Positioned(left: r.position.dx - 120, top: r.position.dy - 120, child: RippleWidget(effect: r))),
                ..._pointerPositions.values.map((pos) => Positioned(
                  left: pos.dx - 80,
                  top: pos.dy - 80,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [Colors.blue.withOpacity(0.18), Colors.blue.withOpacity(0.0)]),
                    ),
                  ),
                )),
                Center(
                  child: AnimatedOpacity(
                    opacity: _pointerPositions.isNotEmpty ? 0.0 : 0.07,
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_selectionMode ? Icons.select_all : Icons.touch_app_outlined, size: 48, color: Colors.white),
                        const SizedBox(height: 8),
                        Text(_selectionMode ? 'SELECTION ACTIVE' : 'TRACKPAD', style: const TextStyle(letterSpacing: 6, fontWeight: FontWeight.w300, fontSize: 11, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Opacity(
                    opacity: 0.04,
                    child: Container(
                      width: 60,
                      height: 40,
                      decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Text('R', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      width: 150,
      padding: const EdgeInsets.only(top: 44, bottom: 20, left: 8, right: 16),
      child: Column(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    _send({'type': 'zoom'});
                    _showLabel('Mission Control');
                  },
                  child: Container(padding: const EdgeInsets.all(6), child: const Icon(Icons.control_camera, size: 16, color: Colors.white38)),
                ),
                const Text('SPEED', style: TextStyle(fontSize: 10, letterSpacing: 3, color: Colors.white38, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('${_sensitivity.toStringAsFixed(1)}×', style: const TextStyle(color: Colors.blue, fontSize: 22, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 12),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        activeTrackColor: Colors.blue,
                        inactiveTrackColor: Colors.white10,
                        thumbColor: Colors.white,
                        overlayColor: Colors.blue.withOpacity(0.15),
                      ),
                      child: Slider(value: _sensitivity, min: 0.5, max: 6.0, onChanged: (v) { setState(() => _sensitivity = v); _triggerSensitivityShow(); }),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const Divider(color: Colors.white10),
          const SizedBox(height: 12),
          _buildCheatSheet(),
        ],
      ),
    );
  }

  Widget _buildCheatSheet() {
    final items = [('1 finger', 'Move'), ('2 finger', 'Scroll'), ('2 tap', 'Right click'), ('3 swipe', 'Exposé'), ('4 swipe', 'Spaces')];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Text(item.$1, style: const TextStyle(fontSize: 9, color: Colors.white24)), const Spacer(), Text(item.$2, style: const TextStyle(fontSize: 9, color: Colors.white38))]),
      )).toList(),
    );
  }
}
