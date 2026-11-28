import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../controllers/registration.dart';
import '../../core/size_class.dart';
import '../../services/catalogue_reader.dart';
import '../../models/progress.dart';
import '../../services/catalogue_store.dart';
import '../client_pick.dart';
import '../palette.dart';
import '../count_stepper.dart';
import '../date_span.dart';
import '../sliding_row.dart';
import '../fold.dart';
import '../format.dart';
import '../instant.dart';
import '../pick_field.dart';
import '../theme.dart';
import '../widgets.dart';
import '../text/strings.dart';

/// Registering cuts, one step after another: 회사 → 작품 → 화수 → 파트 →
/// 컷. Each of the first four picks from what is registered, with
/// 「+ 새로 만들기」 at the bottom of its list. Stages come from a role
/// chip (it checks the role's stages) or one checkbox at a time. Cuts are
/// a first number and a count, plus cuts added by name at the grid's
/// 「+」; picked cells (tap or drag across) can be left out, split A/B,
/// paired as shared (still two cuts) or renamed.
class RegisterView extends StatefulWidget {
  const RegisterView({
    super.key,
    required this.now,
    required this.layout,
    this.reader,
    this.roles = const [],
    this.onCreateClient,
    this.onCreateWork,
    this.onCreateEpisode,
    this.onRegister,
    this.onClientColor,
    this.onWrite,
    this.onUndo,
  });

  /// One edit of what the pick lists hold (rename, delete), then the
  /// views reload; null hides the lists' tools.
  final void Function(void Function(CatalogueStore store) write)? onWrite;

  /// The app's undo, offered after a delete in a pick list.
  final VoidCallback? onUndo;

  final DateTime now;
  final ScreenLayout layout;

  /// Searches and the work's cut format; null shows empty lists.
  final CatalogueReader? reader;

  /// Role presets: name and the stages it takes on.
  /// Sets a client's colour (ARGB); null hides the swatch button.
  final void Function(int clientId, int argb)? onClientColor;

  final List<({int id, String name, List<String> stages})> roles;

  final int Function(String name)? onCreateClient;
  final int Function(String title, int? clientId)? onCreateWork;
  final int Function(int workId, String number)? onCreateEpisode;

  /// Saves the draft; returns how many tasks were made. Null: read-only.
  final int Function(RegistrationDraft draft)? onRegister;

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  PickOption<int>? _client;

  /// Colours of the clients the picker has shown (its search answers).
  final _clientColors = <int, int?>{};
  PickOption<int>? _work;
  PickOption<int>? _episode;
  String? _part;
  final _start = TextEditingController(text: '1');
  final _count = TextEditingController(text: '100');
  final _stages = <String>{};
  CutDraft _cuts = CutDraft();
  Set<String> _taken = const {};

  final _picked = <String>{};

  /// The first stage's start until set: the day of registering.
  late final DateTime _kickoff = DateTime(
    widget.now.year,
    widget.now.month,
    widget.now.day,
  );

  /// Dates set on one stage's row, by stage name; a stage without its own
  /// takes the stage above's (the first: [_kickoff], no deadline).
  final _ownDates = <String, ({DateTime? kickoff, DateTime? due})>{};

  /// What the pick lists last showed, for their tools: whether each item
  /// is used, an episode's subtitle (kept when renumbered), a part's id.
  final _used = <(CatalogueKind, int), bool>{};
  final _clientsUsed = <int, bool>{};
  final _episodeTitles = <int, String?>{};
  final _partIds = <String, ({int id, bool used})>{};

  /// The tools for one kind of list: rename and delete through
  /// [RegisterView.onWrite]; a picked item renamed shows its new name, a
  /// picked one deleted is unpicked.
  PresetTools<T>? _tools<T>({
    required bool Function(T value) inUse,
    required void Function(CatalogueStore s, T value, String name) rename,
    required void Function(CatalogueStore s, T value) delete,
    required void Function(T value, String? name) after,
    Color Function(T value)? colorOf,
    void Function(T value, Color color)? recolor,
    bool Function(T value)? editable,
  }) {
    final write = widget.onWrite;
    if (write == null) return null;
    return PresetTools<T>(
      inUse: inUse,
      rename: (v, name) {
        write((s) => rename(s, v, name));
        setState(() => after(v, name));
      },
      delete: (v) {
        write((s) => delete(s, v));
        setState(() => after(v, null));
      },
      colorOf: colorOf,
      recolor: recolor,
      editable: editable,
      onUndo: widget.onUndo,
    );
  }

  /// While dragging across the grid: true picks, false drops.
  bool? _paint;
  final _scrollKey = GlobalKey();

  List<String> get _allStages =>
      {for (final r in widget.roles) ...r.stages}.toList();

  void _refold() => setState(() {});

  @override
  void initState() {
    super.initState();
    Folds.newCuts.addListener(_refold);
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
    Folds.newCuts.removeListener(_refold);
    _start.dispose();
    _count.dispose();
    super.dispose();
  }

  // ---- steps ----

  Future<void> _pickWork(PickOption<int> w) async {
    setState(() {
      _work = w;
      _episode = null;
      _part = null;
      _taken = const {};
    });
    final f = (await widget.reader?.numberStyles())?.cut;
    if (!mounted || f == null) return;
    setState(() => _rebuildCuts(prefix: f.prefix, width: f.digits));
  }

  Future<void> _pickEpisode(PickOption<int> e) async {
    setState(() {
      _episode = e;
      _part = null;
    });
    await _loadTaken();
  }

  Future<void> _loadTaken() async {
    final e = _episode;
    if (e == null) return;
    // The episode's numbers, read only to warn of a clash: its saved
    // cuts are edited on their cards now.
    final cuts = await widget.reader?.cuts(e.value);
    if (!mounted || cuts == null) return;
    setState(() => _taken = {for (final c in cuts) c.number});
  }

  void _rebuildCuts({String? prefix, int? width}) {
    final start = int.tryParse(_start.text) ?? 1;
    final count = (int.tryParse(_count.text) ?? 1).clamp(1, 2000);
    final old = _cuts;
    _cuts =
        CutDraft(
            start: start,
            count: count,
            prefix: prefix ?? old.prefix,
            width: width ?? old.width,
          )
          ..extras.addAll(old.extras)
          ..renames.addAll(old.renames)
          ..removed.addAll(old.removed)
          ..splits.addAll(old.splits)
          ..shared.addAll(old.shared);
    final cells = _cuts.cells.toSet();
    _picked.retainWhere(cells.contains);
  }

  // ---- grid picking ----

  String? _cellAt(Offset global) {
    final box = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
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
      final has = _picked.contains(n);
      if (start) _paint = !has;
      if (_paint == null || _paint == has) return;
      _paint! ? _picked.add(n) : _picked.remove(n);
    });
  }

  Future<void> _addCut() async {
    final name = await askName(
      context,
      title: S.addCut.t,
      prefix: _cuts.prefix,
    );
    if (name == null || !mounted) return;
    setState(() => _cuts.add(name));
  }

  Future<void> _rename(String id) async {
    // The value alone in the field (12, 12A); the notation outside it.
    final name = await askName(
      context,
      title: S.cutName.t,
      initial: _cuts.valueOf(id),
      prefix: _cuts.prefix,
    );
    if (name == null || !mounted) return;
    setState(() {
      _cuts.rename(id, name);
      _picked.clear();
    });
  }

  // ---- saving ----

  Set<String> get _clashes => _cuts.clashes(_taken);

  bool get _ready =>
      widget.onRegister != null &&
      _work != null &&
      _episode != null &&
      _stages.isNotEmpty &&
      _cuts.total > 0 &&
      _clashes.isEmpty;

  void _register() {
    final cb = widget.onRegister;
    if (cb == null || !_ready) return;
    cb(
      RegistrationDraft(
        workId: _work!.value,
        episodeId: _episode!.value,
        partLabel: _part,
        stages: [
          for (final s in _allStages)
            if (_stages.contains(s)) s,
        ],
        cuts: _cuts,
        kickoffAt: _kickoff,
        schedules: {
          for (final s in _checked)
            s: (kickoffAt: _datesOf(s).kickoff, dueAt: _endOf(_datesOf(s).due)),
        },
      ),
    );
    final cuts = _cuts.total;
    // Saved: the form starts over, as when the screen first opened.
    setState(_clear);
    _snack('${S.register.t} · $cuts cut', key: 'registered-snack');
  }

  /// Everything typed and picked, to put back after a reset.
  ({
    PickOption<int>? client,
    PickOption<int>? work,
    PickOption<int>? episode,
    String? part,
    Set<String> stages,
    CutDraft cuts,
    String start,
    String count,
    Map<String, ({DateTime? kickoff, DateTime? due})> dates,
  })
  _snapshot() => (
    client: _client,
    work: _work,
    episode: _episode,
    part: _part,
    stages: {..._stages},
    cuts: _cuts,
    start: _start.text,
    count: _count.text,
    dates: {..._ownDates},
  );

  /// The form as the screen first opens it: nothing picked, the first
  /// role's stages, cuts 1-100, starting today.
  void _clear() {
    _client = null;
    _work = null;
    _episode = null;
    _part = null;
    _stages
      ..clear()
      ..addAll(widget.roles.isEmpty ? const [] : widget.roles.first.stages);
    _start.text = '1';
    _count.text = '100';
    _cuts = CutDraft(prefix: _cuts.prefix, width: _cuts.width);
    _ownDates.clear();
    _picked.clear();
    _taken = const {};
  }

  /// 「초기화」: the form empties at once; the snack bar's undo puts back
  /// what was there (no confirmation first).
  void _reset() {
    final was = _snapshot();
    setState(_clear);
    _snack(
      S.resetForm.t,
      key: 'reset-snack',
      undo: () {
        setState(() {
          _client = was.client;
          _work = was.work;
          _episode = was.episode;
          _part = was.part;
          _stages
            ..clear()
            ..addAll(was.stages);
          _cuts = was.cuts;
          _start.text = was.start;
          _count.text = was.count;
          _ownDates
            ..clear()
            ..addAll(was.dates);
        });
        unawaited(_loadTaken());
      },
    );
  }

  void _snack(String text, {required String key, VoidCallback? undo}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: Key(key),
            content: Text(text),
            action: undo == null
                ? null
                : SnackBarAction(
                    key: const Key('reset-undo'),
                    label: S.undoDrop.t,
                    onPressed: undo,
                  ),
          ),
        );

  /// The checked stages, in order.
  List<String> get _checked => [
    for (final s in _allStages)
      if (_stages.contains(s)) s,
  ];

  /// A deadline day's end.
  static DateTime? _endOf(DateTime? d) =>
      d == null ? null : DateTime(d.year, d.month, d.day, 23, 59);

  /// [stage]'s dates: its own, else the stage above's — copied down, so
  /// LO's dates start 原画's until 原画 gets its own.
  ({DateTime kickoff, DateTime? due, bool ownKickoff, bool ownDue}) _datesOf(
    String stage,
  ) {
    var kickoff = _kickoff;
    DateTime? due;
    for (final s in _checked) {
      final own = _ownDates[s];
      kickoff = own?.kickoff ?? kickoff;
      due = own?.due ?? due;
      if (s == stage) {
        return (
          kickoff: kickoff,
          due: due,
          ownKickoff: own?.kickoff != null,
          ownDue: own?.due != null,
        );
      }
    }
    return (kickoff: kickoff, due: due, ownKickoff: false, ownDue: false);
  }

  Future<void> _pickDate(String stage, {required bool due}) async {
    final now = _datesOf(stage);
    final d = await showInstantDatePicker(
      context: context,
      firstDate: DateTime(widget.now.year - 1),
      lastDate: DateTime(widget.now.year + 2),
      initialDate: due ? (now.due ?? now.kickoff) : now.kickoff,
      title: due ? S.pickDue.t : S.pickKickoff.t,
    );
    if (d == null || !mounted) return;
    setState(() {
      final own = _ownDates[stage];
      _ownDates[stage] = due
          ? (kickoff: own?.kickoff, due: d)
          : (kickoff: d, due: own?.due);
    });
  }

  // ---- build ----

  /// The cut grids keep wide side margins on phones: room to drag the page
  /// without starting a pick on a cell.
  EdgeInsets get _gridPadding => widget.layout.size == SizeClass.narrow
      ? const EdgeInsets.fromLTRB(36, 10, 36, 24)
      : const EdgeInsets.fromLTRB(14, 10, 14, 24);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final cells = _cuts.cells;
    final clashes = _clashes;
    return ColoredBox(
      color: c.panel,
      child: Column(
        children: [
          Expanded(
            child: Listener(
              onPointerUp: (_) {
                if (_paint != null) setState(() => _paint = null);
              },
              onPointerCancel: (_) {
                if (_paint != null) setState(() => _paint = null);
              },
              child: OwnScroll(
                builder: (controller) => Scrollbar(
                  controller: controller,
                  child: CustomScrollView(
                    key: _scrollKey,
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
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                        sliver: SliverToBoxAdapter(child: _summary(context)),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(10, 4, 14, 0),
                        sliver: SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FoldToggle(
                              key: const Key('fold-new-cuts'),
                              state: Folds.newCuts,
                              label: '${cells.length} cut',
                            ),
                          ),
                        ),
                      ),
                      if (Folds.newCuts.value)
                        SliverPadding(
                          padding: _gridPadding,
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 60,
                                  mainAxisExtent: 24,
                                  mainAxisSpacing: 2,
                                  crossAxisSpacing: 2,
                                ),
                            itemCount: cells.length + 1,
                            itemBuilder: (context, i) => i == cells.length
                                ? _plusCell(context)
                                : _cell(
                                    context,
                                    cells[i],
                                    clashes.contains(cells[i]),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _actions(context),
        ],
      ),
    );
  }

  Widget _form(BuildContext context) {
    final c = AppColors.of(context);
    final r = widget.reader;
    final wide = widget.layout.size != SizeClass.narrow;
    final fw = wide ? 200.0 : double.infinity;
    final sw = wide ? 130.0 : double.infinity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ClientPick(
              picked: _client,
              reader: r,
              colors: _clientColors,
              width: fw,
              onPicked: (x) => setState(() {
                _client = x;
                _work = null;
                _episode = null;
                _part = null;
              }),
              onCreate: widget.onCreateClient,
              inUse: _clientsUsed,
              tools: _tools<int>(
                inUse: (id) => _clientsUsed[id] ?? true,
                rename: (s, id, name) => s.renameClient(id, name),
                delete: (s, id) => s.deleteClient(id),
                after: (id, name) {
                  if (_client?.value != id) return;
                  if (name == null) {
                    _client = _work = _episode = null;
                    _part = null;
                  } else {
                    _client = (value: id, title: name, note: null);
                  }
                },
                colorOf: (id) => clientColorOf(id, _clientColors[id]),
                recolor: widget.onClientColor == null
                    ? null
                    : (id, col) {
                        _clientColors[id] = col.toARGB32();
                        widget.onClientColor!(id, col.toARGB32());
                        setState(() {});
                      },
              ),
              onColor: widget.onClientColor == null
                  ? null
                  : (id, argb) {
                      widget.onClientColor!(id, argb);
                      setState(() {});
                    },
            ),
            PickField<int>(
              key: const Key('pick-work'),
              current: _work?.value,
              label: S.title.t,
              width: fw,
              value: _work?.title,
              search: (q) async {
                if (r == null) return const [];
                final rows = await r.searchWorks(q, clientId: _client?.value);
                for (final x in rows) {
                  _used[(CatalogueKind.work, x.id)] = x.inUse;
                }
                return [
                  for (final x in rows)
                    (value: x.id, title: x.title, note: null),
                ];
              },
              onPicked: _pickWork,
              tools: _tools<int>(
                inUse: (id) => _used[(CatalogueKind.work, id)] ?? true,
                rename: (s, id, name) => s.renameWork(id, name),
                delete: (s, id) => s.deleteWork(id),
                after: (id, name) {
                  if (_work?.value != id) return;
                  if (name == null) {
                    _work = _episode = null;
                    _part = null;
                  } else {
                    _work = (value: id, title: name, note: null);
                  }
                },
              ),
              onCreate: widget.onCreateWork == null
                  ? null
                  : (name) async => (
                      value: widget.onCreateWork!(name, _client?.value),
                      title: name,
                      note: null,
                    ),
            ),
            PickField<int>(
              key: const Key('pick-episode'),
              current: _episode?.value,
              label: S.episode.t,
              width: sw,
              enabled: _work != null,
              value: _episode?.title,
              search: (q) async {
                final w = _work;
                if (r == null || w == null) return const [];
                final rows = await r.searchEpisodes(w.value, q);
                for (final x in rows) {
                  _used[(CatalogueKind.episode, x.id)] = x.inUse;
                  _episodeTitles[x.id] = x.title;
                }
                return [
                  for (final x in rows)
                    (value: x.id, title: x.number, note: x.title),
                ];
              },
              onPicked: _pickEpisode,
              tools: _tools<int>(
                inUse: (id) => _used[(CatalogueKind.episode, id)] ?? true,
                // The number changes; the subtitle stays.
                rename: (s, id, name) =>
                    s.renameEpisode(id, name, title: _episodeTitles[id]),
                delete: (s, id) => s.deleteEpisode(id),
                after: (id, name) {
                  if (_episode?.value != id) return;
                  if (name == null) {
                    _episode = null;
                    _part = null;
                  } else {
                    _episode = (
                      value: id,
                      title: episodeShown(name),
                      note: null,
                    );
                  }
                },
              ),
              onCreate: widget.onCreateEpisode == null
                  ? null
                  : (name) async {
                      final id = widget.onCreateEpisode!(_work!.value, name);
                      return (value: id, title: episodeShown(name), note: null);
                    },
            ),
            PickField<String>(
              key: const Key('pick-part'),
              current: _part,
              label: S.part.t,
              width: sw,
              enabled: _episode != null,
              value: _part,
              search: (q) async {
                if (r == null) return const [];
                final e = _episode;
                final rows = e == null
                    ? const <PartRow>[]
                    : await r.parts(e.value);
                for (final x in rows) {
                  _partIds[x.label] = (id: x.id, used: x.inUse);
                }
                return [
                  (value: '', title: '—', note: null),
                  for (final x in rows)
                    if (x.label.contains(q))
                      (value: x.label, title: x.label, note: '${x.cutCount}'),
                ];
              },
              tools: _tools<String>(
                // 「—」 (no part) and a typed new one are not saved parts.
                editable: _partIds.containsKey,
                inUse: (label) => _partIds[label]?.used ?? true,
                rename: (s, label, name) =>
                    s.renamePart(_partIds[label]!.id, name),
                delete: (s, label) => s.deletePart(_partIds[label]!.id),
                after: (label, name) {
                  if (_part == label) _part = name;
                },
              ),
              onPicked: (x) =>
                  setState(() => _part = x.value.isEmpty ? null : x.value),
              onCreate: (name) async => (value: name, title: name, note: null),
            ),
          ],
        ),
        Text(S.roles.t, style: TextStyle(fontSize: 12, color: c.muted)),
        // One row the finger slides along: a role is a shortcut, most
        // people use one or two.
        SlidingRow(
          key: const Key('roles-row'),
          children: [
            for (final role in widget.roles)
              ToolbarButton(
                key: Key('role-${role.name}'),
                label: role.name,
                selected:
                    _stages.length == role.stages.length &&
                    role.stages.every(_stages.contains),
                onTap: () => setState(
                  () => _stages
                    ..clear()
                    ..addAll(role.stages),
                ),
              ),
          ],
        ),
        // Folded, only the checked stages show.
        ValueListenableBuilder<bool>(
          valueListenable: Folds.registerStages,
          builder: (context, open, _) => Wrap(
            spacing: 14,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FoldToggle(
                key: const Key('fold-stages'),
                state: Folds.registerStages,
                label: S.stagesN.f({'n': _stages.length}),
              ),
              for (final s in _allStages)
                if (open || _stages.contains(s)) _stageBox(s),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            CountStepper(
              label: S.firstCut.t,
              preview: _cuts.number(_cuts.start),
              controller: _start,
              fieldKey: const Key('reg-start'),
              onChanged: () => setState(_rebuildCuts),
            ),
            CountStepper(
              label: S.cutCount.t,
              preview: '~ ${_cuts.number(_cuts.start + _cuts.count - 1)}',
              controller: _count,
              fieldKey: const Key('reg-count'),
              onChanged: () => setState(_rebuildCuts),
            ),
          ],
        ),
        // Each card the register makes (one per stage) with its own
        // production dates, the stage above's until set.
        for (final s in _checked) _stageDates(s),
      ],
    );
  }

  Widget _stageBox(String s) => InkWell(
    key: Key('stage-$s'),
    onTap: () => setState(
      () => _stages.contains(s) ? _stages.remove(s) : _stages.add(s),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: _stages.contains(s),
          visualDensity: VisualDensity.compact,
          onChanged: (v) =>
              setState(() => v == true ? _stages.add(s) : _stages.remove(s)),
        ),
        Text(stageText(s), style: const TextStyle(fontSize: 13)),
      ],
    ),
  );

  Widget _summary(BuildContext context) {
    final c = AppColors.of(context);
    final picked = [
      for (final x in _cuts.cells)
        if (_picked.contains(x)) x,
    ];
    final any = picked.isNotEmpty;
    VoidCallback act(void Function() f) =>
        () => setState(() {
          f();
          _picked.clear();
        });
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
          label: S.takeOut.t,
          selected: false,
          onTap: any ? act(() => _cuts.toggleRemoved(picked)) : null,
        ),
        ToolbarButton(
          key: const Key('cut-split'),
          label: 'A/B',
          selected: false,
          onTap: any ? act(() => _cuts.toggleSplit(picked)) : null,
        ),
        ToolbarButton(
          key: const Key('cut-share'),
          label: S.shared.t,
          selected: false,
          onTap: _cuts.canShare(picked)
              ? act(() => _cuts.toggleShared(picked))
              : null,
        ),
        ToolbarButton(
          key: const Key('cut-rename'),
          label: S.name.t,
          selected: false,
          onTap: picked.length == 1 ? () => _rename(picked.single) : null,
        ),
        ToolbarButton(
          key: const Key('cut-clear'),
          label: S.clear.t,
          selected: false,
          onTap: any ? () => setState(_picked.clear) : null,
        ),
      ],
    );
  }

  /// The screen's foot, fixed above the tabs (and the keyboard): 「초기화」
  /// on the left, quiet; 「등록」 on the right, the main action.
  Widget _actions(BuildContext context) {
    final c = AppColors.of(context);
    return DecoratedBox(
      key: const Key('register-actions'),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // The quiet one gives way first on a narrow screen.
            Flexible(
              child: TextButton.icon(
                key: const Key('register-reset'),
                onPressed: widget.onRegister == null ? null : _reset,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: Text(
                  S.resetForm.t,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            FilledButton(
              key: const Key('register'),
              onPressed: _ready ? _register : null,
              child: Text(S.register.t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String id, bool clash) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final removed = _cuts.removed.contains(id);
    final split = _cuts.splits[id];
    final paired = _cuts.partner(id) != null;
    final on = _picked.contains(id);
    final edge = clash
        ? scheme.error
        : paired
        ? scheme.primary
        : (on ? c.selected : c.line);
    return MetaData(
      metaData: id,
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onLongPress: () => _rename(id),
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
            key: Key('cell-$id'),
            decoration: BoxDecoration(
              color: on ? c.selected : (removed ? null : c.panel),
              border: Border.all(color: edge, width: clash || paired ? 1.6 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text.rich(
                TextSpan(
                  text: _cuts.label(id),
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
                  fontSize: 10.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: clash
                      ? scheme.error
                      : removed
                      ? c.faint
                      : (split != null || paired ? scheme.primary : null),
                  fontWeight: split != null || paired ? FontWeight.w700 : null,
                  decoration: removed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _plusCell(BuildContext context) {
    final c = AppColors.of(context);
    return InkWell(
      key: const Key('cell-add'),
      onTap: _addCut,
      borderRadius: BorderRadius.circular(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(Icons.add, size: 16, color: c.muted),
      ),
    );
  }

  /// One stage's row: its name, then 「제작」 [start → deadline]; a date
  /// copied from the stage above shows faint until set here.
  Widget _stageDates(String stage) {
    final c = AppColors.of(context);
    final d = _datesOf(stage);
    final can = widget.onRegister != null;
    Widget date(String key, DateTime? day, bool own, bool due) => InkWell(
      key: Key('$key-$stage'),
      onTap: can ? () => _pickDate(stage, due: due) : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          day == null ? '—' : formatDate(day),
          style: TextStyle(
            color: own ? null : c.muted,
            decoration: can ? TextDecoration.underline : null,
            decorationColor: c.faint,
          ),
        ),
      ),
    );
    return Row(
      key: Key('reg-stage-dates-$stage'),
      spacing: 10,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            stageText(stage),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Flexible(
          child: DateSpanPill(
            label: S.production.t,
            start: date('reg-kickoff', d.kickoff, d.ownKickoff, false),
            end: date('reg-due', d.due, d.ownDue, true),
          ),
        ),
      ],
    );
  }
}
