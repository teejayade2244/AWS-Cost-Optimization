provider "aws" {
  region = var.aws_region
}

# IAM Role for Lambda Function with additional permissions for RDS and Cost Explorer
resource "aws_iam_role" "lambda_exec_role" {
  name               = "lambda-cost-opt-role"
  description        = "IAM role for Lambda function to detect underutilized resources"
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

# Custom IAM policy for the Lambda function with specific permissions
resource "aws_iam_policy" "lambda_cost_opt_policy" {
  name        = "LambdaCostOptimizationPolicy"
  description = "Permissions for cost optimization Lambda function"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "ce:GetCostAndUsage",
          "ce:GetReservationUtilization"
        ],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach custom policy and managed policies to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_policies" {
  for_each = toset([
    aws_iam_policy.lambda_cost_opt_policy.arn,
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
  ])
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = each.value
}

# SNS Topic for Cost Alerts with additional configuration
resource "aws_sns_topic" "alerts" {
  name              = "underutilized-resources-alerts"
  display_name      = "Underutilized Resources Alerts"
  kms_master_key_id = "alias/aws/sns" # Use AWS managed KMS key
  
  tags = {
    Environment = var.environment
    Project     = "Cost-Optimization"
    Owner       = "CloudOps"
  }
}

# Multiple SNS Topic Subscriptions (email and Lambda for automated actions)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.email_endpoint
  
  # Only confirm subscription automatically in non-production
  confirmation_timeout_in_minutes = var.environment == "prod" ? 30 : 0
}

# Lambda function deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda_function_payload.zip"
  
  excludes = [
    "__pycache__",
    "*.pyc"
  ]
}

# Lambda Function with enhanced configuration
resource "aws_lambda_function" "cost_optimizer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "underutilized-resources-detector"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "main.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  description = "Detects underutilized EC2, EBS, and RDS resources and sends alerts"
  timeout     = 120 # Increased timeout for processing all resources
  memory_size = 256
  
  environment {
    variables = {
      SNS_TOPIC_ARN          = aws_sns_topic.alerts.arn
      EC2_CPU_THRESHOLD      = var.ec2_cpu_threshold
      EBS_IOPS_THRESHOLD     = var.ebs_iops_threshold
      RDS_CPU_THRESHOLD      = var.rds_cpu_threshold
      EVALUATION_PERIOD_DAYS = var.evaluation_period_days
      ENVIRONMENT           = var.environment
    }
  }

  tracing_config {
    mode = "Active" 
  }
  
  tags = {
    CostCenter = "CloudOptimization"
  }
}

# CloudWatch Log Group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.cost_optimizer.function_name}"
  retention_in_days = 30
  
  tags = {
    Application = "CostOptimization"
  }
}

# CloudWatch Event Rule with improved scheduling
resource "aws_cloudwatch_event_rule" "daily_trigger" {
  name                = "underutilized-resources-check"
  description         = "Triggers daily check for underutilized resources"
  schedule_expression = "cron(0 20 ? * MON-FRI *)" 
  
  tags = {
    Purpose = "CostOptimization"
  }
}

# CloudWatch Event Target with input transformation
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.daily_trigger.name
  target_id = "invoke-underutilized-resources-check"
  arn       = aws_lambda_function.cost_optimizer.arn
  
  input = jsonencode({
    "checkType" : "fullScan",
    "regions" : [var.aws_region]
  })
}

# Lambda Permission for EventBridge with condition
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimizer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_trigger.arn
}

# CloudWatch Alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${aws_lambda_function.cost_optimizer.function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 3600 # 1 hour
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    FunctionName = aws_lambda_function.cost_optimizer.function_name
  }
  
  alarm_description = "This alarm triggers when the cost optimization Lambda function has errors"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  
  tags = {
    Service = "CostOptimization"
  }
}

