import 'package:flutter/material.dart';

import '../../backend/native_backend.dart';
import '../../components/pablo_button.dart';
import '../../data/library.dart';
import '../../theme/tokens.dart';
import '../../utils/asset_id.dart';

class TagsTab extends StatefulWidget {
  const TagsTab({required this.photoId, super.key});
  final String photoId;
  @override
  State<TagsTab> createState() => _TagsTabState();
}

class _TagsTabState extends State<TagsTab> {
  // Persisted (catalog) tags when a backend is mounted; otherwise an in-memory
  // model (_extra/_removedBase) for the offline/mock case.
  List<String> _base = const [];
  final List<String> _extra = [];
  final Set<String> _removedBase = {};
  final TextEditingController _ctl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  @override
  void didUpdateWidget(covariant TagsTab old) {
    super.didUpdateWidget(old);
    if (old.photoId != widget.photoId) {
      _ctl.clear();
      _reload();
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _reload() {
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    _base = engine != null
        ? engine.assetTags(assetIdFor(widget.photoId))
        : getPhotoTags(widget.photoId);
    _extra.clear();
    _removedBase.clear();
  }

  List<String> get _tags => [
        ..._base.where((t) => !_removedBase.contains(t)),
        ..._extra,
      ];

  void _add() {
    final t = _ctl.text.trim();
    if (t.isEmpty || _tags.contains(t)) return;
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    if (engine != null) {
      engine.addTag(assetIdFor(widget.photoId), t);
      setState(() {
        _ctl.clear();
        _reload();
      });
    } else {
      setState(() {
        _extra.add(t);
        _ctl.clear();
      });
    }
  }

  void _remove(String tag) {
    final engine = NativeBackendScope.maybeOf(context)?.engine;
    if (engine != null) {
      engine.removeTag(assetIdFor(widget.photoId), tag);
      setState(_reload);
    } else {
      setState(() {
        if (_extra.contains(tag)) {
          _extra.remove(tag);
        } else {
          _removedBase.add(tag);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = _tags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                'No tags yet.',
                style: PabloTypography.sans(
                  fontSize: 12,
                  color: PabloColors.textMuted,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: PabloSpacing.lg),
            child: Text(
              '${tags.length} tag${tags.length == 1 ? '' : 's'}',
              style: PabloTypography.sans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: PabloColors.textMuted,
                letterSpacing: 0.05 * 10,
              ).copyWith(height: 1.0),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: PabloSpacing.lg),
            child: Wrap(
              spacing: PabloSpacing.sm + 1,
              runSpacing: PabloSpacing.sm + 1,
              children: tags
                  .map((t) => Container(
                        padding: const EdgeInsets.fromLTRB(
                          PabloSpacing.lg, // 10
                          PabloSpacing.sm, // 4
                          PabloSpacing.base, // 8
                          PabloSpacing.sm, // 4
                        ),
                        decoration: BoxDecoration(
                          color: PabloColors.accentBackground,
                          border: Border.all(color: PabloColors.accentSoft),
                          borderRadius: PabloRadius.smAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              t,
                              style: PabloTypography.sans(
                                fontSize: 11.5,
                                color: PabloColors.accentPrimary,
                              ),
                            ),
                            const SizedBox(width: PabloSpacing.sm),
                            GestureDetector(
                              onTap: () => _remove(t),
                              child: Text(
                                '✕',
                                style: PabloTypography.sans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: PabloColors.accentPrimary,
                                ).copyWith(
                                  color: PabloColors.accentPrimary
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: PabloColors.backgroundSurface,
                  border: Border.all(color: PabloColors.borderSubtle),
                  borderRadius: PabloRadius.smAll,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: TextField(
                  controller: _ctl,
                  onSubmitted: (_) => _add(),
                  cursorColor: PabloColors.accentPrimary,
                  style: PabloTypography.sans(fontSize: 12),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Add tag…',
                    hintStyle: PabloTypography.sans(
                      fontSize: 12,
                      color: PabloColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            PabloButton(
              label: '+',
              variant: PabloButtonVariant.primary,
              size: PabloButtonSize.xs,
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}
