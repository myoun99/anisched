import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../controllers/registration.dart';
import '../../core/size_class.dart';
import '../../services/catalogue_reader.dart';
import '../../models/number_style.dart';
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
import '../notice.dart';

/// Registering cuts in four cards (유저 2026-11-28): [회사 · 작품 · 화 ·
/// 파트] — each picks from what is registered, with 「+ 새로 만들기」 at
/// the bottom of its list; [담당] — roles (several at once: their stages
/// together) and one checkbox per stage; [일정] — each stage's dates; and
/// [등록할 컷] — the list of cut blocks that will be saved, filled by the
/// tools above it (「범위로 추가」: first cut to last; 「직접 추가」: one
/// by name). Picked blocks (tap or drag across) can be paired as shared
/// (one block, two cuts), renamed or deleted.
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
  // The range tool's first and last cut.
  final _first = TextEditingController(text: '1');
  final _last = TextEditingController(text: '100');
  final _stages = <String>{};
  CutDraft _cuts = CutDraft(count: 0);
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
    _first.dispose();
    _last.dispose();
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

  /// The list in the work's notation, its blocks kept.
  void _rebuildCuts({String? prefix, int? width}) {
    final old = _cuts;
    _cuts =
        CutDraft(
            count: 0,
            prefix: prefix ?? old.prefix,
            width: width ?? old.width,
          )
          ..extras.addAll(old.extras)
          ..renames.addAll(old.renames)
          ..shared.addAll(old.shared);
    final cells = _cuts.cells.toSet();
    _picked.retainWhere(cells.contains);
  }

  int? get _firstNo => int.tryParse(_first.text.trim());
  int? get _lastNo => int.tryParse(_last.text.trim());

  /// 「범위로 추가」: the first cut to the last as blocks.
  void _addRange() {
    final a = _firstNo;
    final b = _lastNo;
    if (a == null || b == null) return;
    setState(() => _cuts.addRange(a, b));
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

  /// 「직접 추가」: one cut by name (12A, BANK).
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

  /// Clashes by value in the document's notation (C012, 12: one cut).
  Set<String> get _clashes =>
      _cuts.clashes(_taken, (n) => parseCutInput(n, _cuts.style));

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
    String first,
    String last,
    Map<String, ({DateTime? kickoff, DateTime? due})> dates,
  })
  _snapshot() => (
    client: _client,
    work: _work,
    episode: _episode,
    part: _part,
    stages: {..._stages},
    cuts: _cuts,
    first: _first.text,
    last: _last.text,
    dates: {..._ownDates},
  );

  /// The form as the screen first opens it: nothing picked, the first
  /// role's stages, no cuts yet, starting today.
  void _clear() {
    _client = null;
    _work = null;
    _episode = null;
    _part = null;
    _stages
      ..clear()
      ..addAll(widget.roles.isEmpty ? const [] : widget.roles.first.stages);
    _first.text = '1';
    _last.text = '100';
    _cuts = CutDraft(count: 0, prefix: _cuts.prefix, width: _cuts.width);
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
          _first.text = was.first;
          _last.text = was.last;
          _ownDates
            ..clear()
            ..addAll(was.dates);
        });
        unawaited(_loadTaken());
      },
    );
  }

  void _snack(String text, {required String key, VoidCallback? undo}) =>
      showNotice(
        context,
        text,
        key: Key(key),
        action: undo == null
            ? null
            : (
                label: S.undoDrop.t,
                onPressed: undo,
                key: const Key('reset-undo'),
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

  /// The cut list keeps wide side margins on phones: room to drag the page
  /// without starting a pick on a block.
  EdgeInsets get _listPadding => widget.layout.size == SizeClass.narrow
      ? const EdgeInsets.symmetric(horizontal: 22)
      : EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
                  child: SingleChildScrollView(
                    key: _scrollKey,
                    controller: controller,
                    physics: _paint == null
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        _section(
                          key: 'reg-sec-work',
                          icon: Icons.movie_outlined,
                          title: S.title.t,
                          child: _workPicks(context),
                        ),
                        _section(
                          key: 'reg-sec-roles',
                          icon: Icons.badge_outlined,
                          title: S.roles.t,
                          child: _roleRows(context),
                        ),
                        _section(
                          key: 'reg-sec-dates',
                          icon: Icons.event_outlined,
                          title: S.schedule.t,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 4,
                            children: [
                              // Each card the register makes (one per
                              // stage) with its own production dates.
                              for (final s in _checked) _stageDates(s),
                            ],
                          ),
                        ),
                        _section(
                          key: 'reg-sec-cuts',
                          icon: Icons.view_module_outlined,
                          title: S.cutsToRegister.t,
                          trailing: _pickTools(context),
                          child: _cutList(context),
                        ),
                      ],
                    ),
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

  /// One card of the form: its icon and title on the left (any tools on
  /// the right), then its contents.
  Widget _section({
    required String key,
    required IconData icon,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    final c = AppColors.of(context);
    return Panel(
      key: Key(key),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 6,
            children: [
              Icon(icon, size: 16, color: c.muted),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
              if (trailing != null) Expanded(child: trailing),
            ],
          ),
          child,
        ],
      ),
    );
  }

  Widget _workPicks(BuildContext context) {
    final r = widget.reader;
    final wide = widget.layout.size != SizeClass.narrow;
    final fw = wide ? 200.0 : double.infinity;
    final sw = wide ? 130.0 : double.infinity;
    return Wrap(
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
              for (final x in rows) (value: x.id, title: x.title, note: null),
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
                _episode = (value: id, title: episodeShown(name), note: null);
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
            final rows = e == null ? const <PartRow>[] : await r.parts(e.value);
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
            rename: (s, label, name) => s.renamePart(_partIds[label]!.id, name),
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
    );
  }

  /// Roles first (several may be on: their stages together), then each
  /// stage's own checkbox; folded, only the checked stages show.
  Widget _roleRows(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [
      // One row the finger slides along: most people use one or two.
      SlidingRow(
        key: const Key('roles-row'),
        children: [
          for (final role in widget.roles)
            ToolbarButton(
              key: Key('role-${role.name}'),
              label: role.name,
              selected: _roleOn(role.stages),
              onTap: () => setState(() => _toggleRole(role.stages)),
            ),
        ],
      ),
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
    ],
  );

  /// A role is on when all its stages are checked.
  bool _roleOn(List<String> stages) =>
      stages.isNotEmpty && stages.every(_stages.contains);

  /// Turns a role on (adds its stages) or off (drops those no other role
  /// that stays on also takes).
  void _toggleRole(List<String> stages) {
    if (!_roleOn(stages)) {
      _stages.addAll(stages);
      return;
    }
    final kept = {
      for (final r in widget.roles)
        if (!identical(r.stages, stages) && _roleOn(r.stages)) ...r.stages,
    };
    _stages.removeWhere((s) => stages.contains(s) && !kept.contains(s));
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

  /// The picked blocks' tools, on the section's right: shared, name,
  /// delete, unpick.
  Widget _pickTools(BuildContext context) {
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
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 6,
      children: [
        ToolbarButton(
          key: const Key('cut-share'),
          label: S.shared.t,
          icon: Icons.link,
          selected: false,
          onTap: _cuts.canShare(picked)
              ? act(() => _cuts.toggleShared(picked))
              : null,
        ),
        ToolbarButton(
          key: const Key('cut-rename'),
          label: S.name.t,
          icon: Icons.drive_file_rename_outline,
          selected: false,
          onTap: picked.length == 1 ? () => _rename(picked.single) : null,
        ),
        ToolbarButton(
          key: const Key('cut-delete'),
          label: S.remove.t,
          icon: Icons.delete_outline,
          selected: false,
          onTap: any ? act(() => _cuts.delete(picked)) : null,
        ),
        ToolbarButton(
          key: const Key('cut-clear'),
          label: S.clear.t,
          icon: Icons.close,
          selected: false,
          onTap: any ? () => setState(_picked.clear) : null,
        ),
      ],
    );
  }

  /// The tools that fill the list (first cut ~ last cut and 「범위로
  /// 추가」, 「직접 추가」), the count, then the list itself: one block a
  /// cut, a shared pair one block.
  Widget _cutList(BuildContext context) {
    final c = AppColors.of(context);
    final clashes = _clashes;
    final cells = _cuts.cells;
    final a = _firstNo;
    final b = _lastNo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            CountStepper(
              label: S.firstCut.t,
              preview: a == null ? '' : _cuts.number(a),
              controller: _first,
              fieldKey: const Key('reg-first'),
              onChanged: () => setState(() {}),
            ),
            CountStepper(
              label: S.lastCut.t,
              preview: b == null ? '' : _cuts.number(b),
              controller: _last,
              fieldKey: const Key('reg-last'),
              onChanged: () => setState(() {}),
            ),
            FilledButton.tonalIcon(
              key: const Key('cut-add-range'),
              onPressed: a == null || b == null ? null : _addRange,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: Text(S.addRange.t),
            ),
            OutlinedButton.icon(
              key: const Key('cut-add-one'),
              onPressed: _addCut,
              icon: const Icon(Icons.add, size: 18),
              label: Text(S.addOne.t),
            ),
          ],
        ),
        Row(
          spacing: 8,
          children: [
            FoldToggle(
              key: const Key('fold-new-cuts'),
              state: Folds.newCuts,
              label: '${_cuts.total} cut',
            ),
            Text('× ${_stages.length}', style: TextStyle(color: c.muted)),
          ],
        ),
        if (Folds.newCuts.value)
          Padding(
            padding: _listPadding,
            child: Wrap(
              key: const Key('cut-blocks'),
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in cells)
                  // A shared pair is one block, on its first cell.
                  if (!_cuts.shared.containsValue(id))
                    _block(context, id, clashes),
              ],
            ),
          ),
      ],
    );
  }

  /// One block: a cut, or a shared pair (「C012/C013」); picked by a tap
  /// or a drag across, renamed by a long press.
  Widget _block(BuildContext context, String id, Set<String> clashes) {
    final scheme = Theme.of(context).colorScheme;
    final pair = _cuts.shared[id];
    final ids = [id, ?pair];
    final clash = ids.any(clashes.contains);
    final on = ids.every(_picked.contains);
    return MetaData(
      metaData: id,
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onLongPress: pair == null ? () => _rename(id) : null,
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
          child: CutBlock(
            key: Key('cell-$id'),
            picked: on,
            edge: clash ? scheme.error : null,
            children: [
              Text(
                ids.map(_cuts.shown).join('/'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: clash ? scheme.error : null,
                ),
              ),
            ],
          ),
        ),
      ),
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
