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

