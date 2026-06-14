#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Grid-search the face-clustering pipeline on OUR cached embeddings.

Sweeps  embedder x method x graph/hyperparams, picks the best config per
(embedder, method) on a TUNE identity-split, and reports it on a disjoint TEST
split (no leakage). Methods: DBSCAN, HDBSCAN, Agglomerative, Chinese Whispers,
and (if installed) Leiden + Infomap on a mutual-kNN graph — the "strong
normalized embeddings + sparse similarity graph + community detection" stack.
Metric: pairwise F1 (the standard face-clustering measure) + ARI.
"""
from __future__ import annotations

import sys
from itertools import product
from pathlib import Path

import numpy as np
from sklearn.cluster import DBSCAN, HDBSCAN, AgglomerativeClustering
from sklearn.metrics import adjusted_rand_score

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from common import load_face_db, l2_normalize  # noqa: E402

try:
    import igraph as ig
    import leidenalg
    HAVE_LEIDEN = True
except ImportError:
    HAVE_LEIDEN = False
try:
    import infomap as _infomap
    HAVE_INFOMAP = True
except ImportError:
    HAVE_INFOMAP = False

DB = "/tmp/full_db/manifest.csv"
EMB = ["auraface", "sface", "vit_cosface", "buffalo_l", "ensemble(auraface+sface)"]
SEED = 1234


# --------------------------------------------------------------- data utilities
def load_emb(name):
    z = np.load(ROOT / f"eval_out/embeddings_{name}.npz", allow_pickle=True)
    return z["X"].astype(np.float32), [str(i) for i in z["ids"]]


def build_matrix(name, label_of):
    if name.startswith("ensemble"):
        inner = name[name.find("(") + 1:name.rfind(")")].split("+")
        mats, idsets = [], []
        for m in inner:
            X, ids = load_emb(m); mats.append((dict(zip(ids, X)))); idsets.append(set(ids))
        common_ids = sorted(set.intersection(*idsets))
        X = np.array([l2_normalize(np.concatenate([mats[j][i] for j in range(len(inner))]))
                      for i in common_ids], np.float32)
        ids = common_ids
    else:
        X, ids = load_emb(name)
    y = np.array([label_of[i] for i in ids])
    return X, y


SEEDS = [1234, 7, 42, 99, 2024]


def split(y, seed, frac=0.4):
    rng = np.random.default_rng(seed)
    ppl = sorted(set(y)); rng.shuffle(ppl)
    tune = set(ppl[: max(1, int(len(ppl) * frac))])
    m = np.array([p in tune for p in y])
    return m, ~m


def pairwise_f1(pred, true):
    pred = _relabel_noise(np.asarray(pred))
    true = np.asarray(true)
    _, p = np.unique(pred, return_inverse=True)
    _, t = np.unique(true, return_inverse=True)
    cont = np.zeros((p.max() + 1, t.max() + 1), np.int64)
    np.add.at(cont, (p, t), 1)
    tp = (cont * (cont - 1) // 2).sum()
    pp = (cont.sum(1) * (cont.sum(1) - 1) // 2).sum()
    tt = (cont.sum(0) * (cont.sum(0) - 1) // 2).sum()
    prec = tp / pp if pp else 0.0
    rec = tp / tt if tt else 0.0
    return 0.0 if prec + rec == 0 else 2 * prec * rec / (prec + rec)


def _relabel_noise(pred):
    pred = pred.copy()
    nxt = pred.max() + 1 if len(pred) and pred.max() >= 0 else 0
    for i in np.where(pred < 0)[0]:
        pred[i] = nxt; nxt += 1
    return pred


def score(pred, true):
    return pairwise_f1(pred, true), float(adjusted_rand_score(true, pred)), len(set(_relabel_noise(np.asarray(pred))))


# ----------------------------------------------------------------- graph helpers
def knn_graph(X, k, mutual):
    S = X @ X.T
    np.fill_diagonal(S, -1.0)
    nn = np.argsort(-S, axis=1)[:, :k]
    edges = {}
    nnset = [set(row) for row in nn]
    for i in range(len(X)):
        for j in nn[i]:
            if mutual and i not in nnset[j]:
                continue
            a, b = (i, j) if i < j else (j, i)
            edges[(a, b)] = float(S[i, j])
    return edges


def chinese_whispers(X, k, thr, mutual, iters=20):
    edges = {e: w for e, w in knn_graph(X, k, mutual).items() if w >= thr}
    n = len(X)
    adj = [{} for _ in range(n)]
    for (a, b), w in edges.items():
        adj[a][b] = w; adj[b][a] = w
    lab = np.arange(n)
    rng = np.random.default_rng(SEED)
    order = np.arange(n)
    for _ in range(iters):
        rng.shuffle(order)
        for i in order:
            if not adj[i]:
                continue
            tally = {}
            for j, w in adj[i].items():
                tally[lab[j]] = tally.get(lab[j], 0.0) + w
            lab[i] = max(tally, key=tally.get)
    return lab


def community(X, k, mutual, algo, resolution=1.0):
    # Community detectors need non-negative edge weights; a kNN edge to a
    # different person can have negative cosine, so keep only positive-similarity
    # edges (dissimilar pairs shouldn't be linked anyway).
    edges = {e: w for e, w in knn_graph(X, k, mutual).items() if w > 0.0}
    n = len(X)
    if algo == "leiden":
        g = ig.Graph(n=n, edges=list(edges.keys()))
        g.es["weight"] = list(edges.values())
        part = leidenalg.find_partition(
            g, leidenalg.RBConfigurationVertexPartition,
            weights="weight", resolution_parameter=resolution, seed=SEED)
        return np.array(part.membership)
    if algo == "infomap":
        im = _infomap.Infomap("--two-level --silent --seed %d" % SEED)
        for (a, b), w in edges.items():
            im.add_link(a, b, w)
        im.run()
        lab = np.full(n, -1)
        for node in im.tree:
            if node.is_leaf:
                lab[node.node_id] = node.module_id
        return lab
    raise ValueError(algo)


# ------------------------------------------------------------------- the methods
def gen_configs():
    cfgs = []
    for eps, ms in product([.3, .4, .45, .5, .55, .6, .65, .7, .75, .8], [2, 3, 4]):
        cfgs.append(("dbscan", {"eps": eps, "min_samples": ms}))
    for mcs, ms, cse in product([2, 3, 4, 5], [1, 2, 3], [0.0, 0.1, 0.2]):
        cfgs.append(("hdbscan", {"min_cluster_size": mcs, "min_samples": ms, "cse": cse}))
    for dt in [.5, .6, .65, .7, .75, .8, .85, .9, .95, 1.0, 1.05]:
        cfgs.append(("agglomerative", {"distance_threshold": dt}))
    for k, thr, mut in product([5, 10, 20], [.3, .4, .5, .6], [True, False]):
        cfgs.append(("chinese_whispers", {"k": k, "thr": thr, "mutual": mut}))
    if HAVE_LEIDEN:
        for k, mut, res in product([5, 10, 20], [True, False], [.5, 1.0, 1.5]):
            cfgs.append(("leiden", {"k": k, "mutual": mut, "resolution": res}))
    if HAVE_INFOMAP:
        for k, mut in product([5, 10, 20], [True, False]):
            cfgs.append(("infomap", {"k": k, "mutual": mut}))
    return cfgs


def run_method(method, p, X):
    if method == "dbscan":
        D = np.clip(1.0 - X @ X.T, 0.0, 2.0)
        return DBSCAN(eps=p["eps"], min_samples=p["min_samples"], metric="precomputed").fit_predict(D)
    if method == "hdbscan":
        return HDBSCAN(min_cluster_size=p["min_cluster_size"], min_samples=p["min_samples"],
                       cluster_selection_epsilon=p["cse"], metric="euclidean").fit_predict(X)
    if method == "agglomerative":
        return AgglomerativeClustering(n_clusters=None, distance_threshold=p["distance_threshold"],
                                       linkage="average", metric="cosine").fit_predict(X)
    if method == "chinese_whispers":
        return chinese_whispers(X, p["k"], p["thr"], p["mutual"])
    if method in ("leiden", "infomap"):
        return community(X, p["k"], p["mutual"], method, p.get("resolution", 1.0))
    raise ValueError(method)


def main():
    label_of = {f.face_id: f.person_name for f in load_face_db(DB)}
    configs = gen_configs()
    methods = sorted({m for m, _ in configs})
    print(f"grid: {len(configs)} configs x {len(EMB)} embedders | "
          f"leiden={HAVE_LEIDEN} infomap={HAVE_INFOMAP}\n")

    print(f"{len(SEEDS)}-seed CV: per seed, tune the best config then score the held split.\n"
          "Reporting mean test pairwise-F1 +/- std (stability is as important as the mean).\n")
    summary = {}   # (emb, method) -> list of test F1 across seeds
    for emb in EMB:
        X, y = build_matrix(emb, label_of)
        print(f"== {emb} ==")
        for method in methods:
            f1s = []
            for seed in SEEDS:
                tm, sm = split(y, seed)
                Xt, yt, Xs, ys = X[tm], y[tm], X[sm], y[sm]
                best = None
                for m, p in configs:
                    if m != method:
                        continue
                    try:
                        f1, _, _ = score(run_method(m, p, Xt), yt)
                    except Exception:
                        continue
                    if best is None or f1 > best[0]:
                        best = (f1, p)
                if best is None:
                    continue
                try:
                    f1t, _, _ = score(run_method(method, best[1], Xs), ys)
                    f1s.append(f1t)
                except Exception:
                    pass
            if f1s:
                summary[(emb, method)] = f1s
                print(f"   {method:17s} F1 = {np.mean(f1s):.3f} +/- {np.std(f1s):.3f}  "
                      f"(min {min(f1s):.3f})")
        print()
    print("=== most STABLE (highest mean - std), per (embedder, method) ===")
    ranked = sorted(summary.items(), key=lambda kv: np.mean(kv[1]) - np.std(kv[1]), reverse=True)
    for (emb, method), f1s in ranked[:6]:
        print(f"   {emb:26s} {method:15s} mean {np.mean(f1s):.3f}  std {np.std(f1s):.3f}  min {min(f1s):.3f}")


if __name__ == "__main__":
    main()
