#!/usr/bin/env python3
"""Verify public source access and reject missing or conflicting local inputs."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
EDITION = ROOT / "Sources/KeyminApp/BuildEdition.swift"

with tempfile.TemporaryDirectory(prefix="keymin-public-access-", dir="/private/tmp") as directory:
    folder = Path(directory)

    # The access fixture needs no Xcode plugins, so avoid a full-Xcode license dependency.
    compile_environment = os.environ.copy()
    compile_environment["DEVELOPER_DIR"] = "/Library/Developer/CommandLineTools"
    compiler = ["swiftc", "-module-cache-path", str(folder / "modules")]

    # Public source and App Store builds must both keep the shared identity and normal access rules.
    for flags, expected in (([], "source"), (["-D", "KEYMIN_APP_STORE"], "app-store")):
        executable = folder / f"test-{expected}"
        subprocess.run(
            compiler + flags + [str(EDITION), str(ROOT / "scripts/test_source_build.swift"), "-o", str(executable)],
            check=True,
            env=compile_environment,
        )
        subprocess.run([str(executable), expected], check=True)

    # The local flag must fail when the ignored access source is absent.
    missing = subprocess.run(
        compiler + ["-typecheck", "-D", "KEYMIN_LOCAL_BUILD", str(EDITION)],
        capture_output=True,
        text=True,
        env=compile_environment,
    )
    assert missing.returncode != 0 and "KeyminLocalAccess" in missing.stderr

    # App Store and private-local flags must never coexist.
    conflict = subprocess.run(
        compiler + [
            "-typecheck", "-D", "KEYMIN_LOCAL_BUILD", "-D", "KEYMIN_APP_STORE", str(EDITION),
        ],
        capture_output=True,
        text=True,
        env=compile_environment,
    )
    assert conflict.returncode != 0 and "Local access must not be included" in conflict.stderr
    print("Public source and App Store editions keep normal access rules; local flags are guarded")
