# -*- coding: utf-8 -*-
"""
gen_pin_doc.py —— 从 xdc/sys_pins.xdc 自动生成 docs/引脚分配.md

为什么这么做：
    引脚表原来是手写的，和 xdc 两份维护，迟早对不上（之前就出现过编号重复、
    JD 被塞进 VGA 那一节的问题）。现在**唯一事实来源就是 xdc**，文档自动生成。

用法（仓库根目录）：
    python tools/gen_pin_doc.py
"""
import os
import re
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
XDC = os.path.join(ROOT, "xdc", "sys_pins.xdc")
OUT = os.path.join(ROOT, "docs", "引脚分配.md")

# 端口前缀 → (小节标题, 说明)
GROUPS = OrderedDict([
    ("系统", ("一、系统（时钟 / 复位）", "全系统只有一个时钟源，复位低有效。")),
    ("拨码开关", ("二、拨码开关 `SW[15:0]`", "阈值设定用，含义见 `接口协议.md` 第五节。")),
    ("按键", ("三、按键 `BTN[4:0]`", "已过 `common/debounce.v` 的 10 ms 消抖。")),
    ("LED", ("四、LED `LED[15:0]`", "`LED[3:0]`=报警等级，`LED[7:4]`=报警来源，`LED[8]`=蜂鸣器在响。")),
    ("数码管", ("五、8 位数码管（段选 `SEG` / 位选 `AN`）", "共阳极，段选与位选都是**低有效**，AN0 = 最右一位。")),
    ("JA (OLED)", ("六、Pmod JA —— Pmod OLED（SPI）", "128×32 单色 OLED（SSD1306），v2 起已上板验证。")),
    ("JB (HYGRO)", ("七、Pmod JB —— Pmod HYGRO 温湿度（6 针 I2C）", "板载 SHTC3，7 位地址 0x70。")),
    ("JC (ALS)", ("八、Pmod JC —— Pmod ALS 光照（6 针 SPI）", "板载 ADC081S021（8 位），SCLK 上限 4 MHz。")),
    ("JD (蜂鸣器)", ("九、Pmod JD（丝印 JXADC）—— 自制蜂鸣器模块", "只用了 1 根信号线，其余引脚留空备用。")),
    ("VGA", ("十、VGA（板载接口，12 位色）", "R/G/B 各 4 位；HS/VS 负极性同步。")),
    ("串口", ("十一、板载 USB-UART（串口上报）", "和 JTAG 共用一根 USB 线，115200 8N1。")),
])



# 需要额外解释的组（模块引脚号 ↔ FPGA 引脚，这部分 xdc 里没有，手写）
EXTRA = {
    "数码管": [
        "> 段选位序：`SEG[7:0] = {DP, CG, CF, CE, CD, CC, CB, CA}`（bit7 = 小数点）。",
        "> 位选：`AN[0]` = 最右一位，`AN[7]` = 最左一位。",
        "",
    ],
    "JA (OLED)": [
        "**模块引脚 ↔ 信号**（12 针 Pmod，模块只用了 1、2、4、7、8 脚）：",
        "",
        "| 模块脚 | 信号 | FPGA 引脚 |",
        "|---|---|---|",
        "| 1 | CS | C17 |",
        "| 2 | SDIN | D18 |",
        "| 4 | SCLK | G17 |",
        "| 7 | D/C | D17 |",
        "| 8 | RES | E17 |",
        "| 5 / 11 | GND | — |",
        "| 6 / 12 | VCC 3.3 V | — |",
        "",
    ],
    "JB (HYGRO)": [
        "**模块引脚 ↔ 信号**（官方手册 J1：`1=NC 2=NC 3=SCL 4=SDA 5=GND 6=VCC`）：",
        "",
        "| 模块脚 | 信号 | FPGA 引脚 |",
        "|---|---|---|",
        "| 1 / 2 | NC（空脚） | D14 / F16（本工程不接） |",
        "| **3** | **SCL** | **G16** |",
        "| **4** | **SDA** | **H14** |",
        "| 5 | GND | — |",
        "| 6 | VCC 3.3 V | — |",
        "",
        "> ⚠️ SCL/SDA **不在 1、2 脚**，这是最容易接错的地方。",
        "",
    ],
    "JC (ALS)": [
        "**模块引脚 ↔ 信号**（官方手册：`1=~CS 2=NC 3=MISO 4=SCLK 5=GND 6=VCC`）：",
        "",
        "| 模块脚 | 信号 | FPGA 引脚 |",
        "|---|---|---|",
        "| **1** | **~CS** | **K1** |",
        "| 2 | NC（空脚） | F6（本工程不接） |",
        "| **3** | **MISO** | **J2** |",
        "| **4** | **SCLK** | **G6** |",
        "| 5 | GND | — |",
        "| 6 | VCC 3.3 V | — |",
        "",
    ],
    "JD (蜂鸣器)": [
        "**模块引脚 ↔ 信号**（JXADC 的 8 根信号在芯片里是 `XA_N/XA_P[1..4]`，bank 15）：",
        "",
        "| 板口脚 | FPGA 引脚 | 用途 |",
        "|---|---|---|",
        "| **1** | **A14** | `BUZZ` 蜂鸣器信号 |",
        "| 2 | A13 | 留空 |",
        "| 3 | A16 | 留空 |",
        "| 4 | A15 | 留空 |",
        "| 7 / 8 / 9 / 10 | B17 / B16 / A18 / B18 | 留空 |",
        "| 5 / 11 | GND | — |",
        "| 6 / 12 | VCC 3.3 V | — |",
        "",
        "> 自家模块如果信号不在 1 脚，改 xdc 里 `BUZZ` 那一行的 `PACKAGE_PIN` 即可，重新跑本脚本。",
        "> 接前用万用表/丝印确认 1 脚，插反会把信号对到 GND（不烧，但不响）。",
        "",
    ],
}

def classify(port):
    if port in ("CLK100MHZ", "CPU_RESETN"):
        return "系统"
    if port.startswith("SW["):
        return "拨码开关"
    if port.startswith("BTN["):
        return "按键"
    if port.startswith("LED["):
        return "LED"
    if port.startswith("SEG[") or port.startswith("AN["):
        return "数码管"
    if port.startswith("OLED_"):
        return "JA (OLED)"
    if port.startswith("HYGRO_"):
        return "JB (HYGRO)"
    if port.startswith("ALS_"):
        return "JC (ALS)"
    if port == "BUZZ":
        return "JD (蜂鸣器)"
    if port.startswith("VGA_"):
        return "VGA"
    if port.startswith("UART_"):
        return "串口"
    return None


def parse_xdc(path):
    pat = re.compile(r"PACKAGE_PIN\s+(\S+)\s+IOSTANDARD\s+(\S+)\s*\}\s*\[get_ports\s*\{\s*([^}]+?)\s*\}\]")
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.lstrip().startswith("#"):
                continue
            m = pat.search(line)
            if m:
                rows.append((m.group(3).strip(), m.group(1), m.group(2)))
    return rows


def split_index(port):
    m = re.match(r"^(.*)\[(\d+)\]$", port)
    if m:
        return m.group(1), int(m.group(2))
    return port, None


def add_table(lines, items, ncol=2):
    """items: [(label, pin)]，按 ncol 列并排排版。"""
    per = (len(items) + ncol - 1) // ncol
    header = []
    for _ in range(ncol):
        header += ["信号", "FPGA 引脚"]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "---|" * len(header))
    for r in range(per):
        cells = []
        for c in range(ncol):
            k = c * per + r
            if k < len(items):
                cells += [items[k][0], items[k][1]]
            else:
                cells += ["", ""]
        lines.append("| " + " | ".join(cells) + " |")


def main():
    rows = parse_xdc(XDC)
    if not rows:
        raise SystemExit("xdc 里没解析到引脚，检查正则")

    buckets = OrderedDict((k, []) for k in GROUPS)
    unknown = []
    for port, pin, std in rows:
        g = classify(port)
        if g is None:
            unknown.append((port, pin, std))
            continue
        buckets[g].append((port, pin, std))

    L = []
    L.append("# 引脚分配表（Nexys A7-100T / XC7A100T-1CSG324C）")
    L.append("")
    L.append("> **本文件由 `tools/gen_pin_doc.py` 从 `xdc/sys_pins.xdc` 自动生成，不要手改。**")
    L.append("> 引脚唯一事实来源是 xdc；要改引脚，改 xdc 后重新跑一次脚本。")
    L.append("> 最后生成：2026-11-25　版本：v2.0（结构化重排 + 自动生成）")
    L.append("")
    L.append("| 版本 | 日期 | 变更 |")
    L.append("|---|---|---|")
    L.append("| v1.0 | 2026-11-25 | 初版手写引脚表 |")
    L.append("| v1.1 | 2026-11-25 | 补 Pmod 接线说明、订正 HYGRO/ALS 引脚 |")
    L.append("| v2.0 | 2026-11-25 | 改为从 xdc 自动生成；修掉编号重复、JD 归位 |")
    L.append("")
    L.append("---")
    L.append("")

    for key, (title, note) in GROUPS.items():
        items = buckets.get(key, [])
        if not items:
            continue
        L.append(f"## {title}")
        L.append("")
        if note:
            L.append(note)
            L.append("")

        # 向量端口（如 LED[15:0]）按名称分表、按位排序；标量端口合并成一张表
        vec_names = OrderedDict()
        scalars = []
        for (port, pin, std) in items:
            name, idx = split_index(port)
            if idx is None:
                scalars.append((port, pin))
            else:
                vec_names.setdefault(name, []).append((idx, pin))

        lens = {len(v) for v in vec_names.values()}
        if 2 <= len(vec_names) <= 3 and len(lens) == 1 and list(lens)[0] <= 4:
            # 同位宽的 2~3 组向量（如 VGA 的 R/G/B 各 4 位）并排成一张表
            names = list(vec_names.keys())
            n = list(lens)[0]
            hdr = ["信号", "FPGA 引脚"] * len(names)
            L.append("| " + " | ".join(hdr) + " |")
            L.append("|" + "---|" * len(hdr))
            for i in range(n):
                cells = []
                for nm in names:
                    lst = sorted(vec_names[nm], key=lambda t: t[0])
                    cells += [f"`{nm}[{lst[i][0]}]`", f"**{lst[i][1]}**"]
                L.append("| " + " | ".join(cells) + " |")
            L.append("")
        else:
            for name, lst in vec_names.items():
                lst.sort(key=lambda t: t[0])
                cells = [(f"`{name}[{idx}]`", f"**{pin}**") for idx, pin in lst]
                add_table(L, cells, ncol=2 if len(cells) > 8 else 1)
                L.append("")
        if scalars:
            cells = [(f"`{port}`", f"**{pin}**") for port, pin in scalars]
            add_table(L, cells, ncol=2 if len(cells) > 6 else 1)
            L.append("")

        bad = [(port, std) for (port, _pin, std) in items if std != "LVCMOS33"]
        if bad:
            L.append("> 电平标准不是 3.3 V 的信号：" +
                     "、".join(f"`{port}` = {std}" for port, std in bad) +
                     "（在 1.8 V bank，写成 LVCMOS33 会报 DRC 错误）。")
            L.append("")
        if key in EXTRA:
            L.extend(EXTRA[key])

    if unknown:
        L.append("## 未归类的端口（脚本没认出来，检查 classify()）")
        L.append("")
        for p, pin, std in unknown:
            L.append(f"- `{p}` → {pin} ({std})")
        L.append("")

    L.append("---")
    L.append("")
    L.append("## 十二、Pmod 接线说明（给成员B）")
    L.append("")
    L.append("**不需要额外买线**：Pmod HYGRO 和 Pmod ALS 出厂各带一根 **6 针 Pmod 排线**，")
    L.append("一头插模块、一头插板子 JB / JC 口（12 针排针的 **1~6 脚**，也就是上排）。")
    L.append("")
    L.append("| 模块 | 实际用到的线 | 说明 |")
    L.append("|---|---|---|")
    L.append("| Pmod HYGRO | **4 根**：SCL、SDA、GND、VCC | I2C，pin1/pin2 是 NC，模块自带 SCL/SDA 上拉 |")
    L.append("| Pmod ALS | **5 根**：~CS、MISO、SCLK、GND、VCC | SPI，pin2 是 NC |")
    L.append("")
    L.append("两个模块都由板子 Pmod 口直接供 **3.3 V**，不需要外接电源。")
    L.append("")
    L.append("**用杜邦线代替时的注意事项**：")
    L.append("")
    L.append("- 线尽量短（≤15 cm）：I2C 100 kHz、SPI 1 MHz 在 15 cm 内都稳；")
    L.append("- **VCC / GND 千万别接反**（会烧模块），接前用万用表量板子 Pmod 口第 6 脚是不是 3.3 V；")
    L.append("- 只能接 **3.3 V**：Nexys A7 的 Pmod 口没有 5 V；")
    L.append("- **断电插拔**。")
    L.append("")
    L.append("**接线后自检顺序**：")
    L.append("")
    L.append("1. 量模块 VCC-GND = 3.3 V，不是就别往下走；")
    L.append("2. 量 HYGRO 的 SCL 静态为高（I2C 空闲为高），高说明上拉正常；")
    L.append("3. 上板后看串口 `S=`：`03` 两路正常，`01`/`02` 另一路通信失败。")
    L.append("")
    L.append("## 十三、引脚变更流程")
    L.append("")
    L.append("1. 只改 `xdc/sys_pins.xdc`，**不改代码里的端口名**；")
    L.append("2. 改完重新跑一次 `tools/gen_pin_doc.py`，让本文件同步；")
    L.append("3. 由组长跑一次 `scripts/build_bitstream.bat`，确认 WNS > 0 且 DRC 0 error；")
    L.append("4. 涉及新模块的引脚，同时更新 `docs/接口协议.md`。")
    L.append("")
    L.append("## 十四、板载其他资源（本工程未使用，留档备查）")
    L.append("")
    L.append("| 资源 | 说明 |")
    L.append("|---|---|")
    L.append("| 板载音频口 `AUD_PWM` / `AUD_SD` | A11 / D12；蜂鸣器已改接 Pmod JD，这两个空着 |")
    L.append("| 以太网 PHY | 10/100 MII，`eth_*` |")
    L.append("| USB HID Host / microSD / QSPI Flash | S25FL128S 16 MiB（本机烧不进去） |")
    L.append("| 板载温度传感器 | ADT7420（I2C，与 Pmod 无关） |")
    L.append("| 完整官方引脚模板 | `v2_oled_time_display/constr/Nexys-A7-100T-Master-full.xdc` |")
    L.append("")

    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))
    print(f"生成 {OUT}，共 {len(rows)} 个引脚")


if __name__ == "__main__":
    main()
