# ------------------------------------------------------------------------------
# Generic private endpoint factory.
#
# One module call creates any number of private endpoints from a map, each
# with an optional DNS zone group. Keeping this generic avoids repeating the
# private_service_connection boilerplate in every service module and lets
# environments decide which services are privately addressed.
# ------------------------------------------------------------------------------

resource "azurerm_private_endpoint" "this" {
  for_each = var.endpoints

  name                = "${var.name_prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name_prefix}-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = each.value.subresource_names
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(each.value.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = each.value.private_dns_zone_ids
    }
  }
}
