import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../controllers/registration.dart';
import '../../core/size_class.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets.dart';

/// Registering an episode's cuts: which work, the part (free text), the
/// stages (a role chip turns on its stages; each stage is a checkbox),
/// the first cut number and the count, and a grid where picked cells
/// (tap or drag across) become missing, split A/B or shared.
class RegisterView extends StatefulWidget {
  const RegisterView({
    super.key,
    required this.now,
    required this.layout,
    this.works = const {},
    this.clients = const {},
    this.roles = const [],
    this.onRegister,
  });

  final DateTime now;
  final ScreenLayout layout;

  /// Work titles by id.
  final Map<int, String> works;

  /// Client names by id.
  final Map<int, String> clients;

  /// Role presets: name and the stages it takes on.
  final List<({int id, String name, List<String> stages})> roles;

  /// Saves the draft; returns how many tasks were made. Null: read-only.
  final int Function(RegistrationDraft draft)? onRegister;

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

enum _Flow { inWork, newWork }

class _RegisterViewState extends State<RegisterView> {
  _Flow _flow = _Flow.inWork;
  int? _work;
  int? _client;
  final _title = TextEditingController();
  final _episode = TextEditingController(text: '#01');
  final _part = TextEditingController();
  final _start = TextEditingController(text: '1');
  final _count = TextEditingController(text: '100');
  final _stages = <String>{};
  CutDraft _cuts = CutDraft();
  final _picked = <String>{};
  late DateTime _kickoff = DateTime(
    widget.now.year,
    widget.now.month,
    widget.now.day,
  );
  DateTime? _due;
  String? _done;

  /// While dragging across the grid: true picks, false drops.
  bool? _paint;
  final _gridKey = GlobalKey();

  List<String> get _allStages =>
      {for (final r in widget.roles) ...r.stages}.toList();

  @override
  void initState() {
    super.initState();
    if (widget.roles.isNotEmpty) _stages.addAll(widget.roles.first.stages);
  }

  @override
  void didUpdateWidget(RegisterView old) {
    super.didUpdateWidget(old);
    if (_stages.isEmpty && old.roles.isEmpty && widget.roles.isNotEmpty) {
      _stages.addAll(widget.roles.first.stages);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _episode, _part, _start, _count]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setRun() {
    final start = int.tryParse(_start.text) ?? 1;
    final count = (int.tryParse(_count.text) ?? 1).clamp(1, 2000);
    setState(() {
      _cuts = CutDraft(start: start < 0 ? 0 : start, count: count)
        ..removed.addAll(_cuts.removed)
        ..splits.addAll(_cuts.splits)
        ..shared.addAll(_cuts.shared);
      _picked.removeWhere((n) => !_cuts.cells.contains(n));
    });
  }

  void _step(TextEditingController c, int by) {
    final v = (int.tryParse(c.text) ?? 0) + by;
    c.text = '${v < 1 ? 1 : v}';
    _setRun();
  }

  String? _cellAt(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(global));
    for (final e in result.path) {
      final t = e.target;
      if (t is RenderMetaData && t.metaData is String) {
        return t.metaData as String;
      }
    }
    return null;
  }

  void _paintAt(Offset global, {bool start = false}) {
    final n = _cellAt(global);
    if (n == null) return;
    setState(() {
      if (start) _paint = !_picked.contains(n);
      if (_paint == true) {
        _picked.add(n);
      } else if (_paint == false) {
        _picked.remove(n);
      }
    });
  }

  bool get _ready =>
      widget.onRegister != null &&
      _stages.isNotEmpty &&
      _cuts.total > 0 &&
      _episode.text.trim().isNotEmpty &&
      (_flow == _Flow.newWork ? _title.text.trim().isNotEmpty : _work != null);

  void _register() {
    final cb = widget.onRegister;
    if (cb == null || !_ready) return;
    final n = cb(
      RegistrationDraft(
        workId: _flow == _Flow.inWork ? _work : null,
        newWorkTitle: _flow == _Flow.newWork ? _title.text : null,
        clientId: _flow == _Flow.newWork ? _client : null,
        episodeNumber: _episode.text.trim(),
        partLabel: _part.text,
        stages: [
          for (final s in _allStages)
            if (_stages.contains(s)) s,
          for (final s in _stages)
            if (!_allStages.contains(s)) s,
        ],
        cuts: _cuts,
        kickoffAt: _kickoff,
        dueAt: _due == null
            ? null
            : DateTime(_due!.year, _due!.month, _due!.day, 23, 59),
      ),
    );
    setState(() {
      _done = '$n건 등록';
      _picked.clear();
      _cuts = CutDraft(start: _cuts.start, count: _cuts.count);
    });
  }

  Future<void> _pickDate(bool due) async {
    final first = DateTime(widget.now.year - 1);
    final last = DateTime(widget.now.year + 2);
    final d = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: due ? (_due ?? _kickoff) : _kickoff,
    );
    if (d == null || !mounted) return;
    setState(() => due ? _due = d : _kickoff = d);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final picked = _picked.toList()..sort();
    return ColoredBox(
      color: c.panel,
      child: Listener(
        onPointerUp: (_) => _paint = null,
        onPointerCancel: (_) => _paint = null,
        child: OwnScroll(
          builder: (controller) => Scrollbar(
            controller: controller,
            child: CustomScrollView(
              key: _gridKey,
              controller: controller,
              physics: _paint == null
                  ? null
                  : const NeverScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  sliver: SliverToBoxAdapter(child: _form(context)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  sliver: SliverToBoxAdapter(child: _summary(context, picked)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(14),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 72,
                          mainAxisExtent: 30,
                          mainAxisSpacing: 3,
                          crossAxisSpacing: 3,
                        ),
                    itemCount: _cuts.cells.length,
                    itemBuilder: _cell,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int i) {
    final c = AppColors.of(context);
    final n = _cuts.cells[i];
    final removed = _cuts.removed.contains(n);
    final split = _cuts.splits[n];
    final on = _picked.contains(n);
    final accent = Theme.of(context).colorScheme.primary;
    return MetaData(
      metaData: n,
      behavior: HitTestBehavior.opaque,
      child: Listener(
        onPointerDown: (e) {
          if (e.kind == PointerDeviceKind.mouse &&
              e.buttons != kPrimaryMouseButton) {
            return;
          }
          _paintAt(e.position, start: true);
        },
        onPointerMove: (e) {
          if (_paint != null) _paintAt(e.position);
        },
        child: DecoratedBox(
          key: Key('cell-$n'),
          decoration: BoxDecoration(
            color: on ? c.selected : (removed ? null : c.panel),
            border: Border.all(color: on ? c.selected : c.line),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text.rich(
              TextSpan(
                text: _cuts.label(n),
                children: [
                  if (split != null)
                    TextSpan(
                      text: ' ${'ABCDEFGH'.substring(0, split)}',
                      style: const TextStyle(fontSize: 9),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: removed ? c.faint : (split != null ? accent : null),
                fontWeight: split != null || _cuts.shared.containsKey(n)
                    ? FontWeight.w700
                    : null,
                decoration: removed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, List<String> picked) {
    final c = AppColors.of(context);
    final any = picked.isNotEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${_cuts.total} cut',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        Text('× ${_stages.length}', style: TextStyle(color: c.muted)),
        ToolbarButton(
          key: const Key('cut-remove'),
          label: '빼기',
          selected: false,
          onTap: any
              ? () => setState(() {
                  _cuts.toggleRemoved(picked);
                  _picked.clear();
                })
              : null,
        ),
        ToolbarButton(
          key: const Key('cut-split'),
          label: 'A/B',
          selected: false,
          onTap: any
              ? () => setState(() {
                  _cuts.toggleSplit(picked);
                  _picked.clear();
                })
              : null,
        ),
        ToolbarButton(
          key: const Key('cut-share'),
          label: '겸용',
          selected: false,
          onTap: _cuts.canShare(picked)
              ? () => setState(() {
                  _cuts.toggleShared(picked);
                  _picked.clear();
                })
              : null,
        ),
        ToolbarButton(
          key: const Key('cut-clear'),
          label: '해제',
          selected: false,
          onTap: any ? () => setState(_picked.clear) : null,
        ),
        FilledButton(
          key: const Key('register'),
          onPressed: _ready ? _register : null,
          child: const Text('등록'),
        ),
        SizedBox(
          width: 80,
          child: Text(_done ?? '', style: TextStyle(color: c.muted)),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final c = AppColors.of(context);
    InputDecoration deco(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    );
    Widget field(double width, Widget child) =>
        SizedBox(width: width, child: child);
    final wide = widget.layout.size != SizeClass.narrow;
    final fw = wide ? 200.0 : double.infinity;
    final sw = wide ? 120.0 : 150.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        SegmentGroup(
          children: [
            for (final f in _Flow.values)
              SegmentButton(
                key: Key('flow-${f.name}'),
                label: f == _Flow.inWork ? '작품 안에서' : '한 번에',
                selected: _flow == f,
                onTap: () => setState(() => _flow = f),
              ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (_flow == _Flow.inWork)
              field(
                wide ? 260 : double.infinity,
                DropdownButtonFormField<int>(
                  key: const Key('reg-work'),
                  initialValue: _work,
                  decoration: deco('작품'),
                  items: [
                    for (final e in widget.works.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _work = v),
                ),
              )
            else ...[
              field(
                fw,
                TextField(
                  key: const Key('reg-title'),
                  controller: _title,
                  decoration: deco('작품 이름'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              field(
                fw,
                DropdownButtonFormField<int?>(
                  initialValue: _client,
                  decoration: deco('회사'),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    for (final e in widget.clients.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _client = v),
                ),
              ),
            ],
            field(
              sw,
              TextField(
                key: const Key('reg-episode'),
                controller: _episode,
                decoration: deco('화수'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            field(
              sw,
              TextField(
                key: const Key('reg-part'),
                controller: _part,
                decoration: deco('파트'),
              ),
            ),
          ],
        ),
        Text('담당', style: TextStyle(fontSize: 12, color: c.muted)),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final r in widget.roles)
              ToolbarButton(
                key: Key('role-${r.name}'),
                label: r.name,
                selected:
                    _stages.length == r.stages.length &&
                    r.stages.every(_stages.contains),
                onTap: () => setState(
                  () => _stages
                    ..clear()
                    ..addAll(r.stages),
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            for (final s in _allStages)
              InkWell(
                key: Key('stage-$s'),
                onTap: () => setState(
                  () =>
                      _stages.contains(s) ? _stages.remove(s) : _stages.add(s),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _stages.contains(s),
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setState(
                        () => v == true ? _stages.add(s) : _stages.remove(s),
                      ),
                    ),
                    Text(s, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            _stepper('첫 컷', _cuts.number(_cuts.start), _start, 'reg-start'),
            _stepper(
              '컷 수',
              '~ ${_cuts.number(_cuts.start + _cuts.count - 1)}',
              _count,
              'reg-count',
            ),
            _dateButton('착수', _kickoff, () => _pickDate(false)),
            _dateButton('마감', _due, () => _pickDate(true)),
          ],
        ),
      ],
    );
  }

  Widget _stepper(
    String label,
    String preview,
    TextEditingController ctl,
    String key,
  ) {
    final c = AppColors.of(context);
    Widget btn(IconData icon, int by) => InkWell(
      onTap: () => _step(ctl, by),
      child: SizedBox(width: 34, height: 36, child: Icon(icon, size: 18)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text.rich(
          TextSpan(
            text: '$label ',
            children: [
              TextSpan(
                text: preview,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          style: TextStyle(fontSize: 12, color: c.muted),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(Icons.remove, -1),
              SizedBox(
                width: 64,
                child: TextField(
                  key: Key(key),
                  controller: ctl,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: (_) => _setRun(),
                ),
              ),
              btn(Icons.add, 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateButton(String label, DateTime? d, VoidCallback onTap) {
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        ToolbarButton(
          key: Key('reg-date-$label'),
          label: d == null ? '—' : formatDate(d),
          selected: false,
          onTap: widget.onRegister == null ? null : onTap,
        ),
      ],
    );
  }
}
