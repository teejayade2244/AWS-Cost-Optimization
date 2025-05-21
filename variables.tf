# Variables with descriptions and default values
variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "email_endpoint" {
  description = "Email address to receive underutilized resource alerts"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "ec2_cpu_threshold" {
  description = "CPU utilization threshold percentage for EC2 instances"
  type        = number
  default     = 10.0
}

variable "ebs_iops_threshold" {
  description = "IOPS threshold for EBS volumes"
  type        = number
  default     = 100
}

variable "rds_cpu_threshold" {
  description = "CPU utilization threshold percentage for RDS instances"
  type        = number
  default     = 10.0
}

variable "evaluation_period_days" {
  description = "Number of days to evaluate metrics for underutilization"
  type        = number
  default     = 14
}

