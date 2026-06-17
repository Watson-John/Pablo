# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""dlib ResNet-34 face embedder (the classic ``face_recognition`` model).

This wraps dlib's ``dlib_face_recognition_resnet_model_v1.dat`` — a 27-layer
ResNet trained on ~3M faces that maps a 150x150 aligned face chip to a 128-D
descriptor. We compare descriptors with Euclidean distance (the model was
trained so that same-identity descriptors are < ~0.6 apart), so this embedder
advertises ``metric = "l2"``; ``pair_score`` turns that into a *negative* L2 so
higher still means more-similar.

dlib is intentionally NOT a hard dependency of this harness: the eval box ships
without it. ``import dlib`` therefore happens lazily inside ``__init__`` and a
failure is re-raised as a clear ``RuntimeError`` — ``run.py``'s phase-2 loop
catches that and simply SKIPS this model rather than aborting the whole run.

Alignment note: unlike the ArcFace-family embedders, dlib does its OWN
alignment. We hand it the YuNet bounding box, let its 5-point shape predictor
(``shape_predictor_5_face_landmarks.dat``) find landmarks inside that box, then
``get_face_chip`` produces the canonical 150x150 chip dlib's recognizer expects.
"""

from __future__ import annotations

from typing import Any, Dict

import numpy as np

import common
from common import Detection
from embed.base import Embedder


class DlibResnetEmbedder(Embedder):
    """128-D dlib ResNet face descriptor (candidate model, L2 metric).

    cfg keys:
        path      : dlib_face_recognition_resnet_model_v1.dat   (required)
        predictor : shape_predictor_5_face_landmarks.dat        (required)
    """

    name = "dlib"
    dim = 128
    metric = "l2"
    role = "candidate"

    # dlib's recognizer is trained on chips of exactly this size; the
    # single-image compute_face_descriptor overload requires 150x150.
    CHIP_SIZE = 150

    def __init__(self, cfg: Dict[str, Any]):
        super().__init__(cfg)
        self.dim = 128
        # Honor cfg overrides but default to the contract values for this family.
        self.metric = cfg.get("metric", "l2")
        self.role = cfg.get("role", "candidate")

        # --- Lazy import: dlib is optional in this environment. -------------
        # Keep the import inside __init__ so merely importing this module never
        # requires dlib; only *constructing* the embedder does. Any failure
        # (missing wheel, ABI mismatch, …) becomes a clear RuntimeError that
        # run.py turns into a clean "SKIPPED" for this single model.
        try:
            import dlib  # type: ignore
        except Exception as ex:  # noqa: BLE001 — any import failure means "skip me"
            raise RuntimeError(
                "dlib is not available — install it (pip install dlib) to "
                f"evaluate the dlib_resnet model. Original error: {ex!r}"
            ) from ex
        self._dlib = dlib

        predictor_path = cfg.get("predictor")
        if not predictor_path:
            raise RuntimeError(
                "dlib_resnet requires a 'predictor' path "
                "(shape_predictor_5_face_landmarks.dat) in its config."
            )

        # Load both models up front so a bad/missing file fails fast at
        # construction time (run.py skips the model) rather than per-face.
        try:
            self._predictor = dlib.shape_predictor(predictor_path)
            self._recognizer = dlib.face_recognition_model_v1(cfg["path"])
        except Exception as ex:  # noqa: BLE001 — bad path/file => skip this model
            raise RuntimeError(
                f"failed to load dlib models (predictor={predictor_path!r}, "
                f"recognizer={cfg.get('path')!r}): {ex!r}"
            ) from ex

    def embed(self, image_bgr: np.ndarray, det: Detection) -> np.ndarray:
        """Return an L2-normalized 128-D dlib descriptor for one detected face.

        dlib wants RGB; OpenCV crops are BGR, so flip channels. The YuNet bbox
        (x, y, w, h) becomes a dlib.rectangle(left, top, right, bottom); the
        shape predictor finds 5 landmarks inside it; get_face_chip warps the
        face to the canonical 150x150 chip the recognizer was trained on.
        """
        dlib = self._dlib

        # OpenCV -> dlib colour order. compute_face_descriptor / get_face_chip
        # expect an 8-bit RGB image; np.ascontiguousarray guards against the
        # non-contiguous view that BGR->RGB slicing produces (dlib needs a
        # contiguous buffer to wrap).
        rgb = np.ascontiguousarray(image_bgr[:, :, ::-1])

        # bbox is (x, y, w, h) in pixels -> integer rect (left, top, right, bottom).
        x, y, w, h = det.bbox
        left, top = int(round(x)), int(round(y))
        right, bottom = int(round(x + w)), int(round(y + h))
        rect = dlib.rectangle(left, top, right, bottom)

        # 5-point landmarks within the box, then the canonical aligned chip.
        shape = self._predictor(rgb, rect)
        chip = dlib.get_face_chip(rgb, shape, size=self.CHIP_SIZE)

        # Single-image overload: a 150x150 aligned chip -> 128-D descriptor
        # (dlib.vector). Deterministic — no jittering.
        desc = self._recognizer.compute_face_descriptor(chip)

        # dlib.vector -> contiguous float32, then L2-normalize per the contract
        # (every embedder returns a unit-length 1-D float32 vector).
        return common.l2_normalize(np.asarray(desc, dtype=np.float32).ravel())
