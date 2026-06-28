#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Measure license-clean, training-free boosts to SFace on OUR faces.

Compares, on the same faces + identity split, under one consistent protocol:
  - baseline        : SFace cosine
  - +TTA            : embed(face) + embed(hflip) averaged, re-normalized
  - +whiten         : PCA-whitening fit on the calibration split (clustering aid)
  - +ASnorm         : adaptive symmetric score normalization (TAR@FAR aid)
  - +TTA+whiten     : the stackable clean combo

Targets the two weak spots: TAR@FAR=1e-3 and clustering F1. None of this touches
the non-commercial ceiling models — it's all SFace (Apache-2.0) + our labels.
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from common import load_face_db, load_image_bgr, l2_normalize          # noqa: E402
from detect.yunet import YuNetDetector                                  # noqa: E402
from embed.base import build_embedder                                   # noqa: E402
from metrics import clustering                                          # noqa: E402
import yaml                                                             # noqa: E402

DB = "/tmp/full_db/manifest.csv"
SEED, FRAC, FAR = 1234, 0.4, 1e-3
cfg = yaml.safe_load(open(ROOT / "config.yaml"))


# ----------------------------------------------------------------- split + pairs
def identity_split(y):
    rng = np.random.default_rng(SEED)
    ppl = sorted(set(y)); rng.shuffle(ppl)
    calib = set(ppl[: max(1, int(len(ppl) * FRAC))])
    m = np.array([p in calib for p in y])
    return m, ~m


def make_pairs(y, ratio=10):
    rng = np.random.default_rng(SEED)
    idx_by = {}
    for i, p in enumerate(y):
        idx_by.setdefault(p, []).append(i)
    gen = [(a, b) for p in idx_by for k, a in enumerate(idx_by[p]) for b in idx_by[p][k + 1:]]
    alli = np.arange(len(y))
    imp = []
    target = len(gen) * ratio
    while len(imp) < target:
        a, b = int(rng.integers(len(y))), int(rng.integers(len(y)))
        if a != b and y[a] != y[b]:
            imp.append((a, b))
    return gen, imp


def roc_tar(gen_scores, imp_scores, far=FAR):
    from sklearn.metrics import roc_auc_score
    s = np.concatenate([gen_scores, imp_scores])
    lab = np.concatenate([np.ones(len(gen_scores)), np.zeros(len(imp_scores))])
    auc = float(roc_auc_score(lab, s))
    thr = np.quantile(imp_scores, 1.0 - far)          # threshold at FAR
    tar = float(np.mean(gen_scores >= thr))
    return auc, tar


def cos(X, a, b):
    return float(X[a] @ X[b])


# ---------------------------------------------------------------------- AS-norm
def asnorm_scores(X, pairs, cohort, topk=100):
    """Adaptive symmetric norm: normalize each pair score by each end's stats
    against its top-k most-similar cohort (impostor) faces."""
    # Precompute per-row cohort mean/std over the top-k cohort similarities.
    sims = X @ cohort.T                                # (N, |cohort|)
    topk = min(topk, cohort.shape[0])
    part = np.sort(sims, axis=1)[:, -topk:]
    mu = part.mean(axis=1); sd = part.std(axis=1) + 1e-6
    out = np.empty(len(pairs), np.float32)
    for i, (a, b) in enumerate(pairs):
        s = float(X[a] @ X[b])
        out[i] = 0.5 * ((s - mu[a]) / sd[a] + (s - mu[b]) / sd[b])
    return out


# -------------------------------------------------------------------- whitening
def fit_whiten(Xc, shrink=0.1, k=None):
    mu = Xc.mean(0)
    Xc0 = Xc - mu
    cov = np.cov(Xc0, rowvar=False)
    cov = (1 - shrink) * cov + shrink * np.eye(cov.shape[0]) * np.trace(cov) / cov.shape[0]
    w, V = np.linalg.eigh(cov)
    order = np.argsort(w)[::-1]
    w, V = w[order], V[:, order]
    if k:
        w, V = w[:k], V[:, :k]
    W = V @ np.diag(1.0 / np.sqrt(w + 1e-6))
    return mu, W


def apply_whiten(X, mu, W):
    return l2_normalize((X - mu) @ W)


# ------------------------------------------------------------------- evaluation
def evaluate(name, Xh, yh, gen, imp, score_fn):
    gs = np.array([score_fn(Xh, a, b) for a, b in gen], np.float32)
    is_ = np.array([score_fn(Xh, a, b) for a, b in imp], np.float32)
    auc, tar = roc_tar(gs, is_)
    cl = clustering.evaluate(Xh, yh, metric="cosine", methods=["dbscan", "chinese_whispers"], seed=SEED)
    f1 = max((cl[m].get("pairwise_f1", float("nan")) for m in cl if isinstance(cl.get(m), dict)),
             default=float("nan"))
    print(f"  {name:14s}  AUC={auc:.4f}  TAR@1e-3={tar:.4f}  clusterF1={f1:.4f}")
    return auc, tar, f1


def main():
    faces = load_face_db(DB)
    label_of = {f.face_id: f.person_name for f in faces}
    z = np.load(ROOT / "eval_out/embeddings_sface.npz", allow_pickle=True)
    X = z["X"].astype(np.float32); ids = [str(i) for i in z["ids"]]
    y = np.array([label_of[i] for i in ids])
    cm, hm = identity_split(y)
    Xc, Xh, yh = X[cm], X[hm], list(y[hm])
    gen, imp = make_pairs(yh)
    print(f"SFace boosts — {len(ids)} faces, held {hm.sum()} ({len(set(yh))} ppl), "
          f"{len(gen)} genuine / {len(imp)} impostor pairs\n")

    print("[baseline + score-only tricks]")
    evaluate("baseline", Xh, yh, gen, imp, cos)
    # AS-norm uses the calib split as the impostor cohort.
    asn_g = asnorm_scores  # alias
    gs = asnorm_scores(Xh, gen, Xc); is_ = asnorm_scores(Xh, imp, Xc)
    auc, tar = roc_tar(gs, is_)
    cl = clustering.evaluate(Xh, yh, metric="cosine", methods=["dbscan", "chinese_whispers"], seed=SEED)
    f1 = max((cl[m].get("pairwise_f1", float("nan")) for m in cl if isinstance(cl.get(m), dict)), default=float("nan"))
    print(f"  {'+ASnorm':14s}  AUC={auc:.4f}  TAR@1e-3={tar:.4f}  clusterF1={f1:.4f}  (clusterF1 unchanged: ASnorm is score-level)")

    # Whitening (embedding-level) — fit on calib.
    mu, W = fit_whiten(Xc)
    Xh_w = apply_whiten(Xh, mu, W)
    print("\n[embedding-level tricks]")
    evaluate("+whiten", Xh_w, yh, gen, imp, cos)

    # TTA — re-embed SFace with horizontal flip.
    print("\n[TTA — re-embedding SFace(face)+SFace(flip)] ...")
    det = YuNetDetector(cfg["detector"], ROOT)
    sf = build_embedder({"name": "sface", "type": "sface", "metric": "cosine",
                         "path": str(ROOT / "models/face_recognition_sface_2021dec.onnx")})
    by_id = {f.face_id: f for f in faces}
    tta = {}
    for i in ids:
        img = load_image_bgr(by_id[i].crop_path)
        if img is None:
            continue
        d = det.detect_primary(img)
        if d is None:
            continue
        flip = cv2.flip(img, 1)
        df = det.detect_primary(flip)
        v = sf.embed(img, d)
        if df is not None:
            v = l2_normalize(v + sf.embed(flip, df))
        tta[i] = v
    Xt = np.array([tta.get(i, X[k]) for k, i in enumerate(ids)], np.float32)
    Xt_h = Xt[hm]
    evaluate("+TTA", Xt_h, yh, gen, imp, cos)
    # TTA + whiten (fit whiten on TTA calib)
    mu2, W2 = fit_whiten(Xt[cm])
    evaluate("+TTA+whiten", apply_whiten(Xt_h, mu2, W2), yh, gen, imp, cos)


if __name__ == "__main__":
    main()
