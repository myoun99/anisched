/// The charts of the timeline and the work tab — one board for both, in
/// parts by subject: the days shown ([ChartWindow], chart_window), moving
/// them (chart_controls), what the days look like (chart_days), the board
/// and its layers (chart_board), a bar (chart_bar) and the month view
/// (chart_month).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/size_class.dart';
import '../../models/progress.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text/strings.dart';
import '../fit_text.dart';
import '../palette.dart';

part 'chart_window.dart';
part 'chart_controls.dart';
part 'chart_days.dart';
part 'chart_board.dart';
part 'chart_bar.dart';
part 'chart_month.dart';

/// Local calendar day as a UTC midnight, so day differences are exact.
DateTime chartDay(DateTime t) {
  final l = t.isUtc ? t.toLocal() : t;
  return DateTime.utc(l.year, l.month, l.day);
}

/// Paint counts per chart layer, for tests that pin which layer redraws.
@visibleForTesting
abstract final class ChartPaints {
  static int background = 0;
  static int today = 0;
  static int preview = 0;
  static int barBuilds = 0;

  static void reset() => background = today = preview = barBuilds = 0;
}
