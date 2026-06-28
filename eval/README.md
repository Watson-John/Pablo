# Face-model evaluation harness

Benchmarks 4 face-recognition models on **our** labeled face database and picks
the best *shippable* (permissively-licensed) one. Throwaway eval code — the app
is C++; only the winning config gets reimplemented there.

**Decision it produces:** ship **SFace** or **dlib** (both permissive), judged
against **buffalo_l** and **AdaFace** as non-shippable accuracy ceilings. If no
clean model is close enough, that's the evidence to revisit licensing.

## Plugs into the face DB we built

Phase 0 *is* [`eval/ingest`](ingest/) — its `faces_db/manifest.csv` +
`crops/<person>/` are exactly what every downstream phase reads (via
`common.load_face_db`). Point `config.yaml`'s `ingest.faces_db` at a built DB, or
run with `--ingest` to build it first.

```
eval/
  config.yaml          # single source of truth (paths, tolerances)
  common.py            # data contract: FaceEntry/Detection + ArcFace align + metrics utils
  run.py               # CLI orchestrator (phases 0-4)
  ingest/              # Phase 0 — Picasa -> faces_db (already built; see ingest/README.md)
  detect/yunet.py      # shared detector -> 5 landmarks
  embed/               # base.py + sface / dlib_resnet / arcface_onnx (buffalo_l + adaface)
  metrics/             # verification / identification / clustering / operating_point
  report/reporter.py   # master table + plots + decision
  tests/               # test_rect64 (ingest gate) + test_sanity (preprocessing gate)
  tools/download_models.sh
```

## Run

```bash
pip install -r requirements.txt          # (dlib optional — needs a toolchain)
bash tools/download_models.sh            # YuNet/SFace/buffalo_l/dlib into models/
# build the DB once (or point config at an existing one):
python run.py --config config.yaml --ingest
# or, DB already built:
python run.py --config config.yaml
```

Phases: **0** ingest → **1** YuNet detect (5 landmarks, quarantine misses, report
recall) → **2** embed per model (cached to `eval_out/embeddings_<model>.npz`) →
**3** metrics → **4** `eval_out/report.md`. Any model whose file/dep is missing is
skipped, so partial runs work (e.g. without dlib or AdaFace).

## The two parts that must be exactly right

1. **rect64 decode** (Picasa leading-zero gotcha) — in `ingest/picasa_ini.py`,
   gated by `ingest/tests/test_rect64.py`.
2. **Per-model preprocessing** — each embedder does its own alignment/color/norm
   (SFace `alignCrop`/BGR; dlib `get_face_chip`/RGB; buffalo_l RGB+`(x-127.5)/127.5`;
   AdaFace **BGR**+`(x/255-0.5)/0.5`). `tests/test_sanity.py` catches a wrong recipe
   (same-person pair must out-score a different-person pair). **Do not trust metrics
   past a failing sanity check.**

## Threshold calibration

Thresholds are calibrated on a **calibration split of identities** and all metrics
reported on a disjoint **held-out split** — never calibrate and score on the same
faces (`eval.calibration_split` in config).

## Decision rule

Ship the most permissive model (SFace > dlib) whose **TAR@FAR=1e-3 is within 1.5
pts of buffalo_l**, **cluster F1 within 0.03**, and **auto-accept error < 1%** at
prompt rate ≤ 15% (all in `config.yaml` → `decision`). Else the clean-model gap is
real — revisit buffalo_l licensing or synthetic training. **Veto:** a candidate
that fails badly on a hard subset (kids / age-gap / low-light) is disqualified.

> Our DB skews to a few heavily-photographed people (e.g. ~733 "Little John",
> Victoria across ages) — good for age-gap robustness, but small in identity count
> (17 people). Treat absolute TAR@FAR=1e-4 with caution and lean on the *gap to
> buffalo_l* and clustering metrics.
