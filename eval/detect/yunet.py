# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Shared YuNet face detector.

Wraps OpenCV's ``cv2.FaceDetectorYN`` (the DNN-based YuNet detector) and emits
the harness' ``Detection`` records. One detector instance is reused across every
crop in Phase 1.

YuNet's native per-face output is a flat 15-float row:

    [ x, y, w, h,                      # bbox (top-left + size, pixels)
      x_re, y_re,                      # right eye
      x_le, y_le,                      # left eye
      x_nt, y_nt,                      # nose tip
      x_rcm, y_rcm,                    # right mouth corner
      x_lcm, y_lcm,                    # left mouth corner
      score ]                          # confidence

(Verified against the OpenCV 4.x docs — classcv_1_1FaceDetectorYN and the
DNN face tutorial.) That native order is what ``SFace.alignCrop`` expects, so we
preserve it UNCHANGED in ``Detection.row``.

ArcFace-family alignment (``common.ARCFACE_5PT``) instead wants the order
``[left eye, right eye, nose, left mouth, right mouth]``. So ``Detection.landmarks``
is the same five points REORDERED into that template order — swapping the two
eyes and the two mouth corners relative to YuNet's native layout.
"""

from __future__ import annotations

from pathlib import Path
from typing import List, Optional

import cv2
import numpy as np

from common import Detection

# Native YuNet 15-float column layout (indices into Detection.row).
#   bbox = row[0:4]; landmark x/y pairs follow; score = row[14].
_BBOX = slice(0, 4)
_SCORE = 14

# YuNet's native 5-landmark order ALREADY matches the ArcFace template
# (common.ARCFACE_5PT) position-for-position — landmark slot 0 is at image-left,
# the same side as ARCFACE_5PT[0]. Empirically verified on real buffalo_l
# embeddings: feeding the native order gives clean genuine/impostor separation
# (within 0.46 / across -0.01), whereas swapping the eyes mirrors every face and
# collapses it (within 0.61 / across 0.47). So Detection.landmarks uses the
# native order unchanged. (Detection.row stays native too, for SFace.alignCrop.)
# Each native slot s occupies row columns (4 + 2*s, 4 + 2*s + 1).
_ARCFACE_FROM_NATIVE = (0, 1, 2, 3, 4)


class YuNetDetector:
    """OpenCV YuNet detector producing harness ``Detection`` records.

    Parameters
    ----------
    cfg : dict
        ``config['detector']`` — keys: ``yunet_model`` (path relative to *base*
        unless absolute), ``score_threshold``, ``nms_threshold``, ``top_k``.
    base : pathlib.Path
        Harness root; used to resolve a relative ``yunet_model`` path.
    """

    def __init__(self, cfg: dict, base: Path):
        self.cfg = cfg

        # Resolve the model path against the harness root (absolute passes through).
        model = Path(cfg["yunet_model"])
        if not model.is_absolute():
            model = base / model
        self.model_path = model
        if not self.model_path.exists():
            raise FileNotFoundError(
                f"YuNet model not found: {self.model_path} "
                "(see tools/download_models.sh)"
            )

        self.score_threshold = float(cfg.get("score_threshold", 0.7))
        self.nms_threshold = float(cfg.get("nms_threshold", 0.3))
        self.top_k = int(cfg.get("top_k", 5000))

        # input_size is a placeholder here — we MUST call setInputSize() to the
        # actual image dimensions before every detect() call (see detect()).
        self._detector = cv2.FaceDetectorYN_create(
            str(self.model_path),
            "",                       # no separate config file for the ONNX model
            (320, 320),               # provisional; overwritten per image
            self.score_threshold,
            self.nms_threshold,
            self.top_k,
        )

    # ------------------------------------------------------------------ detect

    def detect(self, image_bgr: np.ndarray) -> List[Detection]:
        """Detect every face in a BGR image.

        Returns a list of ``Detection`` (possibly empty). ``landmarks`` are in
        ArcFace template order; ``row`` is YuNet's raw native 15-float output.
        """
        if image_bgr is None or getattr(image_bgr, "size", 0) == 0:
            return []

        # OpenCV requires the network input size to match the image on EVERY
        # call; setInputSize takes (width, height).
        h, w = image_bgr.shape[:2]
        self._detector.setInputSize((w, h))

        # detect() returns (retval, faces); faces is None when nothing is found,
        # otherwise an (N, 15) float32 array.
        _, faces = self._detector.detect(image_bgr)
        if faces is None:
            return []

        out: List[Detection] = []
        for raw in faces:
            row = np.asarray(raw, dtype=np.float32).reshape(-1)
            if row.shape[0] < 15:
                # Defensive: skip malformed rows rather than crash the run.
                continue

            bbox = tuple(float(v) for v in row[_BBOX])           # x, y, w, h
            score = float(row[_SCORE])

            # Reorder the five (x, y) landmark pairs from native YuNet order
            # into ArcFace template order to match common.ARCFACE_5PT.
            landmarks = np.empty((5, 2), dtype=np.float32)
            for dst, native_slot in enumerate(_ARCFACE_FROM_NATIVE):
                base_col = 4 + 2 * native_slot
                landmarks[dst, 0] = row[base_col]
                landmarks[dst, 1] = row[base_col + 1]

            out.append(Detection(
                bbox=bbox,
                landmarks=landmarks,
                score=score,
                row=row.copy(),          # native order, untouched, for SFace
            ))
        return out

    def detect_primary(self, image_bgr: np.ndarray) -> Optional[Detection]:
        """Return the single best face, or ``None`` if none detected.

        "Best" = the largest face by bbox area weighted toward higher
        confidence: face crops are typically one centered subject, so the
        biggest high-score box is the intended target. We rank by area first,
        breaking ties by score.
        """
        dets = self.detect(image_bgr)
        if not dets:
            return None

        def _key(d: Detection):
            _, _, bw, bh = d.bbox
            return (bw * bh, d.score)

        return max(dets, key=_key)
