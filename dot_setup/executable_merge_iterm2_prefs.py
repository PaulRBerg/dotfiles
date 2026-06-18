#!/usr/bin/env python3
"""Merge selected iTerm2 preferences into an exported macOS defaults plist."""

from __future__ import annotations

import os
import plistlib
import sys
import tempfile
from pathlib import Path
from typing import Any


PROFILE_MATCH_KEYS = ("Guid", "Name")


def load_plist(path: Path) -> dict[str, Any]:
    if not path.exists() or path.stat().st_size == 0:
        return {}

    with path.open("rb") as handle:
        data = plistlib.load(handle)

    if not isinstance(data, dict):
        raise TypeError(f"{path} does not contain a plist dictionary")

    return data


def merge_dict(target: dict[str, Any], source: dict[str, Any]) -> None:
    for key, value in source.items():
        existing = target.get(key)
        if isinstance(existing, dict) and isinstance(value, dict):
            merge_dict(existing, value)
        else:
            target[key] = value


def find_profile_index(profiles: list[Any], match: dict[str, Any]) -> int | None:
    has_selector = False

    for key in PROFILE_MATCH_KEYS:
        value = match.get(key)
        if not value:
            continue
        has_selector = True

        for index, profile in enumerate(profiles):
            if isinstance(profile, dict) and profile.get(key) == value:
                return index

    if has_selector:
        return None

    return 0 if profiles else None


def build_profile(match: dict[str, Any]) -> dict[str, Any]:
    profile = {key: match[key] for key in PROFILE_MATCH_KEYS if key in match}
    profile.setdefault("Name", "Default")
    return profile


def merge_default_profile(current: dict[str, Any], profile_spec: dict[str, Any]) -> None:
    match = profile_spec.get("Match", {})
    settings = profile_spec.get("Settings", {})
    if not isinstance(match, dict) or not isinstance(settings, dict):
        raise TypeError("Default Profile Match and Settings must be dictionaries")

    profiles = current.setdefault("New Bookmarks", [])
    if not isinstance(profiles, list):
        raise TypeError("New Bookmarks must be an array")

    profile_index = find_profile_index(profiles, match)
    if profile_index is None:
        profile = build_profile(match)
        profiles.append(profile)
        profile_index = len(profiles) - 1

        if "Default Bookmark Guid" not in current and isinstance(profile.get("Guid"), str):
            current["Default Bookmark Guid"] = profile["Guid"]

    profile = profiles[profile_index]
    if not isinstance(profile, dict):
        raise TypeError(f"New Bookmarks[{profile_index}] must be a dictionary")
    merge_dict(profile, settings)


def write_plist(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as handle:
            plistlib.dump(data, handle, sort_keys=True)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(
            "usage: merge_iterm2_prefs.py MANAGED_PLIST CURRENT_PLIST OUTPUT_PLIST",
            file=sys.stderr,
        )
        return 2

    managed = load_plist(Path(argv[1]))
    current = load_plist(Path(argv[2]))

    global_settings = managed.get("Global Settings", {})
    if not isinstance(global_settings, dict):
        raise TypeError("Global Settings must be a dictionary")
    merge_dict(current, global_settings)

    profile_spec = managed.get("Default Profile", {})
    if profile_spec:
        if not isinstance(profile_spec, dict):
            raise TypeError("Default Profile must be a dictionary")
        merge_default_profile(current, profile_spec)

    write_plist(Path(argv[3]), current)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
