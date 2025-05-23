import boto3
from datetime import datetime, timedelta
import json
from typing import List, Tuple, Dict, Any

# Configuration
REGION = 'eu-west-2'
SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:123456789012:underutilized-resources'
EC2_CPU_THRESHOLD = 10    
CPU_LOOKBACK_DAYS = 7
EBS_SNAPSHOT_AGE_DAYS = 30
RDS_CPU_THRESHOLD = 10     
NETWORK_THRESHOLD = 1000   

# Clients
ec2 = boto3.client('ec2', region_name=REGION)
cloudwatch = boto3.client('cloudwatch', region_name=REGION)
sns = boto3.client('sns', region_name=REGION)
rds = boto3.client('rds', region_name=REGION)

def get_instance_tags(instance: Dict[str, Any]) -> Dict[str, str]:
    """Extract tags from an EC2 instance."""
    return {tag['Key']: tag['Value'] for tag in instance.get('Tags', [])}

def get_metric_average(namespace: str, metric_name: str, dimensions: List[Dict], 
                      days_back: int = CPU_LOOKBACK_DAYS) -> float:
    """Get average metric value over specified period."""
    try:
        response = cloudwatch.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dimensions,
            StartTime=datetime.utcnow() - timedelta(days=days_back),
            EndTime=datetime.utcnow(),
            Period=86400,  # Daily
            Statistics=['Average']
        )
        
        datapoints = response.get('Datapoints', [])
        if not datapoints:
            return 0.0
            
        return sum(dp['Average'] for dp in datapoints) / len(datapoints)
    except Exception as e:
        print(f"Error getting metrics: {e}")
        return 0.0


########################################################################################
# EC2 functions
########################################################################################
def check_underutilized_ec2() -> List[Tuple[str, float, str, Dict[str, str]]]:
    """Check for underutilized EC2 instances with enhanced metrics."""
    print("Checking underutilized EC2 instances...")
    underutilized = []
    
    try:
        instances = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )
        
        for reservation in instances['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_type = instance['InstanceType']
                tags = get_instance_tags(instance)
                
                # Skip if marked to ignore
                if tags.get('CostOptimization') == 'Ignore':
                    continue
                
                # Get CPU utilization
                cpu_avg = get_metric_average(
                    'AWS/EC2', 'CPUUtilization',
                    [{'Name': 'InstanceId', 'Value': instance_id}]
                )
                
                # Get network utilization
                network_in = get_metric_average(
                    'AWS/EC2', 'NetworkIn',
                    [{'Name': 'InstanceId', 'Value': instance_id}]
                )
                
                network_out = get_metric_average(
                    'AWS/EC2', 'NetworkOut',
                    [{'Name': 'InstanceId', 'Value': instance_id}]
                )
                
                # Consider underutilized if low CPU AND low network
                if (cpu_avg < EC2_CPU_THRESHOLD and 
                    network_in < NETWORK_THRESHOLD and 
                    network_out < NETWORK_THRESHOLD):
                    
                    underutilized.append((
                        instance_id, 
                        round(cpu_avg, 2), 
                        instance_type,
                        tags
                    ))
                    
    except Exception as e:
        print(f"Error checking EC2 instances: {e}")
    return underutilized

#######################################################################################
# RDS and EBS functions
####################################################################################
def check_underutilized_rds() -> List[Tuple[str, float, str]]:
    """Check for underutilized RDS instances."""
    print("Checking underutilized RDS instances...")
    underutilized = []
    
    try:
        db_instances = rds.describe_db_instances()
        
        for db in db_instances['DBInstances']:
            if db['DBInstanceStatus'] != 'available':
                continue
                
            db_id = db['DBInstanceIdentifier']
            db_class = db['DBInstanceClass']
            
            cpu_avg = get_metric_average(
                'AWS/RDS', 'CPUUtilization',
                [{'Name': 'DBInstanceIdentifier', 'Value': db_id}]
            )
            
            if cpu_avg < RDS_CPU_THRESHOLD:
                underutilized.append((db_id, round(cpu_avg, 2), db_class))
                
    except Exception as e:
        print(f"Error checking RDS instances: {e}")
    
    return underutilized

#######################################################################################
# EBS functions
#######################################################################################
def check_old_ebs_snapshots() -> List[Tuple[str, int, str, str]]:
    """Check for old EBS snapshots with enhanced info."""
    print("Checking old EBS snapshots...")
    old_snapshots = []
    now = datetime.utcnow()
    
    try:
        snapshots = ec2.describe_snapshots(OwnerIds=['self'])['Snapshots']
        
        for snap in snapshots:
            snap_id = snap['SnapshotId']
            start_time = snap['StartTime'].replace(tzinfo=None)
            age = (now - start_time).days
            volume_size = snap.get('VolumeSize', 0)
            
            tags = {t['Key']: t['Value'] for t in snap.get('Tags', [])}
            
            # Skip if marked to keep
            if any(tag in tags for tag in ['DoNotDelete', 'Keep', 'Backup']):
                continue
            
            if age > EBS_SNAPSHOT_AGE_DAYS:
                old_snapshots.append((
                    snap_id, 
                    age, 
                    tags.get('Name', 'Unnamed'),
                    f"{volume_size}GB"
                ))
                
    except Exception as e:
        print(f"Error checking EBS snapshots: {e}")
    
    return old_snapshots

#######################################################################################
# Unattached volumes functions
#######################################################################################
def check_unattached_volumes() -> List[Tuple[str, str, str]]:
    """Check for unattached EBS volumes."""
    print("Checking unattached EBS volumes...")
    unattached = []
    
    try:
        volumes = ec2.describe_volumes(
            Filters=[{'Name': 'status', 'Values': ['available']}]
        )
        
        for volume in volumes['Volumes']:
            volume_id = volume['VolumeId']
            size = volume['Size']
            volume_type = volume['VolumeType']
            
            tags = {t['Key']: t['Value'] for t in volume.get('Tags', [])}
            name = tags.get('Name', 'Unnamed')
            
            unattached.append((volume_id, f"{size}GB", name))
            
    except Exception as e:
        print(f"Error checking EBS volumes: {e}")
    
    return unattached

#######################################################################################
# Cost estimation functions
#######################################################################################
def estimate_monthly_savings(ec2_data: List, rds_data: List, volume_data: List) -> Dict[str, float]:
    """Estimate potential monthly savings (rough estimates)."""
    # Rough AWS pricing estimates (USD/month)
    ec2_pricing = {
        't2.micro': 8.5, 't2.small': 17, 't2.medium': 34,
        't3.micro': 7.5, 't3.small': 15, 't3.medium': 30,
        'm5.large': 70, 'm5.xlarge': 140, 'c5.large': 62
    }
    
    rds_pricing = {
        'db.t3.micro': 15, 'db.t3.small': 30, 'db.m5.large': 140
    }
    
    ec2_savings = sum(ec2_pricing.get(instance_type, 50) for _, _, instance_type, _ in ec2_data)
    rds_savings = sum(rds_pricing.get(db_class, 50) for _, _, db_class in rds_data)
    volume_savings = len(volume_data) * 8  # ~$8/month per 100GB volume
    
    return {
        'ec2': round(ec2_savings, 2),
        'rds': round(rds_savings, 2),
        'storage': round(volume_savings, 2),
        'total': round(ec2_savings + rds_savings + volume_savings, 2)
    }

#######################################################################################
# Publish alert functions
#######################################################################################
def publish_enhanced_alert(ec2_data: List, rds_data: List, ebs_data: List, volume_data: List):
    """Publish enhanced alert with cost estimates."""
    if not any([ec2_data, rds_data, ebs_data, volume_data]):
        print("No underutilized resources found.")
        return
    savings = estimate_monthly_savings(ec2_data, rds_data, volume_data)
    message = "*AWS Cost Optimization Report*\n"
    message += f"Estimated Monthly Savings: ${savings['total']}\n\n"
    
    if ec2_data:
        message += f"underutilized EC2 Instances (${savings['ec2']}/month):\n"
        for instance_id, cpu, instance_type, tags in ec2_data:
            name = tags.get('Name', 'Unnamed')
            message += f" - {instance_id} ({name}): {instance_type}, Avg CPU = {cpu}%\n"
        message += "\n"
    
    if rds_data:
        message += f"Underutilized RDS Instances (${savings['rds']}/month):\n"
        for db_id, cpu, db_class in rds_data:
            message += f" - {db_id}: {db_class}, Avg CPU = {cpu}%\n"
        message += "\n"
    
    if volume_data:
        message += f"Unattached EBS Volumes (${savings['storage']}/month):\n"
        for volume_id, size, name in volume_data:
            message += f" - {volume_id} ({name}): {size}\n"
        message += "\n"
    
    if ebs_data:
        message += f"Old EBS Snapshots (>{EBS_SNAPSHOT_AGE_DAYS} days):\n"
        for snap_id, age, name, size in ebs_data:
            message += f" - {snap_id} ({name}): {age} days old, {size}\n"
    
    message += "\n *Recommendations:*\n"
    message += "• Review and potentially terminate unused instances\n"
    message += "• Consider downsizing underutilized resources\n"
    message += "• Delete old snapshots after verification\n"
    message += "• Attach or delete unattached volumes\n"
    
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='AWS Cost Optimization Report - Potential Savings: $' + str(savings['total']),
            Message=message
        )
        print("Enhanced alert sent to SNS.")
    except Exception as e:
        print(f"Error sending SNS notification: {e}")

#######################################################################################
# Lambda handler
#######################################################################################
def lambda_handler(event, context):
    """Enhanced Lambda handler with comprehensive cost optimization checks."""
    try:
        print("Starting AWS cost optimization analysis...")
        
        ec2_underused = check_underutilized_ec2()
        rds_underused = check_underutilized_rds()
        old_snapshots = check_old_ebs_snapshots()
        unattached_volumes = check_unattached_volumes()
        
        publish_enhanced_alert(ec2_underused, rds_underused, old_snapshots, unattached_volumes)
        
        # Return summary for Lambda logs
        return {
            'statusCode': 200,
            'body': json.dumps({
                'underutilized_ec2': len(ec2_underused),
                'underutilized_rds': len(rds_underused),
                'old_snapshots': len(old_snapshots),
                'unattached_volumes': len(unattached_volumes)
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

# For local testing
if __name__ == "__main__":
    lambda_handler({}, {})