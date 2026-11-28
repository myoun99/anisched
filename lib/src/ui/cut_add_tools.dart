import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/registration.dart';
import 'instant.dart';
import 'text/strings.dart';
import 'theme.dart';

/// The tools that fill a list of new cuts ([draft]), each a pill from the
/// left: [↔ C __ ~ C __ 추가] a range, [✎ C __ 추가] one by name (12A,
/// BANK). After an
/// add its fields empty and the first takes the focus again. The register
/// screen and a card's 「+」 use this one.
class CutAddTools extends StatefulWidget {
  const CutAddTools({
    super.key,
    required this.draft,
    required this.onChanged,
    this.first,
  });

  final CutDraft draft;

  /// After cuts were added.
  final VoidCallback onChanged;

  /// The first cut the range field starts with (the next free number).
  final int? first;

  @override
  State<CutAddTools> createState() => _CutAddToolsState();
}

class _CutAddToolsState extends State<CutAddTools> {
  late final _first = TextEditingController(text: '${widget.first ?? ''}');
  final _last = TextEditingController();
  final _name = TextEditingController();
  final _firstFocus = FocusNode();
  final _nameFocus = FocusNode();

  int? get _a => int.tryParse(_first.text.trim());
  int? get _b => int.tryParse(_last.text.trim());

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _name.dispose();
    _firstFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// After an add the fields empty. From the button the focus goes (a
  /// phone's keyboard closes); from Enter it stays on the first field, to
  /// type the next one (유저 2026-11-28).
  void _after({required bool enter, required FocusNode first}) {
    if (enter) {
      first.requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    widget.onChanged();
  }

  void _addRange({bool enter = false}) {
    final a = _a;
    final b = _b ?? a;
    if (a == null || b == null) return;
    widget.draft.addRange(a, b);
    setState(() {
      _first.clear();
      _last.clear();
    });
    _after(enter: enter, first: _firstFocus);
  }

  void _addOne({bool enter = false}) {
    if (!widget.draft.add(_name.text)) return;
    setState(_name.clear);
    _after(enter: enter, first: _nameFocus);
  }

  Widget _field(
    Key key,
    TextEditingController ctl, {
    required double width,
    FocusNode? focus,
    VoidCallback? onSubmit,
    bool digits = true,
    String? hint,
  }) => PillField(
    fieldKey: key,
    controller: ctl,
    width: width,
    prefix: widget.draft.prefix,
    focus: focus,
    digits: digits,
    hint: hint,
    onChanged: (_) => setState(() {}),
    onSubmit: onSubmit,
  );

  static final _compact = FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    minimumSize: const Size(0, 36),
    shape: const StadiumBorder(),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final a = _a;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        // [ ↔  C __ ~ C __  추가 ]: a range of cuts.
        CutToolPill(
          key: const Key('cut-range-pill'),
          icon: Icons.linear_scale,
          children: [
            _field(
              const Key('reg-first'),
              _first,
              width: 44,
              focus: _firstFocus,
              onSubmit: () => _addRange(enter: true),
            ),
            Text('~', style: TextStyle(color: c.muted)),
            _field(
              const Key('reg-last'),
              _last,
              width: 44,
              onSubmit: () => _addRange(enter: true),
            ),
            FilledButton.tonal(
              key: const Key('cut-add-range'),
              style: _compact,
              onPressed: a == null ? null : _addRange,
              child: Text(S.add.t),
            ),
          ],
        ),
        // [ ✎  C __  추가 ]: one cut by name.
        CutToolPill(
          key: const Key('cut-name-pill'),
          icon: Icons.edit_outlined,
          children: [
            _field(
              const Key('cut-add-name'),
              _name,
              width: 64,
              focus: _nameFocus,
              onSubmit: () => _addOne(enter: true),
              digits: false,
              hint: '12A',
            ),
            FilledButton.tonal(
              key: const Key('cut-add-one'),
              style: _compact,
              onPressed: _name.text.trim().isEmpty ? null : _addOne,
              child: Text(S.add.t),
            ),
          ],
        ),
      ],
    );
  }
}

/// One tool in a rounded outline: a small icon saying what it is (no
/// words), then its fields and its button.
class CutToolPill extends StatelessWidget {
  const CutToolPill({super.key, required this.icon, required this.children});

  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 3, 3, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Icon(icon, size: 18, color: c.muted),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A field inside a [CutToolPill]: no box of its own (the pill is the
/// box), [prefix] before it, always shown. The register's cut fields and
/// the settings' digit counts use this one.
class PillField extends StatelessWidget {
  const PillField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.width,
    this.prefix = '',
    this.focus,
    this.digits = true,
    this.hint,
    this.onChanged,
    this.onSubmit,
    this.maxLength,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final double width;
  final String prefix;
  final FocusNode? focus;

  /// Digits only, with a number keyboard.
  final bool digits;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const bare = InputBorder.none;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix.isNotEmpty) Text(prefix, style: TextStyle(color: c.faint)),
        SizedBox(
          width: width,
          child: TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focus,
            onTapOutside: unfocusOutside,
            keyboardType: digits ? TextInputType.number : null,
            inputFormatters: [
              if (digits) FilteringTextInputFormatter.digitsOnly,
              if (maxLength != null)
                LengthLimitingTextInputFormatter(maxLength),
            ],
            onChanged: onChanged,
            onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: bare,
              enabledBorder: bare,
              focusedBorder: bare,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 2,
                vertical: 8,
              ),
              hintText: hint,
              hintStyle: TextStyle(color: c.faint),
            ),
          ),
        ),
      ],
    );
  }
}
