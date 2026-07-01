// model_download_stage.dart — the "Downloading search model" first-run stage.
//
// Rendered by FirstRunIndexingScreen ABOVE the indexing phases when the
// semantic-search model files are not yet present (ModelFetcher.missing).
// One row per file with a progress bar and MB counters, an error state with
// Retry, and a Skip escape hatch — search still works without the model via
// the built-in fallback embedder, just with reduced quality.

import 'package:flutter/material.dart';

import '../../components/pablo_button.dart';
import '../../data/model_fetcher.dart';
import '../../theme/tokens.dart';

/// Runs one download pass, reporting per-file progress. Injected so the app
/// binds it to [ModelFetcher.ensureModels] while widget tests fake it.
typedef ModelDownload = Future<void> Function(ModelProgress onProgress);

class ModelDownloadStage extends StatefulWidget {
  const ModelDownloadStage({
    required this.download,
    required this.onComplete,
    required this.onSkip,
    this.specs = ModelFetcher.defaultSpecs,
    super.key,
  });

  /// Kicks off (or retries) the download; completes when all files verify.
  final ModelDownload download;

  /// All files downloaded and verified.
  final VoidCallback onComplete;

  /// User chose to continue without the model.
  final VoidCallback onSkip;

  /// The files shown as progress rows (keyed by [ModelSpec.destName]).
  final List<ModelSpec> specs;

  @override
  State<ModelDownloadStage> createState() => _ModelDownloadStageState();
}

class _ModelDownloadStageState extends State<ModelDownloadStage> {
  final Map<String, (int, int)> _progress = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await widget.download(_onChunk);
      if (mounted) widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ModelFetchException ? e.message : '$e');
    }
  }

  void _onChunk(String file, int received, int total) {
    if (!mounted) return;
    setState(() => _progress[file] = (received, total));
  }

  void _retry() {
    setState(() => _error = null);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Downloading search model',
          style: PabloTypography.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: PabloSpacing.sm),
        Text(
          'A one-time download so search understands what is in your photos. '
          'Resumes automatically if interrupted.',
          style: PabloTypography.sans(
            fontSize: 11,
            color: PabloColors.textMuted,
            height: 1.4,
          ),
        ),
        const SizedBox(height: PabloSpacing.lg),
        for (final spec in widget.specs) ...[
          _FileRow(spec: spec, progress: _progress[spec.destName]),
          const SizedBox(height: PabloSpacing.lg),
        ],
        if (_error != null) ...[
          _ErrorBox(message: _error!, onRetry: _retry),
          const SizedBox(height: PabloSpacing.base),
        ],
        TextButton(
          onPressed: widget.onSkip,
          child: Text(
            'Skip — search works without it, with reduced quality',
            style: PabloTypography.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: PabloColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.spec, required this.progress});

  final ModelSpec spec;
  final (int, int)? progress;

  @override
  Widget build(BuildContext context) {
    final received = progress?.$1 ?? 0;
    final total = progress?.$2 ?? spec.bytes;
    final value = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                spec.destName,
                style: PabloTypography.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: PabloColors.textSecondary,
                ),
              ),
            ),
            Text(
              '${_mb(received)} / ${_mb(total)} MB',
              style: PabloTypography.mono(fontSize: 10.5),
            ),
          ],
        ),
        const SizedBox(height: PabloSpacing.sm),
        ClipRRect(
          borderRadius: PabloRadius.pillAll,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: PabloColors.backgroundActive,
            valueColor: const AlwaysStoppedAnimation(PabloColors.accentPrimary),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PabloSpacing.xl),
      decoration: const BoxDecoration(
        color: PabloColors.errorBackground,
        borderRadius: PabloRadius.smAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Download failed',
            style: PabloTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PabloColors.errorText,
            ),
          ),
          const SizedBox(height: PabloSpacing.sm),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: PabloTypography.sans(
              fontSize: 11,
              color: PabloColors.errorText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: PabloSpacing.lg),
          PabloButton(
            label: 'Retry',
            variant: PabloButtonVariant.secondary,
            size: PabloButtonSize.xs,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
