// first_run_indexing_screen.dart — the safe first-launch indexing UI (Stage 9).
//
// On a large first launch we do NOT render the full image grid while facial
// recognition + semantic embedding run — instead this screen shows clear,
// separate progress for each pass with completed/pending/skipped/failed counts,
// and lets the user drop the indexing to the background at any time. Indexing is
// resumable, so "Continue in background" (or quitting) never loses progress.

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/indexing/indexing_controller.dart';
import '../../data/models.dart';
import '../../theme/tokens.dart';
import 'model_download_stage.dart';

class FirstRunIndexingScreen extends StatefulWidget {
  const FirstRunIndexingScreen({
    super.key,
    this.needsModelDownload = false,
    this.modelDownload,
    this.onModelsReady,
    this.onModelStageResolved,
  });

  /// When true (and [modelDownload] is provided) the "Downloading search
  /// model" stage renders above the indexing phases until it completes or is
  /// skipped. The caller decides via ModelFetcher.missing().
  final bool needsModelDownload;

  /// Drives the download — the app binds ModelFetcher.ensureModels over the
  /// merged models dir; widget tests fake it.
  final ModelDownload? modelDownload;

  /// Fired once the download completes and verifies (not on skip) — the hook
  /// for notifying the engine that model files just appeared.
  final VoidCallback? onModelsReady;

  /// Fired when the model stage stops blocking, whether by a verified download
  /// OR by the user skipping — the gate for starting the indexing pass.
  final VoidCallback? onModelStageResolved;

  @override
  State<FirstRunIndexingScreen> createState() => _FirstRunIndexingScreenState();
}

class _FirstRunIndexingScreenState extends State<FirstRunIndexingScreen> {
  bool _modelStageDone = false;

  bool get _showModelStage =>
      widget.needsModelDownload &&
      !_modelStageDone &&
      widget.modelDownload != null;

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final indexing = st.indexing;
    // The face pass reports through the shared task list (id 'face-scan').
    TaskInfo? faceTask;
    for (final t in st.tasks) {
      if (t.id == 'face-scan') {
        faceTask = t;
        break;
      }
    }

    return Container(
      color: PabloColors.backgroundShell,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(PabloSpacing.xxxxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(PabloSpacing.xxxxl),
          decoration: BoxDecoration(
            color: PabloColors.backgroundSurface,
            borderRadius: PabloRadius.panelAll,
            boxShadow: PabloShadows.lg,
          ),
          // Scrolls if the (optional) model-download stage makes the card
          // taller than a min-height window; sizes to content otherwise.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preparing your library',
                  style: PabloTypography.serif(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: PabloSpacing.base),
                Text(
                  'Pablo is analysing your photos so search, people, and '
                  'discovery work fully. This runs once and resumes safely if '
                  'interrupted.',
                  style: PabloTypography.sans(
                    fontSize: 12.5,
                    color: PabloColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: PabloSpacing.xxxl),
                if (_showModelStage) ...[
                  ModelDownloadStage(
                    download: widget.modelDownload!,
                    onComplete: () {
                      setState(() => _modelStageDone = true);
                      widget.onModelsReady?.call();
                      widget.onModelStageResolved?.call();
                    },
                    onSkip: () {
                      setState(() => _modelStageDone = true);
                      widget.onModelStageResolved?.call();
                    },
                  ),
                  const SizedBox(height: PabloSpacing.xxl),
                ],
                _FacePhase(task: faceTask),
                const SizedBox(height: PabloSpacing.xxl),
                if (indexing != null)
                  AnimatedBuilder(
                    animation: indexing,
                    builder: (_, __) =>
                        _EmbedPhase(progress: indexing.progress),
                  )
                else
                  const _EmbedPhase(progress: null),
                const SizedBox(height: PabloSpacing.xxxl),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => st.setShowIndexingScreen(false),
                    child: Text(
                      'Continue in background →',
                      style: PabloTypography.sans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: PabloColors.accentPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FacePhase extends StatelessWidget {
  const _FacePhase({required this.task});
  final TaskInfo? task;

  @override
  Widget build(BuildContext context) {
    final pct = (task?.percent ?? 100) / 100.0;
    final done = task == null || pct >= 1.0;
    return _PhaseCard(
      title: 'Facial recognition',
      value: done ? 1.0 : pct.clamp(0.0, 1.0),
      trailing: done ? 'Done' : '${((task?.percent ?? 0)).round()}%',
      caption: done
          ? 'People are grouped and ready.'
          : 'Finding and grouping faces…',
    );
  }
}

class _EmbedPhase extends StatelessWidget {
  const _EmbedPhase({required this.progress});
  final IndexingProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) {
      return const _PhaseCard(
        title: 'Semantic index',
        value: 0,
        trailing: 'Queued',
        caption: 'Waiting to start after faces…',
      );
    }
    return _PhaseCard(
      title: 'Semantic index',
      value: p.fraction,
      trailing: p.isDone ? 'Done' : '${(p.fraction * 100).round()}%',
      caption: 'Completed ${p.completed} · Pending ${p.pending} · '
          'Skipped ${p.skipped} · Failed ${p.failed}',
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.title,
    required this.value,
    required this.trailing,
    required this.caption,
  });

  final String title;
  final double value;
  final String trailing;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: PabloTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PabloColors.textPrimary,
                ),
              ),
            ),
            Text(
              trailing,
              style: PabloTypography.mono(
                fontSize: 11,
                color: PabloColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: PabloSpacing.sm),
        ClipRRect(
          borderRadius: PabloRadius.pillAll,
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: PabloColors.backgroundActive,
            valueColor: const AlwaysStoppedAnimation(PabloColors.accentPrimary),
          ),
        ),
        const SizedBox(height: PabloSpacing.sm),
        Text(
          caption,
          style: PabloTypography.sans(
            fontSize: 11,
            color: PabloColors.textMuted,
          ),
        ),
      ],
    );
  }
}
