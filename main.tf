data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------- ネットワーク（インターネットへの出口は作らない） ----------

resource "aws_vpc" "this" {
  cidr_block           = "10.80.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.name_prefix }
}

resource "aws_subnet" "this" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.80.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.name_prefix}-${count.index}" }
}

# Gateway が VPC に置く入口（resource gateway の ENI）用
resource "aws_security_group" "resource_gateway" {
  name        = "${var.name_prefix}-rg"
  description = "resource gateway"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }
}

# MCP サーバー用（入口からの 443 だけ許可）
resource "aws_security_group" "mcp_server" {
  name        = "${var.name_prefix}-mcp"
  description = "mcp server"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.resource_gateway.id]
  }
}

# ---------- MCP サーバー（社内 CA 署名の証明書で HTTPS） ----------

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_instance" "mcp_server" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.this[0].id
  vpc_security_group_ids      = [aws_security_group.mcp_server.id]
  user_data_replace_on_change = true
  tags                        = { Name = "${var.name_prefix}-mcp" }

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /opt/mcp
    cat > /opt/mcp/server.pem <<'PEM'
    ${trimspace(tls_locally_signed_cert.server.cert_pem)}
    PEM
    cat > /opt/mcp/server.key <<'PEM'
    ${trimspace(tls_private_key.server.private_key_pem)}
    PEM
    base64 -d > /opt/mcp/server.py <<'B64'
    ${base64encode(file("${path.module}/mcp_server.py"))}
    B64
    nohup python3 /opt/mcp/server.py > /var/log/mcp.log 2>&1 &
  EOT
}

# VPC の中だけで引ける DNS 名 → EC2 のプライベート IP
resource "aws_route53_zone" "internal" {
  name = join(".", slice(split(".", var.mcp_domain), 1, length(split(".", var.mcp_domain))))

  vpc {
    vpc_id = aws_vpc.this.id
  }
}

resource "aws_route53_record" "mcp" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = var.mcp_domain
  type    = "A"
  ttl     = 60
  records = [aws_instance.mcp_server.private_ip]
}

# ---------- 社内 CA の証明書を S3 に置く ----------

resource "aws_s3_bucket" "ca" {
  bucket        = "agentcore-private-ca-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_object" "ca" {
  bucket  = aws_s3_bucket.ca.id
  key     = "ca.pem"
  content = tls_self_signed_cert.ca.cert_pem
}

# ---------- Gateway と実行ロール ----------

resource "aws_iam_role" "gateway" {
  name = "${var.name_prefix}-agentcore-gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock-agentcore.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

# Gateway は CA の証明書をこのロール（Gateway の実行ロール）で読みに行く
resource "aws_iam_role_policy" "gateway_ca_read" {
  role = aws_iam_role.gateway.id
  name = "ca-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.ca.arn}/${aws_s3_object.ca.key}"
    }]
  })
}

resource "aws_bedrockagentcore_gateway" "this" {
  name            = "${var.name_prefix}-gw"
  role_arn        = aws_iam_role.gateway.arn
  protocol_type   = "MCP"
  authorizer_type = "AWS_IAM" # privateEndpoint のターゲットは NONE だと作れない（インターセプター Lambda を設定した場合を除く）

  depends_on = [aws_iam_role_policy.gateway_ca_read]
}
