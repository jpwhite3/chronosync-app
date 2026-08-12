# Continuous Integration

GitHub Actions is the authoritative clean-room verification environment for
ChronoSync. Pull requests and pushes to `main` run the product CI and security
workflows. Merge-queue commits and manual dispatches use the same definitions.

## Required CI Gate

The `CI` workflow runs independent jobs so a platform failure is easy to
identify and unrelated work can proceed in parallel:

| Check | What it verifies |
| --- | --- |
| Repository checks | Workflow syntax and immutable action pins, Make recipes, and whitespace. |
| Flutter checks | Locked packages, generated files, formatting, analyzer, VM and Chrome tests, coverage, and a sanitized web release build. |
| Relay checks | Locked npm install, high-severity dependency audit, strict TypeScript checks, and Vitest. |
| Native iOS simulator build and tests | Unsigned simulator build and native `RunnerTests`. |
| Native Mac release build | Branding outputs, native tests, release build, signature, sandbox, and entitlements. |
| CI required | Stable aggregate result used by `main` protection. |

Coverage is retained for 14 days. Failed Apple test jobs retain their
`.xcresult` bundle for seven days. Product binaries are deliberately not
published: production identifiers, signing, URLs, and release environments are
not configured yet.

## Security and Dependencies

The `Security` workflow runs CodeQL for the TypeScript relay on pull requests,
`main`, merge-queue commits, and every Monday. Pull requests also receive a
dependency review that rejects newly introduced high-severity vulnerabilities
in supported manifests. GitHub secret scanning, push protection, and Dependabot
security updates are enabled at repository level. `Security required` is the
stable aggregate result used by `main` protection.

`.github/dependabot.yml` opens grouped weekly update pull requests for Flutter,
npm, and GitHub Actions. All workflow actions are pinned to full commit SHAs;
Dependabot updates the version comments and pins together.

## Reproduce CI Locally

Use the same entry points before opening a pull request:

```sh
make workflow-check                 # Action syntax and immutable pins
make ci                             # Repository, Flutter/web, and relay gates
make ci-native \
  RELAY_URL=https://relay.example.com \
  WEB_URL=https://app.example.com   # Apple builds and native tests
make branding-assets-check          # Requires ImageMagick and librsvg
```

`make workflow-check` uses Ruby's YAML parser, runs regression tests for pin
enforcement, and downloads a checksum-verified actionlint binary when it is not
installed. CI installs only lockfile-resolved app and relay packages. Hosted CI
also collects Flutter coverage and checks the complete pushed or pull-request
diff; locally, `make test-coverage` produces the equivalent coverage file.

## Permissions and Secrets

Verification workflows have read-only repository access. The CodeQL job alone
can upload security results. Checkout credentials are not persisted, and the
repository permits only GitHub-owned actions with repository-wide full-SHA
enforcement. A local composite action installs the exact Flutter revision from
the `3.41.9` release tag and verifies its commit before use; its GitHub-owned
cache dependency is also SHA-pinned. No CI secrets are required.

Keep Cloudflare credentials and Apple signing material out of these workflows.
When deployment is ready, use separate workflows with protected GitHub
environments, scoped secrets, manual approval, and the release checklist in
[Release Guide](release.md).

## Diagnosing a Failure

Open the failed job and start with its first failing step. Download coverage or
`.xcresult` artifacts from the run summary when present. A generated-source or
packaged-client mismatch must be fixed by regenerating and committing the
derived file; do not weaken the check. See [Troubleshooting](troubleshooting.md)
for platform-specific recovery steps.
