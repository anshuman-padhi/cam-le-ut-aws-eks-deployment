# CAM LE 6.2 - AWS EKS Untethered Mode Deployment

This folder contains the complete deployment scripts for installing Boomi Cloud API Management Local Edition 6.2 in **untethered mode** on AWS EKS. Copy this folder to your local machine to the same location as the Boomi CAM Local folder and run the deployment scripts.

## Quick Start

### Prerequisites
- AWS CLI v2.x (configured with credentials)
- kubectl v1.25+
- eksctl v0.150+
- Helm v3.x
- Docker or Podman
- MySQL client
- jq

### 1. Configure Deployment

Create your configuration file in this directory:

```bash
# Copy the template
cp my-config.env.template my-config.env

# Edit with your settings
vi my-config.env
```

Required settings:
```bash
export CAM_AWS_REGION=ap-southeast-2
export CAM_CLUSTER_NAME=cam-le-prod-cluster
export CAM_K8S_NAMESPACE=camle
export CAM_DB_PASSWORD='YourSecurePassword123!'
export CAM_DML_PASSWORD='YourDMLPassword123!'
export CAM_ADMIN_PASSWORD='YourAdminPassword123!'
```

### 2. Run Deployment

From this directory:

```bash
cd install-untethered-camle-aws
source my-config.env
./deploy-cam-le-untethered-complete.sh --interactive
```

## Deployment Scripts

### Main Deployment Script
- **deploy-cam-le-untethered-complete.sh** - Complete orchestration (11 phases)

### Child Scripts  
- **aurora-mysql.sh** - Create Aurora MySQL cluster (multi-AZ)
- **setup-ecr-and-build.sh** - Build & push Docker images to ECR
- **install-aws-lb-controller.sh** - Install AWS Load Balancer Controller
- **upgrade-to-internet-facing.sh** - Upgrade LoadBalancers to internet-facing

## Deployment Phases

The main script executes 11 phases:

1. Check Prerequisites
2. Setup Environment
3. Generate Custom Values (Area UUID, Package Key/Secret)
4. Create EKS Cluster
5. Create Aurora Database
6. Initialize Database (139 tables)
   - 6b. Create Kubernetes Namespace
7. Build & Push Docker Images
8. Create Kubernetes Secrets
9. Create Helm Values
   - 9b. Fix Load Balancer IAM
10. Deploy CAM LE with Helm
11. Verify Deployment

**Total Time**: 75-120 minutes

## Folder Structure

```
install-untethered-camle-aws/          # This folder - All deployment files
├── deploy-cam-le-untethered-complete.sh
├── aurora-mysql.sh
├── setup-ecr-and-build.sh
├── install-aws-lb-controller.sh
├── upgrade-to-internet-facing.sh
├── README.md
├── my-config.env.template       # Configuration template
├── my-config.env                # Your configuration (create from template)
├── db-config.env                # Generated during deployment
├── ecr-config.env               # Generated during deployment
├── custom-cam-le.env            # Generated during deployment
└── cam-le-untethered-values.yaml # Generated during deployment

../                              # Parent folder - Boomi resources
├── deploy/                      # Helm charts
├── scripts/                     # Supporting scripts
│   ├── customize.sh            # Generate custom values
│   └── db/                     # SQL schema files
└── keystores/                   # Generated SSL certificates
```

## Usage Examples

### Interactive Deployment (Recommended)
```bash
./deploy-cam-le-untethered-complete.sh --interactive
```

### Automatic Deployment
```bash
./deploy-cam-le-untethered-complete.sh --auto
```

### Resume from Specific Phase
```bash
# Resume from phase 7 (build images)
./deploy-cam-le-untethered-complete.sh --start-from 7
```

### Upgrade to Internet-Facing LoadBalancers
```bash
./upgrade-to-internet-facing.sh
```

## Configuration Files

**User Configuration** (create before deployment):
- `my-config.env` - Main configuration (copy from template)

**Generated Configuration** (created during deployment):
- `db-config.env` - Database connection details
- `ecr-config.env` - ECR registry information  
- `custom-cam-le.env` - Area UUID, Package Key/Secret
- `cam-le-untethered-values.yaml` - Helm values

All configuration files are stored locally in the `install-untethered-camle-aws` folder. 

## Output Files

Generated in this directory:
- `cam-le-untethered-values.yaml` - Helm values
- `deployment-summary.txt` - Access URLs and credentials
- `ekscluster-config.yaml` - EKS cluster configuration
- `db-init-job.yaml` - Database initialization job

## Accessing CAM LE

After deployment completes:

```bash
# Get service URLs
kubectl get svc -n camle

# ConfigUI URL will be shown in deployment-summary.txt
# Login: admin / <your CAM_ADMIN_PASSWORD>
```

## Troubleshooting

### View logs
```bash
kubectl logs -n camle -l app=platformapi-deploy
kubectl logs -n camle -l app=configui-deploy
kubectl logs -n camle -l app=trafficmanager-deploy
```

### Check pod status
```bash
kubectl get pods -n camle
kubectl describe pod <pod-name> -n camle
```

### Verify database  
```bash
kubectl run mysql-client --rm -it --restart=Never \
  --image=mysql:8.0 -n camle \
  -- mysql -h <db-endpoint> -u admin -p
```

## Cleanup

To remove all deployed resources:

```bash
./cleanup-all-resources.sh
```

This removes:
- Helm deployment
- Kubernetes resources
- EKS cluster
- Aurora database
- ECR repositories
- Local config files

## Documentation

- **Parent Directory**: Full Boomi CAM LE documentation
- **UNTETHERED-DEPLOYMENT-GUIDE.md**: Detailed deployment guide

## Support

For issues or questions, refer to:
1. UNTETHERED-DEPLOYMENT-GUIDE.md
2. Boomi official documentation
3. Check kubectl logs for specific component errors
