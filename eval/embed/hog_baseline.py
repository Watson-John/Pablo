# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""HOG face descriptor — a classical, pre-deep-learning baseline.

This is the *technique Picasa actually used* for face grouping: its binary
exposes a ``HOGSimilarityComputer`` (Histogram-of-Oriented-Gradients) alongside
the proprietary Neven Vision recognizer. We cannot run Neven's weights (they're
statically linked in Picasa3.exe and its per-face templates were never written
to the .picasa.ini), so HOG-on-aligned-faces stands in as a faithful
"Picasa-era / classical" reference point: it answers "do the modern learned
embedders actually beat the hand-crafted approach the old tool relied on?".

No learned weights — just gradients on a landmark-aligned, grayscale face,
L2-normalized so cosine == correlation. Honestly labeled role='baseline'.
"""

from __future__ import annotations

from typing import Any, Dict

import cv2
import numpy as np
from skimage.feature import hog

import common
from embed.base import Embedder


class HOGBaselineEmbedder(Embedder):
    """Landmark-aligned grayscale HOG descriptor (classical baseline)."""

    def __init__(self, cfg: Dict[str, Any]):
        super().__init__(cfg)
        self.metric = "cosine"
        self.size = int(cfg.get("size", 128))          # aligned face size
        self.orientations = int(cfg.get("orientations", 9))
        self.ppc = int(cfg.get("pixels_per_cell", 16))
        self.cpb = int(cfg.get("cells_per_block", 2))
        self.dim = 0                                    # set on first embed

    def embed(self, image_bgr: np.ndarray, det) -> np.ndarray:
        # Align with the same 5-point similarity transform the learned models
        # use, so every model sees the same canonical face — only the descriptor
        # differs. Then grayscale (HOG ignores color).
        aligned = common.align_arcface(image_bgr, det.landmarks, self.size)
        gray = cv2.cvtColor(aligned, cv2.COLOR_BGR2GRAY)
        feat = hog(
            gray,
            orientations=self.orientations,
            pixels_per_cell=(self.ppc, self.ppc),
            cells_per_block=(self.cpb, self.cpb),
            block_norm="L2-Hys",
            feature_vector=True,
        ).astype(np.float32)
        self.dim = int(feat.shape[0])
        return common.l2_normalize(feat)
