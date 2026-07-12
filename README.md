# GCP Reference Build — Standard Platform Engineering Project

## What's in here

```
terraform/
  modules/
    vpc/                 custom VPC, private subnets, Cloud NAT, firewall rules
    iam/                 service accounts, Workload Identity bindings, custom role
    artifact-registry/   image repo, cleanup policy, Binary Authorization + attestor
    gke/                 regional cluster (public mode, see below), VPC-native, Dataplane V2
    secret-manager/      secrets + per-workload IAM bindings
    monitoring/          alert policies, notification channel, dashboard
  envs/dev/              wires all modules together for one environment
app/                     Flask app: /healthz, /readyz, Secret Manager read, structured logs
helm/flask-app/          Deployment, Service, HPA, NetworkPolicy, Workload Identity KSA
cloudbuild/
  cloudbuild-pr.yaml      PR validation: build -> test -> scan (no deploy)
  cloudbuild-deploy.yaml  full pipeline: build -> test -> scan -> attest -> deploy
  TRIGGERS.md             branch policy + trigger setup (two files, two triggers)
policies/                Gatekeeper constraint: non-root + resource limits required
```

## The request path, end to end

1. Developer pushes to a feature branch, opens a PR against `main`.
2. GitHub branch protection requires the `pr-validation` Cloud Build trigger to
   pass before merge is allowed — build, test, Trivy scan. No deploy.
3. PR merges to `main` → `main-deploy` trigger fires → build, test, scan,
   **attest** (Binary Authorization signs the image), pauses for manual
   approval, then deploys via Helm to GKE.
4. GKE's Binary Authorization admission controller checks the image has a
   valid attestation before letting the pod schedule — an unattested image
   is rejected at the cluster boundary even if someone tries to `kubectl apply`
   it directly, bypassing the pipeline entirely.
5. Pod starts with a dedicated Kubernetes ServiceAccount bound via Workload
   Identity to a GCP service account that can read exactly two secrets and
   write logs/metrics — nothing else.
6. Cloud Logging and Managed Prometheus collect logs/metrics automatically
   from GKE's built-in `logging_config`/`monitoring_config`; alert policies
   fire to email on crash loops, latency SLO breach, or readiness failures.

## Networking, explained at a glance

- **VPC is global, subnets are regional** — global VPC
- **VPC-native (alias IP) GKE**: every Pod gets a, routable IP from the
  `pods` secondary range, every Service gets one from `services`. 
- **Public cluster**: nodes and the control plane both have
  public IPs, deliberately, so `kubectl`/`helm` can be done locally
  without a bastion while testing. Control plane access is still restricted
  to `authorized_network_cidr`, the Cloud NAT and Cloud Router the private 
  mode needs are already in the VPC
  module regardless of which mode you're in, so switching back is a
  small, contained change.
- **Private Google Access** on the subnet lets nodes reach Artifact Registry,
  Secret Manager, Cloud Logging etc. over Google's internal network, never
  touching the public internet even though there's no NAT rule written for
  those specific destinations.
- **Dataplane V2 + NetworkPolicy**: default-deny between pods, explicit allow
  rules only - same zero-trust posture as the VPC's deny-all-ingress firewall,
  just enforced one layer up at the pod level.

## IAM, explained at a glance

- **Hierarchy**: Organization → Folder → Project → Resource. This project only
  touches the Project level.
- **One service account per workload**, never a shared "deploy-everything" SA.
  Look at `terraform/modules/iam/main.tf`, `cloudbuild-deployer` can push
  images, deploy to GKE, and read secrets. It **cannot** create IAM bindings,
  delete resources, or touch anything outside this project.
- **Workload Identity** is the mechanism that lets a specific Kubernetes Pod
  (identified by namespace + KSA name) impersonate a specific GCP SA, with zero
  credential files ever touching disk.
- **Custom role example** (`releaseApprover`): shows a role build having the narrowest one that does the
  job rather than reaching for a predefined role that's "close enough."

## Storage used in this build

- **Artifact Registry** - container images (see artifact-registry module).
- **GCS bucket** - Terraform remote state (`backend "gcs"` in `envs/dev/main.tf`).
- **Secret Manager** - manages secrets



