#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "launch-assets"
OUT.mkdir(parents=True, exist_ok=True)

ACCENT = "#FF5A52"
INK = "#111827"
MUTED = "#586273"
MAGICK = shutil.which("magick") or shutil.which("convert")
if not MAGICK:
    raise SystemExit("ImageMagick is required")


def find_font(pattern: str) -> str:
    return subprocess.check_output(
        ["fc-match", "-f", "%{file}", pattern], text=True
    ).strip()


HEAD = find_font("Noto Sans CJK JP:style=Bold")
BODY = find_font("Noto Sans CJK JP:style=Medium")

SPECS = [
    {
        "name": "01-apexterm-launch-hero",
        "source": "docs/images/overview.png",
        "kicker": "APEXTERM / LAUNCH",
        "headline": ["ターミナルを、", "開発の", "ワークスペースへ。"],
        "sub": "タブ、分割、検索、履歴をひとつに。",
        "chips": ["分割ペイン", "⌘K 横断検索", "Timeline"],
        "image": (715, 170, 805, 525),
        "headline_y": 240,
        "sub_y": 500,
        "chips_y": 575,
        "headline_size": 58,
        "line_gap": 76,
    },
    {
        "name": "02-apexterm-universal-search",
        "source": "docs/images/universal-search.png",
        "kicker": "UNIVERSAL SEARCH",
        "headline": ["⌘Kで、", "全部見つかる。"],
        "sub": "Workspace / Session / Command / Agent を横断。",
        "chips": ["検索", "履歴", "Agent"],
        "image": (820, 105, 635, 589),
        "headline_y": 265,
        "sub_y": 500,
        "chips_y": 580,
        "headline_size": 78,
        "line_gap": 98,
    },
    {
        "name": "03-apexterm-command-timeline",
        "source": "docs/images/command-timeline.png",
        "kicker": "COMMAND TIMELINE",
        "headline": ["実行したことを、", "あとから追える。"],
        "sub": "成功・失敗・出力を、時系列の記録に。",
        "chips": ["履歴", "実行結果", "Filter"],
        "image": (720, 180, 820, 578),
        "headline_y": 255,
        "sub_y": 475,
        "chips_y": 555,
        "headline_size": 58,
        "line_gap": 98,
    },
    {
        "name": "04-apexterm-appearance",
        "source": "docs/images/settings.png",
        "kicker": "APPEARANCE & SETTINGS",
        "headline": ["見た目も操作も、", "自分仕様。"],
        "sub": "外観、アクセント、ターミナル設定まで。",
        "chips": ["System", "Light", "Dark"],
        "image": (800, 105, 650, 650),
        "headline_y": 265,
        "sub_y": 485,
        "chips_y": 565,
        "headline_size": 62,
        "line_gap": 98,
    },
    {
        "name": "05-apexterm-compact-tabs",
        "source": "docs/images/compact-tabs.png",
        "kicker": "COMPACT TABS",
        "headline": ["狭くても、", "迷わない。"],
        "sub": "幅に合わせて、タブを丸型アイコンへ。",
        "chips": ["丸型タブ", "狭幅対応", "Compact"],
        "image": (900, 110, 540, 551),
        "headline_y": 275,
        "sub_y": 500,
        "chips_y": 580,
        "headline_size": 78,
        "line_gap": 98,
    },
]


def add_text(cmd: list[str], *, font: str, size: int, fill: str, x: int, y: int, text: str) -> None:
    cmd.extend(
        [
            "-font", font,
            "-pointsize", str(size),
            "-fill", fill,
            "-stroke", "none",
            "-annotate", f"+{x}+{y}",
            text,
        ]
    )


def generate(spec: dict[str, object]) -> Path:
    name = str(spec["name"])
    source = ROOT / str(spec["source"])
    x, y, w, h = spec["image"]  # type: ignore[misc]
    headline = list(spec["headline"])  # type: ignore[arg-type]
    chips = list(spec["chips"])  # type: ignore[arg-type]
    output = OUT / f"{name}.jpg"

    cmd = [
        MAGICK,
        "-size", "1600x900",
        "gradient:#FFFDFC-#EDF1F5",
        "-gravity", "northwest",
        "-fill", "rgba(255,90,82,0.10)",
        "-stroke", "none",
        "-draw", "circle 1490,80 1810,80 circle 30,880 300,880",
        "-fill", "rgba(255,90,82,0.28)",
        "-draw", "circle 1480,770 1484,770 circle 1510,770 1514,770 circle 1540,770 1544,770 circle 1480,800 1484,800 circle 1510,800 1514,800 circle 1540,800 1544,800",
        "-fill", ACCENT,
        "-draw", "roundrectangle 80,66 126,112 14,14",
    ]
    add_text(cmd, font=HEAD, size=29, fill="#FFFFFF", x=93, y=72, text="A")
    add_text(cmd, font=HEAD, size=34, fill=INK, x=142, y=72, text="ApexTerm")
    add_text(cmd, font=BODY, size=20, fill=ACCENT, x=80, y=146, text=str(spec["kicker"]))

    for idx, line in enumerate(headline):
        add_text(
            cmd,
            font=HEAD,
            size=int(spec["headline_size"]),
            fill=INK,
            x=80,
            y=int(spec["headline_y"]) + idx * int(spec["line_gap"]),
            text=line,
        )

    add_text(cmd, font=BODY, size=27, fill=MUTED, x=80, y=int(spec["sub_y"]), text=str(spec["sub"]))

    cursor = 80
    chip_y = int(spec["chips_y"])
    for label in chips:
        width = max(132, 44 + len(label) * 22)
        cmd.extend(
            [
                "-fill", "#FFFFFF",
                "-stroke", "#DFE3EA",
                "-strokewidth", "2",
                "-draw", f"roundrectangle {cursor},{chip_y} {cursor + width},{chip_y + 52} 26,26",
            ]
        )
        text_x = cursor + max(18, int((width - len(label) * 19) / 2))
        add_text(cmd, font=BODY, size=21, fill=INK, x=text_x, y=chip_y + 10, text=label)
        cursor += width + 14

    # The actual README screenshot is composited directly. Its UI pixels are never redrawn.
    cmd.extend(
        [
            "-fill", "#FFFFFF",
            "-stroke", "#D5DAE2",
            "-strokewidth", "2",
            "-draw", f"roundrectangle {x - 10},{y - 10} {x + w + 10},{y + h + 10} 32,32",
            "(", str(source), "-resize", f"{w}x{h}!", ")",
            "-geometry", f"+{x}+{y}",
            "-composite",
        ]
    )

    add_text(cmd, font=BODY, size=20, fill="#5F6978", x=80, y=820, text="github.com/uniplanck/ApexTerm")
    add_text(cmd, font=BODY, size=18, fill=ACCENT, x=1165, y=820, text="NATIVE macOS TERMINAL WORKSPACE")
    cmd.extend(
        [
            "-colorspace", "sRGB",
            "-sampling-factor", "4:2:0",
            "-strip",
            "-quality", "91",
            str(output),
        ]
    )
    subprocess.run(cmd, check=True)
    return output


for item in SPECS:
    print(generate(item))

subprocess.run(
    ["zip", "-j", "-q", str(OUT / "ApexTerm_X_launch_assets.zip"), *[str(OUT / f"{item['name']}.jpg") for item in SPECS]],
    check=True,
)
