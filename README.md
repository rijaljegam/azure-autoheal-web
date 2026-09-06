# Auto-healing web tier on Azure

A containerised static page served from a VM Scale Set behind a Standard Load
Balancer. **Any single instance can be destroyed without the site going down,
and the platform rebuilds it without intervention.**

Built with Terraform, deployed to Azure, container published on Docker Hub.

| Requirement | How it is met |
|---|---|
| **Self-healing** — terminating an instance triggers automatic replacement | Autoscale minimum + `automatic_instance_repair`, both driven by the load balancer health probe |
| **Self-provisioning IaC** — one command up, a second run changes nothing | `terraform apply -var-file=input.tfvars`; idempotency protected by `ignore_changes = [instances]` |
| **n+1 capacity** — traffic spread across ≥2 instances behind a load balancer | 2 instances minimum (validated), Standard Load Balancer with HTTP probe |
| **Static web page** | nginx serving a custom `index.html` |
| **Containerised, pulled at boot** | Dockerfile → public Docker Hub → cloud-init pulls and runs it via systemd |
| **Modules, variables, tagging, naming** | Three modules; `{type}-{workload}-{env}-{loc}-{nnn}`; tags from one merged local |
| **Pipeline: lint / validate / plan-only** | GitHub Actions — nothing in it applies |

---

## How to test this

Three levels, depending on whether you have Docker or an Azure subscription to
hand.

### 1. Check the code — no Azure account, no credentials, ~30 seconds

```bash
git clone https://github.com/rijaljegam/azure-autoheal-web.git
cd azure-autoheal-web/terraform

terraform init -backend=false
terraform validate
terraform fmt -check -recursive
```

Expected:

```
Terraform has been successfully initialized!
Success! The configuration is valid.
```

`-backend=false` skips state entirely and never authenticates the provider, so
nothing here touches Azure. `fmt -check` exits non-zero and names any file that
isn't canonically formatted — silence means clean.

### 2. Check the container — Docker only, ~1 minute

```bash
docker run --rm -d --name web -p 8080:80 rijaljegam/autoheal-web:1.0.0
sleep 2 && curl -s http://localhost:8080 | head -5
docker stop web
```

That is the published image the VMs pull. To build it yourself instead:

```bash
cd docker && docker build -t autoheal-web:test .
```

### 3. Deploy it — your own Azure subscription, ~10 minutes, ~AUD 2/day

Nothing from this repo's author is needed. You deploy into your own
subscription, using the public container image.

`terraform/input.tfvars` is committed with working values for everything.
Change **three**:

| Variable | Set it to |
|---|---|
| `tenant_id` | `az account show --query tenantId -o tsv` |
| `subscription_id` | `az account show --query id -o tsv` |
| `admin_ssh_public_key` | Contents of your `.pub` file — not a path, and must be `ssh-rsa` |

```bash
cd terraform

# Open input.tfvars and set the three values above
nano input.tfvars        # or vi / code / notepad

az login --tenant <your-tenant-id>
terraform init

# Always plan first — read it before creating anything
terraform plan -var-file=input.tfvars
```

The plan should report **14 to add, 0 to change, 0 to destroy**. A leftover
placeholder is caught here by variable validation rather than part-way through
an apply. Once it looks right:

```bash
terraform apply -var-file=input.tfvars # not required only if you would like to apply a real infra

curl "$(terraform output -raw site_url)"      # allow ~3 min for cloud-init
```

An early `curl` returning a connection reset is normal — instances join the
backend pool before Docker has finished pulling the image, so the probe fails
until the container is serving.

Then run the healing tests below, which are the part actually worth executing.
**Tear it down when you are finished:**

```bash
terraform destroy -var-file=input.tfvars
```

> Resource names are scoped per subscription, so deploying alongside someone
> else is fine. Two stacks in the **same** subscription need different
> `instance` values (`001`, `002`, …) to avoid clashes.

---

## What it builds

| Resource | Name |
|---|---|
| Resource group | `rg-autoheal-dev-aue-001` |
| Virtual network | `vnet-autoheal-dev-aue-001` (`10.60.0.0/22`) |
| Subnet | `snet-web-autoheal-dev-aue-001` (`10.60.0.0/24`) |
| Network security group | `nsg-web-autoheal-dev-aue-001` |
| Public IP | `pip-autoheal-dev-aue-001` — Standard, zone-redundant |
| Load balancer | `lb-autoheal-dev-aue-001` — Standard SKU |
| Scale set | `vmss-autoheal-dev-aue-001` — 2 × `Standard_B2ats_v2` |
| Autoscale setting | `autoscale-autoheal-dev-aue-001` |

Naming is `{type}-{workload}-{env}-{loc}-{instance}`, derived from a single
`local.suffix`. Change `workload` or `environment` in `input.tfvars` and every
resource follows consistently.

Tags applied to everything: `Workload`, `Environment`, `Owner`, `CostCentre`,
`ManagedBy`, `Repository`, plus anything in `extra_tags`.

## Architecture

```
                              Internet
                                 │
                                 │  HTTP :80
                                 ▼
                   ┌─────────────────────────────┐
                   │  pip-autoheal-dev-aue-001   │  Standard SKU, static
                   │  Public IP, zone-redundant  │
                   └──────────────┬──────────────┘
                                  │
                   ┌──────────────▼──────────────┐
                   │  lb-autoheal-dev-aue-001    │  Standard LB — layer 4
                   │                             │
                   │  rule      :80 → :80        │  forwards traffic
                   │  probe     HTTP GET /       │  ── the health signal ──┐
                   │  outbound  SNAT (all ports) │  egress for image pulls │
                   └──────────────┬──────────────┘                         │
                                  │                                        │
  ┌───────────────────────────────┴─────────────────────────────────┐      │
  │  vnet-autoheal-dev-aue-001            10.60.0.0/22              │      │
  │                                                                 │      │
  │  ┌───────────────────────────────────────────────────────────┐  │      │
  │  │  snet-web-autoheal-dev-aue-001        10.60.0.0/24         │  │      │
  │  │  nsg-web: allow :80 Internet + AzureLoadBalancer, deny all │  │      │
  │  │                                                            │  │      │
  │  │   ┌──────────────────────┐    ┌──────────────────────┐     │  │      │
  │  │   │  instance 0          │    │  instance 1          │     │  │      │
  │  │   │  Ubuntu 24.04        │    │  Ubuntu 24.04        │     │  │      │
  │  │   │   └ Docker Engine    │    │   └ Docker Engine    │     │  │      │
  │  │   │      └ nginx :80     │    │      └ nginx :80     │     │  │      │
  │  │   │  (systemd-managed)   │    │  (systemd-managed)   │     │  │      │
  │  │   └──────────────────────┘    └──────────────────────┘     │  │      │
  │  │                                                            │  │      │
  │  │            vmss-autoheal-dev-aue-001  (no public IPs)      │  │      │
  │  └───────────────────────────────────────────────────────────┘  │      │
  └─────────────────────────────────────────────────────────────────┘      │
                                  │                                        │
                   ┌──────────────▼──────────────┐                         │
                   │  Self-healing               │◄────────────────────────┘
                   │                             │   both driven by the probe
                   │  autoscale  min 2 / max 2   │   → rebuilds DELETED instances
                   │  instance_repair  PT10M     │   → rebuilds UNHEALTHY instances
                   └─────────────────────────────┘

  Egress (cloud-init → Docker Hub):
    instance → LB outbound rule → SNAT via public IP → docker.io
    A Standard LB provides NO implicit outbound. Without that rule the image
    pull fails and every instance comes up unhealthy.
```

## Repository layout

```
azure-autoheal-web/
├── docker/
│   ├── Dockerfile              nginx:1.27-alpine + index.html
│   └── index.html
├── terraform/
│   ├── providers.tf            azurerm ~> 4.0, local backend
│   ├── variables.tf            all root inputs, with validation
│   ├── locals.tf               naming suffix and tag set
│   ├── main.tf                 wiring only — no resource blocks
│   ├── outputs.tf
│   ├── input.tfvars            all values, explicitly set
│   └── modules/
│       ├── network/            vnet, subnet, NSG
│       ├── loadbalancer/       public IP, LB, probe, rules, outbound SNAT
│       └── web_vmss/           scale set, cloud-init, autoscale
└── .github/workflows/ci.yml    lint / validate / docker-build / plan
```

`main.tf` contains no `resource` blocks — every resource lives in a module, and
the root file is wiring. Every root variable is set explicitly in
`input.tfvars`, including ones with defaults, so the deployed configuration is
readable in one place rather than spread between two files.

---

## How the healing actually works

Two mechanisms, because there are two different failures and each one only
covers its own:

| Failure | Covered by | Behaviour |
|---|---|---|
| Instance running but **unhealthy** — container crashed, nginx erroring, disk full | `automatic_instance_repair` | Probe marks it down; platform deletes and recreates it |
| Instance **deleted** — `az vmss delete-instances`, or a zone failure | Autoscale `minimum` | Capacity drops below minimum; autoscale creates a replacement |

**This distinction is the crux, and it is easy to get wrong.** A scale set does
*not* automatically replace an instance you delete — deleting **decrements its
capacity**, and the scale set is then perfectly content at the lower number.
Only the autoscale minimum pulls it back up. Equally, autoscale is blind to an
instance that is running but serving errors; only the repair policy sees that.

Implement one and you have a tier that either shrinks permanently when someone
deletes an instance, or cheerfully load-balances across broken ones. You need
both.

The load balancer probe is the shared health signal: it decides which instances
receive traffic **and** which ones the platform rebuilds.

### Timing

Healing restores redundancy; it does not prevent the loss. Throughout, the
surviving instance keeps serving — that is the n+1 requirement doing its job.

| Step | Typical |
|---|---|
| Probe detects failure | ~10s (5s interval × 2 probes) |
| Autoscale notices capacity below minimum | ~1 min |
| Instance boot + cloud-init + image pull | 2–3 min |
| **Total** | **3–5 min** |

Azure deliberately will *not* repair if too much of the scale set is unhealthy
at once. That is protective — it stops a bad image triggering a rebuild loop
across every instance — but it means a total outage does not self-heal, by
design.

## Proving it heals

**Test 1 — delete an instance.** Exercises the autoscale minimum.

In one terminal, watch the site:

```bash
URL=$(terraform output -raw site_url)
while true; do printf '%s ' "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL")"; sleep 2; done
```

In another, kill one:

```bash
RG=$(terraform output -raw resource_group_name)
VMSS=$(terraform output -raw scale_set_name)

az vmss list-instances -g "$RG" -n "$VMSS" -o table
az vmss delete-instances -g "$RG" -n "$VMSS" --instance-ids 0
```

Expect an **unbroken run of `200`s** while the instance count goes 2 → 1 → 2.

Azure's own record of the replacement:

```bash
az monitor activity-log list -g "$RG" --offset 1h \
  --query "[?contains(operationName.value, 'autoscale')].{time:eventTimestamp, op:operationName.localizedValue}" \
  -o table
```

**Test 2 — break the app, not the VM.** Exercises `automatic_instance_repair`.

```bash
az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id 1 \
  --command-id RunShellScript --scripts "systemctl stop web-container"
```

The probe fails, the load balancer stops sending it traffic, and after the
grace period the platform rebuilds the instance.

## Idempotency

A second `terraform apply -var-file=input.tfvars` reports **no changes**.

The one thing that would otherwise break this is autoscale changing the instance
count behind Terraform's back. Handled with:

```hcl
lifecycle {
  ignore_changes = [instances]
}
```

Without it, every plan after a scale event shows a diff and every apply fights
the autoscaler.

---

## Prerequisites

**To deploy:**

- Terraform ≥ 1.9 and the Azure CLI
- An Azure subscription with at least 4 vCPUs of regional quota
- An SSH key pair. Azure's `admin_ssh_key` requires **`ssh-rsa`**:

  ```bash
  ssh-keygen -t rsa -b 4096 -m PEM -C "azure-autoheal" -f ~/.ssh/autoheal -N ""
  ```

**Not required:** Docker, or a Docker Hub account. The image is already
published at `docker.io/rijaljegam/autoheal-web:1.0.0` and is the default in
`input.tfvars`.

### Publishing your own image — optional

```bash
cd docker
docker build -t YOUR_DOCKERHUB_USER/autoheal-web:1.0.0 .
docker login
docker push YOUR_DOCKERHUB_USER/autoheal-web:1.0.0
```

The repository must be **public** — cloud-init performs an unauthenticated
pull, and a private repo means every instance comes up unhealthy with no
obvious cause on the Azure side.

Use a real version tag. With `:latest`, a replacement instance created next
month can pull different content from the instances beside it, leaving a
load-balanced tier serving two different pages.

---

## Pipeline

`.github/workflows/ci.yml` — **plan only. Nothing in it applies.**

| Job | Does | Needs credentials |
|---|---|---|
| `lint` | `terraform fmt -check -recursive`, `tflint`, `hadolint` | No |
| `validate` | `terraform init -backend=false`, `terraform validate` | No |
| `docker-build` | Builds the image and smoke-tests that it serves on port 80 | No |
| `plan` | Azure OIDC login, `terraform plan` | Yes |

Triggered manually (`workflow_dispatch`) only — there is no shared branch to
protect here. Add a `pull_request:` trigger to make it a required status check.

> **`plan` does not run in this repository as published.** It needs a federated
> identity credential in Azure, which is specific to whoever owns the
> subscription — so it cannot be shipped with the code. `lint`, `validate` and
> `docker-build` run and pass without any setup.
>
> To run `plan` yourself: fork or clone the repo, create a FIC against **your**
> subscription using the commands below, add the three repository secrets, and
> trigger the workflow. It takes about five minutes.

### `plan` requires a federated identity credential in Azure

`plan` authenticates with OIDC, so no client secret is stored in GitHub — but
Azure must be told to trust this repository. Without a **federated identity
credential (FIC)** on the app registration, `azure/login` fails with
`AADSTS70021: No matching federated identity record found`. GitHub mints the
token happily; Azure refuses to exchange it.

```bash
SUB=<your-subscription-id>
GH=<owner>/<repo>

az ad app create --display-name sp-gh-autoheal
APP_ID=$(az ad app list --display-name sp-gh-autoheal --query "[0].appId" -o tsv)
az ad sp create --id "$APP_ID"

# Reader is sufficient — this pipeline plans, it never applies
az role assignment create --assignee "$APP_ID" --role Reader --scope "/subscriptions/$SUB"

az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"gh-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"repo:${GH}:ref:refs/heads/main\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}"
```

The `subject` must match the workflow's trigger context **exactly**. This
workflow is `workflow_dispatch` from `main`, so it is `ref:refs/heads/main`. A
FIC created for `pull_request` will not match, and the resulting error names
neither the subject nor the mismatch.

Then set repository secrets `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`. None is a credential — they are identifiers. That is
the point of OIDC: nothing to leak, nothing to rotate. The workflow also needs
`permissions: id-token: write`, which is already set.

**What the plan actually shows.** State is local, so a CI runner starts with
none and reports every resource as a create even when the stack is deployed. It
demonstrates the configuration is valid and plannable, not a live delta. For a
real delta the azurerm backend — commented in `providers.tf` — would be needed.

---

## Assumptions

Stated explicitly, because several are the reason something looks simpler than
it would be in production.

**Scope**

- A single region. No cross-region DR. Losing Australia East loses the site.
- HTTP only. A Standard Load Balancer is layer 4 and cannot terminate TLS, so
  real HTTPS means Application Gateway or Front Door.
- The page is public and unauthenticated. That is the requirement, not an
  oversight.
- The workload is **stateless**. Nothing on an instance is worth keeping, which
  is what makes destroy-and-replace a valid healing strategy. This design would
  be actively dangerous for anything holding data.

**Environment**

- The container image is **public** on Docker Hub. A private registry would
  need a pull secret or a managed identity against ACR.
- Terraform state is **local**, on one operator's machine. Fine for a
  single-operator demo; anything shared needs the azurerm backend for locking.
- The stack is short-lived and destroyed after review.

**Constraints hit during this deployment** — recorded because they shaped the
final configuration:

- The subscription has a **4 vCPU regional quota**. At 2 vCPUs per instance
  that is exactly two instances, so `instance_count_max = 2` and the autoscale
  *scale-out* rule cannot fire. The autoscale **minimum** still provides
  instance replacement, which is what the brief requires.
- `Standard_B1s` returned **SkuNotAvailable / Capacity Restrictions** in
  Australia East, both zonally and regionally. Moved to `Standard_B2ats_v2`.
- The `SkuNotAvailable` result above was specific to `Standard_B1s`, not to
  B-series generally. `Standard_B2ats_v2` does have zonal capacity in Australia
  East, so `availability_zones = ["1", "2", "3"]` and instances are spread
  across all three zones. The load balancer frontend is zone-redundant to
  match. Note that `zones` cannot be changed in place — moving between zonal
  and regional allocation destroys and recreates the scale set.
- No inbound SSH. Instances have no public IPs and the NSG permits port 80
  only, so `admin_ssh_public_key` is a required input that cannot be used for
  access. Debugging is via `az vmss run-command invoke` and the serial console.

## Design notes

**A Standard SKU load balancer provides no implicit outbound internet access.**
The most common way this design fails on a first apply: without the explicit
`azurerm_lb_outbound_rule`, instances cannot reach Docker Hub, cloud-init never
pulls the image, and every instance comes up unhealthy — looking like a scale
set problem when it is a networking one. Worse than neutral: adding a VM to a
Standard LB backend pool *removes* the default outbound access it would
otherwise have had. A NAT Gateway is sturdier at real scale; the outbound rule
is used here because it costs nothing on top of the load balancer.

**The container runs under systemd, not `docker run` from `runcmd`.** cloud-init
executes only on first boot, so a container started there would not survive a
reboot. `--restart=always` covers a crashed container but not a rebooted host.

**HTTP probe, not TCP.** A TCP probe passes as soon as something is listening
on port 80 — including an nginx returning 500s. That distinction is the
difference between healing and cheerfully load-balancing across broken
instances.

**`grace_period = PT10M`** must exceed cloud-init's runtime (apt, Docker
install, image pull — typically 60–90s). Set it too short and the platform
kills instances that were seconds from becoming healthy, forever.

**Rolling upgrade mode** applies changes a batch at a time, gated on the probe.
An image that fails to start takes out one batch, not the whole tier.

**The scale set depends on the whole load balancer module.** Azure rejects a
probe as a VMSS `health_probe_id` unless a load balancing *rule* already
references that probe (`CannotUseInactiveHealthProbe`). Passing the pool and
probe IDs alone lets Terraform create the scale set in parallel with the rule,
and it loses the race — on a fresh apply only.

**`resource_provider_registrations = "none"`.** The provider otherwise attempts
to register ~60 resource providers on every run, which times out on a fresh
subscription. This stack needs three: `Microsoft.Network`, `Microsoft.Compute`,
`Microsoft.Insights`.

---

## Cost

Sized for a demo, not for load. Australia East, list price, excluding GST:

| Item | Qty | ~AUD/month |
|---|---|---|
| `Standard_B2ats_v2` (2 vCPU / 1 GiB) | 2 | 25 |
| Standard Load Balancer (2 rules, low data) | 1 | 27 |
| Standard public IP, static | 1 | 6 |
| 30 GB StandardSSD OS disk | 2 | 7 |
| Autoscale setting, NSG, VNet, subnet | — | 0 |
| **Total** | | **~65** |

Roughly **AUD 2.15/day**, or **AUD 0.09/hour** while it exists.

Everything here bills **hourly on existence, not usage** — an idle stack costs
the same as a busy one. The load balancer is the largest line item and cannot
be reduced: Basic SKU was free but was retired in September 2025, so Standard
is the only option.

```bash
terraform destroy -var-file=input.tfvars
```

## Not included

Deliberately out of scope, and what production would add:

- **TLS.** HTTP only. Real deployments front this with Application Gateway or
  Front Door and terminate TLS there.
- **Remote state.** Local state is fine for one operator; anything shared needs
  the azurerm backend for locking and durability.
- **A private registry.** Docker Hub public means anyone can pull the image —
  fine for a static page, wrong for anything with content in it.
- **Log aggregation and alerting.** No Log Analytics workspace, and no alert on
  repair events, so a tier quietly healing itself every hour would go unnoticed.
- **Outbound restriction.** Instances can reach any internet destination. A
  tightened egress policy would need a private registry and an apt mirror to be
  practical.
