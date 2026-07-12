# GCP Reference Build — Standard Platform Engineering Project

A deliberately "textbook-standard" GCP build, built to translate your Azure/AKS
production experience into GCP vocabulary and give you a concrete thing to
walk an interviewer through.

## What's in here

```
terraform/
  modules/
    vpc/                 custom VPC, private subnets, Cloud NAT, firewall rules
    iam/                 service accounts, Workload Identity bindings, custom role
    artifact-registry/   image repo, cleanup policy, Binary Authorization + attestor
    gke/                 private regional cluster, VPC-native, Dataplane V2
    secret-manager/      secrets + per-workload IAM bindings
    monitoring/          alert policies, notification channel, dashboard
  envs/dev/              wires all modules together for one environment
app/                     Flask app: /healthz, /readyz, Secret Manager read, structured logs
helm/flask-app/          Deployment, Service, HPA, NetworkPolicy, Workload Identity KSA
cloudbuild/
  cloudbuild.yaml        build -> test -> scan -> attest -> deploy pipeline
  TRIGGERS.md            branch policy + trigger setup (PR validation vs deploy)
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

- **VPC is global, subnets are regional** — the opposite of Azure's VNet model
  where the VNet itself is regional. Don't say "which region is the VPC in"
  in an interview; say "which region is the subnet in."
- **VPC-native (alias IP) GKE**: every Pod gets a real, routable IP from the
  `pods` secondary range, every Service gets one from `services`. This is the
  modern default — the old routes-based networking mode is deprecated for new
  clusters.
- **Private cluster**: nodes have no public IPs. Outbound internet (e.g. `pip
  install` during image build, OS patching) goes through Cloud NAT. Inbound
  admin access to the control plane is restricted to `authorized_network_cidr`
  — your equivalent of an Azure Firewall allow-list, but Google-managed.
- **Private Google Access** on the subnet lets nodes reach Artifact Registry,
  Secret Manager, Cloud Logging etc. over Google's internal network, never
  touching the public internet even though there's no NAT rule written for
  those specific destinations.
- **Dataplane V2 + NetworkPolicy**: default-deny between pods, explicit allow
  rules only — same zero-trust posture as the VPC's deny-all-ingress firewall,
  just enforced one layer up at the pod level.

## IAM, explained at a glance

- **Hierarchy**: Organization → Folder → Project → Resource. This project only
  touches the Project level, but be ready to say the words "org policy" and
  "folder-level constraints" if asked how you'd manage this across 50 projects.
- **One service account per workload**, never a shared "deploy-everything" SA.
  Look at `terraform/modules/iam/main.tf` — `cloudbuild-deployer` can push
  images, deploy to GKE, and read secrets. It **cannot** create IAM bindings,
  delete resources, or touch anything outside this project.
- **Workload Identity** is the mechanism that lets a specific Kubernetes Pod
  (identified by namespace + KSA name) impersonate a specific GCP SA, with zero
  credential files ever touching disk. This directly replaces the old
  "download a JSON key, mount it as a Secret" anti-pattern — if you see that
  pattern in an existing GCP environment, flagging it is a strong signal of
  seniority.
- **Custom role example** (`releaseApprover`): shows you understand roles are
  just named permission sets, and you build the narrowest one that does the
  job rather than reaching for a predefined role that's "close enough."

## Storage used in this build

- **Artifact Registry** — container images (see artifact-registry module).
- **GCS bucket** — Terraform remote state (`backend "gcs"` in `envs/dev/main.tf`).
  This needs to exist before first `terraform init`; create it once by hand
  or via a bootstrap script, since Terraform can't create the bucket it's
  about to store its own state in.
- **Secret Manager** — not technically "storage" in the disk sense, but it's
  the answer if asked "where do secrets live" — never in Terraform state,
  never in a ConfigMap, never in an env var baked into the image.

## Security controls, mapped to the job description's exact phrases

| JD phrase                     | What implements it here |
|--------------------------------|--------------------------|
| Secrets management             | Secret Manager + Workload Identity, CSI-driver-ready |
| Policy enforcement              | Binary Authorization (image-level) + Gatekeeper (config-level) |
| Vulnerability scanning          | Trivy in Cloud Build + Artifact Registry's built-in scanning |
| Least-privilege access controls | Per-workload SAs, custom role, default-deny NetworkPolicy |

## Deploying this for real

You'll need a GCP project with billing enabled (the free trial / $300 credit
covers this comfortably for a few days of testing).

```bash
# one-time: create the state bucket referenced in envs/dev/main.tf
gsutil mb -l us-central1 gs://YOUR-PROJECT-terraform-state
gsutil versioning set on gs://YOUR-PROJECT-terraform-state

cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars   # fill in your project ID, IP, etc.
terraform init
terraform plan
terraform apply

# get cluster credentials
gcloud container clusters get-credentials $(terraform output -raw cluster_name) \
  --region us-central1 --project YOUR-PROJECT

# deploy the app manually the first time (Cloud Build does this after)
helm install flask-app ../../../helm/flask-app -n flask-app --create-namespace
```

Tear it all down with `terraform destroy` when you're done experimenting —
GKE clusters and Cloud NAT aren't free-tier-eligible for long.

## How to use this for interview prep

Don't memorize this file. Instead, for each module, be able to answer out
loud: *"what would break if this weren't here, and how would I notice?"*
That's the question that separates "I copied a Terraform example" from
"I understand what a properly built platform looks like" — which is exactly
what this project was built to get you to.
