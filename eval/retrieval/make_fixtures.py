#!/usr/bin/env python3
"""Emit self-contained fixtures for the native SigLIP2 retrieval test: a few real
Flickr30k images pre-resized to 224x224 RGBA (raw bytes, so the C++ test needs no
JPEG decoder) + golden text/image embeddings for a numeric parity check.

    source .venv-semantic/bin/activate
    python eval/retrieval/make_fixtures.py
"""
import json
import os

import numpy as np
import torch
from PIL import Image
from transformers import AutoModel, AutoProcessor

CKPT = "google/siglip2-base-patch16-224"
OUT = os.path.expanduser(os.environ.get("OUT", "~/pablo-semantic-models"))
IMG = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/flickr30k_images"
# Top results from the spike (content-verified by captions).
PICS = {"tree": "10602072.jpg", "dog": "115275821.jpg", "car": "125382282.jpg"}
QUERIES = ["tree", "a dog", "a car"]

def main():
    os.makedirs(OUT, exist_ok=True)
    model = AutoModel.from_pretrained(CKPT).eval()
    proc = AutoProcessor.from_pretrained(CKPT)
    fx = {"images": {}, "queries": {}}

    # Images: resize to 224x224 bilinear, save RGBA raw; also record the model's
    # own embedding (so the C++ path can be checked for parity + retrieval).
    for label, fn in PICS.items():
        im = Image.open(os.path.join(IMG, fn)).convert("RGB").resize(
            (224, 224), Image.BILINEAR)
        rgba = im.convert("RGBA").tobytes()  # R,G,B,A per pixel, row-major
        with open(os.path.join(OUT, f"fixture_{label}.rgba"), "wb") as f:
            f.write(rgba)
        with torch.no_grad():
            v = model.get_image_features(**proc(images=[im], return_tensors="pt"))
            v = (v / v.norm(dim=-1, keepdim=True))[0].numpy()
        fx["images"][label] = {"file": f"fixture_{label}.rgba", "w": 224, "h": 224,
                               "emb": [float(x) for x in v]}

    for q in QUERIES:
        tin = proc(text=[q], padding="max_length", max_length=64, return_tensors="pt")
        with torch.no_grad():
            v = model.get_text_features(input_ids=tin["input_ids"])
            v = (v / v.norm(dim=-1, keepdim=True))[0].numpy()
        fx["queries"][q] = [float(x) for x in v]

    # Ground-truth retrieval ordering (what the C++ must reproduce).
    labels = list(PICS)
    order = {}
    for q in QUERIES:
        tv = np.array(fx["queries"][q])
        sims = {lab: float(tv @ np.array(fx["images"][lab]["emb"])) for lab in labels}
        order[q] = sorted(labels, key=lambda l: -sims[l])
    fx["expected_top"] = order
    with open(os.path.join(OUT, "fixtures.json"), "w") as f:
        json.dump(fx, f, indent=2)
    print("expected top-1 per query (Python ground truth):")
    for q, o in order.items():
        print(f"  {q:8s} -> {o[0]}")
    print(f"wrote fixtures to {OUT}")

if __name__ == "__main__":
    main()
