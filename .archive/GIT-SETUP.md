# Git Repository Setup Guide

This guide helps you initialize and push the CAM LE AWS deployment repository to GitHub.

## Prerequisites

- Git installed (`git --version`)
- GitHub account
- Git configured with your identity:
  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "your.email@example.com"
  ```

## Step 1: Create GitHub Repository

1. Go to https://github.com/new
2. **Repository name**: `cam-le-ut-aws-eks-deployment` (or your preferred name)
3. **Description**: "Automated deployment scripts for Boomi Cloud API Management Local Edition (Untethered Mode) on AWS EKS"
4. **Visibility**: Choose Public or Private
5. **DO NOT** initialize with README, .gitignore, or license (we already have these)
6. Click "Create repository"

## Step 2: Initialize Local Git Repository

Navigate to the project directory and initialize git:

```bash
cd /path/to/Boomi_Cam_Local_6_2_0_GA_346/cam-le-ut-aws-eks-deployment

# Initialize git repository
git init

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: CAM LE 6.2 AWS EKS deployment automation"
```

## Step 3: Link to GitHub Repository

Replace `YOUR_USERNAME` with your GitHub username:

```bash
# Add remote repository
git remote add origin https://github.com/YOUR_USERNAME/cam-le-ut-aws-eks-deployment.git

# Verify remote
git remote -v
```

## Step 4: Push to GitHub

```bash
# Push to main branch
git branch -M main
git push -u origin main
```

## Step 5: Verify Upload

1. Go to your GitHub repository URL
2. Verify all files are present:
   - ✅ README.md displays as repository homepage
   - ✅ Scripts in `/scripts` directory
   - ✅ Documentation in `/docs` directory
   - ✅ Configuration template in `/config` directory
   - ✅ LICENSE, CONTRIBUTING.md, CHANGELOG.md present

## Step 6: Set Up Branch Protection (Optional)

For collaborative projects:

1. Go to repository Settings → Branches
2. Add branch protection rule for `main`:
   - Require pull request reviews before merging
   - Require status checks to pass
   - Require branches to be up to date

## Repository Features to Enable

### Topics/Tags

Add relevant topics to help others discover your repository:

```
boomi, aws, eks, aurora, deployment, automation, kubernetes, api-management, 
cloud, devops, infrastructure-as-code
```

### GitHub Actions (Future)

Consider adding CI/CD workflows:
- Shellcheck for script validation
- Documentation link checking
- Automated testing in AWS sandbox

### Issues and Discussions

Enable:
- **Issues**: For bug reports and feature requests
- **Discussions**: For Q&A and community interaction
- **Wiki**: For extended documentation

## Quick Commands Reference

```bash
# Check status
git status

# Add new files
git add filename

# Commit changes
git commit -m "Description of changes"

# Push changes
git push origin main

# Pull latest changes
git pull origin main

# Create new branch
git checkout -b feature/new-feature

# View commit history
git log --oneline
```

## Updating the Repository

When you make changes to scripts or documentation:

```bash
# 1. Check what changed
git status
git diff

# 2. Add changed files
git add .

# 3. Commit with descriptive message
git commit -m "feat: Add support for multi-region deployment"

# 4. Push to GitHub
git push origin main
```

## Commit Message Convention

Use conventional commits format:

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code formatting (no logic change)
- `refactor:` Code refactoring
- `test:` Adding tests
- `chore:` Maintenance tasks

Examples:
```bash
git commit -m "feat: Add automated backup script"
git commit -m "fix: Resolve Aurora subnet group creation error"
git commit -m "docs: Update troubleshooting section with EKS 1.29 notes"
```

## Troubleshooting

### Authentication Issues

If using HTTPS and having authentication issues:

```bash
# Use SSH instead
git remote set-url origin git@github.com:YOUR_USERNAME/cam-le-ut-aws-eks-deployment.git
```

Or use GitHub CLI:
```bash
gh auth login
```

### Large Files

If you accidentally committed large files:

```bash
# Remove file from git but keep locally
git rm --cached path/to/large/file

# Update .gitignore
echo "path/to/large/file" >> .gitignore

# Commit the change
git commit -m "chore: Remove large file from git"
```

## Security Considerations

⚠️ **IMPORTANT**: Never commit sensitive data!

The `.gitignore` file already excludes:
- ✅ Password files (`*.env` except templates)
- ✅ SSL certificates and keystores
- ✅ Generated configuration files
- ✅ AWS credentials

Before committing, always verify:
```bash
# Check what will be committed
git status
git diff --cached

# Search for potential secrets
grep -r "password\|secret\|key" --include="*.env" .
```

## Next Steps

After setting up the repository:

1. **Add README badges**: Build status, license, version
2. **Create releases**: Tag versions for stable releases
3. **Write examples**: Add example deployments in `/examples`
4. **Set up CI/CD**: Automate testing and validation
5. **Engage community**: Respond to issues and PRs

## Resources

- [GitHub Docs](https://docs.github.com/)
- [Git Documentation](https://git-scm.com/doc)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)

---

**Happy Coding!** 🚀

For questions or issues, please open a GitHub issue or discussion.
