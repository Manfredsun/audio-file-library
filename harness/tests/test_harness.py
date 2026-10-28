#!/usr/bin/env python3
"""harness.py 自己的測試（架構文件 §24 的 evals：確認 harness 真的擋得住該擋的東西）。

    python3 harness/tests/test_harness.py

每個測試在暫存資料夾建一個小 git repo，複製一份 harness.py 與真正的 policy.yaml / limits.yaml 進去。
不碰這個 repo 的工作樹，也不需要 Xcode，所以 Claude 在 Linux VM 裡就能跑。
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.dirname(HERE)

TASK = """id: T-1
title: test
risk: {risk}
base: HEAD
scope:
  - app/Sources/Feature/*
  - app/Tests/*
  - scripts/probe.sh
  - organizer/*
required_tests:
{required}
approved:
{approved}
manual_checks:
{manual}
allow_test_removal: false
"""

GOOD_LOG = """** BUILD SUCCEEDED **
Test Suite 'FeatureTests' started at x.
Test Case '-[FoleyLibraryTests.FeatureTests testA]' passed (0.001 seconds).
Test Case '-[FoleyLibraryTests.FeatureTests testB]' passed (0.001 seconds).
Test Suite 'FeatureTests' passed at x.
\t Executed {n} tests, with 0 failures (0 unexpected) in 0.1 (0.1) seconds
** TEST SUCCEEDED **
"""

BAD_LOG = """/Users/x/Local Library Manager/app/Sources/Feature/A.swift:3:1: error: cannot find 'zzz' in scope
** BUILD FAILED **
"""


class Repo(object):
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="harness-test-")
        os.makedirs(os.path.join(self.root, "harness"))
        for f in ("harness.py", "policy.yaml", "limits.yaml"):
            shutil.copy(os.path.join(HARNESS, f), os.path.join(self.root, "harness", f))
        self.write("app/Sources/Feature/A.swift", "struct A {}\n")
        self.write("app/Sources/Other/B.swift", "struct B {}\n")
        self.write("app/Sources/Database/Migrations.swift", "// v1\n")
        self.write("app/Tests/FeatureTests.swift", "func testA() {}\nfunc testB() {}\n")
        self.write("organizer/references/taxonomy.md", "# t\n")
        self.write("organizer/schemas/taxonomy.json", "{}\n")
        self.write("README.md", "# r\n")
        self.task()
        self.git("init", "-q")
        self.git("add", "-A")
        self.git("commit", "-qm", "base")

    def git(self, *a):
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + list(a),
                       cwd=self.root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def write(self, path, text):
        full = os.path.join(self.root, path)
        d = os.path.dirname(full)
        if not os.path.isdir(d):
            os.makedirs(d)
        with open(full, "w") as f:
            f.write(text)

    def remove(self, path):
        os.remove(os.path.join(self.root, path))

    def task(self, risk="normal", required=(), approved=(), manual=(), scope=()):
        fmt = lambda xs: "".join("  - %s\n" % x for x in xs) or "  []\n"
        body = TASK.format(risk=risk, required=fmt(required), approved=fmt(approved), manual=fmt(manual))
        body = body.replace("  - organizer/*\n", "  - organizer/*\n" + "".join("  - %s\n" % x for x in scope))
        body = body.replace(":\n  []\n", ": []\n")
        self.write("harness/task.yaml", body)

    def run(self, *args):
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        r = subprocess.run([sys.executable, os.path.join(self.root, "harness", "harness.py")] + list(args),
                           cwd=self.root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        return r.returncode, r.stdout.decode("utf-8")

    def new_run(self):
        rc, out = self.run("new-run")
        assert rc == 0, out
        return out.strip().splitlines()[-1]

    def verify(self, log):
        run = self.new_run()
        rc, out = self.run("check-diff", "--run", run)
        if rc != 0:
            self.run("evaluate", run, "--skip-build")
        else:
            with open(os.path.join(run, "build.log"), "w") as f:
                f.write(log)
            self.run("evaluate", run)
        with open(os.path.join(run, "validation.json")) as f:
            return json.load(f)

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)


class DiffPolicyTests(unittest.TestCase):
    def setUp(self):
        self.r = Repo()

    def tearDown(self):
        self.r.cleanup()

    def check(self):
        return self.r.run("check-diff")

    def test_in_scope_change_passes(self):
        self.r.write("app/Sources/Feature/A.swift", "struct A { var x = 1 }\n")
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_docs_always_allowed(self):
        self.r.write("README.md", "# changed\n")
        self.r.write("docs/HANDOFF.md", "x\n")
        self.assertEqual(self.check()[0], 0)

    def test_script_outputs_are_ignored(self):
        self.r.write("docs/state.txt", "x\n")
        self.assertEqual(self.check()[0], 0)

    def test_non_ascii_path_in_scope(self):
        self.r.write("app/Sources/Feature/中文.swift", "struct Z {}\n")
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def test_out_of_scope_fails(self):
        self.r.write("app/Sources/Other/B.swift", "struct B { }\n//\n")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("scope:app/Sources/Other/B.swift", out)

    def test_deny_fails_even_if_in_scope(self):
        self.r.write("organizer/library.sqlite", "x")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("deny:organizer/library.sqlite", out)

    def test_approval_file_needs_approval(self):
        self.r.task(scope=["app/Sources/Database/*"])
        self.r.write("app/Sources/Database/Migrations.swift", "// v2\n")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("approval:app/Sources/Database/Migrations.swift", out)
        self.assertNotIn("scope:", out)

    def test_approval_granted(self):
        self.r.task(scope=["app/Sources/Database/*"], approved=["app/Sources/Database/Migrations.swift"])
        self.r.write("app/Sources/Database/Migrations.swift", "// v2\n")
        rc, out = self.check()
        self.assertEqual(rc, 0, out)
        self.assertIn("已核准：app/Sources/Database/Migrations.swift", out)

    def test_deleting_test_file_fails(self):
        self.r.remove("app/Tests/FeatureTests.swift")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("tests:app/Tests/FeatureTests.swift", out)

    def test_removing_test_function_fails(self):
        self.r.write("app/Tests/FeatureTests.swift", "func testA() {}\n")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("tests:count", out)

    def test_generated_json_without_source_fails(self):
        self.r.write("organizer/schemas/taxonomy.json", '{"x": 1}\n')
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("generated:organizer/schemas/taxonomy.json", out)

    def test_generated_json_with_source_passes(self):
        self.r.write("organizer/references/taxonomy.md", "# t2\n")
        self.r.write("organizer/schemas/taxonomy.json", '{"x": 1}\n')
        self.assertEqual(self.check()[0], 0)

    def test_swift_file_removal_needs_approval(self):
        self.r.write("app/Sources/Feature/A.swift", "try FileManager.default.removeItem(at: url)\n")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("approval:pattern:file-remove", out)

    def test_swift_network_needs_approval(self):
        self.r.write("app/Sources/Feature/A.swift", "let s = URLSession.shared\n")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("pattern:network", out)

    def test_script_sudo_denied(self):
        self.r.write("scripts/probe.sh", "#!/bin/bash\nsudo ls\n")
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("deny-pattern:sudo", out)

    def test_script_readonly_sqlite_ok_but_write_needs_approval(self):
        self.r.write("scripts/probe.sh", '#!/bin/bash\nsqlite3 "file:$DB?mode=ro" "SELECT 1; DELETE"\n')
        self.assertEqual(self.check()[0], 0)
        self.r.write("scripts/probe.sh", '#!/bin/bash\nsqlite3 "$DB" "DELETE FROM sounds"\n')
        rc, out = self.check()
        self.assertEqual(rc, 1)
        self.assertIn("pattern:db-write", out)


class EvaluateTests(unittest.TestCase):
    def setUp(self):
        self.r = Repo()

    def tearDown(self):
        self.r.cleanup()

    def test_pass(self):
        self.r.write("app/Sources/Feature/A.swift", "struct A { let y = 2 }\n")
        v = self.r.verify(GOOD_LOG.format(n=2))
        self.assertEqual(v["verdict"], "PASS", v["checks"])
        self.assertEqual(v["tests"], 2)

    def test_build_failure(self):
        self.r.write("app/Sources/Feature/A.swift", "zzz\n")
        v = self.r.verify(BAD_LOG)
        self.assertEqual(v["verdict"], "FAIL")
        self.assertIn("cannot find", [c for c in v["checks"] if c["id"] == "V1"][0]["detail"])

    def test_policy_failure_skips_build(self):
        self.r.write("app/Sources/Other/B.swift", "//\n")
        v = self.r.verify(GOOD_LOG.format(n=2))
        self.assertEqual(v["verdict"], "FAIL")
        self.assertEqual([c for c in v["checks"] if c["id"] == "V1"][0]["status"], "SKIP")

    def test_same_failure_twice_blocks(self):
        self.r.write("app/Sources/Feature/A.swift", "zzz\n")
        self.assertEqual(self.r.verify(BAD_LOG)["verdict"], "FAIL")
        v = self.r.verify(BAD_LOG)
        self.assertEqual(v["verdict"], "BLOCKED")
        self.assertTrue(any("同一個失敗" in e for e in v["escalation"]))

    def test_test_count_cannot_drop_below_last_pass(self):
        self.r.write("app/Sources/Feature/A.swift", "struct A { let y = 2 }\n")
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=10))["verdict"], "PASS")
        self.r.write("app/Sources/Feature/A.swift", "struct A { let y = 3 }\n")
        v = self.r.verify(GOOD_LOG.format(n=8))
        self.assertEqual(v["verdict"], "FAIL")

    def test_required_test_must_run(self):
        self.r.task(required=["FeatureTests", "MissingTests"])
        v = self.r.verify(GOOD_LOG.format(n=2))
        self.assertEqual(v["verdict"], "FAIL")
        self.assertIn("MissingTests", [c for c in v["checks"] if c["id"] == "V4"][0]["detail"])

    def test_required_test_case(self):
        self.r.task(required=["FeatureTests.testB"])
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PASS")

    def test_manual_check_pending_then_pass(self):
        self.r.task(manual=["點一次選單，位置正確"])
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PENDING")
        self.r.task(manual=["[x] 點一次選單，位置正確"])
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PASS")

    def test_high_risk_needs_review_with_matching_fingerprint(self):
        self.r.task(risk="high")
        self.r.write("app/Sources/Feature/A.swift", "struct A { let z = 1 }\n")
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PENDING")
        fp = self.r.run("fingerprint")[1].split()[0]
        self.r.write("harness/reviews/T-1.md", "fingerprint: %s\nverdict: approve\n" % fp)
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PASS")
        # review 之後再改程式碼 → review 失效
        self.r.write("app/Sources/Feature/A.swift", "struct A { let z = 2 }\n")
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PENDING")


class GateTests(unittest.TestCase):
    def setUp(self):
        self.r = Repo()

    def tearDown(self):
        self.r.cleanup()

    def gate(self, *paths):
        self.r.write(".commit-paths", "\n".join(paths) + "\n")
        return self.r.run("gate", os.path.join(self.r.root, ".commit-paths"))

    def test_docs_only_commit_needs_no_run(self):
        self.r.write("docs/HANDOFF.md", "x\n")
        self.assertEqual(self.gate("docs/HANDOFF.md")[0], 0)

    def test_code_commit_without_run_refused(self):
        self.r.write("app/Sources/Feature/A.swift", "struct A { let q = 1 }\n")
        self.assertEqual(self.gate("app/Sources/Feature/A.swift")[0], 1)

    def test_code_commit_after_pass(self):
        self.r.write("app/Sources/Feature/A.swift", "struct A { let q = 1 }\n")
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PASS")
        self.r.write("docs/HANDOFF.md", "寫交接不會讓驗證失效\n")
        rc, out = self.gate("app/Sources/Feature/A.swift", "docs/HANDOFF.md")
        self.assertEqual(rc, 0, out)

    def test_edit_after_pass_refused(self):
        self.r.write("app/Sources/Feature/A.swift", "struct A { let q = 1 }\n")
        self.assertEqual(self.r.verify(GOOD_LOG.format(n=2))["verdict"], "PASS")
        self.r.write("app/Sources/Feature/A.swift", "struct A { let q = 2 }\n")
        rc, out = self.gate("app/Sources/Feature/A.swift")
        self.assertEqual(rc, 1)
        self.assertIn("驗證之後程式碼又改過", out)


class ConfigTests(unittest.TestCase):
    def test_real_config_files_parse(self):
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        code = ("import sys; sys.path.insert(0, %r); import harness as h; "
                "p = h.policy(); h.limits(); h.task(); "
                "h.named_patterns(p['swift_approval_patterns']); h.named_patterns(p['script_deny_patterns']); "
                "h.named_patterns(p['script_approval_patterns']); print('ok')") % HARNESS
        r = subprocess.run([sys.executable, "-c", code], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
        self.assertEqual(r.stdout.decode().strip(), "ok", r.stdout.decode())


class StepTests(unittest.TestCase):
    def setUp(self):
        self.r = Repo()

    def tearDown(self):
        self.r.cleanup()

    def test_step_cli_executes_and_records_the_actual_command(self):
        run = self.r.new_run()
        rc, out = self.r.run("step", run, "probe", "--", sys.executable, "-c", "print('probe completed')")
        self.assertEqual(rc, 0, out)
        with open(os.path.join(run, "build.log")) as f:
            self.assertIn("probe completed", f.read())
        with open(os.path.join(run, "steps.json")) as f:
            self.assertEqual(json.load(f)["probe"]["rc"], 0)

    def test_step_cli_propagates_failure_and_records_it(self):
        run = self.r.new_run()
        rc, out = self.r.run("step", run, "probe", "--", sys.executable, "-c", "raise SystemExit(3)")
        self.assertEqual(rc, 3, out)
        with open(os.path.join(run, "steps.json")) as f:
            self.assertEqual(json.load(f)["probe"]["rc"], 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
