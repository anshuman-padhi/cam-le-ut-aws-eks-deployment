#!/bin/bash
# Complete Deployment Script for CAM LE 6.2 - Untethered Mode on AWS EKS
# This script automates the entire deployment process with all required steps

# ===========================================
# CONFIGURABLE PARAMETERS
# ===========================================
# All parameters can be configured via environment variables before running this script.
# See cam-le-config-template.env for a complete configuration template.
#
# Quick Configuration:
# -------------------
# export CAM_AWS_REGION=us-east-1                    # AWS region
# export CAM_CLUSTER_NAME=cam-le-cluster             # EKS cluster name
# export CAM_K8S_NAMESPACE=default                   # Kubernetes namespace
# export CAM_EKS_NODE_TYPE=m5.large                  # EKS node instance type
# export CAM_EKS_NODE_MIN=3                          # Minimum nodes
# export CAM_EKS_NODE_MAX=4                          # Maximum nodes
# export CAM_EKS_NODE_DESIRED=3                      # Desired nodes
# export CAM_DB_CLUSTER_NAME=cam-le-aurora-cluster   # Aurora cluster name
# export CAM_DB_INSTANCE_NAME=cam-le-aurora-instance # Aurora instance name
# export CAM_DB_INSTANCE_CLASS=db.r6g.large          # Aurora instance class
# export CAM_DB_NAME=masherysolar                    # Database name
# export CAM_DB_USERNAME=admin                       # Database admin user
# export CAM_DML_USERNAME=masheryonprem              # Database DML user
# export CAM_ADMIN_USERNAME=admin                    # CAM LE admin username
# export CAM_DB_PASSWORD='YourDBPassword'            # Database admin password
# export CAM_DML_PASSWORD='YourDMLPassword'          # Database DML password  
# export CAM_ADMIN_PASSWORD='YourAdminPassword'      # CAM LE admin password
#
# Usage Examples:
# ---------------
# 1. Use defaults (will prompt for passwords):
#    ./deploy-cam-le-untethered-complete.sh
#
# 2. Custom cluster name and region:
#    export CAM_CLUSTER_NAME=my-cluster
#    export CAM_AWS_REGION=ap-southeast-2
#    export CAM_DB_PASSWORD='SecurePass123!'
#    export CAM_DML_PASSWORD='SecurePass123!'
#    export CAM_ADMIN_PASSWORD='SecurePass123!'
#    ./deploy-cam-le-untethered-complete.sh
#
# 3. Using a configuration file (Recommended):
#    source my-config.env
#    ./deploy-cam-le-untethered-complete.sh
#
# ===========================================

set -e  # Exit on any error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
    echo ""
}

# Backup existing file with timestamp
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_name="${file}.${timestamp}.bak"
        log_info "Backing up existing file: $file → $backup_name"
        mv "$file" "$backup_name"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"
    
    local missing=0
    
    command -v aws >/dev/null 2>&1 || { log_error "AWS CLI not found"; missing=1; }
    command -v kubectl >/dev/null 2>&1 || { log_error "kubectl not found"; missing=1; }
    command -v eksctl >/dev/null 2>&1 || { log_error "eksctl not found"; missing=1; }
    command -v helm >/dev/null 2>&1 || { log_error "Helm not found"; missing=1; }
    command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1 || { log_error "Docker or Podman not found"; missing=1; }
    command -v openssl >/dev/null 2>&1 || { log_error "OpenSSL not found"; missing=1; }
    
    if [ $missing -eq 1 ]; then
        log_error "Missing required tools. Please install them and try again."
        exit 1
    fi
    
    log_info "✅ All prerequisites met"
    log_info "ℹ️  Database initialization will use Kubernetes Job (no local MySQL client needed)"
}

# Set environment variables
setup_environment() {
    log_section "Setting Up Environment"
    
    # AWS Configuration (configurable via environment variables)
    export AWS_REGION=${CAM_AWS_REGION:-us-east-1}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # EKS Cluster Configuration
    export CLUSTER_NAME=${CAM_CLUSTER_NAME:-cam-le-cluster}
    export K8S_NAMESPACE=${CAM_K8S_NAMESPACE:-default}
    export EKS_VERSION=${CAM_EKS_VERSION:-1.31}
    export EKS_NODE_TYPE=${CAM_EKS_NODE_TYPE:-m5.large}
    export EKS_NODE_MIN=${CAM_EKS_NODE_MIN:-3}
    export EKS_NODE_MAX=${CAM_EKS_NODE_MAX:-4}
    export EKS_NODE_DESIRED=${CAM_EKS_NODE_DESIRED:-3}
    
    # Aurora Database Configuration
    export DB_CLUSTER_IDENTIFIER=${CAM_DB_CLUSTER_NAME:-cam-le-aurora-cluster}
    export DB_INSTANCE_IDENTIFIER=${CAM_DB_INSTANCE_NAME:-cam-le-aurora-instance}
    export DB_INSTANCE_CLASS=${CAM_DB_INSTANCE_CLASS:-db.r6g.large}
    export DB_NAME=${CAM_DB_NAME:-masherysolar}
    export DB_USERNAME=${CAM_DB_USERNAME:-admin}
    export DML_USERNAME=${CAM_DML_USERNAME:-masheryonprem}
    
    # CAM LE Admin Configuration
    export ADMIN_USERNAME=${CAM_ADMIN_USERNAME:-admin}
    
    # Prompt for passwords if not set via environment variables
    if [ -z "$CAM_DB_PASSWORD" ]; then
        read -sp "Enter Database Admin Password: " CAM_DB_PASSWORD
        echo ""
        export DB_PASSWORD=$CAM_DB_PASSWORD
    else
        export DB_PASSWORD=$CAM_DB_PASSWORD
    fi
    
    if [ -z "$CAM_DML_PASSWORD" ]; then
        read -sp "Enter Database DML User Password: " CAM_DML_PASSWORD
        echo ""
        export DML_PASSWORD=$CAM_DML_PASSWORD
    else
        export DML_PASSWORD=$CAM_DML_PASSWORD
    fi
    
    if [ -z "$CAM_ADMIN_PASSWORD" ]; then
        read -sp "Enter CAM LE Admin Password: " CAM_ADMIN_PASSWORD
        echo ""
        export ADMIN_PASSWORD=$CAM_ADMIN_PASSWORD
    else
        export ADMIN_PASSWORD=$CAM_ADMIN_PASSWORD
    fi
    
    log_info "========================================="
    log_info "Deployment Configuration:"
    log_info "========================================="
    log_info "AWS Region:           $AWS_REGION"
    log_info "AWS Account ID:       $AWS_ACCOUNT_ID"
    log_info "EKS Cluster Name:     $CLUSTER_NAME"
    log_info "EKS Version:          $EKS_VERSION"
    log_info "Kubernetes Namespace: $K8S_NAMESPACE"
    log_info "EKS Node Type:        $EKS_NODE_TYPE"
    log_info "EKS Node Count:       $EKS_NODE_DESIRED (min: $EKS_NODE_MIN, max: $EKS_NODE_MAX)"
    log_info "Aurora Cluster:       $DB_CLUSTER_IDENTIFIER"
    log_info "Aurora Instance:      $DB_INSTANCE_IDENTIFIER"
    log_info "Aurora Instance Class: $DB_INSTANCE_CLASS"
    log_info "Database Name:        $DB_NAME"
    log_info "Database Admin User:  $DB_USERNAME"
    log_info "Database DML User:    $DML_USERNAME"
    log_info "CAM LE Admin User:    $ADMIN_USERNAME"
    log_info "========================================="
    echo ""
    
    # Confirm before proceeding
    read -p "Proceed with these settings? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Deployment cancelled by user"
        exit 0
    fi
}

# Generate custom values for untethered mode
generate_custom_values() {
    log_section "Phase 1: Generating Custom Values for Untethered Mode"
    
    if [ ! -f "../scripts/customize.sh" ]; then
        log_error "../scripts/customize.sh not found!"
        exit 1
    fi
    
    log_info "Running customize.sh to generate Area UUID, Package Key, and Secret..."
    
    # Backup existing custom values file
    backup_file "custom-values.txt"
    
    # Generate custom values
    ../scripts/customize.sh -u -k -s -b > custom-values.txt
    
    # Parse values
    export AREA_UUID=$(sed -n '1p' custom-values.txt | tr -d '\n' | xargs)
    export PACKAGE_KEY=$(sed -n '2p' custom-values.txt | tr -d '\n' | xargs)
    export PACKAGE_SECRET=$(sed -n '3p' custom-values.txt | tr -d '\n' | xargs)
    
    # Validate
    if [ -z "$AREA_UUID" ] || [ -z "$PACKAGE_KEY" ] || [ -z "$PACKAGE_SECRET" ]; then
        log_error "Failed to generate custom values!"
        log_error "AREA_UUID: $AREA_UUID"
        log_error "PACKAGE_KEY: $PACKAGE_KEY"
        log_error "PACKAGE_SECRET: $PACKAGE_SECRET"
        exit 1
    fi
    
    log_info "✅ Generated custom values:"
    log_info "  Area UUID: ${AREA_UUID}"
    log_info "  Package Key: ${PACKAGE_KEY:0:20}..."
    log_info "  Package Secret: ${PACKAGE_SECRET:0:20}..."
    
    # Backup and save to file
    backup_file "custom-cam-le.env"
    cat > custom-cam-le.env <<EOF
# CAM LE Custom Values for Untethered Mode
# Generated on $(date)
export AREA_UUID="${AREA_UUID}"
export PACKAGE_KEY="${PACKAGE_KEY}"
export PACKAGE_SECRET="${PACKAGE_SECRET}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD}"
export DML_PASSWORD="${DML_PASSWORD}"
export DB_PASSWORD="${DB_PASSWORD}"
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export CLUSTER_NAME="${CLUSTER_NAME}"
EOF
    
    log_info "✅ Custom values saved to custom-cam-le.env"
}

# Create EKS cluster
create_eks_cluster() {
    log_section "Phase 2: Creating EKS Cluster"
    
    # Check if cluster exists
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION &>/dev/null; then
        log_warn "Cluster $CLUSTER_NAME already exists. Skipping creation."
        return
    fi
    
    log_info "Creating EKS cluster configuration..."
    
    backup_file "eks-cluster-config.yaml"
    cat > eks-cluster-config.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${EKS_VERSION}"
vpc:
  cidr: 10.0.0.0/16
  nat:
    gateway: HighlyAvailable
managedNodeGroups:
  - name: cam-le-nodegroup
    instanceType: ${EKS_NODE_TYPE}
    desiredCapacity: ${EKS_NODE_DESIRED}
    minSize: ${EKS_NODE_MIN}
    maxSize: ${EKS_NODE_MAX}
    volumeSize: 80
    privateNetworking: true
    labels:
      workload: cam-le
    tags:
      Environment: production
      Application: cam-le
iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: apiml-sa
        namespace: ${K8S_NAMESPACE}
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
        - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
cloudWatch:
  clusterLogging:
    enableTypes: ["api", "audit", "authenticator", "controllerManager", "scheduler"]
EOF
    
    log_info "Creating EKS cluster (this will take 15-20 minutes)..."
    eksctl create cluster -f eks-cluster-config.yaml
    
    log_info "✅ EKS cluster created"
    
    # Update kubeconfig
    aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
    
    # Install AWS Load Balancer Controller
    log_info "Installing AWS Load Balancer Controller..."
    ./install-aws-lb-controller.sh
    
    log_info "✅ AWS Load Balancer Controller installed"
}

# Create Aurora database
create_database() {
    log_section "Phase 5: Creating Aurora MySQL Database"
    
    if [ -f "db-config.env" ]; then
        log_warn "Database configuration exists. Skipping database creation."
        source db-config.env
        return
    fi
    
    log_info "Creating Aurora MySQL database..."
    log_info "Cluster: ${DB_CLUSTER_IDENTIFIER}"
    log_info "Instance: ${DB_INSTANCE_IDENTIFIER}"
    log_info "Instance class: ${DB_INSTANCE_CLASS}"
    
    # Export all required environment variables for aurora-mysql.sh
    export CAM_AWS_REGION=$AWS_REGION
    export CAM_DB_CLUSTER_NAME=$DB_CLUSTER_IDENTIFIER
    export CAM_DB_INSTANCE_NAME=$DB_INSTANCE_IDENTIFIER
    export CAM_DB_INSTANCE_CLASS=$DB_INSTANCE_CLASS
    export CAM_DB_USERNAME=$DB_USERNAME
    export CAM_DB_PASSWORD=$DB_PASSWORD
    export CAM_DB_NAME=$DB_NAME
    export CAM_CLUSTER_NAME=$CLUSTER_NAME
    
    # Run aurora-mysql.sh (now natively supports environment variables)
    ./aurora-mysql.sh
    
    source db-config.env
    
    log_info "✅ Aurora database created: $DB_ENDPOINT"
}

# Initialize database
initialize_database() {
    log_section "Phase 6: Initializing Database Schema"
    
    source db-config.env
    
    # Source custom-cam-le.env if it exists (contains DML_PASSWORD)
    if [ -f "custom-cam-le.env" ]; then
        source custom-cam-le.env
    fi
    
    # Fallback: use environment variable or default
    DML_PASSWORD=${DML_PASSWORD:-${CAM_DML_PASSWORD:-SecureDmlPassword123!}}
    
    log_info "Creating Kubernetes Job to initialize Aurora database with full schema..."
    log_info "Database endpoint: ${DB_ENDPOINT}"
    log_info "DML User: masheryonprem"
    log_info "Schema files: 4 SQL files from scripts/db/"
    
    # Create ConfigMap with all SQL schema files
    log_info "Creating ConfigMap with schema SQL files..."
    kubectl create configmap db-schema-sql \
      --from-file=../scripts/db/apim-le-db-schema_6.2.0.sql \
      --from-file=../scripts/db/apim-le-db-counter-purger-schema_6.2.0.sql \
      --from-file=../scripts/db/apim-le-db-token-purger-schema_6.2.0.sql \
      --from-file=../scripts/db/apim-le-db-audit-purger-schema_6.2.0.sql \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Create a Kubernetes Job to run MySQL client inside the cluster
    backup_file "db-init-job.yaml"
    cat > db-init-job.yaml <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: aurora-db-init
  namespace: ${K8S_NAMESPACE}
spec:
  ttlSecondsAfterFinished: 300
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: mysql-client
        image: mysql:8.0
        env:
        - name: DB_ENDPOINT
          value: "${DB_ENDPOINT}"
        - name: DB_USERNAME
          value: "${DB_USERNAME}"
        - name: DB_PASSWORD
          value: "${DB_PASSWORD}"
        - name: DML_PASSWORD
          value: "${DML_PASSWORD}"
        - name: AREA_UUID
          value: "${AREA_UUID}"
        volumeMounts:
        - name: sql-files
          mountPath: /sql
        command:
        - /bin/bash
        - -c
        - |
          set -e
          
          echo "===================================="
          echo "Aurora Database Schema Initialization"
          echo "===================================="
          echo "Endpoint: \${DB_ENDPOINT}"
          echo "Username: \${DB_USERNAME}"
          echo ""
          
          echo "Waiting for Aurora to be reachable..."
          max_attempts=60
          attempt=0
          
          until mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} -e "SELECT 1" > /dev/null 2>&1; do
            attempt=\$((attempt + 1))
            if [ \$attempt -ge \$max_attempts ]; then
              echo "ERROR: Database not reachable after \$max_attempts attempts"
              exit 1
            fi
            echo "Attempt \$attempt/\$max_attempts: Database not ready yet, waiting 10 seconds..."
            sleep 10
          done
          
          echo ""
          echo "✓ Database is reachable!"
          echo ""
          
          # Create database and users
          echo "Creating database and users..."
          mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} -e "
          CREATE DATABASE IF NOT EXISTS masherysolar CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
          GRANT ALL PRIVILEGES ON masherysolar.* TO '\${DB_USERNAME}'@'%';
          FLUSH PRIVILEGES;
          "
          
          mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} -e "
          CREATE USER IF NOT EXISTS 'masheryonprem'@'%' IDENTIFIED BY '\${DML_PASSWORD}';
          GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON masherysolar.* TO 'masheryonprem'@'%';
          FLUSH PRIVILEGES;
          "
          
          echo "✓ Database and users created"
          echo ""
          
          # Run schema SQL files in order
          echo "Running schema SQL files..."
          echo ""
          
          echo "[1/4] Running main schema (apim-le-db-schema_6.2.0.sql)..."
          mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} masherysolar < /sql/apim-le-db-schema_6.2.0.sql
          echo "✓ Main schema loaded"
          echo ""
          
          echo "[2/4] Running counter purger schema (apim-le-db-counter-purger-schema_6.2.0.sql)..."
          mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} masherysolar < /sql/apim-le-db-counter-purger-schema_6.2.0.sql
          echo "✓ Counter purger schema loaded"
          echo ""
          
          echo "[3/4] Running token purger schema (apim-le-db-token-purger-schema_6.2.0.sql)..."
          mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} masherysolar < /sql/apim-le-db-token-purger-schema_6.2.0.sql
          echo "✓ Token purger schema loaded"
          echo ""
          
          echo "[4/4] Running audit purger schema (apim-le-db-audit-purger-schema_6.2.0.sql)..."
          mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} masherysolar < /sql/apim-le-db-audit-purger-schema_6.2.0.sql
          echo "✓ Audit purger schema loaded"
          echo ""
          
          # Seed Area 33
          echo "Seeding Area 33 data..."
          mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} masherysolar -e "
          INSERT INTO areas (id, uuid, name, created, updated, status) 
          VALUES (33, '\${AREA_UUID}', 'CAM LE Local Area', NOW(), NOW(), 'active')
          ON DUPLICATE KEY UPDATE 
            uuid = '\${AREA_UUID}',
            updated = NOW(),
            name = 'CAM LE Local Area';
          "
          echo "✓ Area 33 seeded"
          echo ""
          
          # Verify schema
          TABLE_COUNT=\$(mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} -D masherysolar -sNe "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'masherysolar';")
          echo "Schema verification:"
          echo "  Tables created: \$TABLE_COUNT"
          
          if [ "\$TABLE_COUNT" -gt "10" ]; then
            echo ""
            echo "Sample tables:"
            mysql -h \${DB_ENDPOINT} -u \${DB_USERNAME} -p\${DB_PASSWORD} -D masherysolar -e "SHOW TABLES LIMIT 10;"
          fi
          
          echo ""
          echo "===================================="
          echo "✅ Database Schema Initialization Complete"
          echo "===================================="
          echo "Database: masherysolar"
          echo "Admin User: \${DB_USERNAME}"
          echo "DML User: masheryonprem"
          echo "Tables: \$TABLE_COUNT"
          echo "===================================="
      volumes:
      - name: sql-files
        configMap:
          name: db-schema-sql
EOF
    
    log_info "Applying database initialization Job to Kubernetes..."
    
    # Delete existing job if it exists
    kubectl delete job aurora-db-init -n ${K8S_NAMESPACE} --ignore-not-found=true
    
    # Apply the job
    kubectl apply -f db-init-job.yaml
    
    log_info "Waiting for database schema initialization Job to complete..."
    log_info "(This may take 5-10 minutes to load all schema files)"
    
    # Wait for job to complete (timeout after 15 minutes)
    if kubectl wait --for=condition=complete --timeout=900s job/aurora-db-init -n ${K8S_NAMESPACE}; then
        log_info ""
        log_info "Job completed! Showing logs:"
        log_info "===================================="
        kubectl logs job/aurora-db-init -n ${K8S_NAMESPACE}
        log_info "===================================="
        log_info ""
        log_info "✅ Database schema initialized successfully via Kubernetes Job"
    else
        log_error "Database initialization Job failed or timed out"
        log_error ""
        log_error "Check Job status:"
        kubectl get job aurora-db-init -n ${K8S_NAMESPACE}
        log_error ""
        log_error "Check Pod logs:"
        kubectl logs job/aurora-db-init -n ${K8S_NAMESPACE}
        log_error ""
        log_error "To retry, re-run:"
        log_error "  ./deploy-cam-le-untethered-complete.sh --start-from 6"
        exit 1
    fi
    
    # Clean up the job after success
    log_info "Cleaning up initialization Job..."
    kubectl delete job aurora-db-init -n ${K8S_NAMESPACE} --ignore-not-found=true
    kubectl delete configmap db-schema-sql -n ${K8S_NAMESPACE} --ignore-not-found=true
    
    log_info "✅ Database schema initialization complete"
}

# Create Kubernetes Namespace
create_namespace() {
    log_section "Phase 6b: Creating Kubernetes Namespace"
    
    log_info "Ensuring namespace '$K8S_NAMESPACE' exists..."
    
    # Check if namespace already exists
    if kubectl get namespace "$K8S_NAMESPACE" &>/dev/null; then
        log_info "Namespace '$K8S_NAMESPACE' already exists ✓"
    else
        log_info "Creating namespace '$K8S_NAMESPACE'..."
        kubectl create namespace "$K8S_NAMESPACE"
        log_info "✅ Namespace '$K8S_NAMESPACE' created"
    fi
    
    # Set as default namespace for current context (optional, helps with kubectl commands)
    kubectl config set-context --current --namespace="$K8S_NAMESPACE"
    log_info "✅ Set '$K8S_NAMESPACE' as default namespace for current context"
}

# Source configuration
setup_environment() {
    log_section "Phase 2: Setting Up Environment"
    
    # Load main configuration
    if [ ! -f "my-config.env" ]; then
        log_error "my-config.env not found in current directory!"
        log_error "Please copy my-config.env to install-aws-untethered folder"
        exit 1
    fi
    
    source my-config.env
}

# Build and push images
build_and_push_images() {
    log_section "Phase 5: Building and Pushing Docker Images"
    
    if [ -f "ecr-config.env" ]; then
        log_warn "ECR configuration exists. Skipping image build."
        source ecr-config.env
        return
    fi
    
    log_info "Building and pushing Docker images (this will take 30-60 minutes)..."
    ./setup-ecr-and-build.sh
    
    source ecr-config.env
    
    log_info "✅ Images built and pushed to ECR"
}

# Create Kubernetes secrets
create_secrets() {
    log_section "Phase 7: Creating Kubernetes Secrets"
    
    source db-config.env
    source ecr-config.env
    
    # Source custom-cam-le.env for DML_PASSWORD and other values
    if [ -f "custom-cam-le.env" ]; then
        source custom-cam-le.env
    fi
    
    # Ensure DML_PASSWORD is set (critical for database access)
    if [ -z "$DML_PASSWORD" ]; then
        DML_PASSWORD=${CAM_DML_PASSWORD:-}
    fi
    if [ -z "$DML_PASSWORD" ]; then
        log_error "DML_PASSWORD is not set! This is required for application database access."
        log_error "Please set CAM_DML_PASSWORD environment variable or source custom-cam-le.env"
        exit 1
    fi
    
    log_info "Creating database secrets..."
    log_info "DML User: masheryonprem"
    log_info "DML Password: ${DML_PASSWORD:0:4}**** (first 4 chars shown)"
    
    # DDL user secret (admin credentials for schema management)
    kubectl create secret generic db-ddl-cred \
      --from-literal=username=${DB_USERNAME} \
      --from-literal=password=${DB_PASSWORD} \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # DML user secret (application credentials for runtime access)
    # Note: Keys use dot prefix (.apimdbuser, .apimdbpasswd) as required by Boomi CAM LE
    kubectl create secret generic apim-db-secret \
      --from-literal=.apimdbuser=masheryonprem \
      --from-literal=.apimdbpasswd=${DML_PASSWORD} \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "✅ Database DML user credential secret created"
    
    log_info "Creating package secrets (ConfigUI-Platform API auth)..."
    
    # Package key and secret
    kubectl create secret generic configui-secrets \
      --from-literal=.mlc_apikey=${PACKAGE_KEY} \
      --from-literal=.mlc_apisecret=${PACKAGE_SECRET} \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Creating admin password secret..."
    
    # Admin password
    kubectl create secret generic configui-user-secrets \
      --from-literal=.mlc_password=${ADMIN_PASSWORD} \
      --from-literal=.mlc_server_secret=$(openssl rand -base64 32) \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Creating ECR pull secret..."
    
    # ECR pull secret
    kubectl create secret docker-registry ecr-registry-secret \
      --docker-server=${ECR_REGISTRY} \
      --docker-username=AWS \
      --docker-password=$(aws ecr get-login-password --region ${AWS_REGION}) \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Generate self-signed certificate for TLS
    log_info "Generating self-signed SSL certificates..."
    mkdir -p ../keystores
    
    # Generate certificates
    openssl req -x509 -newkey rsa:4096 -keyout ../keystores/key.pem \
      -out ../keystores/cert.pem -days 365 -nodes \
      -subj "/CN=*.elb.amazonaws.com" 2>/dev/null
    
    openssl pkcs12 -export -in ../keystores/cert.pem -inkey ../keystores/key.pem \
      -out ../keystores/trafficmanager-keystore.p12 -name trafficmanager \
      -passout pass:changeit
    
    openssl pkcs12 -export -in ../keystores/cert.pem -inkey ../keystores/key.pem \
      -out ../keystores/platformapi-keystore.p12 -name platformapi \
      -passout pass:changeit
    
    kubectl create secret generic trafficmanager-keystore-secret \
      --from-file=trafficmanager.jks=../keystores/trafficmanager-keystore.p12 \
      --from-literal=.ssl.password=changeit \
      --from-literal=.ssl.keypassword=changeit \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create secret generic platformapi-keystore-secret \
      --from-file=tml-cm.jks=../keystores/platformapi-keystore.p12 \
      --from-literal=.ssl.password=changeit \
      --from-literal=.ssl.keypassword=changeit \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Creating OAuth secrets..."
    
    kubectl create secret generic oauth-authenticator-secret \
      --from-literal=.oapiusername="$(echo -n "oapiroot" | base64 | tr -d '\n')" \
      --from-literal=.oapipassword="$(openssl rand -base64 64 | tr -d '\n')" \
      --from-literal=.publickeyname="$(echo -n "public_key" | base64 | tr -d '\n')" \
      --from-literal=.publickeyvalue="$(openssl rand -base64 22 | tr -d '\n')" \
      --from-literal=.aeadsecret="$(openssl rand -base64 16 | tr -d '\n')" \
      --from-literal=.aeadnonce="$(openssl rand -base64 16 | tr -d '\n')" \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    log_info "Creating missing optional secrets (populated with dummy data)..."

    # API Debug Header Secret (Traffic Manager & Platform API)
    # Required for volume mount: apidebug-secret-vol
    kubectl create secret generic api-debug-header-secret \
      --from-literal=api-debug-header="X-Debug-Mode: enabled" \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # Traffic Manager Truststore Secret
    # Required for volume mount: trafficmanager-truststore-vol
    # Generate truststore if it doesn't exist
    if [ ! -f "../keystores/truststore.jks" ]; then
        log_info "Generating truststore.jks from certificate..."
        keytool -import -trustcacerts -noprompt \
          -alias server-cert \
          -file ../keystores/cert.pem \
          -keystore ../keystores/truststore.jks \
          -storepass changeit 2>/dev/null || {
            # Fallback: create empty truststore
            keytool -genkeypair -alias dummy -keyalg RSA -keysize 2048 \
              -keystore ../keystores/truststore.jks -storepass changeit \
              -dname "CN=dummy" -validity 1 2>/dev/null
            keytool -delete -alias dummy -keystore ../keystores/truststore.jks \
              -storepass changeit 2>/dev/null || true
        }
    fi
    kubectl create secret generic trafficmanager-truststore-secret \
      --from-file=truststore.jks=../keystores/truststore.jks \
      --from-literal=.trustStorePassword=changeit \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    # ConfigUI Certificate & Key Secrets
    # Required for volume mounts: configui-certificate-vol, configui-key-vol
    # CRITICAL: Filenames must match exactly what the deployment expects
    # Deployment mounts: /etc/mashery-server-ssl/tml-cm-crt.pem and /etc/mashery-server-ssl/tml-cm-key.pk8
    kubectl create secret generic configui-certificate-secret \
      --from-file=tml-cm-crt.pem=../keystores/cert.pem \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic configui-key-secret \
      --from-file=tml-cm-key.pk8=../keystores/key.pem \
      -n ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "✅ All secrets created"
}

# Create Helm values file
create_helm_values() {
    log_section "Phase 7: Creating Helm Values File"
    
    source custom-cam-le.env
    source db-config.env
    source ecr-config.env
    
    log_info "Generating Helm values file with all required fields..."
    
    backup_file "cam-le-untethered-values.yaml"
    cat > cam-le-untethered-values.yaml <<EOF
# CAM LE 6.2 Helm Values - Untethered Mode for AWS EKS
# Generated on $(date)

global:
  acceptEUA: true
  apimClusterMode: untethered
  apimImageRegistry: ${ECR_REGISTRY}/cam-le
  imagePullSecrets:
    - name: ecr-registry-secret
  imagePullPolicy: IfNotPresent
  k8sServiceType: LoadBalancer
  apimClusterName: ${CAM_APIM_CLUSTER_NAME:-camle-test}
  localDevAdminUser: admin
  localDevOAuthScope: "${AREA_UUID}"
  enableProbes: true
  
  mysqlDatabase:
    host: ${DB_ENDPOINT}
    port: 3306
    databaseSchema: masherysolar
    role: 'masherySolar'
    sslMode: 'disable'
    mutualTls: 'disable'
    caConfigmap: 'null'
    sslSecret: 'null'
    clientCertConfigmap: 'null'
    clientKeySecret: 'null'
    clientKeystoreSecret: 'null'
    connectTimeout: 4000
    netReadTimeout: 30
    netWriteTimeout: 360
    socketTimeout: 0
  
  logging:
    includeFluentBitContainer: true
    appLogLocation: console
  
  verboseLog: "disable"
  
  securityContext:
    runAsUser: 10001
    runAsGroup: 10001
  
  serviceAccountName: apiml-sa
  
  email:
    mail.transport.protocol: "log"

trafficmanager:
  image: apim-le-trafficmanager
  tag: v6.2.0
  replicas: 2
  logback:
    logLevel: INFO
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "2000m"
      memory: "2Gi"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  datasource:
    pool:
      maxActive: 16
      maxIdle: 8

platformapi:
  image: apim-le-platformapi
  tag: v6.2.0
  replicas: 1
  logback:
    logLevel: INFO
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
    limits:
      cpu: "1000m"
      memory: "2Gi"
  datasource:
    pool:
      maxActive: 16
      maxIdle: 8

configui:
  image: apim-le-configui
  tag: v6.2.0
  replicas: 1
  logger:
    logLevel: info
  httpsEnabled: true
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
    limits:
      cpu: "500m"
      memory: "1Gi"
  service:
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
  datasource:
    pool:
      maxActive: 16
      maxIdle: 8

loader:
  image: apim-le-loader
  tag: v6.2.0
  replicas: 1
  datasource:
    pool:
      maxActive: 12
      maxIdle: 6

loadercron:
  image: apim-le-loader-cron
  tag: v6.2.0
  serviceLoad: true
  fullLoad:
    schedule: "0 2 * * *"
    concurrencyPolicy: Forbid
  deltaLoad:
    schedule: "*/15 * * * *"
    concurrencyPolicy: Forbid
  onpremLoad:
    schedule: "*/15 * * * *"
    concurrencyPolicy: Forbid
  serviceUpdateSince: 15
  mapiLoad: true
  mapiUpdateSince: 15
  packagerLoad: true
  packagerUpdateSince: 15
  devclassLoad: true
  devclassUpdateSince: 15
  httpsClientSecurityLoad: true
  httpsClientSecurityUpdateSince: 15

cache:
  image: apim-le-cache
  tag: v6.2.0
  replicas: 3
  statisticsEnabled: true
  dataRegionMetricsEnabled: false
  allocatedRam:
    memcache:
      initial: 256
      max: 512
    counter:
      initial: 256
      max: 512
    content:
      initial: 256
      max: 512
    service:
      initial: 256
      max: 512
    package:
      initial: 256
      max: 512
    httpssecurity:
      initial: 256
      max: 512
  log4j:
    rootLogLevel: ERROR
    igniteLogLevel: ERROR
    apimLogLevel: INFO
  resources:
    requests:
      cpu: "500m"
      memory: "2Gi"
    limits:
      cpu: "1000m"
      memory: "3Gi"

logcollector:
  replicas: 2
  logsync:
    image: cam-le-logsync
    tag: v6.2.0
  datasource:
    pool:
      maxActive: 8
      maxIdle: 4
  logback:
    loglevel: INFO

preInstallDBPrep:
  image: apim-le-toolkit
  tag: v6.2.0
  populateSeedData: true
  apiKey: "${PACKAGE_KEY}"
  apiSecret: "${PACKAGE_SECRET}"
  initDBUserName: ${DB_USERNAME}
  areaName: "CAM LE Local Area"

loaderjob:
  image: apim-le-loader-cron
  tag: v6.2.0
EOF
    
    log_info "✅ Helm values file created"
}

# Fix Load Balancer Controller IAM Permissions
fix_load_balancer_iam() {
    log_section "Phase 7b: Fixing Load Balancer Controller IAM Permissions"
    
    source my-config.env
    
    log_info "Attaching Load Balancer IAM policy..."
    log_info "This fixes LoadBalancer services stuck in <pending> state"
    
    # Get the Load Balancer Controller service account role name
    LB_CONTROLLER_ROLE=$(kubectl get sa -n kube-system aws-load-balancer-controller -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null | cut -d'/' -f2)
    
    if [ -z "$LB_CONTROLLER_ROLE" ]; then
        log_warn "AWS Load Balancer Controller not found or not configured with IAM role"
        log_warn "LoadBalancer services may not provision external IPs"
        return
    fi
    
    log_info "Load Balancer Controller Role: $LB_CONTROLLER_ROLE"
    
    # Attach ElasticLoadBalancingFullAccess policy
    aws iam attach-role-policy \
      --role-name "$LB_CONTROLLER_ROLE" \
      --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess \
      --region ${CAM_AWS_REGION} 2>/dev/null || {
        log_warn "Policy may already be attached or IAM permissions needed"
      }
    
    # Restart Load Balancer Controller to pick up new permissions
    log_info "Restarting Load Balancer Controller..."
    kubectl rollout restart deployment -n kube-system aws-load-balancer-controller 2>/dev/null || {
        log_warn "Load Balancer Controller deployment not found in kube-system"
    }
    
    log_info "✅ Load Balancer Controller IAM permissions configured"
}

# Deploy CAM LE
deploy_cam_le() {
    log_section "Phase 8: Deploying CAM LE with Helm"
    
    source custom-cam-le.env
    
    # Create service account
    log_info "Creating service account and RBAC..."
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: apiml-sa
  namespace: ${K8S_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: apiml-role
  namespace: ${K8S_NAMESPACE}
rules:
- apiGroups: [""]
  resources: ["pods", "services", "endpoints"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: apiml-rolebinding
  namespace: ${K8S_NAMESPACE}
subjects:
- kind: ServiceAccount
  name: apiml-sa
  namespace: ${K8S_NAMESPACE}
roleRef:
  kind: Role
  name: apiml-role
  apiGroup: rbac.authorization.k8s.io
EOF
    
    log_info "Validating Helm chart..."
    cd ../deploy && helm lint . -f ../install-aws-untethered/cam-le-untethered-values.yaml && cd ../install-aws-untethered
    
    log_info "Deploying CAM LE (this will take 15-20 minutes)..."
    
    helm upgrade --install cam-le ../deploy/ \
      -f cam-le-untethered-values.yaml \
      --set preInstallDBPrep.initDBUserPassword=${DB_PASSWORD} \
      --set preInstallDBPrep.localDevAdminPassword=${ADMIN_PASSWORD} \
      -n ${K8S_NAMESPACE} \
      --wait --timeout 20m
    
    log_info "✅ CAM LE deployed"
}

# Verify deployment
verify_deployment() {
    log_section "Phase 9: Verifying Deployment"
    
    log_info "Checking pod status..."
    kubectl get pods -n ${K8S_NAMESPACE}
    
    log_info "Waiting for LoadBalancers to provision..."
    sleep 60
    
    CONFIGUI_URL=$(kubectl get svc configui-svc -n ${K8S_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    TM_URL=$(kubectl get svc trafficmanager-svc -n ${K8S_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    PAPI_URL=$(kubectl get svc platformapi-svc -n ${K8S_NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    log_info "Testing Platform API health..."
    sleep 30
    
    if curl -k -s https://${PAPI_URL}:8080/platform/ping | grep -q "UP"; then
        log_info "✅ Platform API is healthy"
    else
        log_warn "Platform API may not be ready yet. Check logs: kubectl logs -l app=platformapi"
    fi
    
    backup_file "deployment-summary.txt"
    cat > deployment-summary.txt <<EOF
========================================
 CAM LE Deployment Complete!
========================================

Config UI: https://${CONFIGUI_URL}:443
Traffic Manager: https://${TM_URL}:443
Platform API: https://${PAPI_URL}:8080

Login Credentials:
  Username: admin
  Password: ${ADMIN_PASSWORD}

Custom Values:
  Area UUID: ${AREA_UUID}
  Package Key: ${PACKAGE_KEY}
  Package Secret: ${PACKAGE_SECRET}

========================================
EOF
    
    cat deployment-summary.txt
    
    log_info "✅ Deployment summary saved to deployment-summary.txt"
}

# Prompt to continue
prompt_continue() {
    local phase_name=$1
    echo ""
    log_info "✅ Phase completed: $phase_name"
    echo ""
    read -p "Continue to next phase? (y/n/q to quit): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Qq]$ ]]; then
        log_warn "Deployment paused by user"
        log_info "To resume, run: $0 --start-from <phase-number>"
        exit 0
    elif [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warn "Deployment paused by user"
        log_info "To resume, run: $0 --start-from <phase-number>"
        exit 0
    fi
}

# Display help menu
show_help() {
    cat <<EOF
CAM LE 6.2 - Untethered Mode Deployment Script
===============================================

Usage: $0 [OPTIONS]

OPTIONS:
  --help, -h              Show this help message
  --interactive, -i       Interactive mode (prompt after each phase)
  --start-from PHASE      Start from specific phase (1-9)
  --auto                  Automatic mode (no prompts, run all phases)

PHASES:
  1. Check Prerequisites
  2. Setup Environment
  3. Generate Custom Values (Area UUID, Package Key, Secret)
  4. Create EKS Cluster
  5. Create Aurora Database
  6. Initialize Database
  7. Build and Push Docker Images
  8. Create Kubernetes Secrets
  9. Create Helm Values
  10. Deploy CAM LE
  11. Verify Deployment

EXAMPLES:
  # Interactive mode (recommended)
  $0 --interactive

  # Automatic mode (no prompts)
  $0 --auto

  # Start from phase 5 (database already created, skip to images)
  $0 --start-from 5

  # Start from phase 8 in interactive mode
  $0 --interactive --start-from 8

CONFIGURATION:
  Set environment variables before running:
    source my-config.env
    $0 --interactive

  See cam-le-config-template.env for all configuration options.

EOF
    exit 0
}

# Display phase menu
show_phase_menu() {
    echo ""
    echo "========================================"
    echo "  CAM LE Deployment Phases"
    echo "========================================"
    echo "  1. Check Prerequisites"
    echo "  2. Setup Environment"
    echo "  3. Generate Custom Values"
    echo "  4. Create EKS Cluster"
    echo "  5. Create Aurora Database"
    echo "  6. Initialize Database"
    echo "  7. Build and Push Docker Images"
    echo "  8. Create Kubernetes Secrets"
    echo "  9. Create Helm Values"
    echo " 10. Deploy CAM LE"
    echo " 11. Verify Deployment"
    echo "========================================"
    echo ""
}

# Main execution
main() {
    # Parse command line arguments
    local INTERACTIVE_MODE=false
    local AUTO_MODE=false
    local START_PHASE=1
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                ;;
            --interactive|-i)
                INTERACTIVE_MODE=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --start-from)
                START_PHASE=$2
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # If no mode specified, ask user
    if [ "$INTERACTIVE_MODE" = false ] && [ "$AUTO_MODE" = false ]; then
        echo ""
        echo "========================================"
        echo " CAM LE 6.2 - Untethered Mode Deployment"
        echo "========================================"
        echo ""
        echo "Select deployment mode:"
        echo "  1) Interactive (recommended) - Prompt after each phase"
        echo "  2) Automatic - Run all phases without prompts"
        echo "  3) Custom - Select starting phase"
        echo "  4) Help - Show detailed usage"
        echo ""
        read -p "Select option (1-4): " -n 1 -r
        echo ""
        
        case $REPLY in
            1)
                INTERACTIVE_MODE=true
                ;;
            2)
                AUTO_MODE=true
                ;;
            3)
                show_phase_menu
                read -p "Enter starting phase (1-11): " START_PHASE
                if ! [[ "$START_PHASE" =~ ^[0-9]+$ ]] || [ "$START_PHASE" -lt 1 ] || [ "$START_PHASE" -gt 11 ]; then
                    log_error "Invalid phase number. Must be between 1 and 11."
                    exit 1
                fi
                INTERACTIVE_MODE=true
                ;;
            4)
                show_help
                ;;
            *)
                log_error "Invalid option"
                exit 1
                ;;
        esac
    fi
    
    
    echo ""
    echo "========================================"
    echo " CAM LE 6.2 - Untethered Mode Deployment"
    echo " Complete Automated Installation"
    echo "========================================"
    echo ""
    
    # Set Kubernetes namespace from configuration
    K8S_NAMESPACE=${CAM_K8S_NAMESPACE:-camle}
    log_info "Kubernetes Namespace: $K8S_NAMESPACE"
    echo ""
    
    if [ "$INTERACTIVE_MODE" = true ]; then
        log_info "Running in INTERACTIVE mode"
        log_info "Starting from phase: $START_PHASE"
    else
        log_info "Running in AUTOMATIC mode"
    fi
    echo ""
    
    # Phase 1: Check Prerequisites
    if [ $START_PHASE -le 1 ]; then
        check_prerequisites
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Check Prerequisites"
    fi
    
    # Phase 2: Setup Environment
    if [ $START_PHASE -le 2 ]; then
        setup_environment
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Setup Environment"
    fi
    
    # Phase 3: Generate Custom Values
    if [ $START_PHASE -le 3 ]; then
        generate_custom_values
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Generate Custom Values"
    fi
    
    # Phase 4: Create EKS Cluster
    if [ $START_PHASE -le 4 ]; then
        create_eks_cluster
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Create EKS Cluster"
    fi
    
    # Phase 5: Create Aurora Database
    if [ $START_PHASE -le 5 ]; then
        create_database
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Create Aurora Database"
    fi
    
    # Phase 6: Initialize Database
    if [ $START_PHASE -le 6 ]; then
        initialize_database
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Initialize Database"
    fi
    
    # Phase 6b: Create Kubernetes Namespace (sub-phase, always runs with phase 6)
    if [ $START_PHASE -le 6 ]; then
        create_namespace
    fi
    
    # Phase 7: Build and Push Images
    if [ $START_PHASE -le 7 ]; then
        build_and_push_images
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Build and Push Docker Images"
    fi
    
    # Phase 8: Create Kubernetes Secrets
    if [ $START_PHASE -le 8 ]; then
        create_secrets
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Create Kubernetes Secrets"
    fi
    
    # Phase 9: Create Helm Values
    if [ $START_PHASE -le 9 ]; then
        create_helm_values
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Create Helm Values"
    fi
    
    # Phase 9b: Fix Load Balancer Controller IAM (sub-phase, always runs with phase 9)
    if [ $START_PHASE -le 9 ]; then
        fix_load_balancer_iam
    fi
    
    # Phase 10: Deploy CAM LE
    if [ $START_PHASE -le 10 ]; then
        deploy_cam_le
        [ "$INTERACTIVE_MODE" = true ] && prompt_continue "Deploy CAM LE"
    fi
    
    # Phase 11: Verify Deployment
    if [ $START_PHASE -le 11 ]; then
        verify_deployment
    fi
    
    log_section "✅ DEPLOYMENT COMPLETE!"
    log_info "Review deployment-summary.txt for access details"
    log_info "For troubleshooting, see UNTETHERED-DEPLOYMENT-GUIDE.md"
}

# Run main function
main "$@"
