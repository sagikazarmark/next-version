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
tags="v0.9.0 v0.10.0 v0.9.1 v0.2.0 latest foo 1.0.0 V2.0.0 v1.0.0-rc.1 v1.0.0-rc.2 v3.0.0+build vv4.0.0"

# Bumps
ok "first release, patch" "" "version=0.0.1 tag=v0.0.1 latest=v0.0.0 make-latest=true previous=" BUMP=patch
ok "first release, minor" "" "version=0.1.0 tag=v0.1.0 latest=v0.0.0 make-latest=true" BUMP=minor
ok "first release, major" "" "version=1.0.0 tag=v1.0.0 latest=v0.0.0 make-latest=true" BUMP=major
ok "patch from the semver-latest tag" "$tags" \
  "version=0.10.1 tag=v0.10.1 latest=v0.10.0 make-latest=true prerelease=false previous=v0.10.0" BUMP=patch
ok "minor" "$tags" "version=0.11.0 tag=v0.11.0 latest=v0.10.0" BUMP=minor
ok "major ignores prereleases" "$tags" "version=1.0.0 tag=v1.0.0 latest=v0.10.0 previous=v0.10.0" BUMP=major
ok "version overrides bump" "$tags" "version=0.12.0 tag=v0.12.0" BUMP=major VERSION=v0.12.0
fails "unknown bump" "$tags" "bump must be patch, minor or major" BUMP=huge
fails "no bump and no version" "$tags" "bump must be patch, minor or major"

# Exact versions
ok "first release, exact" "" "version=0.1.0 tag=v0.1.0 make-latest=true previous=" VERSION=v0.1.0
ok "exact, newer" "$tags" "version=2.0.0 tag=v2.0.0 make-latest=true previous=v0.10.0" VERSION=v2.0.0
ok "exact, without the tag prefix" "$tags" "version=2.0.0 tag=v2.0.0 make-latest=true previous=v0.10.0" \
  VERSION=2.0.0
for version in V1.2.3 vv1.2.3 v01.2.3 v1.2 v1.2.3+build "v1.2.3 " v foo; do
  fails "invalid version '$version'" "$tags" "version must be X.Y.Z (with or without the tag prefix, v;" \
    "VERSION=$version"
done

# Existing tags
fails "existing release" "$tags" "v0.10.0 already exists" VERSION=v0.10.0
fails "existing release, without the tag prefix" "$tags" "v0.10.0 already exists" VERSION=0.10.0
fails "existing release, allowing everything" "$tags" "v0.9.1 already exists" \
  VERSION=v0.9.1 REQUIRE_NEWER=false ALLOW_PRERELEASE=true
fails "existing prerelease" "$tags" "v1.0.0-rc.2 already exists" \
  VERSION=v1.0.0-rc.2 ALLOW_PRERELEASE=true

# Older versions
fails "older" "$tags" "v0.9.2 is older than the latest release tag, v0.10.0; set require-newer" VERSION=v0.9.2
ok "older, require-newer off" "$tags" "version=0.9.2 tag=v0.9.2 make-latest=false previous=v0.9.1" \
  VERSION=v0.9.2 REQUIRE_NEWER=false
ok "older than every tag, require-newer off" "$tags" "version=0.1.0 make-latest=false previous=" \
  VERSION=v0.1.0 REQUIRE_NEWER=false
fails "older, require-newer on" "$tags" "older than the latest release tag" \
  VERSION=v0.9.2 REQUIRE_NEWER=true
fails "older, require-newer empty is the default, on" "$tags" "older than the latest release tag" \
  VERSION=v0.9.2 REQUIRE_NEWER=

# Prereleases
fails "prerelease" "$tags" "set allow-prerelease (ALLOW_PRERELEASE) to true" VERSION=v1.0.0-rc.3
ok "prerelease, allowed" "$tags" \
  "version=1.0.0-rc.3 tag=v1.0.0-rc.3 latest=v0.10.0 make-latest=false prerelease=true previous=v1.0.0-rc.2" \
  VERSION=v1.0.0-rc.3 ALLOW_PRERELEASE=true
ok "first prerelease" "" \
  "version=0.1.0-alpha tag=v0.1.0-alpha make-latest=false prerelease=true previous=" \
  VERSION=v0.1.0-alpha ALLOW_PRERELEASE=true
fails "prerelease with build metadata" "$tags" \
  "version must be X.Y.Z or X.Y.Z-PRERELEASE (with or without the tag prefix, v)" \
  VERSION=v1.0.0-rc.3+build ALLOW_PRERELEASE=true
fails "prerelease of a released version" "$tags" "older than the latest release tag" \
  VERSION=v0.10.0-rc.1 ALLOW_PRERELEASE=true
ok "release after its prereleases starts its notes at the previous release" "$tags" \
  "version=1.0.0 make-latest=true prerelease=false previous=v0.10.0" VERSION=v1.0.0

# Tag prefixes: only tags with the prefix count, and the version is what follows it.
prefixed="core-v0.1.0 core-v0.2.0-rc.1 core-v0.1.1 v0.9.0 0.8.0 app-v0.5.0 core-vv0.7.0 core-0.6.0"
ok "custom prefix, bump" "$prefixed" \
  "version=0.2.0 tag=core-v0.2.0 latest=core-v0.1.1 make-latest=true previous=core-v0.1.1" \
  BUMP=minor TAG_PREFIX=core-v
ok "custom prefix, exact with the prefix" "$prefixed" "version=0.3.0 tag=core-v0.3.0" \
  VERSION=core-v0.3.0 TAG_PREFIX=core-v
ok "custom prefix, exact without it" "$prefixed" "version=0.3.0 tag=core-v0.3.0" \
  VERSION=0.3.0 TAG_PREFIX=core-v
ok "custom prefix, prerelease notes" "$prefixed" \
  "version=0.2.0-rc.2 tag=core-v0.2.0-rc.2 prerelease=true previous=core-v0.2.0-rc.1" \
  VERSION=0.2.0-rc.2 ALLOW_PRERELEASE=true TAG_PREFIX=core-v
ok "custom prefix, first release" "v1.0.0 2.0.0" \
  "version=0.0.1 tag=core-v0.0.1 latest=core-v0.0.0 previous=" BUMP=patch TAG_PREFIX=core-v
fails "custom prefix, existing" "$prefixed" "core-v0.1.1 already exists" VERSION=0.1.1 TAG_PREFIX=core-v
fails "custom prefix, another prefix" "$prefixed" \
  "version must be X.Y.Z (with or without the tag prefix, core-v;" VERSION=v0.3.0 TAG_PREFIX=core-v
ok "custom prefix is literal, not a pattern" "a.b1.0.0 axb2.0.0" \
  "version=1.0.1 tag=a.b1.0.1 latest=a.b1.0.0" BUMP=patch TAG_PREFIX=a.b
ok "empty prefix" "1.0.0 v2.0.0 1.1.0-rc.1" "version=1.0.1 tag=1.0.1 latest=1.0.0 previous=1.0.0" \
  BUMP=patch TAG_PREFIX=
ok "empty prefix, first release" "v1.0.0" "version=0.1.0 tag=0.1.0 latest=0.0.0 previous=" \
  BUMP=minor TAG_PREFIX=
fails "empty prefix, a v" "1.0.0" "version must be X.Y.Z (without a tag prefix;" VERSION=v1.0.1 TAG_PREFIX=
ok "prefix ending in a digit, version as it is" "11.0.0" "version=1.2.3 tag=11.2.3 latest=11.0.0" \
  VERSION=1.2.3 TAG_PREFIX=1 REQUIRE_NEWER=false
ok "prefix ending in a digit, a version is never stripped" "" "version=11.2.3 tag=111.2.3" \
  VERSION=11.2.3 TAG_PREFIX=1
ok "prefix ending in a digit, with the prefix" "x11.0.0" "version=1.2.3 tag=x11.2.3 latest=x11.0.0" \
  VERSION=x11.2.3 TAG_PREFIX=x1

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
if [[ "$out" == "version=0.2.1" ]]; then pass; else fail "last tag without a newline" "expected version=0.2.1"; fi

echo "$passed passed, $failed failed"
[[ $failed == 0 ]]
