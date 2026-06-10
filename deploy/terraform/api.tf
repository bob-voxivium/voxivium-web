# =============================================================================
# API Gateway (HTTP API — cheaper and simpler than REST API)
# =============================================================================
# Two public routes:
#   POST /subscribe → subscribe Lambda
#   POST /contact   → contact Lambda
#
# Notes:
#   - CORS is locked to the production origin so the API can't be embedded
#     on attacker-controlled pages.
#   - Throttling is set on the default stage to prevent runaway costs from
#     bot abuse. Adjust the limits up if you have legitimate traffic spikes.
#   - The list_subscribers Lambda is INTENTIONALLY not exposed here.
# =============================================================================

resource "aws_apigatewayv2_api" "forms" {
  name          = "voxivium-forms-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins  = ["https://${var.domain_name}", "https://${var.site_subdomain}"]
    allow_methods  = ["POST", "OPTIONS"]
    allow_headers  = ["content-type"]
    max_age        = 3600
    allow_credentials = false
  }
}

# -------- Lambda integrations --------
resource "aws_apigatewayv2_integration" "subscribe" {
  api_id                 = aws_apigatewayv2_api.forms.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.subscribe.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "contact" {
  api_id                 = aws_apigatewayv2_api.forms.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact.invoke_arn
  payload_format_version = "2.0"
}

# -------- Routes --------
resource "aws_apigatewayv2_route" "subscribe" {
  api_id    = aws_apigatewayv2_api.forms.id
  route_key = "POST /subscribe"
  target    = "integrations/${aws_apigatewayv2_integration.subscribe.id}"
}

resource "aws_apigatewayv2_route" "contact" {
  api_id    = aws_apigatewayv2_api.forms.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact.id}"
}

# -------- Stage with throttling and access logs --------
resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/voxivium-forms-api"
  retention_in_days = 30
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.forms.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20  # max concurrent
    throttling_rate_limit  = 10  # requests/second sustained
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

# -------- Allow API Gateway to invoke each Lambda --------
resource "aws_lambda_permission" "subscribe_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subscribe.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.forms.execution_arn}/*/*"
}

resource "aws_lambda_permission" "contact_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.forms.execution_arn}/*/*"
}

output "api_endpoint" {
  value       = aws_apigatewayv2_api.forms.api_endpoint
  description = "Base URL for form submissions (POST to /subscribe and /contact)"
}
