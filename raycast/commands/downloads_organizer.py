#!/Users/tianli/Dev/tools/mactools/.venv/bin/python3
# @raycast.schemaVersion 1
# @raycast.title Organize Downloads
# @raycast.mode fullOutput
# @raycast.icon 📂
# @raycast.packageName File Utils
# @raycast.description 按扩展名分类 Downloads 到子目录
"""Downloads 自动整理工具 - 按文件扩展名分类到子目录。

用法:
    python3 downloads_organizer.py              # 扫描 Downloads 根目录
    python3 downloads_organizer.py --dry-run    # 预览模式，只打印不移动
    python3 downloads_organizer.py --scan-archive  # 同时扫描 归档/其他文档
    python3 downloads_organizer.py --dry-run --scan-archive  # 预览+归档
"""

import argparse
import logging
import os
import shutil
import sys
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).parent
CONFIG_FILE = SCRIPT_DIR / "downloads_organizer.yaml"


def setup_logging(log_file: str) -> logging.Logger:
    """配置日志：同时输出到文件和 stdout。"""
    log_path = Path(log_file).expanduser()
    log_path.parent.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger("downloads_organizer")
    logger.setLevel(logging.INFO)

    fmt = logging.Formatter("%(asctime)s  %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

    fh = logging.FileHandler(log_path, encoding="utf-8")
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    return logger


def load_config() -> dict:
    """读取 YAML 配置文件。"""
    with open(CONFIG_FILE, encoding="utf-8") as f:
        return yaml.safe_load(f)


def build_ext_map(categories: dict) -> dict[str, str]:
    """构建扩展名 -> 分类名的映射表。

    优先匹配 .tar.gz 等复合扩展名。
    """
    ext_map = {}
    for category, extensions in categories.items():
        for ext in extensions:
            ext_map[ext.lower()] = category
    return ext_map


def get_file_ext(filename: str) -> str:
    """获取文件扩展名，支持 .tar.gz 等复合扩展名。"""
    lower = filename.lower()
    if lower.endswith(".tar.gz"):
        return ".tar.gz"
    if lower.endswith(".tar.bz2"):
        return ".tar.bz2"
    if lower.endswith(".tar.xz"):
        return ".tar.xz"
    _, ext = os.path.splitext(lower)
    return ext


def classify(filename: str, ext_map: dict, fallback: str) -> str:
    """根据扩展名返回目标分类名。"""
    ext = get_file_ext(filename)
    return ext_map.get(ext, fallback)


def should_ignore(filename: str, ignore_prefixes: list[str]) -> bool:
    """判断是否应忽略该文件。"""
    return any(filename.startswith(prefix) for prefix in ignore_prefixes)


def safe_move(src: Path, dest_dir: Path, logger: logging.Logger, dry_run: bool) -> bool:
    """移动文件到目标目录，文件名冲突时自动加序号。

    返回 True 表示移动成功（或 dry-run 下会移动）。
    """
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / src.name

    if dest.exists():
        stem = src.stem
        ext = src.suffix
        # 处理 .tar.gz 的情况
        if src.name.lower().endswith(".tar.gz"):
            stem = src.name[: -len(".tar.gz")]
            ext = ".tar.gz"
        counter = 1
        while dest.exists():
            dest = dest_dir / f"{stem} ({counter}){ext}"
            counter += 1

    if dry_run:
        logger.info("[预览] %s -> %s", src, dest)
        return True

    try:
        shutil.move(str(src), str(dest))
        logger.info("[移动] %s -> %s", src, dest)
        return True
    except Exception as e:
        logger.error("[失败] %s -> %s: %s", src, dest, e)
        return False


def scan_directory(
    scan_dir: Path,
    target_dir: Path,
    ext_map: dict,
    fallback: str,
    ignore_prefixes: list[str],
    logger: logging.Logger,
    dry_run: bool,
) -> tuple[int, int]:
    """扫描单个目录，返回 (处理数, 跳过数)。"""
    moved = 0
    skipped = 0

    if not scan_dir.exists():
        logger.warning("目录不存在，跳过: %s", scan_dir)
        return moved, skipped

    for item in sorted(scan_dir.iterdir()):
        if not item.is_file():
            continue
        if should_ignore(item.name, ignore_prefixes):
            skipped += 1
            continue

        category = classify(item.name, ext_map, fallback)
        dest_dir = target_dir / category

        # 如果文件已经在目标目录中，跳过
        if item.parent == dest_dir:
            skipped += 1
            continue

        if safe_move(item, dest_dir, logger, dry_run):
            moved += 1

    return moved, skipped


def main():
    parser = argparse.ArgumentParser(description="Downloads 自动整理工具")
    parser.add_argument("--dry-run", action="store_true", help="预览模式，只打印不移动")
    parser.add_argument("--scan-archive", action="store_true", help="同时扫描 归档/其他文档")
    args = parser.parse_args()

    config = load_config()
    logger = setup_logging(config["log_file"])

    target_dir = Path(config["target_dir"]).expanduser()
    ext_map = build_ext_map(config["categories"])
    fallback = config["fallback"]
    ignore_prefixes = config["ignore_prefixes"]

    scan_dirs = [Path(d).expanduser() for d in config["scan_dirs"]]
    if args.scan_archive:
        scan_dirs += [Path(d).expanduser() for d in config.get("archive_dirs", [])]

    if args.dry_run:
        logger.info("=== 预览模式 ===")

    total_moved = 0
    total_skipped = 0

    for scan_dir in scan_dirs:
        logger.info("扫描: %s", scan_dir)
        moved, skipped = scan_directory(scan_dir, target_dir, ext_map, fallback, ignore_prefixes, logger, args.dry_run)
        total_moved += moved
        total_skipped += skipped

    mode = "预览" if args.dry_run else "整理"
    logger.info("=== %s完成: 处理 %d 个文件, 跳过 %d 个 ===", mode, total_moved, total_skipped)


if __name__ == "__main__":
    main()
