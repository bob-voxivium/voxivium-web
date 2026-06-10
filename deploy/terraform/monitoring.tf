# =============================================================================
# Basic monitoring
# =============================================================================
# Alarms send email via an SNS topic. Subscribe yourself to the topic with:
#   aws sns subscribe --topic-arn <arn> --protocol email --notification-endpoint you@example.com
# (You'll have to confirm the subscription via the email link.)
# =============================================================================

resource "aws_sns_topic" "alarms" {
  name = "voxivium-alarms"
}

# Lambda error rate — fires if any of the four functions errors
locals {
  monitored_lambdas = {
    subscribe        = aws_lambda_function.subscribe.function_name
    list_subscribers = aws_lambda_function.list_subscribers.function_name
    contact          = aws_lambda_function.contact.function_name
    drain            = aws_lambda_function.drain_contact_queue.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.monitored_lambdas

  alarm_name          = "voxivium-${each.key}-errors"
  alarm_description   = "Lambda ${each.value} reported errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
}

output "alarms_topic_arn" {
  value       = aws_sns_topic.alarms.arn
  description = "Subscribe to this SNS topic to receive alarm notifications"
}
