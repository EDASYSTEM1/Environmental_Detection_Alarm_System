# -*- coding: utf-8 -*-
"""
vcd2html.py —— 把 VCD 波形转成一个「能交互看」的 HTML（滚轮缩放 / 拖拽平移 / 悬停读值）

为什么不用 GTKWave：校园网/SourceForge 下不下来，Vivado 又没 xsim 授权。
浏览器人人都有，所以直接把波形做成一个自包含 HTML，双击就能看。

用法：
    python tools\\wave\\vcd2html.py wave_uart.vcd uart.html "UART 8N1 发送时序"
"""
import json
import os
import re
import sys

HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>__TITLE__</title>
<style>
  html,body{margin:0;padding:0;background:#0f172a;color:#e2e8f0;
            font-family:"Microsoft YaHei",Consolas,monospace}
  #bar{padding:8px 12px;background:#1e293b;display:flex;gap:10px;align-items:center;
       position:sticky;top:0;z-index:9;box-shadow:0 2px 8px #0006}
  #bar b{font-size:15px}
  button{background:#334155;color:#e2e8f0;border:0;padding:5px 12px;border-radius:4px;
         cursor:pointer;font-size:13px}
  button:hover{background:#475569}
  #hint{margin-left:auto;color:#94a3b8;font-size:12px}
  #wrap{position:relative}
  canvas{display:block;cursor:crosshair}
  #tip{position:fixed;background:#1e293b;border:1px solid #475569;padding:4px 8px;
       border-radius:4px;font-size:12px;pointer-events:none;display:none;z-index:20}
</style>
</head>
<body>
<div id="bar">
  <b>__TITLE__</b>
  <button onclick="fit()">适应全宽 (F)</button>
  <button onclick="zoom(0.7)">放大 +</button>
  <button onclick="zoom(1.4)">缩小 -</button>
  <span id="win" style="color:#93c5fd;font-size:13px"></span>
  <span id="hint">滚轮缩放 · 按住左键拖动平移 · 鼠标悬停读时间/值</span>
</div>
<div id="wrap"><canvas id="c"></canvas></div>
<div id="tip"></div>
<script>
const D = __DATA__;
const cv = document.getElementById('c');
const ctx = cv.getContext('2d');
const LAB = 200, ROW = 26, HEAD = 34, BOT = 26;
let t0 = 0, t1 = D.tmax || 1;
let hover = null, drag = null;

function resize(){
  cv.width = window.innerWidth;
  cv.height = HEAD + D.signals.length * ROW + BOT;
  cv.style.width = cv.width + 'px';
  cv.style.height = cv.height + 'px';
  draw();
}
function X(t){ return LAB + (t - t0) / (t1 - t0 || 1) * (cv.width - LAB - 16); }
function T(px){ return t0 + (px - LAB) / (cv.width - LAB - 16) * (t1 - t0 || 1); }

function changesIn(sig){
  const out = [];
  let prev = sig.changes.length ? sig.changes[0][1] : 'x';
  for (let i = 0; i < sig.changes.length; i++){
    const [t, v] = sig.changes[i];
    if (t <= t1) out.push([t, v]);
    if (t > t1) break;
  }
  return out;
}

function drawSignal(sig, y0, i){
  const yHi = y0 + 6, yLo = y0 + ROW - 8, yMid = (yHi + yLo) / 2;
  // 名称
  ctx.fillStyle = '#cbd5e1';
  ctx.font = '13px Consolas, monospace';
  ctx.textAlign = 'right';
  ctx.fillText(sig.label, LAB - 10, yMid + 4);

  const ch = sig.changes;
  if (!ch.length){ return; }
  let cur = ch[0][1];
  // 起始段
  let px0 = X(Math.max(ch[0][0], t0));
  if (ch[0][0] < t0) px0 = X(t0);

  for (let k = 1; k < ch.length; k++){
    const [t, v] = ch[k];
    const px1 = X(t);
    if (px1 < LAB) { cur = v; continue; }
    if (px0 > cv.width) break;
    paintSeg(sig, cur, px0, Math.min(px1, cv.width), yHi, yLo, yMid);
    // 跳变竖线
    ctx.strokeStyle = '#38bdf8';
    ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(px1, yHi); ctx.lineTo(px1, yLo); ctx.stroke();
    px0 = px1; cur = v;
  }
  paintSeg(sig, cur, px0, cv.width - 16, yHi, yLo, yMid);
}

function paintSeg(sig, val, x0, x1, yHi, yLo, yMid){
  if (x1 <= x0) return;
  if (sig.width === 1){
    const y = (val === '1') ? yHi : (val === '0' ? yLo : yMid);
    ctx.strokeStyle = (val === '1') ? '#22c55e' : (val === '0' ? '#94a3b8' : '#ef4444');
    ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke();
  } else {
    ctx.strokeStyle = '#60a5fa';
    ctx.lineWidth = 1;
    ctx.strokeRect(x0 + 1, yHi + 1, Math.max(x1 - x0 - 2, 1), yLo - yHi - 2);
    if (x1 - x0 > 46){
      let v = 'x';
      try { v = '0x' + parseInt(val || '0', 2).toString(16).toUpperCase(); } catch(e){}
      ctx.fillStyle = '#93c5fd';
      ctx.font = '11px Consolas, monospace';
      ctx.textAlign = 'center';
      ctx.fillText(v, (x0 + x1) / 2, yMid + 4);
    }
  }
}

function niceStep(span){
  const raw = span / 8, p = Math.pow(10, Math.floor(Math.log10(raw))), n = raw / p;
  const m = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
  return m * p;
}

function draw(){
  ctx.fillStyle = '#0f172a';
  ctx.fillRect(0, 0, cv.width, cv.height);

  // 时间刻度
  const step = niceStep(t1 - t0);
  ctx.font = '11px Consolas, monospace';
  ctx.textAlign = 'center';
  for (let t = Math.ceil(t0 / step) * step; t <= t1; t += step){
    const x = X(t);
    ctx.strokeStyle = '#1e293b'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(x, HEAD - 10); ctx.lineTo(x, cv.height - BOT); ctx.stroke();
    ctx.fillStyle = '#64748b';
    ctx.fillText(fmt(t) + ' ns', x, cv.height - 8);
  }

  // 行分隔
  D.signals.forEach((s, i) => {
    const y0 = HEAD + i * ROW;
    ctx.strokeStyle = '#16213a'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(0, y0 + ROW - 0.5); ctx.lineTo(cv.width, y0 + ROW - 0.5); ctx.stroke();
    drawSignal(s, y0, i);
  });

  // 左栏
  ctx.fillStyle = '#0b1120';
  ctx.fillRect(0, 0, LAB - 4, cv.height);
  ctx.fillStyle = '#cbd5e1';
  ctx.font = '13px Consolas, monospace';
  ctx.textAlign = 'right';
  D.signals.forEach((s, i) => {
    const yMid = HEAD + i * ROW + ROW / 2;
    ctx.fillText(s.label, LAB - 10, yMid + 4);
  });

  // 悬停线
  if (hover !== null && hover >= LAB){
    const x = hover;
    ctx.strokeStyle = '#f59e0b'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(x, HEAD - 10); ctx.lineTo(x, cv.height - BOT); ctx.stroke();
  }

  document.getElementById('win').textContent =
    '窗口 ' + fmt(t0) + ' ~ ' + fmt(t1) + ' ns';
}

function fmt(v){
  if (Math.abs(v) >= 1000) return (v / 1000).toFixed(2) + ' µs';
  return v.toFixed(0);
}

function valueAt(sig, t){
  let v = 'x';
  for (const [tt, vv] of sig.changes){ if (tt <= t) v = vv; else break; }
  return v;
}

cv.addEventListener('wheel', e => {
  e.preventDefault();
  const mouseT = T(e.offsetX);
  const k = e.deltaY > 0 ? 1.25 : 0.8;
  t0 = mouseT - (mouseT - t0) * k;
  t1 = mouseT + (t1 - mouseT) * k;
  draw();
}, {passive:false});

cv.addEventListener('mousedown', e => { drag = {x:e.offsetX, t0:t0, t1:t1}; });
window.addEventListener('mouseup', () => { drag = null; });
cv.addEventListener('mousemove', e => {
  if (drag){
    const dt = (drag.x - e.offsetX) / (cv.width - LAB - 16) * (drag.t1 - drag.t0);
    t0 = drag.t0 + dt; t1 = drag.t1 + dt;
  }
  hover = e.offsetX;
  draw();
  const tip = document.getElementById('tip');
  if (e.offsetX > LAB){
    const t = T(e.offsetX);
    let html = '<b>' + fmt(t) + ' ns</b>';
    D.signals.forEach(s => {
      let v = valueAt(s, t);
      if (s.width > 1){ try { v = '0x' + parseInt(v, 2).toString(16).toUpperCase(); } catch(err){} }
      html += '<br>' + s.label + ' = ' + v;
    });
    tip.innerHTML = html;
    tip.style.display = 'block';
    tip.style.left = (e.clientX + 14) + 'px';
    tip.style.top = (e.clientY + 14) + 'px';
  } else { tip.style.display = 'none'; }
});
cv.addEventListener('mouseleave', () => {
  document.getElementById('tip').style.display = 'none'; hover = null; draw();
});

window.addEventListener('keydown', e => { if (e.key === 'f' || e.key === 'F') fit(); });
function fit(){ t0 = 0; t1 = D.tmax || 1; draw(); }
function zoom(k){
  const c = (t0 + t1) / 2, half = (t1 - t0) / 2 * k;
  t0 = c - half; t1 = c + half; draw();
}

window.addEventListener('resize', resize);
resize();
</script>
</body>
</html>
"""


def parse_vcd(path):
    """返回 (signals, tmax)；signals 只取顶层 scope（测试平台的信号），避免几千个内部信号。"""
    scopes = []
    cur_scope = []
    defs = []          # (id, width, name, scope_depth, kind)
    changes = {}
    t = 0
    unit_ns = 1.0

    head = open(path, "r", errors="replace").read(4000).replace("\n", " ")
    m = re.search(r"\$timescale\s+(\d+)\s*(fs|ps|ns|us|ms|s)", head)
    if m:
        mult = {"fs": 1e-6, "ps": 1e-3, "ns": 1.0, "us": 1e3, "ms": 1e6, "s": 1e9}
        unit_ns = float(m.group(1)) * mult[m.group(2)]

    with open(path, "r", errors="replace") as f:
        for line in f:
            s = line.strip()
            if s.startswith("$scope"):
                p = s.split()
                cur_scope.append(p[2] if len(p) > 2 else "?")
            elif s.startswith("$upscope"):
                if cur_scope:
                    cur_scope.pop()
            elif s.startswith("$var"):
                p = s.split()
                defs.append((p[3], int(p[2]), p[4], len(cur_scope)))
            elif s.startswith("#"):
                try:
                    t = int(s[1:])
                except ValueError:
                    pass
            elif s[:1] in "01xzXZ" and len(s) >= 2:
                changes.setdefault(s[1:], []).append((t, s[0]))
            elif s[:1] == "b":
                p = s.split()
                changes.setdefault(p[1], []).append((t, p[0][1:]))

    top = min((d[3] for d in defs), default=1)
    sigs = []
    for vid, width, name, depth in defs:
        if depth != top:
            continue
        ch = changes.get(vid, [])
        if not ch or name.startswith("$"):
            continue
        sigs.append({
            "label": name + ("" if width == 1 else "[%d:0]" % (width - 1)),
            "width": width,
            "changes": [[round(t * unit_ns, 3), v] for t, v in ch],
        })

    tmax = max((c[0] for s in sigs for c in s["changes"]), default=1)
    return sigs, tmax


def main():
    if len(sys.argv) < 3:
        print("用法: python vcd2html.py <in.vcd> <out.html> [标题]")
        sys.exit(1)
    vcd, out = sys.argv[1], sys.argv[2]
    title = sys.argv[3] if len(sys.argv) > 3 else os.path.basename(vcd)

    sigs, tmax = parse_vcd(vcd)
    if not sigs:
        print("没解析到顶层信号，检查 VCD 是否用了 $dumpvars")
        sys.exit(1)

    data = json.dumps({"signals": sigs, "tmax": tmax}, ensure_ascii=False)
    html = HTML.replace("__DATA__", data).replace("__TITLE__", title)
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    print("生成 %s（%d 个信号，%d 个时间点）" % (out, len(sigs), len(sigs[0]["changes"]) if sigs else 0))


if __name__ == "__main__":
    main()
