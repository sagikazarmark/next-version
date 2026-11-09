# next-version

GitHub Action that picks the next version from a repository's tags. It bumps the latest `vX.Y.Z`
tag by `patch`, `minor` or `major`, or checks an exact version you pass. It refuses a version that
is already a tag, and by default one that is not newer than the latest.

It reads the tags through the GitHub API, so it needs no checkout and no `fetch-depth: 0`.

## Usage

```yaml
on:
  workflow_dispatch:
    inputs:
      bump:
        type: choice
        options: [patch, minor, major]
        default: patch
      version:
        description: Exact version, vX.Y.Z (overrides bump)
        type: string

jobs:
  release:
    runs-on: ubuntu-latest

    permissions:
      contents: write

    steps:
      - name: Pick the version
        id: version
        uses: sagikazarmark/next-version@v1
        with:
          bump: ${{ inputs.bump }}
          version: ${{ inputs.version }}

      - name: Release
        env:
          GH_TOKEN: ${{ github.token }}
          VERSION: ${{ steps.version.outputs.version }}
        run: gh release create "$VERSION" --repo "$GITHUB_REPOSITORY" --generate-notes
```

The first release counts from `v0.0.0`, so `patch` gives `v0.0.1`. Pass `version: v0.1.0` (or any
other) to start elsewhere.

### Which tags count

Only tags of the form `vX.Y.Z` count as releases: `v` in lowercase, no leading zeros, no
prerelease or build part. The latest release is the highest of them by
[semantic versioning](https://semver.org), not the most recent or the last alphabetically.
Prerelease tags (`v1.0.0-rc.1`) never count as the latest, and other tags are ignored. Every tag,
of whatever form, counts when checking that the version does not exist yet.

### Release an older version

A patch to an older minor version, say `v1.4.3` after `v1.5.0`, is older than the latest. Allow it
with `require-newer: false`:

```yaml
- uses: sagikazarmark/next-version@v1
  id: version
  with:
    version: v1.4.3
    require-newer: false
```

It still must not exist. Publish it without marking it the Latest release, so that tools following
the latest release stay on `v1.5.0`, and start its release notes at the version before it:

```sh
gh release create "$VERSION" --latest="$MAKE_LATEST" --notes-start-tag "$PREVIOUS" --generate-notes
```

with `MAKE_LATEST` and `PREVIOUS` set from the `make-latest` and `previous` outputs. `previous` is
empty when there is no older version; drop `--notes-start-tag` then.

### Release a prerelease

Exact versions may have a prerelease part with `allow-prerelease: true`:

```yaml
- uses: sagikazarmark/next-version@v1
  id: version
  with:
    version: v2.0.0-rc.1
    allow-prerelease: true
```

Bumps always give a release, never a prerelease. A prerelease must be newer than the latest
release (so `v1.5.0-rc.1` after `v1.5.0` fails unless `require-newer` is false), and its
`make-latest` output is always `false`; publish it with `gh release create --prerelease`. Its
`previous` output includes prereleases, so the notes for `v2.0.0-rc.2` start at `v2.0.0-rc.1`,
while those for `v2.0.0` start at the release before it.

## Inputs

| Name | Description | Default |
| --- | --- | --- |
| `bump` | `patch`, `minor` or `major`. Ignored when `version` is set. | `patch` |
| `version` | Exact version, `vX.Y.Z` (or `vX.Y.Z-PRERELEASE` with `allow-prerelease`). Overrides `bump`. | `""` |
| `require-newer` | Require the version to be newer than the latest `vX.Y.Z` tag. | `true` |
| `allow-prerelease` | Allow an exact version with a prerelease part. | `false` |
| `repository` | The repository whose tags to read, `owner/name`. | The current repository |
| `token` | Token for reading the tags. | `github.token` |

## Outputs

| Name | Description |
| --- | --- |
| `version` | The version. |
| `latest` | The latest `vX.Y.Z` tag, or `v0.0.0` without one. |
| `make-latest` | `true` when the version is a release newer than every `vX.Y.Z` tag, so it should be marked the Latest release (`gh release create --latest`, the API's `make_latest`). |
| `prerelease` | `true` when the version has a prerelease part. |
| `previous` | Where its release notes start: the highest tag below the version (only `vX.Y.Z` tags for a release, prereleases too for a prerelease). Empty without one. |

## Run it locally

`pick.sh` reads the tags from stdin, one per line, and takes the inputs as environment variables
(`BUMP`, `VERSION`, `REQUIRE_NEWER`, `ALLOW_PRERELEASE`):

```sh
git tag --list | BUMP=minor ./pick.sh
gh api --paginate repos/OWNER/REPO/tags --jq '.[].name' | VERSION=v1.4.3 REQUIRE_NEWER=false ./pick.sh
```

It prints the result, and writes the outputs to `$GITHUB_OUTPUT` when that is set. Run the tests
with `./pick_test.sh`; they need only bash (3.2 or newer).

## License

`semver` is [semver-tool](https://github.com/fsaintjacques/semver-tool) 3.4.0, vendored unmodified
and licensed under the
[Apache License 2.0](https://github.com/fsaintjacques/semver-tool/blob/3.4.0/LICENSE).
