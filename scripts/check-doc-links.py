#!/usr/bin/env python3
"""Fail on Markdown links that point at files which do not exist.

Only local links are checked. External URLs are left alone: resolving them would
make CI depend on the network and on other people's uptime.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
SKIP_DIRS = {".git", ".terraform", "__pycache__", "node_modules"}
EXPECTED_PLACEHOLDERS = {"docs/images/architecture.png"}


def is_external(target):
    return target.startswith(("http://", "https://", "mailto:", "#"))


def main():
    broken = []
    for path in sorted(ROOT.rglob("*.md")):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        for line_number, line in enumerate(path.read_text().splitlines(), start=1):
            for target in LINK.findall(line):
                target = target.split()[0].strip("<>")
                if is_external(target) or not target:
                    continue
                local_target = target.split("#")[0]
                relative_target = (path.parent / local_target).resolve().relative_to(ROOT)
                if str(relative_target) in EXPECTED_PLACEHOLDERS:
                    continue
                # Strip any anchor; headings are not validated.
                resolved = (path.parent / local_target).resolve()
                if not resolved.exists():
                    broken.append(f"{path.relative_to(ROOT)}:{line_number}: {target}")

    if broken:
        print("Broken local documentation links:")
        print("\n".join(broken))
        return 1
    print("All local documentation links resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
