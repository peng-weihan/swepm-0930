#!/usr/bin/env python3
"""Append only the two test crates' existing-workspace rustls dev dependency.

No Cargo command, installation, network access, production dependency change,
lockfile change, or workspace-manifest rewrite is performed here. All proposed
manifest changes are parsed and checked before either file is written.
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import tomllib


TARGETS = {
    "crates/model/Cargo.toml": "crabtalk-model",
    "crates/daemon/Cargo.toml": "crabtalk-daemon",
}
ADDITION = "\n# SWEPM test fixture: use the CLI's existing TLS provider.\n[dev-dependencies.rustls]\nworkspace = true\n"


def prepare_manifest(original: str, expected_package: str) -> str:
    before = tomllib.loads(original)
    if before.get("package", {}).get("name") != expected_package:
        raise ValueError(f"unexpected package; wanted {expected_package}")
    dev = before.get("dev-dependencies", {})
    if "rustls" in dev:
        if dev["rustls"] != {"workspace": True}:
            raise ValueError("existing rustls dev dependency differs; refusing to rewrite it")
        return original

    # A nested dev-dependency table is legal both with and without an explicit
    # [dev-dependencies] header. Appending preserves every existing byte.
    updated = original + ADDITION
    after = tomllib.loads(updated)
    expected = copy.deepcopy(before)
    expected.setdefault("dev-dependencies", {})["rustls"] = {"workspace": True}
    if after != expected:
        raise ValueError("proposed change affects more than the rustls dev dependency")
    if not updated.startswith(original):
        raise ValueError("proposed manifest change is not append-only")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("/testbed"))
    parser.add_argument("--check", action="store_true", help="validate and report without writes")
    args = parser.parse_args()
    root = args.root.resolve()
    workspace = tomllib.loads((root / "Cargo.toml").read_text())
    rustls = workspace.get("workspace", {}).get("dependencies", {}).get("rustls")
    if not isinstance(rustls, dict):
        raise ValueError("workspace rustls declaration is missing")
    if rustls.get("default-features") is not False:
        raise ValueError("workspace rustls default features changed; inspect before continuing")
    if not {"ring", "std", "tls12"}.issubset(rustls.get("features", [])):
        raise ValueError("workspace rustls lacks the CLI provider features")

    protected = [root / "Cargo.toml", root / "Cargo.lock"]
    protected_bytes = {path: path.read_bytes() for path in protected if path.exists()}
    proposals = []
    for relative, package in TARGETS.items():
        path = root / relative
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError(f"refusing unexpected manifest location: {relative}")
        original_bytes = path.read_bytes()
        updated = prepare_manifest(original_bytes.decode("utf-8"), package).encode("utf-8")
        proposals.append((path, original_bytes, updated))

    # Do not make a partial change if another worker changed a file after read.
    for path, original, _ in proposals:
        if path.read_bytes() != original:
            raise ValueError(f"manifest changed during preparation: {path}")
    for path, original, updated in proposals:
        if not args.check and original != updated:
            path.write_bytes(updated)
        print(json.dumps({
            "manifest": str(path.relative_to(root)),
            "check_only": args.check,
            "changed": original != updated,
            "before_sha256": hashlib.sha256(original).hexdigest(),
            "after_sha256": hashlib.sha256(updated).hexdigest(),
            "only_change": "dev-dependencies.rustls.workspace=true",
        }))
    for path, original in protected_bytes.items():
        if path.read_bytes() != original:
            raise ValueError(f"protected workspace/lockfile changed: {path}")


if __name__ == "__main__":
    main()
