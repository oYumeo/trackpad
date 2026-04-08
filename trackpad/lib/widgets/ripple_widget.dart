import 'package:flutter/material.dart';

class RippleEffect {
  final Offset position;
  final int createdAt = DateTime.now().millisecondsSinceEpoch;
  RippleEffect({required this.position});
}

class RippleWidget extends StatefulWidget {
  final RippleEffect effect;
  const RippleWidget({super.key, required this.effect});

  @override
  State<RippleWidget> createState() => _RippleWidgetState();
}

class _RippleWidgetState extends State<RippleWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween<double>(begin: 0.2, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween<double>(begin: 0.4, end: 0.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.scale(
        scale: _scale.value,
        child: Opacity(
          opacity: _opacity.value,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue.withOpacity(0.6), width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}
