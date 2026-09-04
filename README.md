# Auto-healing web tier on Azure

A containerised static page served from a VM Scale Set behind a Standard Load
Balancer. Any single instance can be destroyed without the site going down, and
the platform rebuilds it without intervention.

## What it builds

| Resource | Name |
|---|---|
| Resource group | `rg-autoheal-dev-aue-001` |
| VNet / subnet | `vnet-autoheal-dev-aue-001` / `snet-web-autoheal-dev-aue-001` |
| NSG | `nsg-web-autoheal-dev-aue-001` |
| Public IP (zone-redundant) | `pip-autoheal-dev-aue-001` |
| Load balancer (Standard) | `lb-autoheal-dev-aue-001` |
| Scale set | `vmss-autoheal-dev-aue-001` |
| Autoscale setting | `autoscale-autoheal-dev-aue-001` |

Naming is `{type}-{workload}-{env}-{loc}-{instance}`, derived from
`local.suffix`. Change `workload` or `environment` and every resource follows.

## How the healing actually works

Two mechanisms, because there are two different failures and each one only
covers its own:

| Failure | Covered by | Behaviour |
|---|---|---|
| Instance running but **unhealthy** (container crashed, nginx erroring) | `automatic_instance_repair` | LB probe marks it down; platform deletes and recreates it |
| Instance **deleted** (`az vmss delete-instances`, or a zone failure) | Autoscale `minimum` | Capacity drops below minimum; autoscale creates a replacement |

This distinction matters and is easy to get wrong. A scale set does **not**
automatically replace an instance you delete — deleting reduces its capacity,
and it is content at the lower number. Only the autoscale minimum pulls it back
up. Equally, autoscale is blind to an instance that is running but serving
errors; only the repair policy sees that. You need both.

The load balancer probe is the shared health signal: it decides which instances
get traffic *and* which ones the platform rebuilds.

## Prerequisites

- Terraform ≥ 1.9, Azure CLI, Docker
- A Docker Hub account (free tier is fine)
- An SSH key pair — `ssh-keygen -t ed25519` if you need one

## Deploy

**1. Build and push the image.** It must be public; cloud-init pulls without
credentials.

```bash
cd docker

docker build -t YOUR_DOCKERHUB_USER/autoheal-web:1.0.0 .
docker login
docker push YOUR_DOCKERHUB_USER/autoheal-web:1.0.0
```

Use a real version tag. With `:latest`, a replacement instance created next
month can pull different content from the instances beside it, and you get a
load-balanced tier serving two different pages.

**2. Configure and apply.**

```bash
cd ../terraform
cp input.tfvars.example input.tfvars
# edit: tenant_id, subscription_id, container_image, admin_ssh_public_key

az login
terraform init
terraform apply -var-file=input.tfvars
```

**3. Wait ~3 minutes** for cloud-init to install Docker and pull the image, then:

```bash
curl "$(terraform output -raw site_url)"
```

Instances are in the backend pool immediately but fail the probe until the
container is up, so an early curl gets a connection reset rather than a page.

### Idempotency

A second `terraform apply -var-file=input.tfvars` makes no changes. The one thing that would otherwise
break this is autoscale changing `instances` behind Terraform's back — handled
by `ignore_changes = [instances]` on the scale set. Without it, every plan after
a scale event shows a diff and every apply fights the autoscaler.

## Proving it heals

**Kill an instance:**

```bash
RG=$(terraform output -raw resource_group_name)
VMSS=$(terraform output -raw scale_set_name)

az vmss list-instances -g "$RG" -n "$VMSS" -o table
az vmss delete-instances -g "$RG" -n "$VMSS" --instance-ids 0
```

Then, in another terminal, watch the site stay up throughout:

```bash
while true; do curl -s -o /dev/null -w "%{http_code} " "$(terraform output -raw site_url)"; sleep 1; done
```

You should see an unbroken run of `200`s — the surviving instance carries the
traffic. Within a few minutes autoscale notices capacity is below minimum and
builds a replacement.

**Break the app instead of the VM** — this exercises the repair policy rather
than autoscale:

```bash
az vmss run-command invoke -g "$RG" -n "$VMSS" --instance-id 1 \
  --command-id RunShellScript --scripts "systemctl stop web-container"
```

The probe fails, the LB stops sending it traffic, and after the grace period the
platform rebuilds the instance.

## Pipeline

`.github/workflows/ci.yml` — **plan only, never applies.**

| Job | Does |
|---|---|
| `lint` | `terraform fmt -check -recursive`, `tflint`, `hadolint` |
| `validate` | `terraform init -backend=false`, `terraform validate` |
| `docker-build` | Builds the image and smoke-tests that it serves on 80 |
| `plan` | Azure OIDC login, `terraform plan` |

`validate` runs with `-backend=false` so it needs no credentials and works on
fork PRs. `plan` is skipped rather than failed when secrets are unavailable.

Repository settings needed for `plan`: secrets `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC federated credential, no client
secret), and variables `CONTAINER_IMAGE`, `ADMIN_SSH_PUBLIC_KEY`.

## Design notes

**Standard SKU load balancer provides no implicit outbound internet access.**
This is the most common way this design fails on first apply: without the
explicit `azurerm_lb_outbound_rule`, instances cannot reach Docker Hub,
cloud-init never pulls the image, and every instance comes up unhealthy —
looking like a scale set problem when it is a networking one. A NAT Gateway is
the sturdier choice at real scale (much larger SNAT port budget); the outbound
rule is used here because it costs nothing on top of the load balancer.

**The container runs under systemd, not `docker run` from `runcmd`.** cloud-init
executes only on first boot, so a container started there would not survive a VM
reboot. `--restart=always` covers a crashed container but not a rebooted host.

**HTTP probe, not TCP.** A TCP probe passes as soon as something is listening on
80 — including an nginx returning 500s. The distinction is the difference
between healing and cheerfully load-balancing across broken instances.

**`grace_period = PT10M`** must exceed cloud-init's runtime (apt, Docker install,
image pull — typically 60–90s). Set it too short and the platform kills
instances that were seconds from becoming healthy, forever.

**Rolling upgrade mode** applies changes a batch at a time, gated on the probe.
An image that fails to start takes out one batch, not the whole tier.

## Cost

Sized for a demo, not for load. Approximate Australia East monthly cost:

| Item | ~AUD/month |
|---|---|
| 2 × `Standard_B1s` (1 vCPU / 1 GiB) | 23 |
| Standard Load Balancer | 27 |
| Standard public IP (static) | 6 |
| 2 × 30 GB StandardSSD OS disk | 7 |
| **Total** | **~63** |

Where the money goes, and what can't be reduced:

- **`Standard_B1s`** is the cheapest size that comfortably runs Docker plus an
  nginx container. `B1ls` (0.5 GiB) is cheaper but leaves almost no headroom —
  an OOM during cloud-init shows up as an instance that never becomes healthy,
  which is a miserable thing to debug for a few dollars.
- **The load balancer is unavoidable.** Basic SKU was free but was retired in
  September 2025, so Standard is the only option. It's the single largest line
  item and there is no cheaper way to satisfy the n+1 requirement.
- **`instance_count_max = 3`**, not higher, so a runaway scale-out can't quietly
  multiply the bill.
- `Standard_LRS` (HDD) OS disks would save ~AUD 3/month but boot noticeably
  slower, which lengthens healing time. Set `os_disk_type` if you want it.

If this is on an **Azure free account**, the 750 free B1s hours/month for the
first 12 months covers roughly one instance continuously — so the compute half
of the bill may be near zero.

**The real saving is not leaving it running.** Bring it up, take the evidence
you need, tear it down:

```bash
terraform destroy -var-file=input.tfvars
```

At ~AUD 2/day, a stack left running for a forgotten month costs more than the
whole exercise is worth.

## Not included

Deliberately out of scope for a demo, and what you would add for production:

- TLS. The page is HTTP only. Real deployments front this with Application
  Gateway or Front Door and terminate TLS there.
- Remote state. Local state is fine for one operator; anything shared needs the
  azurerm backend (commented in `providers.tf`) for locking.
- A private image registry. Docker Hub public means anyone can pull the image —
  fine for a static page, wrong for anything with content in it.
- Log aggregation and alerting on repair events.
