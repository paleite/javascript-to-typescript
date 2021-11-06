#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
DEBUG=${DEBUG:-false}
readonly DEBUG
[[ "${DEBUG}" == 'true' ]] && set -o xtrace

type git >/dev/null
type npm >/dev/null

function commit() {
  git diff-index --quiet HEAD || git commit --no-verify "${@}"
}

MIGRATION_DIR_RELATIVE="${1:-.}"
readonly MIGRATION_DIR_RELATIVE
MIGRATION_DIR="$(cd "${MIGRATION_DIR_RELATIVE}" && pwd)"
readonly MIGRATION_DIR

BIN_DIR="$(cd "${MIGRATION_DIR}" && npm bin)"
readonly BIN_DIR

GIT_ROOT="$(git rev-parse --show-toplevel)"
readonly GIT_ROOT

PACKAGEJSON_DIR="$(cd "${BIN_DIR}"/../../ && pwd)"
readonly PACKAGEJSON_DIR

# Ensure package.json could be found within the repository.
if [ "${GIT_ROOT#${PACKAGEJSON_DIR}}" != "${GIT_ROOT}" ]; then
  echo "❌ Couldn't find a package.json-file"
  exit 1
fi

echo "🚚 Installing dependencies..."
cd "${PACKAGEJSON_DIR}"
npm install --save-dev @types/node@^14 @babel/core @babel/preset-env prettier ts-migrate typescript
commit --all --message="ts-migrate: Add dependencies"

# We format the JavaScript files before we convert, so the diffs in the later
# commits only show the changes from the the TypeScript migration.
echo "💅 Formatting JavaScript..."
"${BIN_DIR}"/prettier --no-error-on-unmatched-pattern --write "${MIGRATION_DIR}/**/*.js"
commit --all --message="ts-migrate: Format JavaScript files"

echo "📄 Create tsconfig.json"
"${BIN_DIR}"/ts-migrate init "${MIGRATION_DIR}"
git add "${MIGRATION_DIR}"
commit --all --message="ts-migrate: Add tsconfig.json"

echo "♻️ Rename .js to .ts"
"${BIN_DIR}"/ts-migrate rename "${MIGRATION_DIR}"
git add ./\*.ts
commit --all --message='ts-migrate: Rename JS to TS'

echo '🧪 Creating $TSFixMe type definitions (alias for the any-keyword)...'
echo "type \$TSFixMe = any; type \$TSFixMeFunction = (...args: any[]) => any;" >"${MIGRATION_DIR}"/tsfixme.d.ts
git add "${MIGRATION_DIR}"/tsfixme.d.ts
commit --message='ts-migrate: Add $TSFixMe alias definition'

echo '🪄 Migrate (Annotate TypeScript-errors and add $TSFixMe aliases)'
"${BIN_DIR}"/ts-migrate migrate --aliases tsfixme "${MIGRATION_DIR}"
# Stage all TypeScript files _including_ subfolders
git add ./\*.ts
commit --message='ts-migrate: Add migration annotations (@ts-expect-error and $TSFixMe)'

echo "💅 Format..."
"${BIN_DIR}"/prettier --write "**/*.ts"
commit --all --message="ts-migrate: Format TypeScript files"

echo "✔︎ Typecheck..."
"${BIN_DIR}"/tsc --noEmit

echo "✨ Done migrating JavaScript to TypeScript. Now you can install more types, e.g. 'npm install --save-dev @types/lodash', add proper types wherever it says \$TSFixMe and re-run ts-migrate 'npx ts-migrate reignore ${MIGRATION_DIR_RELATIVE}'"
