// UnnamedFacesPage — 3-tab flow for assigning / ignoring unclustered faces.

import 'package:flutter/material.dart';
import 'package:photo_native/photo_native.dart';

import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'face_naming.dart';
import 'people_controller.dart';
import 'people_scope.dart';
import 'widgets/groups_tab.dart';
import 'widgets/ignored_tab.dart';
import 'widgets/unclustered_tab.dart';
import 'widgets/unnamed_tabs.dart';

class UnnamedFacesPage extends StatefulWidget {
  const UnnamedFacesPage({super.key});

  @override
  State<UnnamedFacesPage> createState() => _UnnamedFacesPageState();
}

class _UnnamedFacesPageState extends State<UnnamedFacesPage> {
  UnnamedTabId _tab = UnnamedTabId.groups;
  final Map<String, String> _names = {};
  final Set<String> _assigned = {};
  final Set<String> _ignored = {};
  final Set<String> _ignoredSolo = {};
  final Set<String> _selectedSolos = {};
  final TextEditingController _bulkCtl = TextEditingController();

  // Unclustered (solo) faces would come from the pipeline; there is no
  // separate solo read-back yet, so this stays empty rather than synthesized.
  final List<UnnamedFace> _solos = const [];

  @override
  void dispose() {
    _bulkCtl.dispose();
    super.dispose();
  }

  Future<void> _assign(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final pc = PeopleScope.read(context);
    // Existing person → assign immediately; a brand-new name confirms first.
    if (!isExistingPerson(pc, trimmed) &&
        !await confirmNewPerson(context, trimmed)) {
      return;
    }
    // Live: promote the cluster into a named person (confirm-all + merge). The
    // clusterUpdated re-query drops it from listClusters; the overlay below
    // shows it as "assigned" until then.
    if (pc.isLive) {
      final clusterId = PeopleController.nativeClusterId(id);
      if (clusterId != null) pc.assignCluster(clusterId, trimmed);
    }
    if (!mounted) return;
    setState(() {
      _names[id] = trimmed;
      _assigned.add(id);
    });
  }

  void _toggleIgnore(String id) {
    setState(() {
      if (_ignored.contains(id)) {
        _ignored.remove(id);
      } else {
        _ignored.add(id);
      }
    });
  }

  void _toggleIgnoreSolo(String id) {
    setState(() {
      if (_ignoredSolo.contains(id)) {
        _ignoredSolo.remove(id);
      } else {
        _ignoredSolo.add(id);
      }
    });
  }

  void _toggleSelectSolo(String id, bool multi) {
    setState(() {
      if (!multi) {
        if (_selectedSolos.contains(id) && _selectedSolos.length == 1) {
          _selectedSolos.clear();
        } else {
          _selectedSolos
            ..clear()
            ..add(id);
        }
      } else {
        if (_selectedSolos.contains(id)) {
          _selectedSolos.remove(id);
        } else {
          _selectedSolos.add(id);
        }
      }
    });
  }

  void _bulkAssign() {
    final name = _bulkCtl.text.trim();
    if (name.isEmpty || _selectedSolos.isEmpty) return;
    setState(() {
      for (final id in _selectedSolos) {
        _names[id] = name;
        _assigned.add(id);
      }
      _selectedSolos.clear();
      _bulkCtl.clear();
    });
  }

  void _bulkIgnore() {
    setState(() {
      _ignoredSolo.addAll(_selectedSolos);
      _selectedSolos.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pc = PeopleScope.of(context);
    final clusters = pc.unnamedFaces();
    // Live clusters come through listClusters; there's no separate "solo"
    // (unclustered) concept, so that tab is mock-only.
    final solos = pc.isLive ? const <UnnamedFace>[] : _solos;
    FaceRow? coverOf(UnnamedFace f) {
      final cid = PeopleController.nativeClusterId(f.id);
      return cid == null ? null : pc.coverFace(cid);
    }

    final activeClusters = clusters
        .where((f) => !_ignored.contains(f.id) && !_assigned.contains(f.id))
        .toList();
    final assignedClusters =
        clusters.where((f) => _assigned.contains(f.id)).toList();
    final ignoredClusters =
        clusters.where((f) => _ignored.contains(f.id)).toList();
    final activeSolos =
        solos.where((f) => !_ignoredSolo.contains(f.id)).toList();
    final ignoredSolos =
        solos.where((f) => _ignoredSolo.contains(f.id)).toList();
    final totalIgnored = ignoredClusters.length + ignoredSolos.length;

    final tabs = [
      UnnamedTab(UnnamedTabId.groups, 'Face Groups',
          activeClusters.length + assignedClusters.length),
      UnnamedTab(UnnamedTabId.unclustered, 'Unclustered', activeSolos.length),
      UnnamedTab(UnnamedTabId.ignored, 'Ignored', totalIgnored),
    ];

    return Container(
      color: PabloColors.backgroundSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xxl,
              vertical: PabloSpacing.lg,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PabloColors.borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unnamed Faces',
                    style: PabloTypography.serif(fontSize: 16)),
                const SizedBox(height: 2),
                Text.rich(TextSpan(
                  children: [
                    TextSpan(
                      text: '${assignedClusters.length} assigned',
                      style: PabloTypography.sans(
                        fontSize: 12,
                        color: PabloColors.success,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' · ${activeClusters.length} groups · ${activeSolos.length} unclustered',
                      style: PabloTypography.sans(
                        fontSize: 12,
                        color: PabloColors.textMuted,
                      ),
                    ),
                  ],
                )),
              ],
            ),
          ),

          // Tab bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: PabloSpacing.xl,
              vertical: PabloSpacing.md,
            ),
            decoration: const BoxDecoration(
              color: PabloColors.backgroundSurfaceAlt,
              border: Border(
                bottom: BorderSide(color: PabloColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: UnnamedTabButton(
                      tab: tabs[i],
                      active: _tab == tabs[i].id,
                      onTap: () => setState(() => _tab = tabs[i].id),
                    ),
                  ),
              ],
            ),
          ),

          // Content — each tab is its own lazy CustomScrollView (cards, and the
          // native texture slots their cover crops hold, build on demand).
          Expanded(
            child: switch (_tab) {
              UnnamedTabId.groups => GroupsTab(
                  active: activeClusters,
                  done: assignedClusters,
                  names: _names,
                  coverOf: coverOf,
                  onAssign: _assign,
                  onIgnore: _toggleIgnore,
                ),
              UnnamedTabId.unclustered => UnclusteredTab(
                  active: activeSolos,
                  selectedIds: _selectedSolos,
                  bulkCtl: _bulkCtl,
                  onToggleSelect: _toggleSelectSolo,
                  onBulkAssign: _bulkAssign,
                  onBulkIgnore: _bulkIgnore,
                  onIgnoreSolo: _toggleIgnoreSolo,
                ),
              UnnamedTabId.ignored => IgnoredTab(
                  ignoredClusters: ignoredClusters,
                  ignoredSolos: ignoredSolos,
                  onRestoreCluster: _toggleIgnore,
                  onRestoreSolo: _toggleIgnoreSolo,
                  onRestoreAll: () {
                    setState(() {
                      _ignored.clear();
                      _ignoredSolo.clear();
                    });
                  },
                ),
            },
          ),
        ],
      ),
    );
  }
}
