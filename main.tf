data "azurerm_client_config" "current" {}

resource "random_string" "unique" {
  length  = 4
  lower   = true
  numeric = false
  special = false
  upper   = false
}

data "http" "icanhazip" {
  url = "https://ipv4.icanhazip.com/"
}

####################################################################################################
#                                                                                                  #
# Resource Group                                                                                   #
#                                                                                                  #
####################################################################################################

data "azurerm_resource_group" "rg" {
  name = var.existing_rg
}

####################################################################################################
#                                                                                                  #
# Network                                                                                          #
#                                                                                                  #
####################################################################################################

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space = [
    var.virtual_network_address_space
  ]

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_subnet" "subnet_agent" {
  name                 = "snet-agent-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    var.agent_subnet_address_prefix
  ]
  delegation {
    name = "Microsoft.App/environments"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

resource "azurerm_subnet" "subnet_pe" {
  name                 = "snet-pe-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    var.private_endpoint_subnet_address_prefix
  ]
}

resource "azurerm_subnet" "subnet_jump" {
  name                 = "snet-jump-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [
    var.jump_subnet_address_prefix
  ]
}

resource "azurerm_network_security_group" "nsg_pe" {
  name                = "nsg-snet-pe-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association_pe" {
  subnet_id                 = azurerm_subnet.subnet_pe.id
  network_security_group_id = azurerm_network_security_group.nsg_pe.id
}

resource "azurerm_network_security_group" "nsg_agent" {
  name                = "nsg-snet-agent-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
resource "azurerm_subnet_network_security_group_association" "nsg_association_agent" {
  subnet_id                 = azurerm_subnet.subnet_agent.id
  network_security_group_id = azurerm_network_security_group.nsg_agent.id
}

resource "azurerm_network_security_group" "nsg_jump" {
  name                = "nsg-snet-jump-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowRDPInbound"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = chomp(data.http.icanhazip.response_body)
    destination_address_prefix = "*"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association_jump" {
  subnet_id                 = azurerm_subnet.subnet_jump.id
  network_security_group_id = azurerm_network_security_group.nsg_jump.id
}

####################################################################################################
#                                                                                                  #
# Storage                                                                                          #
#                                                                                                  #
####################################################################################################

resource "azurerm_storage_account" "storage_account" {
  name                            = "sa${var.geo_short}${random_string.unique.result}${var.env_name}ai"
  resource_group_name             = data.azurerm_resource_group.rg.name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  network_rules {
    bypass         = ["AzureServices"]
    default_action = "Deny"
    ip_rules       = ["${chomp(data.http.icanhazip.response_body)}"]
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_storage_container" "storage_container_ragdata" {
  name                  = "ragdata"
  storage_account_id    = azurerm_storage_account.storage_account.id
  container_access_type = "private"
}

resource "azurerm_cosmosdb_account" "cosmosdb" {
  name                = "cosmos${var.geo_short}${random_string.unique.result}${var.env_name}ai"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name

  offer_type        = "Standard"
  kind              = "GlobalDocumentDB"
  free_tier_enabled = false

  local_authentication_enabled  = false
  public_network_access_enabled = false

  automatic_failover_enabled       = false
  multiple_write_locations_enabled = false

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = false
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_key_vault" "key_vault" {
  name                       = "kv-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location                   = data.azurerm_resource_group.rg.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = ["${chomp(data.http.icanhazip.response_body)}"]
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "random_password" "password_aiadmin" {
  special = true
  length  = 16
}

resource "azurerm_key_vault_secret" "key_vault_secret_aiadmin" {
  name         = "aiadmin-password"
  value        = random_password.password_aiadmin.result
  key_vault_id = azurerm_key_vault.key_vault.id

  depends_on = [time_sleep.wait_after_key_vault_secrets_officer_role_applied]
}

resource "time_sleep" "wait_after_key_vault_secrets_officer_role_applied" {
  create_duration = "60s"

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer_me]
}

####################################################################################################
#                                                                                                  #
# AI                                                                                               #
#                                                                                                  #
####################################################################################################

resource "azurerm_cognitive_account" "ai_foundry" {
  depends_on = [
    azurerm_subnet.subnet_agent
  ]
  name                       = "foundry-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location                   = data.azurerm_resource_group.rg.location
  resource_group_name        = data.azurerm_resource_group.rg.name
  kind                       = "AIServices"
  sku_name                   = var.foundry_sku
  project_management_enabled = true
  custom_subdomain_name      = "foundry${var.geo_short}${random_string.unique.result}${var.env_name}ai"
  local_auth_enabled         = false

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = ["${chomp(data.http.icanhazip.response_body)}"]
  }

  network_injection {
    scenario  = "agent"
    subnet_id = azurerm_subnet.subnet_agent.id
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_cognitive_deployment" "aifoundry_deployment_gpt" {
  name                 = "gpt-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  cognitive_account_id = azurerm_cognitive_account.ai_foundry.id

  sku {
    name     = var.gpt_model_sku
    capacity = var.gpt_model_rate_limit
  }

  model {
    format  = "OpenAI"
    name    = var.gpt_model_name
    version = var.gpt_model_version
  }
}

resource "azurerm_cognitive_deployment" "aifoundry_deployment_ada" {
  name                 = "ada-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  cognitive_account_id = azurerm_cognitive_account.ai_foundry.id

  sku {
    name     = var.ada_model_sku
    capacity = var.ada_model_rate_limit
  }

  model {
    format  = "OpenAI"
    name    = var.ada_model_name
    version = var.ada_model_version
  }
}

resource "azapi_resource" "ai_foundry_project" {
  depends_on = [
    azurerm_cognitive_account.ai_foundry,
    azurerm_private_endpoint.pe_storage,
    azurerm_private_endpoint.pe_cosmosdb,
    azurerm_private_endpoint.pe_aisearch,
    azurerm_private_endpoint.pe_aifoundry
  ]

  type                      = "Microsoft.CognitiveServices/accounts/projects@2026-07-01"
  name                      = "project-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  parent_id                 = azurerm_cognitive_account.ai_foundry.id
  location                  = var.location
  schema_validation_enabled = false

  body = {
    sku = {
      name = var.foundry_sku
    }
    identity = {
      type = "SystemAssigned"
    }

    properties = {
      displayName = "project"
      description = "A project for the AI Foundry account with network secured deployed Agent"
    }
  }

  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "time_sleep" "wait_project_identities" {
  depends_on = [
    azapi_resource.ai_foundry_project
  ]
  create_duration = "10s"
}

resource "azapi_resource" "conn_cosmosdb" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01"
  name                      = azurerm_cosmosdb_account.cosmosdb.name
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  body = {
    name = azurerm_cosmosdb_account.cosmosdb.name
    properties = {
      category = "CosmosDb"
      target   = azurerm_cosmosdb_account.cosmosdb.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.cosmosdb.id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "conn_storage" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01"
  name                      = azurerm_storage_account.storage_account.name
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  body = {
    name = azurerm_storage_account.storage_account.name
    properties = {
      category = "AzureStorageAccount"
      target   = azurerm_storage_account.storage_account.primary_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.storage_account.id
        location   = var.location
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

resource "azapi_resource" "conn_aisearch" {
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01"
  name                      = azurerm_search_service.ai_search.name
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  depends_on = [
    azapi_resource.ai_foundry_project
  ]

  body = {
    name = azurerm_search_service.ai_search.name
    properties = {
      category = "CognitiveSearch"
      target   = "https://${azurerm_search_service.ai_search.name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2026-03-01-preview"
        ResourceId = azurerm_search_service.ai_search.id
        location   = var.location
      }
    }
  }

  response_export_values = [
    "identity.principalId"
  ]
}

resource "azurerm_search_service" "ai_search" {
  name                          = "search-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  resource_group_name           = data.azurerm_resource_group.rg.name
  location                      = data.azurerm_resource_group.rg.location
  sku                           = var.search_sku
  local_authentication_enabled  = false
  public_network_access_enabled = true
  network_rule_bypass_option    = "AzureServices"
  replica_count                 = 1
  partition_count               = 1

  allowed_ips = [
    "${chomp(data.http.icanhazip.response_body)}"
  ]

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "time_sleep" "wait_rbac" {
  depends_on = [
    azurerm_role_assignment.cosmosdb_operator_ai_foundry_project,
    azurerm_role_assignment.storage_blob_data_contributor_ai_foundry_project,
    azurerm_role_assignment.search_index_data_contributor_ai_foundry_project,
    azurerm_role_assignment.search_service_contributor_ai_foundry_project
  ]
  create_duration = "60s"
}

resource "azapi_resource" "ai_foundry_project_capability_host" {
  depends_on = [
    azapi_resource.conn_aisearch,
    azapi_resource.conn_cosmosdb,
    azapi_resource.conn_storage,
    time_sleep.wait_rbac
  ]
  type                      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2026-05-01"
  name                      = "caphost-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  parent_id                 = azapi_resource.ai_foundry_project.id
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
      vectorStoreConnections = [
        azurerm_search_service.ai_search.name
      ]
      storageConnections = [
        azurerm_storage_account.storage_account.name
      ]
      threadStorageConnections = [
        azurerm_cosmosdb_account.cosmosdb.name
      ]
    }
  }
}

resource "azurerm_cosmosdb_sql_role_assignment" "cosmosdb_db_sql_role_aifp" {
  depends_on = [
    azapi_resource.ai_foundry_project_capability_host
  ]
  name                = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}cosmosdb_dbsqlrole")
  resource_group_name = data.azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.cosmosdb.name
  scope               = azurerm_cosmosdb_account.cosmosdb.id
  role_definition_id  = "${azurerm_cosmosdb_account.cosmosdb.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "storage_blob_data_owner_ai_foundry_project" {
  depends_on = [
    azapi_resource.ai_foundry_project_capability_host
  ]
  name                 = uuidv5("dns", "${azapi_resource.ai_foundry_project.name}${azapi_resource.ai_foundry_project.output.identity.principalId}${azurerm_storage_account.storage_account.name}storageblobdataowner")
  scope                = azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
  condition_version    = "2.0"
  condition            = <<-EOT
  (
    (
      !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})
      AND !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'})
      AND !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'})
    )
    OR
    (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.project_id_guid}'
    AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent')
  )
  EOT
}

####################################################################################################
#                                                                                                  #
# DNS                                                                                              #
#                                                                                                  #
####################################################################################################

resource "azurerm_private_dns_zone" "plz_cosmos_db" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone" "plz_ai_search" {
  name                = "privatelink.search.windows.net"
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone" "plz_storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone" "plz_cognitive_services" {
  name                = "privatelink.cognitiveservices.azure.com"
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone" "plz_ai_services" {
  name                = "privatelink.services.ai.azure.com"
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone" "plz_openai" {
  name                = "privatelink.openai.azure.com"
  resource_group_name = data.azurerm_resource_group.rg.name

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_cosmos_db_link" {
  depends_on = [
    azurerm_private_dns_zone.plz_cosmos_db,
    azurerm_virtual_network.vnet
  ]
  name                 = "link-cosmosdb-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  private_dns_zone_id  = azurerm_private_dns_zone.plz_cosmos_db.id
  virtual_network_id   = azurerm_virtual_network.vnet.id
  registration_enabled = false

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_ai_search_link" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.plz_cosmos_db_link,
    azurerm_private_dns_zone.plz_ai_search,
    azurerm_virtual_network.vnet
  ]

  name                 = "link-aisearch-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  private_dns_zone_id  = azurerm_private_dns_zone.plz_ai_search.id
  virtual_network_id   = azurerm_virtual_network.vnet.id
  registration_enabled = false

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_storage_blob_link" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.plz_ai_search_link,
    azurerm_private_dns_zone.plz_storage_blob,
    azurerm_virtual_network.vnet
  ]
  name                 = "link-storage-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  private_dns_zone_id  = azurerm_private_dns_zone.plz_storage_blob.id
  virtual_network_id   = azurerm_virtual_network.vnet.id
  registration_enabled = false

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_cognitive_services_link" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.plz_storage_blob_link,
    azurerm_private_dns_zone.plz_cognitive_services,
    azurerm_virtual_network.vnet
  ]
  name                 = "link-cogsvc-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  private_dns_zone_id  = azurerm_private_dns_zone.plz_cognitive_services.id
  virtual_network_id   = azurerm_virtual_network.vnet.id
  registration_enabled = false

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_ai_services_link" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.plz_cognitive_services_link,
    azurerm_private_dns_zone.plz_ai_services,
    azurerm_virtual_network.vnet
  ]
  name                 = "link-aiservices-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  private_dns_zone_id  = azurerm_private_dns_zone.plz_ai_services.id
  virtual_network_id   = azurerm_virtual_network.vnet.id
  registration_enabled = false

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "plz_openai_link" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.plz_ai_services_link,
    azurerm_private_dns_zone.plz_openai,
    azurerm_virtual_network.vnet
  ]
  name                 = "link-openai-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  private_dns_zone_id  = azurerm_private_dns_zone.plz_openai.id
  virtual_network_id   = azurerm_virtual_network.vnet.id
  registration_enabled = false

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

####################################################################################################
#                                                                                                  #
# Private Endpoints                                                                                #
#                                                                                                  #
####################################################################################################

resource "azurerm_private_endpoint" "pe_storage" {
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.plz_ai_search_link,
    azurerm_private_dns_zone_virtual_network_link.plz_storage_blob_link,
    azurerm_private_dns_zone_virtual_network_link.plz_cognitive_services_link,
    azurerm_private_dns_zone_virtual_network_link.plz_ai_services_link,
    azurerm_private_dns_zone_virtual_network_link.plz_openai_link,
    azurerm_private_dns_zone_virtual_network_link.plz_cosmos_db_link,
    azurerm_storage_account.storage_account,
    azurerm_virtual_network.vnet
  ]

  name                = "pe-sa${var.geo_short}${random_string.unique.result}${var.env_name}ai-blob"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet_pe.id

  private_service_connection {
    name                           = "psl-conn-${azurerm_storage_account.storage_account.name}-blob"
    private_connection_resource_id = azurerm_storage_account.storage_account.id
    subresource_names = [
      "blob"
    ]
    is_manual_connection = false
  }

  private_dns_zone_group {
    name = "dns-config-${azurerm_storage_account.storage_account.name}"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.plz_storage_blob.id
    ]
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_endpoint" "pe_cosmosdb" {
  depends_on = [
    azurerm_private_endpoint.pe_storage,
    azurerm_cosmosdb_account.cosmosdb,
    azurerm_virtual_network.vnet
  ]

  name                = "pe-cosmos-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet_pe.id

  private_service_connection {
    name                           = "psl-conn-${azurerm_cosmosdb_account.cosmosdb.name}"
    private_connection_resource_id = azurerm_cosmosdb_account.cosmosdb.id
    subresource_names = [
      "Sql"
    ]
    is_manual_connection = false
  }

  private_dns_zone_group {
    name = "dns-config-${azurerm_cosmosdb_account.cosmosdb.name}"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.plz_cosmos_db.id
    ]
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_endpoint" "pe_aisearch" {
  depends_on = [
    azurerm_private_endpoint.pe_cosmosdb,
    azurerm_search_service.ai_search,
    azurerm_virtual_network.vnet
  ]

  name                = "pe-search-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet_pe.id

  private_service_connection {
    name                           = "psl-conn-${azurerm_search_service.ai_search.name}"
    private_connection_resource_id = azurerm_search_service.ai_search.id
    subresource_names = [
      "searchService"
    ]
    is_manual_connection = false
  }

  private_dns_zone_group {
    name = "dns-config-${azurerm_search_service.ai_search.name}"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.plz_ai_search.id
    ]
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_endpoint" "pe_aifoundry" {
  depends_on = [
    azurerm_private_endpoint.pe_aisearch,
    azurerm_cognitive_account.ai_foundry,
    azurerm_virtual_network.vnet
  ]

  name                = "pe-foundry-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet_pe.id

  private_service_connection {
    name                           = "psl-conn-${azurerm_cognitive_account.ai_foundry.name}"
    private_connection_resource_id = azurerm_cognitive_account.ai_foundry.id
    subresource_names = [
      "account"
    ]
    is_manual_connection = false
  }

  private_dns_zone_group {
    name = "dns-config-${azurerm_cognitive_account.ai_foundry.name}"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.plz_cognitive_services.id,
      azurerm_private_dns_zone.plz_ai_services.id,
      azurerm_private_dns_zone.plz_openai.id
    ]
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

####################################################################################################
#                                                                                                  #
# Role Assignments                                                                                 #
#                                                                                                  #
####################################################################################################

resource "azurerm_role_assignment" "cosmosdb_operator_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  scope                = azurerm_cosmosdb_account.cosmosdb.id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "storage_blob_data_contributor_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  scope                = azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "search_index_data_contributor_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  scope                = azurerm_search_service.ai_search.id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "search_index_data_reader_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  scope                = azurerm_search_service.ai_search.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "search_service_contributor_ai_foundry_project" {
  depends_on = [
    resource.time_sleep.wait_project_identities
  ]
  scope                = azurerm_search_service.ai_search.id
  role_definition_name = "Search Service Contributor"
  principal_id         = azapi_resource.ai_foundry_project.output.identity.principalId
}

resource "azurerm_role_assignment" "storage_blob_data_contributor_me" {
  scope                = azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "storage_blob_data_reader_me" {
  scope                = azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "storage_blob_data_contributor_ai_search" {
  scope                = azurerm_storage_account.storage_account.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_search_service.ai_search.identity[0].principal_id
}

resource "azurerm_role_assignment" "cognitive_services_contributor_ai_search" {
  scope                = azurerm_cognitive_account.ai_foundry.id
  role_definition_name = "Cognitive Services Contributor"
  principal_id         = azurerm_search_service.ai_search.identity[0].principal_id
}

resource "azurerm_role_assignment" "cognitive_services_openai_contributor_ai_search" {
  scope                = azurerm_cognitive_account.ai_foundry.id
  role_definition_name = "Cognitive Services OpenAI Contributor"
  principal_id         = azurerm_search_service.ai_search.identity[0].principal_id
}

resource "azurerm_role_assignment" "key_vault_secrets_officer_me" {
  scope                = azurerm_key_vault.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

####################################################################################################
#                                                                                                  #
# Jumpbox                                                                                          #
#                                                                                                  #
####################################################################################################

resource "azurerm_windows_virtual_machine" "jumpbox" {
  name                  = "vm${var.geo_short}${random_string.unique.result}${var.env_name}ai"
  resource_group_name   = data.azurerm_resource_group.rg.name
  location              = data.azurerm_resource_group.rg.location
  size                  = var.jump_box_size
  network_interface_ids = [azurerm_network_interface.jumpbox_nic.id]
  admin_username        = "aiadmin"
  admin_password        = azurerm_key_vault_secret.key_vault_secret_aiadmin.value

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  lifecycle {
    ignore_changes = [
      tags, identity
    ]
  }
}

resource "azurerm_network_interface" "jumpbox_nic" {
  name                = "nic-jump-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "jumpbox-nic-ipconfig"
    subnet_id                     = azurerm_subnet.subnet_jump.id
    public_ip_address_id          = azurerm_public_ip.pip_jump_box.id
    private_ip_address_allocation = "Dynamic"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_public_ip" "pip_jump_box" {
  name                = "pip-jump-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  allocation_method   = "Static"

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "jumpbox_shutdown_schedule" {
  virtual_machine_id    = azurerm_windows_virtual_machine.jumpbox.id
  location              = data.azurerm_resource_group.rg.location
  enabled               = true
  timezone              = "GMT Standard Time"
  daily_recurrence_time = "1830"

  notification_settings {
    enabled = false
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

####################################################################################################
#                                                                                                  #
# Logging & Diagnostics                                                                            #
#                                                                                                  #
####################################################################################################

resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  name                = "la-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "ai_foundry_diagnostics" {
  name                       = "diag-foundry-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  target_resource_id         = azurerm_cognitive_account.ai_foundry.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_metric {
    category = "AllMetrics"
  }

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "ai_search_diagnostics" {
  name                       = "diag-search-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  target_resource_id         = azurerm_search_service.ai_search.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_metric {
    category = "AllMetrics"
  }

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "ai_project_diagnostics" {
  name                       = "diag-project-${var.geo_short}-${random_string.unique.result}-${var.env_name}-ai"
  target_resource_id         = azapi_resource.ai_foundry_project.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace.id

  enabled_metric {
    category = "AllMetrics"
  }

  enabled_log {
    category_group = "allLogs"
  }
}
