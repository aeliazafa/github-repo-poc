# PoC: PR-based promotion and release tags

Demo repository for replacing cherry-pick with pull requests and tag-based releases.
Everything here is dummy content. Do not add company code, hostnames or secrets.

## Flow

```
feature/A --PR--> dev --auto PR--> sit --auto PR--> uat --auto PR--> release/A  (= main + feature A only)
feature/B --PR--> dev --auto PR--> sit                 (B's PR into uat waits for QA approval)

release/A --tag v1.0.0-rc.1--> alpha (regression test) --tag v1.0.0--> prod (reviewer approves)
prod succeeded and stable, no rollback --PR--> main
```

The developer opens only the first PR (feature into `dev`). The same feature branch is promoted at
every later step. Alpha and prod are built from the release branch, never from `sit` or `uat`, so
features B and C cannot reach production by accident. `main` always matches what is live in prod.

Regression gate: the final tag needs a `regression` = success status on the release branch tip, posted by
Jenkins after the automation suite or by QA through `record-regression.yml`.

Skipping regression: tag the release branch tip with an annotated tag whose message has a line
`SKIP-REGRESSION: <reason>`, e.g. `git tag -a v1.0.1 -m "SKIP-REGRESSION: urgent fix, QA lead agreed"`.
The prod environment reviewer still has to approve, and the warning shows on the workflow run.

## Files

| Path | Purpose |
| --- | --- |
| `.github/workflows/ci.yml` | Runs `tests/check.sh` on PRs and pushes. Job `test` is a required check. |
| `.github/workflows/pr-checklist.yml` | Blocks PRs into `uat` and `release/*` until the checklist is ticked. |
| `.github/workflows/record-regression.yml` | QA records a manual regression result as the `regression` commit status (needs approval in the `qa-signoff` environment). |
| `.github/workflows/main-source-guard.yml` | Only a `release/*` branch may be merged into `main`. |
| `.github/workflows/promote-next.yml` | Opens the next PR (dev to sit, sit to uat, uat to `release/<feature>`) and enables auto-merge. |
| `.github/workflows/sync-main-back.yml` | PR from `main` into `dev`, `sit`, `uat` after each release and weekly, to stop drift. |
| `.github/workflows/deploy-branch.yml` | Mock Jenkins deploy on push to `dev`, `sit`, `uat`. |
| `.github/workflows/release.yml` | Tag on a release branch: `-rc` deploys alpha, final tag deploys prod (mocked), then opens the PR into `main`. |
| `.github/CODEOWNERS` | QA team must approve. |
| `.github/promotion-checklist.md` | Checklist pasted into every auto-opened PR. |
| `.github/pull_request_template.md` | Template for developer PRs. |
| `docs/jenkins-notes.md` | How the real Jenkins would be connected. |

Follow the setup guide document for the click-by-click steps.
