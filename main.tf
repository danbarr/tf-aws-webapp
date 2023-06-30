terraform {
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.62"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      environment = var.env
      department  = var.department
      owner       = var.owner
      application = "HashiCafe website"
    }
  }
}

locals {
  timestamp = timestamp()
}

resource "random_integer" "product" {
  min = 0
  max = length(var.hashi_products) - 1
  keepers = {
    "timestamp" = local.timestamp
  }
}

data "hcp_packer_image" "ubuntu-webserver" {
  bucket_name    = var.packer_bucket
  cloud_provider = "aws"
  channel = var.packer_channel
  region         = var.region

  lifecycle {
    postcondition {
      condition = timecmp(plantimestamp(), timeadd(self.created_at, "720h")) < 0
      error_message = "The selected image is more than 30 days old."
    }

    postcondition {
      condition = self.revoke_at == null
      error_message = "The selected image is scheduled to be revoked."
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "all" {
  filter {
    # Don't want local zones
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_availability_zone" "selected" {
  name = data.aws_availability_zones.all.names[0]
  lifecycle {
    postcondition {
      condition = self.state == "available"
      error_message = "The selected availability zone is degraded or unavailable."
    }
  }
}

data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type

  lifecycle {
    postcondition {
      condition = self.ebs_optimized_support != "unsupported"
      error_message = "The EC2 instance type (${var.instance_type}) must support EBS optimization."
    }
  }
}

resource "aws_vpc" "hashicafe" {
  cidr_block           = var.address_space
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc-${var.region}"
  }

  lifecycle {
    postcondition {
      condition     = self.enable_dns_hostnames == true
      error_message = "VPC must have DNS hostnames enabled."
    }
  }
}

resource "aws_subnet" "hashicafe" {
  vpc_id     = aws_vpc.hashicafe.id
  cidr_block = var.subnet_prefix
  availability_zone = data.aws_availability_zone.selected.name

  tags = {
    Name = "${var.prefix}-subnet"
  }
}

resource "aws_security_group" "hashicafe" {
  name = "${var.prefix}-security-group"

  vpc_id = aws_vpc.hashicafe.id

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "${var.prefix}-security-group"
  }
}

resource "aws_security_group_rule" "ingress" {
  for_each          = toset(["22", "80", "443"])
  security_group_id = aws_security_group.hashicafe.id
  type              = "ingress"
  description       = "Inbound port ${each.value}"
  from_port         = each.value
  to_port           = each.value
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_internet_gateway" "hashicafe" {
  vpc_id = aws_vpc.hashicafe.id

  tags = {
    Name = "${var.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "hashicafe" {
  vpc_id = aws_vpc.hashicafe.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hashicafe.id
  }
}

resource "aws_route_table_association" "hashicafe" {
  subnet_id      = aws_subnet.hashicafe.id
  route_table_id = aws_route_table.hashicafe.id
}

resource "aws_instance" "hashicafe" {
  ami                         = data.hcp_packer_image.ubuntu-webserver.cloud_image_id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.hashicafe.id
  vpc_security_group_ids      = [aws_security_group.hashicafe.id]
  key_name                    = aws_key_pair.hashicafe.key_name

  tags = {
    Name = "${var.prefix}-hashicafe-instance"
  }

  lifecycle {
    precondition {
      condition     = data.hcp_packer_image.ubuntu-webserver.region == var.region
      error_message = "The selected image must be in the same region as the deployed resources."
    }

    postcondition {
      condition     = self.ami == data.hcp_packer_image.ubuntu-webserver.cloud_image_id
      error_message = "A new source AMI is available in the HCP Packer channel, please re-deploy."
    }

    postcondition {
      condition     = self.public_dns != ""
      error_message = "EC2 instance must be in a VPC that has public DNS hostnames enabled."
    }

    postcondition {
      condition     = self.instance_state == "running"
      error_message = "EC2 instance must be running."
    }
  }
}

data "aws_ebs_volume" "root" {
  filter {
    name = "volume-id"
    values = [aws_instance.hashicafe.root_block_device[0].volume_id]
  }

  lifecycle {
    postcondition {
      condition     = self.encrypted
      error_message = "The server's root volume is not encrypted."
    }
  }
}

resource "aws_eip" "hashicafe" {
  domain = "vpc"
}

resource "aws_eip_association" "hashicafe" {
  instance_id   = aws_instance.hashicafe.id
  allocation_id = aws_eip.hashicafe.id
}

# We're using a little trick here so we can run the provisioner without
# destroying the VM. Do not do this in production.

resource "null_resource" "configure-web-app" {
  depends_on = [aws_eip_association.hashicafe]

  triggers = {
    build_number = local.timestamp
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.hashicafe.private_key_pem
    host        = aws_eip.hashicafe.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir /var/www/html/img",
      "sudo chown -R ubuntu:ubuntu /var/www/html"
    ]
  }

  provisioner "file" {
    content = templatefile("files/index.html", {
      product_name  = var.hashi_products[random_integer.product.result].name
      product_color = var.hashi_products[random_integer.product.result].color
      product_image = var.hashi_products[random_integer.product.result].image_file
    })
    destination = "/var/www/html/index.html"
  }

  provisioner "file" {
    source      = "files/img/"
    destination = "/var/www/html/img"
  }
}

resource "tls_private_key" "hashicafe" {
  algorithm = "RSA"
}

resource "aws_key_pair" "hashicafe" {
  key_name   = "${var.prefix}-hashicafe-sshkey"
  public_key = tls_private_key.hashicafe.public_key_openssh
}
