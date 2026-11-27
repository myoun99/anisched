import 'dart:async';

import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../models/progress.dart';
import '../models/work_interval.dart';
import 'format.dart';
import 'theme.dart';

/// The running work timer: which cut, how long, and pause / resume. Its
/// space is always there; with nothing running it shows a dash.
class TimerCard extends StatefulWidget {
  const TimerCard({
    super.key,
    required this.running,
    required this.task,
    required this.group,
    required this.onStop,
    required this.onResume,
    this.clock = systemClock,
    this.large = true,
  });

  /// The open interval, if a timer runs.
  final WorkInterval? running;

  /// The task the timer runs on, or last ran on (for resume).
  final TaskRow? task;
  final PartGroup? group;
  final VoidCallback onStop;
  final VoidCallback onResume;
  final Clock clock;

  /// Big digits (wide screens) or a compact clock.
  final bool large;

  @override
  State<TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<TimerCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TimerCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.running == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) =>
      '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    final r = widget.running;
    final t = widget.task;
    final g = widget.group;
    final elapsed = r?.elapsed(widget.clock()) ?? Duration.zero;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Row(
              spacing: 10,
              children: [
                Text(
                  t == null ? '—' : taskLabel(t),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (g != null)
                  Flexible(
                    child: Text(
                      '${groupTitle(g)} ${g.stageName}',
                      style: TextStyle(color: c.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            Text(
              _clock(elapsed),
              key: const Key('timer-clock'),
              style: TextStyle(
                fontSize: widget.large ? 64 : 44,
                fontWeight: FontWeight.w700,
                height: 1,
                color: r == null ? c.muted : ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(
              height: 44,
              child: r != null
                  ? FilledButton(
                      key: const Key('timer-stop'),
                      onPressed: widget.onStop,
                      child: const Text('정지'),
                    )
                  : OutlinedButton(
                      key: const Key('timer-resume'),
                      onPressed: t == null ? null : widget.onResume,
                      child: const Text('다시 시작'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
