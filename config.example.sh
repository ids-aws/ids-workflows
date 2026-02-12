#!/bin/bash
# Configuration template - Copy to config.local.sh and customize

# GitHub Organization
ORG_NAME="innovds"

# AWS Configuration (optional, for ECR registry-type only)
AWS_ACCOUNT_ID=""
AWS_REGION=""

# ECR Registry (derived, empty if no AWS)
ECR_REGISTRY="${AWS_ACCOUNT_ID:+${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com}"

# SonarQube
SONAR_HOST_URL=""

# Azure DevOps
AZURE_ORG="innovds"
AZURE_PROJECT=""
