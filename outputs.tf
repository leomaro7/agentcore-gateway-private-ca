output "gateway_id" {
  value = aws_bedrockagentcore_gateway.this.gateway_id
}

output "gateway_url" {
  value = aws_bedrockagentcore_gateway.this.gateway_url
}

output "mcp_endpoint" {
  value = "https://${var.mcp_domain}/mcp"
}

output "ca_s3_uri" {
  value = "s3://${aws_s3_bucket.ca.id}/${aws_s3_object.ca.key}"
}

# create-gateway-target の --private-endpoint にそのまま渡す JSON
output "private_endpoint_json" {
  value = jsonencode({
    managedVpcResource = {
      vpcIdentifier         = aws_vpc.this.id
      subnetIds             = aws_subnet.this[*].id
      endpointIpAddressType = "IPV4"
      securityGroupIds      = [aws_security_group.resource_gateway.id]
    }
  })
}
