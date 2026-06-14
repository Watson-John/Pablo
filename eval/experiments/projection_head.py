#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""License-clean domain adaptation: a small projection head on FROZEN shippable
embeddings (SFace / AuraFace), trained on OUR labels with a CosFace margin loss.

This is the clean version of "transfer learning to boost the shippable model":
no non-commercial teacher — just the Apache embedder (frozen) + your family's
labels. Evaluated CLOSED-SET (the app's real job): split each person's faces into
train/test by IMAGE, train the head on train, measure on held-out images of the
SAME people. Reports baseline vs +head on TAR@1e-3, cluster F1, rank-1.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from sklearn.metrics import roc_auc_score

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from common import load_face_db  # noqa: E402
from metrics import clustering  # noqa: E402

DB = "/tmp/full_db/manifest.csv"
EMB = ["sface", "auraface"]
SEEDS = [0, 1, 2]
FAR = 1e-3


def load(name):
    z = np.load(ROOT / f"eval_out/embeddings_{name}.npz", allow_pickle=True)
    return z["X"].astype(np.float32), [str(i) for i in z["ids"]]


def closed_split(y, seed, train_frac=0.6):
    """Per-person image split: same identities in train and test (closed-set)."""
    rng = np.random.default_rng(seed)
    train = np.zeros(len(y), bool)
    for p in set(y):
        idx = np.where(y == p)[0]; rng.shuffle(idx)
        train[idx[: max(1, int(len(idx) * train_frac))]] = True
    return train, ~train


def pairs(y, seed, ratio=10):
    rng = np.random.default_rng(seed)
    by = {}
    for i, p in enumerate(y):
        by.setdefault(p, []).append(i)
    gen = [(a, b) for p in by for k, a in enumerate(by[p]) for b in by[p][k + 1:]]
    imp = []
    while len(imp) < len(gen) * ratio:
        a, b = int(rng.integers(len(y))), int(rng.integers(len(y)))
        if a != b and y[a] != y[b]:
            imp.append((a, b))
    return gen, imp


def verif(X, gen, imp):
    g = np.array([X[a] @ X[b] for a, b in gen])
    i = np.array([X[a] @ X[b] for a, b in imp])
    auc = float(roc_auc_score(np.r_[np.ones(len(g)), np.zeros(len(i))], np.r_[g, i]))
    thr = np.quantile(i, 1 - FAR)
    return auc, float((g >= thr).mean())


def rank1(Xq, yq, Xg, yg):
    S = Xq @ Xg.T
    nn_idx = S.argmax(1)
    return float(np.mean([yg[j] == yq[k] for k, j in enumerate(nn_idx)]))


def cluster_f1(X, y):
    r = clustering.evaluate(X, list(y), metric="cosine",
                            methods=["agglomerative"], seed=0)
    return r["agglomerative"]["pairwise_f1"]


class Head(nn.Module):
    def __init__(self, d, out=128, p=0.3):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(d, d), nn.BatchNorm1d(d), nn.ReLU(), nn.Dropout(p),
            nn.Linear(d, out), nn.BatchNorm1d(out))

    def forward(self, x):
        return F.normalize(self.net(x), dim=1)


class CosFace(nn.Module):
    def __init__(self, out, n_cls, s=16.0, m=0.25):
        super().__init__()
        self.W = nn.Parameter(F.normalize(torch.randn(n_cls, out), dim=1))
        self.s, self.m = s, m

    def forward(self, emb, lab):
        cos = emb @ F.normalize(self.W, dim=1).t()
        margin = torch.zeros_like(cos).scatter_(1, lab.view(-1, 1), self.m)
        return self.s * (cos - margin)


def train_head(Xtr, ytr, d, n_cls, out=128, epochs=200, seed=0):
    torch.manual_seed(seed)
    head, cosface = Head(d, out), CosFace(out, n_cls)
    opt = torch.optim.AdamW(list(head.parameters()) + list(cosface.parameters()),
                            lr=1e-3, weight_decay=5e-4)
    Xt = torch.from_numpy(Xtr); yt = torch.from_numpy(ytr)
    head.train()
    for _ in range(epochs):
        opt.zero_grad()
        loss = F.cross_entropy(cosface(head(Xt), yt), yt)
        loss.backward(); opt.step()
    head.eval()
    return head


def apply_head(head, X):
    with torch.no_grad():
        return F.normalize(head(torch.from_numpy(X.astype(np.float32))), dim=1).numpy()


def main():
    label_of = {f.face_id: f.person_name for f in load_face_db(DB)}
    for name in EMB:
        X, ids = load(name)
        y = np.array([label_of[i] for i in ids])
        classes = sorted(set(y)); cls_idx = {c: k for k, c in enumerate(classes)}
        print(f"== {name}  ({len(ids)} faces, {len(classes)} people) ==")
        base, head_res = {"tar": [], "f1": [], "r1": []}, {"tar": [], "f1": [], "r1": []}
        for seed in SEEDS:
            tr, te = closed_split(y, seed)
            Xtr, ytr, Xte, yte = X[tr], y[tr], X[te], y[te]
            ytr_i = np.array([cls_idx[c] for c in ytr], np.int64)
            gen, imp = pairs(yte, seed)
            # baseline
            _, btar = verif(Xte, gen, imp)
            base["tar"].append(btar); base["f1"].append(cluster_f1(Xte, yte))
            base["r1"].append(rank1(Xte, yte, Xtr, ytr))
            # + head
            head = train_head(Xtr, ytr_i, X.shape[1], len(classes), seed=seed)
            Hte, Htr = apply_head(head, Xte), apply_head(head, Xtr)
            _, htar = verif(Hte, gen, imp)
            head_res["tar"].append(htar); head_res["f1"].append(cluster_f1(Hte, yte))
            head_res["r1"].append(rank1(Hte, yte, Htr, ytr))
        for k, lbl in (("tar", "TAR@1e-3"), ("f1", "clusterF1"), ("r1", "rank1")):
            b, h = np.mean(base[k]), np.mean(head_res[k])
            print(f"   {lbl:10s} baseline {b:.3f}  ->  +head {h:.3f}   ({h-b:+.3f})")
        print()


if __name__ == "__main__":
    main()
