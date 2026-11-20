# Proposal: PR-Based Promotion, Release Tags and Controlled Releases

## Decision requested

We ask approval to run a proof of concept (PoC) that replaces cherry-pick with pull-request promotion and tag-based releases, and to request the GitHub settings it needs from IT.

**Problem today.** Cherry-picking copies commits by hand between branches. It creates duplicate commits, misses commits easily and leaves no approval record. Because `sit` and `uat` hold several features at once, nobody can say with certainty what will reach production.

**The proposal in one rule.** Production receives exactly one tested feature, built from `main`, and `main` moves only after production succeeds.

- Developers open one PR, into `dev`. Automation opens every later PR, and each merges only when its checks and approvals pass.
- After UAT, a release branch `release/<feature>` is cut from `main` with that one feature. Alpha and prod deploy from tags on it, through the existing Jenkins.
- Regression at alpha follows a risk-based policy. Skipping it is allowed only as a recorded exception.
- `main` is updated only after prod is deployed and stable with no rollback.
- Every step is protected by reviews, approvals, protected branches and tags, and least-privilege automation.

**Result.** An audit trail for every promotion, no missed commits, and no way for features B and C to reach production by accident.

**Decisions needed.** Approve the PoC, confirm the roles under Roles and approvals, and agree the requests under IT requests.

## Process flow

A feature moves through nine steps. Only the first is manual work for the developer, and every later step is gated by GitHub rules.

&#91;embedded content: process flow · feature branch to production, with main updated last\]

Features A and B enter through `dev` and are tested in `sit`. B's promotion PR into `uat` stays open until QA approves it, so only A is cut into a release branch that alpha and prod run.

| # | Step | Owner | What happens | Gate |
| --- | --- | --- | --- | --- |
| 1 | Build | Developer | Pushes the feature branch from the IDE and opens a PR into `dev` | CI green, 1 peer review |
| 2 | Integrate | Automation | Jenkins deploys `dev` on push | None |
| 3 | QA test | Automation, QA | A PR into `sit` opens and merges once approved; Jenkins deploys `sit` | CI green, 1 approval |
| 4 | UAT | QA team | After QA passes in `sit`, a PR into `uat` opens; Jenkins deploys `uat` | Checklist ticked, CI green, QA team approval |
| 5 | Release branch | Automation | `release/<feature>` is cut from `main` and a PR brings in that one feature | Checklist ticked, CI green, QA team approval |
| 6 | Alpha | Release owner, QA | An rc tag on the release branch deploys alpha (pre-production). Jenkins runs the automation suite, QA tests by risk, and the result is recorded as the `regression` status | Tag rules, regression policy |
| 7 | Prod | Release owner, prod reviewer | The final tag on the same commit deploys prod. A recorded skip replaces the regression status | Prod reviewer approves; `regression` is success, or a recorded skip |
| 8 | Main | Release owner | After prod succeeds, a PR from the release branch into `main` is approved once prod is stable | No rollback; successful prod deployment; only `release/*` may merge |
| 9 | Sync | Automation | A PR from `main` into `dev`, `sit` and `uat` stops drift | Merge commit, normal approvals |

## Security and compliance controls

Every promotion is gated by controls that GitHub enforces, so the process does not depend on people remembering the rules. Availability of some settings depends on our GitHub Enterprise version and plan, which IT must confirm.

| Control | What it prevents | How |
| --- | --- | --- |
| Branch rulesets | Direct pushes, unreviewed code, force pushes | Require a PR, approvals, code owner review and status checks on `dev`, `sit`, `uat`, `release/**`, `main`; merge commits only ([rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)) |
| Approval from someone other than the last pusher | An author approving their own latest change | Turn on the option in the pull request rule ([rules](https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)) |
| Code owners on pipeline files | Weakening the controls through a normal PR | Make the platform team the code owner of `.github/workflows/` and deployment config |
| Deployment must succeed before merge | `main` changing before prod is live | Ruleset rule "Require deployments to succeed before merging" with `prod`; not available in organization-level rulesets ([rules](https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)). To validate in the PoC |
| Environment protection | Unreviewed prod deployments, exposed prod secrets | `prod` requires up to six named reviewers; its secrets are released only after approval ([environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)) |
| Regression sign-off | A release reaching prod without recorded testing | The final tag needs a `regression` status of success on the release commit. Manual results go through a workflow in the `qa-signoff` environment, approved by the QA team |
| Tag rulesets | Unauthorised release tags and forged skip-regression tags | Only the release owner may create `v*` tags; rulesets can target tags ([API](https://docs.github.com/en/rest/repos/rules)) |
| Least-privilege automation | A compromised workflow doing more than it should | Each workflow declares minimal `permissions`; the default token is read-only ([guidance](https://docs.github.com/en/actions/reference/security/secure-use)) |
| Pinned actions | Supply-chain attack through a hijacked action tag | Pin third-party actions to a full commit SHA and enforce it with the "Require actions to be pinned" setting ([setting](https://docs.github.com/en/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization)) |
| Secrets handling | Secret leaks and over-broad access | Anyone with write access can read repository secrets, so keep prod secrets as environment secrets behind reviewers, and rotate them ([guidance](https://docs.github.com/en/actions/reference/security/secure-use)) |
| Feature flag change control | Unreviewed flag changes in production | LaunchDarkly approvals per environment: required or not, number of approvals, and whether requesters may approve their own ([settings](https://launchdarkly.com/docs/home/releases/approvals-settings)) |

**Automation identity.** The workflow that opens PRs should run as a GitHub App or a service account with access to this repository only, not a person's token. The PoC uses a personal token only because it is a demo.

**Runners.** Calling the internal Jenkins needs a self-hosted runner. Keep it for private repositories only: on public repositories anyone who can open a PR may be able to attack it ([guidance](https://docs.github.com/en/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization)).

**Audit trail.** Pull requests, approvals, deployment history, GitHub Releases and tags together show who approved what, and when it reached each environment.

**Workflow hygiene.** The PoC workflows pass PR text through environment variables instead of inserting it into scripts, which avoids script injection.

## Testing and regression policy

`sit` and `uat` test feature A together with B and C, while alpha tests A alone on top of `main`. Regression at alpha closes that gap, and this policy sets how much regression each release needs. No process can guarantee that a release is defect-free; this one reduces the risk and records every decision.

**Where each kind of test runs**

| Layer | Owner | When it runs |
| --- | --- | --- |
| Unit and API tests for the change, front end and back end | Developer | On every PR, as the required `test` check |
| Back-end API tests for changed endpoints | Developer and QA | In the same CI run on PRs into `release/**` |
| Automated member-journey suite (front end, from the automation team) | Automation team | After the rc tag deploys to alpha: Jenkins runs it and reports a `regression` status on the release commit |
| Manual regression of the changed area | QA | At alpha, sized by risk. QA records the result with the sign-off workflow and an evidence link |
| Monitoring and rollback readiness | Developer and operations | After the prod deployment |

The journey suite covers the front end and reaches the back end only through the screens, so it does not replace back-end API tests. It needs a deployed environment, which is why it runs after alpha is deployed and not on the PR.

**Regression required at alpha, by risk**

| Situation | Required before the final tag |
| --- | --- |
| High risk: payments, member data, authentication, many users affected | Full manual regression plus the automated suites. No skipping. |
| Medium risk, journey suite covers the area | Automated suite passes, plus a short manual check of the changed area |
| Medium risk, no automation for the area | Time-boxed manual regression of the changed area from a checklist |
| Low risk or hotfix | Automated checks and developer tests pass. The QA lead may approve a recorded skip. |

**Rules**

1. The developer lists the affected areas in the PR, so testers check what changed instead of everything.
2. The final tag needs a `regression` status of success on the release commit. Jenkins posts it after the automated suite, or QA records it through the sign-off workflow with an evidence link, and a QA reviewer approves that record. The status belongs to one commit, so any new commit on the release branch must be tested again.
3. A skip is a tag whose message states the reason and names the QA lead who agreed. The prod reviewer must still approve.
4. If no automation exists for a feature, release is not blocked. The checklist asks for either new automation or linked manual test evidence, and missing automation becomes a backlog item.
5. The team reviews skipped and failed releases each month to adjust the risk rules.

## Feature flags with LaunchDarkly

LaunchDarkly flags are in use for the front end and stay front-end only: back-end flags are not planned. Flags therefore control who sees a screen, while the release branch keeps unreleased back-end work out of production.

|  | Today | Target |
| --- | --- | --- |
| Front end | LaunchDarkly flags decide which testers see which feature | Same, with flag state recorded in the release checklist |
| Back end | No flags | Not planned. Back-end changes are kept out of production by the release branch, not by flags |
| Changing flags in prod | Not controlled | Approval required per environment ([settings](https://launchdarkly.com/docs/home/releases/approvals-settings)) |
| Old flags | Not tracked | Each flag has an owner and is removed after full rollout |

**Rules**

1. A front-end flag hides a screen, not an API. The back end has no flags, so new endpoints and behaviour are live as soon as they are deployed to an environment. They must enforce their own access rules and stay backward compatible, and the release branch decides when they reach production.
2. Flags default to off in production. Risky features get a flag that can be switched off immediately.
3. Align flag state with the release. In alpha, only the flags for the feature being released are on, so alpha behaves like production will.
4. Prod flag changes need an approval from someone other than the requester.
5. Every flag has a ticket, an owner and a removal date.

**Why release branches stay.** Without back-end flags, a feature that changes back-end behaviour cannot be merged early and switched off. The release branch is what keeps features B and C out of production. If back-end flags are adopted later, this can be revisited.

## Roles and approvals

No single person can take a change from code to production. The author, the tester and the person releasing are different people, and GitHub enforces the split.

| Role | Does | Cannot |
| --- | --- | --- |
| Developer | Pushes the feature branch, opens the PR into `dev`, lists the affected areas | Approve their own PR, merge into `sit`, `uat`, `release/**` or `main` directly, create release tags |
| Peer reviewer | Approves PRs into `dev` and `sit` | Approve a PR they wrote or last pushed to |
| QA team (GitHub team) | Tests in `sit`, `uat` and alpha, ticks the checklist, approves PRs into `uat` and `release/**`, records regression results (a second QA member approves each record) | Change rulesets or pipeline files |
| QA lead | Agrees to a regression skip and is named in the tag message | Skip a high-risk release |
| Release owner | Creates rc and final tags, approves the PR into `main` once prod is stable | Approve the prod deployment of a tag they created |
| Prod reviewer | Approves the deployment in the `prod` environment | Create the tag they approve |
| Platform team | Owns workflows, rulesets and the automation identity. Their changes also go through a reviewed PR | Bypass the rulesets |
| Automation identity (GitHub App or service account) | Opens promotion PRs and turns on auto-merge | Approve anything. A PR merges only when the rules are met |

The principles behind this table are separation of duties and least privilege: each role gets only the access it needs, and anything sensitive needs a second person.

## Rollout, risks and mitigations

We move in three phases, and each phase starts only when the previous exit gate is met. No dates are set until the pilot team and IT confirm capacity.

&#91;embedded content: rollout · three phases with exit gates\]

The pilot also connects the automation suite through Jenkins. How Jenkins starts the automation team's script is worked out with that team during the pilot.

| Risk | Mitigation |
| --- | --- |
| The team resists the new PR habit | Pilot with one team, run the demo and a short training, and let automation remove the manual steps |
| `sit` and `uat` drift away from `main` | The sync workflow opens a PR from `main` into them after each release and weekly |
| Feature A depends on feature B | The PR template asks for dependencies, and dependent features are released together in one release branch |
| Only one release can sit in alpha at a time | The release owner keeps a queue and tags the next candidate when alpha is free |
| Regression is skipped too often | A skip needs the QA lead's name, high-risk releases cannot skip, and skips are reviewed monthly |
| The release branch conflicts with newer `main` changes | Conflicts appear in the PR into the release branch, before alpha, not at release time |
| A required GitHub setting is not on our plan | The PoC finds this early; fall back to manual checks for that control until IT enables it |
| GitHub cannot reach the internal Jenkins | Ask IT for a webhook route, or use a self-hosted runner that calls Jenkins |

## IT requests, open questions and PoC status

**Requests to IT** (each needs confirming against our GitHub Enterprise version and plan):

- Branch and tag rulesets with required reviews, status checks and code owner review, including the rule that requires a successful `prod` deployment before merging into `main`.
- A GitHub team for QA with Write access, and CODEOWNERS enabled.
- GitHub Actions enabled, "Allow auto-merge" on, and the setting that requires actions to be pinned to a commit SHA.
- A GitHub App or service account for the promotion automation.
- Environments with required reviewers: `prod` (prod reviewers) and `qa-signoff` (QA team), plus environment secrets for `prod`.
- A route from GitHub to the internal Jenkins (a webhook, or a self-hosted runner), and a Jenkins multibranch job that also builds tags.
- A Jenkins credential that can post a commit status named `regression` to the repository, limited to that permission.
- LaunchDarkly: approvals required for production flag changes.

**Decided**

- Alpha is the pre-production environment where testers repeat regression.
- `dev` and `sit` stay separate.
- The release branch is named `release/<feature>`.
- LaunchDarkly stays front-end only; back-end flags are not planned.

**Open questions**

- Who the release owner, QA lead and prod reviewers are. To be defined later.
- How Jenkins starts the front-end automation: it triggers the automation team's repository script, and the details are still to be worked out with that team.

**PoC status.** The [setup guide](https://claude.ai/artifact/CfXofe1DLfsR5QNEWhtfxK) has the click-by-click steps, the demo script and the workflow files (in the starter repository). The regression gate is now in the starter repository: the final tag needs a `regression` status on the release commit, posted by Jenkins or recorded by QA. The branch flow and tag checks were tested in a local Git repository and the workflows pass `actionlint`, but they have not yet run on GitHub. The "require deployments" rule is a ruleset setting that still has to be validated in the PoC.

**Sources**

- [GitHub: secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub: deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub: available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets) and the [Enterprise Cloud version](https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [GitHub: limiting Actions for an organization](https://docs.github.com/en/organizations/managing-organization-settings/disabling-or-limiting-github-actions-for-your-organization)
- [GitHub: rules REST API](https://docs.github.com/en/rest/repos/rules)
- [LaunchDarkly: approval request settings](https://launchdarkly.com/docs/home/releases/approvals-settings)
- [LaunchDarkly: SDK flag changes](https://launchdarkly.com/docs/sdk/features/flag-changes)
