#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Build a labeled face database from a Picasa-organized photo tree.

Reads ``.picasa.ini`` face rectangles + contact names (Source A), optionally
falls back to embedded XMP regions (Source B), crops each named face, and writes
``crops/<person>/`` + ``manifest.csv``. The crops/<person>/ layout is identical
to the evaluation harness's ``eval_data/`` input, so the output drops straight in.

NEVER modifies source photos. Run:

    python build_face_db.py --root "/Volumes/X9 Pro/Pictures Partailly Sorted 2025" \\
        --out ./faces_db --pad 0.2

EXIF ORIENTATION (verified empirically on this library — read this):
  The spec assumed Picasa stores face rectangles relative to the *displayed*
  (EXIF-rotated) image. Annotating real rotated photos from this tree shows the
  OPPOSITE: the rectangles are relative to the RAW, un-rotated pixel buffer — the
  box lands on the face only when decoded against raw dimensions, and lands on a
  torso/background when decoded against the EXIF-oriented dimensions. So the
  default ``--coord-space raw`` decodes against raw dims and rotates the *crop*
  upright afterward. ``--coord-space display`` selects the spec's interpretation
  for libraries where that holds. For orientation-1 photos the two are identical.

See README.md for the full option list.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import sys
import unicodedata
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional, Tuple

from PIL import Image, ImageOps  # noqa: F401  (ImageOps kept for reference)

from contacts_xml import find_contacts_xml, load_contacts_xml
from picasa_ini import (
    UNNAMED_HASH,
    decode_rect64_norm,
    find_picasa_ini,
    parse_picasa_ini,
)
from xmp_regions import exiftool_available, named_face_regions, read_xmp_regions

# These are the user's own trusted photos; lift PIL's decompression-bomb guard.
Image.MAX_IMAGE_PIXELS = None

_UNSAFE = set('<>:"/\\|?*') | {chr(c) for c in range(32)}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".gif", ".webp"}
# RAW: Pillow only exposes a tiny embedded thumbnail (a .nef gives 160x120), so
# crops would be useless. Skipped by default; preview extraction is a TODO.
RAW_EXTS = {".dng", ".nef", ".cr2", ".cr3", ".arw", ".raf", ".rw2", ".orf",
            ".pef", ".srw", ".raw", ".nrw", ".sr2"}

# Maps an EXIF Orientation value to the PIL transpose that makes it upright
# (identical to what ImageOps.exif_transpose applies).
_ORIENT_TRANSPOSE = {
    2: Image.Transpose.FLIP_LEFT_RIGHT,
    3: Image.Transpose.ROTATE_180,
    4: Image.Transpose.FLIP_TOP_BOTTOM,
    5: Image.Transpose.TRANSPOSE,
    6: Image.Transpose.ROTATE_270,
    7: Image.Transpose.TRANSVERSE,
    8: Image.Transpose.ROTATE_90,
}
_EXIF_ORIENTATION_TAG = 0x0112  # 274


def slugify(name: str, max_len: int = 120) -> str:
    """Filesystem-safe folder/file component; preserves readable spaces/unicode.

    Caps length (most filesystems limit a path component to 255 bytes); an
    over-long name keeps a prefix plus a short hash of the full name so distinct
    long names stay distinct.
    """
    name = unicodedata.normalize("NFC", name)
    cleaned = "".join("_" if ch in _UNSAFE else ch for ch in name)
    cleaned = cleaned.strip().strip(".")
    if not cleaned:
        return "_unnamed"
    if len(cleaned) > max_len:
        suffix = "_" + hashlib.blake2b(name.encode("utf-8"), digest_size=4).hexdigest()
        cleaned = cleaned[: max_len - len(suffix)].rstrip() + suffix
    return cleaned


def content_key(path: Path) -> str:
    """Stable dedup key for a photo: size + sampled bytes (blake2b, 16 hex)."""
    h = hashlib.blake2b(digest_size=8)
    try:
        size = path.stat().st_size
        h.update(str(size).encode())
        with path.open("rb") as f:
            h.update(f.read(262144))           # first 256 KiB
            if size > 262144:
                f.seek(max(0, size - 262144))
                h.update(f.read(262144))        # last 256 KiB
    except OSError:
        return ""
    return h.hexdigest()


def git_worktree_root(path: Path) -> Optional[Path]:
    """Return the enclosing git work-tree root for ``path``, or None.

    Detects both a normal repo (``.git`` dir) and a worktree/submodule
    (``.git`` file). ``path`` need not exist yet.
    """
    p = path.resolve()
    for d in [p, *p.parents]:
        if (d / ".git").exists():
            return d
    return None


def build_case_index(folder: Path) -> Dict[str, Path]:
    """Map lowercased filename -> actual path (Picasa section names are Windows-cased)."""
    index: Dict[str, Path] = {}
    try:
        for entry in folder.iterdir():
            if entry.is_file():
                index.setdefault(entry.name.lower(), entry)
    except (OSError, PermissionError):
        pass
    return index


def apply_orientation(img: Image.Image, orientation: int) -> Image.Image:
    """Rotate/flip ``img`` upright for the given EXIF orientation value."""
    method = _ORIENT_TRANSPOSE.get(orientation)
    return img.transpose(method) if method is not None else img


def open_source(path: Path) -> Optional[Tuple[Image.Image, int]]:
    """Open a photo as RGB **without** applying orientation; return (img, orient).

    Returns None on decode failure. The caller decides how to use ``orient``
    (see --coord-space).
    """
    try:
        img = Image.open(path)
        img.load()
        orient = img.getexif().get(_EXIF_ORIENTATION_TAG, 1) or 1
        return img.convert("RGB"), int(orient)
    except (OSError, SyntaxError, ValueError):
        return None


def crop_face(
    img: Image.Image, box_norm: Tuple[float, float, float, float], pad: float
) -> Optional[Image.Image]:
    """Crop a padded face box (pad = fraction of box size), clamped to image."""
    w, h = img.size
    l, t, r, b = box_norm
    px_l, px_t, px_r, px_b = l * w, t * h, r * w, b * h
    bw, bh = px_r - px_l, px_b - px_t
    if bw <= 1 or bh <= 1:
        return None
    px_l -= bw * pad
    px_r += bw * pad
    px_t -= bh * pad
    px_b += bh * pad
    x0, y0 = max(0, int(round(px_l))), max(0, int(round(px_t)))
    x1, y1 = min(w, int(round(px_r))), min(h, int(round(px_b)))
    if x1 - x0 < 1 or y1 - y0 < 1:
        return None
    return img.crop((x0, y0, x1, y1))


@dataclass
class Stats:
    folders_with_ini: int = 0
    images_referenced: int = 0
    images_missing: int = 0
    images_unreadable: int = 0
    skipped_raw: int = 0
    faces_written: int = 0
    skipped_unnamed: int = 0
    skipped_unresolved: int = 0
    skipped_dup: int = 0
    skipped_tiny: int = 0
    skipped_error: int = 0
    xmp_faces_written: int = 0
    by_person: Counter = field(default_factory=Counter)


MANIFEST_COLS = [
    "face_id", "person_name", "contact_hash", "source_image",
    "folder", "bbox_px", "bbox_norm", "source", "crop_path",
]


class FaceDBBuilder:
    def __init__(self, args):
        self.args = args
        self.out = Path(args.out)
        self.crops_dir = self.out / "crops"
        self.pad = args.pad
        self.min_size = args.min_size
        self.keep_unknown = args.keep_unknown
        self.xmp_fallback = args.xmp_fallback
        self.coord_space = args.coord_space
        self.include_raw = args.include_raw
        self.global_contacts: Dict[str, str] = {}
        self.seen_faces: set = set()       # (content_key, rect_hex) dedup
        self.used_crop_paths: set = set()
        self.stats = Stats()
        self._writer = None
        self._mf = None

    # -- output helpers --
    def _open_manifest(self):
        self.out.mkdir(parents=True, exist_ok=True)
        self.crops_dir.mkdir(parents=True, exist_ok=True)
        self._mf = (self.out / "manifest.csv").open("w", newline="", encoding="utf-8")
        self._writer = csv.DictWriter(self._mf, fieldnames=MANIFEST_COLS)
        self._writer.writeheader()

    def _close(self):
        if self._mf:
            self._mf.close()

    def _unique_crop_path(self, person_slug: str, face_id: str) -> Path:
        person_dir = self.crops_dir / person_slug
        person_dir.mkdir(parents=True, exist_ok=True)
        base = person_dir / f"{face_id}.jpg"
        if str(base) not in self.used_crop_paths:
            self.used_crop_paths.add(str(base))
            return base
        n = 1
        while True:
            cand = person_dir / f"{face_id}_{n}.jpg"
            if str(cand) not in self.used_crop_paths:
                self.used_crop_paths.add(str(cand))
                return cand
            n += 1

    def _emit(self, *, name, chash, src_image: Path, folder: Path,
              crop_src: Image.Image, crop_orient: int, box_norm, idx: int,
              source: str) -> bool:
        w, h = crop_src.size
        crop = crop_face(crop_src, box_norm, self.pad)
        if crop is None:
            self.stats.skipped_tiny += 1
            return False
        crop = apply_orientation(crop, crop_orient)   # rotate the crop upright
        if self.min_size and (crop.width < self.min_size or crop.height < self.min_size):
            self.stats.skipped_tiny += 1
            return False

        slug = slugify(name)
        face_id = f"{slug}__{src_image.stem}__{idx}"
        if len(face_id) > 150:   # keep the crop filename under FS component limits
            face_id = face_id[:140] + "_" + hashlib.blake2b(
                face_id.encode("utf-8"), digest_size=4).hexdigest()
        # Path creation + save can fail (too-long/odd path, permissions); skip the
        # one face and keep going rather than aborting the whole walk.
        try:
            crop_path = self._unique_crop_path(slug, face_id)
            crop.save(crop_path, "JPEG", quality=95)
        except OSError:
            self.stats.skipped_error += 1
            return False

        l, t, r, b = box_norm
        self._writer.writerow({
            "face_id": crop_path.stem,
            "person_name": name,
            "contact_hash": chash,
            "source_image": str(src_image.resolve()),
            "folder": str(folder),
            "bbox_px": f"{l*w:.1f},{t*h:.1f},{r*w:.1f},{b*h:.1f}",
            "bbox_norm": f"{l:.6f},{t:.6f},{r:.6f},{b:.6f}",
            "source": source,
            "crop_path": str(crop_path),
        })
        self.stats.by_person[name] += 1
        return True

    # -- main walk --
    def run(self):
        root = Path(self.args.root)
        if not root.is_dir():
            print(f"error: root not found: {root}", file=sys.stderr)
            return 1

        # PII guard: the output is face crops + a manifest of names and absolute
        # photo paths. Refuse to write it inside a git work tree (where a routine
        # `git add -A` would commit it) unless explicitly overridden.
        gitroot = git_worktree_root(self.out)
        if gitroot and not self.args.allow_in_repo:
            print(
                f"error: --out '{self.out}' is inside a git work tree ({gitroot}).\n"
                f"  This would write face crops + a names/paths manifest (PII) into\n"
                f"  version control. Pick an --out outside the repo, or pass\n"
                f"  --allow-in-repo to override (ensure .gitignore covers it).",
                file=sys.stderr,
            )
            return 2

        if self.args.contacts_xml:
            self.global_contacts = load_contacts_xml(Path(self.args.contacts_xml))
        elif self.args.find_contacts_xml:
            cx = find_contacts_xml([root])
            if cx:
                self.global_contacts = load_contacts_xml(cx)
                print(f"contacts.xml: {cx} ({len(self.global_contacts)} contacts)")

        if self.xmp_fallback and not exiftool_available():
            print("warning: --xmp-fallback set but exiftool not on PATH; skipping XMP",
                  file=sys.stderr)
            self.xmp_fallback = False

        self._open_manifest()
        try:
            for dirpath, _dirnames, _filenames in os.walk(root):
                folder = Path(dirpath)
                ini = find_picasa_ini(folder)
                if ini is None:
                    continue
                self._process_folder(folder, ini)
                if self.args.limit and self.stats.faces_written >= self.args.limit:
                    print(f"(reached --limit {self.args.limit})")
                    break
        finally:
            self._close()

        self._print_summary()
        return 0

    def _prepare_crop_source(self, img_raw: Image.Image, orient: int,
                             display: bool) -> Tuple[Image.Image, int]:
        """Return (image_to_decode_against, orientation_to_apply_to_crop).

        display=True  -> orient the whole image first; boxes are display-relative.
        display=False -> decode against the raw buffer; orient the crop after.
        """
        if display:
            return apply_orientation(img_raw, orient), 1
        return img_raw, orient

    def _process_folder(self, folder: Path, ini: Path):
        contacts, faces_by_file = parse_picasa_ini(ini)
        if not faces_by_file:
            return
        self.stats.folders_with_ini += 1
        case_index = build_case_index(folder)

        def resolve_name(chash: str) -> Optional[str]:
            return contacts.get(chash) or self.global_contacts.get(chash)

        ini_referenced = set()
        for section, recs in faces_by_file.items():
            actual = case_index.get(section.lower())
            if actual is None:
                self.stats.images_missing += 1
                continue
            ini_referenced.add(actual.name.lower())
            if actual.suffix.lower() in RAW_EXTS and not self.include_raw:
                self.stats.skipped_raw += 1
                continue
            self.stats.images_referenced += 1

            opened = open_source(actual)
            if opened is None:
                self.stats.images_unreadable += 1
                continue
            img_raw, orient = opened
            crop_src, crop_orient = self._prepare_crop_source(
                img_raw, orient, display=self.coord_space == "display")
            ckey = content_key(actual)

            for idx, (chash, rect_hex) in enumerate(recs):
                if chash == UNNAMED_HASH:
                    self.stats.skipped_unnamed += 1
                    continue
                name = resolve_name(chash)
                if name is None:
                    if self.keep_unknown:
                        name = f"Unknown_{chash}"   # full hash — distinct unknowns stay distinct
                    else:
                        self.stats.skipped_unresolved += 1
                        continue
                dkey = (ckey, rect_hex.lower())
                if ckey and dkey in self.seen_faces:
                    self.stats.skipped_dup += 1
                    continue
                self.seen_faces.add(dkey)
                if self._emit(
                    name=name, chash=chash, src_image=actual, folder=folder,
                    crop_src=crop_src, crop_orient=crop_orient,
                    box_norm=decode_rect64_norm(rect_hex), idx=idx, source="ini",
                ):
                    self.stats.faces_written += 1

        if self.xmp_fallback:
            self._xmp_pass(folder, case_index, ini_referenced)

    def _xmp_pass(self, folder: Path, case_index: Dict[str, Path], ini_referenced: set):
        """Source B: images in this folder with no INI face entry.

        XMP MWG / MS regions are defined relative to the *displayed* image, so
        this path always orients the image first (unlike the Picasa-INI path).
        """
        for lower_name, path in case_index.items():
            if lower_name in ini_referenced:
                continue
            if path.suffix.lower() not in IMAGE_EXTS:
                continue
            regions = named_face_regions(read_xmp_regions(path))
            if not regions:
                continue
            opened = open_source(path)
            if opened is None:
                self.stats.images_unreadable += 1
                continue
            img_raw, orient = opened
            crop_src = apply_orientation(img_raw, orient)   # display-relative
            ckey = content_key(path)
            for idx, reg in enumerate(regions):
                dkey = (ckey, f"xmp{idx}")
                if ckey and dkey in self.seen_faces:
                    self.stats.skipped_dup += 1
                    continue
                self.seen_faces.add(dkey)
                if self._emit(
                    name=reg.name, chash="", src_image=path, folder=folder,
                    crop_src=crop_src, crop_orient=1, box_norm=reg.box_norm,
                    idx=idx, source="xmp",
                ):
                    self.stats.faces_written += 1
                    self.stats.xmp_faces_written += 1

    def _print_summary(self):
        s = self.stats
        print("\n== face DB summary ==")
        print(f"  coord-space            : {self.coord_space}")
        print(f"  folders with face INIs : {s.folders_with_ini}")
        print(f"  images referenced      : {s.images_referenced}")
        print(f"  images missing on disk : {s.images_missing}")
        print(f"  images unreadable      : {s.images_unreadable}")
        print(f"  RAW skipped            : {s.skipped_raw}")
        print(f"  faces written          : {s.faces_written}  (xmp: {s.xmp_faces_written})")
        print(f"  distinct people        : {len(s.by_person)}")
        print(f"  skipped unnamed (ffff) : {s.skipped_unnamed}")
        print(f"  skipped unresolved hash: {s.skipped_unresolved}")
        print(f"  skipped duplicate face : {s.skipped_dup}")
        print(f"  skipped tiny/invalid   : {s.skipped_tiny}")
        print(f"  skipped write error    : {s.skipped_error}")
        if s.by_person:
            print("  top people:")
            for name, n in s.by_person.most_common(15):
                print(f"    {n:5d}  {name}")
        print(f"\n  -> {self.out / 'crops'}  +  {self.out / 'manifest.csv'}")


def parse_args(argv):
    ap = argparse.ArgumentParser(description="Build a labeled face DB from a Picasa tree")
    ap.add_argument("--root", default="/Volumes/X9 Pro/Pictures Partailly Sorted 2025",
                    help="root of the Picasa-organized photo tree")
    ap.add_argument("--out", default="./faces_db", help="output dir (crops/ + manifest.csv)")
    ap.add_argument("--pad", type=float, default=0.2,
                    help="pad each face box by this fraction (Picasa boxes are tight)")
    ap.add_argument("--coord-space", choices=("raw", "display"), default="raw",
                    help="rect64 coordinate basis. 'raw' (default, verified on this "
                         "library) decodes against un-oriented dims + rotates the crop; "
                         "'display' assumes EXIF-oriented coords (the spec's assumption)")
    ap.add_argument("--min-size", type=int, default=0,
                    help="skip crops smaller than this many px on a side (0 = keep all)")
    ap.add_argument("--keep-unknown", action="store_true",
                    help="keep unresolved-hash faces as Unknown_<hash> instead of skipping")
    ap.add_argument("--include-raw", action="store_true",
                    help="attempt RAW files via Pillow (WARNING: only the embedded "
                         "thumbnail, often tiny). Off by default.")
    ap.add_argument("--xmp-fallback", action="store_true",
                    help="for images with no INI entry, read embedded XMP regions (exiftool)")
    ap.add_argument("--contacts-xml", default=None,
                    help="explicit path to Picasa db3/contacts.xml (hash fallback)")
    ap.add_argument("--find-contacts-xml", action="store_true",
                    help="search the tree for a contacts.xml to resolve unknown hashes")
    ap.add_argument("--limit", type=int, default=0, help="stop after N faces (testing)")
    ap.add_argument("--allow-in-repo", action="store_true",
                    help="permit writing the (PII) face DB inside a git work tree")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    return FaceDBBuilder(args).run()


if __name__ == "__main__":
    raise SystemExit(main())
