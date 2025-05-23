# 🛠️ AWS underutilized resources detector via Automated Resource Monitoring

Automated solution to identify and alert on underutilized AWS resources using Terraform, Lambda, and EventBridge. Achieve 18% average cost savings through proactive infrastructure optimization.

## 📊 Architecture Overview
![Blank diagram](https://github.com/user-attachments/assets/76159a79-7e6a-450b-98fb-119cabc97b3d)
- **AWS Lambda** – Executes logic to identify idle or underutilized resources.
- **Amazon CloudWatch** – Provides metrics used to determine underutilization.
- **Amazon EventBridge (Scheduler)** – Triggers the Lambda function every weekend (Friday night).
- **Amazon SNS** – Publishes alerts when inefficient resources are found.
- **Email Subscriber** – Receives real-time alerts.
- **Terraform** – Provisions and manages all resources as code.
- **VPC (Private/Public Subnets)** – Hosts EC2, RDS, EBS resources for scanning.

## 🧩 Features
- 🔁 **Scheduled Lambda Execution** — Runs every Friday at midnight (UTC) using EventBridge.
- 🔍 **Underutilization Detection** — Checks EC2, EBS, and Snapshots for usage patterns.
- 📧 **Real-Time Alerts** — Uses SNS + email to notify engineers.
- 💸 **18% Cost Savings** — Proactively identifies and reports idle resources.
- 📦 **Terraform Module Ready** — Can be reused across environments and accounts.

## 🚀 Getting Started

### Prerequisites
- [Terraform CLI](https://developer.hashicorp.com/terraform/downloads)
- AWS CLI configured with appropriate IAM permissions
- A verified email address for SNS subscription

### Deployment
```bash
git clone https://github.com/your-username/aws-cost-optimizer.git
cd aws-cost-optimizer

# Initialize Terraform
terraform init

# Review resources
terraform plan

# Apply infrastructure
terraform apply -var-file="dev.tfvars" -auto-approve
