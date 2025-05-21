# Outputs for easy reference
output "lambda_function_name" {
  value       = aws_lambda_function.cost_optimizer.function_name
  description = "Name of the deployed Lambda function"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "ARN of the SNS topic for alerts"
}

output "cloudwatch_rule_arn" {
  value       = aws_cloudwatch_event_rule.daily_trigger.arn
  description = "ARN of the CloudWatch Event Rule"
}