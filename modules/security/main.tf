resource "aws_security_group" "alb" {
  name        = "production-platform-alb-sg"
  description = "Security group for ALB"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  description       = "Allow inbound HTTP from internet to Application Load Balancer"
  from_port         = 80
  to_port           = 80
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ec2" {
  description                  = "Allow outbound HTTP from Application Load Balancer to EC2 instances"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_security_group" "ec2" {
  name        = "production-platform-ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb" {
  description                  = "Allow inbound HTTP from Application Load Balancer only"
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_endpoint" {
  description                  = "Allow outbound HTTPS from EC2 instances to VPC Interface Endpoints"
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = aws_security_group.vpc_endpoints.id
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "production-platform-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  description                  = "Allow inbound HTTPS to VPC Interface Endpoints from EC2 instances"
  security_group_id            = aws_security_group.vpc_endpoints.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_default_security_group" "default" {
  vpc_id = var.vpc_id
  tags = {
    Name = "default-restricted"
  }
}
