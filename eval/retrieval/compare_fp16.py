#!/usr/bin/env python3
"""Quantize the exported SigLIP2 ONNX to fp16 (and int8-dynamic for size) and
measure the difference vs fp32: file size, per-embedding cosine drift, and the
10-query text→image retrieval metrics on Flickr30k.

    source .venv-semantic/bin/activate
    python eval/retrieval/compare_fp16.py           # N=1500 default
"""
import csv
import os
import time

import numpy as np
import onnx
import onnxruntime as ort
from onnxconverter_common import float16
from PIL import Image
from transformers import AutoProcessor

CKPT = "google/siglip2-base-patch16-224"
M = os.path.expanduser("~/pablo-semantic-models")
IMG = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/flickr30k_images"
CSV = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/results.csv"
N = int(os.environ.get("N", "1500"))
QUERIES = {
    "tree": ["tree", "forest", "wood"], "wedding": ["wedding", "bride", "groom"],
    "beach": ["beach", "ocean", "sand", "shore", "surf"],
    "snow": ["snow", "ski", "snowboard", "winter"],
    "car": ["car", "vehicle", "truck", "taxi"], "dog": ["dog", "puppy"],
    "group photo": ["group", "crowd", "team", "posing"],
    "document": ["document", "paper", "book", "read", "sign"],
    "sunset": ["sunset", "sunrise", "dusk", "dawn"],
    "building": ["building", "house", "tower", "church", "architecture"],
}

def log(*a): print(*a, flush=True)
def mb(p): return os.path.getsize(p) / 1e6

def to_fp16(src, dst):
    # keep_io_types=True (fp32 I/O = drop-in) but leave the graph's PRE-EXISTING
    # Cast nodes in fp32 — onnxconverter-common mis-types them otherwise (the
    # SigLIP vision-embeddings Cast). The size win is in the big Gather/MatMul
    # weights, which still convert.
    m = onnx.load(src)
    casts = [n.name for n in m.graph.node if n.op_type == "Cast"]
    m16 = float16.convert_float_to_float16(m, keep_io_types=True, node_block_list=casts)
    onnx.save(m16, dst)

def to_int8(src, dst):
    from onnxruntime.quantization import quantize_dynamic, QuantType
    quantize_dynamic(src, dst, weight_type=QuantType.QInt8)

def norm(x):
    return x / (np.linalg.norm(x, axis=-1, keepdims=True) + 1e-12)

def _in_dtype(sess):
    return np.float16 if "float16" in sess.get_inputs()[0].type else np.float32

def embed_images(sess, files, proc):
    dt = _in_dtype(sess)
    out, B = [], 16
    for i in range(0, len(files), B):
        batch = []
        for fn in files[i:i+B]:
            try:
                batch.append(Image.open(os.path.join(IMG, fn)).convert("RGB"))
            except Exception:
                batch.append(Image.new("RGB", (224, 224)))
        px = proc(images=batch, return_tensors="np")["pixel_values"].astype(dt)
        out.append(sess.run(None, {"pixel_values": px})[0].astype(np.float32))
    return norm(np.nan_to_num(np.concatenate(out)))

def embed_texts(sess, texts, proc):
    ids = proc(text=texts, padding="max_length", max_length=64,
               return_tensors="np")["input_ids"].astype(np.int64)
    return norm(sess.run(None, {"input_ids": ids})[0].astype(np.float32))

def metrics(sims, rel, files):
    ks = [1, 5, 10]
    agg = {f"P@{k}": [] for k in ks}; maps = []
    for qi, q in enumerate(rel):
        order = np.argsort(-sims[qi]); relevant = rel[q]
        for k in ks:
            agg[f"P@{k}"].append(sum(1 for i in order[:k] if i in relevant) / k)
        hits = s = 0
        for i, idx in enumerate(order.tolist(), 1):
            if idx in relevant:
                hits += 1; s += hits / i
        maps.append(s / len(relevant) if relevant else np.nan)
    return {k: float(np.nanmean(v)) for k, v in agg.items()} | {"mAP": float(np.nanmean(maps))}

def main():
    img32, txt32 = f"{M}/semantic_image.onnx", f"{M}/semantic_text.onnx"
    img16, txt16 = f"{M}/semantic_image.fp16.onnx", f"{M}/semantic_text.fp16.onnx"
    txt8 = f"{M}/semantic_text.int8.onnx"; img8 = f"{M}/semantic_image.int8.onnx"

    log("converting fp16 …"); to_fp16(img32, img16); to_fp16(txt32, txt16)
    log("converting int8 (size reference) …"); to_int8(img32, img8); to_int8(txt32, txt8)

    log("\n=== FILE SIZE ===")
    log(f"  image:  fp32 {mb(img32):7.1f} MB | fp16 {mb(img16):7.1f} MB | int8 {mb(img8):7.1f} MB")
    log(f"  text:   fp32 {mb(txt32):7.1f} MB | fp16 {mb(txt16):7.1f} MB | int8 {mb(txt8):7.1f} MB")
    tot = lambda a, b: mb(a) + mb(b)
    log(f"  TOTAL:  fp32 {tot(img32,txt32):7.1f} MB | fp16 {tot(img16,txt16):7.1f} MB "
        f"| int8 {tot(img8,txt8):7.1f} MB")

    proc = AutoProcessor.from_pretrained(CKPT)
    files = [f for f in sorted(os.listdir(IMG)) if f.lower().endswith(".jpg")][:N]
    caps = {}
    with open(CSV, newline="") as f:
        for r in csv.reader(f, delimiter="|"):
            if len(r) >= 3 and r[0].strip() != "image_name":
                caps.setdefault(r[0].strip(), []).append(r[2].strip().lower())
    rel = {q: set() for q in QUERIES}
    for idx, fn in enumerate(files):
        t = " ".join(caps.get(fn, []))
        for q, kws in QUERIES.items():
            if any(k in t for k in kws): rel[q].add(idx)

    def sess(p): return ort.InferenceSession(p, providers=["CPUExecutionProvider"])
    log(f"\nembedding {len(files)} images @ fp32 and fp16 …")
    i32 = embed_images(sess(img32), files, proc)
    i16 = embed_images(sess(img16), files, proc)
    q32 = embed_texts(sess(txt32), list(QUERIES), proc)
    q16 = embed_texts(sess(txt16), list(QUERIES), proc)

    # per-embedding cosine drift fp16 vs fp32
    img_cos = float(np.mean(np.sum(i32 * i16, axis=1)))
    txt_cos = float(np.mean(np.sum(q32 * q16, axis=1)))
    log(f"\n=== PRECISION DRIFT (fp16 vs fp32, cosine; 1.0 = identical) ===")
    log(f"  image embeddings: {img_cos:.5f}   text embeddings: {txt_cos:.5f}")

    m32 = metrics(q32 @ i32.T, rel, files)
    m16 = metrics(q16 @ i16.T, rel, files)
    log(f"\n=== RETRIEVAL ({len(files)} imgs) ===")
    log(f"  {'':6s} P@1    P@5    P@10   mAP")
    log(f"  fp32   {m32['P@1']:.3f}  {m32['P@5']:.3f}  {m32['P@10']:.3f}  {m32['mAP']:.3f}")
    log(f"  fp16   {m16['P@1']:.3f}  {m16['P@5']:.3f}  {m16['P@10']:.3f}  {m16['mAP']:.3f}")
    log("\n(fp16 keeps fp32 I/O — a drop-in for the native OnnxEmbedder.)")

if __name__ == "__main__":
    main()
