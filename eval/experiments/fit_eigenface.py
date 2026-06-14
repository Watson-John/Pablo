#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Fit an Eigenface PCA basis from a faces_db and save it for the embedder.

  python experiments/fit_eigenface.py /tmp/full_db/manifest.csv
Saves models/eigenface_basis.npz (mean, components, size). Unsupervised — uses
aligned grayscale pixels only, no identity labels.
"""
import sys
from pathlib import Path

import cv2
import numpy as np
import yaml
from sklearn.decomposition import PCA

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from common import load_face_db, load_image_bgr, align_arcface  # noqa: E402
from detect.yunet import YuNetDetector                          # noqa: E402

SIZE, K = 64, 200
manifest = sys.argv[1] if len(sys.argv) > 1 else "/tmp/full_db/manifest.csv"
cfg = yaml.safe_load(open(ROOT / "config.yaml"))
det = YuNetDetector(cfg["detector"], ROOT)

rows = []
for f in load_face_db(manifest):
    img = load_image_bgr(f.crop_path)
    if img is None:
        continue
    d = det.detect_primary(img)
    if d is None:
        continue
    g = cv2.cvtColor(align_arcface(img, d.landmarks, SIZE), cv2.COLOR_BGR2GRAY)
    rows.append(g.astype(np.float32).ravel())
X = np.asarray(rows, np.float32)
print(f"fitting PCA on {X.shape[0]} faces x {X.shape[1]} px -> {K} eigenfaces")
pca = PCA(n_components=min(K, X.shape[0] - 1), svd_solver="randomized", random_state=1234)
pca.fit(X)
out = ROOT / "models/eigenface_basis.npz"
np.savez(out, mean=pca.mean_.astype(np.float32),
         components=pca.components_.astype(np.float32), size=SIZE)
print(f"saved {out}  (var explained: {pca.explained_variance_ratio_.sum():.2f})")
