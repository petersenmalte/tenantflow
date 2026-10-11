"""Plots from bench/results/results.json (no hand-made numbers).

Usage:  cd python && uv run --group bench python ../bench/plot.py
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = Path(__file__).resolve().parent
res = json.loads((HERE / "results" / "results.json").read_text())
VARIANTS = res["meta"]["variants"]
# categorical slots 1-4 of the reference palette, fixed order (validated; contrast WARN ->
# direct value labels)
LIGHT = dict(zip(VARIANTS, ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"], strict=True))
DARK = dict(zip(VARIANTS, ["#3987e5", "#d95926", "#199e70", "#c98500"], strict=True))
THEMES = {
    "light": dict(bg="#fcfcfb", fg="#0b0b0b", sub="#52514e", grid="#e4e3df", col=LIGHT),
    "dark": dict(bg="#1a1a19", fg="#f0efec", sub="#c3c2b7", grid="#383835", col=DARK),
}
LABEL = {
    "none": "none",
    "cedar-only": "Cedar only",
    "fides": "FIDES (1.5.0 logic)",
    "tenantflow": "TenantFlow",
}


def style(ax, t):
    ax.set_facecolor(t["bg"])
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color(t["grid"])
    ax.tick_params(colors=t["sub"], length=0)
    ax.yaxis.grid(True, color=t["grid"], linewidth=0.8)
    ax.set_axisbelow(True)


def bars(ax, groups, getter, t, ylabel, pct=True, ymax=None):
    n = len(VARIANTS)
    w = 0.8 / n
    for j, v in enumerate(VARIANTS):
        xs = [i + (j - (n - 1) / 2) * w for i in range(len(groups))]
        vals = [getter(g, v) for g in groups]
        ax.bar(xs, vals, width=w - 0.04, color=t["col"][v], label=LABEL[v])
        for x, val in zip(xs, vals, strict=True):
            ax.text(
                x,
                val + (ymax or 1) * 0.015,
                f"{val:.0%}" if pct else f"{val:g}",
                ha="center",
                va="bottom",
                fontsize=8,
                color=t["fg"],
            )
    ax.set_xticks(range(len(groups)), [g[1] for g in groups], color=t["sub"])
    ax.set_ylabel(ylabel, color=t["sub"])
    if ymax:
        ax.set_ylim(0, ymax)
    style(ax, t)


def render(name, t):
    plt.rcParams.update({"font.size": 10, "font.family": "sans-serif"})
    fig, axes = plt.subplots(
        1, 3, figsize=(15, 4.6), facecolor=t["bg"], gridspec_kw={"width_ratios": [1.6, 1, 1]}
    )
    # 1) attack success
    groups = [
        ("leak", f"cross-tenant leaks\n(scripted, n={res['leak']['none']['n']})"),
        ("forgery", f"label forgery\n(scripted, n={res['forgery']['none']['n']})"),
        ("fuzz", f"fuzzer, any violation\n({res['meta']['episodes']} episodes)"),
    ]
    get = lambda g, v: res["fuzz"][v]["any"]["rate"] if g[0] == "fuzz" else res[g[0]][v]["rate"]  # noqa: E731
    bars(axes[0], groups, get, t, "attack success rate", ymax=1.15)
    axes[0].set_title("Attack success (lower is better)", color=t["fg"], loc="left")
    axes[0].yaxis.set_major_formatter(lambda y, _: f"{y:.0%}")
    # 2) utility
    bars(
        axes[1],
        [("utility", f"legitimate workflows\n(n={res['utility']['none']['n']})")],
        lambda g, v: res["utility"][v]["rate"],
        t,
        "workflows completed",
        ymax=1.15,
    )
    axes[1].set_title("Utility (higher is better)", color=t["fg"], loc="left")
    axes[1].yaxis.set_major_formatter(lambda y, _: f"{y:.0%}")
    # 3) latency
    ax = axes[2]
    lat = res["latency"]
    xs = range(len(VARIANTS))
    ax.bar(
        xs, [lat[v]["p50_us"] for v in VARIANTS], color=[t["col"][v] for v in VARIANTS], width=0.6
    )
    ax.scatter(xs, [lat[v]["p95_us"] for v in VARIANTS], color=t["fg"], marker="_", s=400, zorder=3)
    for x, v in zip(xs, VARIANTS, strict=True):
        ax.text(
            x,
            lat[v]["p95_us"] * 1.06,
            f"p50 {lat[v]['p50_us']:.0f}\np95 {lat[v]['p95_us']:.0f}",
            ha="center",
            va="bottom",
            fontsize=8,
            color=t["fg"],
        )
    ax.set_xticks(
        list(xs), [LABEL[v].replace(" (", "\n(") for v in VARIANTS], color=t["sub"], fontsize=8
    )
    ax.set_ylabel("µs per decision", color=t["sub"])
    ax.set_ylim(0, max(lat[v]["p95_us"] for v in VARIANTS) * 1.35)
    ax.set_title("Latency (bar p50, tick p95)", color=t["fg"], loc="left")
    style(ax, t)
    handles, labels = axes[0].get_legend_handles_labels()
    leg = fig.legend(handles, labels, loc="lower center", ncol=4, frameon=False, labelcolor=t["fg"])
    for txt in leg.get_texts():
        txt.set_color(t["fg"])
    fig.tight_layout(rect=(0, 0.07, 1, 1))
    out = HERE / "results" / "plots"
    out.mkdir(parents=True, exist_ok=True)
    fig.savefig(out / f"summary-{name}.png", dpi=130, facecolor=t["bg"])
    plt.close(fig)


for name, theme in THEMES.items():
    render(name, theme)
print("wrote", HERE / "results" / "plots")
