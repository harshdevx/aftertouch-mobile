import 'package:flutter/widgets.dart';

import '../app_ink.dart';

/// Online = filled ink dot. Offline = hollow ring. Always paired with a text
/// label at the call site (never colour/shape alone) — see UX spec §5.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.online, this.size = 8});

  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = context.ink;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? ink.ink900 : null,
        border: online ? null : Border.all(color: ink.ink300, width: 1.5),
      ),
    );
  }
}
