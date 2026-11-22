#!/usr/bin/env python3
"""Behavioral tests for scripts/prove.sh, with stand-ins for the app scripts."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]

STUBS = {
    "run-debug.sh": """#!/bin/bash
root=$(cd "$(dirname "$0")/.." && pwd -P)
for argument in "$@"; do
  [ "$argument" != --build-only ] || { [ ! -f "$root/build-fails" ] || exit 1; exit 0; }
done
echo "$*" >> "$PROVE_TEST_LOG"
[ ! -f "$root/no-start" ] || { echo '{"pid":4243,"error":"stub"}'; exit 3; }
echo '{"pid":4242,"app":"stub"}'
""",
    "debug.sh": """#!/bin/bash
root=$(cd "$(dirname "$0")/.." && pwd -P)
shift 2
if [ "$1" = state ]; then
  [ ! -f "$root/state-fails" ] || exit 3
  cat "$root/state.json"
  exit 0
fi
[ "$1" != boom ]
""",
    "capture.sh": """#!/bin/bash
root=$(cd "$(dirname "$0")/.." && pwd -P)
while [ $# -gt 1 ]; do
  case "$1" in
    --out) out=$2; shift ;;
    --state-dir | --pid) shift ;;
  esac
  shift
done
label=$1
suffix=$(cat "$root/shot-suffix" 2>/dev/null)
count=$(find "$out" -name '*.png' | wc -l | tr -d ' ')
file="$out/$(printf '%02d' $((count + 1)))-$label$suffix.png"
echo png > "$file"
echo "$file"
""",
    "stop-debug.sh": "#!/bin/bash\necho \"stop $*\" >> \"$PROVE_TEST_LOG\"\n",
}

PROOF = """# the tab opens on home
run close-notch
run open-notch
shot opened
check .tab == "home"
"""


@unittest.skipUnless(shutil.which("jq") and shutil.which("git"), "needs jq and git")
class ProveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.repo = self.dir / "repo"
        scripts = self.repo / "scripts"
        (scripts / "lib").mkdir(parents=True)
        for name in ("prove.sh",):
            shutil.copy(REPO / "scripts" / name, scripts / name)
        for name in ("proof.sh", "prove-session.sh"):
            shutil.copy(REPO / "scripts" / "lib" / name, scripts / "lib" / name)
        for name, body in STUBS.items():
            (scripts / name).write_text(body)
        for script in scripts.rglob("*.sh"):
            script.chmod(0o755)
        self.log = self.dir / "calls.log"
        self.log.write_text("")
        bin_dir = self.dir / "bin"
        bin_dir.mkdir()
        fake_defaults = bin_dir / "defaults"
        fake_defaults.write_text('#!/bin/bash\necho "defaults $*" >> "$PROVE_TEST_LOG"\n')
        fake_defaults.chmod(0o755)
        self.bin_dir = bin_dir
        self.git("init", "-q", "-b", "main")
        self.proof = self.dir / "tab.proof"
        self.proof.write_text(PROOF)

    def git(self, *args: str) -> str:
        result = subprocess.run(
            ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
            cwd=self.repo, capture_output=True, text=True, check=True,
        )
        return result.stdout.strip()

    def commit(self, name: str, **files: str | None) -> str:
        for filename, content in files.items():
            path = self.repo / filename.replace("_json", ".json").replace("_", "-")
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_text(content)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", name)
        return self.git("rev-parse", "HEAD")

    def prove(self, *args: str, **extra_env: str) -> subprocess.CompletedProcess[str]:
        env = {k: v for k, v in os.environ.items() if not k.startswith("T3ISLE_")}
        env["PROVE_TEST_LOG"] = str(self.log)
        env["PATH"] = f"{self.bin_dir}:{env['PATH']}"
        env.update(extra_env)
        return subprocess.run(
            [str(self.repo / "scripts" / "prove.sh"), "--out", str(self.dir / "out"), *args],
            cwd=self.repo, capture_output=True, text=True, env=env,
        )

    def fixed_and_broken(self) -> tuple[str, str]:
        broken = self.commit("broken", state_json='{"tab":"shelf"}')
        fixed = self.commit("fixed", state_json='{"tab":"home"}')
        return broken, fixed

    def report(self) -> dict:
        return json.loads((self.dir / "out" / "report.json").read_text())

    def test_exits_0_when_the_base_fails_and_the_head_passes(self) -> None:
        broken, fixed = self.fixed_and_broken()
        result = self.prove("--base", broken, "--head", fixed, str(self.proof))
        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.report()
        self.assertTrue(report["proven"])
        self.assertFalse(report["base"]["passed"])
        self.assertTrue(report["head"]["passed"])
        self.assertEqual(report["base"]["sha"], broken)
        self.assertEqual(report["head"]["checks"], [{"check": '.tab == "home"', "passed": True}])
        self.assertEqual(json.loads(result.stdout), report)

    def test_exits_1_when_base_and_head_are_the_same(self) -> None:
        _, fixed = self.fixed_and_broken()
        result = self.prove("--base", fixed, "--head", fixed, str(self.proof))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("does not show the bug", result.stderr)
        self.assertFalse(self.report()["proven"])

    def test_exits_1_when_the_head_still_fails(self) -> None:
        broken, _ = self.fixed_and_broken()
        result = self.prove("--base", broken, "--head", broken, str(self.proof))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("head fails", result.stderr)

    def test_exits_2_when_the_build_fails(self) -> None:
        broken, _ = self.fixed_and_broken()
        failing = self.commit("fails to build", build_fails="")
        result = self.prove("--base", broken, "--head", failing, str(self.proof))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("head build failed", result.stderr)

    def test_exits_2_when_the_app_does_not_start(self) -> None:
        broken, _ = self.fixed_and_broken()
        stuck = self.commit("does not start", no_start="")
        result = self.prove("--base", broken, "--head", stuck, str(self.proof))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("head app did not start", result.stderr)

    def test_exits_3_when_a_step_fails(self) -> None:
        broken, fixed = self.fixed_and_broken()
        self.proof.write_text(PROOF.replace("run open-notch", "run boom"))
        result = self.prove("--base", broken, "--head", fixed, str(self.proof))
        self.assertEqual(result.returncode, 3, result.stderr)

    def test_exits_3_when_the_state_cannot_be_read(self) -> None:
        broken, _ = self.fixed_and_broken()
        unreadable = self.commit("no state", state_fails="")
        result = self.prove("--base", broken, "--head", unreadable, str(self.proof))
        self.assertEqual(result.returncode, 3, result.stderr)

    def test_exits_3_when_the_filter_errors_on_the_state(self) -> None:
        broken, fixed = self.fixed_and_broken()
        self.proof.write_text(PROOF.replace('.tab == "home"', ".tab | tonumber"))
        result = self.prove("--base", broken, "--head", fixed, str(self.proof))
        self.assertEqual(result.returncode, 3, result.stderr)

    def test_pairs_the_shots_by_label(self) -> None:
        broken, fixed = self.fixed_and_broken()
        result = self.prove("--base", broken, "--head", fixed, str(self.proof))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.report()["pairs"],
            [{"label": "opened", "base": "base/captures/01-opened.png", "head": "head/captures/01-opened.png"}],
        )
        for side in ("base", "head"):
            self.assertTrue((self.dir / "out" / side / "captures" / "01-opened.png").is_file())

    def test_leaves_a_shot_that_one_side_lacks_unpaired(self) -> None:
        broken, _ = self.fixed_and_broken()
        renamed = self.commit("renames the shot", state_json='{"tab":"home"}', shot_suffix="-later")
        result = self.prove("--base", broken, "--head", renamed, str(self.proof))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("one side only", result.stderr)
        self.assertEqual(
            self.report()["pairs"],
            [
                {"label": "opened", "base": "base/captures/01-opened.png", "head": None},
                {"label": "opened-later", "base": None, "head": "head/captures/01-opened-later.png"},
            ],
        )

    def test_finds_a_proof_by_name(self) -> None:
        broken, fixed = self.fixed_and_broken()
        proofs = self.repo / "scripts" / "proofs"
        proofs.mkdir()
        (proofs / "tab.proof").write_text(PROOF)
        result = self.prove("--base", broken, "--head", fixed, "tab")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.report()["proof"], "tab")

    def test_removes_its_worktrees_and_work_folder(self) -> None:
        broken, fixed = self.fixed_and_broken()
        for head in (fixed, "no-such-ref"):
            self.prove("--base", broken, "--head", head, str(self.proof))
        self.assertEqual(self.git("worktree", "list").count("\n"), 0)
        self.assertEqual(list((self.repo / ".build").glob("prove.*")), [])

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines()

    def test_stops_each_app_it_launched(self) -> None:
        broken, fixed = self.fixed_and_broken()
        self.prove("--base", broken, "--head", fixed, str(self.proof))
        stops = [c for c in self.calls() if c.startswith("stop ")]
        self.assertEqual(len(stops), 2)
        self.assertTrue(all(c.endswith(" 4242") for c in stops))

    def test_stops_an_app_that_started_but_never_became_ready(self) -> None:
        broken, _ = self.fixed_and_broken()
        stuck = self.commit("does not start", no_start="")
        result = self.prove("--base", broken, "--head", stuck, str(self.proof))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertTrue(any(c.startswith("stop ") and c.endswith(" 4243") for c in self.calls()))

    def test_passes_settings_and_launch_arguments_to_the_app(self) -> None:
        broken, fixed = self.fixed_and_broken()
        self.proof.write_text("set t3Enabled bool false\nset openingTab string last\nlaunch --demo\n" + PROOF)
        result = self.prove("--base", broken, "--head", fixed, str(self.proof))
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertEqual(sum(c.startswith("defaults write ") and c.endswith("/defaults t3Enabled -bool false") for c in calls), 2)
        self.assertEqual(sum(c.endswith("/defaults openingTab -string last") for c in calls), 2)
        self.assertEqual(sum(c.startswith("--no-build --state-dir ") and c.endswith(" --demo") for c in calls), 2)

    def test_exits_3_when_a_wrapper_ends_a_session_without_running_its_checks(self) -> None:
        _, fixed = self.fixed_and_broken()
        result = self.prove("--base", fixed, "--head", fixed, str(self.proof), T3ISLE_PROVE_SCREEN_WRAP="false")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("recorded 0 of 1 checks", result.stderr)

    def test_removes_its_worktrees_after_a_failed_run(self) -> None:
        broken, _ = self.fixed_and_broken()
        stuck = self.commit("does not start", no_start="")
        self.prove("--base", broken, "--head", stuck, str(self.proof))
        self.assertEqual(self.git("worktree", "list").count("\n"), 0)
        self.assertEqual(list((self.repo / ".build").glob("prove.*")), [])

    def test_rejects_bad_arguments_with_64(self) -> None:
        broken, fixed = self.fixed_and_broken()
        bad_proofs = {
            "no check": "run close-notch\n",
            "unknown directive": PROOF + "press enter\n",
            "repeated label": PROOF + "shot opened\n",
            "bad label": PROOF + "shot no/slash\n",
            "bad set": PROOF + "set key flag value\n",
            "bare launch": PROOF + "launch\n",
            "bad filter": PROOF + "check .tab ==\n",
        }
        for name, content in bad_proofs.items():
            with self.subTest(name):
                self.proof.write_text(content)
                result = self.prove("--base", broken, "--head", fixed, str(self.proof))
                self.assertEqual(result.returncode, 64, result.stderr)
        self.proof.write_text(PROOF)
        for args in (
            [],
            ["--base"],
            ["--bogus", str(self.proof)],
            [str(self.proof), "second"],
            ["--base", "no-such-ref", str(self.proof)],
            [str(self.dir / "missing.proof")],
        ):
            with self.subTest(args=args):
                self.assertEqual(self.prove(*args).returncode, 64)


if __name__ == "__main__":
    unittest.main()
