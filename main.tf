# This terraform creates a VPC with the following:
# 1 Internet Gateway that provides access to the internet
# 1 or more Public subnets in each availability zone
# 1 or more Private subnets in each availability zone
# 1 or more Firewall subnets in each availability zone
# 1 or more public NAT gateway in each availability zone
# VPC flow logs
# 1 AWS Network Firewall with base stateless and stateful rules for the allowed networks only.
# Network Firewall logs to Cloudwatch
# Default VPC Security group
# Security group for only the allowed networks
# Route table configuration
# s3, ec2, and elasticloadbalancing service endpoints

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
}

provider "aws" {
  profile = "" # The name of the profile in your ~/aws/config file
  region  = var.region
  default_tags {
    tags = {
      Name = var.vpc_name
      Owner = var.owner
    }
  }
}

locals {
  nat_gateway_count = length(var.azs)
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  instance_tenancy     = var.instance_tenancy
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
}

resource "aws_s3_bucket" "vpc_flow_log" {
  bucket = "${var.vpc_name}--flowlog"
  force_destroy = true
}

resource "aws_s3_bucket_acl" "vpc_flow_log_bucket_acl" {
  bucket = aws_s3_bucket.vpc_flow_log.id
  acl    = "private"
}

resource "aws_s3_bucket_versioning" "vpc_flow_log_bucket_versioning" {
  bucket = aws_s3_bucket.vpc_flow_log.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_log_bucket_encryption" {
  bucket = aws_s3_bucket.vpc_flow_log.id
  rule {
    apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vpc_flow_log_bucket_public_access_block" {
  bucket = aws_s3_bucket.vpc_flow_log.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_flow_log" "this" {
  log_destination      = aws_s3_bucket.vpc_flow_log.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
}


resource "aws_vpc_dhcp_options" "this" {
  count = var.enable_dhcp_options ? 1 : 0

  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.enable_dhcp_options ? 1 : 0

  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

resource "aws_subnet" "public_subnets" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.public_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)
 
  tags = {
    Name = format("${var.vpc_name}-public-%s", element(var.azs, count.index))
  }  
}
 
resource "aws_subnet" "private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)
 
  tags = {
    Name = format("${var.vpc_name}-private-%s",element(var.azs, count.index))
  }  
}

resource "aws_subnet" "firewall_subnets" {
  count             = length(var.firewall_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.firewall_subnet_cidrs, count.index)
  availability_zone = element(var.azs, count.index)
 
  tags = {
    Name = format("${var.vpc_name}-firewall-%s",element(var.azs, count.index))
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "firewall" {
  count = local.nat_gateway_count
  vpc_id = aws_vpc.main.id

  tags = {
    Name = format("${var.vpc_name}-firewall-%s",element(var.azs, count.index))
  }
}

resource "aws_route" "public_internet_gateway" { 
  count = local.nat_gateway_count

  route_table_id         = element(aws_route_table.firewall[*].id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table" "public" {
  count = local.nat_gateway_count
  vpc_id = aws_vpc.main.id

  tags = {
    Name = format("${var.vpc_name}-public-%s",element(var.azs, count.index))
  } 
}

resource "aws_route_table" "private" {
  count = local.nat_gateway_count
  vpc_id = aws_vpc.main.id

  tags = merge(
    {
      "Name" = format(
        "${var.vpc_name}-private-%s",
        element(var.azs, count.index),
      )
    },
  )
}

resource "aws_eip" "nat_eip" {
  count = local.nat_gateway_count
  vpc = true

  tags = {
    Name = format("${var.vpc_name}-%s",element(var.azs, count.index))
  }

  depends_on = [aws_internet_gateway.gw]
}

locals {
  nat_gateway_ips = try(aws_eip.nat_eip[*].id, [])
}

resource "aws_nat_gateway" "nat_gw" {
  count = local.nat_gateway_count

  allocation_id = element(local.nat_gateway_ips[*], count.index)
  subnet_id = element(aws_subnet.public_subnets[*].id, count.index)

  tags = {
    Name = format("${var.vpc_name}-%s",element(var.azs, count.index))
  }

  depends_on = [aws_internet_gateway.gw]
}

resource "aws_route" "private_nat_gateway" {
  count = local.nat_gateway_count

  route_table_id         = element(aws_route_table.private[*].id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.nat_gw[*].id, count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.public_subnet_cidrs)

  subnet_id = element(aws_subnet.private_subnets[*].id, count.index)
  route_table_id = element(aws_route_table.private[*].id, count.index)
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = element(aws_route_table.public[*].id, count.index)
}

resource "aws_route_table_association" "firewall" {
  count = length(var.firewall_subnet_cidrs)

  subnet_id      = element(aws_subnet.firewall_subnets[*].id, count.index)
  route_table_id = element(aws_route_table.firewall[*].id, count.index)
}

locals {
    nat_gateway_ip_addresses = try(aws_eip.nat_eip[*].public_ip, [])
}

resource "aws_networkfirewall_rule_group" "this" {
  capacity = 100
  name     = "${var.vpc_name}-default"
  type     = "STATEFUL"

  rule_group {
    rules_source {

      dynamic "stateful_rule" {
        for_each = var.allowed_networks
        content {
          action = "PASS"
          header {
            destination      = "10.0.0.16/16"
            destination_port = "ANY"
            protocol         = "TCP"
            direction        = "FORWARD"
            source_port      = "ANY"
            source           = stateful_rule.value
          }
          rule_option {
            keyword = "sid:${stateful_rule.key+1}"
          }
        }
      }

      dynamic "stateful_rule" {
        for_each = var.allowed_networks
        content {
          action = "PASS"
          header {
            destination      = "10.0.0.16/16"
            destination_port = "ANY"
            protocol         = "UDP"
            direction        = "FORWARD"
            source_port      = "ANY"
            source           = stateful_rule.value
          }
          rule_option {
            keyword = "sid:${stateful_rule.key+20}"
          }
        }
      }

      # The EIP addresses of the NAT Gateways needed for Oauth in OpenShift
      dynamic "stateful_rule" {
        for_each = local.nat_gateway_ip_addresses
        content {
          action = "PASS"
          header {
            destination      = "10.0.0.16/16"
            destination_port = "ANY"
            protocol         = "TCP"
            direction        = "FORWARD"
            source_port      = "ANY"
            source           = "${stateful_rule.value}/32"
          }
          rule_option {
            keyword = "sid:${stateful_rule.key+40}"
          }
        }
      }  

      # Allow all outbound traffic
      stateful_rule {
        action = "PASS"
        header {
          destination      = "0.0.0.0/0"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "TCP"
          source           = "10.0.0.0/16"
          source_port      = "ANY"
        }
        rule_option {
            keyword = "sid:46"
        }                
      }                

      stateful_rule {
        action = "DROP"
        header {
          destination      = "10.0.0.0/16"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "ICMP"
          source           = "0.0.0.0/0"
          source_port      = "ANY"
        }
        rule_option {
            keyword = "sid:50"
        }                
      }

      stateful_rule {
        action = "DROP"
        header {
          destination      = "10.0.0.0/16"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "SSH"
          source           = "0.0.0.0/0"
          source_port      = "ANY"
        }
        rule_option {
            keyword = "sid:51"
        }                
      }

      stateful_rule {
        action = "DROP"
        header {
          destination      = "10.0.0.0/16"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "TCP"
          source           = "0.0.0.0/0"
          source_port      = "ANY"
        }
        rule_option {
            keyword = "sid:52"
        }                
      }

      stateful_rule {
        action = "DROP"
        header {
          destination      = "10.0.0.0/16"
          destination_port = "ANY"
          direction        = "FORWARD"
          protocol         = "UDP"
          source           = "0.0.0.0/0"
          source_port      = "ANY"
        }
        rule_option {
            keyword = "sid:53"
        }                
      }
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.vpc_name}-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.this.arn
    }
  }
}

resource "aws_networkfirewall_firewall" "this" {
  name                = "${var.vpc_name}-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = aws_vpc.main.id

  dynamic "subnet_mapping" {
    for_each = aws_subnet.firewall_subnets[*].id

    content {
      subnet_id = subnet_mapping.value
    }
  }
}

locals {
    sync_states = aws_networkfirewall_firewall.this.firewall_status[0].sync_states[*]
}
 
variable "vpce_ids" {
  type = list(string)
  default = []
}

locals {
  firewall-a = {
    for_each = aws_networkfirewall_firewall.this
    vpce_a   = [for ss in local.sync_states : ss.attachment[0].endpoint_id if ss.availability_zone == var.azs[0]]
  }
  firewall-b = {
    for_each = aws_networkfirewall_firewall.this
    vpce_b   = [for ss in local.sync_states : ss.attachment[0].endpoint_id if ss.availability_zone == var.azs[1]]
  }
  firewall-c = {
    for_each = aws_networkfirewall_firewall.this
    vpce_c   = [for ss in local.sync_states : ss.attachment[0].endpoint_id if ss.availability_zone == var.azs[2]]
  }
  vpc_endpoint_ids = concat(var.vpce_ids, local.firewall-a.vpce_a, local.firewall-b.vpce_b, local.firewall-c.vpce_c)
}

resource "aws_route" "public_firewall" {  
  count = length(var.public_subnet_cidrs)

  route_table_id         = element(aws_route_table.public[*].id, count.index)
  destination_cidr_block = "0.0.0.0/0"

  # To install an OpenShift cluster comment out the vpc_endpoint_id and uncomment the gateway_id
  # Uncomment the following after the cluster is created and comment out the gateway_id value and apply.
  # This works with lines 482-485.
  vpc_endpoint_id = element(local.vpc_endpoint_ids[*], count.index)
  # gateway_id    = aws_internet_gateway.gw.id

  timeouts {
    create = "5m"
  }
} 

resource "aws_route_table" "igw_firewall" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw-firewall"
  }  
}

resource "aws_route" "igw_firewall" {  
  count = length(var.firewall_subnet_cidrs)

  route_table_id         = aws_route_table.igw_firewall.id
  destination_cidr_block = element(var.public_subnet_cidrs[*], count.index)
  vpc_endpoint_id        = element(local.vpc_endpoint_ids[*], count.index)

  timeouts {
    create = "5m"
  }
}

# To install an OpenShift cluster comment out following block.
# Uncomment the following after the cluster is created to route the firewall and apply.
# Goes with line 451-454.
resource "aws_route_table_association" "firewall-asc" {  
  route_table_id  = aws_route_table.igw_firewall.id
  gateway_id = aws_internet_gateway.gw.id
}

#
# Create AWS Cloudwatch log group for the firewall logs
#

resource "aws_cloudwatch_log_group" "firewall-flow" {
  name_prefix = "firewall-flow-${var.vpc_name}"
  # Set to true if you do not wish the log group (and any logs it may contain) 
  # to be deleted at destroy time, and instead just remove the log group from the Terraform state.
  skip_destroy = true 
  retention_in_days = 180

  tags = {
    Name = "${var.vpc_name} firewall"
  }
}

resource "aws_networkfirewall_logging_configuration" "anfw_flow_logging_configuration" {
  firewall_arn = aws_networkfirewall_firewall.this.arn
  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall-flow.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }
  }
}

#
# Create a security group for the allowed networks
#

resource "aws_security_group" "allowed-networks-sg" {
  name = "allowed-networks-sg"
  description = "Only allow traffic from allowd networks"
  vpc_id = aws_vpc.main.id
  
  # his is normally not needed, however certain AWS services such as Elastic Map Reduce may 
  # automatically add required rules to security groups used with the service, and those rules 
  # may contain a cyclic dependency that prevent the security groups from being destroyed without 
  # removing the dependency first.
  revoke_rules_on_delete = true

  tags = {
    Name = "allowed-networks-sg"
  }
}

resource "aws_security_group_rule" "allow_inbound_rules" {
  security_group_id = aws_security_group.allowed-networks-sg.id
  type        = "ingress"
  to_port     = 0
  protocol    = "-1"
  from_port   = 0
  cidr_blocks = var.allowed_networks
}

resource "aws_security_group_rule" "allow_self_rule" {
  security_group_id = aws_security_group.allowed-networks-sg.id
  source_security_group_id = aws_security_group.allowed-networks-sg.id
  type      = "ingress"
  to_port   = 0
  protocol  = "-1"
  from_port = 0
}

resource "aws_security_group_rule" "allow_outbound_rules" {
  security_group_id = aws_security_group.allowed-networks-sg.id
  type        = "egress"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

#
# Create the AWS services endpoints so that the network traffic remains private
#

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"

  tags = {
    Name = "s3.${var.region}.amazonaws.com"
  }  
}

resource "aws_vpc_endpoint_route_table_association" "s3_public_association" {  
  count = length(var.public_subnet_cidrs)

  route_table_id  = element(aws_route_table.public[*].id, count.index)
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
}

resource "aws_vpc_endpoint_route_table_association" "s3_private_association" {  
  count = length(var.private_subnet_cidrs)

  route_table_id  = element(aws_route_table.private[*].id, count.index)
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
} 

resource "aws_vpc_endpoint" "ec2" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.ec2"
  vpc_endpoint_type = "Interface"
  subnet_ids = aws_subnet.public_subnets[*].id

  tags = {
    Name = "ec2.${var.region}.amazonaws.com"
  }  
}

resource "aws_vpc_endpoint" "elasticloadbalancing" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.elasticloadbalancing"
  vpc_endpoint_type = "Interface"
  subnet_ids = aws_subnet.public_subnets[*].id

  tags = {
    Name = "elasticloadbalancing.${var.region}.amazonaws.com"
  }  
}
