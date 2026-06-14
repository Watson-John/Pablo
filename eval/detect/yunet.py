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

from common import ARCFACE_5PT, Detection

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
        self._low = None              # lazily-built lower-threshold retry detector
        # The recovery ladder (upscale/pad/lower-threshold) boosts COVERAGE on
        # hard scans but the faces it recovers are low-quality and hurt
        # recognition, so it's opt-in. Off => clean single-shot detection.
        self.recovery_ladder = bool(cfg.get("recovery_ladder", False))

    # ------------------------------------------------------------------ detect

    def _row_to_detection(self, raw) -> Optional[Detection]:
        row = np.asarray(raw, dtype=np.float32).reshape(-1)
        if row.shape[0] < 15:
            return None
        bbox = tuple(float(v) for v in row[_BBOX])               # x, y, w, h
        # YuNet's native landmark order already matches ARCFACE_5PT (see the
        # _ARCFACE_FROM_NATIVE note), so this is an identity copy.
        landmarks = np.empty((5, 2), dtype=np.float32)
        for dst, native_slot in enumerate(_ARCFACE_FROM_NATIVE):
            base_col = 4 + 2 * native_slot
            landmarks[dst, 0] = row[base_col]
            landmarks[dst, 1] = row[base_col + 1]
        return Detection(bbox=bbox, landmarks=landmarks,
                         score=float(row[_SCORE]), row=row.copy())

    def _raw_faces(self, image_bgr, detector=None):
        """Run a YuNet detector on a BGR image -> (N,15) array or None."""
        if image_bgr is None or getattr(image_bgr, "size", 0) == 0:
            return None
        detector = detector or self._detector
        h, w = image_bgr.shape[:2]
        detector.setInputSize((w, h))           # required before every detect()
        _, faces = detector.detect(image_bgr)
        return faces

    def _low_detector(self):
        """Lazily build a lower-threshold detector for the recall-retry pass."""
        if self._low is None:
            self._low = cv2.FaceDetectorYN_create(
                str(self.model_path), "", (320, 320),
                min(0.3, self.score_threshold), self.nms_threshold, self.top_k)
        return self._low

    def detect(self, image_bgr: np.ndarray) -> List[Detection]:
        """Detect every face in a BGR image (list, possibly empty)."""
        faces = self._raw_faces(image_bgr)
        if faces is None:
            return []
        out = [self._row_to_detection(r) for r in faces]
        return [d for d in out if d is not None]

    def _best_on_transformed(self, image_bgr, scale: float, pad: int,
                             low: bool = False) -> Optional[Detection]:
        """Detect on a scaled+padded copy; map the largest face back to ORIGINAL
        crop coordinates. Upscaling lifts small scanned faces above YuNet's min
        size; padding gives margin to faces that fill the frame."""
        work = image_bgr
        if scale != 1.0:
            interp = cv2.INTER_CUBIC if scale > 1.0 else cv2.INTER_AREA
            work = cv2.resize(image_bgr, None, fx=scale, fy=scale, interpolation=interp)
        if pad > 0:
            work = cv2.copyMakeBorder(work, pad, pad, pad, pad, cv2.BORDER_REFLECT_101)
        faces = self._raw_faces(work, self._low_detector() if low else None)
        if faces is None:
            return None
        best, best_area = None, -1.0
        for raw in faces:
            m = np.asarray(raw, dtype=np.float32).reshape(-1)
            if m.shape[0] < 15:
                continue
            m = m.copy()
            for c in (0, 1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13):   # positions
                m[c] = (m[c] - pad) / scale
            m[2] /= scale                                         # w
            m[3] /= scale                                         # h
            area = m[2] * m[3]
            if area > best_area:
                best_area, best = area, m
        return self._row_to_detection(best) if best is not None else None

    @staticmethod
    def _best(dets: List[Detection]) -> Optional[Detection]:
        if not dets:
            return None
        return max(dets, key=lambda d: (d.bbox[2] * d.bbox[3], d.score))

    def _fallback_detection(self, w: int, h: int) -> Detection:
        """Last resort when YuNet finds nothing: the crop IS a Picasa-labeled
        face, so assume it fills the central ~72% and place ArcFace-template
        landmarks there. Marked score=0.0 so callers can count fallbacks apart
        from real detections (alignment is approximate)."""
        frac = 0.72
        bw, bh = w * frac, h * frac
        ox, oy = (w - bw) / 2.0, (h - bh) / 2.0
        lm = np.empty((5, 2), dtype=np.float32)
        row = np.zeros(15, dtype=np.float32)
        row[0:4] = (ox, oy, bw, bh)
        for i, (px, py) in enumerate(ARCFACE_5PT):
            x = ox + (px / 112.0) * bw
            y = oy + (py / 112.0) * bh
            lm[i] = (x, y)
            row[4 + 2 * i], row[4 + 2 * i + 1] = x, y   # native order == ArcFace order
        return Detection(bbox=(ox, oy, bw, bh), landmarks=lm, score=0.0, row=row)

    def detect_primary(self, image_bgr: np.ndarray,
                       allow_fallback: bool = False) -> Optional[Detection]:
        """Best single face, with a recall-recovery ladder. Returns None only if
        every YuNet attempt fails and ``allow_fallback`` is False."""
        d = self._best(self.detect(image_bgr))
        if d is not None:
            return d
        if image_bgr is None or getattr(image_bgr, "size", 0) == 0:
            return None
        if not self.recovery_ladder:                    # clean single-shot mode
            h, w = image_bgr.shape[:2]
            return self._fallback_detection(w, h) if allow_fallback else None
        h, w = image_bgr.shape[:2]
        short = min(h, w)
        up = max(256.0 / short, 1.5) if short < 256 else 1.5     # upscale factor
        pad = int(0.25 * short * up)
        # ladder: upscale -> upscale+pad -> +lower-threshold
        for scale, p, low in ((up, 0, False), (up, pad, False), (up, pad, True)):
            d = self._best_on_transformed(image_bgr, scale, p, low)
            if d is not None:
                return d
        return self._fallback_detection(w, h) if allow_fallback else None
