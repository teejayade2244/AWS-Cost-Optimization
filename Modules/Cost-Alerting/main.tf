provider "aws" {
  region = var.region
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.lambda_function_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
  ])
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = each.value
}

resource "aws_sns_topic" "alerts" {
  name = "${var.lambda_function_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email_endpoint
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/function.zip"
}

resource "aws_lambda_function" "cost_optimizer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "trigger" {
  name                = "${var.lambda_function_name}-schedule"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.trigger.name
  target_id = "lambda"
  arn       = aws_lambda_function.cost_optimizer.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.trigger.arn
}
