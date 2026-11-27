/// How much room a screen gives the layout, decided by its width alone.
///
/// The thresholds were agreed with the user on 2026-11-27: wide from 1100
/// logical pixels (desktop, tablet landscape), medium from 700 (tablet
/// portrait, phone landscape), narrow below that (phone portrait).
enum SizeClass {
  narrow,
  medium,
  wide;

  /// Smallest width that counts as [medium].
  static const double mediumMin = 700;

  /// Smallest width that counts as [wide].
  static const double wideMin = 1100;

  static SizeClass ofWidth(double width) {
    if (width >= wideMin) return SizeClass.wide;
    if (width >= mediumMin) return SizeClass.medium;
    return SizeClass.narrow;
  }
}

/// A screen's size class together with its orientation, which decides
/// where side panels go when the width alone leaves a choice.
class ScreenLayout {
  const ScreenLayout({required this.size, required this.landscape});

  factory ScreenLayout.of(double width, double height) =>
      ScreenLayout(size: SizeClass.ofWidth(width), landscape: width > height);

  final SizeClass size;
  final bool landscape;

  /// A detail panel sits beside the content on wide screens and on medium
  /// screens held sideways; otherwise it goes below.
  bool get detailBeside =>
      size == SizeClass.wide || (size == SizeClass.medium && landscape);

  @override
  bool operator ==(Object other) =>
      other is ScreenLayout &&
      other.size == size &&
      other.landscape == landscape;

  @override
  int get hashCode => Object.hash(size, landscape);

  @override
  String toString() => 'ScreenLayout($size, landscape: $landscape)';
}
