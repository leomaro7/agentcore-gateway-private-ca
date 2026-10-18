# AgentCore Gateway からプライベート CA 署名の MCP サーバーへ直接つなぐ

[Amazon Bedrock AgentCore Gateway がプライベート CA の TLS 証明書に対応](https://aws.amazon.com/jp/about-aws/whats-new/2026/10/agentcore-gateway-private-tls-vpc/)（2026-10）の検証用コード。

検証環境: Terraform 1.16.3 / hashicorp/aws 6.69.1 / hashicorp/tls 4.4.1 / AWS CLI 2.37.7 / ap-northeast-1

## 構成

ターゲットの `certificateConfigurations` は hashicorp/aws 6.69.1 にも CloudFormation（`AWS::BedrockAgentCore::GatewayTarget`）にもまだ無いため、**土台は Terraform、ターゲットだけ AWS CLI** で作る。

```
versions.tf     terraform 1.16+ / aws ~> 6.69 / tls ~> 4.4
variables.tf    region, name_prefix, mcp_domain
certs.tf        検証用プライベート CA（CA:TRUE）と mcp.corp.internal 用サーバー証明書
main.tf         VPC（出口なし）・EC2 の MCP サーバー・プライベートホストゾーン・CA を置く S3・Gateway（AWS_IAM）
mcp_server.py   tools/list と tools/call だけ返す最小の MCP サーバー（Python 標準ライブラリのみ）
outputs.tf      Gateway ID/URL・CA の S3 URI・--private-endpoint 用 JSON
```

CA とサーバーの秘密鍵が state に入るので、検証専用。

## 使い方

```bash
terraform init
terraform apply

export AWS_REGION=ap-northeast-1
GW_ID=$(terraform output -raw gateway_id)
terraform output -raw private_endpoint_json > private-endpoint.json
cat > target.json <<EOF
{"mcp": {"mcpServer": {"endpoint": "$(terraform output -raw mcp_endpoint)"}}}
EOF
cat > certificate.json <<EOF
[{"s3": {"uri": "$(terraform output -raw ca_s3_uri)"}}]
EOF

# CA あり（--certificate-configurations を外すと PKIX path building failed で FAILED）
T2=$(aws bedrock-agentcore-control create-gateway-target --gateway-identifier $GW_ID --name with-ca \
  --private-endpoint file://private-endpoint.json --target-configuration file://target.json \
  --certificate-configurations file://certificate.json \
  --query targetId --output text)

# 後片付け: CLI で作ったターゲットを先に消す
aws bedrock-agentcore-control delete-gateway-target --gateway-identifier $GW_ID --target-id $T2
terraform destroy
```
