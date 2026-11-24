#!/usr/bin/env bash
# Fixture autocontenido (equivale a node-bug de evals/lib/fixtures.sh). Solo crea archivos y estado git.
set -euo pipefail
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
git init -q -b main . ; mkdir -p src test scripts
printf '{ "name": "fixture-sum", "private": true, "scripts": { "lint": "node scripts/lint.mjs", "test": "node --test", "build": "node scripts/build.mjs" } }\n' > package.json
printf 'import { readFileSync } from "node:fs";\nif (/console\\.log/.test(readFileSync("src/sum.js", "utf8"))) process.exit(1);\nconsole.log("lint ok");\n' > scripts/lint.mjs
printf 'import { execFileSync } from "node:child_process";\nexecFileSync(process.execPath, ["--check", "src/sum.js"]);\nconsole.log("build ok");\n' > scripts/build.mjs
printf 'function sum(a, b) {\n  return a + b;\n}\nmodule.exports = { sum };\n' > src/sum.js
printf 'const test = require("node:test");\nconst assert = require("node:assert");\nconst { sum } = require("../src/sum.js");\ntest("suma", () => assert.strictEqual(sum(2, 3), 5));\ntest("suma negativos", () => assert.strictEqual(sum(-2, -3), -5));\n' > test/sum.test.js
printf '# Fixture\n- Verificaciones obligatorias: `npm run lint`, `npm test`, `npm run build`.\n' > README.md
git add -A && git commit -q -m base
printf 'function sum(a, b) {\n  return a - b;\n}\nfunction double(x) {\n  return sum(x, x);\n}\nmodule.exports = { sum, double };\n' > src/sum.js
