#!/usr/bin/env python3
"""Generate App Store Connect screenshots (English UI chrome) for Arqma Wallet Mobile."""

from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "store_assets" / "app_store"
UPLOAD_READY = OUT / "upload_ready" / "iphone_65_1284x2778"
LOGO = ROOT / "assets" / "images" / "arq_logo_with_padding.png"
APP_VERSION = "5.1.2"

# App Store Connect — iPhone 6.5" Display
SIZE_65_A = (1284, 2778)
SIZE_65_B = (1242, 2688)

# App Store Connect — iPad 13" Display (12.9" / 13" class)
SIZE_IPAD_13_A = (2048, 2732)
SIZE_IPAD_13_B = (2064, 2752)
SIZE_IPAD_13_LAND_A = (2732, 2048)
SIZE_IPAD_13_LAND_B = (2752, 2064)

# Parity with lib/core/theme/arqma_colors.dart
SCAFFOLD = (14, 12, 9)  # #0E0C09
PANEL = (29, 29, 29)  # darkPanel
PANEL_ALT = (22, 20, 16)
GOLD = (219, 209, 156)  # arqmaGreenSolid #DBD19C
GOLD_DIM = (168, 144, 96)  # arqmaGreenDarkSolid
TEXT = (244, 236, 218)  # textPrimary
TEXT_SEC = (201, 184, 150)  # textSecondary
TEXT_MUTED = (138, 125, 98)
POSITIVE = (201, 169, 90)  # txIn
IDENTICON = (203, 143, 225)
OUTLINE = (92, 79, 56)
HEADER_BG = (10, 10, 10)
STATUS_BAR_H = 54
TAB_BAR_H = 88
FOOTER_H = 118
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


def _scale(size: tuple[int, int], px: int) -> int:
    return max(1, int(px * size[0] / 1284))


def _new_canvas(size: tuple[int, int], bg: tuple[int, int, int] = SCAFFOLD) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", size, bg)
    return img, ImageDraw.Draw(img)


def _status_bar(draw: ImageDraw.ImageDraw, w: int, size: tuple[int, int]) -> None:
    fs = _scale(size, 28)
    draw.rectangle((0, 0, w, STATUS_BAR_H), fill=HEADER_BG)
    draw.text((_scale(size, 48), _scale(size, 18)), "21:36", fill=TEXT, font=_font(fs))
    draw.text((w - _scale(size, 200), _scale(size, 18)), "●●●●  WiFi  99%", fill=TEXT_SEC, font=_font(_scale(size, 24)))


def _paste_logo(img: Image.Image, xy: tuple[int, int], width: int) -> None:
    if not LOGO.is_file():
        return
    logo = Image.open(LOGO).convert("RGBA")
    ratio = width / logo.width
    nh = int(logo.height * ratio)
    logo = logo.resize((width, nh), Image.Resampling.LANCZOS)
    img.paste(logo, xy, logo)


def _draw_spinner(draw: ImageDraw.ImageDraw, cx: int, cy: int, radius: int) -> None:
    draw.arc(
        (cx - radius, cy - radius, cx + radius, cy + radius),
        start=0,
        end=300,
        fill=GOLD,
        width=max(3, radius // 8),
    )


def _draw_identicon(draw: ImageDraw.ImageDraw, cx: int, cy: int, radius: int, seed: int) -> None:
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=IDENTICON)
    for i in range(6):
        angle = seed * 0.7 + i * 1.05
        x = cx + int(math.cos(angle) * radius * 0.45)
        y = cy + int(math.sin(angle) * radius * 0.45)
        r = max(4, radius // 5)
        hue = (seed * 40 + i * 37) % 360
        col = (
            120 + (hue % 80),
            90 + ((hue // 2) % 60),
            140 + ((hue // 3) % 50),
        )
        draw.ellipse((x - r, y - r, x + r, y + r), fill=col)


def _wallet_tab_bar(draw: ImageDraw.ImageDraw, w: int, y: int, active: int, size: tuple[int, int]) -> int:
    tabs = ["Transactions", "Send", "Receive", "Staking pools", "Address book"]
    h = TAB_BAR_H
    draw.rectangle((0, y, w, y + h), fill=HEADER_BG, outline=OUTLINE)
    slot = w // len(tabs)
    fs = _scale(size, 20)
    for i, label in enumerate(tabs):
        cx = slot * i + slot // 2
        color = GOLD if i == active else TEXT_MUTED
        short = label if len(label) <= 12 else label.split()[0]
        tw = draw.textlength(short, font=_font(fs))
        draw.text((cx - tw / 2, y + _scale(size, 52)), short, fill=color, font=_font(fs))
        if i == active:
            draw.line((slot * i + 8, y + h - 4, slot * (i + 1) - 8, y + h - 4), fill=GOLD, width=3)
    return y + h


def _status_footer(draw: ImageDraw.ImageDraw, w: int, h: int, size: tuple[int, int], line: str) -> None:
    y0 = h - FOOTER_H
    draw.rectangle((0, y0, w, h), fill=HEADER_BG, outline=OUTLINE)
    fs = _scale(size, 22)
    draw.text((_scale(size, 24), y0 + _scale(size, 18)), line, fill=TEXT_SEC, font=_font(fs))
    draw.text((_scale(size, 24), y0 + _scale(size, 52)), f"Arqma Wallet {APP_VERSION} · English", fill=TEXT_MUTED, font=_font(_scale(size, 20)))
    draw.text((w - _scale(size, 280), y0 + _scale(size, 36)), "Height 2,841,502 / 2,841,502", fill=TEXT_MUTED, font=_font(_scale(size, 20)))


def screen_splash(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size, SCAFFOLD)
    _status_bar(draw, w, size)
    logo_w = _scale(size, 420)
    logo_x = w // 2 - logo_w // 2
    logo_y = h // 2 - _scale(size, 320)
    _paste_logo(img, (logo_x, logo_y), logo_w)
    title_y = logo_y + _scale(size, 260)
    title = "Arqma Wallet"
    tw = draw.textlength(title, font=_font(_scale(size, 44), bold=True))
    draw.text((w // 2 - tw / 2, title_y), title, fill=TEXT, font=_font(_scale(size, 44), bold=True))
    sub = "Starting…"
    sw = draw.textlength(sub, font=_font(_scale(size, 28)))
    draw.text((w // 2 - sw / 2, title_y + _scale(size, 64)), sub, fill=TEXT_SEC, font=_font(_scale(size, 28)))
    _draw_spinner(draw, w // 2, title_y + _scale(size, 170), _scale(size, 44))
    return img


def screen_accounts(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w, size)
    pad = _scale(size, 48)
    y = SAFE_H + _scale(size, 12)
    draw.text((pad, y), "Accounts", fill=GOLD, font=_font(_scale(size, 44), bold=True))
    y += _scale(size, 58)
    draw.text((pad, y), "Remote node · node1.arqma.com", fill=TEXT_SEC, font=_font(_scale(size, 26)))
    y += _scale(size, 36)
    draw.line((pad, y, w - pad, y), fill=OUTLINE, width=2)
    y += _scale(size, 28)

    accounts = [
        ("Main wallet", "arqT9Kp…4mN2xQ7", 12),
        ("Savings", "arqT3Lm…8pR1vW5", 7),
        ("Test mobile", "arqT6Hn…2kD9sF4", 3),
    ]
    row_h = _scale(size, 168)
    for i, (name, addr, seed) in enumerate(accounts):
        box = (pad, y + i * (row_h + _scale(size, 16)), w - pad, y + i * (row_h + _scale(size, 16)) + row_h)
        draw.rounded_rectangle(box, radius=16, fill=PANEL_ALT, outline=OUTLINE, width=2)
        icon_r = _scale(size, 36)
        _draw_identicon(draw, box[0] + _scale(size, 56), (box[1] + box[3]) // 2, icon_r, seed)
        draw.text((box[0] + _scale(size, 112), box[1] + _scale(size, 28)), name, fill=TEXT, font=_font(_scale(size, 30), bold=True))
        draw.text((box[0] + _scale(size, 112), box[1] + _scale(size, 78)), addr, fill=TEXT_MUTED, font=_font(_scale(size, 22)))
        draw.text((box[2] - _scale(size, 160), box[1] + _scale(size, 52)), "Open", fill=GOLD, font=_font(_scale(size, 26), bold=True))

    y2 = y + len(accounts) * (row_h + _scale(size, 16)) + _scale(size, 24)
    for label in ["Create new account", "Restore from seed", "Import view-only wallet"]:
        box = (pad, y2, w - pad, y2 + _scale(size, 88))
        draw.rounded_rectangle(box, radius=14, fill=PANEL, outline=OUTLINE, width=2)
        draw.text((pad + _scale(size, 24), y2 + _scale(size, 28)), label, fill=GOLD, font=_font(_scale(size, 28)))
        y2 += _scale(size, 104)

    _status_footer(draw, w, h, size, "Ready · mainnet · node1.arqma.com:19994")
    return img


def screen_home(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w, size)
    pad = _scale(size, 16)
    app_h = _scale(size, 168)
    draw.rectangle((0, SAFE_H, w, SAFE_H + app_h), fill=HEADER_BG)
    _paste_logo(img, (pad, SAFE_H + _scale(size, 20)), _scale(size, 104))
    bal_y = SAFE_H + _scale(size, 36)
    draw.text((w // 2 - _scale(size, 180), bal_y), "12.45000000", fill=GOLD, font=_font(_scale(size, 46), bold=True))
    draw.text((w // 2 + _scale(size, 20), bal_y + _scale(size, 8)), "ARQ", fill=GOLD, font=_font(_scale(size, 28)))
    draw.text((w // 2 - _scale(size, 120), bal_y + _scale(size, 58)), "unlocked 12.45000000 ARQ", fill=TEXT_SEC, font=_font(_scale(size, 22)))

    tab_y = SAFE_H + app_h
    body_y = _wallet_tab_bar(draw, w, tab_y, 0, size)

    txs = [
        ("Received", "+0.50000000 ARQ", POSITIVE),
        ("Sent", "−1.25000000 ARQ", TEXT),
        ("Service node reward", "+0.01000000 ARQ", GOLD_DIM),
        ("Received", "+2.00000000 ARQ", POSITIVE),
    ]
    row_h = _scale(size, 132)
    for i, (kind, amt, col) in enumerate(txs):
        box = (pad, body_y + _scale(size, 16) + i * (row_h + _scale(size, 12)), w - pad, body_y + _scale(size, 16) + i * (row_h + _scale(size, 12)) + row_h)
        draw.rounded_rectangle(box, radius=14, fill=PANEL, outline=OUTLINE, width=1)
        draw.text((pad + _scale(size, 24), box[1] + _scale(size, 24)), kind, fill=col, font=_font(_scale(size, 28), bold=True))
        draw.text((pad + _scale(size, 24), box[1] + _scale(size, 68)), amt, fill=TEXT_SEC, font=_font(_scale(size, 24)))
        draw.text((w - pad - _scale(size, 180), box[1] + _scale(size, 44)), "Confirmed", fill=TEXT_MUTED, font=_font(_scale(size, 20)))

    _status_footer(draw, w, h, size, "Synced · mainnet · node1.arqma.com")
    return img


def screen_send(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w, size)
    pad = _scale(size, 48)
    y = SAFE_H + _scale(size, 12)
    draw.text((pad, y), "Send", fill=GOLD, font=_font(_scale(size, 44), bold=True))
    y += _scale(size, 64)
    draw.line((pad, y, w - pad, y), fill=OUTLINE, width=2)
    y += _scale(size, 24)
    fields = [
        ("Address", "arqT1abc…xyz9"),
        ("Amount", "1.25000000"),
        ("Priority fee", "Low"),
        ("Note", "Payment for services"),
    ]
    for label, value in fields:
        box = (pad, y, w - pad, y + _scale(size, 120))
        draw.rounded_rectangle(box, radius=14, fill=PANEL, outline=OUTLINE, width=2)
        draw.text((pad + _scale(size, 24), y + _scale(size, 18)), label, fill=TEXT_MUTED, font=_font(_scale(size, 22)))
        draw.text((pad + _scale(size, 24), y + _scale(size, 56)), value, fill=TEXT, font=_font(_scale(size, 30)))
        y += _scale(size, 140)
    btn = (pad, h - FOOTER_H - _scale(size, 140), w - pad, h - FOOTER_H - _scale(size, 36))
    draw.rounded_rectangle(btn, radius=18, fill=GOLD_DIM, outline=GOLD, width=2)
    draw.text((w // 2 - _scale(size, 55), btn[1] + _scale(size, 36)), "Send", fill=(20, 17, 10), font=_font(_scale(size, 36), bold=True))
    tab_y = btn[1] - TAB_BAR_H - _scale(size, 8)
    _wallet_tab_bar(draw, w, tab_y, 1, size)
    _status_footer(draw, w, h, size, "Synced · mainnet")
    return img


def screen_receive(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w, size)
    pad = _scale(size, 48)
    y = SAFE_H + _scale(size, 12)
    draw.text((pad, y), "Receive", fill=GOLD, font=_font(_scale(size, 44), bold=True))
    y += _scale(size, 64)
    draw.line((pad, y, w - pad, y), fill=OUTLINE, width=2)
    y += _scale(size, 24)
    qr_size = _scale(size, 520)
    qr_box = (w // 2 - qr_size // 2, y, w // 2 + qr_size // 2, y + qr_size)
    draw.rounded_rectangle(qr_box, radius=20, fill=(255, 248, 237), outline=GOLD, width=3)
    x0, y0, x1, y1 = qr_box
    step = _scale(size, 28)
    for yy in range(y0 + 24, y1 - 24, step):
        for xx in range(x0 + 24, x1 - 24, step):
            if (xx + yy) % (step * 2) == 0:
                draw.rectangle((xx, yy, xx + step - 4, yy + step - 4), fill=(30, 26, 18))
    y += qr_size + _scale(size, 32)
    box = (pad, y, w - pad, y + _scale(size, 180))
    draw.rounded_rectangle(box, radius=16, fill=PANEL, outline=OUTLINE, width=2)
    draw.text((pad + _scale(size, 28), y + _scale(size, 24)), "Your address", fill=GOLD, font=_font(_scale(size, 30), bold=True))
    draw.text((pad + _scale(size, 28), y + _scale(size, 72)), "arqT9demo…wallet\nTap to copy", fill=TEXT_SEC, font=_font(_scale(size, 24)))
    _status_footer(draw, w, h, size, "Synced · mainnet")
    return img


def screen_history(size: tuple[int, int]) -> Image.Image:
    return screen_home(size)


def screen_settings(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img, draw = _new_canvas(size)
    _status_bar(draw, w, size)
    pad = _scale(size, 48)
    y = SAFE_H + _scale(size, 12)
    draw.text((pad, y), "Settings", fill=GOLD, font=_font(_scale(size, 44), bold=True))
    y += _scale(size, 58)
    draw.text((pad, y), "Mobile wallet · remote node", fill=TEXT_SEC, font=_font(_scale(size, 26)))
    y += _scale(size, 36)
    draw.line((pad, y, w - pad, y), fill=OUTLINE, width=2)
    y += _scale(size, 24)
    rows = [
        ("Remote node", "node1.arqma.com"),
        ("Network", "mainnet"),
        ("Language", "English"),
        ("History days", "30"),
        ("Version", APP_VERSION),
    ]
    for i, (k, v) in enumerate(rows):
        box = (pad, y + i * _scale(size, 110), w - pad, y + i * _scale(size, 110) + _scale(size, 96))
        draw.rounded_rectangle(box, radius=12, fill=PANEL, outline=OUTLINE, width=1)
        draw.text((pad + _scale(size, 24), box[1] + _scale(size, 20)), k, fill=TEXT_MUTED, font=_font(_scale(size, 22)))
        draw.text((pad + _scale(size, 24), box[1] + _scale(size, 52)), v, fill=GOLD if k == "Remote node" else TEXT, font=_font(_scale(size, 28)))
    _status_footer(draw, w, h, size, "Ready · mainnet")
    return img


SCREENS = [
    ("01_splash.png", screen_splash),
    ("02_accounts.png", screen_accounts),
    ("03_wallet.png", screen_home),
    ("04_send.png", screen_send),
    ("05_receive.png", screen_receive),
    ("06_history.png", screen_history),
    ("07_settings.png", screen_settings),
]

UPLOAD_PRIMARY = [
    "01_splash.png",
    "02_accounts.png",
    "03_wallet.png",
]

LEGACY_NAMES = [
    "01_accounts.png",
    "02_wallet.png",
    "03_send.png",
    "04_receive.png",
    "05_history.png",
    "06_settings.png",
]


def _write_set(label: str, master_size: tuple[int, int], alt_size: tuple[int, int] | None) -> None:
    dest = OUT / label
    dest.mkdir(parents=True, exist_ok=True)
    for legacy in LEGACY_NAMES:
        legacy_path = dest / legacy
        if legacy_path.is_file():
            legacy_path.unlink()
    for name, fn in SCREENS:
        master = fn(master_size)
        master.save(dest / name, format="PNG", optimize=True)
        if alt_size:
            alt = master.resize(alt_size, Image.Resampling.LANCZOS)
            alt.save(dest / name.replace(".png", f"_{alt_size[0]}x{alt_size[1]}.png"), format="PNG", optimize=True)
    print(f"Wrote {len(SCREENS)} screenshots → {dest}")


def _write_upload_ready() -> None:
    src = OUT / "iphone_65_1284x2778"
    UPLOAD_READY.mkdir(parents=True, exist_ok=True)
    for legacy in UPLOAD_READY.glob("*.png"):
        legacy.unlink()
    for name in UPLOAD_PRIMARY:
        src_file = src / name
        if not src_file.is_file():
            continue
        dest = UPLOAD_READY / name
        dest.write_bytes(src_file.read_bytes())
    readme = UPLOAD_READY.parent / "README.md"
    readme.write_text(
        f"""# App Store Connect — upload-ready screenshots

Primary **iPhone 6.5\" Display** set for version **{APP_VERSION}**.

Upload these three PNGs first (in order), then add optional screens from `../iphone_65_1284x2778/` if needed.

| Order | File | Screen |
|-------|------|--------|
| 1 | `iphone_65_1284x2778/01_splash.png` | App launch / loading with Arqma logo |
| 2 | `iphone_65_1284x2778/02_accounts.png` | Wallet list (Accounts) |
| 3 | `iphone_65_1284x2778/03_wallet.png` | Open wallet — balance & transactions |

## App Store Connect

1. [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **Arqma Wallet** → **5.1.2** (or current version).
2. **App Store** tab → **Screenshots** → **iPhone 6.5\" Display**.
3. Drag files from `upload_ready/iphone_65_1284x2778/` (1284×2778) or the parent folder (alt 1242×2688 also accepted).
4. Optional: **iPad 13\" Display** — use matching files from `../ipad_13_2048x2732/`.
5. Save → submit for review when metadata is complete.

Regenerate: `./tool/generate_app_store_screenshots.sh`
""",
        encoding="utf-8",
    )
    print(f"Upload-ready set → {UPLOAD_READY}")


def main() -> None:
    _write_set("iphone_65_1284x2778", SIZE_65_A, SIZE_65_B)
    _write_set("ipad_13_2048x2732", SIZE_IPAD_13_A, SIZE_IPAD_13_B)
    _write_set("ipad_13_2732x2048_landscape", SIZE_IPAD_13_LAND_A, SIZE_IPAD_13_LAND_B)
    _write_upload_ready()
    readme = OUT / "README.md"
    readme.write_text(
        f"""# App Store Connect — screenshots (English)

Version **{APP_VERSION}**. Regenerate with `./tool/generate_app_store_screenshots.sh`.

## Quick upload (recommended order)

See **`upload_ready/README.md`** — three primary iPhone 6.5\" screenshots:

1. **Splash** — loading screen with Arqma logo
2. **Accounts** — wallet list
3. **Wallet** — open wallet with balance & history

## iPhone 6.5\" Display

Folder: **`iphone_65_1284x2778/`** — **1284 × 2778** px (portrait). Alt: **1242 × 2688**.

| File | Screen |
|------|--------|
| `01_splash.png` | Launch / loading |
| `02_accounts.png` | Accounts list |
| `03_wallet.png` | Wallet / balance & transactions |
| `04_send.png` | Send |
| `05_receive.png` | Receive + QR |
| `06_history.png` | Transaction history |
| `07_settings.png` | Settings |

## iPad 13\" Display

Folder: **`ipad_13_2048x2732/`** — **2048 × 2732** px (portrait). Alt: **2064 × 2752**.

Same seven screens as iPhone. Upload portrait set in App Store Connect → iPad → 13\" Display.

Optional landscape: **`ipad_13_2732x2048_landscape/`** — **2732 × 2048** (alt **2752 × 2064**).
""",
        encoding="utf-8",
    )
    print(f"README → {readme}")


if __name__ == "__main__":
    main()
