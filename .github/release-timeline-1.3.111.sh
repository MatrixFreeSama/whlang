#!/usr/bin/env bash
set -euo pipefail

versions=(1.3.99 1.3.102 1.3.110 1.3.111)
commits=(
  d67f8af8ca8889ec29b69521747db268af274f09
  c59ed074877197c38b86bd0c262c2936be638cbf
  39c7766c3b1fb41c728b68e82d85cefbc557bcdb
  d65d8842d7ff46a0b549792bb931ac9384a08b95
)

# Validate the complete release set before deleting anything. Historical sha256
# files are allowed to contain stale/absolute path fields; the digest itself is
# the authority.
for v in "${versions[@]}"; do
  zip="dist/Wheelchair-${v}.zip"
  sum="dist/Wheelchair-${v}.zip.sha256"
  test -f "$zip"
  test -f "$sum"
  expected="$(awk 'NR==1{print $1}' "$sum")"
  actual="$(sha256sum "$zip" | awk '{print $1}')"
  test -n "$expected"
  test "$actual" = "$expected"
  unzip -tq "$zip" >/dev/null
done

# The three missing releases must really be absent before we repair the timeline.
for v in 1.3.99 1.3.102 1.3.110; do
  if gh release view "v${v}" >/dev/null 2>&1; then
    echo "unexpected existing release v${v}" >&2
    exit 1
  fi
done

# Remove the prematurely published newest release and its tag.
gh release delete v1.3.111 --cleanup-tag --yes

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

notes_for() {
  local v="$1"
  local zip="dist/Wheelchair-${v}.zip"
  local needle="${v//./_}"
  local out="$work/notes-${v}.md"
  local p
  p="$(unzip -Z1 "$zip" | grep -E "RELEASE_NOTES_${needle}\\.md$" | head -n1 || true)"
  if [ -n "$p" ]; then
    unzip -p "$zip" "$p" > "$out"
  else
    cat > "$out" <<EOF
# Wheelchair ${v}

Wheelchair ${v}. Release assets are mirrored from the repository \`dist/\` directory.
EOF
  fi
  printf '%s\n' "$out"
}

# Recreate the missing history in strict version order. Each release points at the
# commit where that release first became part of repository history; 1.3.111
# points at the final synchronized source commit.
for i in "${!versions[@]}"; do
  v="${versions[$i]}"
  c="${commits[$i]}"
  notes="$(notes_for "$v")"
  args=(
    "v${v}"
    "dist/Wheelchair-${v}.zip"
    "dist/Wheelchair-${v}.zip.sha256"
    --target "$c"
    --title "Wheelchair ${v}"
    --notes-file "$notes"
  )
  if [ "$v" = "1.3.111" ]; then
    gh release create "${args[@]}" --latest
  else
    gh release create "${args[@]}" --latest=false
  fi
  sleep 2
done

# Verify targets and both release assets before removing this one-shot mechanism.
for i in "${!versions[@]}"; do
  v="${versions[$i]}"
  c="${commits[$i]}"
  gh release view "v${v}" --json tagName,name,publishedAt,url >/dev/null
  actual="$(git ls-remote origin "refs/tags/v${v}" | awk '{print $1}')"
  test "$actual" = "$c"
  assets="$(gh release view "v${v}" --json assets --jq '.assets[].name')"
  grep -qx "Wheelchair-${v}.zip" <<<"$assets"
  grep -qx "Wheelchair-${v}.zip.sha256" <<<"$assets"
done

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
rm -f .github/workflows/release-timeline-1.3.111.yml .github/release-timeline-1.3.111.sh
rmdir .github/workflows 2>/dev/null || true
git add -A .github
git commit -m 'Complete release timeline through 1.3.111'
git push origin HEAD:main
