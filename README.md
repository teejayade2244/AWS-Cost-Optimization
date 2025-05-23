# 🛠️ AWS Cost Optimization via Automated Resource Monitoring

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
