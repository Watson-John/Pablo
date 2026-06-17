# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""SFace embedder (OpenCV ``cv2.FaceRecognizerSF``).

SFace is the recognition half of OpenCV's YuNet+SFace face pipeline. It ships as
a 128-D, cosine-metric model and is our primary *candidate* (shippable) embedder.

The critical detail: SFace does its OWN alignment via ``alignCrop`` and that
method consumes YuNet's **native 15-float detection row** (bbox[4] +
5 landmarks[10] + score[1]) — i.e. ``Detection.row`` — NOT the ArcFace-reordered
``Detection.landmarks``. alignCrop internally maps the landmarks (which live at
row indices 4..13 in (x, y) pairs: right-eye, left-eye, nose, right-mouth,
left-mouth) onto SFace's own canonical template, so feeding it the reordered
points would corrupt the warp. We therefore pass ``det.row`` verbatim.

Pixel order is BGR (OpenCV native) and all normalization is internal to the
model, so we hand ``feature`` the raw aligned BGR crop and only L2-normalize the
output ourselves (alignCrop -> feature -> l2_normalize).

API verified against OpenCV 4.11 (and the OpenCV docs / opencv_zoo sample):
    recog   = cv2.FaceRecognizerSF_create(model_path, "")  # (model, config="")
    aligned = recog.alignCrop(image_bgr, det.row)           # native YuNet row
    feat    = recog.feature(aligned)                         # -> (1, 128) float32
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

import cv2
import numpy as np

from common import Detection, l2_normalize
from embed.base import Embedder


class SFaceEmbedder(Embedder):
    """OpenCV SFace recognizer: 128-D, cosine, BGR-native, self-aligning."""

    name = "sface"
    dim = 128
    metric = "cosine"
    role = "candidate"

    def __init__(self, cfg: Dict[str, Any]):
        # Base sets self.name / self.metric / self.role from cfg (with our
        # class-level defaults as the fallback).
        super().__init__(cfg)

        model_path = cfg.get("path")
        if not model_path:
            raise ValueError("SFaceEmbedder: config missing 'path' to the SFace ONNX model")
        if not Path(model_path).is_file():
            raise FileNotFoundError(
                f"SFaceEmbedder: model not found at {model_path!r} "
                "(see tools/download_models.sh — face_recognition_sface_2021dec.onnx)"
            )

        # config="" : ONNX models carry their own config, so none is required.
        self._recog = cv2.FaceRecognizerSF_create(str(model_path), "")
        if self._recog is None:  # defensive — create can fail on a bad model file
            raise RuntimeError(f"SFaceEmbedder: failed to load SFace model at {model_path!r}")

        self.dim = 128
        self.metric = cfg.get("metric", "cosine")
        self.role = cfg.get("role", "candidate")

    def embed(self, image_bgr: np.ndarray, det: Detection) -> np.ndarray:
        """Align with SFace's own warp, extract the 128-D feature, L2-normalize.

        ``det.row`` is YuNet's raw 15-float output and is exactly what
        ``alignCrop`` expects; the reordered ``det.landmarks`` must NOT be used.
        """
        # alignCrop wants a contiguous float32 row of YuNet's native layout.
        face_box = np.asarray(det.row, dtype=np.float32).ravel()

        aligned = self._recog.alignCrop(image_bgr, face_box)
        feat = self._recog.feature(aligned)  # (1, 128) float32, BGR in / no external norm

        # Flatten (1,128)->(128,) and unit-normalize so downstream cosine == dot.
        return l2_normalize(np.asarray(feat, dtype=np.float32).ravel())
