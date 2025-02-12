#!/bin/bash

# Set your AWS profile and region
PROFILE="my-file-test"
REGION="us-east-1"

echo "Starting cleanup..."

# Delete secrets from Secrets Manager
echo "Deleting secrets..."
for secret in $(aws secretsmanager list-secrets --profile $PROFILE --region $REGION \
    --query 'SecretList[?contains(Name, `bastion-host-keypair-main`)].Name' --output text); do
    echo "Deleting secret: $secret"
    aws secretsmanager delete-secret --secret-id $secret --force-delete-without-recovery \
        --profile $PROFILE --region $REGION
done

# Delete CloudFormation stacks
echo "Deleting CloudFormation stacks..."
for stack in $(aws cloudformation list-stacks --profile $PROFILE --region $REGION \
    --query 'StackSummaries[?StackStatus!=`DELETE_COMPLETE` && !contains(StackName, `CDKToolkit`)].StackName' --output text); do
    echo "Deleting stack: $stack"
    # First remove stack protection if it exists
    aws cloudformation update-termination-protection --no-enable-termination-protection \
        --stack-name $stack --profile $PROFILE --region $REGION 2>/dev/null || true
    
    # Try to delete the stack
    aws cloudformation delete-stack --stack-name $stack --profile $PROFILE --region $REGION
    
    # Wait for stack deletion
    echo "Waiting for stack $stack to be deleted..."
    aws cloudformation wait stack-delete-complete --stack-name $stack --profile $PROFILE --region $REGION
done

echo "Deleting RDS instances..."
for db in $(aws rds describe-db-instances --profile $PROFILE --region $REGION \
    --query 'DBInstances[].DBInstanceIdentifier' --output text); do
    echo "Deleting RDS instance: $db"
    # Disable deletion protection
    aws rds modify-db-instance --db-instance-identifier $db \
        --no-deletion-protection --profile $PROFILE --region $REGION
    
    # Delete the instance without final snapshot
    aws rds delete-db-instance --db-instance-identifier $db \
        --skip-final-snapshot --profile $PROFILE --region $REGION
    
    echo "Waiting for RDS instance $db to be deleted..."
    aws rds wait db-instance-deleted --db-instance-identifier $db \
        --profile $PROFILE --region $REGION
done

echo "Deleting S3 buckets..."
for bucket in $(aws s3api list-buckets --profile $PROFILE \
    --query 'Buckets[].Name' --output text); do
    # Skip CDK toolkit bucket
    if [[ $bucket == cdk-* ]]; then
        echo "Skipping CDK bucket: $bucket"
        continue
    fi
    
    echo "Cleaning bucket: $bucket"
    # Delete all versions (including delete markers)
    aws s3api list-object-versions --bucket $bucket --profile $PROFILE \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read -r key versionId; do
        echo "Deleting object: $key (version $versionId)"
        aws s3api delete-object --bucket $bucket --key "$key" --version-id "$versionId" --profile $PROFILE
    done
    
    # Delete delete markers
    aws s3api list-object-versions --bucket $bucket --profile $PROFILE \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | while read -r key versionId; do
        echo "Deleting delete marker: $key (version $versionId)"
        aws s3api delete-object --bucket $bucket --key "$key" --version-id "$versionId" --profile $PROFILE
    done
    
    echo "Deleting bucket: $bucket"
    aws s3 rb s3://$bucket --force --profile $PROFILE
done

echo "Deleting Lambda functions..."
for func in $(aws lambda list-functions --profile $PROFILE --region $REGION \
    --query 'Functions[].FunctionName' --output text); do
    echo "Deleting function: $func"
    aws lambda delete-function --function-name $func --profile $PROFILE --region $REGION
done


# Delete secrets from Secrets Manager
echo "Deleting secrets..."
for secret in $(aws secretsmanager list-secrets --profile $PROFILE --region $REGION \
    --query 'SecretList[?contains(Name, `bastion-host-keypair-main`)].Name' --output text); do
    echo "Deleting secret: $secret"
    aws secretsmanager delete-secret --secret-id $secret --force-delete-without-recovery \
        --profile $PROFILE --region $REGION
done


echo "Cleanup completed!"


echo "=== CHECKING ALL RESOURCES ==="

echo -e "\n1. CloudFormation Stacks:"
aws cloudformation list-stacks --profile $PROFILE --region $REGION \
    --query 'StackSummaries[?StackStatus!=`DELETE_COMPLETE`].[StackName,StackStatus]' \
    --output table

echo -e "\n2. Secrets in Secrets Manager:"
aws secretsmanager list-secrets --profile $PROFILE --region $REGION \
    --query 'SecretList[?contains(Name, `na-my-file`) || contains(Name, `postgres`) || contains(Name, `bastion`)].[Name,ARN]' \
    --output table

echo -e "\n3. SSM Parameters:"
aws ssm get-parameters-by-path --path "/" --recursive --profile $PROFILE --region $REGION \
    --query 'Parameters[?contains(Name, `na-my-file`)].[Name,Type]' \
    --output table

echo -e "\n4. S3 Buckets:"
aws s3api list-buckets --profile $PROFILE \
    --query 'Buckets[?contains(Name, `na-my-file`)].[Name,CreationDate]' \
    --output table

echo -e "\n5. RDS Instances:"
aws rds describe-db-instances --profile $PROFILE --region $REGION \
    --query 'DBInstances[?contains(DBInstanceIdentifier, `na-my-file`)].[DBInstanceIdentifier,DBInstanceStatus]' \
    --output table

echo -e "\n6. Lambda Functions:"
aws lambda list-functions --profile $PROFILE --region $REGION \
    --query 'Functions[?contains(FunctionName, `na-my-file`)].[FunctionName,Runtime]' \
    --output table

echo -e "\n7. API Gateway APIs:"
aws apigateway get-rest-apis --profile $PROFILE --region $REGION \
    --query 'items[?contains(name, `na-my-file`)].[name,id]' \
    --output table

echo -e "\n8. Cognito User Pools:"
aws cognito-idp list-user-pools --max-results 60 --profile $PROFILE --region $REGION \
    --query 'UserPools[?contains(Name, `na-my-file`)].[Name,Id]' \
    --output table