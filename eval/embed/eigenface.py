# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Eigenfaces (Turk & Pentland, 1991) — the original face-recognition baseline.

PCA on aligned grayscale face pixels: project each face onto the top-K principal
components ("eigenfaces") of a fitted basis, then compare with cosine. Even older
and simpler than HOG — it anchors the "classical" end of the spectrum so the
jump to modern learned embeddings is fully quantified.

The basis (mean + components) is fitted offline by experiments/fit_eigenface.py
and loaded from ``cfg['path']`` (a .npz). Unsupervised — no identity labels used
to build it.
"""

from __future__ import annotations

from typing import Any, Dict

import cv2
import numpy as np

import common
from embed.base import Embedder


class EigenFaceEmbedder(Embedder):
    def __init__(self, cfg: Dict[str, Any]):
        super().__init__(cfg)
        self.metric = "cosine"
        z = np.load(cfg["path"])
        self.mean = z["mean"].astype(np.float32)            # (D,)
        self.components = z["components"].astype(np.float32)  # (K, D)
        self.size = int(z["size"])
        self.dim = int(self.components.shape[0])

    def embed(self, image_bgr: np.ndarray, det) -> np.ndarray:
        aligned = common.align_arcface(image_bgr, det.landmarks, self.size)
        gray = cv2.cvtColor(aligned, cv2.COLOR_BGR2GRAY).astype(np.float32).ravel()
        proj = (gray - self.mean) @ self.components.T        # (K,)
        return common.l2_normalize(proj)
