#!/usr/bin/env python3
"""Local Library Manager 的 coding harness。

只用標準函式庫：Mac 內建的 python3（Command Line Tools）沒有 PyYAML，版本也可能只有 3.9。

子命令
  new-run                 建立 runs/<id>/，印出路徑
  event RUN TYPE [JSON]   追加一筆事件到 runs/<id>/events.jsonl
  step RUN NAME -- CMD    執行一個步驟（有逾時），輸出附加到 build.log
  check-diff [--run RUN]  Diff / Policy 驗證（Claude 可以在 Linux VM 先跑一次）
  evaluate RUN            讀 build.log + diff 結果，給出最終判定、寫 ledger
  fingerprint             目前工作樹（相對 HEAD）的程式碼指紋
  gate PATHS_FILE         commit 前的閘門：程式碼改動必須有同指紋的 PASS
  metrics                 從 ledger 算基本指標

判定只有四種：PASS / PENDING / FAIL / BLOCKED。說明見 harness/VERIFY.md。
"""
from __future__ import print_function

import argparse
import datetime
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RUNS = os.path.join(ROOT, "runs")
LEDGER = os.path.join(RUNS, "ledger.jsonl")


# ---------------------------------------------------------------- 設定檔

class ConfigError(Exception):
    pass


def _scalar(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        return v[1:-1]
    if v == "[]":
        return []
    if v.lower() in ("true", "yes"):
        return True
    if v.lower() in ("false", "no"):
        return False
    if re.match(r"^-?\d+$", v):
        return int(v)
    return v


def load_conf(path):
    """極小的 YAML 子集：`key: value`、`key:` 加 `  - item`、整行 # 註解。"""
    data, current = {}, None
    if not os.path.exists(path):
        raise ConfigError("找不到 %s" % os.path.relpath(path, ROOT))
    with open(path, encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            if line[0] in " \t":
                if not s.startswith("- ") and s != "-":
                    raise ConfigError("%s:%d 無法解析：%s" % (path, n, line))
                if current is None:
                    raise ConfigError("%s:%d list item 前面沒有 key" % (path, n))
                data[current].append(_scalar(s[1:]))
                continue
            if ":" not in s:
                raise ConfigError("%s:%d 無法解析：%s" % (path, n, line))
            key, _, val = s.partition(":")
            key = key.strip()
            if val.strip() == "":
                data[key] = []
                current = key
            else:
                data[key] = _scalar(val)
                current = None
    return data


def policy():
    return load_conf(os.path.join(HERE, "policy.yaml"))


def limits():
    return load_conf(os.path.join(HERE, "limits.yaml"))


def task():
    t = load_conf(os.path.join(HERE, "task.yaml"))
    for k in ("scope", "required_tests", "approved", "manual_checks"):
        v = t.get(k, [])
        t[k] = v if isinstance(v, list) else [v]
    t.setdefault("id", "(未命名)")
    t.setdefault("risk", "normal")
    t.setdefault("base", "HEAD")
    t.setdefault("allow_test_removal", False)
    return t


def named_patterns(items):
    out = []
    for it in items or []:
        name, sep, rx = str(it).partition("=")
        if not sep:
            raise ConfigError("pattern 格式應為「名稱 = regex」：%s" % it)
        out.append((name.strip(), re.compile(rx.strip(), re.IGNORECASE)))
    return out


def match_any(path, globs):
    for g in globs or []:
        if fnmatch.fnmatchcase(path, g):
            return g
    return None


# ---------------------------------------------------------------- git

def git(*args, **kw):
    # --no-optional-locks：Claude 的 Linux VM 不能刪檔，一般的 git status 會留下刪不掉的 index.lock。
    r = subprocess.run(["git", "--no-optional-locks", "-c", "core.quotepath=off"] + list(args), cwd=ROOT,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0 and not kw.get("ok_fail"):
        raise RuntimeError("git %s 失敗：%s" % (" ".join(args), r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout.decode("utf-8", "replace")


def resolve(ref):
    return git("rev-parse", "--verify", ref + "^{commit}").strip()


def changed_files(base, pol):
    """相對 base 的改動（含未追蹤檔）。回傳 {path: 'A'|'M'|'D'}。"""
    out = {}
    for line in git("diff", "--name-status", "--no-renames", base).splitlines():
        if not line.strip():
            continue
        st, _, path = line.partition("\t")
        out[path] = st[0]
    for path in git("ls-files", "--others", "--exclude-standard").splitlines():
        if path.strip():
            out[path] = "A"
    ign = pol.get("ignore", [])
    return {p: s for p, s in out.items() if not match_any(p, ign)}


def added_lines(base, path, status):
    if status == "D":
        return []
    if status == "A" and not git("ls-files", "--", path).strip():
        try:
            with open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as f:
                return f.read().splitlines()
        except (IOError, OSError):
            return []
    lines = []
    for l in git("diff", "-U0", base, "--", path).splitlines():
        if l.startswith("+") and not l.startswith("+++"):
            lines.append(l[1:])
    return lines


TEST_FUNC = re.compile(r"^\s*(?:@\w+\s+)*(?:override\s+)?func\s+test\w*\s*\(", re.M)


def count_test_funcs_at(base, globs):
    total = 0
    for p in git("ls-tree", "-r", "--name-only", base).splitlines():
        if match_any(p, globs) and p.endswith(".swift"):
            total += len(TEST_FUNC.findall(git("show", "%s:%s" % (base, p), ok_fail=True)))
    return total


def count_test_funcs_now(globs):
    total, seen = 0, set()
    for g in globs or []:
        prefix = os.path.dirname(g.split("*")[0].split("?")[0]) or "."
        for dirpath, _, files in os.walk(os.path.join(ROOT, prefix)):
            for fn in files:
                p = os.path.relpath(os.path.join(dirpath, fn), ROOT)
                if p in seen or not match_any(p, globs) or not p.endswith(".swift"):
                    continue
                seen.add(p)
                with open(os.path.join(ROOT, p), encoding="utf-8", errors="replace") as f:
                    total += len(TEST_FUNC.findall(f.read()))
    return total


def file_hash(path):
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        return "DELETED"
    h = hashlib.sha256()
    with open(full, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def fingerprint(pol=None):
    """HEAD → 工作樹的程式碼改動指紋。文件不算（fingerprint_exclude）。"""
    pol = pol or policy()
    files = changed_files("HEAD", pol)
    ex = pol.get("fingerprint_exclude", [])
    h = hashlib.sha256()
    n = 0
    for p in sorted(files):
        if match_any(p, ex):
            continue
        h.update(("%s\0%s\0%s\n" % (p, files[p], file_hash(p))).encode("utf-8"))
        n += 1
    return ("empty" if n == 0 else h.hexdigest()[:16]), n


# ---------------------------------------------------------------- runs / events / ledger

def now():
    return datetime.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")


def event(run_dir, etype, data=None, **extra):
    rec = {"event": etype, "timestamp": now(), "agent": os.environ.get("HARNESS_AGENT", "claude")}
    rec.update(extra)
    rec["data"] = data or {}
    with open(os.path.join(run_dir, "events.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (IOError, OSError, ValueError):
        return default


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")


def ledger():
    out = []
    if os.path.exists(LEDGER):
        with open(LEDGER, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        out.append(json.loads(line))
                    except ValueError:
                        pass
    return out


def cmd_new_run(_):
    t = task()
    os.makedirs(RUNS, exist_ok=True)
    day = datetime.date.today().isoformat()
    n = 1
    while os.path.exists(os.path.join(RUNS, "%s-%03d" % (day, n))):
        n += 1
    run_id = "%s-%03d" % (day, n)
    d = os.path.join(RUNS, run_id)
    os.makedirs(d)
    attempt = 1 + sum(1 for e in ledger() if e.get("task") == t["id"] and e.get("verdict") != "PASS")
    write_json(os.path.join(d, "state.json"), {
        "run_id": run_id, "task": t["id"], "status": "running", "attempt": attempt,
        "current_agent": os.environ.get("HARNESS_AGENT", "claude"), "started": now()})
    with open(os.path.join(HERE, "task.yaml"), encoding="utf-8") as src, \
            open(os.path.join(d, "task.yaml"), "w", encoding="utf-8") as dst:
        dst.write(src.read())
    with open(os.path.join(RUNS, "LATEST"), "w") as f:
        f.write(run_id + "\n")
    event(d, "run_started", {"task": t["id"], "attempt": attempt})
    print(d)


def cmd_event(a):
    event(a.run, a.type, json.loads(a.data) if a.data else {})


def cmd_step(a):
    lim = limits()
    timeout = int(lim.get("timeout_%s_seconds" % a.name, 600))
    cmd = a.command[1:] if a.command and a.command[0] == "--" else a.command
    log = os.path.join(a.run, "build.log")
    event(a.run, "tool_call", {"step": a.name, "cmd": cmd, "timeout": timeout})
    t0 = time.time()
    with open(log, "a", encoding="utf-8") as f:
        f.write("\n===== step %s @ %s =====\n" % (a.name, now()))
        f.flush()
        try:
            rc = subprocess.run(cmd, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, timeout=timeout).returncode
            timed_out = False
        except subprocess.TimeoutExpired:
            rc, timed_out = 124, True
            f.write("\n!!!!! step %s 逾時（%d 秒）\n" % (a.name, timeout))
        except OSError as e:
            rc, timed_out = 127, False
            f.write("\n!!!!! step %s 無法執行：%s\n" % (a.name, e))
    steps = read_json(os.path.join(a.run, "steps.json"), {})
    steps[a.name] = {"rc": rc, "timed_out": timed_out, "seconds": round(time.time() - t0, 1)}
    write_json(os.path.join(a.run, "steps.json"), steps)
    event(a.run, "tool_result", {"step": a.name, "rc": rc, "timed_out": timed_out,
                                 "seconds": steps[a.name]["seconds"]})
    sys.exit(rc)


# ---------------------------------------------------------------- V3 diff / policy

def check_diff(pol=None, t=None, lim=None):
    pol, t, lim = pol or policy(), t or task(), lim or limits()
    base = resolve(str(t["base"]))
    files = changed_files(base, pol)
    errors, warnings, approvals_used = [], [], []
    approved = set(str(x) for x in t["approved"])
    scope = list(t["scope"]) + list(pol.get("always_allowed", []))

    def need(key, why):
        if key in approved:
            approvals_used.append(key)
        else:
            errors.append("approval:%s — %s，task.yaml 的 approved 沒有列「%s」" % (key, why, key))

    for p, st in sorted(files.items()):
        g = match_any(p, pol.get("deny", []))
        if g:
            errors.append("deny:%s — 禁止改動（policy deny：%s）" % (p, g))
            continue
        g = match_any(p, pol.get("approval", []))
        if g:
            need(g, "%s 屬於需要核准的檔案" % p)
        if not match_any(p, scope):
            errors.append("scope:%s — 不在任務範圍（task.yaml scope）" % p)
        if st == "D" and match_any(p, pol.get("protected_tests", [])) and not t["allow_test_removal"]:
            errors.append("tests:%s — 刪除了測試檔" % p)

    # 產生物必須跟著來源一起改
    for rule in pol.get("generated", []):
        gen, _, srcs = str(rule).partition("<=")
        gen = gen.strip()
        src_globs = [s.strip() for s in srcs.split("|") if s.strip()]
        gen_changed = [p for p in files if fnmatch.fnmatchcase(p, gen)]
        if gen_changed and not any(match_any(p, src_globs) for p in files):
            for p in gen_changed:
                errors.append("generated:%s — 產生物被改，但來源（%s）沒改；不要手改產生物" % (p, " / ".join(src_globs)))

    # 新增行的危險樣式
    swift_ap = named_patterns(pol.get("swift_approval_patterns"))
    sh_deny = named_patterns(pol.get("script_deny_patterns"))
    sh_ap = named_patterns(pol.get("script_approval_patterns"))
    added_total = 0
    for p, st in sorted(files.items()):
        lines = added_lines(base, p, st)
        added_total += len(lines)
        text = "\n".join(lines)
        if p.endswith(".swift") and not match_any(p, pol.get("protected_tests", [])):
            for name, rx in swift_ap:
                if rx.search(text):
                    need("pattern:" + name, "%s 新增了 %s" % (p, name))
        if p.startswith("scripts/") and (p.endswith(".sh") or p.endswith(".py")):
            for name, rx in sh_deny:
                if rx.search(text):
                    errors.append("deny-pattern:%s — %s 新增了禁止的指令" % (name, p))
            for name, rx in sh_ap:
                if rx.search(text):
                    need("pattern:" + name, "%s 新增了 %s" % (p, name))

    # 測試數量
    pt = pol.get("protected_tests", [])
    tests_base = count_test_funcs_at(base, pt)
    tests_now = count_test_funcs_now(pt)
    if tests_now < tests_base and not t["allow_test_removal"]:
        errors.append("tests:count — test 函式從 %d 變成 %d" % (tests_base, tests_now))

    code_files = [p for p in files if not match_any(p, pol.get("fingerprint_exclude", []))]
    if len(code_files) > int(lim.get("max_files_per_step", 8)):
        warnings.append("步子太大：%d 個程式碼檔案（上限 %s，CLAUDE.md §52）" % (len(code_files), lim.get("max_files_per_step")))
    if added_total > int(lim.get("max_added_lines_per_step", 400)):
        warnings.append("步子太大：新增 %d 行（上限 %s）" % (added_total, lim.get("max_added_lines_per_step")))

    return {
        "ok": not errors, "base": base, "files": files, "errors": errors, "warnings": warnings,
        "approvals_used": sorted(set(approvals_used)), "added_lines": added_total,
        "test_funcs": {"base": tests_base, "now": tests_now},
    }


def cmd_check_diff(a):
    r = check_diff()
    if a.run:
        write_json(os.path.join(a.run, "diff-check.json"), r)
        with open(os.path.join(a.run, "diff.patch"), "w", encoding="utf-8") as f:
            f.write(git("diff", r["base"]))
            untracked = [p for p, s in r["files"].items() if s == "A" and not git("ls-files", "--", p).strip()]
            if untracked:
                f.write("\n# 未追蹤的新檔案\n" + "".join("#   %s\n" % p for p in untracked))
        event(a.run, "validation_started" if r["ok"] else "validation_failed",
              {"layer": "diff", "errors": r["errors"]})
    print("V3 Diff/Policy：%s（%d 個檔案，base %s）" % ("PASS" if r["ok"] else "FAIL", len(r["files"]), r["base"][:8]))
    for e in r["errors"]:
        print("  ✗ " + e)
    for w in r["warnings"]:
        print("  ! " + w)
    for ap in r["approvals_used"]:
        print("  ✓ 已核准：" + ap)
    sys.exit(0 if r["ok"] else 1)


# ---------------------------------------------------------------- evaluate

def parse_log(path):
    txt = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            txt = f.read()
    executed = [(int(m.group(1)), int(m.group(2))) for m in
                re.finditer(r"Executed (\d+) tests?, with (\d+) failures?", txt)]
    tests, failures = max(executed) if executed else (0, 0)
    compile_errors = []
    for l in txt.splitlines():
        if re.search(r"(^|\s|:)error: ", l) and "Test Case" not in l and ": error: -[" not in l:
            s = re.sub(r"^/.*?/(app/)", r"\1", l.strip())
            if s not in compile_errors:
                compile_errors.append(s)
    warn = set(l.strip() for l in txt.splitlines()
               if ": warning: " in l and "appintentsmetadataprocessor" not in l)
    failed_tests = sorted(set("%s.%s" % (m.group(1).split(".")[-1], m.group(2)) for m in
                              re.finditer(r"Test Case '-\[(\S+) (\w+)\]' failed", txt)))
    passed_suites = set(re.findall(r"Test Suite '([^']+)' passed", txt))
    passed_cases = set("%s.%s" % (m.group(1).split(".")[-1], m.group(2)) for m in
                       re.finditer(r"Test Case '-\[(\S+) (\w+)\]' passed", txt))
    return {
        "build_ok": "** BUILD SUCCEEDED **" in txt, "build_failed": "** BUILD FAILED **" in txt,
        "test_ok": "** TEST SUCCEEDED **" in txt, "test_failed": "** TEST FAILED **" in txt,
        "tests": tests, "failures": failures, "failed_tests": failed_tests,
        "compile_errors": compile_errors[:20], "warnings": len(warn),
        "passed_suites": passed_suites, "passed_cases": passed_cases,
    }


def last_pass(entries):
    for e in reversed(entries):
        if e.get("verdict") == "PASS" and e.get("tests"):
            return e
    return None


def evaluate(run_dir, skip_build=False):
    pol, t, lim = policy(), task(), limits()
    entries = ledger()
    diff = read_json(os.path.join(run_dir, "diff-check.json")) or check_diff(pol, t, lim)
    steps = read_json(os.path.join(run_dir, "steps.json"), {})
    log = parse_log(os.path.join(run_dir, "build.log"))
    checks, fails, pending = [], [], []

    def add(code, name, status, detail=""):
        checks.append({"id": code, "name": name, "status": status, "detail": detail})
        if status == "FAIL":
            fails.append(code)
        elif status == "PENDING":
            pending.append(code)

    # V3 先列，因為它決定要不要建置
    add("V3", "Diff / Policy", "PASS" if diff["ok"] else "FAIL", "；".join(diff["errors"]))
    timed = [k for k, v in steps.items() if v.get("timed_out")]

    if skip_build:
        add("V1", "建置", "SKIP", "V3 失敗，沒有建置（省下使用者機器的 CPU）")
        add("V2", "測試", "SKIP", "")
    else:
        if log["build_ok"] and not log["build_failed"]:
            add("V1", "建置", "PASS", "")
        else:
            why = "逾時：%s" % ",".join(timed) if timed else (log["compile_errors"][0] if log["compile_errors"] else "沒有看到 BUILD SUCCEEDED")
            add("V1", "建置", "FAIL", why)
        base = last_pass(entries)
        detail = "%d 個測試，%d 個失敗" % (log["tests"], log["failures"])
        if not log["test_ok"] or log["failures"] or log["test_failed"]:
            add("V2", "測試", "FAIL", detail + ("：" + ", ".join(log["failed_tests"][:10]) if log["failed_tests"] else ""))
        elif base and log["tests"] < int(base.get("tests", 0)) and not t["allow_test_removal"]:
            add("V2", "測試", "FAIL", detail + "；比上次 PASS（%s 個）少" % base.get("tests"))
        else:
            add("V2", "測試", "PASS", detail)
        if base and log["warnings"] > int(base.get("warnings", 0)):
            add("V2w", "編譯警告", "WARN", "%d → %d" % (base.get("warnings", 0), log["warnings"]))

    # V4 任務驗收：指定的測試必須真的跑過而且通過
    missing = []
    for req in t["required_tests"]:
        req = str(req)
        ok = req in log["passed_cases"] if "." in req else req in log["passed_suites"]
        if not ok:
            missing.append(req)
    if t["required_tests"]:
        if skip_build:
            add("V4", "任務指定的測試", "SKIP", "")
        else:
            add("V4", "任務指定的測試", "FAIL" if missing else "PASS",
                ("沒跑到或沒通過：" + ", ".join(missing)) if missing else ", ".join(map(str, t["required_tests"])))

    fp, nfp = fingerprint(pol)

    # V5 高風險任務要有對應同一份指紋的 review
    if str(t["risk"]) == "high":
        rv = os.path.join(HERE, "reviews", "%s.md" % t["id"])
        ok, why = False, "缺少 harness/reviews/%s.md" % t["id"]
        if os.path.exists(rv):
            with open(rv, encoding="utf-8") as f:
                body = f.read()
            m_fp = re.search(r"^fingerprint:\s*(\S+)", body, re.M)
            m_v = re.search(r"^verdict:\s*(\S+)", body, re.M)
            if not m_fp or m_fp.group(1) != fp:
                why = "review 的 fingerprint 不是目前這份改動（%s）" % fp
            elif not m_v or m_v.group(1).lower() != "approve":
                why = "review 的 verdict 不是 approve"
            else:
                ok, why = True, "reviewer 已核可"
        add("V5", "Review（risk: high）", "PASS" if ok else "PENDING", why)

    # V6 人工驗收
    todo = [str(x) for x in t["manual_checks"] if not str(x).startswith("[x]")]
    if t["manual_checks"]:
        add("V6", "人工驗收", "PENDING" if todo else "PASS",
            ("待確認：" + "；".join(todo)) if todo else "使用者已確認")

    # 判定 + 升級
    signature = ""
    if fails:
        parts = [e.split(" — ")[0] for e in diff["errors"]] + log["failed_tests"] + log["compile_errors"][:3] + timed
        signature = hashlib.sha1("\n".join(sorted(parts)).encode("utf-8")).hexdigest()[:12]
    same_task = [e for e in entries if e.get("task") == t["id"]]
    since_pass = []
    for e in reversed(same_task):
        if e.get("verdict") == "PASS":
            break
        since_pass.append(e)
    attempts = len(since_pass) + 1
    same = 1
    if signature:
        for e in since_pass:
            if e.get("signature") == signature:
                same += 1
            else:
                break
    verdict = "FAIL" if fails else ("PENDING" if pending else "PASS")
    escalate = []
    if verdict == "FAIL":
        if same >= int(lim.get("max_same_failure", 2)):
            escalate.append("同一個失敗連續 %d 次" % same)
        if attempts >= int(lim.get("max_attempts_per_task", 5)):
            escalate.append("這個任務已送驗 %d 次" % attempts)
        if any(c.startswith("V3") for c in fails) and any("deny" in e for e in diff["errors"]):
            escalate.append("碰到 policy deny（安全規則）")
        if escalate:
            verdict = "BLOCKED"

    state = read_json(os.path.join(run_dir, "state.json"), {})
    result = {
        "run_id": os.path.basename(run_dir.rstrip("/")), "task": t["id"], "title": t.get("title", ""),
        "risk": t["risk"], "verdict": verdict, "checks": checks, "attempt": attempts,
        "signature": signature, "same_failure_count": same if signature else 0, "escalation": escalate,
        "fingerprint": fp, "fingerprint_files": nfp, "tests": log["tests"], "failures": log["failures"],
        "warnings": log["warnings"], "files_changed": sorted(diff["files"]),
        "approvals_used": diff["approvals_used"], "diff_warnings": diff["warnings"],
        "steps": steps, "started": state.get("started"), "finished": now(),
    }
    write_json(os.path.join(run_dir, "validation.json"), result)
    state.update({"status": "completed" if verdict == "PASS" else verdict.lower(), "last_validation": verdict,
                  "finished": result["finished"], "attempt": attempts})
    write_json(os.path.join(run_dir, "state.json"), state)
    with open(os.path.join(run_dir, "final.md"), "w", encoding="utf-8") as f:
        f.write(render_final(result, log))
    os.makedirs(RUNS, exist_ok=True)
    slim = {k: result[k] for k in ("run_id", "task", "risk", "verdict", "attempt", "signature", "fingerprint",
                                  "tests", "failures", "warnings", "started", "finished", "approvals_used")}
    slim["failed_checks"] = fails
    slim["files_changed"] = len(result["files_changed"])
    with open(LEDGER, "a", encoding="utf-8") as f:
        f.write(json.dumps(slim, ensure_ascii=False) + "\n")
    event(run_dir, {"PASS": "run_completed", "PENDING": "review_started"}.get(verdict, "run_failed"),
          {"verdict": verdict, "failed": fails, "pending": pending, "escalation": escalate})
    return result


def render_final(r, log):
    icon = {"PASS": "✓", "FAIL": "✗", "PENDING": "…", "SKIP": "-", "WARN": "!"}
    out = ["# Run %s — %s %s" % (r["run_id"], r["task"], r["title"]), "",
           "**判定：%s**　第 %d 次送驗　指紋 `%s`（%d 個程式碼檔案）" % (r["verdict"], r["attempt"], r["fingerprint"], r["fingerprint_files"]), ""]
    out.append("## 檢查")
    out.append("")
    for c in r["checks"]:
        out.append("- %s **%s %s**：%s %s" % (icon.get(c["status"], "?"), c["id"], c["name"], c["status"],
                                              ("— " + c["detail"]) if c["detail"] else ""))
    if r["diff_warnings"]:
        out += ["", "## 警告", ""] + ["- " + w for w in r["diff_warnings"]]
    if r["approvals_used"]:
        out += ["", "## 動用的核准（使用者請看一眼）", ""] + ["- " + a for a in r["approvals_used"]]
    if log["compile_errors"]:
        out += ["", "## 編譯錯誤（前 10 行）", "", "```"] + log["compile_errors"][:10] + ["```"]
    if log["failed_tests"]:
        out += ["", "## 失敗的測試", ""] + ["- " + x for x in log["failed_tests"][:30]]
    out += ["", "## 改動的檔案", ""] + ["- " + p for p in r["files_changed"]] if r["files_changed"] else []
    out += ["", "## 下一步", ""]
    if r["verdict"] == "PASS":
        out.append("可以交付：更新 HANDOFF、commit（scripts/commit.sh 會核對指紋）。")
    elif r["verdict"] == "PENDING":
        out.append("程式驗證通過，等 review 或人工驗收。完成後再跑一次 verify.sh 才會變成 PASS。")
    elif r["verdict"] == "FAIL":
        out.append("依 harness/LOOP.md §4 的重試階梯處理（第 %d 次）。" % r["attempt"])
    else:
        out += ["停止自動重試。依 harness/LOOP.md §6 用下列格式向使用者回報：", "",
                "```text", "BLOCKED", "Reason: " + "；".join(r["escalation"]),
                "Required human decision: （Claude 填寫）",
                "Current state: run %s，失敗項目 %s" % (r["run_id"], ", ".join(c["id"] for c in r["checks"] if c["status"] == "FAIL")),
                "Suggested next action: （Claude 填寫）", "```"]
    return "\n".join(out) + "\n"


def cmd_evaluate(a):
    r = evaluate(a.run, skip_build=a.skip_build)
    print("判定：%s" % r["verdict"])
    for c in r["checks"]:
        print("  %-4s %-18s %s %s" % (c["id"], c["name"], c["status"], c["detail"]))
    if r["escalation"]:
        print("  升級：" + "；".join(r["escalation"]))
    sys.exit(0 if r["verdict"] in ("PASS", "PENDING") else 1)


# ---------------------------------------------------------------- gate / fingerprint / metrics

def gate(paths):
    pol = policy()
    ex = pol.get("fingerprint_exclude", []) + pol.get("ignore", [])
    code = [p for p in paths if not match_any(p, ex)]
    if not code:
        return True, "只有文件，不需要驗證紀錄"
    fp, _ = fingerprint(pol)
    entries = ledger()
    if not entries:
        return False, "沒有任何驗證紀錄。先跑 scripts/verify.sh"
    last = entries[-1]
    if last.get("verdict") != "PASS":
        return False, "最近一次驗證（%s）是 %s，不是 PASS" % (last.get("run_id"), last.get("verdict"))
    if last.get("fingerprint") != fp:
        return False, "驗證之後程式碼又改過（驗證時 %s，現在 %s）。重跑 scripts/verify.sh" % (last.get("fingerprint"), fp)
    return True, "對應 PASS run %s（指紋 %s）" % (last.get("run_id"), fp)


def cmd_gate(a):
    with open(a.paths_file, encoding="utf-8") as f:
        paths = [l.strip() for l in f if l.strip()]
    ok, why = gate(paths)
    print(("閘門通過：" if ok else "閘門拒絕：") + why)
    sys.exit(0 if ok else 1)


def cmd_fingerprint(_):
    fp, n = fingerprint()
    print("%s  (%d 個程式碼檔案相對 HEAD 有改動)" % (fp, n))


def cmd_metrics(_):
    e = ledger()
    if not e:
        print("ledger 是空的")
        return
    tasks = {}
    for x in e:
        tasks.setdefault(x.get("task"), []).append(x)
    passed = [k for k, v in tasks.items() if any(y.get("verdict") == "PASS" for y in v)]
    runs_to_pass = [next(i for i, y in enumerate(v, 1) if y.get("verdict") == "PASS") for k, v in tasks.items() if k in passed]
    by_check = {}
    for x in e:
        for c in x.get("failed_checks", []):
            by_check[c] = by_check.get(c, 0) + 1
    print("runs                %d" % len(e))
    print("tasks               %d（完成 %d，Task Success Rate %.0f%%）" % (len(tasks), len(passed), 100.0 * len(passed) / len(tasks)))
    print("首次送驗通過率      %.0f%%" % (100.0 * sum(1 for n in runs_to_pass if n == 1) / max(1, len(runs_to_pass))))
    print("平均送驗次數到 PASS %.1f" % (sum(runs_to_pass) / float(max(1, len(runs_to_pass)))))
    print("Validation Pass Rate %.0f%%" % (100.0 * sum(1 for x in e if x.get("verdict") == "PASS") / len(e)))
    print("BLOCKED             %d" % sum(1 for x in e if x.get("verdict") == "BLOCKED"))
    print("失敗分布            %s" % (", ".join("%s×%d" % kv for kv in sorted(by_check.items())) or "—"))
    print("最近測試數          %s" % e[-1].get("tests"))


def main(argv=None):
    p = argparse.ArgumentParser(prog="harness.py")
    sub = p.add_subparsers(dest="cmd")
    sub.add_parser("new-run")
    s = sub.add_parser("event"); s.add_argument("run"); s.add_argument("type"); s.add_argument("data", nargs="?")
    s = sub.add_parser("step"); s.add_argument("run"); s.add_argument("name"); s.add_argument("command", nargs=argparse.REMAINDER)
    s = sub.add_parser("check-diff"); s.add_argument("--run")
    s = sub.add_parser("evaluate"); s.add_argument("run"); s.add_argument("--skip-build", action="store_true")
    sub.add_parser("fingerprint")
    s = sub.add_parser("gate"); s.add_argument("paths_file")
    sub.add_parser("metrics")
    a = p.parse_args(argv)
    fn = {"new-run": cmd_new_run, "event": cmd_event, "step": cmd_step, "check-diff": cmd_check_diff,
          "evaluate": cmd_evaluate, "fingerprint": cmd_fingerprint, "gate": cmd_gate, "metrics": cmd_metrics}.get(a.cmd)
    if not fn:
        p.print_help()
        return 2
    try:
        fn(a)
    except ConfigError as e:
        print("設定錯誤：%s" % e)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
