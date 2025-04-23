terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Data source: Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# --------------------------------------------------
# 1. NETWORK: VPC, Subnets, IGW, Routing (2 AZs)
# --------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"
  tags       = { Name = "TheDungeonShelf-VPC" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "Public-Subnet-1-us-east-1a" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "Public-Subnet-2-us-east-1b" }
}

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"
  tags              = { Name = "Private-Subnet-1-us-east-1a" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.10.3.0/24"
  availability_zone = "us-east-1b"
  tags              = { Name = "Private-Subnet-2-us-east-1b" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "TheDungeonShelf-IGW" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "Public-RouteTable" }
}

resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public_rt.id
}

# --------------------------------------------------
# 2. SECURITY GROUPS
# --------------------------------------------------

resource "aws_security_group" "web_sg" {
  name        = "Web-SG"
  description = "Permite HTTP, HTTPS, SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "Web-SG" }
}

resource "aws_security_group" "db_sg" {
  name        = "DB-SG"
  description = "Permite MySQL from Web-SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "DB-SG" }
}

# --------------------------------------------------
# 3. S3 BUCKET (no ACL resource)
# --------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "product_images" {
  bucket = "thedungeonshelf-product-images-${random_id.bucket_suffix.hex}"
  tags   = { Name = "ProductImages" }
}

# --------------------------------------------------
# 4. APPLICATION LOAD BALANCER + EC2
# --------------------------------------------------

resource "aws_lb" "alb" {
  name               = "thedungeonshelf-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.web_sg.id]
  tags               = { Name = "ALB" }
}

resource "aws_lb_target_group" "tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_instance" "web" {
  count                       = 2
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
    yum install -y nodejs git
    # aquí podrías clonar tu repo y ejecutar tu servicio
  EOF

  tags = { Name = "Web-${count.index}" }
}

resource "aws_lb_target_group_attachment" "attach" {
  count            = 2
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# --------------------------------------------------
# 5. AURORA MYSQL SERVERLESS v2
# --------------------------------------------------

resource "aws_db_subnet_group" "aurora_sg" {
  name       = "aurora-subnet-group"
  subnet_ids = [
    aws_subnet.private_1.id,
    aws_subnet.private_2.id
  ]
  tags = { Name = "AuroraSubnetGroup" }
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier        = "thedungeonshelf-aurora"
  engine                    = "aurora-mysql"
  engine_version            = "8.0.mysql_aurora.3.08.2"
  engine_mode               = "provisioned"
  database_name             = "appdb"
  master_username           = "admin"
  master_password           = "Nicooa6652"
  db_subnet_group_name      = aws_db_subnet_group.aurora_sg.name
  vpc_security_group_ids    = [aws_security_group.db_sg.id]

  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 2
  }

  skip_final_snapshot = true
  tags                = { Name = "AuroraServerlessV2" }
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  identifier            = "thedungeonshelf-aurora-1"
  cluster_identifier    = aws_rds_cluster.aurora.id
  instance_class        = "db.serverless"
  engine                = aws_rds_cluster.aurora.engine
  engine_version        = aws_rds_cluster.aurora.engine_version
  publicly_accessible   = false

  tags = { Name = "AuroraInstanceV2" }
}

# --------------------------------------------------
# 6. OUTPUTS
# --------------------------------------------------

output "alb_dns_name" {
  description = "DNS público del ALB"
  value       = aws_lb.alb.dns_name
}

output "rds_endpoint" {
  description = "Endpoint de Aurora"
  value       = aws_rds_cluster.aurora.endpoint
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3"
  value       = aws_s3_bucket.product_images.bucket
}

output "web_instance_ips" {
  description = "IPs públicas de las instancias web."
  value       = aws_instance.web[*].public_ip
}