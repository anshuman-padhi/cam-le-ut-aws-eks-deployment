#!/bin/bash

# AWS Load Balancer Controller Installation Script

set -e  # Exit on any error

# Set environment variables - use environment or defaults
export AWS_REGION=${CAM_AWS_REGION:-${AWS_REGION:-ap-southeast-2}}
export CLUSTER_NAME=${CAM_CLUSTER_NAME:-${CLUSTER_NAME:-cam-le-cluster}}
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export LBC_VERSION=v2.7.0

echo "========================================="
echo "AWS Load Balancer Controller Installation"
echo "========================================="
echo "Cluster: ${CLUSTER_NAME}"
echo "Region: ${AWS_REGION}"
echo "Account: ${AWS_ACCOUNT_ID}"
echo "LBC Version: ${LBC_VERSION}"
echo ""

# Step 1: Download IAM policy
echo "Step 1: Downloading IAM policy for AWS Load Balancer Controller..."
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json

echo "✅ IAM policy downloaded"

# Step 2: Create IAM policy
echo ""
echo "Step 2: Creating IAM policy..."
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"

# Check if policy already exists
if aws iam get-policy --policy-arn ${POLICY_ARN} 2>/dev/null; then
    echo "Policy already exists: ${POLICY_ARN}"
else
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam_policy.json
    echo "✅ IAM policy created: ${POLICY_ARN}"
fi

# Step 3: Create IAM service account
echo ""
echo "Step 3: Creating IAM service account for AWS Load Balancer Controller..."

eksctl create iamserviceaccount \
  --cluster=${CLUSTER_NAME} \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=${POLICY_ARN} \
  --override-existing-serviceaccounts \
  --approve \
  --region=${AWS_REGION}

echo "✅ IAM service account created"

# Step 4: Add EKS Helm repository
echo ""
echo "Step 4: Adding EKS Helm repository..."
helm repo add eks https://aws.github.io/eks-charts
helm repo update

echo "✅ Helm repository added"

# Step 5: Install AWS Load Balancer Controller
echo ""
echo "Step 5: Installing AWS Load Balancer Controller..."

# Check if already installed
if helm list -n kube-system | grep -q aws-load-balancer-controller; then
    echo "AWS Load Balancer Controller already installed. Upgrading..."
    helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      --set clusterName=${CLUSTER_NAME} \
      --set serviceAccount.create=false \
      --set serviceAccount.name=aws-load-balancer-controller \
      --set region=${AWS_REGION} \
      --set vpcId=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.vpcId" --output text)
else
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
      -n kube-system \
      --set clusterName=${CLUSTER_NAME} \
      --set serviceAccount.create=false \
      --set serviceAccount.name=aws-load-balancer-controller \
      --set region=${AWS_REGION} \
      --set vpcId=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.vpcId" --output text)
fi

echo "✅ AWS Load Balancer Controller installed"

# Step 6: Wait for deployment to be ready
echo ""
echo "Step 6: Waiting for AWS Load Balancer Controller to be ready..."
kubectl wait --for=condition=available --timeout=300s \
  deployment/aws-load-balancer-controller -n kube-system

echo "✅ AWS Load Balancer Controller is ready"

# Step 7: Verify installation
echo ""
echo "Step 7: Verifying installation..."
echo ""

echo "Deployment status:"
kubectl get deployment -n kube-system aws-load-balancer-controller

echo ""
echo "Pods:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

echo ""
echo "Service Account:"
kubectl get serviceaccount -n kube-system aws-load-balancer-controller

echo ""
echo "Logs (last 20 lines):"
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=20

# Clean up
rm -f iam_policy.json

echo ""
echo "========================================="
echo "AWS Load Balancer Controller Installation Complete!"
echo "========================================="
echo "The controller is now ready to provision Network Load Balancers"
echo "for your Kubernetes LoadBalancer services"
echo ""
echo "Next steps:"
echo "1. Continue with Aurora MySQL setup"
echo "2. Deploy CAM LE"
echo "========================================="
