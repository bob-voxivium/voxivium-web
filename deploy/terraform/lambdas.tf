# =============================================================================
# Lambda functions and their IAM roles
# =============================================================================
# Each Lambda gets its own role with the minimum permissions it needs.
# That way a bug or compromise in one function can't reach resources owned
# by another. This is more verbose than a single shared role but it's the
# right pattern for production.
# =============================================================================

# -------- Shared trust policy: Lambda service can assume these roles --------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# -------- Package each Lambda into a zip --------
data "archive_file" "subscribe" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/subscribe"
  output_path = "${path.module}/.build/subscribe.zip"
}

data "archive_file" "list_subscribers" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/list_subscribers"
  output_path = "${path.module}/.build/list_subscribers.zip"
}

data "archive_file" "contact" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/contact"
  output_path = "${path.module}/.build/contact.zip"
}

data "archive_file" "drain_contact_queue" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/drain_contact_queue"
  output_path = "${path.module}/.build/drain_contact_queue.zip"
}

# =============================================================================
# Lambda 1: subscribe — POST /subscribe → DynamoDB (voter records)
# =============================================================================
resource "aws_iam_role" "subscribe" {
  name               = "voxivium-subscribe-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "subscribe" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
  }
  # Voter signups are PutItem-only; uniqueness is enforced via a conditional
  # write so re-subscribing doesn't clobber the original timestamp.
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.submissions.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.turnstile_secret_key.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${var.aws_region}:*:alias/aws/ssm"]
  }
}

resource "aws_iam_role_policy" "subscribe" {
  role   = aws_iam_role.subscribe.id
  policy = data.aws_iam_policy_document.subscribe.json
}

resource "aws_lambda_function" "subscribe" {
  function_name    = "voxivium-subscribe"
  role             = aws_iam_role.subscribe.arn
  filename         = data.archive_file.subscribe.output_path
  source_code_hash = data.archive_file.subscribe.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      SUBMISSIONS_TABLE      = aws_dynamodb_table.submissions.name
      TURNSTILE_SECRET_PARAM = aws_ssm_parameter.turnstile_secret_key.name
      ALLOWED_ORIGIN         = "https://${var.domain_name}"
      SES_FROM_ADDRESS       = var.ses_from_address
      SUPPORT_RECIPIENT      = var.support_recipient
      PRIVACY_RECIPIENT      = var.privacy_recipient
    }
  }
}

resource "aws_cloudwatch_log_group" "subscribe" {
  name              = "/aws/lambda/${aws_lambda_function.subscribe.function_name}"
  retention_in_days = 30
}

# =============================================================================
# Lambda 2: list_subscribers — admin-only, invoked via CLI/console
# =============================================================================
resource "aws_iam_role" "list_subscribers" {
  name               = "voxivium-list-subscribers-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "list_subscribers" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:Scan"]
    resources = [aws_dynamodb_table.submissions.arn]
  }
}

resource "aws_iam_role_policy" "list_subscribers" {
  role   = aws_iam_role.list_subscribers.id
  policy = data.aws_iam_policy_document.list_subscribers.json
}

resource "aws_lambda_function" "list_subscribers" {
  function_name    = "voxivium-list-subscribers"
  role             = aws_iam_role.list_subscribers.arn
  filename         = data.archive_file.list_subscribers.output_path
  source_code_hash = data.archive_file.list_subscribers.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      SUBMISSIONS_TABLE = aws_dynamodb_table.submissions.name
    }
  }
}

resource "aws_cloudwatch_log_group" "list_subscribers" {
  name              = "/aws/lambda/${aws_lambda_function.list_subscribers.function_name}"
  retention_in_days = 30
}

# =============================================================================
# Lambda 3: contact — POST /contact → DynamoDB with pending flag
# =============================================================================
resource "aws_iam_role" "contact" {
  name               = "voxivium-contact-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "contact" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.submissions.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.turnstile_secret_key.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${var.aws_region}:*:alias/aws/ssm"]
  }
  # Support requests are emailed inline instead of waiting for the daily
  # drain — the App Store support address can't have a 24h response floor.
  # Sender is pinned to the verified identity, same condition as the drain.
  statement {
    effect    = "Allow"
    actions   = ["ses:SendEmail"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.ses_from_address]
    }
  }
}

resource "aws_iam_role_policy" "contact" {
  role   = aws_iam_role.contact.id
  policy = data.aws_iam_policy_document.contact.json
}

resource "aws_lambda_function" "contact" {
  function_name    = "voxivium-contact"
  role             = aws_iam_role.contact.arn
  filename         = data.archive_file.contact.output_path
  source_code_hash = data.archive_file.contact.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 256

  environment {
    variables = {
      SUBMISSIONS_TABLE      = aws_dynamodb_table.submissions.name
      TURNSTILE_SECRET_PARAM = aws_ssm_parameter.turnstile_secret_key.name
      ALLOWED_ORIGIN         = "https://${var.domain_name}"
    }
  }
}

resource "aws_cloudwatch_log_group" "contact" {
  name              = "/aws/lambda/${aws_lambda_function.contact.function_name}"
  retention_in_days = 30
}

# =============================================================================
# Lambda 4: drain_contact_queue — scheduled, queries pending GSI and emails
# =============================================================================
# Despite the historical name, this no longer drains an SQS queue. It queries
# the sparse `pending-index` GSI on the submissions table, sends one SES
# email per item, removes the pending flag on success, and finally sends a
# single SMS if at least one email succeeded.
resource "aws_iam_role" "drain_contact_queue" {
  name               = "voxivium-drain-contact-queue-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "drain_contact_queue" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:*:*"]
  }
  # Read the sparse pending GSI; clear the flag on the base table after each send.
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:Query",
      "dynamodb:UpdateItem",
    ]
    resources = [
      aws_dynamodb_table.submissions.arn,
      "${aws_dynamodb_table.submissions.arn}/index/pending-index",
    ]
  }
  # Send one email per pending item via SES — sender restricted by condition.
  statement {
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.ses_from_address]
    }
  }
  statement {
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.textbelt_api_key.arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${var.aws_region}:*:alias/aws/ssm"]
  }
}

resource "aws_iam_role_policy" "drain_contact_queue" {
  role   = aws_iam_role.drain_contact_queue.id
  policy = data.aws_iam_policy_document.drain_contact_queue.json
}

resource "aws_lambda_function" "drain_contact_queue" {
  function_name    = "voxivium-drain-contact-queue"
  role             = aws_iam_role.drain_contact_queue.arn
  filename         = data.archive_file.drain_contact_queue.output_path
  source_code_hash = data.archive_file.drain_contact_queue.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120
  memory_size      = 256

  environment {
    variables = {
      SUBMISSIONS_TABLE    = aws_dynamodb_table.submissions.name
      PENDING_INDEX_NAME   = "pending-index"
      SES_FROM_ADDRESS     = var.ses_from_address
      DIGEST_RECIPIENT     = var.digest_recipient
      SUPPORT_RECIPIENT    = var.support_recipient
      PRIVACY_RECIPIENT    = var.privacy_recipient
      SMS_RECIPIENT_NUMBER = var.sms_recipient_number
      SMS_ADMIN_EMAIL      = var.sms_admin_email
      TEXTBELT_KEY_PARAM   = aws_ssm_parameter.textbelt_api_key.name
    }
  }
}

resource "aws_cloudwatch_log_group" "drain_contact_queue" {
  name              = "/aws/lambda/${aws_lambda_function.drain_contact_queue.function_name}"
  retention_in_days = 30
}

# -------- EventBridge schedule: run drain Lambda every 24 hours --------
resource "aws_cloudwatch_event_rule" "daily_drain" {
  name                = "voxivium-daily-contact-drain"
  description         = "Triggers drain_contact_queue Lambda every 24 hours"
  schedule_expression = "rate(24 hours)"
}

resource "aws_cloudwatch_event_target" "daily_drain" {
  rule      = aws_cloudwatch_event_rule.daily_drain.name
  target_id = "drain-contact-queue"
  arn       = aws_lambda_function.drain_contact_queue.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drain_contact_queue.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_drain.arn
}
