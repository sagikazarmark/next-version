#!/usr/bin/env bash
# Tests for pick.sh. Run: ./pick_test.sh
set -euo pipefail

pick="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pick.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

passed=0
failed=0

# run TAGS VAR=VALUE...: run pick.sh in a clean environment with TAGS (space-separated) on stdin,
# one per line; sets $status, $out (GITHUB_OUTPUT on one line) and $err (stderr).
run() {
  local tags="$1"
  shift
  : > "$work/output"
  status=0
  # shellcheck disable=SC2086 # split the tags
  printf '%s\n' $tags | env -i PATH="$PATH" GITHUB_OUTPUT="$work/output" "$@" bash "$pick" \
    > /dev/null 2> "$work/err" || status=$?
  out="$(tr '\n' ' ' < "$work/output")"
  err="$(cat "$work/err")"
}

pass() {
  passed=$((passed + 1))
}

fail() {
  failed=$((failed + 1))
  printf 'FAIL %s\n  %s\n  status: %s\n  output: %s\n  stderr: %s\n' "$1" "$2" "$status" "$out" "$err" >&2
}

# ok NAME TAGS "KEY=VALUE..." VAR=VALUE...: pick.sh succeeds and writes every KEY=VALUE.
ok() {
  local name="$1" tags="$2" expected="$3"
  shift 3
  run "$tags" "$@"
  if [[ $status != 0 ]]; then
    fail "$name" "expected success"
    return
  fi
  local pair
  for pair in $expected; do
    if [[ " $out" != *" $pair "* ]]; then
      fail "$name" "expected $pair"
      return
    fi
  done
  pass
}

# fails NAME TAGS MESSAGE VAR=VALUE...: pick.sh fails with MESSAGE on stderr and writes nothing.
fails() {
  local name="$1" tags="$2" message="$3"
  shift 3
  run "$tags" "$@"
  if [[ $status == 0 ]]; then
    fail "$name" "expected failure"
  elif [[ "$err" != *"$message"* ]]; then
    fail "$name" "expected stderr to contain: $message"
  elif [[ -n "$out" ]]; then
    fail "$name" "expected no output"
  else
    pass
  fi
}

# Releases, out of order, plus prereleases, build metadata and tags that are not versions.
tags="v0.9.0 v0.10.0 v0.9.1 v0.2.0 latest foo 1.0.0 V2.0.0 v1.0.0-rc.1 v1.0.0-rc.2 v3.0.0+build"

# Bumps
ok "first release, patch" "" "version=v0.0.1 latest=v0.0.0 make-latest=true previous=" BUMP=patch
ok "first release, minor" "" "version=v0.1.0 latest=v0.0.0 make-latest=true" BUMP=minor
ok "first release, major" "" "version=v1.0.0 latest=v0.0.0 make-latest=true" BUMP=major
ok "patch from the semver-latest tag" "$tags" \
  "version=v0.10.1 latest=v0.10.0 make-latest=true prerelease=false previous=v0.10.0" BUMP=patch
ok "minor" "$tags" "version=v0.11.0 latest=v0.10.0" BUMP=minor
ok "major ignores prereleases" "$tags" "version=v1.0.0 latest=v0.10.0 previous=v0.10.0" BUMP=major
ok "version overrides bump" "$tags" "version=v0.12.0" BUMP=major VERSION=v0.12.0
fails "unknown bump" "$tags" "bump must be patch, minor or major" BUMP=huge
fails "no bump and no version" "$tags" "bump must be patch, minor or major"

# Exact versions
ok "first release, exact" "" "version=v0.1.0 make-latest=true previous=" VERSION=v0.1.0
ok "exact, newer" "$tags" "version=v2.0.0 make-latest=true previous=v0.10.0" VERSION=v2.0.0
for version in 1.2.3 V1.2.3 v01.2.3 v1.2 v1.2.3+build "v1.2.3 " foo; do
  fails "invalid version '$version'" "$tags" "version must be vX.Y.Z" "VERSION=$version"
done

# Existing tags
fails "existing release" "$tags" "v0.10.0 already exists" VERSION=v0.10.0
fails "existing release, allowing everything" "$tags" "v0.9.1 already exists" \
  VERSION=v0.9.1 REQUIRE_NEWER=false ALLOW_PRERELEASE=true
fails "existing prerelease" "$tags" "v1.0.0-rc.2 already exists" \
  VERSION=v1.0.0-rc.2 ALLOW_PRERELEASE=true

# Older versions
fails "older" "$tags" "older than the latest release tag, v0.10.0; set require-newer" VERSION=v0.9.2
ok "older, require-newer off" "$tags" "version=v0.9.2 make-latest=false previous=v0.9.1" \
  VERSION=v0.9.2 REQUIRE_NEWER=false
ok "older than every tag, require-newer off" "$tags" "version=v0.1.0 make-latest=false previous=" \
  VERSION=v0.1.0 REQUIRE_NEWER=false
fails "older, require-newer on" "$tags" "older than the latest release tag" \
  VERSION=v0.9.2 REQUIRE_NEWER=true
fails "older, require-newer empty is the default, on" "$tags" "older than the latest release tag" \
  VERSION=v0.9.2 REQUIRE_NEWER=

# Prereleases
fails "prerelease" "$tags" "set allow-prerelease (ALLOW_PRERELEASE) to true" VERSION=v1.0.0-rc.3
ok "prerelease, allowed" "$tags" \
  "version=v1.0.0-rc.3 latest=v0.10.0 make-latest=false prerelease=true previous=v1.0.0-rc.2" \
  VERSION=v1.0.0-rc.3 ALLOW_PRERELEASE=true
ok "first prerelease" "" "version=v0.1.0-alpha make-latest=false prerelease=true previous=" \
  VERSION=v0.1.0-alpha ALLOW_PRERELEASE=true
fails "prerelease with build metadata" "$tags" "version must be vX.Y.Z or vX.Y.Z-PRERELEASE" \
  VERSION=v1.0.0-rc.3+build ALLOW_PRERELEASE=true
fails "prerelease of a released version" "$tags" "older than the latest release tag" \
  VERSION=v0.10.0-rc.1 ALLOW_PRERELEASE=true
ok "release after its prereleases starts its notes at the previous release" "$tags" \
  "version=v1.0.0 make-latest=true prerelease=false previous=v0.10.0" VERSION=v1.0.0

# Flags
fails "REQUIRE_NEWER not a boolean" "$tags" "require-newer (REQUIRE_NEWER) must be true or false" \
  BUMP=patch REQUIRE_NEWER=yes
fails "ALLOW_PRERELEASE not a boolean" "$tags" "allow-prerelease (ALLOW_PRERELEASE) must be true or false" \
  BUMP=patch ALLOW_PRERELEASE=1

# Input: the last tag counts without a trailing newline.
status=0
out="$(printf 'v0.1.0\nv0.2.0' | env -i PATH="$PATH" GITHUB_OUTPUT=/dev/stdout BUMP=patch \
  bash "$pick" 2> "$work/err" | grep '^version=')" || status=$?
err="$(cat "$work/err")"
if [[ "$out" == "version=v0.2.1" ]]; then pass; else fail "last tag without a newline" "expected version=v0.2.1"; fi

echo "$passed passed, $failed failed"
[[ $failed == 0 ]]
