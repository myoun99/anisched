import 'dart:async';

import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../models/progress.dart';
import '../models/work_interval.dart';
import 'format.dart';
import 'theme.dart';

/// The work timer along the bottom of every view: which cut, how long,
/// and stop / resume. Its space is always there.
class TimerBar extends StatefulWidget {
  const TimerBar({
    super.key,
    required this.running,
    required this.task,
    required this.group,
    this.onStop,
    this.onResume,
    this.clock = systemClock,
  });

  /// The open interval, if a timer runs.
  final WorkInterval? running;

  /// The task the timer runs on, or last ran on (for resume).
  final TaskRow? task;
  final PartGroup? group;
  final VoidCallback? onStop;
  final VoidCallback? onResume;
  final Clock clock;

  @override
  State<TimerBar> createState() => _TimerBarState();
}

class _TimerBarState extends State<TimerBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TimerBar old) {
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
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: t == null ? '—' : taskLabel(t),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    children: [
                      if (g != null)
                        TextSpan(
                          text:
                              '  ${g.workTitle} ${g.episodeNumber} · '
                              '${g.stageName}',
                          style: TextStyle(
                            fontWeight: FontWeight.normal,
                            color: c.muted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _clock(elapsed),
                key: const Key('timer-clock'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: r == null ? c.muted : ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(
                width: 104,
                height: 36,
                child: r != null
                    ? FilledButton(
                        key: const Key('timer-stop'),
                        onPressed: widget.onStop,
                        style: const ButtonStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.zero),
                        ),
                        child: const Text('정지', maxLines: 1, softWrap: false),
                      )
                    : OutlinedButton(
                        key: const Key('timer-resume'),
                        onPressed: t == null ? null : widget.onResume,
                        style: const ButtonStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.zero),
                        ),
                        child: const Text(
                          '다시 시작',
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
