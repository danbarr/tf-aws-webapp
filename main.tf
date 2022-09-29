terraform {
  required_version = ">= 1.1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.44.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      environment = var.env
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "hashiapp" {
  cidr_block           = var.address_space
  enable_dns_hostnames = true

  tags = {
    Name = "${var.prefix}-vpc-${var.region}"
  }
}

resource "aws_subnet" "hashiapp_primary" {
  vpc_id            = aws_vpc.hashiapp.id
  cidr_block        = var.subnet_prefix_primary
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.prefix}-subnet-primary"
  }
}

moved {
  from = aws_subnet.hashiapp
  to   = aws_subnet.hashiapp_secondary
}

resource "aws_subnet" "hashiapp_secondary" {
  vpc_id            = aws_vpc.hashiapp.id
  cidr_block        = var.subnet_prefix_secondary
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.prefix}-subnet-secondary"
  }
}

resource "aws_security_group" "hashiapp" {
  name = "${var.prefix}-security-group"

  vpc_id = aws_vpc.hashiapp.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.hashiapp_alb.id]
  }

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

resource "aws_internet_gateway" "hashiapp" {
  vpc_id = aws_vpc.hashiapp.id

  tags = {
    Name = "${var.prefix}-internet-gateway"
  }
}

resource "aws_route_table" "hashiapp" {
  vpc_id = aws_vpc.hashiapp.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hashiapp.id
  }
}

resource "aws_route_table_association" "hashiapp_primary" {
  subnet_id      = aws_subnet.hashiapp_primary.id
  route_table_id = aws_route_table.hashiapp.id
}

moved {
  from = aws_route_table_association.hashiapp
  to   = aws_route_table_association.hashiapp_primary
}

resource "aws_route_table_association" "hashiapp_secondary" {
  subnet_id      = aws_subnet.hashiapp_secondary.id
  route_table_id = aws_route_table.hashiapp.id
}

data "hcp_packer_iteration" "ubuntu" {
  bucket_name = var.packer_bucket
  channel     = var.packer_channel
}

data "hcp_packer_image" "ubuntu" {
  bucket_name    = var.packer_bucket
  cloud_provider = "aws"
  iteration_id   = data.hcp_packer_iteration.ubuntu.ulid
  region         = var.region
}

resource "aws_instance" "hashiapp" {
  for_each                    = toset(["primary", "secondary"])
  ami                         = data.hcp_packer_image.ubuntu.cloud_image_id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  subnet_id                   = each.key == "primary" ? aws_subnet.hashiapp_primary.id : aws_subnet.hashiapp_secondary.id
  vpc_security_group_ids      = [aws_security_group.hashiapp.id]
  user_data                   = file("./user_data.sh")

  tags = {
    Name = "${var.prefix}-hashiapp-instance"
  }
}

moved {
  from = aws_instance.hashiapp
  to   = aws_instance.hashiapp["primary"]
}

resource "aws_security_group" "hashiapp_alb" {
  name   = "${var.prefix}-alb-security-group"
  vpc_id = aws_vpc.hashiapp.id
  tags = {
    Name = "${var.prefix}-alb-security-group"
  }
}

resource "aws_security_group_rule" "hashiapp_alb_ingress" {
  security_group_id = aws_security_group.hashiapp_alb.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "hashiapp_alb_egress" {
  security_group_id        = aws_security_group.hashiapp_alb.id
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.hashiapp.id
}

resource "aws_lb" "hashiapp" {
  name               = "${var.prefix}-hashiapp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.hashiapp_alb.id]
  subnets            = [aws_subnet.hashiapp_primary.id, aws_subnet.hashiapp_secondary.id]
}

resource "aws_lb_target_group" "hashiapp" {
  target_type = "instance"
  name        = "${var.prefix}-hashiapp-alb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.hashiapp.id
}

resource "aws_lb_target_group_attachment" "hashiapp" {
  for_each         = aws_instance.hashiapp
  target_group_arn = aws_lb_target_group.hashiapp.arn
  target_id        = each.value.id
}

resource "aws_lb_listener" "hashiapp" {
  load_balancer_arn = aws_lb.hashiapp.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.hashiapp.arn
  }
}
