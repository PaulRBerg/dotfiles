"""Contract tests for the iTerm2 managed-preferences merge helper."""

from __future__ import annotations

import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT_PATH = Path(__file__).parent.parent / "dot_setup/executable_merge_iterm2_prefs.py"
SPEC = importlib.util.spec_from_file_location("merge_iterm2_prefs", SCRIPT_PATH)
assert SPEC and SPEC.loader
MERGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MERGE)


class MergeIterm2PreferencesTests(unittest.TestCase):
    def write_plist(self, path: Path, data: object) -> None:
        with path.open("wb") as handle:
            plistlib.dump(data, handle)

    def read_plist(self, path: Path) -> dict[str, object]:
        with path.open("rb") as handle:
            return plistlib.load(handle)

    def run_merge(self, managed: object, current: object) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            managed_path = tmp_path / "managed.plist"
            current_path = tmp_path / "current.plist"
            output_path = tmp_path / "output.plist"
            self.write_plist(managed_path, managed)
            self.write_plist(current_path, current)

            self.assertEqual(MERGE.main(["merge", str(managed_path), str(current_path), str(output_path)]), 0)
            return self.read_plist(output_path)

    def test_recursively_merges_global_settings_without_losing_unmanaged_values(self) -> None:
        result = self.run_merge(
            {"Global Settings": {"nested": {"managed": "new"}, "added": True}},
            {"nested": {"managed": "old", "preserved": 1}, "unmanaged": "kept"},
        )

        self.assertEqual(
            result,
            {
                "nested": {"managed": "new", "preserved": 1},
                "added": True,
                "unmanaged": "kept",
            },
        )

    def test_profile_matching_prefers_guid_before_name(self) -> None:
        result = self.run_merge(
            {
                "Default Profile": {
                    "Match": {"Guid": "guid-2", "Name": "Default"},
                    "Settings": {"Rows": 40},
                }
            },
            {
                "New Bookmarks": [
                    {"Guid": "guid-1", "Name": "Default", "Rows": 10},
                    {"Guid": "guid-2", "Name": "Other", "Rows": 20},
                ]
            },
        )

        self.assertEqual(result["New Bookmarks"][0]["Rows"], 10)
        self.assertEqual(result["New Bookmarks"][1]["Rows"], 40)

    def test_profile_matching_falls_back_to_name_when_guid_is_missing(self) -> None:
        result = self.run_merge(
            {
                "Default Profile": {
                    "Match": {"Guid": "missing", "Name": "Default"},
                    "Settings": {"Rows": 40},
                }
            },
            {"New Bookmarks": [{"Guid": "guid-1", "Name": "Default", "Rows": 10}]},
        )

        self.assertEqual(result["New Bookmarks"], [{"Guid": "guid-1", "Name": "Default", "Rows": 40}])

    def test_creates_missing_profile_and_sets_default_guid(self) -> None:
        result = self.run_merge(
            {
                "Default Profile": {
                    "Match": {"Guid": "new-guid", "Name": "Default"},
                    "Settings": {"Rows": 40},
                }
            },
            {},
        )

        self.assertEqual(result["Default Bookmark Guid"], "new-guid")
        self.assertEqual(result["New Bookmarks"], [{"Guid": "new-guid", "Name": "Default", "Rows": 40}])

    def test_rejects_malformed_root_and_container_types(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            malformed_root = tmp_path / "root.plist"
            self.write_plist(malformed_root, ["not", "a", "dictionary"])
            with self.assertRaisesRegex(TypeError, "plist dictionary"):
                MERGE.load_plist(malformed_root)

        with self.assertRaisesRegex(TypeError, "Global Settings"):
            self.run_merge({"Global Settings": []}, {})

        with self.assertRaisesRegex(TypeError, "New Bookmarks"):
            self.run_merge(
                {"Default Profile": {"Match": {"Guid": "guid"}, "Settings": {}}},
                {"New Bookmarks": {}},
            )

    def test_failed_write_keeps_existing_output_and_removes_temporary_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "output.plist"
            self.write_plist(output_path, {"existing": "value"})

            with mock.patch.object(MERGE.plistlib, "dump", side_effect=ValueError("cannot serialize")):
                with self.assertRaisesRegex(ValueError, "cannot serialize"):
                    MERGE.write_plist(output_path, {"new": "value"})

            self.assertEqual(self.read_plist(output_path), {"existing": "value"})
            self.assertEqual(list(output_path.parent.glob(f".{output_path.name}.*")), [])

    def test_write_creates_parent_and_replaces_output_with_a_valid_plist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            output_path = Path(tmp_dir) / "new-parent" / "output.plist"

            MERGE.write_plist(output_path, {"value": 1})

            self.assertEqual(self.read_plist(output_path), {"value": 1})


if __name__ == "__main__":
    unittest.main()
