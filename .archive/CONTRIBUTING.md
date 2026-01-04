# Contributing to CAM LE AWS Deployment

Thank you for your interest in contributing to the Boomi CAM LE AWS deployment project!

## How to Contribute

### Reporting Issues

If you encounter any issues with the deployment scripts:

1. Check existing [issues](../../issues) to see if it's already reported
2. Create a new issue with:
   - Clear description of the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (AWS region, EKS version, etc.)
   - Relevant logs or error messages

### Suggesting Enhancements

We welcome suggestions for improvements:

1. Open an issue with the tag `enhancement`
2. Describe your proposed change
3. Explain the use case and benefits
4. If possible, provide implementation details

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly in your AWS environment
5. Commit with clear messages (`git commit -m 'Add amazing feature'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Coding Standards

- **Shell Scripts**: Follow best practices
  - Use `set -e` for error handling
  - Add comments for complex logic
  - Use meaningful variable names
  - Include help/usage information
  
- **Documentation**: 
  - Update README.md if changing user-facing features
  - Add inline comments for complex operations
  - Update relevant documentation files

### Testing

Before submitting:

- Test deployment in a clean AWS account
- Verify cleanup script removes all resources
- Check that configuration templates are up to date
- Ensure documentation reflects any changes

## Code of Conduct

- Be respectful and inclusive
- Focus on constructive feedback
- Help others learn and grow

## Questions?

Feel free to open an issue for questions or reach out to the maintainers.

Thank you for contributing! 🚀
