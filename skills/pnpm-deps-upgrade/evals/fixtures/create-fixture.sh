#!/usr/bin/env bash
# Create a self-contained pnpm project fixture for the pnpm-deps-upgrade skill evals.
#
#   create-fixture.sh <dest-dir> <variant>
#
# Creates, inside <dest-dir>:
#   <dest-dir>/repo       <- the project root (pass THIS to agents as the repo path)
#   <dest-dir>/origin.git <- bare remote, already wired up as `origin`
#
# Variants:
#   happy           clean tree, upkg + typecheck + test all present and passing
#   no-upkg         clean tree, no `upkg` script (must abort)
#   dirty           uncommitted work in the tree (must abort without touching it)
#   allowbuilds     upgrade pulls in a dep whose build script pnpm blocks
#   typecheck-fail  upgrade breaks typecheck (must not commit/push)
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

mkdir -p scripts src

cat > .gitignore <<'EOF'
node_modules
EOF

cat > src/index.js <<'EOF'
import isNumber from 'is-number';

export const isNumeric = value => isNumber(value);

export const isNumericString = value => typeof value === 'string' && isNumber(Number(value));
EOF

if [ "$VARIANT" != "no-upkg" ]; then
  # Stub `upkg`: mimics `soy ncu` — rewrites stale ranges in package.json in place.
  cat > scripts/upkg.mjs <<'EOF'
import { readFileSync, writeFileSync } from 'node:fs';

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const bumps = { 'is-number': '^7.0.0', esbuild: '^0.21.5' };
const touched = [];

for (const field of ['dependencies', 'devDependencies']) {
  for (const [name, range] of Object.entries(pkg[field] ?? {})) {
    if (bumps[name] && pkg[field][name] !== bumps[name]) {
      touched.push(`${name}: ${pkg[field][name]} -> ${bumps[name]}`);
      pkg[field][name] = bumps[name];
    }
  }
}

writeFileSync('package.json', `${JSON.stringify(pkg, null, 2)}\n`);
console.log(touched.length ? touched.join('\n') : 'All dependencies match the latest package versions');
EOF
fi

# Stub `typecheck`: verifies the upgraded dependency actually landed in node_modules.
cat > scripts/typecheck.mjs <<'EOF'
import { readFileSync } from 'node:fs';

const version = JSON.parse(readFileSync('node_modules/is-number/package.json', 'utf8')).version;

if (!version.startsWith('7.')) {
  console.error(`error TS2307: installed is-number@${version} does not match the declared range`);
  process.exit(1);
}

console.log(`typecheck ok (is-number@${version})`);
EOF

cat > scripts/test.mjs <<'EOF'
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

if [ "$VARIANT" = "typecheck-fail" ]; then
  cat > scripts/typecheck.mjs <<'EOF'
import { readFileSync } from 'node:fs';

const version = JSON.parse(readFileSync('node_modules/is-number/package.json', 'utf8')).version;
console.error(`src/index.js(1,19): error TS7016: could not find a declaration file for 'is-number@${version}'`);
process.exit(1);
EOF
fi

FIXTURE_UPKG="$([ "$VARIANT" = "no-upkg" ] && echo off || echo on)" node -e '
const fs = require("node:fs");
const scripts = {
  typecheck: "node scripts/typecheck.mjs",
  test: "node scripts/test.mjs"
};
if (process.env.FIXTURE_UPKG !== "off") scripts.upkg = "node scripts/upkg.mjs";

const pkg = {
  name: "fixture-app",
  private: true,
  version: "0.0.0",
  type: "module",
  packageManager: "pnpm@12.8.1",
  scripts,
  dependencies: { "is-number": "6.0.0" }
};
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
'

if [ "$VARIANT" = "no-op-upgrade" ]; then
  # Already at the versions the `upkg` stub targets, so a correct run has nothing to upgrade
  # and must NOT produce a "chore(deps): update deps" commit.
  node -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.dependencies = { "is-number": "^7.0.0" };
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
'
fi

if [ "$VARIANT" = "allowbuilds" ]; then
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
