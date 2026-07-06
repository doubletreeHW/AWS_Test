# create-ecs-resources.ps1
# 이 스크립트는 AWS ECR, ECS 클러스터, 태스크 정의 등록 및 서비스를 자동으로 생성합니다.

# 방금 설치된 AWS CLI 기본 설치 경로를 PATH에 강제 추가하여 실행 인식
$env:Path += ";C:\Program Files\Amazon\AWSCLIV2\"

$AWS_REGION = "ap-northeast-2"
$ECR_REPO_NAME = "aws-test-repo"
$ECS_CLUSTER_NAME = "aws-test-cluster"
$ECS_SERVICE_NAME = "aws-test-service"
$ECS_TASK_FAMILY = "aws-test-task"
$CONTAINER_NAME = "aws-test-container"


Write-Host "========== 1. AWS 자격 증명 확인 ==========" -ForegroundColor Cyan
$identity = aws sts get-caller-identity --query "[Account, Arn]" --output json | ConvertFrom-Json
if (-not $identity) {
    Write-Error "AWS 인증 정보가 설정되지 않았습니다. 'aws configure'를 실행하여 자격 증명을 설정해 주세요."
    exit 1
}
$AWS_ACCOUNT_ID = $identity[0]
Write-Host "사용 중인 AWS 계정 ID: $AWS_ACCOUNT_ID" -ForegroundColor Green

Write-Host "`n========== 2. Amazon ECR 레포지토리 생성 ==========" -ForegroundColor Cyan
$repoCheck = aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION 2>$null
if (-not $repoCheck) {
    Write-Host "ECR Repository '$ECR_REPO_NAME' 생성 중..."
    aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION
} else {
    Write-Host "이미 ECR Repository '$ECR_REPO_NAME'가 존재합니다." -ForegroundColor Yellow
}

Write-Host "`n========== 3. ECS 클러스터 생성 ==========" -ForegroundColor Cyan
$clusterCheck = aws ecs describe-clusters --clusters $ECS_CLUSTER_NAME --region $AWS_REGION 2>$null | ConvertFrom-Json
$clusterStatus = $clusterCheck.clusters | Where-Object { $_.status -eq 'ACTIVE' }
if (-not $clusterStatus) {
    Write-Host "ECS 클러스터 '$ECS_CLUSTER_NAME' 생성 중..."
    aws ecs create-cluster --cluster-name $ECS_CLUSTER_NAME --region $AWS_REGION
} else {
    Write-Host "이미 ECS 클러스터 '$ECS_CLUSTER_NAME'가 존재합니다." -ForegroundColor Yellow
}

Write-Host "`n========== 4. ECS Task Execution Role 확인 및 생성 ==========" -ForegroundColor Cyan
$roleName = "ecsTaskExecutionRole"
$roleCheck = aws iam get-role --role-name $roleName 2>$null
if (-not $roleCheck) {
    Write-Host "IAM 역할 '$roleName' 생성 중..."
    
    # Trust policy 파일 임시 작성
    $trustPolicyJson = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@
    $trustPolicyPath = Join-Path $PSScriptRoot "ecs-trust-policy.json"
    [System.IO.File]::WriteAllText($trustPolicyPath, $trustPolicyJson, [System.Text.UTF8Encoding]($false))
    
    # Role 생성 및 Policy 연결
    aws iam create-role --role-name $roleName --assume-role-policy-document "file://$trustPolicyPath"
    aws iam attach-role-policy --role-name $roleName --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    
    Remove-Item $trustPolicyPath -Force
    Write-Host "IAM 역할 '$roleName' 및 관련 정책 연동 완료." -ForegroundColor Green
} else {
    Write-Host "이미 '$roleName' 역할이 존재합니다." -ForegroundColor Yellow
}

Write-Host "`n========== 5. ECS Task Definition 등록 ==========" -ForegroundColor Cyan
$templatePath = Join-Path $PSScriptRoot "..\.aws\task-definition.json"
if (-not (Test-Path $templatePath)) {
    Write-Error "Task definition 템플릿 파일을 찾을 수 없습니다: $templatePath"
    exit 1
}

# 템플릿 파일 읽어서 placeholders 치환
$jsonContent = Get-Content $templatePath -Raw
$jsonContent = $jsonContent.Replace("<AWS_ACCOUNT_ID>", $AWS_ACCOUNT_ID)
$jsonContent = $jsonContent.Replace("<AWS_REGION>", $AWS_REGION)
$jsonContent = $jsonContent.Replace("<ECR_REPOSITORY>", $ECR_REPO_NAME)
$jsonContent = $jsonContent.Replace("<IMAGE_TAG>", "latest") # 최초 기동용 임시 태그

$tempTaskDefPath = Join-Path $PSScriptRoot "temp-task-definition.json"
[System.IO.File]::WriteAllText($tempTaskDefPath, $jsonContent, [System.Text.UTF8Encoding]($false))

Write-Host "Task Definition 등록 중..."
aws ecs register-task-definition --cli-input-json "file://$tempTaskDefPath" --region $AWS_REGION
Remove-Item $tempTaskDefPath -Force

Write-Host "`n========== 6. 기본 VPC 및 서브넷/보안그룹 정보 조회 ==========" -ForegroundColor Cyan
Write-Host "디폴트 VPC 정보 검색 중..."
$defaultVpc = aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query "Vpcs[0].VpcId" --output text --region $AWS_REGION
if ($defaultVpc -eq "None" -or -not $defaultVpc) {
    Write-Error "디폴트 VPC를 찾을 수 없습니다. 수동으로 서브넷 및 보안그룹을 연결해야 할 수 있습니다."
    exit 1
}
Write-Host "디폴트 VPC ID: $defaultVpc"

Write-Host "디폴트 서브넷 목록 조회 중..."
$subnets = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$defaultVpc" "Name=default-for-az,Values=true" --query "Subnets[*].SubnetId" --output json --region $AWS_REGION
$subnetIds = ($subnets | ConvertFrom-Json) -join ","
Write-Host "디폴트 서브넷 ID 목록: $subnetIds"

Write-Host "디폴트 보안그룹 조회 중..."
$securityGroup = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$defaultVpc" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text --region $AWS_REGION
Write-Host "디폴트 보안그룹 ID: $securityGroup"

Write-Host "`n========== 7. ECS 서비스 생성 ==========" -ForegroundColor Cyan
$serviceCheck = aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION 2>$null | ConvertFrom-Json
$serviceStatus = $serviceCheck.services | Where-Object { $_.status -eq 'ACTIVE' }

if (-not $serviceStatus) {
    Write-Host "ECS Fargate 서비스 '$ECS_SERVICE_NAME' 생성 중..."
    
    $networkConfig = "awsvpcConfiguration={subnets=[$subnetIds],securityGroups=[$securityGroup],assignPublicIp=ENABLED}"
    
    aws ecs create-service `
      --cluster $ECS_CLUSTER_NAME `
      --service-name $ECS_SERVICE_NAME `
      --task-definition $ECS_TASK_FAMILY `
      --desired-count 1 `
      --launch-type FARGATE `
      --network-configuration $networkConfig `
      --region $AWS_REGION
      
    Write-Host "ECS 서비스가 생성되었습니다!" -ForegroundColor Green
} else {
    Write-Host "이미 ECS 서비스 '$ECS_SERVICE_NAME'가 구동 중입니다." -ForegroundColor Yellow
}

Write-Host "`n========== 리소스 구성 완료 ==========" -ForegroundColor Green
Write-Host "이제 GitHub Actions Secrets를 세팅하고 코드를 push하면 자동 배포가 활성화됩니다." -ForegroundColor Green
