"""Prepare the two FAT32 directories or export the FPGA's preallocated log to CSV."""
import argparse
import binascii
import csv
from pathlib import Path
import shutil
import struct
import sys

SECTOR = 512
EMPTY = bytes(SECTOR)
FIELDS = struct.Struct("<IhHHBBBBH")
PROJECT = Path(__file__).resolve().parents[1]


def check_bmp(path):
    with path.open("rb") as f:
        head = f.read(54)
    if len(head) < 54 or head[:2] != b"BM":
        raise ValueError("Expected a Windows BMP file.")
    file_size = struct.unpack_from("<I", head, 2)[0]
    offset, dib, width, height, planes, bpp, compression = struct.unpack_from("<IIiiHHI", head, 10)
    if (width, abs(height), planes, bpp, compression) != (320, 240, 1, 24, 0) or dib < 40:
        raise ValueError("Image must be 320 x 240, 24-bit BGR, uncompressed Windows BMP.")
    if offset < 14 + dib or not offset + 320*240*3 <= file_size <= path.stat().st_size:
        raise ValueError("Incomplete BMP or inconsistent BMP size/offset.")


def prepare(root, image, mib):
    if not root.is_dir():
        raise ValueError("Destination must be an existing mounted FAT32 directory.")
    if not 1 <= mib <= 4095:
        raise ValueError("Choose 1..4095 MiB (FAT32 file limit).")
    image_target = root / "IMAGES" / "BG.BMP"
    logfile = root / "LOGS" / "ENVLOG.BIN"
    if image is None:
        image = image_target if image_target.exists() else PROJECT / "tf_card" / "IMAGES" / "BG.BMP"
    check_bmp(image)
    if image_target.exists() and image_target.resolve() != image.resolve():
        if image_target.read_bytes() != image.read_bytes():
            raise ValueError("IMAGES/BG.BMP already exists. Select the existing image or replace it manually.")
    if logfile.exists() and (logfile.stat().st_size < SECTOR or logfile.stat().st_size % SECTOR):
        raise ValueError("Existing LOGS/ENVLOG.BIN has an invalid length. It was preserved.")
    image_target.parent.mkdir(exist_ok=True)
    logfile.parent.mkdir(exist_ok=True)
    if not image_target.exists():
        with image.open("rb") as src, image_target.open("xb") as dst:
            shutil.copyfileobj(src, dst)
    if not logfile.exists():
        zeros = bytes(1024 * 1024)
        new_file = logfile.open("xb")
        try:
            with new_file as f:
                for _ in range(mib):
                    f.write(zeros)
        except (OSError, KeyboardInterrupt):
            # Only remove the incomplete file created by this call.
            if logfile.exists() and logfile.stat().st_size < len(zeros)*mib:
                logfile.unlink()
            raise
    print(f"{image_target}   {logfile}   {logfile.stat().st_size // SECTOR} record slots")


def export_file(source, target):
    size = source.stat().st_size
    if not size or size % SECTOR:
        raise ValueError("Input size must be a nonzero multiple of 512 bytes.")
    valid = damaged = empty = 0
    with source.open("rb") as f, target.open("x", encoding="utf-8-sig", newline="") as dst:
        rows = csv.writer(dst)
        rows.writerow(("slot", "uptime_s", "temperature_C", "humidity_pct", "lux", "sensor_status",
                       "alarm_level", "alarm_source", "data_ok", "light_adc"))
        for slot in range(size // SECTOR):
            sec = f.read(SECTOR)
            if sec == EMPTY:
                empty += 1
                continue
            crc = binascii.crc_hqx(sec[:20], 0xffff)
            if sec[:4] != b"ENV1" or sec[510:] != b"\xa5\x5a" or crc != int.from_bytes(sec[508:510], "little"):
                damaged += 1
                continue
            s, t, h, lux, status, level, src, ok, adc = FIELDS.unpack_from(sec, 4)
            rows.writerow((slot, s, f"{t / 10:.1f}", f"{h / 10:.1f}", lux, f"0x{status:02X}",
                           level, f"0x{src:02X}", ok, adc))
            valid += 1
    print(f"{target}: {valid} records, {empty} empty slots, {damaged} damaged slots skipped")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    cmds = parser.add_subparsers(dest="cmd", required=True)
    make = cmds.add_parser("prepare", help="Install sample image and reserve an empty log if absent")
    make.add_argument("root", type=Path)
    make.add_argument("--bmp", type=Path)
    make.add_argument("--mib", type=int, default=16)
    out = cmds.add_parser("export", help="Export a log into a new CSV")
    out.add_argument("input", type=Path)
    out.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.cmd == "prepare":
        prepare(args.root, args.bmp, args.mib)
    else:
        export_file(args.input, args.output)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as exc:
        sys.exit(str(exc))
