# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
"""Phase-4 reporting: master table, plots, and the ship/escalate decision.

This is the human-facing end of the harness. It consumes the per-model metrics
dict produced by ``run.phase_metrics`` and turns it into:

  * ``report.md``      — YuNet landmark recall, a master comparison table (one
                         row per model), the gap of each *candidate* to the
                         ``buffalo_l`` ceiling, and the explicit ship/escalate
                         decision derived from ``cfg['decision']`` tolerances.
  * ``roc_curves.png`` — every model's ROC overlaid (held-out split).
  * ``hist_<model>.png`` — genuine-vs-impostor score histograms per model.

The exact metric contracts we read (see ``metrics/verification.py``,
``metrics/identification.py``, ``metrics/clustering.py``,
``metrics/operating_point.py``):

  metrics_out[name] = {
    "metric": str, "role": str, "n": int, "dim": int,
    "verification": {
        "auc": float, "eer": float,
        "tar_at_far": {"<%g far>": float, ...},   # e.g. {"0.001": .., "0.0001": ..}
        "roc": {"fpr": [..], "tpr": [..]},
        "gen_scores": [..], "imp_scores": [..],
    },
    "identification": {"rank1": float, "mAP": float},
    "clustering": {
        "<method>": {"ari": .., "nmi": .., "pairwise_f1": .., "n_clusters": ..},
        "n_true_clusters": int,
    },
    "operating_point": {"threshold": .., "auto_accept_error": .., "prompt_rate": ..},
  }

The whole module is defensive: any field may be missing or NaN (a model that was
skipped, a degenerate split, a metric that came back undefined). We never raise
on bad data — we render it as ``n/a`` and keep going, because the point of the
report is to compare whatever models *did* run.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

# Headless rendering: the harness runs in CI / over SSH with no display, so we
# must select the Agg backend BEFORE importing pyplot.
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

# The ceiling we measure every shippable candidate against.
CEILING = "buffalo_l"

# The FAR operating points we tabulate. Keys into ``verification.tar_at_far`` are
# the '%g'-formatted target FAR (see metrics/verification.py), so 1e-3 -> "0.001".
FAR_MAIN = 1.0e-3   # the FAR the decision rule is anchored on (TAR@1e-3)
FAR_FINE = 1.0e-4


# ============================================================ small helpers

def _far_key(far: float) -> str:
    """Key into the verification tar/thr/far dicts: '%g' of the target FAR."""
    return "%g" % float(far)


def _isnum(x: Any) -> bool:
    """True iff x is a real, finite number (not None, not NaN, not inf)."""
    try:
        return x is not None and math.isfinite(float(x))
    except (TypeError, ValueError):
        return False


def _get(d: Any, *keys: str, default: Any = None) -> Any:
    """Nested dict lookup that tolerates missing levels / non-dict values."""
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def _fmt(x: Any, prec: int = 4) -> str:
    """Format a metric for the table; non-numbers / NaNs render as 'n/a'."""
    return f"{float(x):.{prec}f}" if _isnum(x) else "n/a"


def _fmt_pct(x: Any, prec: int = 2) -> str:
    """Render a [0,1] rate as a percentage string, or 'n/a'."""
    return f"{float(x) * 100:.{prec}f}%" if _isnum(x) else "n/a"


def _fmt_signed(x: Any, prec: int = 4) -> str:
    """Signed gap formatting (e.g. '+0.0123'), or 'n/a'."""
    return f"{float(x):+.{prec}f}" if _isnum(x) else "n/a"


def _tar(model: Dict[str, Any], far: float) -> float:
    """TAR @ the given FAR for a model, or NaN if missing."""
    v = _get(model, "verification", "tar_at_far", _far_key(far))
    return float(v) if _isnum(v) else float("nan")


# ----------------------------------------------------- clustering selection

def _cluster_methods(model: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    """The per-method clustering sub-dicts (everything except n_true_clusters)."""
    clus = model.get("clustering") or {}
    return {k: v for k, v in clus.items()
            if k != "n_true_clusters" and isinstance(v, dict)}


def _best_cluster(model: Dict[str, Any]
                  ) -> Tuple[Optional[str], Dict[str, Any]]:
    """Pick the clustering method to report for this model.

    Preference order, per the spec ("pick the best method or show dbscan"):
      1. the method with the highest finite pairwise_f1, else
      2. ``dbscan`` if present, else
      3. any available method.
    Returns (method_name, method_dict). ('', {}) when no clustering ran.
    """
    methods = _cluster_methods(model)
    if not methods:
        return "", {}
    scored = [(name, m) for name, m in methods.items()
              if _isnum(m.get("pairwise_f1"))]
    if scored:
        name, m = max(scored, key=lambda kv: float(kv[1]["pairwise_f1"]))
        return name, m
    if "dbscan" in methods:
        return "dbscan", methods["dbscan"]
    name = next(iter(methods))
    return name, methods[name]


def _cluster_f1(model: Dict[str, Any]) -> float:
    """Reported (best) cluster pairwise-F1 for a model, or NaN."""
    _, m = _best_cluster(model)
    v = m.get("pairwise_f1")
    return float(v) if _isnum(v) else float("nan")


# ============================================================ plotting

def _plot_roc(metrics_out: Dict[str, Any], out_dir: Path) -> Optional[Path]:
    """Overlay every model's ROC curve (log-x FPR) into roc_curves.png."""
    fig, ax = plt.subplots(figsize=(7.0, 5.5))
    drew = False
    for name, model in metrics_out.items():
        roc = _get(model, "verification", "roc")
        if not isinstance(roc, dict):
            continue
        fpr = np.asarray(roc.get("fpr", []), dtype=float).ravel()
        tpr = np.asarray(roc.get("tpr", []), dtype=float).ravel()
        if fpr.size < 2 or tpr.size < 2 or fpr.size != tpr.size:
            continue
        auc = _get(model, "verification", "auc")
        role = model.get("role") or "?"
        label = f"{name} ({role}, AUC={_fmt(auc, 3)})"
        # Mark the ceiling distinctly so it reads as the reference line.
        style = dict(lw=2.4, ls="--") if name == CEILING else dict(lw=1.8)
        ax.plot(fpr, tpr, label=label, **style)
        drew = True
    if not drew:
        plt.close(fig)
        return None

    ax.set_xscale("log")
    ax.set_xlim(1e-5, 1.0)
    ax.set_ylim(0.0, 1.005)
    ax.set_xlabel("False Accept Rate (log)")
    ax.set_ylabel("True Accept Rate")
    ax.set_title("ROC — held-out split (higher/left is better)")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(loc="lower right", fontsize=8, framealpha=0.9)
    fig.tight_layout()
    path = out_dir / "roc_curves.png"
    fig.savefig(path, dpi=130)
    plt.close(fig)
    return path


def _plot_hist(name: str, model: Dict[str, Any], out_dir: Path) -> Optional[Path]:
    """Genuine vs impostor score histogram for one model -> hist_<name>.png."""
    gen = np.asarray(_get(model, "verification", "gen_scores", default=[]),
                     dtype=float).ravel()
    imp = np.asarray(_get(model, "verification", "imp_scores", default=[]),
                     dtype=float).ravel()
    gen = gen[np.isfinite(gen)]
    imp = imp[np.isfinite(imp)]
    if gen.size == 0 and imp.size == 0:
        return None

    fig, ax = plt.subplots(figsize=(6.5, 4.0))
    # Shared, robust binning across both distributions.
    both = np.concatenate([gen, imp]) if (gen.size and imp.size) else (
        gen if gen.size else imp)
    lo, hi = float(np.min(both)), float(np.max(both))
    if not (math.isfinite(lo) and math.isfinite(hi)) or hi <= lo:
        lo, hi = lo - 1.0, lo + 1.0
    bins = np.linspace(lo, hi, 60)

    if imp.size:
        ax.hist(imp, bins=bins, density=True, alpha=0.55,
                label=f"impostor (n={imp.size})", color="#c0392b")
    if gen.size:
        ax.hist(gen, bins=bins, density=True, alpha=0.55,
                label=f"genuine (n={gen.size})", color="#2980b9")

    # Mark the model's operating threshold if we have it.
    thr = _get(model, "operating_point", "threshold")
    if _isnum(thr):
        ax.axvline(float(thr), color="k", ls="--", lw=1.2,
                   label=f"threshold={float(thr):.3f}")

    metric = model.get("metric", "?")
    ax.set_xlabel(f"pair score ({metric}; higher = more similar)")
    ax.set_ylabel("density")
    ax.set_title(f"{name}: genuine vs impostor scores")
    ax.legend(fontsize=8, framealpha=0.9)
    fig.tight_layout()
    path = out_dir / f"hist_{name}.png"
    fig.savefig(path, dpi=130)
    plt.close(fig)
    return path


# ============================================================ decision rule

def _decide(cfg: Dict[str, Any], metrics_out: Dict[str, Any]
            ) -> Tuple[List[str], Optional[str]]:
    """Apply the ship/escalate rule and return (markdown_lines, shipped_name).

    Rule: among the *candidate*-role models, in the most-permissive order
    (``sface`` before ``dlib``), ship the FIRST one that clears ALL tolerances
    versus ``buffalo_l``:
      * TAR@1e-3 within ``tar_gap_points`` (in percentage points) of buffalo_l,
      * cluster F1 within ``cluster_f1_gap`` of buffalo_l,
      * auto-accept error <= ``max_auto_accept_error``,
      * prompt rate <= ``max_prompt_rate``.
    If no candidate clears, escalate. The full pass/fail of every candidate is
    surfaced so the decision is auditable.
    """
    dec = cfg.get("decision", {}) or {}
    tar_gap_points = float(dec.get("tar_gap_points", 1.5))
    cluster_f1_gap = float(dec.get("cluster_f1_gap", 0.03))
    max_auto_err = float(dec.get("max_auto_accept_error", 0.01))
    max_prompt = float(dec.get("max_prompt_rate", 0.15))
    # tar_gap_points is in percentage POINTS; TAR values are fractions in [0,1].
    tar_gap_frac = tar_gap_points / 100.0

    lines: List[str] = []
    lines.append("## Decision\n")
    lines.append(
        "**Rule:** ship the most permissive *candidate* (`sface` > `dlib`) that "
        f"clears every tolerance versus `{CEILING}`; otherwise **escalate**.\n")

    # Surface the tolerances so they are easy to find and tune.
    lines.append("**Tolerances** (from `config.yaml` → `decision`):\n")
    lines.append("")
    lines.append("| tolerance | value |")
    lines.append("| --- | --- |")
    lines.append(f"| `tar_gap_points` (TAR@1e-3, pct points) | {tar_gap_points:g} |")
    lines.append(f"| `cluster_f1_gap` | {cluster_f1_gap:g} |")
    lines.append(f"| `max_auto_accept_error` | {max_auto_err:g} |")
    lines.append(f"| `max_prompt_rate` | {max_prompt:g} |")
    lines.append("")

    ceiling = metrics_out.get(CEILING)
    if not isinstance(ceiling, dict):
        lines.append(
            f"> **ESCALATE** — ceiling `{CEILING}` did not run, so no candidate "
            "can be measured against it. Re-run with the ceiling model present.\n")
        return lines, None

    ceil_tar = _tar(ceiling, FAR_MAIN)
    ceil_f1 = _cluster_f1(ceiling)
    lines.append(
        f"`{CEILING}` reference — TAR@1e-3 = {_fmt(ceil_tar)}, "
        f"cluster F1 = {_fmt(ceil_f1)}.\n")

    if not (_isnum(ceil_tar) and _isnum(ceil_f1)):
        lines.append(
            f"> **ESCALATE** — `{CEILING}` reference metrics are undefined "
            "(NaN), so the gap tolerances cannot be evaluated.\n")
        return lines, None

    # Most-permissive-first candidate ordering.
    order = ["sface", "dlib"]
    present = [m["name"] for m in cfg.get("models", [])
               if m.get("role") == "candidate"]
    # Honour config order for any candidate not in the explicit preference list.
    candidates = [n for n in order if n in present] + \
                 [n for n in present if n not in order]

    lines.append("### Candidate evaluation\n")
    lines.append("")
    lines.append("| candidate | TAR@1e-3 gap | F1 gap | auto-accept err | "
                 "prompt rate | verdict |")
    lines.append("| --- | --- | --- | --- | --- | --- |")

    shipped: Optional[str] = None
    verdicts: List[Tuple[str, bool, List[str]]] = []

    for name in candidates:
        model = metrics_out.get(name)
        if not isinstance(model, dict):
            lines.append(f"| `{name}` | — | — | — | — | did not run |")
            verdicts.append((name, False, ["did not run"]))
            continue

        c_tar = _tar(model, FAR_MAIN)
        c_f1 = _cluster_f1(model)
        auto_err = _get(model, "operating_point", "auto_accept_error")
        prompt = _get(model, "operating_point", "prompt_rate")

        # Gaps: ceiling minus candidate (positive == candidate is worse).
        tar_gap = (ceil_tar - c_tar) if _isnum(c_tar) else float("nan")
        f1_gap = (ceil_f1 - c_f1) if _isnum(c_f1) else float("nan")

        reasons: List[str] = []
        # Each check is a hard gate; a NaN metric is treated as a failure
        # (we cannot prove the candidate is safe).
        if not _isnum(c_tar):
            ok_tar = False
            reasons.append("TAR@1e-3 undefined")
        else:
            ok_tar = tar_gap <= tar_gap_frac
            if not ok_tar:
                reasons.append(
                    f"TAR gap {_fmt_signed(tar_gap)} > {tar_gap_frac:.4f}")
        if not _isnum(c_f1):
            ok_f1 = False
            reasons.append("cluster F1 undefined")
        else:
            ok_f1 = f1_gap <= cluster_f1_gap
            if not ok_f1:
                reasons.append(f"F1 gap {_fmt_signed(f1_gap)} > {cluster_f1_gap:g}")
        if not _isnum(auto_err):
            ok_auto = False
            reasons.append("auto-accept error undefined")
        else:
            ok_auto = float(auto_err) <= max_auto_err
            if not ok_auto:
                reasons.append(
                    f"auto-accept err {_fmt_pct(auto_err)} > {max_auto_err:g}")
        if not _isnum(prompt):
            ok_prompt = False
            reasons.append("prompt rate undefined")
        else:
            ok_prompt = float(prompt) <= max_prompt
            if not ok_prompt:
                reasons.append(
                    f"prompt rate {_fmt_pct(prompt)} > {max_prompt:g}")

        passed = ok_tar and ok_f1 and ok_auto and ok_prompt
        verdict = "PASS" if passed else "FAIL"
        # The first passing candidate in permissive order is the one we ship.
        if passed and shipped is None:
            shipped = name
            verdict = "**PASS → SHIP**"

        lines.append(
            f"| `{name}` | {_fmt_signed(tar_gap)} | {_fmt_signed(f1_gap)} | "
            f"{_fmt_pct(auto_err)} | {_fmt_pct(prompt)} | {verdict} |")
        verdicts.append((name, passed, reasons))

    lines.append("")
    # Per-candidate pass/fail prose so the failure reasons are explicit.
    for name, passed, reasons in verdicts:
        if passed:
            lines.append(f"- `{name}`: **PASS** — clears every tolerance.")
        else:
            why = "; ".join(reasons) if reasons else "one or more tolerances"
            lines.append(f"- `{name}`: **FAIL** — {why}.")
    lines.append("")

    if shipped is not None:
        lines.append(
            f"> ## DECISION: SHIP `{shipped}`\n>\n"
            f"> `{shipped}` is the most permissive candidate that clears all "
            f"tolerances versus `{CEILING}`.\n")
    else:
        lines.append(
            "> ## DECISION: ESCALATE\n>\n"
            "> No candidate cleared every tolerance versus "
            f"`{CEILING}`. Tune the model recipe, relax the tolerances in "
            "`config.yaml`, or take the decision to a human.\n")

    return lines, shipped


# ============================================================ master table

def _master_table(metrics_out: Dict[str, Any]) -> List[str]:
    """Build the one-row-per-model comparison table (markdown)."""
    ceiling = metrics_out.get(CEILING)
    ceil_tar = _tar(ceiling, FAR_MAIN) if isinstance(ceiling, dict) else float("nan")
    ceil_f1 = _cluster_f1(ceiling) if isinstance(ceiling, dict) else float("nan")

    header = ("| model | role | AUC | EER | TAR@1e-3 | TAR@1e-4 | Rank-1 | mAP "
              "| cluster (method) | ARI | NMI | F1 | auto-accept err | "
              "prompt rate | Δ TAR@1e-3 | Δ F1 |")
    sep = ("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- "
           "| --- | --- | --- | --- | --- |")
    rows: List[str] = [header, sep]

    # Order: ceiling(s) first as the reference, then candidates — but keep
    # insertion order within each group for stability. Skip junk (non-dict)
    # model values entirely so a malformed entry can't poison the ordering.
    names = [n for n in metrics_out if isinstance(metrics_out[n], dict)]
    names.sort(key=lambda n: (metrics_out[n].get("role") != "ceiling",))

    for name in names:
        model = metrics_out[name]
        if not isinstance(model, dict):
            continue
        role = model.get("role") or "?"
        auc = _get(model, "verification", "auc")
        eer = _get(model, "verification", "eer")
        tar3 = _tar(model, FAR_MAIN)
        tar4 = _tar(model, FAR_FINE)
        rank1 = _get(model, "identification", "rank1")
        mAP = _get(model, "identification", "mAP")
        method, cm = _best_cluster(model)
        ari = cm.get("ari")
        nmi = cm.get("nmi")
        f1 = cm.get("pairwise_f1")
        auto_err = _get(model, "operating_point", "auto_accept_error")
        prompt = _get(model, "operating_point", "prompt_rate")

        # Gaps to the ceiling (ceiling minus candidate). Blank for the ceiling
        # itself and when either side is undefined.
        if name == CEILING:
            d_tar = d_f1 = "—"
        else:
            dt = (ceil_tar - tar3) if (_isnum(ceil_tar) and _isnum(tar3)) else None
            df = (ceil_f1 - f1) if (_isnum(ceil_f1) and _isnum(f1)) else None
            d_tar = _fmt_signed(dt) if dt is not None else "n/a"
            d_f1 = _fmt_signed(df) if df is not None else "n/a"

        method_lbl = method if method else "n/a"
        rows.append(
            f"| `{name}` | {role} | {_fmt(auc)} | {_fmt(eer)} | {_fmt(tar3)} | "
            f"{_fmt(tar4)} | {_fmt(rank1)} | {_fmt(mAP)} | {method_lbl} | "
            f"{_fmt(ari)} | {_fmt(nmi)} | {_fmt(f1)} | {_fmt_pct(auto_err)} | "
            f"{_fmt_pct(prompt)} | {d_tar} | {d_f1} |")
    return rows


# ============================================================ entry point

def write_report(cfg: Dict[str, Any], metrics_out: Dict[str, Any],
                 detect_stats: Dict[str, Any], out_dir) -> Path:
    """Render report.md + plots into ``out_dir``; return the report.md path.

    Parameters
    ----------
    cfg          : the loaded ``config.yaml`` dict (we read ``decision`` and the
                   model roster).
    metrics_out  : ``{model_name: {...}}`` from ``run.phase_metrics`` (see the
                   module docstring for the per-model schema). May be empty or
                   contain partially-NaN models.
    detect_stats : ``{recall, kept, missed, missed_ids}`` from ``phase_detect``.
    out_dir      : directory to write report.md / roc_curves.png / hist_*.png.

    Robust to missing models, missing metric keys, and NaNs throughout.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    metrics_out = metrics_out or {}
    detect_stats = detect_stats or {}

    # ---- plots (best-effort; a plotting failure must not sink the report) -----
    roc_path: Optional[Path] = None
    hist_paths: Dict[str, Path] = {}
    try:
        roc_path = _plot_roc(metrics_out, out_dir)
    except Exception as ex:  # noqa: BLE001 — never let a plot crash the report
        roc_path = None
        print(f"[report] ROC plot failed: {ex}", flush=True)
    for name, model in metrics_out.items():
        if not isinstance(model, dict):
            continue
        try:
            p = _plot_hist(name, model, out_dir)
        except Exception as ex:  # noqa: BLE001
            p = None
            print(f"[report] hist plot failed for {name}: {ex}", flush=True)
        if p is not None:
            hist_paths[name] = p

    # ---- assemble markdown ----------------------------------------------------
    md: List[str] = []
    md.append("# Face-model evaluation report\n")
    md.append("Comparison of candidate face embedders against the "
              f"`{CEILING}` ceiling, on the labeled Picasa face DB.\n")

    # Detection / YuNet landmark recall.
    md.append("## YuNet landmark recall\n")
    recall = detect_stats.get("recall")
    kept = detect_stats.get("kept")
    missed = detect_stats.get("missed")
    total = (int(kept) + int(missed)) if (_isnum(kept) and _isnum(missed)) else None
    md.append("YuNet must find 5 landmarks on a crop for that face to enter the "
              "evaluation; crops it misses are quarantined.\n")
    md.append("")
    md.append("| metric | value |")
    md.append("| --- | --- |")
    md.append(f"| landmark recall | {_fmt_pct(recall)} |")
    md.append(f"| faces kept | {int(kept) if _isnum(kept) else 'n/a'} |")
    md.append(f"| faces quarantined | {int(missed) if _isnum(missed) else 'n/a'} |")
    if total is not None:
        md.append(f"| total crops | {total} |")
    md.append("")

    # Master comparison table.
    md.append("## Master comparison\n")
    if metrics_out:
        md.append("One row per model. Δ columns are **ceiling minus candidate** "
                  "(positive = candidate is worse than the ceiling). Cluster "
                  "ARI/NMI/F1 are for the best-F1 method (falling back to "
                  "`dbscan`).\n")
        md.append("")
        md.extend(_master_table(metrics_out))
        md.append("")
    else:
        md.append("_No models produced metrics — nothing to compare. Check that "
                  "phase 2 embedded at least one model._\n")

    # Plots.
    md.append("## Plots\n")
    if roc_path is not None:
        md.append(f"![ROC curves]({roc_path.name})\n")
    else:
        md.append("_ROC plot unavailable (no usable ROC arrays)._\n")
    for name in metrics_out:
        if name in hist_paths:
            md.append(f"![{name} score histogram]({hist_paths[name].name})\n")
    md.append("")

    # Decision.
    decision_lines, shipped = _decide(cfg, metrics_out)
    md.extend(decision_lines)

    # ---- write ----------------------------------------------------------------
    report_md = out_dir / "report.md"
    report_md.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(f"[report] wrote {report_md} (decision: "
          f"{'SHIP ' + shipped if shipped else 'ESCALATE'})", flush=True)
    return report_md
