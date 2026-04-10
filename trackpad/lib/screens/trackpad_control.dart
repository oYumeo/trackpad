import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/ripple_widget.dart';
import '../widgets/grid_painter.dart';

class TrackpadControl extends StatefulWidget {
  final String ip;
  final bool isUsbMode, isP2PMode;

  const TrackpadControl({
    super.key,
    required this.ip,
    this.isUsbMode = false,
    this.isP2PMode = false,
  });

  @override
  State<TrackpadControl> createState() => _TrackpadControlState();
}

class _TrackpadControlState extends State<TrackpadControl> with TickerProviderStateMixin {
  // Network & Connection
  RawDatagramSocket? _udp;
  Socket? _tcp;
  ServerSocket? _iosServer;
  bool _connected = false, _connecting = true;

  // Gesture State
  bool _isDragging = false, _wasScrolling = false;
  bool _isAltTab = false, _is3FingerTriggered = false;
  bool _isDoubleTapDrag = false, _isHoldDrag = false, _sentDragDown = false;
  bool _selectionMode = false, _isMacMode = true;

  // Values
  double _sensitivity = 4.0, _totalScroll = 0, _dragX = 0, _totalDragY = 0;
  int _maxPointers = 0, _lastTapTime = 0, _lastClickTime = 0, _clickCount = 1;
  Offset _lastFocal = Offset.zero, _tapPos = Offset.zero, _scrollVel = Offset.zero;

  // Resources
  final Map<int, Offset> _pointers = {};
  final Map<int, int> _pointerTimes = {};
  final List<RippleEffect> _ripples = [];
  Timer? _longPressT, _labelT, _inertiaT;
  String _label = '';

  bool get _isWifi => !widget.isUsbMode && !widget.isP2PMode;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _connect();
  }

  // --- Network Logic ---

  void _connect() async {
    setState(() => _connecting = true);
    try {
      if (widget.isP2PMode) {
        setState(() => _connected = true);
        _showLabel("ADB P2P Active");
      } else if (widget.isUsbMode) {
        if (Platform.isIOS) {
          _iosServer = await ServerSocket.bind(InternetAddress.anyIPv4, 50010);
          _showLabel("iOS USB: Waiting...");
          _iosServer!.listen((s) {
            setState(() {
              _tcp = s;
              _connected = true;
              _connecting = false;
            });
            HapticFeedback.heavyImpact();
          });
        } else {
          _tcp = await Socket.connect(widget.ip == "localhost" ? "127.0.0.1" : widget.ip, 50010, timeout: const Duration(seconds: 5));
          _tcp!.setOption(SocketOption.tcpNoDelay, true);
          setState(() => _connected = true);
        }
      } else {
        _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        setState(() => _connected = true);
      }
      if (_connected) {
        _connecting = false;
        HapticFeedback.mediumImpact();
        if (!widget.isP2PMode) _showLabel(widget.isUsbMode ? "USB Active" : "WiFi Active");
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _send(Map<String, dynamic> d) {
    if (!_connected) return;
    final m = "${jsonEncode(d)}\n";
    if (widget.isP2PMode) {
      debugPrint("TP:$m");
    } else if (widget.isUsbMode) {
      _tcp?.write(m);
    } else {
      _udp?.send(utf8.encode(m), InternetAddress(widget.ip), 50005);
    }
  }

  // --- Interaction Helpers ---

  void _showLabel(String l) {
    _labelT?.cancel();
    setState(() => _label = l);
    _labelT = Timer(const Duration(milliseconds: 1500), () => mounted ? setState(() => _label = '') : null);
  }

  void _move(Offset delta, {int? count}) {
    if (delta == Offset.zero) return;
    final type = (_selectionMode || _isDoubleTapDrag || _isHoldDrag) ? 'drag' : 'move';
    _send({
      'type': type,
      'dx': delta.dx * _sensitivity,
      'dy': delta.dy * _sensitivity,
      if (count != null) 'clickCount': count
    });
  }

  void _scroll(Offset delta) {
    if (delta == Offset.zero) return;
    _wasScrolling = true;
    _totalScroll += delta.distance;
    _scrollVel = delta;
    _send({'type': 'scroll', 'dx': delta.dx * -5, 'dy': delta.dy * -6});
  }

  void _tap(Size size) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _clickCount = (now - _lastClickTime < 400) ? _clickCount + 1 : 1;
    _lastClickTime = now;

    final isR = _tapPos.dx > size.width * 0.75 && _tapPos.dy > size.height * 0.75;

    if (_maxPointers == 2) {
      if (_totalScroll < 5 && (now - _lastTapTime) < 100 && !_wasScrolling) {
        _click('right');
      }
    } else if (_maxPointers == 1) {
      _click(isR ? 'right' : 'left');
    }
  }

  void _click(String b) {
    b == 'left' ? HapticFeedback.lightImpact() : HapticFeedback.mediumImpact();
    _send({'type': 'click', 'button': b, 'clickCount': _clickCount});
    _showLabel("${b == 'left' ? '' : 'Right '}${_clickCount > 1 ? 'Double ' : ''}Click");
  }

  void _startInertia() {
    _inertiaT?.cancel();
    _inertiaT = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (_scrollVel.distance < 0.5) {
        t.cancel();
        return;
      }
      _send({'type': 'scroll', 'dx': _scrollVel.dx * 2, 'dy': _scrollVel.dy * 2});
      _scrollVel *= 0.92;
    });
  }

  @override
  void dispose() {
    _udp?.close();
    _tcp?.destroy();
    _iosServer?.close();
    _inertiaT?.cancel();
    _labelT?.cancel();
    _longPressT?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  // --- UI Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Row(
            children: [
              Expanded(child: LayoutBuilder(builder: (_, c) => _buildTrackpad(Size(c.maxWidth, c.maxHeight)))),
              _buildRightPanel(),
            ],
          ),
          _buildStatusBar(),
          if (_label.isNotEmpty) _buildGestureLabel(),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final color = widget.isP2PMode
        ? Colors.orange
        : (_connecting
            ? Colors.orange
            : (_connected ? (widget.isUsbMode ? Colors.green : Colors.blue) : Colors.red));

    return Positioned(
      top: 0,
      left: 0,
      right: 0, // Full width to avoid flex confusion
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 16, right: 160), // Room for side panel
        child: Row(
          children: [
            _statusCircle(color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isP2PMode
                    ? 'ADB P2P'
                    : (_connecting ? 'Connecting...' : '${widget.isUsbMode ? "USB" : "WiFi"}: ${widget.ip}'),
                style: const TextStyle(fontSize: 11, color: Colors.white54),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _btn(
              active: _selectionMode,
              icon: _selectionMode ? Icons.select_all : Icons.deselect,
              label: _selectionMode ? 'Selecting' : 'Select',
              onTap: () {
                setState(() {
                  _selectionMode = !_selectionMode;
                  _send({'type': _selectionMode ? 'mouseDown' : 'mouseUp', 'button': 'left'});
                  HapticFeedback.mediumImpact();
                });
              },
            ),
            const SizedBox(width: 8),
            _btn(
              active: false,
              icon: _isMacMode ? Icons.laptop_mac : Icons.laptop_windows,
              label: _isMacMode ? 'MAC' : 'WIN',
              onTap: () {
                setState(() {
                  _isMacMode = !_isMacMode;
                  _showLabel("${_isMacMode ? 'Mac' : 'Win'} Mode");
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.white38),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCircle(Color color) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
        ),
      );

  Widget _btn({required bool active, required IconData icon, required String label, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? Colors.blue.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: active ? Colors.blue : Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: active ? Colors.blue : Colors.white54),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: active ? Colors.blue : Colors.white54)),
            ],
          ),
        ),
      );

  Widget _buildTrackpad(Size size) => Listener(
        onPointerDown: (e) {
          if (_pointers.length >= 4) return;
          _inertiaT?.cancel();
          _tapPos = e.localPosition;
          setState(() {
            _is3FingerTriggered = false;
            if (_pointers.isEmpty) {
              _maxPointers = 0;
              _isDragging = false;
              _totalScroll = 0;
            }
            _pointers[e.pointer] = e.localPosition;
            _pointerTimes[e.pointer] = DateTime.now().millisecondsSinceEpoch;
            if (_pointers.length > _maxPointers) _maxPointers = _pointers.length;

            // Alt-Tab logic
            if (_pointers.length == 4 && !_isAltTab) {
              _isAltTab = true;
              _send({'type': 'keyDown', 'key': 0x12});
              _send({'type': 'keyTap', 'key': 0x09});
              HapticFeedback.heavyImpact();
            }

            // Long press detection
            if (_pointers.length == 1) {
              _longPressT = Timer(const Duration(milliseconds: 250), () {
                if (mounted && _pointers.length == 1 && !_isDragging) {
                  setState(() {
                    _isHoldDrag = true;
                    _send({'type': 'mouseDown', 'button': 'left'});
                    _sentDragDown = true;
                    HapticFeedback.heavyImpact();
                  });
                }
              });
            }

            // Double tap drag detection
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastTapTime < 250 && _pointers.length == 1) {
              _isDoubleTapDrag = true;
              _sentDragDown = false; // Wait for movement to send mouseDown
            }
            _lastTapTime = now;

            _ripples.add(RippleEffect(position: e.localPosition));
            if (_ripples.length > 5) _ripples.removeAt(0);
          });
        },
        onPointerMove: (e) {
          if (!_pointers.containsKey(e.pointer)) return;
          if (!_isHoldDrag && (e.localPosition - _tapPos).distance > 20) _longPressT?.cancel();

          final pCount = _pointers.length;
          final delta = e.delta;

          // USB/P2P uses high Hz tracking
          if (!_isWifi && delta != Offset.zero) {
            if (pCount == 1) {
              if ((e.localPosition - _tapPos).distance > 12) {
                _isDragging = true;
                if (_isDoubleTapDrag && !_sentDragDown) {
                  _send({'type': 'mouseDown', 'button': 'left', 'clickCount': 2});
                  _sentDragDown = true;
                  HapticFeedback.heavyImpact();
                }
              }
              _move(delta, count: _isDoubleTapDrag ? 2 : null);
            } else if (pCount == 2) {
              _scroll(delta / 2);
            }
          }
          setState(() => _pointers[e.pointer] = e.localPosition);
        },
        onPointerUp: (e) {
          if (!_pointers.containsKey(e.pointer)) return;
          _longPressT?.cancel();
          final dur = DateTime.now().millisecondsSinceEpoch - (_pointerTimes[e.pointer] ?? 0);

          setState(() {
            if (_isAltTab && _pointers.length < 4) {
              _send({'type': 'keyUp', 'key': 0x12});
              _isAltTab = false;
            }
            _pointers.remove(e.pointer);
            if (_pointers.isEmpty) {
              if (_isHoldDrag || (_isDoubleTapDrag && _sentDragDown)) {
                _send({'type': 'mouseUp', 'button': 'left'});
              } else if (!_isDragging && !_selectionMode && _maxPointers <= 2 && dur < 300) {
                _tap(size);
              }
              _isHoldDrag = _isDoubleTapDrag = _sentDragDown = false;
            }
          });
          _wasScrolling = false;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            _lastFocal = d.focalPoint;
            _isDragging = false;
            _scrollVel = Offset.zero;
            _totalScroll = _dragX = _totalDragY = 0;
            _inertiaT?.cancel();
          },
          onScaleUpdate: (d) {
            final delta = d.focalPoint - _lastFocal;
            _lastFocal = d.focalPoint;
            if (delta.distance > 200) return;
            final p = d.pointerCount;

            // WiFi uses normal frequency tracking via GestureDetector
            if (_isWifi) {
              if (p == 1) {
                if (delta.distance > 0.5) _isDragging = true;
                if (_isDoubleTapDrag && !_sentDragDown && _isDragging) {
                  _send({'type': 'mouseDown', 'button': 'left', 'clickCount': 2});
                  _sentDragDown = true;
                }
                _move(delta, count: _isDoubleTapDrag ? 2 : null);
              } else if (p == 2) {
                _scroll(delta);
              }
            }

            if (p >= 2 && delta.distance > 1.0) _isDragging = true;
            if (p == (_isMacMode ? 3 : 4)) {
              _swipeWorkspace(delta);
            } else if (p == (_isMacMode ? 4 : 3)) {
              _swipeArrow(delta);
            }
          },
          onScaleEnd: (d) {
            if (_pointers.isEmpty && _maxPointers == 2 && _isDragging) _startInertia();
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 44, 10, 20),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _selectionMode ? Colors.blue : Colors.blue.withValues(alpha: 0.18),
                width: _selectionMode ? 2 : 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28.5),
              child: Stack(
                children: [
                  CustomPaint(painter: GridPainter(), size: Size.infinite),
                  ..._ripples.map((r) => Positioned(left: r.position.dx - 120, top: r.position.dy - 120, child: RippleWidget(effect: r))),
                  ..._pointers.values.map((p) => Positioned(
                        left: p.dx - 80,
                        top: p.dy - 80,
                        child: Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [Colors.blue.withValues(alpha: 0.15), Colors.transparent],
                            ),
                          ),
                        ),
                      )),
                  Center(
                    child: AnimatedOpacity(
                      opacity: _pointers.isEmpty ? 0.07 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_selectionMode ? Icons.select_all : Icons.touch_app_outlined, size: 40, color: Colors.white),
                          const SizedBox(height: 8),
                          Text(
                            _selectionMode ? 'SELECTING' : 'TRACKPAD',
                            style: const TextStyle(letterSpacing: 4, fontSize: 10, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _swipeWorkspace(Offset d) {
    _dragX += d.dx;
    _totalDragY += d.dy;
    if (_dragX.abs() > 50) {
      _send({'type': 'workspace', 'action': 'switch', 'direction': _dragX > 0 ? 'right' : 'left'});
      HapticFeedback.mediumImpact();
      _dragX = 0;
    }
    if (_totalDragY.abs() > 80 && !_is3FingerTriggered) {
      _send({'type': 'workspace', 'action': 'switch', 'direction': _totalDragY > 0 ? 'down' : 'up'});
      HapticFeedback.heavyImpact();
      _is3FingerTriggered = true;
      _totalDragY = 0;
    }
  }

  void _swipeArrow(Offset d) {
    _dragX += d.dx;
    _totalDragY += d.dy;
    if (_dragX.abs() > 8) {
      _send({'type': 'keyTap', 'key': _dragX > 0 ? 0x27 : 0x25});
      HapticFeedback.selectionClick();
      _dragX = 0;
    }
    if (_totalDragY.abs() > 8) {
      _send({'type': 'keyTap', 'key': _totalDragY > 0 ? 0x28 : 0x26});
      HapticFeedback.selectionClick();
      _totalDragY = 0;
    }
  }

  Widget _buildRightPanel() => Container(
        width: 150,
        padding: const EdgeInsets.only(top: 44, bottom: 20, right: 16),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.zoom_out_map, size: 18, color: Colors.white38),
                    onPressed: () => _send({'type': 'zoom'}),
                  ),
                  const Text('SPEED', style: TextStyle(fontSize: 10, color: Colors.white24)),
                  Text('${_sensitivity.toStringAsFixed(1)}x',
                      style: const TextStyle(color: Colors.blue, fontSize: 20, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: _sensitivity,
                        min: 0.5,
                        max: 6.0,
                        onChanged: (v) => setState(() => _sensitivity = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),
            ...[
              ('1 finger', 'Move'),
              ('2 finger', 'Scroll'),
              ('2 tap', 'Right click'),
              (_isMacMode ? '3 swipe' : '4 swipe', 'Exposé'),
            ].map((i) => _cheatRow(i.$1, i.$2)),
          ],
        ),
      );

  Widget _cheatRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(k, style: const TextStyle(fontSize: 9, color: Colors.white24)),
            const Spacer(),
            Text(v, style: const TextStyle(fontSize: 9, color: Colors.white38)),
          ],
        ),
      );

  Widget _buildGestureLabel() => Positioned(
        bottom: 40,
        left: 0,
        right: 160,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(_label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ),
      );
}
