variable "vpc_name" {
  type        = string
  description = "The name of the VPC."
  nullable = false
}

variable "owner" {
  type        = string
  description = "The email address of the owner"
  nullable = false
}

variable "region" {
  type        = string
  description = "The AWS region to create the VPC"
  default = "us-east-2"
}

variable "allowed_networks" {
  type        = list(string)
  description = "A list of networks allowed in by the firewall and security group.  This can be internet egress IP ranges from your company campuses."
  default     = ["129.34.20.0/24", "129.41.46.0/23", "129.41.56.0/22"]
}


variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public Subnet CIDR values"
  # default = ["10.0.101.0/24"]
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}
 
variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private Subnet CIDR values"
  # default = ["10.0.1.0/24"]
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "firewall_subnet_cidrs" {
  type        = list(string)
  description = "Firewall Subnet CIDR values"
  # default = ["10.0.201.0/24"]
  default     = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones"
  # default = ["us-east-2a"]
  default     = ["us-east-2a", "us-east-2b", "us-east-2c"]
}

variable "enable_dns_hostnames" {
  description = "Should be true to enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Should be true to enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "instance_tenancy" {
  description = "A tenancy option for instances launched into the VPC"
  type        = string
  default     = "default"
}

variable "enable_dhcp_options" {
  description = "Should be true if you want to specify a DHCP options set with a custom domain name, and DNS servers"
  type        = bool
  default     = true
}

variable "dhcp_options_domain_name" {
  description = "Specifies DNS domain name for DHCP options set (requires enable_dhcp_options set to true). This needs to be the same as the OpenShift baseDomain Route 53 hosted zone."
  type        = string
  default     = ""
}

variable "dhcp_options_domain_name_servers" {
  description = "Specify a list of DNS server addresses for DHCP options set, default to AWS provided (requires enable_dhcp_options set to true)"
  type        = list(string)
  default     = ["AmazonProvidedDNS"]
}
