# Cloud Build Triggers & Branch Policy Setup

This is the piece that doesn't live in Terraform-friendly resources cleanly (triggers
CAN be Terraform-managed via `google_cloudbuild_trigger`, but it's clearer to reason
about as a checklist first — set it up manually once, then codify it).

## Two triggers, one cloudbuild.yaml

### Trigger 1: `pr-validation`
- **Event**: Pull request against `main`
- **Included steps**: build, test, push (to a `pr-<number>` tag, not `latest`), trivy-scan
- **Excluded**: attest, deploy — a PR should never deploy
- **Comment control**: "Require comment before build" ON for PRs from forks (prevents
  someone opening a malicious PR to run arbitrary code in your build environment —
  this is a real supply-chain vector, not paranoia)

### Trigger 2: `main-deploy`
- **Event**: Push to `main` (i.e., after a PR is merged)
- **Runs**: full pipeline including attest + deploy
- **Approval**: enable "Require approval" on the trigger. This pauses the build
  before the `deploy` step and requires a human with the `releaseApprover` custom
  role (see terraform/modules/iam) to click approve in the console or run
  `gcloud builds approve`. This is your equivalent of an Azure DevOps
  environment approval gate.

## GitHub branch protection (the actual "branch policy" enforcement)

In GitHub repo settings -> Branches -> branch protection rule for `main`:
- Require a pull request before merging (no direct pushes to main)
- Require status checks to pass before merging -> select the `pr-validation`
  Cloud Build check
- Require branches to be up to date before merging
- Require at least 1 approving review
- Do not allow bypassing the above settings (applies rule to admins too)

This is the same governance outcome as your ADO branch policies + required
reviewers — GitHub enforces the human/process gate, Cloud Build enforces the
automated quality gate, and neither can be skipped by pushing straight to main.

## Why deploy is a separate trigger instead of a branch check in the same run

Keeping PR validation and deploy as two distinct triggers (rather than one trigger
with conditional steps) means:
- A flaky deploy step never blocks PR merges
- The deploy trigger's service account can have `container.developer` deploy
  permissions that the PR trigger's identity doesn't need at all — smaller
  blast radius if a PR-triggered build is ever compromised.
