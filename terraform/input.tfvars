# Real values. Gitignored — do not commit.
# Subscription: "Azure subscription 1"
#
#   terraform plan  -var-file=input.tfvars
#   terraform apply -var-file=input.tfvars
#
# Every root variable is set explicitly here, including ones that have defaults
# in variables.tf. Nothing about the deployed stack depends on a default you
# have to go and look up.

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------
tenant_id       = "c191dcf3-de85-46fb-9aea-f7023ed0e904"
subscription_id = "dfcbef8e-4484-4d0a-b066-b4b574751828"

# ---------------------------------------------------------------------------
# Naming — produces rg-autoheal-dev-aue-001, vmss-autoheal-dev-aue-001, ...
# ---------------------------------------------------------------------------
workload      = "autoheal"
environment   = "dev"
location      = "australiaeast"
location_code = "aue"
instance      = "001"

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------
owner       = "JRIJAL"
cost_centre = "personal"

# Merged over the defaults in locals.tf. Use for anything one-off.
extra_tags = {
  Purpose = "auto-healing web tier demo"
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
# 10.60.0.0/22 leaves room for app and data subnets alongside the web tier.
vnet_address_space = ["10.60.0.0/22"]
web_subnet_prefix  = "10.60.0.0/24"

# "Internet" makes the page public. Narrow to your own address if you would
# rather not publish it, e.g. "203.0.113.45/32"
allowed_http_source = "Internet"

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------
# TODO — set after `docker push`. Must be a PUBLIC Docker Hub repo, with an
# explicit version tag (validation rejects an untagged reference).
container_image = "docker.io/rijaljegam/autoheal-web:1.0.0"


# B1s hits "Capacity Restrictions" in australiaeast for this subscription.
# B2ats_v2 is the newer Basv2 family (x86-64 AMD, 2 vCPU / 1 GiB) with better
# capacity, and is cheaper than B2s at ~A$12/instance/month.
#
# NOT a Bpsv2 size — those are ARM64 (Ampere) and the container image is
# amd64 only, which would fail with an exec format error on an otherwise
# healthy-looking instance.
vm_sku       = "Standard_B2ats_v2"
os_disk_type = "StandardSSD_LRS"

# n+1: two instances means losing one still serves traffic. instance_count is
# also the autoscale MINIMUM, which is what rebuilds a deleted instance.
# Total Regional vCPU quota on this subscription is 4. At 2 vCPUs per B2s
# instance, 2 instances consumes the entire allowance — so max MUST be 2, or
# autoscale would attempt a scale-out that Azure rejects.
instance_count     = 2
instance_count_max = 2

# Standard_B2ats_v2 has zonal capacity in australiaeast (verified). The
# SkuNotAvailable problem was specific to Standard_B1s — do not generalise it
# to all B-series. Spreading across all three zones means a single zone outage
# leaves at least one instance serving.
#
# NOTE: zones cannot be changed in place. Editing this list destroys and
# recreates the scale set.
availability_zones = ["1", "2", "3"]

# Public IP zone redundancy — no compute capacity constraint applies here.
lb_frontend_zones = ["1", "2", "3"]

admin_username = "azureuser"

# TODO — paste the contents of your .pub file, not the path.
#   ssh-keygen -t ed25519 -C "autoheal" -f ~/.ssh/autoheal
#   cat ~/.ssh/autoheal.pub
admin_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDQk/W+5Vh1/9y7Z8iJLCw7P/FSoxZdWEJzFEFOgmVqZrEsXrArj4PDL2yc8rOd3Wwc5pAeYjR24zeX7j51V/x1xW9fRwiaFodEzKxs/JsxIXIcgdeViE/nFX2MIMaPyS1bSia49dzE0oKmRO4F9lh+FxPkMb/Lh4K4yACDBDl9mQdnxujFq//kiALJ08YGD2WssJQSnnWdmWKNxBbcu+4HupboYIlW0H1MN5uYpNoDfy5VMmPclys0nXq4VRJZKbjyEYceA/5Tb6HszmOcKbiuwrLoGyABxPY/GZ02PI2r84m0xxDGPh9kLd8f6wDH/fgJLNxSJ1tXqAbU2k3MYga9nN0sXtZOtCXJ/C7TJL+FRt49Irgqs/wk1OAU3UYBE58LHingw15veyaHU0DNpC5g/zZtUizQe5BljLAV4tCPROgw4fEp2GONC/WDqFpLrF+rQruS3fw1TCxJMLSBmn4yRkafcHOa2A61SnOOeMkSq7YbzO0yEpjOKA1R9NzBOcwGH3neR9DIByhnux4pVw6Skiu03PH+pawexMG8BY8h2tG+p70ZacQW+MWQU/eyAkgEnxy9ukhuYr7n71F1ManG1rz7IQGlGDJEMlAgNJAMyhxS3TGAahxKLm30RkYm5MetlztrR4eZ+dTm/ne9ISYWyS/K45hTSa5jyEVSdVGGUQ== azure-autoheal"
