#!/bin/bash

# Aurora MySQL Cluster Setup Script for CAM LE


set -e  # Exit on any error

# Set environment variables - use environment or defaults
export AWS_REGION=${CAM_AWS_REGION:-${AWS_REGION:-ap-southeast-2}}
export DB_CLUSTER_IDENTIFIER=${CAM_DB_CLUSTER_NAME:-${DB_CLUSTER_IDENTIFIER:-cam-le-aurora-prod}}
export DB_INSTANCE_IDENTIFIER=${CAM_DB_INSTANCE_NAME:-${DB_INSTANCE_IDENTIFIER:-cam-le-aurora-db-1}}
export DB_INSTANCE_CLASS=${CAM_DB_INSTANCE_CLASS:-${DB_INSTANCE_CLASS:-db.r6g.large}}
export DB_USERNAME=${CAM_DB_USERNAME:-${DB_USERNAME:-admin}}
export DB_PASSWORD=${CAM_DB_PASSWORD:-${DB_PASSWORD:-ChangeMe_DBPassword123!}}
export DB_NAME=${CAM_DB_NAME:-${DB_NAME:-masherysolar}}
export CLUSTER_NAME=${CAM_CLUSTER_NAME:-${CLUSTER_NAME:-cam-le-cluster}}

echo "========================================="
echo "Aurora MySQL Cluster Setup for CAM LE"
echo "========================================="
echo "Region: ${AWS_REGION}"
echo "Cluster Name: ${DB_CLUSTER_IDENTIFIER}"
echo "Instance Class: ${DB_INSTANCE_CLASS}"
echo "Database Name: ${DB_NAME}"
echo ""

# Step 1: Get VPC and subnet information from EKS cluster
echo "Step 1: Getting VPC and subnet information from EKS cluster..."
VPC_ID=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

if [ -z "$VPC_ID" ]; then
    echo "Error: Could not get VPC ID from EKS cluster '${CLUSTER_NAME}'"
    echo "Make sure the EKS cluster exists and you have the correct region/cluster name"
    exit 1
fi

echo "Found VPC: ${VPC_ID}"

# Step 2: Get private subnets for DB subnet group (must span at least 2 AZs)
echo ""
echo "Step 2: Getting private subnets across multiple Availability Zones..."

# First try: Get subnets tagged for internal ELB (private subnets)
echo "  Trying private subnets (kubernetes.io/role/internal-elb tag)..."
SUBNET_DATA=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
  --query "Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]" \
  --output text \
  --region ${AWS_REGION} 2>/dev/null || true)

# Second try: Get all non-public subnets
if [ -z "$SUBNET_DATA" ]; then
    echo "  No tagged private subnets found. Trying all non-public subnets..."
    SUBNET_DATA=$(aws ec2 describe-subnets \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=map-public-ip-on-launch,Values=false" \
      --query "Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]" \
      --output text \
      --region ${AWS_REGION} 2>/dev/null || true)
fi

# Third try: Get ALL subnets and filter
if [ -z "$SUBNET_DATA" ]; then
    echo "  Getting all subnets in VPC..."
    ALL_SUBNETS=$(aws ec2 describe-subnets \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query "Subnets[*].[SubnetId,AvailabilityZone,MapPublicIpOnLaunch]" \
      --output text \
      --region ${AWS_REGION})
    
    # Prefer private subnets (MapPublicIpOnLaunch=false)
    SUBNET_DATA=$(echo "$ALL_SUBNETS" | grep -E "False|false" || echo "$ALL_SUBNETS")
fi

if [ -z "$SUBNET_DATA" ]; then
    echo "ERROR: No subnets found in VPC ${VPC_ID}"
    echo "Please verify:"
    echo "  1. EKS cluster ${CLUSTER_NAME} exists in region ${AWS_REGION}"
    echo "  2. VPC has subnets configured"
    exit 1
fi

# Extract subnet IDs and AZs
SUBNET_IDS=$(echo "$SUBNET_DATA" | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//')
UNIQUE_AZS=$(echo "$SUBNET_DATA" | awk '{print $2}' | sort -u)
AZ_COUNT=$(echo "$UNIQUE_AZS" | wc -l | tr -d ' ')

echo ""
echo "Subnet Discovery Results:"
echo "  Subnets found: $(echo $SUBNET_IDS | wc -w | tr -d ' ')"
echo "  Subnet IDs: ${SUBNET_IDS}"
echo "  Availability Zones: ${AZ_COUNT}"
echo "$UNIQUE_AZS" | sed 's/^/    - /'

# Aurora requires at least 2 AZs
if [ "$AZ_COUNT" -lt 2 ]; then
    echo ""
    echo "ERROR: Aurora requires subnets in at least 2 Availability Zones"
    echo "Current AZ coverage: ${AZ_COUNT} AZ(s)"
    echo ""
    echo "Detailed subnet information:"
    echo "$SUBNET_DATA" | awk '{printf "  Subnet %s in AZ %s (Public: %s)\n", $1, $2, $3}'
    echo ""
    echo "SOLUTION: Your EKS cluster VPC needs subnets in at least 2 different AZs."
    echo "Please recreate your EKS cluster with multi-AZ subnet configuration."
    exit 1
fi

echo "✓ Multi-AZ requirement satisfied (${AZ_COUNT} AZs)"

# Step 3: Delete existing DB subnet group if it exists (in case of previous failed attempt)
echo ""
echo "Step 3: Preparing DB subnet group..."
aws rds delete-db-subnet-group \
  --db-subnet-group-name cam-le-db-subnet-group \
  --region ${AWS_REGION} 2>/dev/null && echo "  Deleted old subnet group" || true

# Create new DB subnet group with verified multi-AZ subnets
echo "  Creating DB subnet group with ${AZ_COUNT} AZs..."
aws rds create-db-subnet-group \
  --db-subnet-group-name cam-le-db-subnet-group \
  --db-subnet-group-description "CAM LE Aurora subnet group (${AZ_COUNT} AZs)" \
  --subnet-ids ${SUBNET_IDS} \
  --region ${AWS_REGION}

# Verify the subnet group was created properly
echo "  Verifying subnet group..."
CREATED_AZS=$(aws rds describe-db-subnet-groups \
  --db-subnet-group-name cam-le-db-subnet-group \
  --region ${AWS_REGION} \
  --query "DBSubnetGroups[0].Subnets[].SubnetAvailabilityZone.Name" \
  --output text | tr '\t' '\n' | sort -u | wc -l | tr -d ' ')

echo "✓ DB subnet group created with ${CREATED_AZS} AZs"

# Step 4: Create security group for Aurora
echo ""
echo "Step 4: Creating security group for Aurora..."
DB_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
  --group-name cam-le-aurora-sg \
  --description "Security group for CAM LE Aurora MySQL" \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --query 'GroupId' \
  --output text 2>/dev/null || \
  aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=cam-le-aurora-sg" "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region ${AWS_REGION})

echo "Security Group ID: ${DB_SECURITY_GROUP_ID}"

# Step 5: Get EKS node security group
echo ""
echo "Step 5: Getting EKS cluster security group..."
EKS_NODE_SG=$(aws eks describe-cluster \
  --name ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text)

echo "EKS Security Group: ${EKS_NODE_SG}"

# Step 6: Allow MySQL traffic from EKS nodes
echo ""
echo "Step 6: Configuring security group ingress rules..."
aws ec2 authorize-security-group-ingress \
  --group-id ${DB_SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 3306 \
  --source-group ${EKS_NODE_SG} \
  --region ${AWS_REGION} 2>/dev/null || echo "Security group rule may already exist"

# Step 7: Create Aurora MySQL cluster
echo ""
echo "Step 7: Creating Aurora MySQL cluster (this may take 10-15 minutes)..."
aws rds create-db-cluster \
  --db-cluster-identifier ${DB_CLUSTER_IDENTIFIER} \
  --engine aurora-mysql \
  --engine-version 8.0.mysql_aurora.3.11.0 \
  --master-username ${DB_USERNAME} \
  --master-user-password ${DB_PASSWORD} \
  --database-name ${DB_NAME} \
  --db-subnet-group-name cam-le-db-subnet-group \
  --vpc-security-group-ids ${DB_SECURITY_GROUP_ID} \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "mon:04:00-mon:05:00" \
  --region ${AWS_REGION} \
  --tags Key=Application,Value=CAM-LE

# Step 8: Create Aurora instance (writer)
echo ""
echo "Step 8: Creating Aurora DB instance..."
aws rds create-db-instance \
  --db-instance-identifier ${DB_INSTANCE_IDENTIFIER} \
  --db-cluster-identifier ${DB_CLUSTER_IDENTIFIER} \
  --engine aurora-mysql \
  --db-instance-class ${DB_INSTANCE_CLASS} \
  --no-publicly-accessible \
  --region ${AWS_REGION}

# Step 9: Wait for cluster to be available
echo ""
echo "Step 9: Waiting for Aurora cluster to become available..."
echo "This will take approximately 10-15 minutes. Please be patient..."
aws rds wait db-cluster-available \
  --db-cluster-identifier ${DB_CLUSTER_IDENTIFIER} \
  --region ${AWS_REGION}

echo ""
echo "✅ Aurora cluster is now available!"

# Step 10: Get and display database endpoint
echo ""
echo "Step 10: Getting database connection details..."
DB_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier ${DB_CLUSTER_IDENTIFIER} \
  --region ${AWS_REGION} \
  --query "DBClusters[0].Endpoint" \
  --output text)

echo ""
echo "========================================="
echo "Aurora MySQL Cluster Created Successfully!"
echo "========================================="
echo "Database Endpoint: ${DB_ENDPOINT}"
echo "Database Port: 3306"
echo "Database Name: ${DB_NAME}"
echo "Username: ${DB_USERNAME}"
echo "Password: ${DB_PASSWORD}"
echo ""

# Save configuration to file
cat > db-config.env <<EOF
# Aurora MySQL Database Configuration
# Generated on $(date)
export DB_ENDPOINT=${DB_ENDPOINT}
export DB_PORT=3306
export DB_NAME=${DB_NAME}
export DB_USERNAME=${DB_USERNAME}
export DB_PASSWORD=${DB_PASSWORD}
export DB_SECURITY_GROUP_ID=${DB_SECURITY_GROUP_ID}
export AWS_REGION=${AWS_REGION}
EOF

echo "Configuration saved to: db-config.env"
echo ""
echo "To use these values in other scripts, run:"
echo "  source db-config.env"
echo ""
echo "Next steps:"
echo "1. Create DML user in the database"
echo "2. Create Kubernetes secrets"
echo "3. Deploy CAM LE using Helm"
echo "========================================="