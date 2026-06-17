# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""ArcFace-family ONNX embedder (the eval "ceiling" models).

One Embedder serves BOTH ceiling models in config.yaml, because their graphs
are interchangeable 112x112 -> 512-D recognizers and only the *preprocessing*
recipe differs. The recipe is selected entirely from config (``color``/``norm``),
never hard-coded to a single model:

  buffalo_l (insightface w600k_r50, ArcFace R50)
      color: rgb     norm: arcface     (x - 127.5) / 127.5     -> [-1, 1]
  adaface  (mk-minchul/AdaFace ir101)
      color: bgr     norm: adaface     (x / 255 - 0.5) / 0.5   -> [-1, 1]

Web-verified preprocessing (the highest-risk part — get one number wrong and the
embeddings are silently garbage):

  (1) insightface ArcFace ONNX — model_zoo/arcface_onnx.py. For the non-MXNet
      ONNX recognizers (w600k_r50 / buffalo_l) the defaults are
      ``input_mean = 127.5`` and ``input_std = 127.5``, and the blob is built as
          cv2.dnn.blobFromImages(imgs, 1.0/input_std, size,
                                 (input_mean,)*3, swapRB=True)
      So the correct normalization is (x - 127.5) / 127.5 (NOT /128 as the draft
      plan guessed), and swapRB=True means the network is fed RGB. We therefore
      use color='rgb', norm='arcface' for buffalo_l.
      Source: github.com/deepinsight/insightface
              python-package/insightface/model_zoo/arcface_onnx.py

  (2) AdaFace official — mk-minchul/AdaFace inference.py ``to_input``:
          brg_img = ((np_img[:,:,::-1] / 255.) - 0.5) / 0.5
      It reverses RGB->BGR (``[:,:,::-1]``), divides by 255, then (x-0.5)/0.5.
      So AdaFace is fed BGR (a well-known gotcha — feeding it RGB drops accuracy)
      with norm (x/255 - 0.5)/0.5. We use color='bgr', norm='adaface'.
      Source: github.com/mk-minchul/AdaFace inference.py

Both models take NCHW float32 (1, 3, 112, 112) and emit a (1, 512) embedding,
which we L2-normalize. metric=cosine, role=ceiling, dim=512.
"""

from __future__ import annotations

from typing import Any, Dict

import cv2
import numpy as np
import onnxruntime as ort

import common
from common import Detection
from embed.base import Embedder

# insightface ArcFace ONNX preprocessing constants (verified above).
_ARCFACE_MEAN = 127.5
_ARCFACE_STD = 127.5


class ArcFaceOnnxEmbedder(Embedder):
    """512-D ArcFace-family recognizer over ONNX Runtime (CPU).

    Drives both buffalo_l (ArcFace) and AdaFace; the difference is purely the
    ``color`` (rgb|bgr) and ``norm`` (arcface|adaface) preprocessing knobs.
    """

    name = "arcface_onnx"
    dim = 512
    metric = "cosine"
    role = "ceiling"

    def __init__(self, cfg: Dict[str, Any]):
        super().__init__(cfg)
        # Preprocessing recipe — read from config, do not assume one model.
        self.color = str(cfg.get("color", "rgb")).lower()    # 'rgb' | 'bgr'
        self.norm = str(cfg.get("norm", "arcface")).lower()  # 'arcface' | 'adaface'
        if self.color not in ("rgb", "bgr"):
            raise ValueError(f"arcface_onnx: unknown color {self.color!r}")
        if self.norm not in ("arcface", "adaface"):
            raise ValueError(f"arcface_onnx: unknown norm {self.norm!r}")

        # CPU-only session: the harness deliberately runs without a GPU EP so the
        # numbers are reproducible across machines.
        self.session = ort.InferenceSession(
            cfg["path"], providers=["CPUExecutionProvider"]
        )
        # Pull the input/output tensor names from the graph rather than guessing
        # ("input.1", "data", "input" etc. vary by export).
        self.input_name = self.session.get_inputs()[0].name
        self.output_name = self.session.get_outputs()[0].name

        # Fixed contract: ArcFace-family inputs are 112x112; output is 512-D.
        self.dim = 512
        self.metric = cfg.get("metric", "cosine")
        self.role = cfg.get("role", "ceiling")

    # ------------------------------------------------------------------ embed
    def embed(self, image_bgr: np.ndarray, det: Detection) -> np.ndarray:
        """Align -> preprocess -> run -> L2-normalize. Returns 1-D float32 (512,)."""
        # det.landmarks are already in ArcFace template order (eyes, nose, mouth),
        # so align_arcface warps straight to the canonical 112x112 frame.
        aligned = common.align_arcface(image_bgr, det.landmarks, 112)  # BGR uint8

        # Channel order: buffalo_l wants RGB (insightface swapRB=True); AdaFace
        # is fed BGR exactly as align_arcface produces it.
        if self.color == "rgb":
            face = cv2.cvtColor(aligned, cv2.COLOR_BGR2RGB)
        else:
            face = aligned

        face = face.astype(np.float32)

        # Normalization — both recipes map pixel values into roughly [-1, 1].
        if self.norm == "arcface":
            face = (face - _ARCFACE_MEAN) / _ARCFACE_STD       # (x - 127.5)/127.5
        else:  # adaface
            face = (face / 255.0 - 0.5) / 0.5                  # (x/255 - 0.5)/0.5

        # HWC -> CHW -> NCHW float32 (1, 3, 112, 112), contiguous for ORT.
        blob = np.transpose(face, (2, 0, 1))[np.newaxis, ...]
        blob = np.ascontiguousarray(blob, dtype=np.float32)

        out = self.session.run([self.output_name], {self.input_name: blob})[0]
        return common.l2_normalize(out.ravel().astype(np.float32))
