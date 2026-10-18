variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "name_prefix" {
  type    = string
  default = "private-ca"
}

variable "mcp_domain" {
  description = "VPC 内でだけ引ける MCP サーバーのドメイン"
  type        = string
  default     = "mcp.corp.internal"
}
