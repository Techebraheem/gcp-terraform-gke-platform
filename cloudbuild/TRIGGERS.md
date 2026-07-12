# Cloud Build Triggers & Branch Policy Setup

The pipeline is split into two files - `cloudbuild-pr.yaml` and `cloudbuild-deploy.yaml`
- rather than one file with conditional logic. Simpler to reason about, and the
service-account difference between the two IS the actual security boundary
(see the comment at the bottom of each file).

## Two triggers, two files

### Trigger 1: `pr-validation`
- **Event**: Pull request against `main`
- **Config file**: `cloudbuild/cloudbuild-pr.yaml`
- **Steps run**: build, test, push (to a `pr-<number>` tag, never `latest`), trivy-scan
- **Service account**: Cloud Build's default identity - deliberately has no
  deploy or attest permissions, so even a misconfigured trigger can't deploy
- **Comment control**: "Require comment before build" ON for PRs from forks (prevents
  someone opening a malicious PR to run arbitrary code in your build environment -
  this is a real supply-chain vector, not paranoia)

### Trigger 2: `main-deploy`
- **Event**: Push to `main` (i.e., after a PR is merged)
- **Config file**: `cloudbuild/cloudbuild-deploy.yaml`
- **Steps run**: build, test, push, scan, attest, deploy
- **Service account**: `cloudbuild-deployer` - the only identity in this
  project with `roles/container.developer` and Binary Authorization signing
  permission
- **Approval**: enable "Require approval" on the trigger. This pauses the build
  before it starts (not just before deploy) and requires a user with the
  `releaseApprover` custom role (see terraform/modules/iam) to click approve in
  the console or run `gcloud builds approve`. 

## GitHub branch protection (the actual "branch policy" enforcement)

In GitHub repo settings -> Branches -> branch protection rule for `main`:
- Require a pull request before merging (no direct pushes to main)
- Require status checks to pass before merging -> select the `pr-validation`
  Cloud Build check
- Require branches to be up to date before merging
- Require at least 1 approving review
- Do not allow bypassing the above settings (applies rule to admins too)