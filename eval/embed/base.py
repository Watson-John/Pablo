# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Common embedder interface + factory.

Every model implements ``embed(image_bgr, det) -> np.ndarray`` and does its OWN
alignment + preprocessing internally (the per-model recipe is the part that must
be exactly right). The returned vector is ALWAYS L2-normalized 1-D float32, so
downstream code compares with a single ``pair_score`` regardless of model.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict

import numpy as np

from common import Detection


class Embedder(ABC):
    name: str = "base"
    dim: int = 0
    metric: str = "cosine"     # "cosine" | "l2"
    role: str = "candidate"    # "candidate" (shippable) | "ceiling" (eval-only)

    def __init__(self, cfg: Dict[str, Any]):
        self.cfg = cfg
        self.name = cfg.get("name", self.name)
        self.metric = cfg.get("metric", self.metric)
        self.role = cfg.get("role", self.role)

    @abstractmethod
    def embed(self, image_bgr: np.ndarray, det: Detection) -> np.ndarray:
        """Return an L2-normalized 1-D float32 embedding for the detected face.

        image_bgr : the face crop as BGR uint8 (already upright).
        det       : YuNet Detection (bbox + 5 landmarks + raw 15-float row).
        """
        raise NotImplementedError


def build_embedder(model_cfg: Dict[str, Any]) -> Embedder:
    """Construct an Embedder from a config row (lazy imports keep deps optional)."""
    t = model_cfg["type"]
    if t == "sface":
        from embed.sface import SFaceEmbedder
        return SFaceEmbedder(model_cfg)
    if t == "dlib_resnet":
        from embed.dlib_resnet import DlibResnetEmbedder
        return DlibResnetEmbedder(model_cfg)
    if t == "arcface_onnx":
        from embed.arcface_onnx import ArcFaceOnnxEmbedder
        return ArcFaceOnnxEmbedder(model_cfg)
    if t == "hog":
        from embed.hog_baseline import HOGBaselineEmbedder
        return HOGBaselineEmbedder(model_cfg)
    raise ValueError(f"unknown embedder type: {t!r}")
