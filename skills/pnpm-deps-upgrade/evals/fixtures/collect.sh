#!/usr/bin/env bash
# Snapshot the observable end state of a fixture repo into a run's outputs/ dir.
#
#   collect.sh <repo> <outputs-dir> <variant>
#
# Writes outputs/final-state.md plus outputs/state.json (machine-readable) so
# grading can be done programmatically instead of by eyeballing transcripts.
set -uo pipefail

REPO="${1:?usage: collect.sh <repo> <outputs-dir> <variant>}"
OUT="${2:?usage: collect.sh <repo> <outputs-dir> <variant>}"
VARIANT="${3:?usage: collect.sh <repo> <outputs-dir> <variant>}"

mkdir -p "$OUT"
cd "$REPO" || exit 1

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo '')"
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
LAST_SUBJECT="$(git log -1 --format=%s 2>/dev/null || echo '')"
REMOTE_HEAD="$(git ls-remote origin "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')"
REMOTE_ALL="$(git ls-remote origin 2>/dev/null)"

# Re-run the project's own checks against the final tree, when deps are installed.
TYPECHECK_EXIT="skipped"
TEST_EXIT="skipped"
if [ -d node_modules ]; then
  if node -e 'process.exit(require("./package.json").scripts.typecheck ? 0 : 1)' 2>/dev/null; then
    pnpm typecheck > "$OUT/typecheck.txt" 2>&1
    TYPECHECK_EXIT="$?"
  fi
  if node -e 'process.exit(require("./package.json").scripts.test ? 0 : 1)' 2>/dev/null; then
    pnpm test > "$OUT/test.txt" 2>&1
    TEST_EXIT="$?"
  fi
fi

INSTALL_EXIT="skipped"
if [ -f pnpm-lock.yaml ]; then
  pnpm install --frozen-lockfile > "$OUT/install.txt" 2>&1
  INSTALL_EXIT="$?"
fi

{
  echo "# Final state ($VARIANT)"
  echo
  echo '## git status --porcelain'
  echo '```'
  git status --porcelain || true
  echo '```'
  echo
  echo '## git log --oneline -5'
  echo '```'
  git log --oneline -5 || true
  echo '```'
  echo
  echo '## branch / commit count / last subject'
  echo '```'
  echo "branch=$BRANCH"
  echo "head=$HEAD_SHA"
  echo "commit_count=$COMMIT_COUNT"
  echo "last_subject=$LAST_SUBJECT"
  echo "remote_head=$REMOTE_HEAD"
  echo '```'
  echo
  echo '## git ls-remote origin'
  echo '```'
  echo "$REMOTE_ALL"
  echo '```'
  echo
  echo '## re-run results against final tree'
  echo '```'
  echo "typecheck_exit=$TYPECHECK_EXIT"
  echo "test_exit=$TEST_EXIT"
  echo "frozen_install_exit=$INSTALL_EXIT"
  echo '```'
  echo
  echo '## package.json'
  echo '```json'
  cat package.json 2>/dev/null || true
  echo '```'
  echo
  echo '## pnpm-workspace.yaml'
  echo '```yaml'
  cat pnpm-workspace.yaml 2>/dev/null || echo '(absent)'
  echo '```'
  echo
  echo '## lockfile is-number entry'
  echo '```'
  grep -n -A2 -m3 "is-number" pnpm-lock.yaml 2>/dev/null || echo '(no lockfile entry)'
  echo '```'
  echo
  echo '## allowBuilds occurrences'
  echo '```'
  grep -rn "allowBuilds\|dangerouslyAllowAllBuilds" . --include=*.yaml --include=*.yml --include=*.json 2>/dev/null || echo '(none)'
  echo '```'
  echo
  echo '## working tree diff vs HEAD (excluding lockfile)'
  echo '```diff'
  git diff HEAD -- . ':(exclude)pnpm-lock.yaml' | head -200 || true
  echo '```'
  echo
  echo '## tracked files'
  echo '```'
  git ls-files || true
  echo '```'
} > "$OUT/final-state.md"

{
  echo "# Last commit"
  git show --stat --format='%H%n%s%n%an%n%ad' HEAD 2>/dev/null || true
} > "$OUT/commit.patch" 2>&1

if [ "$VARIANT" = "dirty" ]; then
  rm -rf "$OUT/user-wip-src"
  cp -R src "$OUT/user-wip-src" 2>/dev/null || true
fi

python3 - "$OUT" "$VARIANT" "$BRANCH" "$HEAD_SHA" "$COMMIT_COUNT" "$LAST_SUBJECT" "$REMOTE_HEAD" "$TYPECHECK_EXIT" "$TEST_EXIT" "$INSTALL_EXIT" <<'PY'
import json, re, subprocess, sys
from pathlib import Path

out, variant, branch, head, count, subject, remote_head, tc, tt, inst = sys.argv[1:11]
repo = Path(".")
pkg = json.loads((repo / "package.json").read_text())
ws_path = repo / "pnpm-workspace.yaml"
ws = ws_path.read_text() if ws_path.exists() else ""
lock = (repo / "pnpm-lock.yaml").read_text() if (repo / "pnpm-lock.yaml").exists() else ""

state = {
    "variant": variant,
    "branch": branch,
    "head": head,
    "commit_count": int(count),
    "last_subject": subject,
    "remote_head": remote_head,
    "remote_contains_head": bool(head) and remote_head == head,
    "typecheck_exit": tc,
    "test_exit": tt,
    "frozen_install_exit": inst,
    "deps": {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})},
    "workspace_yaml": ws,
    "allow_builds": {},
    "dangerously_allow_all": "dangerouslyAllowAllBuilds" in ws,
    "lockfile_has_is_number_v7": bool(re.search(r"is-number@7", lock)),
    "src_index": (repo / "src" / "index.js").read_text() if (repo / "src" / "index.js").exists() else "",
    "src_files": sorted(p.name for p in (repo / "src").glob("*")) if (repo / "src").exists() else [],
    "src_wip": (repo / "src" / "wip.js").read_text() if (repo / "src" / "wip.js").exists() else "",
    "tracked_files": subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split(),
    "git_status_porcelain": subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.splitlines(),
    "report": (Path(out) / "report.md").read_text() if (Path(out) / "report.md").exists() else "",
}

block = re.search(r"^allowBuilds:\n((?:[ \t]+.*\n?)*)", ws, re.M)
if block:
    for line in block.group(1).splitlines():
        m = re.match(r"\s+([^:]+):\s*(\S+)", line)
        if m:
            state["allow_builds"][m.group(1).strip().strip("'\"")] = m.group(2).strip().strip("'\"")

Path(out, "state.json").write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
print("state.json written")
PY

echo "collected -> $OUT/final-state.md"