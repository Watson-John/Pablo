# Picasa face ingestion

Build a **labeled face database** from a Picasa-organized photo tree. Each face
Picasa tagged is cropped and filed under the person's name, producing:

- **Now** — the ground-truth input to the face-model evaluation harness (this
  module's `crops/<person>/` output *is* the eval's `eval_data/` folder).
- **Later** — a warm start for the app: every Picasa name is a human-confirmed
  label, so these crops can seed per-person prototype sets directly.

> **Never modifies source photos.** It only reads them and writes crops +
> a manifest to a separate output directory.

## Sources

1. **`.picasa.ini` sidecars (primary)** — one INI per folder with a
   `[Contacts2]` map (`hash=Name;;`) and per-image `faces=rect64(HEX),hash;...`
   lines. Section headers are filenames (matched to disk case-insensitively).
2. **Embedded XMP regions (fallback, `--xmp-fallback`)** — MWG `RegionList` or
   Microsoft People `RegionInfoMP`, read via exiftool. Used only for images with
   no INI entry, so faces are never double-counted.

## ⚠️ EXIF orientation — verified, and the opposite of the usual advice

The common guidance is "Picasa rectangles are relative to the *displayed* image,
so apply EXIF orientation first." **On this library that is wrong.** Annotating
real rotated photos (e.g. a phone portrait shot in landscape, EXIF orientation
6) shows the box lands on the face only when decoded against the **raw,
un-rotated** dimensions; decoding against the EXIF-oriented dimensions puts the
box on a torso/background.

So the default is **`--coord-space raw`**: decode the rect against raw
dimensions, crop, then rotate the *crop* upright. Orientation-1 photos (the bulk
of a scanned archive) are unaffected — the two modes are identical there.
`--coord-space display` selects the textbook interpretation for libraries where
it actually holds. **Always eyeball a few rotated-photo crops before trusting a
batch** (the failure is silent and partial — only rotated photos are wrong).

## rect64 decoding

The 16-hex value is four 16-bit uints (left, top, right, bottom), each / 65535.
**Picasa strips leading zeros**, so the hex may be 1–16 digits — left-pad to 16
before decoding or short rectangles silently corrupt. (Unit-tested.)

## RAW files

`.dng/.nef/.cr2/...` are **skipped by default**: Pillow only exposes the tiny
embedded thumbnail (a `.nef` decodes to 160×120), which would pollute the DB
with unusable crops. `--include-raw` opts in anyway; proper preview extraction
(exiftool `-JpgFromRaw`) is a TODO.

## Usage

```bash
python build_face_db.py \
    --root "/Volumes/X9 Pro/Pictures Partailly Sorted 2025" \
    --out  ./faces_db \
    --pad 0.2            # Picasa boxes are tight; pad 20% and clamp

# Options:
#   --coord-space raw|display   (default raw — see orientation note)
#   --keep-unknown              keep unresolved-hash faces as Unknown_<hash>
#   --min-size N                drop crops smaller than N px/side
#   --xmp-fallback              also read embedded XMP regions (needs exiftool)
#   --contacts-xml PATH         resolve stray hashes via Picasa db3/contacts.xml
#   --limit N                   stop after N faces (testing)
```

## Output

```
faces_db/
  manifest.csv
  crops/
    Roy Avery/Roy Avery__IMG_0001__0.jpg
    ...
```

`manifest.csv` columns: `face_id, person_name, contact_hash, source_image,
folder, bbox_px, bbox_norm, source, crop_path`. The `crops/<person>/` layout is
identical to the eval harness's `eval_data/` input — it drops straight in.

The hash `ffffffffffffffff` (detected-but-unnamed) is skipped from ground truth.
Faces are de-duped by `(source-image content hash, rect)` so a photo referenced
from overlapping folders isn't cropped twice.

## Layout & tests

```
eval/ingest/
  picasa_ini.py     # rect64 decode + INI parser (pure; highest silent-error risk)
  contacts_xml.py   # db3/contacts.xml hash→name fallback
  xmp_regions.py    # exiftool MWG / MS People reader (Source B)
  build_face_db.py  # orchestrator → crops/ + manifest.csv
  tests/            # unit tests for the pure parsing functions
```

Requirements: Python 3.9+, Pillow. exiftool only for `--xmp-fallback`.
Run tests: `python -m pytest eval/ingest/tests` (or `python tests/test_picasa_ini.py`).
