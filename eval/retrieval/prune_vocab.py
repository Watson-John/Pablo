#!/usr/bin/env python3
"""Vocab-pruned SigLIP2 text tower for Pablo semantic search.

The Gemma token-embedding table (256000 x 768 = ~197M params) dominates
semantic_text.onnx. Pablo only ever embeds lowercased ENGLISH queries, so we
prune the table to the token ids actually reachable from English text and
insert an in-graph int32 id-remap Gather so the C++ app needs ZERO changes:
the model still accepts raw Gemma ids in [0, 256000).

Pipeline (deterministic given the corpus files):
  1. KEPT-ID SET   tokenize (HF GemmaTokenizerFast, lowercased — Pablo
                   lowercases queries) all Flickr30k captions, every word of
                   /usr/share/dict/words (lowercased), the 10 eval queries,
                   golden.json fixture texts and a ~200-word photo-search
                   vocab.  Union of ids + specials {0 pad, 1 eos, 2 bos, 3 unk}.
  2. SURGERY       new_table = old_table[kept_ids_sorted]; remap int32[256000]
                   maps old id -> new row (unkept -> new row of unk id 3).
                   Insert Gather(remap, ids) in front of the (pruned)
                   embedding Gather.  Nothing else in the graph is touched.
                   -> semantic_text_en.onnx (fp32)
  3. EXACTNESS     fp32 pruned vs fp32 full on 10 queries + 50 random
                   captions: cosine >= 0.999999 required (rows are byte
                   copies, so expect bit-identical).
  4. OOV           emoji / Cyrillic query must not crash: maps through unk,
                   returns a finite vector.
  5. QUANTIZE      onnxruntime quantize_dynamic QInt8
                   -> semantic_text_en.int8.onnx
  6. RETRIEVAL     mirror eval_siglip2.py: cached image embeddings
                   (eval_img_emb.npz, first 3000 Flickr30k images),
                   caption-keyword relevance, queries embedded via the FULL
                   int8 model vs the PRUNED int8 model.
                   Gate: |dmAP| <= 0.005 and |dP@5| <= 0.02.

Usage:
    source .venv-semantic/bin/activate
    python eval/retrieval/prune_vocab.py

Prints a final "RESULT {json}" line with sizes, sha256s and gate results.
"""
import csv
import hashlib
import json
import os
import random
import sys

import numpy as np
import onnx
from onnx import helper, numpy_helper

CKPT = "google/siglip2-base-patch16-224"
MODELS = os.path.expanduser("~/pablo-semantic-models")
SRC_FP32 = os.path.join(MODELS, "semantic_text.onnx")
REF_INT8 = os.path.join(MODELS, "semantic_text.int8.onnx")
OUT_FP32 = os.path.join(MODELS, "semantic_text_en.onnx")
OUT_INT8 = os.path.join(MODELS, "semantic_text_en.int8.onnx")
GOLDEN = os.path.join(MODELS, "golden.json")
IMG_EMB = os.path.join(MODELS, "eval_img_emb.npz")
CSV_PATH = "/Users/johnwatson/Documents/Personal/Pablo/flickr30k_images/results.csv"
WORDS = "/usr/share/dict/words"
SEQ = 64
PAD, EOS, BOS, UNK = 0, 1, 2, 3
SEED = 20260701

# Same queries + relevance keywords as eval_siglip2.py (kept in sync manually).
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

# ~200-word photo-search vocabulary: things people actually type into a photo
# app.  All lowercase (Pablo lowercases queries before tokenizing).
PHOTO_VOCAB = """
red orange yellow green blue purple pink brown black white gray grey gold
silver teal turquoise maroon beige navy violet magenta cyan
spring summer autumn fall winter rain rainbow storm cloud cloudy sunny fog
mist ice frost lightning thunder wind
birthday party graduation christmas halloween easter thanksgiving parade
concert festival picnic vacation holiday anniversary ceremony celebration
barbecue camping hike fireworks costume
bicycle motorcycle boat train airplane bus flower plant grass river
waterfall bridge road street fence bench umbrella balloon cake candle gift
toy ball kite guitar piano drum phone camera computer laptop television
chair table sofa bed lamp mirror clock painting statue fountain
cat puppy kitten horse cow sheep goat pig chicken duck bird fish rabbit
deer bear lion tiger elephant monkey butterfly bee spider snake turtle
frog squirrel fox wolf owl eagle
park garden city town village farm desert island harbor airport station
school church temple museum restaurant cafe market store mall zoo stadium
playground pool gym office kitchen bathroom bedroom garage yard porch
balcony rooftop
mother father mom dad sister brother baby child children kid grandmother
grandfather grandma grandpa aunt uncle cousin wife husband family friend
couple twins
man woman boy girl smile laugh run jump swim dance sing play eat drink
sleep walk sit stand hug kiss wave climb ride surf ski skate cook read
write paint draw
portrait selfie landscape closeup panorama blur night day indoor outdoor
sunrise silhouette reflection shadow
""".split()


def log(*a):
    print(*a, flush=True)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def load_captions():
    caps = []
    with open(CSV_PATH, newline="") as f:
        for row in csv.reader(f, delimiter="|"):
            if len(row) < 3 or row[0].strip() == "image_name":
                continue
            caps.append(row[2].strip().lower())
    return caps


def load_caption_map():
    """image file -> list of lowercased captions (for relevance sets)."""
    caps = {}
    with open(CSV_PATH, newline="") as f:
        for row in csv.reader(f, delimiter="|"):
            if len(row) < 3 or row[0].strip() == "image_name":
                continue
            caps.setdefault(row[0].strip(), []).append(row[2].strip().lower())
    return caps


# ---------------------------------------------------------------- step 1
def build_kept_ids(tok):
    captions = load_captions()
    with open(WORDS, encoding="utf-8", errors="ignore") as f:
        words = sorted({w.strip().lower() for w in f if w.strip()})
    golden_texts = [t["text"] for t in json.load(open(GOLDEN))["tokens"]]
    texts = (captions + words + [q.lower() for q in QUERIES]
             + PHOTO_VOCAB + [t.lower() for t in golden_texts])
    log(f"[1] tokenizing {len(texts)} texts "
        f"({len(captions)} captions, {len(words)} dict words, "
        f"{len(QUERIES)} queries, {len(PHOTO_VOCAB)} photo vocab, "
        f"{len(golden_texts)} golden fixtures)")
    kept = {PAD, EOS, BOS, UNK}
    B = 20000
    for i in range(0, len(texts), B):
        for ids in tok(texts[i:i + B], add_special_tokens=False)["input_ids"]:
            kept.update(ids)
    log(f"[1] kept-id count: {len(kept)} of {tok.vocab_size} "
        f"({100 * len(kept) / tok.vocab_size:.1f}%)")
    return sorted(kept)


# ---------------------------------------------------------------- step 2
def prune_graph(kept_sorted):
    log(f"[2] loading {SRC_FP32}")
    model = onnx.load(SRC_FP32)
    g = model.graph
    inits = {i.name: i for i in g.initializer}

    # Locate the token-embedding Gather: a Gather whose data input is a big
    # 2-D float initializer [vocab, hidden] (vocab >= 100k).
    embed_node, embed_init = None, None
    for n in g.node:
        if n.op_type != "Gather" or n.input[0] not in inits:
            continue
        init = inits[n.input[0]]
        if len(init.dims) == 2 and init.dims[0] >= 100_000:
            embed_node, embed_init = n, init
            break
    assert embed_node is not None, "token-embedding Gather not found"
    vocab, hidden = embed_init.dims
    log(f"[2] embedding init '{embed_init.name}' [{vocab},{hidden}] "
        f"gathered by node '{embed_node.name}' (ids tensor "
        f"'{embed_node.input[1]}')")
    assert vocab == 256000 and hidden == 768

    kept = np.asarray(kept_sorted, dtype=np.int64)
    assert kept[0] >= 0 and kept[-1] < vocab and np.all(np.diff(kept) > 0)
    new_unk_row = int(np.searchsorted(kept, UNK))
    assert kept[new_unk_row] == UNK

    old_table = numpy_helper.to_array(embed_init)
    new_table = np.ascontiguousarray(old_table[kept])
    remap = np.full(vocab, new_unk_row, dtype=np.int32)
    remap[kept] = np.arange(len(kept), dtype=np.int32)

    # Swap in the pruned table (same name — nothing downstream changes).
    new_init = numpy_helper.from_array(new_table, name=embed_init.name)
    g.initializer.remove(embed_init)
    g.initializer.append(new_init)

    # remap Gather: old ids (int64) -> new row indices (int32), inserted
    # right in front of the embedding Gather, which now reads remapped ids.
    remap_name = "pablo_en_vocab_remap"
    g.initializer.append(numpy_helper.from_array(remap, name=remap_name))
    remap_node = helper.make_node(
        "Gather", [remap_name, embed_node.input[1]],
        ["pablo_en_remapped_ids"],
        name="/text_model/embeddings/token_embedding/VocabRemap")
    pos = list(g.node).index(embed_node)
    g.node.insert(pos, remap_node)
    embed_node.input[1] = "pablo_en_remapped_ids"

    onnx.checker.check_model(model)
    onnx.save(model, OUT_FP32)
    log(f"[2] wrote {OUT_FP32} "
        f"({os.path.getsize(OUT_FP32) / 1e6:.1f} MB, kept {len(kept)} rows)")
    return embed_init.name


# ------------------------------------------------------------- inference
def encode(tok, text):
    """Pablo's exact text pipeline: lowercase -> SP encode -> +EOS, pad to 64."""
    ids = tok(text.lower(), add_special_tokens=False)["input_ids"][:SEQ - 1]
    ids = ids + [EOS] + [PAD] * (SEQ - 1 - len(ids))
    return ids


def embed(session, tok, texts):
    ids = np.asarray([encode(tok, t) for t in texts], dtype=np.int64)
    out = session.run(["text_embeds"], {"input_ids": ids})[0]
    return out.astype(np.float32)


def make_session(path):
    import onnxruntime as ort
    opts = ort.SessionOptions()
    opts.log_severity_level = 3
    return ort.InferenceSession(path, opts, providers=["CPUExecutionProvider"])


# ---------------------------------------------------------------- step 3
def exactness_gate(tok):
    captions = load_captions()
    rng = random.Random(SEED)
    texts = list(QUERIES) + rng.sample(captions, 50)
    log(f"[3] fp32 exactness on {len(texts)} texts (10 queries + 50 captions)")
    full = embed(make_session(SRC_FP32), tok, texts)
    pruned = embed(make_session(OUT_FP32), tok, texts)
    cos = np.sum(full * pruned, axis=1) / (
        np.linalg.norm(full, axis=1) * np.linalg.norm(pruned, axis=1))
    bit_identical = int(np.sum(np.all(full == pruned, axis=1)))
    log(f"[3] min cosine {cos.min():.9f}  max|diff| "
        f"{np.abs(full - pruned).max():.3g}  bit-identical "
        f"{bit_identical}/{len(texts)}")
    ok = bool(cos.min() >= 0.999999)
    log(f"[3] exactness gate: {'PASS' if ok else 'FAIL'}")
    return ok, float(cos.min()), bit_identical, len(texts)


# ---------------------------------------------------------------- step 4
def oov_gate(tok):
    texts = ["снег зимой ❄️", "photo of 🐕🌲", "日本の写真"]
    out = embed(make_session(OUT_FP32), tok, texts)
    ok = bool(np.all(np.isfinite(out)))
    norms = np.linalg.norm(out, axis=1)
    log(f"[4] OOV gate ({len(texts)} non-English/emoji queries): "
        f"finite={ok} norms={np.round(norms, 4).tolist()} -> "
        f"{'PASS' if ok else 'FAIL'}")
    return ok


# ---------------------------------------------------------------- step 5
def quantize():
    from onnxruntime.quantization import QuantType, quantize_dynamic
    log(f"[5] quantize_dynamic QInt8 -> {OUT_INT8}")
    quantize_dynamic(OUT_FP32, OUT_INT8, weight_type=QuantType.QInt8)
    log(f"[5] wrote {OUT_INT8} ({os.path.getsize(OUT_INT8) / 1e6:.1f} MB)")


# ---------------------------------------------------------------- step 6
def average_precision(order, relevant):
    if not relevant:
        return float("nan")
    hits, s = 0, 0.0
    for i, idx in enumerate(order, 1):
        if idx in relevant:
            hits += 1
            s += hits / i
    return s / len(relevant)


def retrieval_metrics(qemb, img_emb, rel, qtexts):
    sims = qemb @ img_emb.T
    maps, p5s = [], []
    for qi, q in enumerate(qtexts):
        order = np.argsort(-sims[qi]).tolist()
        maps.append(average_precision(order, rel[q]))
        p5s.append(sum(1 for i in order[:5] if i in rel[q]) / 5)
    return float(np.nanmean(maps)), float(np.mean(p5s)), maps, p5s


def retrieval_gate(tok):
    d = np.load(IMG_EMB, allow_pickle=True)
    files, img_emb = list(d["files"]), d["emb"]
    img_emb = np.nan_to_num(img_emb, nan=0.0, posinf=0.0, neginf=0.0)
    n = np.linalg.norm(img_emb, axis=1, keepdims=True)
    img_emb = img_emb / np.where(n == 0, 1.0, n)
    log(f"[6] retrieval gate on {len(files)} cached image embeddings")

    caps = load_caption_map()
    rel = {q: set() for q in QUERIES}
    for idx, fn in enumerate(files):
        text = " ".join(caps.get(fn, []))
        for q, kws in QUERIES.items():
            if any(k in text for k in kws):
                rel[q].add(idx)

    qtexts = list(QUERIES)
    q_full = embed(make_session(REF_INT8), tok, qtexts)
    q_prun = embed(make_session(OUT_INT8), tok, qtexts)
    qcos = np.sum(q_full * q_prun, axis=1) / (
        np.linalg.norm(q_full, axis=1) * np.linalg.norm(q_prun, axis=1))
    log(f"[6] int8 query-embed cosine full-vs-pruned: "
        f"min {qcos.min():.6f} mean {qcos.mean():.6f}")

    map_a, p5_a, maps_a, p5s_a = retrieval_metrics(q_full, img_emb, rel, qtexts)
    map_b, p5_b, maps_b, p5s_b = retrieval_metrics(q_prun, img_emb, rel, qtexts)
    log(f"[6] {'query':14s} {'#rel':>5s}  mAP(full) mAP(pruned)  "
        f"P@5(full) P@5(pruned)")
    for i, q in enumerate(qtexts):
        log(f"[6] {q:14s} {len(rel[q]):5d}  {maps_a[i]:9.4f} "
            f"{maps_b[i]:11.4f}  {p5s_a[i]:9.2f} {p5s_b[i]:11.2f}")
    log(f"[6] MEAN mAP full={map_a:.4f} pruned={map_b:.4f} "
        f"(d={map_b - map_a:+.4f})  P@5 full={p5_a:.3f} pruned={p5_b:.3f} "
        f"(d={p5_b - p5_a:+.3f})")
    ok = bool(abs(map_b - map_a) <= 0.005 and abs(p5_b - p5_a) <= 0.02)
    log(f"[6] retrieval gate: {'PASS' if ok else 'FAIL'}")
    return ok, map_a, map_b, p5_a, p5_b


def main():
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(CKPT)
    assert tok.vocab_size == 256000

    kept = build_kept_ids(tok)
    init_name = prune_graph(kept)
    exact_ok, min_cos, bit_ident, n_exact = exactness_gate(tok)
    oov_ok = oov_gate(tok)
    quantize()
    ret_ok, map_a, map_b, p5_a, p5_b = retrieval_gate(tok)

    result = {
        "gate_passed": exact_ok and oov_ok and ret_ok,
        "kept_vocab": len(kept),
        "embedding_initializer": init_name,
        "exactness": {"min_cosine": min_cos, "bit_identical": bit_ident,
                      "n": n_exact, "pass": exact_ok},
        "oov_pass": oov_ok,
        "retrieval": {"map_full_int8": map_a, "map_pruned_int8": map_b,
                      "p5_full_int8": p5_a, "p5_pruned_int8": p5_b,
                      "pass": ret_ok},
        "artifacts": [
            {"file": OUT_FP32, "bytes": os.path.getsize(OUT_FP32),
             "sha256": sha256(OUT_FP32)},
            {"file": OUT_INT8, "bytes": os.path.getsize(OUT_INT8),
             "sha256": sha256(OUT_INT8)},
        ],
    }
    for a in result["artifacts"]:
        log(f"ARTIFACT {a['file']}  {a['bytes']} bytes  sha256={a['sha256']}")
    log("RESULT " + json.dumps(result))
    return 0 if result["gate_passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
