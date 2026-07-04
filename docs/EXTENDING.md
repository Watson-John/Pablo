# Extending Pablo

> **Status: NOT yet a stable third-party API.** These are the internal
> extension points a future add-on SDK will formalize (manifest loading,
> versioned ABI, sandboxing — see `docs/FUTURE_WORK.md`). Today, extensions
> are registered at compile time. The seams exist so that new capabilities —
> and eventually plugins — land without rework.

Pablo has three extension seams, one per kind of capability:

| Seam | Language | Add when you want… | Example |
|---|---|---|---|
| `IImageAnalyzer` | C++ | to compute something from an asset's **pixels** and persist it | meme detection, aesthetic score, duplicate fingerprint |
| `ExternalAction` | Dart | a context-menu action that hands photos to **something outside Pablo** | "Open in Photoshop", upload to a service |
| `FaceModelProfile` / semantic `Embedder` | C++ | to swap the **ML models** behind an existing built-in capability | a faster face embedder, a better CLIP variant |

## 1. Image analyzers (`native/core/src/runtime/analyzer.h`)

An analyzer looks at decoded pixels and produces a small JSON payload:

```cpp
class MemeDetector final : public photo::runtime::IImageAnalyzer {
public:
    const std::string& id() const override {
        static const std::string k = "meme.detector"; return k;
    }
    const std::string& version() const override {   // bump ⇒ old rows stale
        static const std::string k = "1"; return k;
    }
    bool available() const override { return model_loaded_; }
    photo::runtime::AnalyzerResult analyze(
        int64_t asset_id, const photo::semantic::PixelView& px) override {
        const float score = run_model(px);          // your inference
        return {0, "{\"meme\":" + std::string(score > 0.5 ? "true" : "false") +
                   ",\"score\":" + std::to_string(score) + "}"};
    }
};
```

Register during engine construction (`Engine::analyzers().register_analyzer(...)`).

**Storage contract** — results persist in the catalog's generic `analysis`
table: `(analyzer_id, asset_id) PRIMARY KEY → (version, status, payload,
updated_ns)` with `ON DELETE CASCADE` from `asset`. Status: `0` pending, `1`
done, `2` failed. New analyzers never need a schema migration; the payload
JSON schema is each analyzer's own contract. A row whose `version` differs
from the analyzer's current `version()` is **stale** and should be re-run —
the same rule the semantic embedder uses.

**Execution contract** — `photo_analyzer_run` writes the pending row
synchronously and schedules decode + `analyze()` on the idle job lane (it
never competes with scrolling). `analyze()` runs off the catalog lock and must
be thread-safe against itself. Pixels arrive as a borrowed RGBA view bounded
to 1024 px on the long edge, decoded by the same codec as the semantic
indexer (`SemanticService::decode_rgba`).

**C ABI / Dart** — `photo_analyzer_list` / `photo_analyzer_run` /
`photo_analysis_get`; Dart: `Engine.listAnalyzers()` / `runAnalyzer()` /
`analysisFor()` (poll: pending → done/failed). Payload-opaque on purpose so
the ABI never grows per-analyzer.

## 2. External actions (`pablo/lib/data/sources/external_actions.dart`)

A user-visible context-menu action that hands the selected photos to
something outside Pablo:

```dart
ExternalActionRegistry.register(ExternalAction(
  id: 'com.example.open-photoshop',
  label: 'Open in Photoshop',
  iconCharacter: '🎨',
  canRun: (paths) => Platform.isMacOS,
  run: (paths) async {
    for (final p in paths) {
      await Process.run('open', ['-a', 'Adobe Photoshop', p]);
    }
  },
));
```

The gallery context menu renders the registry in order; multi-target actions
get the selection count appended, `singleTarget: true` actions receive only
the clicked photo (e.g. reveal-in-file-manager). `register()` is idempotent
by id. Built-ins registered today: `pablo.reveal`, `pablo.open-default`.

## 3. Swappable models

Built-in ML capabilities are already profile/interface driven — a new model
is data + one table row, not a code edit through the services:

- **Faces** (`native/core/src/faces/model_registry.h`): add a
  `FaceModelProfile` row (files, dim, preprocessing, thresholds) to
  `face_model_profiles()`. The first profile whose model files exist in the
  models dir becomes active; rows embedded by other profiles are stale
  (excluded from prototypes; Settings offers "Rebuild face index").
  Per-profile vector files make a dim change safe.
- **Semantic search** (`native/core/src/semantic/embedder.h`): implement
  `Embedder` (image + text into ONE space) and return it from the probe in
  `make_onnx_embedder`. Model id/version are tracked per embedding row;
  stale rows re-queue automatically.

## What belongs where

- Pixels → persisted data: **analyzer**.
- Menu action → external app/service: **external action**.
- Better model behind an existing feature: **profile/embedder row**.
- New UI surface (panel, view): not an extension point yet — that's app code
  (see `pablo/CLAUDE.md` for the feature-folder conventions).

Faces and semantic search predate the analyzer seam and keep their bespoke
storage + eventing; they migrate to it if/when the real SDK lands.
