#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# One-time export of an SSCD copy-detection model to ONNX, so the C++ pipeline
# can run it through ONNX Runtime (no Python in the hot path).
#
# SSCD: https://github.com/facebookresearch/sscd-copy-detection  (MIT)
# Download a TorchScript checkpoint, e.g.:
#   sscd_disc_mixup.torchscript.pt   (ResNet-50 backbone, 512-d embedding)
# from the SSCD model zoo, then:
#
#   python export_sscd_to_onnx.py \
#       --checkpoint sscd_disc_mixup.torchscript.pt \
#       --output ../models/sscd_disc_mixup.onnx
#
# The exported graph has a dynamic batch axis and a fixed spatial size (default
# 288x288), matching the C++ decode stage (resize short side -> center crop).
#
# Requirements:  pip install torch onnx
# Optional check: pip install onnxruntime numpy

import argparse
import sys


def main() -> int:
    ap = argparse.ArgumentParser(description="Export SSCD to ONNX")
    ap.add_argument("--checkpoint", required=True,
                    help="SSCD TorchScript .pt (or a torch.jit-scriptable module)")
    ap.add_argument("--output", required=True, help="destination .onnx path")
    ap.add_argument("--input-size", type=int, default=288,
                    help="square input HxW (must match config.embed.input_size)")
    ap.add_argument("--opset", type=int, default=17)
    ap.add_argument("--no-check", action="store_true",
                    help="skip the onnxruntime parity check")
    args = ap.parse_args()

    try:
        import torch
    except ImportError:
        print("error: PyTorch is required (pip install torch onnx)", file=sys.stderr)
        return 1

    print(f"loading TorchScript checkpoint: {args.checkpoint}")
    model = torch.jit.load(args.checkpoint, map_location="cpu")
    model.eval()

    S = args.input_size
    dummy = torch.randn(1, 3, S, S, dtype=torch.float32)

    print(f"exporting -> {args.output}  (input 1x3x{S}x{S}, dynamic batch, opset {args.opset})")
    torch.onnx.export(
        model, dummy, args.output,
        input_names=["input"],
        output_names=["embedding"],
        dynamic_axes={"input": {0: "batch"}, "embedding": {0: "batch"}},
        opset_version=args.opset,
        do_constant_folding=True,
    )

    # Structural validation.
    try:
        import onnx
        onnx.checker.check_model(args.output)
        m = onnx.load(args.output)
        out = m.graph.output[0]
        dims = [d.dim_value or "?" for d in out.type.tensor_type.shape.dim]
        print(f"onnx ok — output '{out.name}' shape {dims}")
    except ImportError:
        print("note: install onnx to validate the exported graph")

    # Numerical parity vs. the Torch model (recommended).
    if not args.no_check:
        try:
            import numpy as np
            import onnxruntime as ort
            with torch.no_grad():
                ref = model(dummy).cpu().numpy()
            sess = ort.InferenceSession(args.output, providers=["CPUExecutionProvider"])
            got = sess.run(["embedding"], {"input": dummy.numpy()})[0]
            max_abs = float(np.max(np.abs(ref - got)))
            print(f"parity check: max abs diff = {max_abs:.3e}"
                  + ("  OK" if max_abs < 1e-3 else "  WARN (>1e-3)"))
        except ImportError:
            print("note: install onnxruntime + numpy to run the parity check")

    print("done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
