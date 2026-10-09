#!/usr/bin/env bash
# Create a self-contained pnpm project fixture for the pnpm-deps-upgrade skill evals.
#
#   create-fixture.sh <dest-dir> <variant>
#
# Creates, inside <dest-dir>:
#   <dest-dir>/repo       <- the project root (pass THIS to agents as the repo path)
#   <dest-dir>/origin.git <- bare remote, already wired up as `origin`
#
# Variants (the skill drives `pnx npm-check-updates -u [-w]`, so fixtures encode
# whether the correct run needs `-w` or must not use it):
#   happy           pnpm workspace (pnpm-workspace.yaml + packages/lib); the stale
#                   dependency lives in the CHILD package, so a run without `-w`
#                   changes nothing and the upgrade only lands with `-u -w`
#   single-package  plain project, stale dependency at the root; must use `-u`
#                   WITHOUT `-w` (ncu hard-fails otherwise)
#   dirty           uncommitted work in the tree (must abort without touching it)
#   allowbuilds     upgrade pulls in a dep whose build script pnpm blocks
#   typecheck-fail  upgrade breaks typecheck (must not commit/push)
#   no-op-upgrade   already at the latest versions (must not commit)
#
# NOTE for eval authors: the project root is <dest-dir>/repo, NOT <dest-dir>.
# Pass the per-run config dir (e.g. iteration-2/eval-0-x/with_skill) as <dest-dir>
# and give agents the full <dest-dir>/repo path.
set -euo pipefail

DEST="${1:?usage: create-fixture.sh <dest-dir> <variant>}"
VARIANT="${2:?usage: create-fixture.sh <dest-dir> <variant>}"

rm -rf "$DEST"
mkdir -p "$DEST"
REPO="$DEST/repo"
ORIGIN="$DEST/origin.git"

git init --bare -q "$ORIGIN"
git init -q "$REPO"
cd "$REPO"
git config user.email "fixture@example.com"
git config user.name "Fixture"
git config commit.gpgsign false

cat > .gitignore <<'EOF'
node_modules
EOF

# `typecheck` verifies the upgraded dependency actually landed in node_modules.
# It reads is-number relative to the cwd of the script that runs it, which is the
# package that declares the dependency in both the workspace and single-package
# fixtures.
write_typecheck() {
  cat > "$1/typecheck.mjs" <<'EOF'
import { readFileSync } from 'node:fs';

const version = JSON.parse(readFileSync('node_modules/is-number/package.json', 'utf8')).version;

if (!version.startsWith('7.')) {
  console.error(`error TS2307: installed is-number@${version} does not match the declared range`);
  process.exit(1);
}

console.log(`typecheck ok (is-number@${version})`);
EOF
}

write_test() {
  cat > "$1/test.mjs" <<'EOF'
import { isNumeric, isNumericString } from '../src/index.js';

const cases = [
  [isNumeric('42'), true],
  [isNumeric('abc'), false],
  [isNumericString('42'), true],
  [isNumericString('abc'), false]
];

for (const [actual, expected] of cases) {
  if (actual !== expected) {
    console.error(`assertion failed: expected ${expected}, got ${actual}`);
    process.exit(1);
  }
}

console.log(`test ok (${cases.length} assertions)`);
EOF
}

write_src() {
  cat > "$1/index.js" <<'EOF'
import isNumber from 'is-number';

export const isNumeric = value => isNumber(value);

export const isNumericString = value => typeof value === 'string' && isNumber(Number(value));
EOF
}

# --- shared leaf package layout: scripts/ + src/ next to each other -----------
write_leaf() {
  local dir="$1"
  mkdir -p "$dir/scripts" "$dir/src"
  write_typecheck "$dir/scripts"
  write_test "$dir/scripts"
  write_src "$dir/src"
}

if [ "$VARIANT" = "happy" ]; then
  # Workspace: only the child package is stale. A run that forgets `-w` finds
  # nothing to upgrade (ncu prints "No dependencies."), which the grader catches.
  mkdir -p packages/lib
  write_leaf packages/lib
  cat > pnpm-workspace.yaml <<'EOF'
packages:
  - packages/lib
EOF
  cat > package.json <<'EOF'
{
  "name": "fixture-root",
  "private": true,
  "version": "0.0.0",
  "packageManager": "pnpm@12.8.1",
  "scripts": {
    "typecheck": "pnpm -C packages/lib run typecheck",
    "test": "pnpm -C packages/lib run test"
  }
}
EOF
  cat > packages/lib/package.json <<'EOF'
{
  "name": "lib",
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "typecheck": "node scripts/typecheck.mjs",
    "test": "node scripts/test.mjs"
  },
  "dependencies": {
    "is-number": "^6.0.0"
  }
}
EOF
elif [ "$VARIANT" = "single-package" ]; then
  # No workspaces field, no `packages:` key: `-w` would make ncu fail with
  # "workspaces property missing from package.json".
  write_leaf .
  cat > package.json <<'EOF'
{
  "name": "fixture-app",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "packageManager": "pnpm@12.8.1",
  "scripts": {
    "typecheck": "node scripts/typecheck.mjs",
    "test": "node scripts/test.mjs"
  },
  "dependencies": {
    "is-number": "6.0.0"
  }
}
EOF
else
  write_leaf .
  cat > package.json <<'EOF'
{
  "name": "fixture-app",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "packageManager": "pnpm@12.8.1",
  "scripts": {
    "typecheck": "node scripts/typecheck.mjs",
    "test": "node scripts/test.mjs"
  },
  "dependencies": {
    "is-number": "6.0.0"
  }
}
EOF
fi

if [ "$VARIANT" = "typecheck-fail" ]; then
  cat > scripts/typecheck.mjs <<'EOF'
import { readFileSync } from 'node:fs';

const version = JSON.parse(readFileSync('node_modules/is-number/package.json', 'utf8')).version;
console.error(`src/index.js(1,19): error TS7016: could not find a declaration file for 'is-number@${version}'`);
process.exit(1);
EOF
fi

if [ "$VARIANT" = "no-op-upgrade" ]; then
  # Already at the versions ncu targets, so a correct run has nothing to upgrade
  # and must NOT produce a "chore(deps): update deps" commit.
  node -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.dependencies = { "is-number": "^7.0.0" };
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
'
fi

if [ "$VARIANT" = "allowbuilds" ]; then
  # pnpm-workspace.yaml WITHOUT a `packages:` key: this project is NOT a workspace,
  # which also exercises the `-w` guard.
  cat > pnpm-workspace.yaml <<'EOF'
shamefullyHoist: true
EOF
  node -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.devDependencies = { esbuild: "0.21.5" };
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
'
fi

git add -A
git commit -qm "chore: init fixture"
git remote add origin "$ORIGIN"
git push -q -u origin HEAD

if [ "$VARIANT" = "dirty" ]; then
  cat > src/wip.js <<'EOF'
export const workInProgress = true;
EOF
  node -e '
const fs = require("node:fs");
fs.appendFileSync("src/index.js", "\nexport const experimental = () => isNumeric(\"1e3\");\n");
'
fi

echo "fixture ready: $REPO (variant=$VARIANT)"
