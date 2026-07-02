// model_fetcher.dart — first-run download of the SigLIP2 semantic-search
// models from GitHub Releases (Stage 9).
//
// The ONNX towers are far too large to ship inside the app bundle (~470 MB
// total), so they are published as release assets and fetched into the
// user-writable models dir (see models_dir.dart) on first run. Each file
// streams to `<dest>.part` with a running SHA-256, supports a single Range
// resume of an interrupted transfer (GitHub redirects release downloads to
// S3, which honors Range), and is renamed into place atomically only after
// the hash verifies. No retry loops — a failed attempt throws and the UI's
// Retry button simply calls [ModelFetcher.ensureModels] again, which resumes.

import 'dart:io';

import 'package:crypto/crypto.dart';

/// One downloadable model file: release [assetName] → models-dir [destName].
class ModelSpec {
  const ModelSpec({
    required this.assetName,
    required this.destName,
    required this.sha256,
    required this.bytes,
  });

  /// File name of the asset on the GitHub release.
  final String assetName;

  /// File name the engine expects inside the models dir.
  final String destName;

  /// Pinned lowercase-hex SHA-256 of the asset, or 'PENDING' before the
  /// release is cut (presence + non-zero size then counts as valid).
  final String sha256;

  /// Approximate size in bytes — the progress-UI total until Content-Length
  /// is known.
  final int bytes;
}

/// Per-chunk progress: [file] is the destination name, [received]/[total]
/// are bytes (received includes any resumed prefix).
typedef ModelProgress = void Function(String file, int received, int total);

class ModelFetchException implements Exception {
  ModelFetchException(this.message);
  final String message;
  @override
  String toString() => 'ModelFetchException: $message';
}

class ModelFetcher {
  ModelFetcher({this.baseUrl = releaseBase, List<ModelSpec>? specs})
      : specs = specs ?? defaultSpecs;

  /// GitHub release hosting the model assets.
  static const releaseBase =
      'https://github.com/Watson-John/Pablo/releases/download/models-v1';

  /// The SigLIP2 ship set — fp16 image tower + vocab-pruned int8 English text
  /// tower + SentencePiece tokenizer (see native/models/MANIFEST.md). sha256s
  /// are pinned to the models-v1 release assets (checksums.txt on the release
  /// carries the same digests).
  static const defaultSpecs = <ModelSpec>[
    ModelSpec(
      assetName: 'semantic_image.fp16.onnx',
      destName: 'semantic_image.onnx',
      sha256:
          '5af0a3ab1ab09fc9b93fe5ca7b5a4de81b71888a9148fb8a59b072470902a092',
      bytes: 186107375,
    ),
    ModelSpec(
      assetName: 'semantic_text_en.int8.onnx',
      destName: 'semantic_text.onnx',
      sha256:
          '9ae05e04425b3c384b23d64ac853ccfe0cf74f25f31d828f16beb14430a91b73',
      bytes: 117598988,
    ),
    ModelSpec(
      assetName: 'semantic_tokenizer.model',
      destName: 'semantic_tokenizer.model',
      sha256:
          '61a7b147390c64585d6c3543dd6fc636906c9af3865a5548f27f31aee1d4c8e2',
      bytes: 4241003,
    ),
  ];

  final String baseUrl;
  final List<ModelSpec> specs;

  /// The specs whose destination file is absent or fails verification —
  /// non-empty means the first-run download stage should be shown.
  Future<List<ModelSpec>> missing(Directory destDir) async {
    final out = <ModelSpec>[];
    for (final spec in specs) {
      if (!await _isValid(_destFile(destDir, spec), spec)) out.add(spec);
    }
    return out;
  }

  /// Download every missing model into [destDir]. Files already present with
  /// a matching sha256 (or non-empty, when the sha is 'PENDING') are skipped.
  /// Throws [ModelFetchException] on network failure or hash mismatch; the
  /// `.part` file is kept so the next call resumes.
  Future<void> ensureModels(Directory destDir,
      {ModelProgress? onProgress}) async {
    await destDir.create(recursive: true);
    for (final spec in specs) {
      final dest = _destFile(destDir, spec);
      if (await _isValid(dest, spec)) continue;
      await _fetch(spec, dest, onProgress);
    }
  }

  File _destFile(Directory dir, ModelSpec spec) =>
      File('${dir.path}${Platform.pathSeparator}${spec.destName}');

  Future<bool> _isValid(File f, ModelSpec spec) async {
    if (!await f.exists()) return false;
    if (spec.sha256 == 'PENDING') return await f.length() > 0;
    final digest = await sha256.bind(f.openRead()).first;
    return digest.toString() == spec.sha256;
  }

  Future<void> _fetch(ModelSpec spec, File dest, ModelProgress? on) async {
    final part = File('${dest.path}.part');
    final offset = await part.exists() ? await part.length() : 0;
    try {
      await _transfer(spec, part, offset, on);
    } on ModelFetchException {
      rethrow;
    } catch (e) {
      // Keep the .part — the next attempt resumes from it.
      throw ModelFetchException('${spec.assetName}: download failed: $e');
    }
    if (await part.length() == 0) {
      throw ModelFetchException('${spec.assetName}: empty download');
    }
    await part.rename(dest.path); // atomic swap into place
  }

  /// One transfer: resume from [offset] when a .part exists (single Range
  /// attempt); a 416 or a server that ignores Range restarts from scratch.
  Future<void> _transfer(
      ModelSpec spec, File part, int offset, ModelProgress? on) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse('$baseUrl/${spec.assetName}');
      var resume = offset > 0;
      var resp = await _get(client, uri, resume ? offset : null);
      if (resume &&
          resp.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // .part covers (or exceeds) the asset but never verified — restart.
        await _drain(resp);
        resume = false;
        resp = await _get(client, uri, null);
      }
      if (resume && resp.statusCode == HttpStatus.ok) {
        resume = false; // server ignored Range; full body follows
      }
      if (resp.statusCode != HttpStatus.ok &&
          resp.statusCode != HttpStatus.partialContent) {
        await _drain(resp);
        throw ModelFetchException(
            '${spec.assetName}: HTTP ${resp.statusCode} from $uri');
      }

      final digestOut = _DigestSink();
      final hash = sha256.startChunkedConversion(digestOut);
      var received = 0;
      if (resume) {
        // The running hash must cover the kept prefix.
        await part.openRead().forEach(hash.add);
        received = offset;
      }
      final len = resp.contentLength;
      final total = len > 0 ? received + len : spec.bytes;
      final io =
          part.openWrite(mode: resume ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in resp) {
          io.add(chunk);
          hash.add(chunk);
          received += chunk.length;
          on?.call(
              spec.destName, received, total < received ? received : total);
        }
      } finally {
        await io.close();
      }
      hash.close();
      final got = digestOut.value.toString();
      if (spec.sha256 != 'PENDING' && got != spec.sha256) {
        // Keep the .part: the next attempt's Range points past EOF, gets a
        // 416, and restarts clean — self-healing without a retry loop here.
        throw ModelFetchException(
            '${spec.destName}: SHA-256 mismatch (expected ${spec.sha256}, '
            'got $got)');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _get(
      HttpClient client, Uri uri, int? rangeStart) async {
    final req = await client.getUrl(uri);
    req.followRedirects = true; // GitHub release assets 302 → S3
    req.maxRedirects = 8;
    if (rangeStart != null) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-');
    }
    return req.close();
  }

  Future<void> _drain(HttpClientResponse resp) async {
    try {
      await resp.drain<void>();
    } catch (_) {}
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
