# -*- coding: utf-8 -*-
"""VCD → 波形图片（Pillow 画的），用于贴进课程报告。"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

CN_FONT = r"C:\Windows\Fonts\msyh.ttc"
MONO = r"C:\Windows\Fonts\consola.ttf"

C_BG = (255, 255, 255)
C_GRID = (228, 232, 240)
C_TEXT = (30, 41, 59)
C_HIGH = (22, 163, 74)
C_LOW = (100, 116, 139)
C_X = (220, 38, 38)
C_BUS = (37, 99, 235)
C_NAME = (15, 23, 42)


def parse_vcd(path):
    """返回 (defs, chg, unit_ns)：unit_ns = 1 个 VCD 时间单位等于多少 ns。"""
    import re as _re
    with open(path, "r", errors="replace") as _f:
        _head = _f.read(4000)
    _m = _re.search(r"\$timescale\s+(\d+)\s*(fs|ps|ns|us|ms|s)", _head.replace("\n", " "))
    _mult = {"fs": 1e-6, "ps": 1e-3, "ns": 1.0, "us": 1e3, "ms": 1e6, "s": 1e9}
    unit_ns = float(_m.group(1)) * _mult[_m.group(2)] if _m else 1.0
    defs = {}
    chg = {}
    t = 0
    with open(path, "r", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("$var"):
                p = line.split()
                width, vid, name = int(p[2]), p[3], p[4]
                defs.setdefault(name, []).append((vid, width))
            elif line.startswith("#"):
                try:
                    t = int(line[1:])
                except ValueError:
                    pass
            elif line[0] in "01xzXZ" and len(line) >= 2:
                chg.setdefault(line[1:], []).append((t, line[0]))
            elif line[0] == "b":
                p = line.split()
                chg.setdefault(p[1], []).append((t, p[0][1:]))
    return defs, chg, unit_ns


def series(defs, chg, name):
    if name not in defs:
        raise KeyError(f"VCD 里没有信号 {name}，有的：{sorted(defs)[:20]}")
    vid, width = defs[name][0]
    return chg.get(vid, []), width


def nice_step(target):
    import math
    if target <= 0:
        return 1
    exp = math.floor(math.log10(target))
    base = target / (10 ** exp)
    for m in (1, 2, 2.5, 5, 10):
        if base <= m:
            return m * (10 ** exp)
    return 10 ** (exp + 1)


def hexval(bits):
    try:
        v = int(bits, 2)
        return f"0x{v:0{(len(bits) + 3) // 4}X}"
    except ValueError:
        return "x"


def render(vcd, out, specs, title, subtitle="", bit_grid=None):
    defs, chg, unit_ns = parse_vcd(vcd)
    chg = {k: [(t * unit_ns, v) for (t, v) in lst] for k, lst in chg.items()}

    items = []
    tmax = 0
    for name, label in specs:
        pts, width = series(defs, chg, name)
        items.append((label or name, width, pts))
        if pts:
            tmax = max(tmax, pts[-1][0])
    tmax = max(tmax, 1)

    W, LEFT, RIGHT, TOP, BOT = 1700, 210, 40, 96, 56
    ROW = 60
    H = TOP + ROW * len(items) + BOT
    img = Image.new("RGB", (W, H), C_BG)
    d = ImageDraw.Draw(img)

    f_title = ImageFont.truetype(CN_FONT, 30)
    f_sub = ImageFont.truetype(CN_FONT, 18)
    f_name = ImageFont.truetype(MONO, 17)
    f_val = ImageFont.truetype(MONO, 14)
    f_tick = ImageFont.truetype(MONO, 14)

    d.text((LEFT, 18), title, font=f_title, fill=C_TEXT)
    if subtitle:
        d.text((LEFT, 60), subtitle, font=f_sub, fill=(71, 85, 105))

    plot_x0, plot_x1 = LEFT, W - RIGHT

    def X(t):
        return plot_x0 + (t / tmax) * (plot_x1 - plot_x0)

    # 网格 + 时间刻度（取整齐的步长：1/2/2.5/5 × 10^n）
    step = nice_step(tmax / 8.0)
    v = 0
    while v <= tmax + 1e-9:
        x = X(v)
        d.line([(x, TOP - 8), (x, H - BOT + 6)], fill=C_GRID, width=1)
        d.text((x + 3, H - BOT + 10), f"{v:.0f} ns", font=f_tick, fill=(120, 130, 145))
        v += step

    # 比特边界（UART 专用）：从 tx 第一个下降沿开始，每 bit_ns 一条虚线
    if bit_grid == "uart":
        pts, _ = series(defs, chg, "tx")
        t0 = next((tt for tt, vv in pts if vv == "0"), 0)
        bit_ns = 100.0
        for k in range(11):
            xk = X(t0 + k * bit_ns)
            yy = TOP - 8
            while yy < H - BOT + 6:
                d.line([(xk, yy), (xk, yy + 6)], fill=(148, 163, 184), width=1)
                yy += 12

    for i, (label, width, pts) in enumerate(items):
        y0 = TOP + i * ROW
        d.rectangle([0, y0, W, y0 + ROW - 1], outline=(240, 242, 246))
        d.text((LEFT - 12 - d.textlength(label, font=f_name), y0 + ROW // 2 - 10),
               label, font=f_name, fill=C_NAME)

        data = [(0, pts[0][1])] + pts if pts and pts[0][0] > 0 else (pts or [(0, "x")])

        if width == 1:
            y_hi, y_lo = y0 + 10, y0 + ROW - 18
            prev_t, prev_v = data[0]
            for (t, v) in data[1:]:
                y_prev = y_hi if prev_v == "1" else (y_lo if prev_v == "0" else (y_hi + y_lo) // 2)
                col = C_HIGH if prev_v == "1" else (C_LOW if prev_v == "0" else C_X)
                d.line([(X(prev_t), y_prev), (X(t), y_prev)], fill=col, width=3)
                y_new = y_hi if v == "1" else (y_lo if v == "0" else (y_hi + y_lo) // 2)
                d.line([(X(t), y_prev), (X(t), y_new)], fill=col, width=3)
                prev_t, prev_v = t, v
            y_prev = y_hi if prev_v == "1" else (y_lo if prev_v == "0" else (y_hi + y_lo) // 2)
            col = C_HIGH if prev_v == "1" else (C_LOW if prev_v == "0" else C_X)
            d.line([(X(prev_t), y_prev), (X(tmax), y_prev)], fill=col, width=3)
        else:
            y_hi, y_lo = y0 + 12, y0 + ROW - 20
            prev_t, prev_v = data[0]
            for (t, v) in data[1:]:
                xa, xb = X(prev_t), X(t)
                if xb - xa > 3:
                    d.polygon([(xa + 4, y_hi), (xb - 4, y_hi), (xb, y_lo - 4),
                               (xb - 4, y_lo), (xa + 4, y_lo), (xa, y_lo - 4)],
                              outline=C_BUS)
                    txt = hexval(prev_v)
                    if xb - xa > 64:
                        d.text(((xa + xb) / 2 - d.textlength(txt, font=f_val) / 2,
                                (y_hi + y_lo) / 2 - 9), txt, font=f_val, fill=C_BUS)
                d.line([(xb, y_hi), (xb, y_lo)], fill=C_BUS, width=2)
                prev_t, prev_v = t, v
            xa = X(prev_t)
            if plot_x1 - xa > 4:
                d.polygon([(xa + 4, y_hi), (plot_x1 - 4, y_hi), (plot_x1, y_lo - 4),
                           (plot_x1 - 4, y_lo), (xa + 4, y_lo), (xa, y_lo - 4)],
                          outline=C_BUS)
                txt = hexval(prev_v)
                if plot_x1 - xa > 64:
                    d.text(((xa + plot_x1) / 2 - d.textlength(txt, font=f_val) / 2,
                            (y_hi + y_lo) / 2 - 9), txt, font=f_val, fill=C_BUS)

    d.line([(plot_x0, TOP - 8), (plot_x0, H - BOT + 6)], fill=(203, 213, 225), width=1)
    img.save(out)
    print("saved", out, img.size)


if __name__ == "__main__":
    W = os.path.dirname(os.path.abspath(__file__))
    render(
        W + r"\wave_uart.vcd",
        W + r"\uart_wave.png",
        [("clk", "clk"), ("rst", "rst"), ("valid", "valid"), ("ready", "ready"),
         ("data", "data[7:0]"), ("tx", "tx")],
        "UART 8N1 发送时序：发送 0xA5（LSB 先发）",
        "空闲高 → 起始位 0 → 8 个数据位 1 0 1 0 0 1 0 1 → 停止位 1；仿真把分频比压成 10:1，1 比特 = 100 ns；虚线为比特边界", bit_grid="uart",
    )
    render(
        W + r"\wave_oled.vcd",
        W + r"\oled_wave.png",
        [("clk", "clk"), ("oled_res", "oled_res"), ("oled_cs", "oled_cs"),
         ("oled_dc", "oled_dc"), ("oled_sclk", "oled_sclk"), ("oled_sdin", "oled_sdin")],
        "Pmod OLED（SSD1306）SPI 初始化时序：写完 8 位数据",
        "CS 低有效；D/C=0 表示命令；SCLK 空闲低、上升沿采样、MSB 先出；每字节之间留 GAP",
    )
