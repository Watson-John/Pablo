#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# make_exif_fixture.py — regenerate the EXIF test fixtures used by
# native/core/tests/exif_extract_test.cpp.
#
# Provenance: the ground-truth values are *baked by exiftool* (the reference
# implementation) and read back into exif_full.golden.json. The C++ test then
# asserts that our libexif extractor (native/core/src/exif/exif.cpp) recovers
# those same values — i.e. the test is a cross-check of Pablo's reader against
# exiftool, as required by the §5 "EXIF/IPTC read … integ (vs exiftool)" cell.
#
# Requirements: Pillow (`pip install pillow`) and exiftool on PATH.
# Run from anywhere:  python3 native/core/tests/fixtures/make_exif_fixture.py
#
# The generated .jpg and .golden.json are committed so the test is hermetic and
# does NOT need exiftool/Pillow at test time. Re-run this only to change the
# fixture; keep the constants below in sync with exif_extract_test.cpp.

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
JPG = os.path.join(HERE, "exif_full.jpg")
GOLDEN = os.path.join(HERE, "exif_full.golden.json")

# The single source of truth for every baked tag. Keep in sync with the
# kExpected* constants in exif_extract_test.cpp.
TAGS = {
    "Make": "TestMake",
    "Model": "PabloCam 100",
    "EXIF:LensModel": "TestLens 50mm F1.8",
    "FNumber": "2.8",
    "ExposureTime": "1/250",
    "FocalLength": "50.0",
    "ISO": "400",
    "DateTimeOriginal": "2021:07:15 12:30:45",
    "Orientation#": "6",            # '#' -> write the raw numeric value (6 = Rotate 90 CW)
    "ExifImageWidth": "4000",       # PixelXDimension
    "ExifImageHeight": "3000",      # PixelYDimension
    "GPSLatitude": "37.7749",
    "GPSLatitudeRef": "N",
    "GPSLongitude": "122.4194",
    "GPSLongitudeRef": "W",
}


def need(cmd):
    from shutil import which
    if which(cmd) is None:
        sys.exit(f"error: '{cmd}' not found on PATH; cannot regenerate fixtures")


def main():
    need("exiftool")
    try:
        from PIL import Image
    except ImportError:
        sys.exit("error: Pillow not installed (pip install pillow)")

    # A tiny, valid baseline JPEG. Content is irrelevant — only the EXIF matters.
    Image.new("RGB", (16, 16), (200, 60, 40)).save(JPG, "JPEG", quality=85)

    args = ["exiftool", "-overwrite_original", "-q"]
    for k, v in TAGS.items():
        args.append(f"-{k}={v}")
    args.append(JPG)
    subprocess.run(args, check=True)

    # Read the baked EXIF back through exiftool — this JSON is the committed
    # ground-truth the C++ test is cross-checked against. -n gives raw numeric
    # GPS/orientation. We keep only the EXIF: group so the golden is stable and
    # machine-independent (File:* paths/timestamps and Composite:* derivations
    # are dropped).
    out = subprocess.run(
        ["exiftool", "-json", "-G", "-n", JPG],
        check=True, capture_output=True, text=True,
    ).stdout
    data = json.loads(out)[0]
    baked = {k: v for k, v in data.items() if k.startswith("EXIF:")}
    with open(GOLDEN, "w") as f:
        json.dump(baked, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"wrote {JPG}")
    print(f"wrote {GOLDEN}")


if __name__ == "__main__":
    main()
