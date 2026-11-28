import 'dart:async';

import 'package:flutter/material.dart';

import '../core/clock.dart';
import '../models/progress.dart';
import '../models/catalogue.dart';
import 'fit_text.dart';
import 'format.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'theme.dart';

/// The work-time log along the bottom of every view: which cut (its name,
/// title and episode each a button that opens the centred picker), the
/// time recorded on it so far (all sessions added up), one start / pause
/// toggle and the finish button — 완료, then 제출 (a long press steps back).
/// A long press on the bar edits the recorded time by hand. Its space is
/// always there.
class TimerBar extends StatefulWidget {
  const TimerBar({
    super.key,
    required this.running,
    required this.task,
    required this.group,
    this.worked,
    this.onToggle,
    this.clock = systemClock,
    this.onPickCut,
    this.onPickWork,
    this.onPickEpisode,
    this.onPickStage,
    this.onStatus,
    this.onEditTime,
  });

  /// The time bar's pickers: another cut of the same episode, another
  /// title, another episode of the title.
  final VoidCallback? onPickCut;
  final VoidCallback? onPickWork;
  final VoidCallback? onPickEpisode;

  /// Another stage of the same cuts.
  final VoidCallback? onPickStage;

  /// Moves [task] on: done, submitted, or back.
  final ValueChanged<TaskStatus>? onStatus;

  /// Opens the stretches of [task] to fix by hand (a timer left on
  /// overnight).
  final VoidCallback? onEditTime;

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

  /// 00:00:00 — hours in two digits too: some cuts take many hours.
  static String _clock(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:'
      '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  /// The finish button's next step: 제출 (2026-11-28 유저: 완료와 제출 합침).
  static TaskStatus? _next(TaskStatus s) =>
      s == TaskStatus.submitted ? null : TaskStatus.submitted;

  Future<void> _stepBack(BuildContext context, TaskStatus s) async {
    final on = widget.onStatus;
    if (on == null) return;
    final box = context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero) & box.size;
    final back = <(TaskStatus, String)>[
      if (s == TaskStatus.submitted) (TaskStatus.inProgress, S.backToWork.t),
    ];
    if (back.isEmpty) return;
    final picked = await showMenu<TaskStatus>(
      context: context,
      popUpAnimationStyle: instant,
      position: RelativeRect.fromLTRB(at.left, at.top - 8, at.right, at.top),
      items: [
        for (final (st, label) in back)
          PopupMenuItem(
            key: Key('timer-back-${st.dbName}'),
            value: st,
            child: Text(label),
          ),
      ],
    );
    if (picked != null) on(picked);
  }

  /// A plain text button for the bar's names.
  Widget _name(
    String key,
    String text,
    VoidCallback? onTap, {
    TextStyle? style,
  }) => InkWell(
    key: Key(key),
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: FitText(text, style: style),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = widget.task;
    final g = widget.group;
    final run = widget.running;
    // A phone: the stage goes, the clock and the finish button shrink.
    final narrow = MediaQuery.sizeOf(context).width < 500;
    final worked = t == null
        ? Duration.zero
        : (widget.worked?.call() ?? Duration.zero);
    return GestureDetector(
      key: const Key('timer-bar'),
      onLongPress: t == null ? null : widget.onEditTime,
      child: DecoratedBox(
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
                  child: Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: _name(
                          'timer-cut',
                          t == null ? '—' : taskLabel(t),
                          // Empty, the name slot picks the first cut.
                          widget.onPickCut,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (g != null) ...[
                        Flexible(
                          flex: 4,
                          child: _name(
                            'timer-work',
                            g.workTitle,
                            widget.onPickWork,
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ),
                        Flexible(
                          flex: 2,
                          child: _name(
                            'timer-episode',
                            g.episodeNumber,
                            widget.onPickEpisode,
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ),
                        Flexible(
                          flex: 2,
                          child: _name(
                            'timer-stage',
                            stageText(g.stageName),
                            widget.onPickStage,
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  _clock(worked),
                  key: const Key('timer-clock'),
                  style: TextStyle(
                    fontSize: narrow ? 16 : 20,
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
                      foregroundColor: run
                          ? scheme.onPrimary
                          : scheme.onSurface,
                      side: run ? null : BorderSide(color: c.line),
                    ),
                    onPressed: t == null ? null : widget.onToggle,
                    icon: Icon(
                      run ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 22,
                    ),
                  ),
                ),
                if (t != null && widget.onStatus != null)
                  Builder(
                    builder: (context) {
                      final next = _next(t.status);
                      return GestureDetector(
                        onLongPress: () => _stepBack(context, t.status),
                        child: OutlinedButton.icon(
                          key: const Key('timer-finish'),
                          onPressed: next == null
                              ? null
                              : () => widget.onStatus!(next),
                          icon: Icon(
                            next == TaskStatus.submitted
                                ? Icons.send_outlined
                                : Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: narrow
                              ? const SizedBox.shrink()
                              : Text(
                                  next == TaskStatus.submitted || next == null
                                      ? S.stSubmitted.t
                                      : S.stDone.t,
                                ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
