terraform {
  backend "s3" {
    bucket = "ryo-terraform-state-20260430"
    key    = "study-aws-2/terraform.tfstate"
    region = "ap-northeast-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  wordpress_db_host = var.restore_db_endpoint != "" ? var.restore_db_endpoint : aws_db_instance.mysql.address
}

# -------------------------
# SSH Key Pair for Bastion
# -------------------------
resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "bastion_private_key" {
  filename        = "${path.module}/bastion-key.pem"
  content         = tls_private_key.bastion_key.private_key_pem
  file_permission = "0400"
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "study-aws-2-bastion-key"
  public_key = tls_private_key.bastion_key.public_key_openssh

  tags = {
    Name = "study-aws-2-bastion-key"
  }
}

# -------------------------
# VPC
# -------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "study-aws-2-vpc"
  }
}

# -------------------------
# Public Subnets
# -------------------------
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "study-aws-2-public-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "study-aws-2-public-2"
  }
}

# -------------------------
# Private Subnets
# -------------------------
resource "aws_subnet" "private_app_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "study-aws-2-private-app-1"
  }
}

resource "aws_subnet" "private_db_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "study-aws-2-private-db-1"
  }
}

resource "aws_subnet" "private_db_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "study-aws-2-private-db-2"
  }
}

# -------------------------
# Internet Gateway
# -------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "study-aws-2-igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "study-aws-2-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public_rt.id
  gateway_id             = aws_internet_gateway.igw.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "public_1_assoc" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2_assoc" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# -------------------------
# NAT Gateway
# -------------------------
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = {
    Name = "study-aws-2-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_1.id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "study-aws-2-nat"
  }
}

resource "aws_route_table" "private_app_rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "study-aws-2-private-app-rt"
  }
}

resource "aws_route" "private_app_nat" {
  route_table_id         = aws_route_table.private_app_rt.id
  nat_gateway_id         = aws_nat_gateway.nat.id
  destination_cidr_block = "0.0.0.0/0"
}

resource "aws_route_table_association" "private_app_assoc" {
  subnet_id      = aws_subnet.private_app_1.id
  route_table_id = aws_route_table.private_app_rt.id
}

# -------------------------
# Security Groups
# -------------------------
resource "aws_security_group" "alb_sg" {
  name   = "study-aws-2-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "study-aws-2-alb-sg"
  }
}

resource "aws_security_group" "ec2_sg" {
  name   = "study-aws-2-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "study-aws-2-ec2-sg"
  }
}

resource "aws_security_group" "bastion_sg" {
  name   = "study-aws-2-bastion-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "study-aws-2-bastion-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "study-aws-2-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL from WordPress EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  ingress {
    description     = "Allow MySQL from Bastion EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  tags = {
    Name = "study-aws-2-rds-sg"
  }
}

# -------------------------
# RDS
# -------------------------
resource "aws_db_subnet_group" "db_subnet" {
  name = "study-aws-2-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_db_1.id,
    aws_subnet.private_db_2.id
  ]

  tags = {
    Name = "study-aws-2-db-subnet-group"
  }
}

resource "aws_db_instance" "mysql" {
  identifier        = "study-aws-2-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_encrypted = true

  db_name  = "wordpress"
  username = var.db_user
  password = var.db_pass

  db_subnet_group_name   = aws_db_subnet_group.db_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  backup_retention_period = 7
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:00-sun:20:00"

  skip_final_snapshot = true

  tags = {
    Name = "study-aws-2-rds"
  }
}

# -------------------------
# EC2 WordPress
# -------------------------
resource "aws_instance" "web" {
  ami           = "ami-0d52744d6551d851e"
  instance_type = "t2.micro"

  subnet_id = aws_subnet.private_app_1.id

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data_replace_on_change = true

  user_data = <<EOF
#!/bin/bash
set -eux
apt update -y
apt install -y docker.io docker-compose
systemctl start docker
systemctl enable docker

mkdir -p /home/ubuntu/wp
cd /home/ubuntu/wp

cat > docker-compose.yml <<EOL
services:
  wordpress:
    image: wordpress
    container_name: wordpress-app
    restart: always
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: ${local.wordpress_db_host}:3306
      WORDPRESS_DB_USER: ${var.db_user}
      WORDPRESS_DB_PASSWORD: ${var.db_pass}
      WORDPRESS_DB_NAME: wordpress
EOL

docker-compose up -d
EOF

  tags = {
    Name = "study-aws-2-wordpress-ec2"
  }
}

# -------------------------
# Bastion EC2
# -------------------------
resource "aws_instance" "bastion" {
  ami                         = "ami-0d52744d6551d851e"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public_1.id
  associate_public_ip_address = true
  key_name                    = aws_key_pair.bastion_key.key_name

  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  user_data_replace_on_change = true

  user_data = <<EOF
#!/bin/bash
set -eux
apt update -y
apt install -y mysql-client
EOF

  tags = {
    Name = "study-aws-2-bastion"
  }
}

# -------------------------
# ALB
# -------------------------
resource "aws_lb" "alb" {
  name               = "study-aws-2-alb"
  load_balancer_type = "application"

  subnets = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]

  security_groups = [aws_security_group.alb_sg.id]

  tags = {
    Name = "study-aws-2-alb"
  }
}

resource "aws_lb_target_group" "tg" {
  name     = "study-aws-2-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-499"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  tags = {
    Name = "study-aws-2-tg"
  }
}

resource "aws_lb_target_group_attachment" "attach" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web.id
  port             = 80
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# -------------------------
# CloudFront
# -------------------------
resource "aws_cloudfront_distribution" "wordpress" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "study-aws-2-wordpress-cloudfront"

  origin {
    domain_name = aws_lb.alb.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "POST", "PUT", "DELETE", "PATCH"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = true
      headers      = ["CloudFront-Forwarded-Proto"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["JP"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "study-aws-2-cloudfront"
  }
}