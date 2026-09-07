# sg ALB
resource "aws_security_group" "sg_alb" {
  name        = "proj05-alb-${terraform.workspace}"
  description = "SG-ALB - public HTTP/HTTPS traffic to ALB"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "SG-ALB-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_sg_alb_one" {
  security_group_id = aws_security_group.sg_alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "sg_alb_to_app_http" {
  security_group_id            = aws_security_group.sg_alb.id
  referenced_security_group_id = aws_security_group.sg_app.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# sg app
resource "aws_security_group" "sg_app" {
  name        = "proj05-app-${terraform.workspace}"
  description = "SG-App - traffic from SG-ALB to application"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "SG-App-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_app_one" {
  security_group_id            = aws_security_group.sg_app.id
  from_port                    = 8080
  ip_protocol                  = "tcp"
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.sg_alb.id
}

resource "aws_vpc_security_group_egress_rule" "sg_app_to_db" {
  security_group_id            = aws_security_group.sg_app.id
  referenced_security_group_id = aws_security_group.sg_db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "sg_app_to_https" {
  security_group_id = aws_security_group.sg_app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# sg db
resource "aws_security_group" "sg_db" {
  name        = "proj05-db-${terraform.workspace}"
  description = "SG-DB - traffic from SG-App to database"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "SG-DB-${terraform.workspace}"
    Project     = "proj05"
    Environment = terraform.workspace
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_app_only" {
  security_group_id            = aws_security_group.sg_db.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.sg_app.id
}

# nacl
resource "aws_network_acl" "main" {
  vpc_id = var.vpc_id
}

resource "aws_network_acl_rule" "nacl_in_one" {
  network_acl_id = aws_network_acl.main.id
  egress         = false
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "10.0.10.0/24"
}

resource "aws_network_acl_rule" "nacl_out_one" {
  network_acl_id = aws_network_acl.main.id
  egress         = true
  rule_number    = 100
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "10.0.10.0/24"
}

resource "aws_network_acl_rule" "nacl_in_two" {
  network_acl_id = aws_network_acl.main.id
  egress         = false
  rule_number    = 110
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "10.0.20.0/24"
}

resource "aws_network_acl_rule" "nacl_out_two" {
  network_acl_id = aws_network_acl.main.id
  egress         = true
  rule_number    = 110
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "10.0.20.0/24"
}

resource "aws_network_acl_rule" "nacl_in_three" {
  network_acl_id = aws_network_acl.main.id
  egress         = false
  rule_number    = 120
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "nacl_out_three" {
  network_acl_id = aws_network_acl.main.id
  egress         = true
  rule_number    = 120
  protocol       = "-1"
  rule_action    = "deny"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_association" "nacl_assoc_az1" {
  network_acl_id = aws_network_acl.main.id
  subnet_id      = var.isolated_subnet_az1_id
}

resource "aws_network_acl_association" "nacl_assoc_az2" {
  network_acl_id = aws_network_acl.main.id
  subnet_id      = var.isolated_subnet_az2_id
}