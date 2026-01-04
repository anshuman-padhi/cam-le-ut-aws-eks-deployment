#!/bin/bash
# Complete Cleanup Script for CAM LE Deployment
# This removes ALL resources created during deployment

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}  CAM LE Complete Cleanup Script${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will delete ALL resources:${NC}"
echo "  - Helm deployment (cam-le)"
echo "  - All Kubernetes resources in namespace"
echo "  - EKS Cluster (entire cluster)"
echo "  - Aurora Database Cluster"
echo "  - ECR Repositories and images"
echo "  - All Kubernetes secrets"
echo ""
read -p "Are you sure you want to continue? Type 'YES' to confirm: " -r
echo ""

if [ "$REPLY" != "YES" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Load configuration
if [ -f "my-config.env" ]; then
    source my-config.env
elif [ -f "../my-config.env" ]; then
    source ../my-config.env
elif [ -f "custom-cam-le.env" ]; then
    source custom-cam-le.env
elif [ -f "../custom-cam-le.env" ]; then
    source ../custom-cam-le.env
fi

if [ -f "db-config.env" ]; then
    source db-config.env
elif [ -f "../db-config.env" ]; then
    source ../db-config.env
fi

if [ -f "ecr-config.env" ]; then
    source ecr-config.env
elif [ -f "../ecr-config.env" ]; then
    source ../ecr-config.env
fi

# Set defaults if not configured
CLUSTER_NAME=${CAM_CLUSTER_NAME:-cam-le-prod-cluster}
AWS_REGION=${CAM_AWS_REGION:-ap-southeast-2}
DB_CLUSTER=${CAM_DB_CLUSTER_NAME:-cam-le-aurora-prod}
K8S_NAMESPACE=${CAM_K8S_NAMESPACE:-camle}

echo -e "${GREEN}=== Phase 1: Removing Helm Deployment ===${NC}"
helm uninstall cam-le -n default 2>/dev/null || echo "No Helm release in default namespace"
helm uninstall cam-le -n ${K8S_NAMESPACE} 2>/dev/null || echo "No Helm release in ${K8S_NAMESPACE} namespace"
echo ""

echo -e "${GREEN}=== Phase 2: Deleting Kubernetes Resources ===${NC}"

# Delete all resources in namespace
if kubectl get namespace ${K8S_NAMESPACE} &>/dev/null; then
    echo "Deleting all resources in namespace: ${K8S_NAMESPACE}"
    kubectl delete all --all -n ${K8S_NAMESPACE} --grace-period=0 --force 2>/dev/null || true
    kubectl delete secrets --all -n ${K8S_NAMESPACE} 2>/dev/null || true
    kubectl delete configmaps --all -n ${K8S_NAMESPACE} 2>/dev/null || true
    kubectl delete pvc --all -n ${K8S_NAMESPACE} 2>/dev/null || true
    kubectl delete namespace ${K8S_NAMESPACE} 2>/dev/null || true
    echo "Namespace ${K8S_NAMESPACE} deleted"
fi

# Also clean default namespace if used
if [ "${K8S_NAMESPACE}" != "default" ]; then
    echo "Cleaning CAM LE resources from default namespace..."
    kubectl delete deployment,statefulset,service,secret,configmap \
      -l app.kubernetes.io/name=cam-le -n default 2>/dev/null || true
    kubectl delete pods -l app=cache-deploy -n default 2>/dev/null || true
    kubectl delete pods -l app=platformapi-deploy -n default 2>/dev/null || true
    kubectl delete pods -l app=trafficmanager-deploy -n default 2>/dev/null || true
    kubectl delete pods -l app=loader-deploy -n default 2>/dev/null || true
    kubectl delete pods -l app=configui-deploy -n default 2>/dev/null || true
fi

# Delete specific secrets
for secret in apim-db-secret db-ddl-cred configui-secrets configui-user-secrets \
              ecr-registry-secret trafficmanager-keystore-secret platformapi-keystore-secret \
              trafficmanager-truststore-secret oauth-authenticator-secret \
              configui-certificate-secret configui-key-secret api-debug-header-secret; do
    kubectl delete secret $secret -n default 2>/dev/null || true
    kubectl delete secret $secret -n ${K8S_NAMESPACE} 2>/dev/null || true
done

# Delete jobs
kubectl delete job --all -n default 2>/dev/null || true
kubectl delete job --all -n ${K8S_NAMESPACE} 2>/dev/null || true

echo ""

echo -e "${GREEN}=== Phase 3: Deleting EKS Cluster ===${NC}"
if eksctl get cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo "Deleting EKS cluster: ${CLUSTER_NAME}"
    echo "This will take 10-15 minutes..."
    eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --wait
    echo "EKS cluster deleted"
else
    echo "EKS cluster ${CLUSTER_NAME} not found or already deleted"
fi
echo ""

echo -e "${GREEN}=== Phase 4: Deleting Aurora Database ===${NC}"
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

echo -e "${GREEN}=== Phase 5: Deleting ECR Repositories ===${NC}"
if [ -n "${ECR_REGISTRY}" ]; then
    # Extract account and region from ECR_REGISTRY if available
    ACCOUNT_ID=$(echo ${ECR_REGISTRY} | cut -d'.' -f1)
    
    echo "Deleting ECR repositories..."
    for repo in apim-le-cache apim-le-configui apim-le-loader apim-le-loader-cron \
                apim-le-platformapi apim-le-trafficmanager apim-le-toolkit cam-le-logsync; do
        echo "  Deleting: cam-le/${repo}"
        aws ecr delete-repository \
          --repository-name cam-le/${repo} \
          --force \
          --region ${AWS_REGION} 2>/dev/null || echo "    Repository not found or already deleted"
    done
else
    echo "ECR registry not configured, skipping"
fi
echo ""

echo -e "${GREEN}=== Phase 6: Cleaning Up Local Files ===${NC}"
echo "Removing generated configuration files..."
rm -f db-config.env ecr-config.env custom-cam-le.env customvalues.env
rm -f cam-le-untethered-values.yaml.*.bak
rm -f db-init-job.yaml eks-cluster-config.yaml
rm -rf keystores/
echo "Local files cleaned"
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
echo -e "${YELLOW}To start fresh deployment:${NC}"
echo "  1. Review and update my-config.env with your configuration"  
echo "  2. Run: source my-config.env"
echo "  3. Run: ./deploy-cam-le-untethered-complete.sh --interactive"
echo ""
