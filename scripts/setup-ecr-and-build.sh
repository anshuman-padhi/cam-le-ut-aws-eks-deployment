#!/bin/bash

# ECR Repository Setup and Image Build Script for CAM LE

set -e  # Exit on any error

# Set environment variables - use environment or defaults
export AWS_REGION=${CAM_AWS_REGION:-${AWS_REGION:-ap-southeast-2}}
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export ECR_REGISTRY=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
export IMAGE_TAG=${CAM_IMAGE_TAG:-${IMAGE_TAG:-v6.2.0}}
export BUILDER=${CAM_BUILDER:-${BUILDER:-docker}}
export CLUSTER_MODE=${CAM_CLUSTER_MODE:-${CLUSTER_MODE:-untethered}}

# Validate critical variables
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "Error: Failed to get AWS Account ID. Please check AWS credentials."
    exit 1
fi

if [ -z "$ECR_REGISTRY" ]; then
    echo "Error: ECR_REGISTRY is not set"
    exit 1
fi

echo "Validated environment variables:"
echo "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
echo "  ECR_REGISTRY: ${ECR_REGISTRY}"
echo "  BUILDER: ${BUILDER}"
echo "  CLUSTER_MODE: ${CLUSTER_MODE}"

# CAM LE image names
IMAGES=(
  "apim-le-toolkit"
  "apim-jre-base"
  "apim-le-cache"
  "apim-le-loader-cron"
  "apim-le-loader"
  "apim-le-trafficmanager"
  "apim-le-platformapi"
  "apim-le-configui"
  "cam-le-logsync"
)

echo "========================================="
echo "ECR Setup and Image Build for CAM LE"
echo "========================================="
echo "AWS Region: ${AWS_REGION}"
echo "AWS Account: ${AWS_ACCOUNT_ID}"
echo "ECR Registry: ${ECR_REGISTRY}"
echo "Image Tag: ${IMAGE_TAG}"
echo ""

# Step 1: Create ECR repositories
echo "Step 1: Creating ECR repositories..."
for IMAGE in "${IMAGES[@]}"; do
  echo "  Creating repository: cam-le/${IMAGE}"
  aws ecr create-repository \
    --repository-name cam-le/${IMAGE} \
    --region ${AWS_REGION} \
    --image-scanning-configuration scanOnPush=true \
    --tags Key=Application,Value=CAM-LE 2>/dev/null || echo "  Repository ${IMAGE} already exists"
done

echo ""
echo "✅ ECR repositories created successfully"

# Step 2: Authenticate to ECR
echo ""
echo "Step 2: Authenticating to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | \
  ${BUILDER} login --username AWS --password-stdin ${ECR_REGISTRY}

echo "✅ Authenticated to ECR"

# Step 3: Build images
echo ""
echo "Step 3: Building container images..."
echo "This will take approximately 30-60 minutes..."
echo ""

# Check if build script exists
if [ ! -f "build-images.sh" ]; then
    echo "Error: build-images.sh not found in current directory"
    echo "Please run this script from the CAM LE root directory"
    exit 1
fi

# Determine cluster mode (default to untethered)
CLUSTER_MODE=${CLUSTER_MODE:-untethered}
echo "Building for cluster mode: ${CLUSTER_MODE}"

# Display build parameters
echo ""
echo "Build parameters:"
echo "  Builder: ${BUILDER}"
echo "  Registry: ${ECR_REGISTRY}/cam-le"
echo "  Architecture: linux/amd64"
echo "  Image Tag: ${IMAGE_TAG}"
echo "  Cluster Mode: ${CLUSTER_MODE}"
echo ""

# Validate all parameters are set
if [ -z "$BUILDER" ] || [ -z "$ECR_REGISTRY" ] || [ -z "$IMAGE_TAG" ] || [ -z "$CLUSTER_MODE" ]; then
    echo "Error: One or more required parameters are not set"
    echo "BUILDER=$BUILDER"
    echo "ECR_REGISTRY=$ECR_REGISTRY"
    echo "IMAGE_TAG=$IMAGE_TAG"
    echo "CLUSTER_MODE=$CLUSTER_MODE"
    exit 1
fi

# Build images for specified mode
# Note: For untethered mode, cam-le-logsync is not built (filtered by build script)
./build-images.sh \
  -c "${BUILDER}" \
  -p "${ECR_REGISTRY}/cam-le" \
  -a "linux/amd64" \
  -s "${IMAGE_TAG}" \
  -m "${CLUSTER_MODE}"

echo ""
echo "✅ Images built successfully"

# Step 4: Push images to ECR
echo ""
echo "Step 4: Pushing images to ECR..."

for IMAGE in "${IMAGES[@]}"; do
  # Skip cam-le-logsync for untethered mode (not built)
  if [ "${CLUSTER_MODE}" = "untethered" ] && [ "${IMAGE}" = "cam-le-logsync" ]; then
    echo "  Skipping ${IMAGE} (not used in untethered mode)"
    continue
  fi
  
  echo "  Pushing ${IMAGE}:${IMAGE_TAG}..."
  ${BUILDER} push ${ECR_REGISTRY}/cam-le/${IMAGE}:${IMAGE_TAG}
done

echo ""
echo "✅ All images pushed to ECR"

# Step 5: Verify images in ECR
echo ""
echo "Step 5: Verifying images in ECR..."
echo ""

for IMAGE in "${IMAGES[@]}"; do
  echo "Repository: cam-le/${IMAGE}"
  aws ecr describe-images \
    --repository-name cam-le/${IMAGE} \
    --region ${AWS_REGION} \
    --query 'imageDetails[*].[imageTags[0],imageSizeInBytes,imagePushedAt]' \
    --output table
  echo ""
done

# Save ECR configuration
cat > ecr-config.env <<EOF
# ECR Configuration
# Generated on $(date)
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export ECR_REGISTRY=${ECR_REGISTRY}
export IMAGE_TAG=${IMAGE_TAG}
EOF

echo "========================================="
echo "ECR Setup Complete!"
echo "========================================="
echo "ECR Registry: ${ECR_REGISTRY}"
echo "Image Tag: ${IMAGE_TAG}"
echo "Total Images: ${#IMAGES[@]}"
echo ""
echo "Configuration saved to: ecr-config.env"
echo ""
echo "To use these values, run:"
echo "  source ecr-config.env"
echo "========================================="
