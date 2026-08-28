#!/usr/bin/env python3
# @raycast.schemaVersion 1
# @raycast.title Merge Selected PDFs
# @raycast.mode fullOutput
# @raycast.icon 📎
# @raycast.packageName Documents
# @raycast.description 合并 Finder 里选中的多个 PDF（默认按文件名自然排序），输出到同一目录
# @raycast.argument1 { "type": "dropdown", "placeholder": "顺序", "optional": true, "data": [{"title": "按文件名排序（默认）", "value": "name"}, {"title": "按 Finder 选中顺序", "value": "finder"}] }
# @raycast.argument2 { "type": "text", "placeholder": "输出文件名（可留空自动命名）", "optional": true }
"""Finder 选中 → 合并 PDF。

薄壳：排序与命名在这里，合并本体调总部 SSOT
`~/Dev/tools/doctools/scripts/document/pdf_cli.py merge`（铁律 #5 不造轮子）。

设计取舍
- **默认按文件名自然排序**：Finder 的 `selection` 顺序不等于视觉顺序、也不等于点击顺序，
  拿它当"我选的顺序"会静默拼错页序。要按选中顺序时显式选 dropdown 的第二项。
- **绝不覆盖**：同名输出自动加 `-2` `-3`。
- **只读输入**：源文件一个字节不动，合并结果是新文件。
"""
import sys, os; sys.path.insert(0, os.path.expanduser("~/Dev/tools/dev/lib"))
try:
    import log_usage  # noqa: F401  (import 即埋点)
except Exception:
    pass

import re
import subprocess
from pathlib import Path

PY = "/opt/homebrew/bin/python3"   # pypdf 装在这，别用 ~/Dev/.venv
PDF_CLI = Path.home() / "Dev/tools/doctools/scripts/document/pdf_cli.py"


def finder_selection() -> list[Path]:
    osa = '''
    tell application "Finder"
        set out to ""
        set sel to selection
        repeat with x in sel
            set out to out & (POSIX path of (x as alias)) & linefeed
        end repeat
        return out
    end tell
    '''
    r = subprocess.run(["osascript", "-e", osa], capture_output=True, text=True)
    if r.returncode != 0:
        return []
    return [Path(p) for p in r.stdout.splitlines() if p.strip()]


def natural_key(p: Path):
    """01-1-2 排在 01-1-10 前面（纯字典序会反）。"""
    return [int(s) if s.isdigit() else s.lower() for s in re.split(r"(\d+)", p.name)]


def unique_out(path: Path) -> Path:
    if not path.exists():
        return path
    stem, suf, parent = path.stem, path.suffix, path.parent
    n = 2
    while (parent / f"{stem}-{n}{suf}").exists():
        n += 1
    return parent / f"{stem}-{n}{suf}"


def page_count(p: Path) -> str:
    try:
        import pypdf
        return f"{len(pypdf.PdfReader(str(p)).pages)}p"
    except Exception:
        return "?p"


def main() -> int:
    order = (sys.argv[1] if len(sys.argv) > 1 else "").strip() or "name"
    custom = (sys.argv[2] if len(sys.argv) > 2 else "").strip()

    sel = finder_selection()
    if not sel:
        print("❌ Finder 里没有选中任何东西（或最前面的窗口不是 Finder）")
        return 1

    pdfs = [p for p in sel if p.suffix.lower() == ".pdf" and p.is_file()]
    skipped = [p for p in sel if p not in pdfs]
    if len(pdfs) < 2:
        print(f"❌ 选中的 PDF 不足 2 个（PDF {len(pdfs)} 个，其它 {len(skipped)} 个），没什么可合并的")
        for p in sel:
            print("   ·", p.name)
        return 1

    if order == "name":
        pdfs.sort(key=natural_key)

    outdir = pdfs[0].parent
    if custom:
        name = custom if custom.lower().endswith(".pdf") else custom + ".pdf"
        out = outdir / name
    else:
        out = outdir / f"合并_{pdfs[0].stem}_等{len(pdfs)}份.pdf"
    out = unique_out(out)

    print(f"📎 合并 {len(pdfs)} 份（顺序：{'文件名' if order == 'name' else 'Finder 选中'}）")
    for i, p in enumerate(pdfs, 1):
        print(f"  {i:2d}. {page_count(p):>5}  {p.name}")
    if skipped:
        print(f"  （跳过 {len(skipped)} 个非 PDF：{', '.join(x.name for x in skipped[:5])}）")

    r = subprocess.run([PY, str(PDF_CLI), "merge", *[str(p) for p in pdfs], "--out", str(out)],
                       capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        print("\n❌ 合并失败")
        print((r.stderr or r.stdout).strip()[:2000])
        return 1

    size = out.stat().st_size / 1e6
    print(f"\n✅ {out.name}")
    print(f"   {page_count(out)} · {size:.1f} MB · {outdir}")
    subprocess.run(["open", "-R", str(out)])
    return 0


if __name__ == "__main__":
    sys.exit(main())
