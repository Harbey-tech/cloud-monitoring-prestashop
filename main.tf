# --- Provider ---
provider "aws" {
  region = "us-east-1"
}

# --- Variables ---
variable "vpc_id" {
  default = "vpc-0803f9717442c036c"
}

variable "public_subnets" {
  type    = list(string)
  default = ["subnet-0e3a9135e63086a8e", "subnet-0110dff0a08051758"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["subnet-00e12fa1a302c95a0", "subnet-008c203577dfcbff1"]
}

variable "ec2_instance_type" {
  # Free Tier Eligible
  default = "t3.micro"
}

variable "ec2_key_name" {
  default = "Ansible"
}

variable "rds_username" {
  default = "prestashop"
}

variable "rds_password" {
  default = "PrestashopPass123"
}

variable "rds_db_name" {
  default = "prestashop_db"
}

variable "ami_id" {
  default = "ami-0360c520857e3138f" # Ubuntu 24.04
}

# --- Security Groups ---
resource "aws_security_group" "ec2_sg" {
  name        = "prestashop-ec2-sg"
  description = "Allow SSH, HTTP, Prometheus, and Grafana access"
  vpc_id      = var.vpc_id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP (PrestaShop)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus
  ingress {
    description = "Prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana
  ingress {
    description = "Grafana"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prestashop-ec2-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "prestashop-rds-sg"
  description = "Allow MySQL access from EC2"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prestashop-rds-sg"
  }
}

# --- IAM Role & Profile ---
resource "aws_iam_role" "prestashop_role" {
  name = "prestashop-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "prestashop_rds_access" {
  role       = aws_iam_role.prestashop_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_instance_profile" "prestashop_profile" {
  name = "prestashop-instance-profile"
  role = aws_iam_role.prestashop_role.name
}

# --- EC2 Instance ---
resource "aws_instance" "prestashop_ec2" {
  ami                    = var.ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = var.public_subnets[0]
  key_name               = var.ec2_key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.prestashop_profile.name
  associate_public_ip_address = true

  tags = {
    Name = "prestashop-monitoring-server"
    Role = "PrestaShop + Prometheus + Grafana"
  }
}

# --- RDS MySQL ---
resource "aws_db_subnet_group" "prestashop_rds_subnets" {
  name       = "prestashop-rds-subnet-group"
  subnet_ids = var.private_subnets
}

resource "aws_db_instance" "prestashop_rds" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  identifier             = "prestashop-db"
  username               = var.rds_username
  password               = var.rds_password
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.prestashop_rds_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  storage_type           = "gp2"

  tags = {
    Name = "prestashop-rds"
  }
}

# --- Outputs for Ansible ---
output "ec2_public_ip" {
  value = aws_instance.prestashop_ec2.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.prestashop_rds.endpoint
}

output "rds_username" {
  value = var.rds_username
}

output "rds_password" {
  value = var.rds_password
}
