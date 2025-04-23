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

resource "random_id" "alb_suffix" {
  byte_length = 2
}

resource "aws_lb" "alb" {
  name               = "thedungeonshelf-alb-${random_id.alb_suffix.hex}"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.web_sg.id]
  tags               = { Name = "ALB" }
}

resource "aws_lb_target_group" "tg" {
  name     = "web-tg-${random_id.alb_suffix.hex}"
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
# 5. DYNAMODB TABLE
# --------------------------------------------------

resource "aws_dynamodb_table" "product_table" {
  name         = "ProductTable-${random_id.bucket_suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ProductID"

  attribute {
    name = "ProductID"
    type = "S"
  }

  tags = { Name = "ProductTable" }
}

# --------------------------------------------------
# 6. OUTPUTS
# --------------------------------------------------

output "alb_dns_name" {
  description = "DNS público del ALB"
  value       = aws_lb.alb.dns_name
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3"
  value       = aws_s3_bucket.product_images.bucket
}

output "web_instance_ips" {
  description = "IPs públicas de las instancias web."
  value       = aws_instance.web[*].public_ip
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB"
  value       = aws_dynamodb_table.product_table.name
}
