#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pc_monitor.py —— 电脑端串口显示器（配合 FPGA 的 report_tx 上报）

用法：
    pip install pyserial
    python pc_monitor.py                 # 自动扫描串口
    python pc_monitor.py -p COM5         # 指定串口
    python pc_monitor.py -p COM5 -l run.csv

协议（FPGA 每 100 ms 发一行，固定 37 字节）：
    $ENV,T=+25.3,H=55.0,L=0320,A=2,S=03

注意：本脚本在 2026-11-25 写好后**没有在接板子的情况下实测**（当时板子没插），
      逻辑很简单，如果报错请把报错发我。
"""

import argparse
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("缺少 pyserial，请先执行：  pip install pyserial")


def pick_port():
    """没指定 -p 时，列出所有串口让人选。"""
    ports = list(list_ports.comports())
    if not ports:
        sys.exit("没找到串口。检查板子是否插在 PROG/UART 口、驱动是否装好。")
    print("可用串口：")
    for i, p in enumerate(ports):
        print(f"  [{i}] {p.device}  {p.description}")
    if len(ports) == 1:
        return ports[0].device
    idx = input("选择串口序号：").strip() or "0"
    return ports[int(idx)].device


def parse_line(line):
    """把 '$ENV,T=+25.3,H=55.0,L=0320,A=2,S=03' 解析成字典。"""
    if not line.startswith("$ENV,"):
        return None
    out = {}
    for part in line[len("$ENV,"):].split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k] = v
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", help="串口名，如 COM5；不填则自动扫描")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("-l", "--log", help="把收到的行同时写入这个 CSV/text 文件")
    args = ap.parse_args()

    port = args.port or pick_port()
    print(f"打开 {port} @ {args.baud} 8N1，Ctrl+C 退出\n")

    logf = open(args.log, "a", encoding="utf-8") if args.log else None
    if logf:
        logf.write("# time,temp_C,humi_pct,lux,alarm,status\n")

    try:
        with serial.Serial(port, args.baud, timeout=1) as ser:
            while True:
                raw = ser.readline()
                if not raw:
                    continue
                line = raw.decode("ascii", errors="replace").strip()
                d = parse_line(line)
                if not d:
                    print(f"[原始] {line}")
                    continue
                ts = time.strftime("%H:%M:%S")
                print(f"{ts}  温度 {d.get('T', '?')}℃   湿度 {d.get('H', '?')}%   "
                      f"光照 {d.get('L', '?')} lux   报警等级 {d.get('A', '?')}   "
                      f"状态 0x{d.get('S', '??')}")
                if logf:
                    logf.write(f"{ts},{d.get('T')},{d.get('H')},{d.get('L')},"
                               f"{d.get('A')},{d.get('S')}\n")
                    logf.flush()
    except KeyboardInterrupt:
        print("\n已退出。")
    except serial.SerialException as e:
        sys.exit(f"串口打开失败：{e}\n  串口可能被其他软件占用（串口助手/Keil 等），先关掉。")
    finally:
        if logf:
            logf.close()


if __name__ == "__main__":
    main()
