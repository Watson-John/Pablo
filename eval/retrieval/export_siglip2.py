#!/usr/bin/env python3
"""Export google/siglip2-base-patch16-224 image + text encoders to ONNX for the
native OnnxEmbedder, verify parity vs torch, and emit golden fixtures the C++
tokenizer/inference tests assert against.

Outputs (OUT dir, default ~/pablo-semantic-models):
  semantic_image.onnx      pixel_values[N,3,224,224] f32 -> image_embeds[N,768] (L2)
  semantic_text.onnx       input_ids[N,64] i64        -> text_embeds[N,768] (L2)
  semantic_tokenizer.model SentencePiece model (Gemma)
  golden.json              tokenizer + embedding fixtures for the C++ parity test

    source .venv-semantic/bin/activate
    python eval/retrieval/export_siglip2.py
"""
import hashlib
import json
import os
import sys

import numpy as np
import torch
from PIL import Image
from transformers import AutoModel, AutoProcessor, AutoTokenizer

CKPT = "google/siglip2-base-patch16-224"
OUT = os.path.expanduser(os.environ.get("OUT", "~/pablo-semantic-models"))
IMG_DIR = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/flickr30k_images"
SEQ = 64

def log(*a): print(*a, flush=True)

class ImageTower(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, pixel_values):
        f = self.m.get_image_features(pixel_values=pixel_values)
        return f / f.norm(p=2, dim=-1, keepdim=True)

class TextTower(torch.nn.Module):
    def __init__(self, m): super().__init__(); self.m = m
    def forward(self, input_ids):
        f = self.m.get_text_features(input_ids=input_ids)
        return f / f.norm(p=2, dim=-1, keepdim=True)

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def main():
    os.makedirs(OUT, exist_ok=True)
    log(f"loading {CKPT} …")
    model = AutoModel.from_pretrained(CKPT).eval()
    proc = AutoProcessor.from_pretrained(CKPT)
    # Slow tokenizer → writes the SentencePiece `tokenizer.model` the C++ lib loads.
    slow = AutoTokenizer.from_pretrained(CKPT, use_fast=False)

    # ── export the SentencePiece model ──
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        slow.save_pretrained(td)
        import shutil
        src = os.path.join(td, "tokenizer.model")
        if not os.path.exists(src):
            # some saves name it spiece.model
            for cand in ("spiece.model", "sentencepiece.bpe.model"):
                if os.path.exists(os.path.join(td, cand)):
                    src = os.path.join(td, cand); break
        shutil.copy(src, os.path.join(OUT, "semantic_tokenizer.model"))
    log("wrote semantic_tokenizer.model")

    # ── export ONNX ──
    img_path = os.path.join(OUT, "semantic_image.onnx")
    txt_path = os.path.join(OUT, "semantic_text.onnx")
    with torch.no_grad():
        torch.onnx.export(
            ImageTower(model), (torch.randn(1, 3, 224, 224),), img_path,
            input_names=["pixel_values"], output_names=["image_embeds"],
            dynamic_axes={"pixel_values": {0: "b"}, "image_embeds": {0: "b"}},
            opset_version=17, do_constant_folding=True)
        log("wrote semantic_image.onnx")
        torch.onnx.export(
            TextTower(model), (torch.zeros(1, SEQ, dtype=torch.long),), txt_path,
            input_names=["input_ids"], output_names=["text_embeds"],
            dynamic_axes={"input_ids": {0: "b"}, "text_embeds": {0: "b"}},
            opset_version=17, do_constant_folding=True)
        log("wrote semantic_text.onnx")

    # ── parity check: ONNX vs torch ──
    import onnxruntime as ort
    files = [f for f in sorted(os.listdir(IMG_DIR))
             if f.lower().endswith((".jpg", ".jpeg", ".png"))][:3]
    imgs = [Image.open(os.path.join(IMG_DIR, f)).convert("RGB") for f in files]
    queries = ["tree", "a dog on the beach", "wedding", "a red car", "snow"]

    pin = proc(images=imgs, return_tensors="pt")
    tin = proc(text=queries, padding="max_length", max_length=SEQ, return_tensors="pt")
    with torch.no_grad():
        t_img = ImageTower(model)(pin["pixel_values"]).numpy()
        t_txt = TextTower(model)(tin["input_ids"]).numpy()

    si = ort.InferenceSession(img_path, providers=["CPUExecutionProvider"])
    st = ort.InferenceSession(txt_path, providers=["CPUExecutionProvider"])
    o_img = si.run(None, {"pixel_values": pin["pixel_values"].numpy()})[0]
    o_txt = st.run(None, {"input_ids": tin["input_ids"].numpy().astype(np.int64)})[0]

    img_err = float(np.abs(o_img - t_img).max())
    txt_err = float(np.abs(o_txt - t_txt).max())
    log(f"parity: image max|Δ|={img_err:.2e}  text max|Δ|={txt_err:.2e}")
    assert img_err < 2e-3 and txt_err < 2e-3, "ONNX/torch parity failed"

    # cross-modal sanity through ONNX: query 'tree' should top image[0..2] sensibly
    sims = o_txt @ o_img.T
    log("ONNX cross-modal sims (queries x 3 imgs):\n", np.round(sims, 3))

    # ── golden fixtures for the C++ parity test ──
    golden = {
        "ckpt": CKPT, "seq": SEQ, "dim": int(t_img.shape[1]),
        "image_mean": 0.5, "image_std": 0.5, "image_side": 224,
        "eos_id": slow.eos_token_id, "pad_id": slow.pad_token_id,
        "tokens": [],
        "text_embeds": [],
    }
    for q in ["tree", "a dog", "wedding", "beach", "snow", "car",
              "a group of people", "document", "sunset", "a building"]:
        ids = proc(text=[q], padding="max_length", max_length=SEQ,
                   return_tensors="np")["input_ids"][0].astype(int).tolist()
        golden["tokens"].append({"text": q, "ids": ids})
    # a couple of full text embeddings (first 16 dims) for numeric parity
    for q in ["tree", "a red car"]:
        tt = proc(text=[q], padding="max_length", max_length=SEQ, return_tensors="pt")
        with torch.no_grad():
            v = TextTower(model)(tt["input_ids"]).numpy()[0]
        golden["text_embeds"].append({"text": q, "head16": [float(x) for x in v[:16]]})
    with open(os.path.join(OUT, "golden.json"), "w") as f:
        json.dump(golden, f, indent=2)
    log("wrote golden.json")

    # ── sizes + hashes ──
    for name in ("semantic_image.onnx", "semantic_text.onnx", "semantic_tokenizer.model"):
        p = os.path.join(OUT, name)
        log(f"  {name:26s} {os.path.getsize(p)/1e6:8.1f} MB  sha256={sha256(p)[:16]}…")
    log(f"\nOK — exported to {OUT}")

if __name__ == "__main__":
    sys.exit(main())
