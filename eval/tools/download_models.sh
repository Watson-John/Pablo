#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Fetch the face-eval model files into eval/models/.
#
#   bash eval/tools/download_models.sh
#
# Notes on licensing (see the build plan): SFace + YuNet are Apache-2.0 and dlib
# is Boost — these are the *shippable* candidates. buffalo_l (InsightFace) and
# AdaFace are non-commercial and used here as accuracy CEILINGS only — never
# bundled into the app.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/models"
mkdir -p "$DIR"
cd "$DIR"

fetch() {  # fetch <url> <outfile>
  if [ -f "$2" ]; then echo "  have $2"; return; fi
  echo "  -> $2"
  curl -fL --retry 3 -o "$2" "$1"
}

echo "[1/4] YuNet detector (Apache-2.0, opencv_zoo)"
fetch "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx" \
      "face_detection_yunet_2023mar.onnx"

echo "[2/4] SFace recognizer (Apache-2.0, opencv_zoo)"
fetch "https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx" \
      "face_recognition_sface_2021dec.onnx"

echo "[3/4] buffalo_l / ArcFace R50 (InsightFace, NON-COMMERCIAL — ceiling only)"
fetch "https://huggingface.co/immich-app/buffalo_l/resolve/main/w600k_r50.onnx" \
      "w600k_r50.onnx"

echo "[4/4] dlib models (Boost) — recognizer + 5-pt predictor"
for f in dlib_face_recognition_resnet_model_v1.dat shape_predictor_5_face_landmarks.dat; do
  if [ -f "$f" ]; then echo "  have $f"; continue; fi
  echo "  -> $f"
  curl -fL --retry 3 -o "$f.bz2" "http://dlib.net/files/$f.bz2"
  bunzip2 -q "$f.bz2" 2>/dev/null || bzip2 -d "$f.bz2"
done

cat <<'NOTE'

AdaFace IR-101 (NON-COMMERCIAL — ceiling only) is NOT auto-downloaded: it ships
as a PyTorch checkpoint and must be exported to ONNX once. See
https://github.com/mk-minchul/AdaFace — load the IR-101 checkpoint and
torch.onnx.export a (1,3,112,112) input to ./models/adaface_ir101.onnx.
The harness skips any model whose file is absent, so you can run without it.
NOTE
echo "done -> $DIR"
