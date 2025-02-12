#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set the folder name as a variable
new_folder="na-my-file"

# Record the start time
start_time=$(date +%s)

# Welcome message
echo -e "${BLUE}Welcome to the My File Production Environment Setup and Deployment Script!${NC}"
echo -e "${BLUE}This script will guide you through the process of setting up and deploying the My File application.${NC}"
echo

#####################
## Dependencies check
######################
echo -e "${NC}Checking Dependencies...${NC}"
# Check if git is installed
if ! command -v git &> /dev/null
then
    echo -e "${RED}git is not installed. Please install git and try again.${NC}"
    exit 1
fi
# Check if Node.js is installed
if ! command -v node &> /dev/null
then
    echo -e "${RED}Node.js is not installed. Please install Node.js and try again.${NC}"
    exit 1
fi
# Check if npm is installed
if ! command -v npm &> /dev/null
then
    echo -e "${RED}npm is not installed. Please install npm and try again.${NC}"
    exit 1
fi
echo -e "${GREEN}Dependencies found!${NC}"

#######################
## Questions / User Input
#######################
# Prompt user for AWS profile name
read -p "Enter your AWS profile name: " aws_profile

# Prompt user for environment (dev or prod)
read -p "Enter the environment to deploy (1 for dev, 2 for prod) [default: dev]: " environment
environment=${environment:-1}

# Check if the environment is valid
if [ "$environment" != "1" ] && [ "$environment" != "2" ]; then
    echo -e "${RED}Invalid environment. Please enter either '1' for dev or '2' for prod.${NC}"
    exit 1
fi

# Set the environment based on user input
if [ "$environment" == "1" ]; then
    environment="dev"
else
    environment="prod"
fi

# Validate AWS profile
if ! aws sts get-caller-identity --profile "$aws_profile" &>/dev/null; then
    echo -e "${RED}AWS profile '$aws_profile' is not valid or lacks permissions${NC}"
    exit 1
fi

# Check required permissions
# required_services=("s3" "cloudformation" "rds" "cognito-idp" "apigateway")
# for service in "${required_services[@]}"; do
#     if ! aws iam simulate-principal-policy --profile "$aws_profile" [...]; then
#         echo -e "${RED}Missing required permissions for $service${NC}"
#         exit 1
#     fi
# done

#######################
## Folder Prep and Repo Cloning
#######################
echo -e "${NC}Setting Up Folders...${NC}"
# Create the new folder within the current directory
mkdir -p "$new_folder"
cd "$new_folder" || exit
echo -e "${GREEN}Done!${NC}"
echo -e "${NC}Cloning Repos...${NC}"
# Clone the required repositories
repos=(
    "https://github.com/newamericafoundation/na-my-file-infra.git"
    "https://github.com/newamericafoundation/na-my-file-api.git"
    "https://github.com/newamericafoundation/na-my-file-api-client.git"
    "https://github.com/newamericafoundation/na-my-file-client.git"
)

for repo in "${repos[@]}"
do
    repo_name=$(basename "$repo" .git)
    if [ ! -d "$repo_name" ]; then
        git clone "$repo" || { echo -e "${RED}Failed to clone $repo.${NC}"; exit 1; }
    else
        echo -e "${GREEN}$repo_name already exists. Skipping clone.${NC}"
    fi
done
echo -e "${GREEN}Done!${NC}"

#######################
## Installation and Deployment
#######################
echo -e "${NC}Starting Installation...${NC}"

# Deploy the infrastructure
echo -e "${GREEN}Deploying infrastructure...${NC}"
cd na-my-file-infra
npm install || { echo -e "${RED}Failed to install dependencies for infrastructure.${NC}"; exit 1; }
AWS_PROFILE="$aws_profile" npm run cdk-bootstrap || { echo -e "${RED}Failed to bootstrap CDK for infrastructure.${NC}"; exit 1; }
if [ "$environment" == "dev" ]; then
    AWS_PROFILE="$aws_profile" npm run stack-deploy-dev || { echo -e "${RED}Failed to deploy infrastructure for dev environment.${NC}"; exit 1; }
else
    AWS_PROFILE="$aws_profile" npm run stack-deploy-prod || { echo -e "${RED}Failed to deploy infrastructure for prod environment.${NC}"; exit 1; }
fi
cd ..

# Prepare the API and generate OpenAPI spec
echo -e "${GREEN}Preparing the API and generating OpenAPI spec...${NC}"
cd na-my-file-api
npm install || { echo -e "${RED}Failed to install dependencies for API.${NC}"; exit 1; }
AWS_PROFILE="$aws_profile" npm run generate-oas || { echo -e "${RED}Failed to generate OAS.${NC}"; exit 1; }
AWS_PROFILE="$aws_profile" npm run generate-api-client || { echo -e "${RED}Failed to generate API client code.${NC}"; exit 1; }
cd ..

# Install and build the API client
echo -e "${GREEN}Building API client...${NC}"
cd na-my-file-api-client
npm install || { echo -e "${RED}Failed to install dependencies for API client.${NC}"; exit 1; }
AWS_PROFILE="$aws_profile" npm run build || { echo -e "${RED}Failed to build the API client.${NC}"; exit 1; }
cd ..

# Deploying the API
echo -e "${GREEN}Deploying the API...${NC}"
cd na-my-file-api
if [ "$environment" == "dev" ]; then
    AWS_PROFILE="$aws_profile" npm run stack-deploy-dev || { echo -e "${RED}Failed to deploy API for dev environment.${NC}"; exit 1; }
else
    AWS_PROFILE="$aws_profile" npm run stack-deploy-prod || { echo -e "${RED}Failed to deploy API for prod environment.${NC}"; exit 1; }
fi
cd ..

# Setting up the Database
echo -e "${GREEN}Setting up the Database...${NC}"
cd na-my-file-api
# Add these lines before db:setup
chmod +x ./src/scripts/db-setup-tunnel
chmod +x ./src/scripts/ssh-tunnel
AWS_PROFILE="$aws_profile" npm run db:setup || { echo -e "${RED}Failed to set up the database.${NC}"; exit 1; }
cd ..

# Deploy the client  
echo -e "${GREEN}Deploying client...${NC}"
cd na-my-file-client
npm install || { echo -e "${RED}Failed to install dependencies for client.${NC}"; exit 1; }
if [ "$environment" == "dev" ]; then
    AWS_PROFILE="$aws_profile" npm run deploy-dev || { echo -e "${RED}Failed to deploy client for dev environment.${NC}"; exit 1; }
else
    AWS_PROFILE="$aws_profile" npm run deploy-prod || { echo -e "${RED}Failed to deploy client for prod environment.${NC}"; exit 1; }
fi
cd ..


# Get and print the website URL
# echo -e "${GREEN}Getting the website URL...${NC}"
# if [ "$environment" == "dev" ]; then
#     CLOUDFRONT_DIST_ID=$(aws ssm get-parameter --profile "$aws_profile" --region us-east-1 --name "/na-my-file-infra/dev/newamerica-web-ui-cloudfront-dist-id" --query "Parameter.Value" --output text)
#     website_url=$(aws cloudfront get-distribution --profile "$aws_profile" --region us-east-1 --id "$CLOUDFRONT_DIST_ID" --query "Distribution.DomainName" --output text)
# else
#     CLOUDFRONT_DIST_ID=$(aws ssm get-parameter --profile "$aws_profile" --region us-east-1 --name "/na-my-file-infra/prod/newamerica-web-ui-cloudfront-dist-id" --query "Parameter.Value" --output text)
#     website_url=$(aws cloudfront get-distribution --profile "$aws_profile" --region us-east-1 --id "$CLOUDFRONT_DIST_ID" --query "Distribution.DomainName" --output text)
# fi
# echo -e "${GREEN}Your website is available at: ${BLUE}https://$website_url${NC}"

# Record the end time
end_time=$(date +%s)

# Calculate the total execution time
execution_time=$((end_time - start_time))

# Print the total execution time
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${BLUE}Thank you for using the My File Production Environment Setup and Deployment Script.${NC}"
echo -e "${BLUE}Your My File application is now set up and ready to use in the $environment environment.${NC}"
echo -e "${BLUE}Total execution time: $execution_time seconds.${NC}"