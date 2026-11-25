# -*- coding: utf-8 -*-
"""把 docs/接口协议.md 转成 Word（再转 PDF 用），保证表格/代码块/中文正常。"""
import re
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

import os
import sys as _sys
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MD = _sys.argv[1] if len(_sys.argv) > 1 else os.path.join(_ROOT, "docs", "接口协议.md")
OUT = _sys.argv[2] if len(_sys.argv) > 2 else os.path.join(_ROOT, "docs", "接口协议_导出.docx")

CN = "微软雅黑"
MONO = "Consolas"


def style_run(run, size=10.5, bold=False, mono=False, color=None):
    f = MONO if mono else CN
    run.font.size = Pt(size)
    run.bold = bold
    if color:
        run.font.color.rgb = color
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn("w:rFonts"))
    if rFonts is None:
        rFonts = OxmlElement("w:rFonts")
        rPr.append(rFonts)
    rFonts.set(qn("w:ascii"), f)
    rFonts.set(qn("w:hAnsi"), f)
    rFonts.set(qn("w:eastAsia"), CN)


def shade(p, fill="F4F4F4"):
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    pPr.append(shd)


def add_inline(p, text, size=10.5, bold=False):
    for tok in re.split(r"(\*\*.*?\*\*|`[^`]*`)", text):
        if not tok:
            continue
        if tok.startswith("**") and tok.endswith("**"):
            style_run(p.add_run(tok[2:-2]), size=size, bold=True)
        elif tok.startswith("`") and tok.endswith("`"):
            style_run(p.add_run(tok[1:-1]), size=size - 0.5, mono=True, bold=bold)
        else:
            style_run(p.add_run(tok), size=size, bold=bold)


def add_table(doc, rows):
    ncol = max(len(r) for r in rows)
    t = doc.add_table(rows=0, cols=ncol)
    t.style = "Table Grid"
    for i, r in enumerate(rows):
        row = t.add_row()
        trPr = row._tr.get_or_add_trPr()
        cant = OxmlElement("w:cantSplit")          # 行内不跨页断开
        trPr.append(cant)
        if i == 0:
            hdr = OxmlElement("w:tblHeader")       # 表头在每页重复
            trPr.append(hdr)
        for j in range(ncol):
            txt = r[j] if j < len(r) else ""
            cell = row.cells[j]
            cell.text = ""
            p = cell.paragraphs[0]
            p.paragraph_format.space_before = Pt(1)
            p.paragraph_format.space_after = Pt(1)
            add_inline(p, txt.strip(), size=9, bold=(i == 0))


doc = Document()
sec = doc.sections[0]
sec.page_height, sec.page_width = Cm(29.7), Cm(21.0)   # A4
sec.left_margin = sec.right_margin = Cm(2.0)
sec.top_margin = sec.bottom_margin = Cm(1.8)

lines = open(MD, encoding="utf-8").read().splitlines()
i = 0
in_code = False
code_buf = []
table_buf = []


def flush_table():
    global table_buf
    if table_buf:
        rows = [r for r in table_buf if not re.match(r"^\|[\s:|-]+\|$", r)]
        parsed = [[c for c in r.strip().strip("|").split("|")] for r in rows]
        add_table(doc, parsed)
        doc.add_paragraph()
    table_buf = []


while i < len(lines):
    ln = lines[i]
    s = ln.rstrip()

    # 代码块
    if s.startswith("```"):
        if in_code:
            p = doc.add_paragraph()
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(6)
            p.paragraph_format.left_indent = Cm(0.2)
            shade(p)
            for k, cl in enumerate(code_buf):
                r = p.add_run(cl.replace("\t", "    "))
                style_run(r, size=8.5, mono=True)
                if k != len(code_buf) - 1:
                    r.add_break()
            code_buf = []
            in_code = False
        else:
            flush_table()
            in_code = True
        i += 1
        continue

    if in_code:
        code_buf.append(s)
        i += 1
        continue

    # 表格
    if s.startswith("|"):
        table_buf.append(s)
        i += 1
        continue
    else:
        flush_table()

    # 空行
    if not s.strip():
        i += 1
        continue

    # 分隔线
    if re.match(r"^-{3,}$", s.strip()):
        i += 1
        continue

    # 标题
    m = re.match(r"^(#{1,4})\s+(.*)$", s)
    if m:
        level, txt = len(m.group(1)), m.group(2)
        if level == 1:
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            style_run(p.add_run(txt.replace("`", "").replace("**", "")), size=20, bold=True)
        else:
            p = doc.add_paragraph()
            p.paragraph_format.space_before = Pt(10 if level == 2 else 6)
            p.paragraph_format.space_after = Pt(4)
            style_run(p.add_run(txt.replace("`", "").replace("**", "")), size=15 if level == 2 else 12, bold=True)
        i += 1
        continue

    # 引用
    if s.startswith(">"):
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.4)
        add_inline(p, s.lstrip("> ").strip(), size=9.5)
        i += 1
        continue

    # 列表
    m = re.match(r"^(\s*)[-*]\s+(.*)$", s)
    if m:
        p = doc.add_paragraph(style="List Bullet")
        add_inline(p, m.group(2))
        i += 1
        continue

    m = re.match(r"^(\s*)(\d+)\.\s+(.*)$", s)
    if m:
        p = doc.add_paragraph(style="List Number")
        add_inline(p, m.group(3))
        i += 1
        continue

    # 普通段落
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    add_inline(p, s.strip())
    i += 1

flush_table()
doc.save(OUT)
print("saved", OUT)
