#!/usr/bin/env python3
"""Safely update one Realm [[endpoints]] remote target."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


SECTION_RE = re.compile(r"^\s*(\[\[endpoints\]\]|\[[A-Za-z0-9_.-]+\])\s*$")
KEY_VALUE_RE = re.compile(r'^\s*([A-Za-z0-9_.-]+)\s*=\s*(.*?)\s*(?:#.*)?$')
STRING_RE = re.compile(r'^"(.*)"$')


@dataclass
class EndpointBlock:
    start: int
    end: int
    listen: str | None
    remote: str | None
    remote_line: int | None


def parse_string_value(value: str) -> str | None:
    match = STRING_RE.match(value.strip())
    if not match:
        return None
    return match.group(1)


def endpoint_blocks(lines: list[str]) -> list[EndpointBlock]:
    blocks: list[EndpointBlock] = []
    starts = [i for i, line in enumerate(lines) if line.strip() == "[[endpoints]]"]

    for idx, start in enumerate(starts):
        end = len(lines)
        for i in range(start + 1, len(lines)):
            if SECTION_RE.match(lines[i]):
                end = i
                break

        listen = None
        remote = None
        remote_line = None
        for line_no in range(start + 1, end):
            match = KEY_VALUE_RE.match(lines[line_no])
            if not match:
                continue
            key, value = match.groups()
            parsed = parse_string_value(value)
            if key == "listen":
                listen = parsed
            elif key == "remote":
                remote = parsed
                remote_line = line_no

        blocks.append(EndpointBlock(start, end, listen, remote, remote_line))

    return blocks


def validate_realm_subset(lines: list[str]) -> None:
    current_endpoint = False
    endpoint_count = 0
    endpoint_has_listen = False
    endpoint_has_remote = False

    def finish_endpoint() -> None:
        if current_endpoint and (not endpoint_has_listen or not endpoint_has_remote):
            raise ValueError("[[endpoints]] block requires both listen and remote")

    for lineno, raw in enumerate(lines, start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        if line == "[[endpoints]]":
            finish_endpoint()
            current_endpoint = True
            endpoint_count += 1
            endpoint_has_listen = False
            endpoint_has_remote = False
            continue

        if line.startswith("[") and line.endswith("]"):
            finish_endpoint()
            current_endpoint = False
            endpoint_has_listen = False
            endpoint_has_remote = False
            continue

        match = KEY_VALUE_RE.match(raw)
        if not match:
            raise ValueError(f"line {lineno}: expected key = value")

        key, value = match.groups()
        if current_endpoint and key in {"listen", "remote"}:
            parsed = parse_string_value(value)
            if parsed is None:
                raise ValueError(f"line {lineno}: {key} must be a quoted string")
            if key == "listen":
                endpoint_has_listen = True
            else:
                endpoint_has_remote = True

    finish_endpoint()
    if endpoint_count == 0:
        raise ValueError("no [[endpoints]] blocks found")


def patch_endpoint(text: str, listen: str, remote: str, append: bool) -> tuple[str, str]:
    lines = text.splitlines(keepends=True)
    validate_realm_subset(lines)

    matches = [block for block in endpoint_blocks(lines) if block.listen == listen]
    if len(matches) > 1:
        raise ValueError(f"multiple endpoints match listen={listen!r}")

    if not matches:
        if not append:
            raise ValueError(f"no endpoint matches listen={listen!r}")
        suffix = "" if text.endswith("\n") or not text else "\n"
        addition = (
            f'{suffix}\n[[endpoints]]\nlisten = "{listen}"\nremote = "{remote}"\n'
        )
        new_text = text + addition
        validate_realm_subset(new_text.splitlines(keepends=True))
        return new_text, "appended"

    block = matches[0]
    if block.remote_line is None:
        insert_at = block.start + 1
        for i in range(block.start + 1, block.end):
            if KEY_VALUE_RE.match(lines[i]) and KEY_VALUE_RE.match(lines[i]).group(1) == "listen":
                insert_at = i + 1
                break
        lines.insert(insert_at, f'remote = "{remote}"\n')
        action = "inserted remote"
    else:
        old_remote = block.remote or ""
        lines[block.remote_line] = f'remote = "{remote}"\n'
        action = f"updated remote {old_remote} -> {remote}"

    validate_realm_subset(lines)
    return "".join(lines), action


def write_atomic(path: Path, text: str) -> None:
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=str(path.parent), delete=False
    ) as tmp:
        tmp.write(text)
        tmp_path = Path(tmp.name)
    tmp_path.chmod(path.stat().st_mode)
    tmp_path.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", required=True, type=Path, help="Realm TOML file")
    parser.add_argument("--listen", required=True, help='Exact listen value, e.g. "0.0.0.0:11071"')
    parser.add_argument("--remote", required=True, help='New remote value, e.g. "10.66.51.6:13397"')
    parser.add_argument("--append", action="store_true", help="Append endpoint when listen is missing")
    parser.add_argument("--dry-run", action="store_true", help="Validate and print action without writing")
    parser.add_argument("--no-backup", action="store_true", help="Skip timestamped backup")
    args = parser.parse_args()

    path: Path = args.file
    text = path.read_text(encoding="utf-8")
    new_text, action = patch_endpoint(text, args.listen, args.remote, args.append)

    if new_text == text:
        print(f"unchanged: {args.listen} already maps to {args.remote}")
        return 0

    if args.dry_run:
        print(f"dry-run: {action}")
        return 0

    if not args.no_backup:
        stamp = datetime.utcnow().strftime("%Y%m%d-%H%M%S")
        backup = path.with_name(f"{path.name}.bak-{stamp}")
        shutil.copy2(path, backup)
        print(f"backup: {backup}")

    write_atomic(path, new_text)
    print(action)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
