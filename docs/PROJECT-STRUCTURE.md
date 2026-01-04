# Project Structure

This document describes the organization of the CAM LE AWS deployment repository.

## Directory Layout

```
cam-le-ut-aws-eks-deployment/
├── README.md                          # Main documentation (deployment guide)
├── LICENSE                            # MIT License
├── CONTRIBUTING.md                    # Contribution guidelines
├── CHANGELOG.md                       # Version history
├── .gitignore                         # Git ignore rules
│
├── scripts/                           # Deployment automation scripts
│   ├── deploy-cam-le-untethered-complete.sh    # Main deployment orchestrator
│   ├── aurora-mysql.sh                         # Aurora database setup
│   ├── setup-ecr-and-build.sh                  # ECR and image build
│   ├── install-aws-lb-controller.sh            # Load Balancer Controller
│   ├── upgrade-to-internet-facing.sh           # Upgrade LB to internet-facing
│   └── cleanup-all-resources.sh                # Complete cleanup
│
├── config/                            # Configuration templates
│   └── my-config.env.template         # Environment configuration template
│
└── docs/                              # Additional documentation
    ├── UNTETHERED-DEPLOYMENT-GUIDE.md  # Detailed manual deployment guide
    ├── PLATFORM-API-VALIDATION.md      # Platform API testing guide
    └── README.md                       # Documentation index (this file)
```

## File Descriptions

### Root Files

- **README.md**: Complete deployment guide with architecture, installation, validation, and troubleshooting
- **LICENSE**: MIT License for the project
- **CONTRIBUTING.md**: Guidelines for contributing to the project
- **CHANGELOG.md**: Version history and release notes
- **.gitignore**: Excludes sensitive files (passwords, keystores, generated configs)

### Scripts Directory

All executable scripts for deployment automation:

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy-cam-le-untethered-complete.sh` | Main orchestrator (11 phases) | `./deploy-cam-le-untethered-complete.sh --interactive` |
| `aurora-mysql.sh` | Create Aurora MySQL cluster | Called by main script or standalone |
| `setup-ecr-and-build.sh` | Setup ECR and build images | Called by main script or standalone |
| `install-aws-lb-controller.sh` | Install AWS LB Controller | Called by main script or standalone |
| `upgrade-to-internet-facing.sh` | Upgrade LoadBalancers | `./upgrade-to-internet-facing.sh` |
| `cleanup-all-resources.sh` | Remove all AWS resources | `./cleanup-all-resources.sh` |

### Config Directory

Configuration templates and examples:

- **my-config.env.template**: Template for user configuration
  - Copy to `my-config.env` (gitignored) and customize
  - Contains AWS region, cluster names, passwords, etc.

### Docs Directory

Additional documentation:

- **UNTETHERED-DEPLOYMENT-GUIDE.md**: Comprehensive manual deployment guide with detailed steps
- **PLATFORM-API-VALIDATION.md**: How to validate Platform API deployment
- **README.md**: This file - documentation index

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/cam-le-aws-deployment.git
   cd cam-le-aws-deployment
   ```

2. **Configure your deployment**
   ```bash
   cp config/my-config.env.template config/my-config.env
   vim config/my-config.env  # Edit with your settings
   ```

3. **Run deployment**
   ```bash
   source config/my-config.env
   ./scripts/deploy-cam-le-untethered-complete.sh --interactive
   ```

4. **Cleanup when done**
   ```bash
   ./scripts/cleanup-all-resources.sh
   ```

## Generated Files (Not in Git)

During deployment, these files are created locally (excluded by .gitignore):

- `my-config.env` - Your actual configuration
- `db-config.env` - Database connection details
- `ecr-config.env` - ECR registry information
- `custom-cam-le.env` - Generated custom values (Area UUID, Package Key/Secret)
- `cam-le-untethered-values.yaml` - Helm values file
- `deployment-summary.txt` - Access URLs and credentials
- `keystores/` - SSL/TLS certificates and keystores

## Prerequisites

See the main README.md for complete prerequisites.

## Contributing

See CONTRIBUTING.md for guidelines on how to contribute.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
