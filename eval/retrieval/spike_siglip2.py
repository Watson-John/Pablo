#!/usr/bin/env python3
"""Spike: prove google/siglip2-base-patch16-224 does real text->image retrieval
on the Flickr30k library, and dump the EXACT tokenizer + preprocessing params we
must replicate in the C++ OnnxEmbedder.

Run inside the venv:
    source .venv-semantic/bin/activate
    python eval/retrieval/spike_siglip2.py
"""
import csv
import os
import sys
import time

import torch
from PIL import Image
from transformers import AutoModel, AutoProcessor

CKPT = "google/siglip2-base-patch16-224"
IMG_DIR = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/flickr30k_images"
CSV = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/results.csv"
N_IMAGES = int(os.environ.get("N_IMAGES", "800"))
QUERIES = ["tree", "a dog", "wedding", "beach", "snow", "car",
           "a group of people", "sunset", "a building", "person on a bicycle"]

def log(*a):
    print(*a, flush=True)

def main():
    log(f"loading {CKPT} …")
    t0 = time.time()
    model = AutoModel.from_pretrained(CKPT).eval()
    proc = AutoProcessor.from_pretrained(CKPT)
    log(f"loaded in {time.time()-t0:.1f}s")

    # ── GROUND TRUTH for the C++ port ──────────────────────────────────────
    tok = proc.tokenizer
    ip = proc.image_processor
    log("\n=== TOKENIZER ===")
    log("class:", type(tok).__name__)
    log("model_max_length:", tok.model_max_length)
    log("vocab_size:", tok.vocab_size)
    log("pad/eos/bos:", tok.pad_token_id, tok.eos_token_id, tok.bos_token_id)
    demo = proc(text=["a photo of a tree"], padding="max_length",
                max_length=64, return_tensors="pt")
    ids = demo["input_ids"][0].tolist()
    log("ids('a photo of a tree') len=%d:" % len(ids), ids[:20], "…")
    log("decoded:", repr(tok.decode([i for i in ids if i != tok.pad_token_id])))
    log("\n=== IMAGE PROCESSOR ===")
    log("class:", type(ip).__name__)
    log("size:", ip.size, "resample:", getattr(ip, "resample", None))
    log("mean/std:", ip.image_mean, ip.image_std,
        "rescale:", getattr(ip, "rescale_factor", None))
    log("dim:", model.config.text_config.hidden_size, "/",
        model.config.vision_config.hidden_size)

    # ── caption index for sanity checks ────────────────────────────────────
    caps = {}
    with open(CSV, newline="") as f:
        for row in csv.reader(f, delimiter="|"):
            if len(row) < 3 or row[0].strip() == "image_name":
                continue
            caps.setdefault(row[0].strip(), []).append(row[2].strip().lower())

    files = sorted(os.listdir(IMG_DIR))[:N_IMAGES]
    log(f"\nembedding {len(files)} images …")
    t0 = time.time()
    embs = []
    B = 32
    with torch.no_grad():
        for i in range(0, len(files), B):
            batch = []
            for fn in files[i:i+B]:
                try:
                    batch.append(Image.open(os.path.join(IMG_DIR, fn)).convert("RGB"))
                except Exception:
                    batch.append(Image.new("RGB", (224, 224)))
            inp = proc(images=batch, return_tensors="pt")
            e = model.get_image_features(**inp)
            e = e / e.norm(dim=-1, keepdim=True)
            embs.append(e)
            if i % 128 == 0:
                log(f"  {i+len(batch)}/{len(files)}")
    img_emb = torch.cat(embs)  # [N,768] L2-normalized
    dt = time.time() - t0
    log(f"embedded in {dt:.1f}s  ({1000*dt/len(files):.1f} ms/img)")

    # ── text queries → top-5 with caption hit-check ────────────────────────
    with torch.no_grad():
        tinp = proc(text=QUERIES, padding="max_length", max_length=64,
                    return_tensors="pt")
        txt = model.get_text_features(**tinp)
        txt = txt / txt.norm(dim=-1, keepdim=True)
    sims = txt @ img_emb.T  # [Q,N]

    log("\n=== RETRIEVAL (top-5 per query; ✓ = query word in a caption) ===")
    total_hit = 0
    for qi, q in enumerate(QUERIES):
        top = sims[qi].topk(5).indices.tolist()
        word = q.split()[-1]
        line = []
        for idx in top:
            fn = files[idx]
            hit = any(word in c for c in caps.get(fn, []))
            total_hit += hit
            line.append(("✓" if hit else "·") + fn)
        log(f"  {q:22s} -> {'  '.join(line)}")
    log(f"\ncaption-hit@5 (loose sanity): {total_hit}/{len(QUERIES)*5}")

if __name__ == "__main__":
    sys.exit(main())
