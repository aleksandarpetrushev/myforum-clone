#!/bin/bash
# PostToolUse hook (MF-301): after Claude edits a file, run the cheapest check that covers it.
#   backend/app/**.rb         -> its spec (app/x/y.rb -> spec/x/y_spec.rb), if one exists
#   backend/spec/**_spec.rb   -> that spec
#   personalization/**.go     -> go test for that package
#   frontend/src/**.ts|.html  -> TypeScript type-check (Karma cannot run one spec quickly)
# Exit 2 with the failure on stderr feeds the failure back to Claude; anything else stays quiet.
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
file="$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')"
[ -z "$file" ] && exit 0
rel="${file#"$root"/}"

fail() { { echo "Checks failed after editing $rel ($1):"; echo "$2" | tail -40; } >&2; exit 2; }

case "$rel" in
  backend/spec/*_spec.rb)
    spec="${rel#backend/}" ;;
  backend/app/*.rb)
    candidate="spec/${rel#backend/app/}"; candidate="${candidate%.rb}_spec.rb"
    [ -f "$root/backend/$candidate" ] || exit 0
    spec="$candidate" ;;
  personalization/*.go)
    pkg="./$(dirname "${rel#personalization/}")"
    out="$(cd "$root/personalization" && go test "$pkg" 2>&1)" || fail "go test $pkg" "$out"
    exit 0 ;;
  frontend/src/*.ts|frontend/src/*.html)
    out="$(cd "$root/frontend" && npx --no-install tsc -p tsconfig.app.json --noEmit 2>&1)" || fail "tsc" "$out"
    out="$(cd "$root/frontend" && npx --no-install tsc -p tsconfig.spec.json --noEmit 2>&1)" || fail "tsc (specs)" "$out"
    exit 0 ;;
  *) exit 0 ;;
esac

out="$(cd "$root/backend" && bundle exec rspec "$spec" 2>&1)" || fail "rspec $spec" "$out"
exit 0
