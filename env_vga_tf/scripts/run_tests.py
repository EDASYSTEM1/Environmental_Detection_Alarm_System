"""Run the board-level and storage/display testbenches with Icarus Verilog."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    "tb_env_top": "SYS TEST PASSED",
    "tb_sd_spi_block": "SD SPI TEST PASSED",
    "tb_fat32_store": "FAT32_STORE TEST PASSED",
    "tb_bmp_loader": "PASS bmp_loader",
    "tb_env_vga": "PASS env_vga",
    "tb_tf_integration": "TF INTEGRATION TEST PASSED",
    "tb_dashboard_pipeline": "DASHBOARD_PIPELINE TEST PASSED",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", type=Path, help="Directory containing iverilog and vvp")
    parser.add_argument("--libdir", type=Path, help="Icarus backend/VPI directory for a portable install")
    args = parser.parse_args()
    suffix = ".exe" if os.name == "nt" else ""
    iv, vvp = ((str((args.bin / (s+suffix)).resolve()) if args.bin else shutil.which(s))
               for s in ("iverilog","vvp"))
    if not iv or not vvp:
        parser.error("Install Icarus Verilog or specify --bin.")
    extra_iv = ["-B", str(args.libdir.resolve())] if args.libdir else []
    extra_vvp = ["-M", str(args.libdir.resolve())] if args.libdir else []
    rtl = [str(p.relative_to(ROOT)) for p in sorted((ROOT/"rtl").rglob("*.v"))]
    with tempfile.TemporaryDirectory(prefix="vga-tf-") as work:
        for top, expected in CASES.items():
            out = Path(work) / (top+".vvp")
            sim = ["sim/"+top+".v"] + (["sim/hdc1080_model.v"] if top=="tb_env_top" else [])
            subprocess.run([iv, *extra_iv, "-g2012", "-s", top, "-o", str(out), *rtl, *sim],
                           cwd=ROOT, check=True)
            cmd = [vvp, *extra_vvp, str(out)]
            result = subprocess.run(cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    encoding="utf-8", errors="replace", timeout=180)
            if result.returncode or expected not in result.stdout or "[FAIL]" in result.stdout:
                raise SystemExit(f"{top} failed\n{result.stdout}")
            print(top, "PASS", flush=True)
    print(f"{len(CASES)} / {len(CASES)} passed")


if __name__=="__main__":
    main()
