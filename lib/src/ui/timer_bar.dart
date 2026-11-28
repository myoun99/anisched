import 'dart:async';

import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../models/progress.dart';
import 'format.dart';
import 'theme.dart';

/// The work-time log along the bottom of every view: which cut, the time
/// recorded on it so far (all sessions added up), and one start / pause
/// toggle. Its space is always there.
class TimerBar extends StatefulWidget {
  const TimerBar({
    super.key,
    required this.running,
    required this.task,
    required this.group,
    this.worked,
    this.onToggle,
    this.clock = systemClock,
  });

  /// Whether time is being recorded on [task] now.
  final bool running;

  /// The cut on the bar (picked last, or the one running).
  final TaskRow? task;
  final PartGroup? group;

  /// Time recorded on [task] as of now, a running interval included.
  final Duration Function()? worked;

  /// Starts or pauses recording on [task].
  final VoidCallback? onToggle;
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
    if (!widget.running) {
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
    final scheme = Theme.of(context).colorScheme;
    final t = widget.task;
    final g = widget.group;
    final run = widget.running;
    final worked = t == null
        ? Duration.zero
        : (widget.worked?.call() ?? Duration.zero);
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
                              '  ${g.workTitle} ${episodeLabel(g.episodeNumber)} · '
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
                _clock(worked),
                key: const Key('timer-clock'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: run ? scheme.onSurface : c.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox.square(
                dimension: 40,
                child: IconButton.filled(
                  key: const Key('timer-toggle'),
                  tooltip: '',
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: run ? scheme.primary : c.panelAlt,
                    foregroundColor: run ? scheme.onPrimary : scheme.onSurface,
                    side: run ? null : BorderSide(color: c.line),
                  ),
                  onPressed: t == null ? null : widget.onToggle,
                  icon: Icon(
                    run ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 22,
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
