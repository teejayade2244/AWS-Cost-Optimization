variable "region" {
  description = "AWS region"
  type        = string
}

variable "email_endpoint" {
  description = "Email to receive cost alerts"
  type        = string
}

variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
}

variable "schedule_expression" {
  description = "CloudWatch EventBridge schedule for weekends"
  type        = string
  default     = "cron(0 0 ? * FRI *)"
}
