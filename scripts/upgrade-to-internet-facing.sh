#!/bin/bash
# Script to upgrade CAM LE deployment with internet-facing LoadBalancers
# This makes ConfigUI and Traffic Manager accessible from the internet

set -e

echo "========================================="
echo "Upgrading CAM LE to Internet-Facing LBs"
echo "========================================="
echo ""

# Load configuration
if [ ! -f "my-config.env" ]; then
    echo "Error: my-config.env not found in current directory"
    echo "Please copy my-config.env to install-aws-untethered folder"
    exit 1
fi

if [ ! -f "db-config.env" ]; then
    echo "Error: db-config.env not found"
    echo "Database must be created first (run phases 1-5)"
    exit 1  
fi

source my-config.env
source db-config.env

echo "Configuration loaded:"
echo "  Namespace: ${CAM_K8S_NAMESPACE:-camle}"
echo "  Cluster: ${CAM_CLUSTER_NAME}"
echo ""

# Upgrade Helm deployment with new values
echo "Upgrading Helm deployment..."
helm upgrade cam-le ../deploy/ \
  -f cam-le-untethered-values.yaml \
  --set preInstallDBPrep.initDBUserPassword=${DB_PASSWORD} \
  --set preInstallDBPrep.localDevAdminPassword=${ADMIN_PASSWORD} \
  -n ${CAM_K8S_NAMESPACE:-camle}

echo ""
echo "Waiting for LoadBalancers to update (2-3 minutes)..."
sleep 10

# Watch services update
kubectl get svc -n ${CAM_K8S_NAMESPACE:-camle}

echo ""  
echo "========================================="
echo "Upgrade Complete!"
echo "========================================="  
echo ""
echo "To check service status:"
echo "  kubectl get svc -n ${CAM_K8S_NAMESPACE:-camle}"
echo ""
echo "To get new URLs:"
echo '  CONFIGUI_URL=$(kubectl get svc configui-svc -n camle -o jsonpath='"'"'{.status.loadBalancer.ingress[0].hostname}'"'"')'
echo '  echo "ConfigUI: https://${CONFIGUI_URL}:443"'
echo ""
