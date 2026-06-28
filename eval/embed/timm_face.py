# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""timm-hosted face embedders (e.g. gaunernst's ViT CosFace/AdaFace models).

A different architecture family — Vision Transformers — vs the CNN ArcFace
models, loaded straight from the HF hub via timm. Preprocessing (input size,
mean, std, channel order) is read from the model's own pretrained_cfg so we
match exactly what it was trained with; output is L2-normalized.

Note on licensing: models trained on MS1MV3 (cleaned MS-Celeb-1M) are
research/non-commercial — these are ceilings, not shippable candidates.
"""

from __future__ import annotations

from typing import Any, Dict

import cv2
import numpy as np

import common
from embed.base import Embedder


class TimmFaceEmbedder(Embedder):
    def __init__(self, cfg: Dict[str, Any]):
        super().__init__(cfg)
        import timm
        import torch

        self._torch = torch
        self.metric = "cosine"
        self.model = timm.create_model(cfg["hf_hub"], pretrained=True).eval()

        # Pull the exact preprocessing the model was trained with.
        dc = timm.data.resolve_model_data_config(self.model)
        self.size = int(dc["input_size"][-1])
        self.mean = np.array(dc["mean"], np.float32).reshape(1, 1, 3)
        self.std = np.array(dc["std"], np.float32).reshape(1, 1, 3)
        self.rgb = True
        self.dim = 0

    def embed(self, image_bgr: np.ndarray, det) -> np.ndarray:
        aligned = common.align_arcface(image_bgr, det.landmarks, self.size)  # BGR
        img = cv2.cvtColor(aligned, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        img = (img - self.mean) / self.std                       # HWC, model's norm
        t = self._torch.from_numpy(np.ascontiguousarray(img.transpose(2, 0, 1))[None])
        with self._torch.no_grad():
            emb = self.model(t).cpu().numpy().ravel().astype(np.float32)
        self.dim = int(emb.shape[0])
        return common.l2_normalize(emb)
