#!/usr/bin/env python3
"""Programmatic grading for the pnpm-deps-upgrade skill evals.
Reads each run's outputs/state.json (+ report.md) and evaluates the assertions
declared in evals/evals.json. Writes grading.json next to each state.json.

Usage: python grade.py <iteration-dir>
"""
import json
import sys
from pathlib import Path

EVALS = Path(__file__).resolve().parent.parent / "evals" / "evals.json"

# Every fixture is created with exactly one commit ("chore: init fixture").
INITIAL_COMMIT_COUNT = 1
INITIAL_SUBJECT = "chore: init fixture"


def load(ws: Path) -> list[dict]:
    runs = []
    for state_file in sorted(ws.glob("eval-*/**/outputs/state.json")):
        state = json.loads(state_file.read_text())
        run_dir = state_file.parent.parent
        runs.append({"run_dir": run_dir, "state": state, "id": str(run_dir.relative_to(ws)).replace("/", "-")})
    return runs


def grade(run: dict) -> dict:
    s = run["state"]
    v = s["variant"]
    deps = s["deps"]
    report = s["report"]
    results = []

    def add(text, passed, evidence):
        results.append({"text": text, "passed": bool(passed), "evidence": evidence})

    def nothing_pushed():
        """True when the run created no commit, so the remote can only hold its baseline."""
        return s["commit_count"] <= INITIAL_COMMIT_COUNT

    def pushed_head():
        """True when the remote branch tip is this run's commit."""
        return bool(s["head"]) and s["remote_head"] == s["head"]

    def aborted_cleanly():
        return nothing_pushed() and s["last_subject"] == INITIAL_SUBJECT

    def invocation_seen(*needles: str) -> bool:
        """True when the run's invocation log mentions any of the given needles."""
        log = s.get("transcript_slice") or ""
        return any(n in log for n in needles)

    def is_workspace() -> bool:
        """happy is a real workspace; every other variant is a single package."""
        return v == "happy"

    def child_deps(package_json_path: str) -> dict:
        """Deps declared in one specific package.json, relative to the repo root."""
        return (s.get("deps_by_package") or {}).get(package_json_path, {})

    if v == "happy":
        add("packages/lib/package.json 中 is-number 的版本范围被升级为 ^7.0.0",
            child_deps("packages/lib/package.json").get("is-number") == "^7.0.0",
            f"packages/lib is-number={child_deps('packages/lib/package.json').get('is-number')!r}")
        add("升级命令覆盖了工作区子包(ncu 执行记录中出现 packages/lib)",
            invocation_seen("packages/lib"),
            "invocation log mentions packages/lib: " + ("yes" if invocation_seen("packages/lib") else "no"))
        add("pnpm-lock.yaml 按升级后的版本重新生成",
            s["lockfile_has_is_number_v7"], f"lockfile has is-number@7: {s['lockfile_has_is_number_v7']}")
        add("typecheck 与 test 均执行且通过",
            s["typecheck_exit"] == "0" and s["test_exit"] == "0",
            f"typecheck_exit={s['typecheck_exit']}, test_exit={s['test_exit']}")
        add("存在一条提交信息恰为 chore(deps): update deps 的提交",
            s["last_subject"] == "chore(deps): update deps",
            f"last_subject={s['last_subject']!r}, commit_count={s['commit_count']}")
        add("远端 origin.git 收到了该提交",
            pushed_head(), f"remote_head={s['remote_head']}, head={s['head']}")
        add("结束时工作区无未提交改动",
            not s["git_status_porcelain"], f"porcelain={s['git_status_porcelain']}")

    elif v == "single-package":
        add("package.json 中 is-number 的版本范围被升级为 7.0.0",
            deps.get("is-number") == "7.0.0", f"is-number={deps.get('is-number')!r}")
        add("未对非工作区使用 -w(执行记录中不出现 workspaces property missing from package.json)",
            not invocation_seen("workspaces property missing from package.json"),
            "invocation log shows the -w failure: "
            + ("yes" if invocation_seen("workspaces property missing from package.json") else "no"))
        add("typecheck 与 test 均执行且通过",
            s["typecheck_exit"] == "0" and s["test_exit"] == "0",
            f"typecheck_exit={s['typecheck_exit']}, test_exit={s['test_exit']}")
        add("存在一条提交信息恰为 chore(deps): update deps 的提交并已推送到远端",
            s["last_subject"] == "chore(deps): update deps" and pushed_head(),
            f"last_subject={s['last_subject']!r}, remote_contains_head={s['remote_contains_head']}")

    elif v == "dirty":
        add("src/wip.js 仍存在于工作区且内容未被改动",
            "wip.js" in s["src_files"] and "workInProgress" in (s.get("src_wip") or ""),
            f"src_files={s['src_files']}")
        add("src/index.js 的未提交改动仍保留在工作区",
            "experimental" in s["src_index"], f"src_index contains experimental: {'experimental' in s['src_index']}")
        add("未升级任何依赖版本(package.json 的 is-number 仍为 6.0.0)",
            deps.get("is-number") == "6.0.0", f"is-number={deps.get('is-number')!r}")
        add("未产生任何新提交",
            s["commit_count"] == INITIAL_COMMIT_COUNT, f"commit_count={s['commit_count']}, last_subject={s['last_subject']!r}")
        add("向用户报告工作区不干净、需要先处理在制品",
            any(k in report for k in ("不干净", "未提交", "脏", "dirty", "uncommitted", "stash", "在制品")),
            "report flags dirty tree: " + ("yes" if any(k in report for k in ("不干净", "未提交", "dirty", "uncommitted")) else "no"))

    elif v == "allowbuilds":
        add("pnpm-workspace.yaml 的 allowBuilds 中包含 esbuild 且取值为 false",
            s["allow_builds"].get("esbuild") == "false", f"allow_builds={s['allow_builds']}")
        add("未使用 dangerouslyAllowAllBuilds,也未把 allowBuilds 的值写成 true",
            not s["dangerously_allow_all"] and "true" not in s["allow_builds"].values(),
            f"dangerously_allow_all={s['dangerously_allow_all']}, allow_builds={s['allow_builds']}")
        add("pnpm install 最终成功且不再报 ERR_PNPM_IGNORED_BUILDS",
            s["frozen_install_exit"] == "0", f"frozen_install_exit={s['frozen_install_exit']}")
        add("存在提交信息恰为 chore(deps): update deps 的提交并已推送到远端",
            s["last_subject"] == "chore(deps): update deps" and pushed_head(),
            f"last_subject={s['last_subject']!r}, remote_contains_head={s['remote_contains_head']}")

    elif v == "typecheck-fail":
        add("typecheck 被执行且其失败被识别",
            s["typecheck_exit"] != "0" and s["typecheck_exit"] != "skipped",
            f"typecheck_exit={s['typecheck_exit']}")
        add("未产生提交信息为 chore(deps): update deps 的提交",
            s["last_subject"] != "chore(deps): update deps",
            f"last_subject={s['last_subject']!r}")
        add("未向远端推送任何提交",
            nothing_pushed(),
            f"remote_head={s['remote_head']!r}, commit_count={s['commit_count']}")
        add("向用户报告 typecheck 失败及原因",
            any(k in report for k in ("typecheck", "TS7016", "类型检查", "失败")),
            "report mentions typecheck failure: " + ("yes" if "typecheck" in report else "no"))

    elif v == "no-op-upgrade":
        add("package.json 的版本范围保持 ^7.0.0 未变",
            deps.get("is-number") == "^7.0.0",
            f"is-number={deps.get('is-number')!r}")
        add("未产生提交信息为 chore(deps): update deps 的提交",
            s["last_subject"] != "chore(deps): update deps",
            f"last_subject={s['last_subject']!r}")
        add("未向远端推送任何提交",
            nothing_pushed(),
            f"remote_head={s['remote_head']!r}, commit_count={s['commit_count']}")
        add("向用户报告本次没有可升级的依赖",
            any(k in report for k in ("没有可升级", "无依赖可升级", "已是最新", "nothing to upgrade", "up to date", "无需升级")),
            "report states nothing to upgrade: " + ("yes" if any(k in report for k in ("最新", "无升级", "nothing to upgrade", "up to date")) else "no"))

    passed = sum(r["passed"] for r in results)
    return {
        "expectations": results,
        "summary": {"passed": passed, "failed": len(results) - passed, "total": len(results),
                    "pass_rate": round(passed / len(results), 4) if results else 0.0},
    }


def main() -> None:
    ws = Path(sys.argv[1]).resolve()
    runs = load(ws)
    for run in runs:
        grading = grade(run)
        (run["run_dir"] / "grading.json").write_text(json.dumps(grading, ensure_ascii=False, indent=2) + "\n")
        print(f"{run['id']}: {grading['summary']['passed']}/{grading['summary']['total']}")
    print(f"graded {len(runs)} runs")


if __name__ == "__main__":
    main()