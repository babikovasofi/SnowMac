#!/usr/bin/env python3
"""Copy missing Harness files. Preserve existing project content and report conflicts."""
import argparse
import shutil
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("target", type=Path)
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
source = args.source.resolve()
target = args.target.resolve()
if source == target or not (target / ".git").exists():
    parser.error("Choose a different Git checkout as target.")
if not (source / ".codex/hooks.json").is_file():
    parser.error("Source must be an installed Codex Harness.")

patterns = (
    "AGENTS.md", ".gitignore", ".env.example", ".codex/config.toml",
    ".codex/hooks.json", ".codex/agents/**/*", ".codex/hooks/**/*",
    ".codex/harness/**/*", ".codex/scripts/**/*", ".agents/skills/**/*",
    ".memory-bank/index.md", ".memory-bank/*/.gitkeep", "swarm-report/.gitkeep",
)
for path in sorted({path for pattern in patterns for path in source.glob(pattern)}):
    if not path.is_file() or path.is_symlink() or "__pycache__" in path.parts:
        continue
    relative = path.relative_to(source)
    output = target / relative
    if output.resolve() != output:
        print(f"CONFLICT linked path {relative}")
    elif output.is_file() and output.read_bytes() == path.read_bytes():
        continue
    elif output.exists():
        print(f"CONFLICT keep existing {relative}")
    else:
        print(f"ADD {relative}")
        if args.apply and relative == Path(".memory-bank/index.md"):
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text("# Memory Bank\n\nRecord verified project scope, stack and decisions here.\n")
        elif args.apply:
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, output)
