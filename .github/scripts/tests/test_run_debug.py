#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
APP = Path(".build/DerivedData/Build/Products/Debug/T3 Isle.app")
EXECUTABLE = APP / "Contents/MacOS/T3 Isle"

XCODEBUILD = """#!/bin/bash
app=".build/DerivedData/Build/Products/Debug/T3 Isle.app"
if [ -e "$app" ]; then echo "xcodebuild saw the old app" >> "$RUN_DEBUG_TEST_LOG"
else echo "xcodebuild saw no app" >> "$RUN_DEBUG_TEST_LOG"; fi
[ -z "${RUN_DEBUG_TEST_BUILD_FAILS:-}" ] || exit 65
mkdir -p "$app/Contents/MacOS"
printf '#!/bin/sh\\n' > "$app/Contents/MacOS/T3 Isle"
chmod +x "$app/Contents/MacOS/T3 Isle"
"""

REFUSED_TOOLS = ("codesign", "defaults", "open", "osascript")


class RunDebugTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.repo = self.dir / "repo"
        scripts = self.repo / "scripts"
        scripts.mkdir(parents=True)
        shutil.copy(REPO / "scripts" / "run-debug.sh", scripts / "run-debug.sh")
        (scripts / "run-debug.sh").chmod(0o755)
        self.log = self.dir / "calls.log"
        self.log.write_text("")
        self.bin_dir = self.dir / "bin"
        self.bin_dir.mkdir()
        self.tool("xcodebuild", XCODEBUILD)
        for name in REFUSED_TOOLS:
            self.tool(name, f'#!/bin/bash\necho "{name} $*" >> "$RUN_DEBUG_TEST_LOG"\nexit 1\n')

    def tool(self, name: str, body: str) -> None:
        path = self.bin_dir / name
        path.write_text(body)
        path.chmod(0o755)

    def run_debug(self, *args: str, **extra_env: str) -> subprocess.CompletedProcess[str]:
        env = {k: v for k, v in os.environ.items() if not k.startswith("T3ISLE_")}
        env["RUN_DEBUG_TEST_LOG"] = str(self.log)
        env["PATH"] = f"{self.bin_dir}:{env['PATH']}"
        env.update(extra_env)
        return subprocess.run(
            [str(self.repo / "scripts" / "run-debug.sh"), *args],
            cwd=self.repo, capture_output=True, text=True, env=env, timeout=60,
        )

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines()

    def old_build(self) -> Path:
        marker = self.repo / APP / "Contents" / "old-build"
        (self.repo / EXECUTABLE).parent.mkdir(parents=True)
        (self.repo / EXECUTABLE).write_text("#!/bin/sh\n")
        (self.repo / EXECUTABLE).chmod(0o755)
        marker.write_text("")
        return marker

    def running_copy(self) -> subprocess.Popen[bytes]:
        sleep = shutil.which("sleep")
        assert sleep is not None
        copy = subprocess.Popen([str(self.repo / EXECUTABLE), "60"], executable=sleep)
        self.addCleanup(copy.wait)
        self.addCleanup(copy.terminate)
        return copy

    def test_removes_the_old_app_before_the_build(self) -> None:
        marker = self.old_build()
        result = self.run_debug("--build-only")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["xcodebuild saw no app"])
        self.assertFalse(marker.exists())
        self.assertTrue((self.repo / EXECUTABLE).is_file())

    def test_refuses_to_build_while_a_copy_from_the_checkout_runs(self) -> None:
        marker = self.old_build()
        copy = self.running_copy()
        result = self.run_debug("--build-only")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn(f"stop it with scripts/stop-debug.sh {copy.pid}", result.stderr)
        self.assertEqual(json.loads(result.stdout)["pid"], copy.pid)
        self.assertEqual(self.calls(), [])
        self.assertTrue(marker.exists())

    def test_no_build_fails_after_a_failed_build(self) -> None:
        self.old_build()
        failed = self.run_debug("--build-only", RUN_DEBUG_TEST_BUILD_FAILS="1")
        self.assertEqual(failed.returncode, 2, failed.stderr)
        self.assertIn("build failed", failed.stderr)
        result = self.run_debug("--no-build", "--build-only")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn(f"no Debug build at {self.repo / APP}, run without --no-build", result.stderr)
        self.assertIn("run without --no-build", json.loads(result.stdout)["error"])
        self.assertEqual(self.calls(), ["xcodebuild saw no app"])


if __name__ == "__main__":
    unittest.main()
