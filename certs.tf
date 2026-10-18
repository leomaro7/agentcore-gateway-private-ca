# 検証用のプライベート CA と、それで署名した MCP サーバー証明書
# （本番では社内の CA を使う想定。秘密鍵が state に入るので検証専用）

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Gateway に登録するのはこの CA の証明書（MCP サーバーの証明書ではない）
resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true # CA:TRUE。付いていないとターゲットが FAILED になる
  validity_period_hours = 24 * 30
  allowed_uses          = ["cert_signing", "crl_signing"]

  subject {
    common_name = "Demo Private Root CA"
  }
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem
  dns_names       = [var.mcp_domain]

  subject {
    common_name = var.mcp_domain
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem      = tls_cert_request.server.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 24 * 7
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth"]
}
