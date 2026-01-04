#!/bin/bash
# Automated cleanup wrapper - responds YES automatically

# Navigate to scripts directory
cd /Users/anshumanpadhi/workspace/boomi-apim/CAM-LE/Boomi_Cam_Local_6_2_0_GA_346/cam-le-ut-aws-eks-deployment/scripts

# Run cleanup with automatic YES response
echo "YES" | ./cleanup-all-resources.sh
