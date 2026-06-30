provider "aws" {
  region = "us-east-1"
}

# Dynamically fetch the latest official Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Key Pair resource to automatically push your public key to AWS
resource "aws_key_pair" "drupal_key" {
  key_name   = var.key_name
  public_key = file("~/.ssh/Addosser-key.pub")
}

# VPC
resource "aws_vpc" "drupal_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "drupal-vpc" }
}

# Subnets in two availability zones
resource "aws_subnet" "subnet_az1" {
  vpc_id                  = aws_vpc.drupal_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "drupal-subnet-az1" }
}

resource "aws_subnet" "subnet_az2" {
  vpc_id                  = aws_vpc.drupal_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags                    = { Name = "drupal-subnet-az2" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.drupal_vpc.id
}

# Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.drupal_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.subnet_az1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.subnet_az2.id
  route_table_id = aws_route_table.public_rt.id
}

# Security Group
resource "aws_security_group" "drupal_sg" {
  name   = "drupal-sg"
  vpc_id = aws_vpc.drupal_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instances (two app servers referencing the data block)
resource "aws_instance" "drupal_server_1" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet_az1.id
  vpc_security_group_ids = [aws_security_group.drupal_sg.id]
  key_name               = var.key_name
  tags                   = { Name = "drupal-server-1" }

  depends_on = [aws_key_pair.drupal_key]
}

resource "aws_instance" "drupal_server_2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.subnet_az2.id
  vpc_security_group_ids = [aws_security_group.drupal_sg.id]
  key_name               = var.key_name
  tags                   = { Name = "drupal-server-2" }

  depends_on = [aws_key_pair.drupal_key]
}

# RDS MySQL Database
resource "aws_db_instance" "drupal_db" {
  identifier             = "drupal-db"
  engine                 = "mysql"
  engine_version          = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "drupal"
  username               = var.db_username
  password               = var.db_password
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.drupal_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.drupal_db_subnet.name
}

resource "aws_db_subnet_group" "drupal_db_subnet" {
  name       = "drupal-db-subnet"
  subnet_ids = [aws_subnet.subnet_az1.id, aws_subnet.subnet_az2.id]
}

# Application Load Balancer
resource "aws_lb" "drupal_alb" {
  name               = "drupal-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.drupal_sg.id]
  subnets            = [aws_subnet.subnet_az1.id, aws_subnet.subnet_az2.id]
}

resource "aws_lb_target_group" "drupal_tg" {
  name     = "drupal-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.drupal_vpc.id
}

resource "aws_lb_listener" "drupal_listener" {
  load_balancer_arn = aws_lb.drupal_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.drupal_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "tg_attachment_1" {
  target_group_arn = aws_lb_target_group.drupal_tg.arn
  target_id        = aws_instance.drupal_server_1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "tg_attachment_2" {
  target_group_arn = aws_lb_target_group.drupal_tg.arn
  target_id        = aws_instance.drupal_server_2.id
  port             = 80
}