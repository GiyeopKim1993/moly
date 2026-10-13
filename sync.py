#!/usr/bin/env python3
"""Restore or back up the allow-listed parts of a user's Mac profile."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home().resolve()


def inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def cloud_root(value: str | None) -> Path:
    if value:
        root = Path(value).expanduser().resolve()
    else:
        root = next(
            (candidate.resolve() for candidate in (
                HOME / "Library/CloudStorage/Dropbox/Mac-Profile-Sync",
                HOME / "Dropbox/Mac-Profile-Sync",
            ) if candidate.is_dir()),
            None,
        )
        if root is None:
            raise FileNotFoundError(
                "Dropbox sync folder not found. Sign in to the Dropbox Mac app, "
                "or set MOLY_CLOUD_ROOT to its local Mac-Profile-Sync folder."
            )
    if not root.is_dir():
        raise FileNotFoundError(f"Cloud sync folder does not exist: {root}")
    return root


def relative_source(root: Path, value: str) -> Path:
    path = (root / value).resolve()
    if not inside(path, root):
        raise ValueError(f"Cloud source escapes the sync folder: {value}")
    return path


def home_destination(value: str) -> Path:
    if not value.startswith("~/") and value != "~":
        raise ValueError(f"Destination must be in the home folder: {value}")
    path = Path(value).expanduser()
    if not inside(path, HOME):
        raise ValueError(f"Destination escapes the home folder: {value}")
    return path


def same_file(left: Path, right: Path) -> bool:
    if not left.is_file() or not right.is_file():
        return False
    a, b = left.stat(), right.stat()
    return a.st_size == b.st_size and a.st_mtime_ns == b.st_mtime_ns


def copy_tree_changed(source: Path, destination: Path, dry_run: bool) -> None:
    if source.is_symlink():
        raise ValueError(f"Symlinks are not supported as sync roots: {source}")
    if source.is_file():
        if destination.exists() and not destination.is_file():
            raise ValueError(f"File/directory conflict at {destination}")
        if same_file(source, destination):
            return
        print(f"  copy {source} -> {destination}")
        if not dry_run:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        return
    if not source.is_dir():
        raise FileNotFoundError(f"Missing source: {source}")
    if destination.exists() and not destination.is_dir():
        raise ValueError(f"File/directory conflict at {destination}")
    if not dry_run:
        destination.mkdir(parents=True, exist_ok=True)
    for child in source.iterdir():
        copy_tree_changed(child, destination / child.name, dry_run)


def copy_to_cloud(source: Path, destination: Path, dry_run: bool) -> None:
    if not source.exists():
        print(f"  skip missing local item {source}")
        return
    copy_tree_changed(source, destination, dry_run)


def restore_to_home(source: Path, destination: Path, dry_run: bool) -> None:
    if not source.exists():
        raise FileNotFoundError(f"Cloud backup missing: {source}")
    if destination.exists() and source.is_file() and same_file(source, destination):
        return
    if destination.exists() and source.is_dir() and destination.is_dir():
        # Merge changed files without deleting anything from the Mac.
        copy_tree_changed(source, destination, dry_run)
        return
    if destination.exists():
        backup_root = HOME / ".local/share/moly/overwritten"
        backup_path = backup_root / destination.relative_to(HOME)
        print(f"  preserve existing {destination} -> {backup_path}")
        if not dry_run:
            backup_path.parent.mkdir(parents=True, exist_ok=True)
            if backup_path.exists():
                backup_path = backup_path.with_name(backup_path.name + ".previous")
            shutil.move(str(destination), str(backup_path))
    copy_tree_changed(source, destination, dry_run)


def install_packages(manifest: dict, dry_run: bool) -> None:
    formulas = manifest.get("brew_packages", [])
    casks = manifest.get("brew_casks", [])
    if not formulas and not casks:
        return
    brew = shutil.which("brew")
    if not brew:
        print("Homebrew is unavailable; skipping package installs (admin help may be needed).")
        return
    for package, cask in [(name, False) for name in formulas] + [(name, True) for name in casks]:
        command = [brew, "install"] + (["--cask"] if cask else []) + [package]
        print("  run " + " ".join(command))
        if not dry_run:
            subprocess.run(command, check=False)


def synchronize(root: Path, action: str, dry_run: bool) -> None:
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Create the personal manifest first: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("version") != 1:
        raise ValueError("manifest.json must have version: 1")

    for section in ("apps", "settings", "files"):
        entries = manifest.get(section, [])
        if not isinstance(entries, list):
            raise ValueError(f"{section} must be a list")
        print(f"{section}: {len(entries)} item(s)")
        for item in entries:
            source = relative_source(root, item["source"])
            destination = home_destination(item["destination"])
            if action == "backup":
                copy_to_cloud(destination, source, dry_run)
            else:
                restore_to_home(source, destination, dry_run)

    if action == "restore":
        install_packages(manifest, dry_run)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("restore", "backup"))
    parser.add_argument("--cloud-root", default=os.environ.get("MOLY_CLOUD_ROOT"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        root = cloud_root(args.cloud_root)
        lock_path = HOME / ".local/share/moly/sync.lock"
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        with lock_path.open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            synchronize(root, args.action, args.dry_run)
    except BlockingIOError:
        print("Another Moly sync is already running; skipping.")
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"Moly stopped: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
