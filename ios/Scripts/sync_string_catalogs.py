"""Fills the String Catalogs from the keys the compiler extracted (SWIFT_EMIT_LOC_STRINGS).

Xcode does this automatically when you build in the IDE; this script does the same for
command-line builds. Existing translations are kept; keys no longer in code are marked stale.

Usage: python3 ios/Scripts/sync_string_catalogs.py <DerivedData build dir>
"""

import json
import plistlib
import sys
from pathlib import Path

IOS = Path(__file__).resolve().parents[1]
CATALOGS = {
    "Zahori": IOS / "Zahori/Resources/Localizable.xcstrings",
    "ZahoriKit": IOS / "ZahoriKit/Sources/ZahoriKit/Resources/Localizable.xcstrings",
    "ZahoriCore": IOS / "ZahoriKit/Sources/ZahoriCore/Resources/Localizable.xcstrings",
}


def module_of(source: str) -> str:
    if "/ZahoriKit/Sources/ZahoriCore/" in source:
        return "ZahoriCore"
    if "/ZahoriKit/Sources/ZahoriKit/" in source:
        return "ZahoriKit"
    return "Zahori"


def main(build_dir: str) -> None:
    keys = {name: set() for name in CATALOGS}
    for f in Path(build_dir).rglob("*.stringsdata"):
        data = plistlib.loads(f.read_bytes()) if f.read_bytes()[:6] == b"bplist" else json.loads(f.read_text())
        mod = module_of(data.get("source", ""))
        for entry in data.get("tables", {}).get("Localizable", []):
            keys[mod].add(entry["key"])

    for mod, path in CATALOGS.items():
        catalog = json.loads(path.read_text()) if path.exists() else {"sourceLanguage": "es", "strings": {}, "version": "1.0"}
        strings = catalog.setdefault("strings", {})
        for k in keys[mod]:
            strings.setdefault(k, {})
            strings[k].pop("extractionState", None)
        for k in strings:
            if k not in keys[mod]:
                strings[k]["extractionState"] = "stale"
        catalog["strings"] = dict(sorted(strings.items()))
        path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n", encoding="utf-8")
        print(f"{mod}: {len(keys[mod])} keys -> {path.relative_to(IOS)}")


if __name__ == "__main__":
    main(sys.argv[1])
