#!/usr/bin/env python3
"""Generate App Store Connect screenshots (English UI chrome) for Arqma Wallet Mobile."""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "store_assets" / "app_store"
LOGO = ROOT / "assets" / "images" / "arq_logo_with_padding.png"

# App Store Connect — iPhone 6.5" Display
SIZE_65_A = (1284, 2778)
SIZE_65_B = (1242, 2688)

# App Store Connect — iPad 13" Display (12.9" / 13" class)
SIZE_IPAD_13_A = (2048, 2732)
SIZE_IPAD_13_B = (2064, 2752)
SIZE_IPAD_13_LAND_A = (2732, 2048)
SIZE_IPAD_13_LAND_B = (2752, 2064)

SCAFFOLD = (14, 12, 9)
PANEL = (29, 29, 29)
PANEL_ALT = (26, 24, 18)
GOLD = (219, 209, 156)
GOLD_DIM = (168, 144, 96)
TEXT = (244, 236, 218)
TEXT_SEC = (201, 184, 150)
TEXT_MUTED = (138, 125, 98)
POSITIVE = (201, 209, 156)
NEGATIVE = (219, 40, 40)
OUTLINE = (92, 79, 56)
STATUS_BAR_H = 54
NAV_H = 92
SAFE_H = STATUS_BAR_H + 8


def _font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        if os.path.isfile(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _new_canvas(size: tuple[int, int]) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", size, SCAFFOLD)
    return img, ImageDraw.Draw(img)


def _status_bar(draw: ImageDraw.ImageDraw, w: int) -> None:
    draw.rectangle((0, 0, w, STATUS_BAR_H), fill=(10, 8, 6))
    draw.text((48, 18), "21:36", fill=TEXT, font=_font(28))
    draw.text((w - 200, 18), "●●●●  WiFi  99%", fill=TEXT_SEC, font=_font(24))


def _bottom_nav(draw: ImageDraw.ImageDraw, w: int, h: int, active: int) -> None:
    y0 = h - NAV_H
    draw.rectangle((0, y0, w, h), fill=(10, 8, 6), outline=OUTLINE)
    tabs = ["Send", "Receive", "History", "Pools", "Settings"]
    slot = w // len(tabs)
    for i, label in enumerate(tabs):
        cx = slot * i + slot // 2
        color = GOLD if i == active else TEXT_MUTED
        draw.text((cx - 40, y0 + 52), label, fill=color, font=_font(22))


def _header(draw: ImageDraw.ImageDraw, w: int, title: str, subtitle: str = "") -> int:
    y = SAFE_H
    draw.text((48, y), title, fill=GOLD, font=_font(44, bold=True))
    if subtitle:
        draw.text((48, y + 56), subtitle, fill=TEXT_SEC, font=_font(26))
        y += 100
    else:
        y += 64
    draw.line((48, y, w - 48, y), fill=OUTLINE, width=2)
    return y + 24


def _card(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str, body: str, accent: tuple[int, int, int] | None = None) -> None:
    draw.rounded_rectangle(box, radius=16, fill=PANEL, outline=OUTLINE, width=2)
    x0, y0, _, _ = box
    draw.text((x0 + 28, y0 + 24), title, fill=accent or GOLD, font=_font(30, bold=True))
    draw.text((x0 + 28, y0 + 72), body, fill=TEXT_SEC, font=_font(24))


def _paste_logo(img: Image.Image, xy: tuple[int, int], width: int) -> None:
    if not LOGO.is_file():
        return
    logo = Image.open(LOGO).convert("RGBA")
    ratio = width / logo.width
    nh = int(logo.height * ratio)
    logo = logo.resize((width, nh), Image.Resampling.LANCZOS)
    img.paste(logo, xy, logo)


def screen_accounts(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w)
    y = _header(draw, w, "Accounts", "Remote node · node1.arqma.com")
    accounts = [
        ("Main wallet", "12.45000000 ARQ", "Synced"),
        ("Savings", "0.00000000 ARQ", "Scanning 84%"),
        ("Test mobile", "3.12000000 ARQ", "Synced"),
    ]
    for i, (name, bal, st) in enumerate(accounts):
        box = (48, y + i * 200, w - 48, y + i * 200 + 170)
        _card(draw, box, name, f"{bal}\n{st}", GOLD if i == 0 else TEXT_SEC)
    y2 = y + len(accounts) * 200 + 40
    for label in ["Create new account", "Restore from seed", "Import from file"]:
        box = (48, y2, w - 48, y2 + 88)
        draw.rounded_rectangle(box, radius=14, fill=PANEL_ALT, outline=OUTLINE, width=2)
        draw.text((72, y2 + 28), label, fill=GOLD, font=_font(28))
        y2 += 104
    _bottom_nav(draw, w, h, 4)
    return img


def screen_home(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w)
    y = _header(draw, w, "Main wallet", "Height 2,841,502 / 2,841,502")
    box = (48, y, w - 48, y + 280)
    draw.rounded_rectangle(box, radius=20, fill=PANEL_ALT, outline=GOLD, width=3)
    draw.text((72, y + 36), "Balance", fill=TEXT_SEC, font=_font(28))
    draw.text((72, y + 88), "12.45000000", fill=GOLD, font=_font(56, bold=True))
    draw.text((72, y + 168), "ARQ  ·  unlocked 12.45000000", fill=TEXT_SEC, font=_font(24))
    y += 320
    _card(draw, (48, y, w - 48, y + 160), "Latest transaction", "Received +0.50000000 ARQ\nConfirmed · 2h ago", POSITIVE)
    y += 200
    _card(draw, (48, y, w - 48, y + 160), "Remote node", "node1.arqma.com:19994\nConnected · mainnet", GOLD_DIM)
    _paste_logo(img, (w // 2 - 120, h - NAV_H - 200), 240)
    _bottom_nav(draw, w, h, 0)
    return img


def screen_send(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w)
    y = _header(draw, w, "Send", "Send ARQ to a recipient address")
    fields = [
        ("Address", "arqT1abc…xyz9"),
        ("Amount", "1.25000000"),
        ("Priority fee", "Low"),
        ("Note", "Payment for services"),
    ]
    for label, value in fields:
        box = (48, y, w - 48, y + 120)
        draw.rounded_rectangle(box, radius=14, fill=PANEL, outline=OUTLINE, width=2)
        draw.text((72, y + 18), label, fill=TEXT_MUTED, font=_font(22))
        draw.text((72, y + 56), value, fill=TEXT, font=_font(30))
        y += 140
    btn = (48, h - NAV_H - 140, w - 48, h - NAV_H - 36)
    draw.rounded_rectangle(btn, radius=18, fill=GOLD_DIM, outline=GOLD, width=2)
    draw.text((w // 2 - 55, h - NAV_H - 100), "Send", fill=(20, 17, 10), font=_font(36, bold=True))
    _bottom_nav(draw, w, h, 0)
    return img


def screen_receive(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w)
    y = _header(draw, w, "Receive", "Share your address or QR code")
    qr_box = (w // 2 - 260, y, w // 2 + 260, y + 520)
    draw.rounded_rectangle(qr_box, radius=20, fill=(245, 240, 228), outline=GOLD, width=3)
    # faux QR grid
    x0, y0, x1, y1 = qr_box
    step = 28
    for yy in range(y0 + 24, y1 - 24, step):
        for xx in range(x0 + 24, x1 - 24, step):
            if (xx + yy) % (step * 2) == 0:
                draw.rectangle((xx, yy, xx + step - 4, yy + step - 4), fill=(30, 26, 18))
    y += 560
    _card(draw, (48, y, w - 48, y + 200), "Your address", "arqT9demo…wallet\nTap to copy")
    _bottom_nav(draw, w, h, 1)
    return img


def screen_history(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w)
    y = _header(draw, w, "History", "Last 30 days")
    txs = [
        ("Received", "+0.50000000 ARQ", POSITIVE),
        ("Sent", "−1.25000000 ARQ", TEXT),
        ("Service node", "+0.01000000 ARQ", GOLD_DIM),
        ("Received", "+2.00000000 ARQ", POSITIVE),
        ("Sent", "−0.08000000 ARQ", TEXT),
    ]
    for i, (kind, amt, col) in enumerate(txs):
        box = (48, y + i * 150, w - 48, y + i * 150 + 130)
        draw.rounded_rectangle(box, radius=14, fill=PANEL, outline=OUTLINE, width=2)
        draw.text((72, y + i * 150 + 28), kind, fill=col, font=_font(28, bold=True))
        draw.text((72, y + i * 150 + 72), amt, fill=TEXT_SEC, font=_font(26))
        draw.text((w - 220, y + i * 150 + 48), "Confirmed", fill=TEXT_MUTED, font=_font(22))
    _bottom_nav(draw, w, h, 2)
    return img


def screen_settings(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w)
    y = _header(draw, w, "Settings", "Mobile wallet · remote node")
    rows = [
        ("Remote node", "node1.arqma.com"),
        ("Network", "mainnet"),
        ("Language", "English"),
        ("History days", "30"),
        ("Version", "5.1.1"),
    ]
    for i, (k, v) in enumerate(rows):
        box = (48, y + i * 110, w - 48, y + i * 110 + 96)
        draw.rounded_rectangle(box, radius=12, fill=PANEL, outline=OUTLINE, width=1)
        draw.text((72, y + i * 110 + 20), k, fill=TEXT_MUTED, font=_font(22))
        draw.text((72, y + i * 110 + 52), v, fill=GOLD if k == "Remote node" else TEXT, font=_font(28))
    _bottom_nav(draw, w, h, 4)
    return img


SCREENS = [
    ("01_accounts.png", screen_accounts),
    ("02_wallet.png", screen_home),
    ("03_send.png", screen_send),
    ("04_receive.png", screen_receive),
    ("05_history.png", screen_history),
    ("06_settings.png", screen_settings),
]


def _write_set(label: str, master_size: tuple[int, int], alt_size: tuple[int, int] | None) -> None:
    dest = OUT / label
    dest.mkdir(parents=True, exist_ok=True)
    for name, fn in SCREENS:
        master = fn(master_size)
        master.save(dest / name, format="PNG", optimize=True)
        if alt_size:
            alt = master.resize(alt_size, Image.Resampling.LANCZOS)
            alt.save(dest / name.replace(".png", f"_{alt_size[0]}x{alt_size[1]}.png"), format="PNG", optimize=True)
    print(f"Wrote {len(SCREENS)} screenshots → {dest}")


def main() -> None:
    _write_set("iphone_65_1284x2778", SIZE_65_A, SIZE_65_B)
    _write_set("ipad_13_2048x2732", SIZE_IPAD_13_A, SIZE_IPAD_13_B)
    _write_set("ipad_13_2732x2048_landscape", SIZE_IPAD_13_LAND_A, SIZE_IPAD_13_LAND_B)
    readme = OUT / "README.md"
    readme.write_text(
        """# App Store Connect — screenshots (English)

## iPhone 6.5\" Display

Folder: **`iphone_65_1284x2778/`** — **1284 × 2778** px (portrait). Alt: **1242 × 2688**.

| File | Screen |
|------|--------|
| `01_accounts.png` | Accounts |
| `02_wallet.png` | Wallet / balance |
| `03_send.png` | Send |
| `04_receive.png` | Receive + QR |
| `05_history.png` | History |
| `06_settings.png` | Settings |

## iPad 13\" Display

Folder: **`ipad_13_2048x2732/`** — **2048 × 2732** px (portrait). Alt: **2064 × 2752**.

Same six screens as iPhone. Upload portrait set in App Store Connect → iPad → 13\" Display.

Optional landscape: **`ipad_13_2732x2048_landscape/`** — **2732 × 2048** (alt **2752 × 2064**).

## Regenerate

```bash
cd flutter-mobile/arqma_wallet_mobile
./tool/generate_app_store_screenshots.sh
```
""",
        encoding="utf-8",
    )
    print(f"README → {readme}")


if __name__ == "__main__":
    main()
