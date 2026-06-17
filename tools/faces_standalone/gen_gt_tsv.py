#!/usr/bin/env python3
"""Flatten the Picasa face manifest into a tab-separated ground-truth file for
faces_probe's full-res mode (image \t person \t x1 \t y1 \t x2 \t y2, grouped by
image). Tabs avoid the CSV-quoting the C++ side would otherwise have to parse.

  python3 gen_gt_tsv.py /tmp/full_db/manifest.csv /tmp/full_db/faces.tsv
"""
import csv
import collections
import sys

src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/full_db/manifest.csv"
dst = sys.argv[2] if len(sys.argv) > 2 else "/tmp/full_db/faces.tsv"

by_img = collections.OrderedDict()
for r in csv.DictReader(open(src)):
    by_img.setdefault(r["source_image"], []).append(r)

n = 0
with open(dst, "w") as out:
    for img in sorted(by_img):
        for r in by_img[img]:
            x1, y1, x2, y2 = (float(v) for v in r["bbox_px"].split(","))
            out.write(f"{img}\t{r['person_name']}\t{x1:.1f}\t{y1:.1f}\t{x2:.1f}\t{y2:.1f}\n")
            n += 1
print(f"wrote {dst}: {n} faces across {len(by_img)} images")
