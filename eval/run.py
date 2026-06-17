#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Face-model evaluation harness — CLI orchestrator.

Phases (each guarded so a partial environment still does useful work):
  0  ingest    (optional --ingest) build faces_db from the Picasa tree
  1  detect    YuNet -> 5 landmarks per crop; quarantine misses, report recall
  2  embed     per-model preprocessing -> cached embeddings_<model>.npz
  3  metrics    verification / identification / clustering / operating point
  4  report     master table + plots + decision -> report/report.md

  python run.py --config config.yaml                 # all phases
  python run.py --config config.yaml --only embed    # one phase (uses caches)
  python run.py --config config.yaml --ingest        # build faces_db first
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import (  # noqa: E402
    Detection, FaceEntry, group_by_person, load_face_db, load_image_bgr,
)


# --------------------------------------------------------------------- helpers

def _resolve(base: Path, p: str) -> Path:
    q = Path(p)
    return q if q.is_absolute() else (base / q)


def load_config(path: str) -> dict:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def log(msg: str) -> None:
    print(msg, flush=True)


# ------------------------------------------------------------------- phase 0/1

def phase_ingest(cfg: dict, base: Path) -> None:
    """Build faces_db from the Picasa tree by invoking eval/ingest."""
    sys.path.insert(0, str(base / "ingest"))
    import build_face_db  # noqa: E402  (our Phase-0 ingester)
    ing = cfg["ingest"]
    out = _resolve(base, ing["faces_db"])
    log(f"[phase 0] ingest {ing['picasa_root']} -> {out}")
    build_face_db.main([
        "--root", ing["picasa_root"], "--out", str(out),
        "--pad", str(ing.get("crop_padding", 0.2)), "--allow-in-repo",
    ])


def phase_detect(cfg: dict, base: Path, faces: List[FaceEntry]
                 ) -> Tuple[Dict[str, Detection], dict]:
    """Run YuNet on each crop -> Detection (5 landmarks). Quarantine misses."""
    from detect.yunet import YuNetDetector
    det = YuNetDetector(cfg["detector"], base)
    allow_fb = bool(cfg["detector"].get("fallback_full_crop", False))
    kept: Dict[str, Detection] = {}
    quality: Dict[str, dict] = {}     # face_id -> {face_px, blur}
    missed: List[str] = []
    n_fallback = 0
    for i, e in enumerate(faces):
        img = load_image_bgr(e.crop_path)
        d = det.detect_primary(img, allow_fallback=allow_fb) if img is not None else None
        if d is None:
            missed.append(e.face_id)
        else:
            kept[e.face_id] = d
            if d.score == 0.0:           # synthesized full-crop fallback
                n_fallback += 1
            # Per-face quality (Picasa's facequality): detected-face size +
            # sharpness. Used to gate recognition, not coverage.
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            quality[e.face_id] = {
                "face_px": float(min(d.bbox[2], d.bbox[3])),
                "blur": float(cv2.Laplacian(gray, cv2.CV_64F).var()),
            }
    n = max(1, len(faces))
    yunet_kept = len(kept) - n_fallback   # real YuNet detections
    yunet_recall = yunet_kept / n
    coverage = len(kept) / n
    log(f"[phase 1] YuNet recall: {yunet_recall:.3f} ({yunet_kept} real detections); "
        f"coverage {coverage:.3f} ({len(kept)} usable, {n_fallback} full-crop fallback, "
        f"{len(missed)} dropped)")
    return kept, {"recall": yunet_recall, "coverage": coverage,
                  "kept": len(kept), "yunet_kept": yunet_kept,
                  "fallback": n_fallback, "missed": len(missed),
                  "missed_ids": missed}, quality


# --------------------------------------------------------------------- phase 2

def phase_embed(cfg: dict, base: Path, faces: List[FaceEntry],
                dets: Dict[str, Detection], out_dir: Path
                ) -> Dict[str, Tuple[np.ndarray, List[str]]]:
    """Embed every kept face per model; cache to embeddings_<model>.npz."""
    from embed.base import build_embedder
    results: Dict[str, Tuple[np.ndarray, List[str]]] = {}
    by_id = {e.face_id: e for e in faces}
    for mcfg in cfg["models"]:
        name = mcfg["name"]
        cache = out_dir / f"embeddings_{name}.npz"
        if cache.exists():
            z = np.load(cache, allow_pickle=True)
            results[name] = (z["X"], list(z["ids"]))
            log(f"[phase 2] {name}: loaded {len(results[name][1])} cached vectors")
            continue
        try:
            extra = {}
            if mcfg.get("path"):                       # HOG has no model file
                extra["path"] = str(_resolve(base, mcfg["path"]))
            if mcfg.get("predictor"):
                extra["predictor"] = str(_resolve(base, mcfg["predictor"]))
            emb = build_embedder({**mcfg, **extra})
        except Exception as ex:  # noqa: BLE001 — a missing model/dep skips that model
            log(f"[phase 2] {name}: SKIPPED ({ex})")
            continue
        vecs, ids = [], []
        for fid, d in dets.items():
            img = load_image_bgr(by_id[fid].crop_path)
            if img is None:
                continue
            try:
                v = emb.embed(img, d)
            except Exception as ex:  # noqa: BLE001
                log(f"[phase 2] {name}: embed failed for {fid}: {ex}")
                continue
            vecs.append(np.asarray(v, np.float32).ravel())
            ids.append(fid)
        if not vecs:
            log(f"[phase 2] {name}: no embeddings produced")
            continue
        X = np.vstack(vecs)
        np.savez(cache, X=X, ids=np.array(ids, object))
        results[name] = (X, ids)
        log(f"[phase 2] {name}: embedded {len(ids)} faces (dim={X.shape[1]}) -> {cache.name}")
    return results


# --------------------------------------------------------------------- phase 3

def _identity_split(labels: List[str], frac: float, seed: int
                    ) -> Tuple[np.ndarray, np.ndarray]:
    """Split by IDENTITY (never the same person in both) -> (calib_mask, held_mask)."""
    rng = np.random.default_rng(seed)
    people = sorted(set(labels))
    rng.shuffle(people)
    n_calib = max(1, int(round(len(people) * frac)))
    calib_people = set(people[:n_calib])
    labels_arr = np.array(labels)
    calib_mask = np.array([l in calib_people for l in labels_arr])
    return calib_mask, ~calib_mask


def phase_metrics(cfg: dict, embeddings: Dict[str, Tuple[np.ndarray, List[str]]],
                  faces: List[FaceEntry], quality: Dict[str, dict]) -> dict:
    from metrics import verification, identification, clustering, operating_point
    ev = cfg["eval"]
    label_of = {e.face_id: e.person_name for e in faces}

    def quality_ok(fid: str) -> bool:
        if not ev.get("quality_gate", False):
            return True
        q = quality.get(fid)
        if q is None:
            return True
        return (q["face_px"] >= ev.get("min_face_px", 0) and
                q["blur"] >= ev.get("min_blur_var", 0.0))

    out: dict = {}
    for name, (X, ids) in embeddings.items():
        mcfg = next(m for m in cfg["models"] if m["name"] == name)
        metric = mcfg.get("metric", "cosine")
        # Quality-gate: identical face set across all models (gate is detector-
        # level, model-independent) -> a fair comparison on recognizable faces.
        keep = [k for k, i in enumerate(ids) if quality_ok(i)]
        n_gated = len(ids) - len(keep)
        X = X[keep]
        ids = [ids[k] for k in keep]
        y = [label_of[i] for i in ids]
        calib_mask, held_mask = _identity_split(y, ev["calibration_split"], ev["seed"])
        Xc, yc = X[calib_mask], list(np.array(y)[calib_mask])
        Xh, yh = X[held_mask], list(np.array(y)[held_mask])

        res = {"metric": metric, "role": mcfg.get("role"), "n": len(ids),
               "n_gated": n_gated, "dim": X.shape[1], "n_held": len(yh)}
        res["verification"] = verification.evaluate(
            Xc, yc, Xh, yh, metric=metric, far_targets=ev["far_targets"],
            impostor_ratio=ev["impostor_to_genuine_ratio"], seed=ev["seed"],
            bootstrap_ci=ev.get("bootstrap_ci", False))
        res["identification"] = identification.evaluate(Xh, yh, metric=metric)
        res["clustering"] = clustering.evaluate(
            Xh, yh, metric=metric, methods=ev["clustering"], seed=ev["seed"])
        res["operating_point"] = operating_point.evaluate(
            Xc, yc, Xh, yh, metric=metric,
            # Anchor the operating threshold at the SAME FAR the decision rule
            # uses (TAR@1e-3), not the strictest target — anchoring at 1e-4 sets
            # a conservative threshold that inflates false-rejects.
            far_target=max(ev["far_targets"]), uncertain_band=ev["uncertain_band"],
            seed=ev["seed"])
        out[name] = res
        v = res["verification"]
        log(f"[phase 3] {name}: AUC={v.get('auc', float('nan')):.4f} "
            f"EER={v.get('eer', float('nan')):.4f} "
            f"TAR@1e-3={v.get('tar_at_far', {}).get('0.001', float('nan')):.4f} "
            f"rank1={res['identification'].get('rank1', float('nan')):.4f}")
    return out


# --------------------------------------------------------------------- phase 4

def phase_report(cfg: dict, base: Path, metrics_out: dict, detect_stats: dict,
                 out_dir: Path) -> None:
    from report.reporter import write_report
    path = write_report(cfg, metrics_out, detect_stats, out_dir)
    log(f"[phase 4] report -> {path}")


# --------------------------------------------------------------------- driver

def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Face-model evaluation harness")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--faces-db", default=None,
                    help="override config's ingest.faces_db (point at any built DB)")
    ap.add_argument("--ingest", action="store_true", help="build faces_db first (phase 0)")
    ap.add_argument("--only", choices=["detect", "embed", "metrics", "report"],
                    help="run a single phase (uses caches for the rest)")
    args = ap.parse_args(argv)

    base = Path(args.config).resolve().parent
    cfg = load_config(args.config)
    if args.faces_db:
        cfg["ingest"]["faces_db"] = args.faces_db
    out_dir = _resolve(base, cfg["eval"]["output_dir"])
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.ingest:
        phase_ingest(cfg, base)

    manifest = _resolve(base, cfg["ingest"]["faces_db"]) / "manifest.csv"
    if not manifest.exists():
        log(f"error: {manifest} not found — run with --ingest or build the face DB first.")
        return 1
    faces = load_face_db(manifest)
    # Only keep people with enough faces to form genuine pairs.
    groups = group_by_person(faces)
    minf = cfg["eval"]["min_faces_per_person"]
    faces = [e for e in faces if len(groups[e.person_name]) >= minf]
    log(f"loaded {len(faces)} faces across {len(set(e.person_name for e in faces))} "
        f"people (>= {minf} faces each)")

    dets, detect_stats, quality = phase_detect(cfg, base, faces)
    embeddings = phase_embed(cfg, base, faces, dets, out_dir)
    if not embeddings:
        log("no embeddings produced (models missing?). See tools/download_models.sh")
        return 1
    metrics_out = phase_metrics(cfg, embeddings, faces, quality)
    phase_report(cfg, base, metrics_out, detect_stats, out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
