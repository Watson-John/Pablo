#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Detection recall bake-off on OUR faces_db crops.

Detection is the pipeline's real bottleneck (YuNet ~70% on scans). Each crop IS a
Picasa-confirmed face, so 'recall' = does the detector find a face in the crop.
Compares YuNet vs SCRFD-10G (Apache) vs dlib-CNN vs dlib-HOG vs Haar, and reports
how many of YuNet's MISSES each recovers (+ the union ceiling).
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from common import load_face_db, load_image_bgr  # noqa: E402
from detect.yunet import YuNetDetector  # noqa: E402
import yaml  # noqa: E402

DB = "/tmp/full_db/manifest.csv"
M = ROOT / "models"


# ----------------------------------------------------------------- SCRFD decode
class SCRFD:
    def __init__(self, path, thresh=0.5, size=320):
        ort.set_default_logger_severity(3)   # silence per-inference shape warnings
        so = ort.SessionOptions()
        so.log_severity_level = 4
        self.s = ort.InferenceSession(str(path), sess_options=so,
                                      providers=["CPUExecutionProvider"])
        self.inp = self.s.get_inputs()[0].name
        self.outs = [o.name for o in self.s.get_outputs()]
        self.thresh, self.size = thresh, size

    def detect(self, img_bgr):
        h0, w0 = img_bgr.shape[:2]
        sz = self.size
        scale = sz / max(h0, w0)
        rw, rh = int(round(w0 * scale)), int(round(h0 * scale))
        resized = cv2.resize(img_bgr, (rw, rh))
        canvas = np.zeros((sz, sz, 3), np.uint8)
        canvas[:rh, :rw] = resized
        blob = cv2.dnn.blobFromImage(canvas, 1.0 / 128, (sz, sz),
                                     (127.5, 127.5, 127.5), swapRB=True)
        outs = self.s.run(self.outs, {self.inp: blob})
        # Group outputs by last dim: 1=score, 4=bbox, 10=kps; sort by #points (stride 8,16,32).
        score_o = sorted([o for o in outs if o.shape[-1] == 1], key=lambda a: -a.shape[-2] if a.ndim > 1 else -a.size)
        bbox_o = sorted([o for o in outs if o.shape[-1] == 4], key=lambda a: -a.shape[-2])
        boxes = []
        for idx, stride in enumerate((8, 16, 32)):
            scores = score_o[idx].reshape(-1)
            bpred = bbox_o[idx].reshape(-1, 4) * stride
            fh, fw = sz // stride, sz // stride
            ac = np.stack(np.mgrid[:fh, :fw][::-1], -1).astype(np.float32).reshape(-1, 2) * stride
            ac = np.stack([ac, ac], 1).reshape(-1, 2)        # 2 anchors per cell
            keep = np.where(scores >= self.thresh)[0]
            for i in keep:
                cx, cy = ac[i]
                x1, y1 = cx - bpred[i, 0], cy - bpred[i, 1]
                x2, y2 = cx + bpred[i, 2], cy + bpred[i, 3]
                boxes.append((x1 / scale, y1 / scale, x2 / scale, y2 / scale, float(scores[i])))
        return boxes      # may be empty


def main():
    faces = load_face_db(DB)
    cfg = yaml.safe_load(open(ROOT / "config.yaml"))
    yunet = YuNetDetector(cfg["detector"], ROOT)
    scrfd = SCRFD(M / "scrfd_10g_bnkps.onnx")
    import dlib
    cnn = dlib.cnn_face_detection_model_v1(str(M / "mmod_human_face_detector.dat"))
    hog = dlib.get_frontal_face_detector()
    haar = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")

    def d_yunet(img):
        return bool(yunet.detect(img))

    def d_scrfd(img):
        return bool(scrfd.detect(img))

    def d_cnn(img):
        rgb = np.ascontiguousarray(img[:, :, ::-1])
        return len(cnn(rgb, 1)) > 0

    def d_hog(img):
        rgb = np.ascontiguousarray(img[:, :, ::-1])
        return len(hog(rgb, 1)) > 0

    def d_haar(img):
        g = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        return len(haar.detectMultiScale(g, 1.1, 3, minSize=(20, 20))) > 0

    dets = {"yunet": d_yunet, "scrfd_10g": d_scrfd, "dlib_cnn": d_cnn,
            "dlib_hog": d_hog, "haar": d_haar}
    hit = {k: set() for k in dets}
    total = 0
    for e in faces:
        img = load_image_bgr(e.crop_path)
        if img is None:
            continue
        total += 1
        for k, fn in dets.items():
            try:
                if fn(img):
                    hit[k].add(e.face_id)
            except Exception:
                pass
    yunet_miss = {e.face_id for e in faces if e.face_id not in hit["yunet"]
                  and load_image_bgr(e.crop_path) is not None}
    print(f"detection recall on {total} face crops:\n")
    print(f"  {'detector':10s} {'recall':>8s}   {'of YuNet-misses recovered':>26s}")
    for k in dets:
        rec = len(hit[k]) / total
        recov = len(hit[k] & yunet_miss) / max(1, len(yunet_miss))
        print(f"  {k:10s} {rec:8.1%}   {recov:>25.1%}")
    union = set().union(*hit.values())
    best_pair = max(((a, b, len(hit[a] | hit[b])) for a in dets for b in dets if a < b),
                    key=lambda t: t[2])
    print(f"\n  union (any detector): {len(union)/total:.1%}")
    print(f"  best 2-detector combo: {best_pair[0]}+{best_pair[1]} = {best_pair[2]/total:.1%}")
    print(f"  (YuNet missed {len(yunet_miss)} = {len(yunet_miss)/total:.1%})")


if __name__ == "__main__":
    main()
