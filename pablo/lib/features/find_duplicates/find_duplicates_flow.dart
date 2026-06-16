// FindDuplicatesFlow — the staged "Find Duplicates" workflow.
//
// Stages: 1) choose scope (selection / folders / library) → 2) review, where
// exact duplicates are shown first, then visually-similar groups behind a
// similarity slider, with ranked auto-selection (newest / largest / highest-res)
// so the user can clear thousands of dupes with minimal manual checking. Apply
// quarantines the non-keepers (never deletes). State is local to this widget.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../components/pablo_button.dart';
import '../../data/models.dart';
import '../../data/mock/mock_data.dart';
import '../../data/mock/photo_factory.dart';
import '../../data/sources/dedup_repository.dart';
import '../../theme/tokens.dart';
import 'dedup_models.dart';
import 'dedup_review_stage.dart';
import 'dedup_scope_stage.dart';

class FindDuplicatesFlow extends StatefulWidget {
  const FindDuplicatesFlow({super.key});

  @override
  State<FindDuplicatesFlow> createState() => _FindDuplicatesFlowState();
}

class _FindDuplicatesFlowState extends State<FindDuplicatesFlow> {
  final DedupRepository _repo = createDedupRepository();

  int _stage = 0; // 0 = scope, 1 = review
  DedupScopeKind _scope = DedupScopeKind.library;
  final Set<String> _folderIds = {};

  final Map<String, Photo> _index = {}; // scoped photo id → Photo
  List<String> _scopedIds = const [];
  List<DupCluster> _exact = const [];
  List<DupCluster> _similar = const [];

  double _threshold = 0.80;
  KeeperRule _rule = KeeperRule.highestRes;
  final Set<String> _discards = {};
  bool _busy = false;

  // ── scope resolution ──
  List<Photo> _leafPhotos() {
    final out = <Photo>[];
    final seen = <String>{};
    void walk(FolderNode n) {
      if (n.isGroup) {
        for (final c in n.children) {
          walk(c);
        }
      } else if (_scope != DedupScopeKind.folders || _folderIds.contains(n.id)) {
        for (final p in photosFor(n.id)) {
          if (seen.add(p.id)) out.add(p);
        }
      }
    }
    for (final f in kFolders) {
      walk(f);
    }
    return out;
  }

  List<Photo> _resolvePhotos(BuildContext context) {
    final st = AppScope.read(context);
    if (_scope == DedupScopeKind.selection) {
      final ids = st.selectedPhotos;
      final out = <Photo>[];
      for (final node in _allLeafIds()) {
        for (final p in photosFor(node)) {
          if (ids.contains(p.id)) out.add(p);
        }
      }
      return out;
    }
    return _leafPhotos();
  }

  List<String> _allLeafIds() {
    final ids = <String>[];
    void walk(FolderNode n) {
      if (n.isGroup) {
        for (final c in n.children) {
          walk(c);
        }
      } else {
        ids.add(n.id);
      }
    }
    for (final f in kFolders) {
      walk(f);
    }
    return ids;
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    final photos = _resolvePhotos(context);
    _index
      ..clear()
      ..addEntries(photos.map((p) => MapEntry(p.id, p)));
    _scopedIds = [for (final p in photos) p.id];
    final exact = await _repo.findExact(_scopedIds);
    final similar = await _repo.findSimilar(_scopedIds, _threshold);
    if (!mounted) return;
    setState(() {
      _exact = [for (final c in exact) c.rankedBy(_rule)];
      _similar = [for (final c in similar) c.rankedBy(_rule)];
      _discards.clear();
      _busy = false;
      _stage = 1;
    });
  }

  Future<void> _retuneThreshold(double v) async {
    setState(() => _threshold = v);
    final similar = await _repo.findSimilar(_scopedIds, v);
    if (!mounted) return;
    setState(() {
      _similar = [for (final c in similar) c.rankedBy(_rule)];
      _discards.removeWhere((id) => !_visibleIds().contains(id));
    });
  }

  void _setRule(KeeperRule r) => setState(() {
        _rule = r;
        _exact = [for (final c in _exact) c.rankedBy(r)];
        _similar = [for (final c in _similar) c.rankedBy(r)];
      });

  Set<String> _visibleIds() =>
      {for (final c in [..._exact, ..._similar]) ...c.photoIds};

  void _autoSelect({required bool exact, required bool similar}) => setState(() {
        for (final c in _exact) {
          if (exact) _discards.addAll(c.discards);
        }
        for (final c in _similar) {
          if (similar) _discards.addAll(c.discards);
        }
      });

  void _toggleDiscard(String id) => setState(() {
        _discards.contains(id) ? _discards.remove(id) : _discards.add(id);
      });

  void _setKeeper(DupCluster c, String keeperId) => setState(() {
        DupCluster upd(DupCluster x) =>
            x.id == c.id ? x.copyWith(keeperId: keeperId) : x;
        _exact = [for (final x in _exact) upd(x)];
        _similar = [for (final x in _similar) upd(x)];
        _discards.remove(keeperId);
      });

  void _apply() {
    // Phase 1 (mock): drop quarantined photos from the visible clusters and
    // surface a summary. The native engine performs the real quarantine move.
    final n = _discards.length;
    setState(() {
      List<DupCluster> prune(List<DupCluster> cs) => [
            for (final c in cs)
              if (c.photoIds.where((p) => !_discards.contains(p)).length > 1)
                c.copyWith(
                    photoIds:
                        c.photoIds.where((p) => !_discards.contains(p)).toList()),
          ];
      _exact = prune(_exact);
      _similar = prune(_similar);
      _discards.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Quarantined $n photo(s) — moved to Quarantine, not deleted'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Container(
      color: PabloColors.backgroundShell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(st.closeFindDuplicates),
          Expanded(
            child: _stage == 0
                ? DedupScopeStage(
                    scope: _scope,
                    folderIds: _folderIds,
                    busy: _busy,
                    onScope: (s) => setState(() => _scope = s),
                    onToggleFolder: (id) => setState(() =>
                        _folderIds.contains(id) ? _folderIds.remove(id) : _folderIds.add(id)),
                    onScan: _scan,
                  )
                : DedupReviewStage(
                    exact: _exact,
                    similar: _similar,
                    index: _index,
                    threshold: _threshold,
                    rule: _rule,
                    discards: _discards,
                    onThreshold: _retuneThreshold,
                    onRule: _setRule,
                    onAutoSelect: _autoSelect,
                    onToggleDiscard: _toggleDiscard,
                    onSetKeeper: _setKeeper,
                    onApply: _apply,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(VoidCallback onClose) {
    final steps = ['Choose scope', 'Review & resolve'];
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: PabloSpacing.xxxl, vertical: PabloSpacing.xl),
      decoration: const BoxDecoration(
        color: PabloColors.backgroundSurface,
        border: Border(bottom: BorderSide(color: PabloColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text('Find Duplicates',
              style: PabloTypography.serif(
                  fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(width: PabloSpacing.xxxl),
          for (var i = 0; i < steps.length; i++) ...[
            Text('${i + 1}. ${steps[i]}',
                style: PabloTypography.sans(
                  fontSize: 12.5,
                  fontWeight: i == _stage ? FontWeight.w600 : FontWeight.w400,
                  color: i == _stage
                      ? PabloColors.accentPrimary
                      : PabloColors.textMuted,
                )),
            if (i < steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: PabloSpacing.base),
                child: Text('→', style: TextStyle(color: PabloColors.textMuted)),
              ),
          ],
          const Spacer(),
          if (_stage == 1)
            Padding(
              padding: const EdgeInsets.only(right: PabloSpacing.base),
              child: PabloButton(
                label: 'Back',
                variant: PabloButtonVariant.ghost,
                onPressed: () => setState(() => _stage = 0),
              ),
            ),
          PabloButton(
            label: 'Close',
            variant: PabloButtonVariant.secondary,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
