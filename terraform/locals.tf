locals {
  # {type}-{workload}-{env}-{loc}-{instance} — every resource name derives from
  # this suffix, so changing workload or environment renames the whole stack
  # consistently instead of leaving stragglers behind.
  suffix = "${var.workload}-${var.environment}-${var.location_code}-${var.instance}"

  tags = merge(
    {
      Workload    = var.workload
      Environment = var.environment
      Owner       = var.owner
      CostCentre  = var.cost_centre
      ManagedBy   = "Terraform"
      Repository  = "azure-autoheal-web"
    },
    var.extra_tags,
  )
}
