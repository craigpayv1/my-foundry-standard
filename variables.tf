variable "existing_rg" {
  type    = string
  default = "craig-pay-sandbox-rg"
}

variable "env_name" {
  type    = string
  default = "tmp"
}

variable "foundry_sku" {
  type    = string
  default = "S0" # "S0", "S1", "S2" etc.
}

variable "search_sku" {
  type    = string
  default = "standard" # lower case "free", "basic", "standard" etc.
}

variable "semantic_search_sku" {
  type    = string
  default = "standard" # lower case "free" or "standard"
}

variable "gpt_model_name" {
  type    = string
  default = "gpt-4.1"
}

variable "gpt_model_version" {
  type    = string
  default = "2025-04-14"
}

variable "gpt_model_sku" {
  type    = string
  default = "GlobalStandard" # values such as "Standard", "GlobalStandard", "GlobalPremium" etc.
}

variable "gpt_model_rate_limit" {
  type    = number
  default = 30 # value between 1 and 50 (in 1000s, 30 is 30000)
}

variable "ada_model_name" {
  type    = string
  default = "text-embedding-ada-002"
}

variable "ada_model_version" {
  type    = string
  default = "2"
}

variable "ada_model_sku" {
  type    = string
  default = "Standard"
}

variable "ada_model_rate_limit" {
  type    = number
  default = 50 # value between 1 and 340 (in 1000s, 50 is 50000)
}

variable "virtual_network_address_space" {
  description = "The address space for the virtual network"
  type        = string
  default     = "10.0.0.0/25"
}

variable "private_endpoint_subnet_address_prefix" {
  description = "The address prefix for the subnet that contains the private endpoints"
  type        = string
  default     = "10.0.0.0/27"
}

variable "agent_subnet_address_prefix" {
  description = "The address prefix for the subnet that will be delegated to the Standard Agent"
  type        = string
  default     = "10.0.0.32/27"
}

variable "jump_subnet_address_prefix" {
  description = "The address prefix for the subnet that contains the private endpoints"
  type        = string
  default     = "10.0.0.64/27"
}

variable "location" {
  description = "The name of the location to provision the resources to"
  type        = string
  default     = "uksouth"
}

variable "geo_short" {
  type    = string
  default = "uks"
}

variable "jump_box_size" {
  type    = string
  default = "Standard_B2ms"
}
