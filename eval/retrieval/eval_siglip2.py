#!/usr/bin/env python3
"""Text→image retrieval eval for google/siglip2-base-patch16-224 on the Flickr30k
library, using the dataset's own captions as (noisy) ground truth.

For each query a set of concept keywords defines relevance: an image is relevant
if any of its 5 captions contains any keyword. Reports Recall@k, Precision@k,
mAP + latency/throughput. Honest caveats: captions miss background content and
some concepts (e.g. 'document') are rare in Flickr30k, so absolute recall is a
floor, not a ceiling.

    source .venv-semantic/bin/activate
    python eval/retrieval/eval_siglip2.py            # default N=3000
"""
import csv
import os
import time

import numpy as np
import torch
from PIL import Image
from transformers import AutoModel, AutoProcessor

CKPT = "google/siglip2-base-patch16-224"
IMG = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/flickr30k_images"
CSV = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/results.csv"
N = int(os.environ.get("N", "3000"))
CACHE = os.path.expanduser("~/pablo-semantic-models/eval_img_emb.npz")

# query -> relevance keywords (substring match in any caption)
QUERIES = {
    "tree": ["tree", "forest", "wood"],
    "wedding": ["wedding", "bride", "groom", "marry"],
    "beach": ["beach", "ocean", "sea ", "sand", "shore", "surf"],
    "snow": ["snow", "ski", "snowboard", "winter"],
    "car": ["car", "vehicle", "automobile", "truck", "taxi"],
    "dog": ["dog", "puppy", "canine"],
    "group photo": ["group", "crowd", "team", "people pose", "posing"],
    "document": ["document", "paper", "book", "read", "newspaper", "sign"],
    "sunset": ["sunset", "sunrise", "dusk", "dawn"],
    "building": ["building", "house", "tower", "skyscraper", "church",
                 "architecture"],
}

def log(*a): print(*a, flush=True)

def main():
    caps = {}
    with open(CSV, newline="") as f:
        for row in csv.reader(f, delimiter="|"):
            if len(row) < 3 or row[0].strip() == "image_name":
                continue
            caps.setdefault(row[0].strip(), []).append(row[2].strip().lower())

    files = [f for f in sorted(os.listdir(IMG))
             if f.lower().endswith(".jpg")][:N]

    model = AutoModel.from_pretrained(CKPT).eval()
    proc = AutoProcessor.from_pretrained(CKPT)

    if os.path.exists(CACHE):
        d = np.load(CACHE, allow_pickle=True)
        if list(d["files"]) == files:
            img_emb = d["emb"]
            log(f"loaded cached embeddings for {len(files)} images")
        else:
            img_emb = None
    else:
        img_emb = None

    if img_emb is None:
        log(f"embedding {len(files)} images …")
        t0 = time.time()
        chunks, B = [], 32
        with torch.no_grad():
            for i in range(0, len(files), B):
                batch = []
                for fn in files[i:i+B]:
                    try:
                        batch.append(Image.open(os.path.join(IMG, fn)).convert("RGB"))
                    except Exception:
                        batch.append(Image.new("RGB", (224, 224)))
                e = model.get_image_features(**proc(images=batch, return_tensors="pt"))
                e = e / e.norm(dim=-1, keepdim=True)
                chunks.append(e.numpy().astype(np.float32))
                if i % 320 == 0:
                    log(f"  {i+len(batch)}/{len(files)}")
        img_emb = np.concatenate(chunks)
        dt = time.time() - t0
        log(f"embedded in {dt:.1f}s ({1000*dt/len(files):.1f} ms/img)")
        np.savez(CACHE, files=np.array(files), emb=img_emb)

    # A few unreadable/blank images can embed to non-finite values — zero them so
    # they simply never rank (keeps the matmul clean).
    img_emb = np.nan_to_num(img_emb, nan=0.0, posinf=0.0, neginf=0.0)

    # relevance sets from captions
    rel = {q: set() for q in QUERIES}
    for idx, fn in enumerate(files):
        text = " ".join(caps.get(fn, []))
        for q, kws in QUERIES.items():
            if any(k in text for k in kws):
                rel[q].add(idx)

    # query embeddings + ranking
    qtexts = list(QUERIES)
    with torch.no_grad():
        tin = proc(text=qtexts, padding="max_length", max_length=64,
                   return_tensors="pt")
        t0 = time.time()
        qe = model.get_text_features(input_ids=tin["input_ids"])
        qe = (qe / qe.norm(dim=-1, keepdim=True)).numpy()
        qlat = (time.time() - t0) / len(qtexts) * 1000
    sims = qe @ img_emb.T  # [Q,N]

    def ap(ranked, relevant):
        if not relevant:
            return float("nan")
        hits, s = 0, 0.0
        for i, idx in enumerate(ranked, 1):
            if idx in relevant:
                hits += 1
                s += hits / i
        return s / len(relevant)

    ks = [1, 5, 10]
    log(f"\nSigLIP2 retrieval on {len(files)} Flickr30k images "
        f"(query latency ~{qlat:.1f} ms, storage {img_emb.nbytes/1e6:.0f} MB "
        f"@ fp32, {img_emb.shape[1]}-d)\n")
    hdr = f"{'query':14s} {'#rel':>5s} " + " ".join(f'P@{k:<2d} R@{k:<3d}' for k in ks) + "  mAP"
    log(hdr); log("-" * len(hdr))
    agg = {f"P@{k}": [] for k in ks}
    agg.update({f"R@{k}": [] for k in ks})
    maps = []
    for qi, q in enumerate(qtexts):
        order = np.argsort(-sims[qi])
        relevant = rel[q]
        row = f"{q:14s} {len(relevant):5d} "
        for k in ks:
            topk = order[:k]
            hit = sum(1 for i in topk if i in relevant)
            p = hit / k
            r = hit / len(relevant) if relevant else float("nan")
            agg[f"P@{k}"].append(p); agg[f"R@{k}"].append(r)
            row += f"{p:4.2f} {r:5.2f} "
        m = ap(order.tolist(), relevant); maps.append(m)
        row += f" {m:4.2f}"
        log(row)
    log("-" * len(hdr))
    mean = f"{'MEAN':14s} {'':5s} "
    for k in ks:
        mean += f"{np.nanmean(agg[f'P@{k}']):4.2f} {np.nanmean(agg[f'R@{k}']):5.2f} "
    mean += f" {np.nanmean(maps):4.2f}"
    log(mean)
    log("\nNote: relevance = a query keyword appears in a caption — a NOISY floor "
        "(captions miss background objects; 'document' is rare in Flickr30k).")

if __name__ == "__main__":
    main()
