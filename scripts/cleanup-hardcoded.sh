#!/bin/bash
# Direct cleanup script with hardcoded values from parent config

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}  CAM LE Complete Cleanup Script${NC}"
echo -e "${RED}  (Hardcoded for cam-le-test-cluster)${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will delete ALL resources:${NC}"
echo "  - EKS Cluster: cam-le-test-cluster"
echo "  - Aurora Database: cam-le-aurora-test"
echo "  - ECR Repositories (9 repos)"
echo ""
read -p "Are you sure you want to continue? Type 'YES' to confirm: " -r
echo ""

if [ "$REPLY" != "YES" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Hardcoded values from parent directory my-config.env
CLUSTER_NAME=cam-le-test-cluster
AWS_REGION=ap-southeast-2
DB_CLUSTER=cam-le-aurora-test
K8S_NAMESPACE=camle
AWS_ACCOUNT_ID=622467680580
ECR_REGISTRY=622467680580.dkr.ecr.ap-southeast-2.amazonaws.com

echo -e "${GREEN}=== Phase 1: Deleting EKS Cluster ===${NC}"
if eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo "Deleting EKS cluster: ${CLUSTER_NAME}"
    echo "This will take 10-15 minutes..."
    eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --wait
    echo "EKS cluster deleted"
else
    echo "EKS cluster ${CLUSTER_NAME} not found or already deleted"
fi
echo ""

echo -e "${GREEN}=== Phase 2: Deleting Aurora Database ===${NC}"
if aws rds describe-db-clusters --db-cluster-identifier ${DB_CLUSTER} --region ${AWS_REGION} &>/dev/null; then
    echo "Deleting Aurora cluster: ${DB_CLUSTER}"
    
    # Delete instances first
    INSTANCES=$(aws rds describe-db-instances --region ${AWS_REGION} \
      --query "DBInstances[?DBClusterIdentifier=='${DB_CLUSTER}'].DBInstanceIdentifier" \
      --output text)
    
    for instance in $INSTANCES; do
        echo "  Deleting instance: $instance"
        aws rds delete-db-instance \
          --db-instance-identifier $instance \
          --skip-final-snapshot \
          --region ${AWS_REGION} 2>/dev/null || true
    done
    
    # Wait for instances to delete
    echo "  Waiting for instances to delete..."
    sleep 30
    
    # Delete cluster
    echo "  Deleting cluster..."
    aws rds delete-db-cluster \
      --db-cluster-identifier ${DB_CLUSTER} \
      --skip-final-snapshot \
      --region ${AWS_REGION} 2>/dev/null || true
    
    echo "Aurora cleanup initiated (will complete in background)"
else
    echo "Aurora cluster ${DB_CLUSTER} not found or already deleted"
fi
echo ""

echo -e "${GREEN}=== Phase 3: Deleting ECR Repositories ===${NC}"
echo "Deleting ECR repositories..."
for repo in apim-le-cache apim-le-configui apim-le-loader apim-le-loader-cron \
            apim-le-platformapi apim-le-trafficmanager apim-le-toolkit apim-jre-base cam-le-logsync; do
    echo "  Deleting: cam-le/${repo}"
    aws ecr delete-repository \
      --repository-name cam-le/${repo} \
      --force \
      --region ${AWS_REGION} 2>/dev/null || echo "    Repository not found or already deleted"
done
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "All resources have been deleted or cleanup initiated."
echo ""
echo "Note: Aurora database deletion may take 5-10 minutes to complete in the background."
echo "You can verify with:"
echo "  aws rds describe-db-clusters --region ${AWS_REGION}"
echo ""
