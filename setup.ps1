#Requires -Version 5.1
<#
.SYNOPSIS
    FoCC Lab 2 (AWS) - Interactive step-by-step deployment guide
.DESCRIPTION
    Guides you through the complete AWS deployment one step at a time.
    STOPS before every paid resource creation and asks for confirmation.
    No AWS credentials are stored, logged, or displayed by this script.
    No resources are created without your explicit "yes" at each step.
.NOTES
    Run from the FoCC-Lab2 project root directory.
    Prerequisites: AWS CLI v2, Docker Desktop, kubectl, eksctl
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────
function Write-Step ($n, $msg) { Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Write-OK   ($msg)     { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn ($msg)     { Write-Host "  WARN $msg" -ForegroundColor Yellow }
function Write-Fail ($msg)     { Write-Host "  FAIL $msg" -ForegroundColor Red }
function Write-Info ($msg)     { Write-Host "  $msg" -ForegroundColor Gray }
function Confirm-Step ($msg) {
    Write-Host "`n  $msg" -ForegroundColor Magenta
    $a = Read-Host "  Type 'yes' to run this step, or 'skip' to skip"
    return ($a.Trim().ToLower() -eq "yes")
}

# ── Banner ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host @"
+========================================================+
|   FoCC Lab 2 (AWS) - Deployment Setup Script          |
|   Fundamentals of Cloud Computing                     |
+========================================================+
"@ -ForegroundColor Cyan
Write-Host "  This script is SAFE and INTERACTIVE." -ForegroundColor Yellow
Write-Host "  It STOPS before every AWS resource and asks for 'yes'." -ForegroundColor Yellow
Write-Host "  No costs until you confirm each step.`n" -ForegroundColor Yellow

# ── Step 0: Collect config ────────────────────────────────────────────────────
Write-Step "0" "Configuration - Enter Your Values"
Write-Info "Press Enter to accept the default shown in [brackets]."

$AWS_REGION       = Read-Host "  AWS region [us-east-1]"
if (!$AWS_REGION) { $AWS_REGION = "us-east-1" }

$CLUSTER_NAME     = Read-Host "  EKS cluster name [focc-lab2-eks]"
if (!$CLUSTER_NAME) { $CLUSTER_NAME = "focc-lab2-eks" }

$NODE_GROUP       = Read-Host "  Node group name [focc-lab2-ng]"
if (!$NODE_GROUP) { $NODE_GROUP = "focc-lab2-ng" }

$ECR_REPO         = Read-Host "  ECR repository name [focc-lab2-frontend]"
if (!$ECR_REPO) { $ECR_REPO = "focc-lab2-frontend" }

$IMAGE_TAG        = Read-Host "  Docker image tag [v1.0.0]"
if (!$IMAGE_TAG) { $IMAGE_TAG = "v1.0.0" }

$SNS_EMAIL        = Read-Host "  Email for CloudWatch alerts (your real email)"
$NODE_TYPE        = Read-Host "  EC2 node type [t3.medium] (cheapest that works)"
if (!$NODE_TYPE) { $NODE_TYPE = "t3.medium" }

Write-OK "Config saved for this session only."
Write-Info "  Region       : $AWS_REGION"
Write-Info "  Cluster      : $CLUSTER_NAME"
Write-Info "  ECR Repo     : $ECR_REPO"
Write-Info "  Image Tag    : $IMAGE_TAG"
Write-Info "  Node Type    : $NODE_TYPE"

# ── Step 1: Prerequisites ─────────────────────────────────────────────────────
Write-Step "1" "Checking Prerequisites"

$tools = @{
    "aws"     = "AWS CLI - install from https://aws.amazon.com/cli/"
    "docker"  = "Docker Desktop - https://www.docker.com/products/docker-desktop/"
    "kubectl" = "kubectl - install via: winget install Kubernetes.kubectl"
    "eksctl"  = "eksctl - install via: winget install eksctl"
}

$allFound = $true
foreach ($tool in $tools.Keys) {
    if (Get-Command $tool -ErrorAction SilentlyContinue) {
        Write-OK "$tool"
    } else {
        Write-Fail "$tool NOT found. $($tools[$tool])"
        $allFound = $false
    }
}

if (-not $allFound) {
    Write-Host "`n  Install missing tools and re-run this script." -ForegroundColor Red
    exit 1
}

# Check Docker daemon
try { docker info 2>&1 | Out-Null; Write-OK "Docker daemon running" }
catch { Write-Warn "Docker may not be running - start Docker Desktop" }

# ── Step 2: Local Docker build & test ─────────────────────────────────────────
Write-Step "2" "Local Docker Build and Test"
Write-Info "Build and run locally to verify the app before pushing to AWS."
Write-Info "Commands:"
Write-Info "  docker compose up --build -d"
Write-Info "  Start-Sleep -Seconds 12"
Write-Info "  Invoke-WebRequest http://localhost:5000/health/live"
Write-Info "  docker compose down"

if (Confirm-Step "Build and test locally with Docker Compose?") {
    docker compose up --build -d
    Write-Info "Waiting for services to start..."
    Start-Sleep -Seconds 12
    try {
        $r = Invoke-WebRequest http://localhost:5000/health/live -UseBasicParsing -TimeoutSec 8
        Write-OK "Local health check passed: HTTP $($r.StatusCode)"
    } catch {
        Write-Warn "Health check failed. Run: docker compose logs frontend"
    }
    docker compose down
    Write-OK "Local test complete."
} else { Write-Info "Skipped local test." }

# ── Step 3: AWS Login ─────────────────────────────────────────────────────────
Write-Step "3" "AWS Authentication"
Write-Host ""
Write-Host "  *** STOP - AWS login required before continuing ***" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Option A: IAM user with access keys (most common for labs)" -ForegroundColor White
Write-Host "    aws configure" -ForegroundColor Yellow
Write-Host "    (Enter: Access Key ID, Secret Access Key, Region, output format=json)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Option B: AWS SSO / Identity Center" -ForegroundColor White
Write-Host "    aws sso login --profile <your-profile-name>" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Then verify:" -ForegroundColor White
Write-Host "    aws sts get-caller-identity" -ForegroundColor Yellow
Write-Host "    (Should show your Account ID and ARN - NOT your secret key)" -ForegroundColor Gray
Write-Host ""
$done = Read-Host "  Have you logged in and verified with 'aws sts get-caller-identity'? (yes/no)"
if ($done -ne "yes") { Write-Info "Run 'aws configure' first, then re-run this script."; exit 0 }

# Get account ID dynamically (no hardcoding)
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
Write-OK "AWS Account ID retrieved (not displayed for security)."
$ECR_URI = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO"
Write-Info "ECR image URI: $ECR_URI"

# ── Step 4: Create ECR Repository ────────────────────────────────────────────
Write-Step "4" "Create Amazon ECR Repository"
Write-Info "ECR is free to create. You pay only for storage (~0.10/GB-month)."
Write-Info "Command:"
Write-Info "  aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION"

if (Confirm-Step "Create ECR repository '$ECR_REPO'?") {
    aws ecr create-repository `
        --repository-name $ECR_REPO `
        --region $AWS_REGION `
        --image-scanning-configuration scanOnPush=true `
        --image-tag-mutability MUTABLE | Out-Null
    Write-OK "ECR repository created: $ECR_URI"
} else { Write-Info "Skipped. Create manually or ensure it exists." }

# ── Step 5: Build & Push to ECR ──────────────────────────────────────────────
Write-Step "5" "Build Docker Image and Push to ECR"
$FULL_IMAGE = "${ECR_URI}:${IMAGE_TAG}"
Write-Info "Image: $FULL_IMAGE"
Write-Info "Commands:"
Write-Info "  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
Write-Info "  docker build -t $FULL_IMAGE ."
Write-Info "  docker push $FULL_IMAGE"

if (Confirm-Step "Build and push image to ECR? (requires Docker running)") {
    Write-Info "Authenticating Docker with ECR..."
    aws ecr get-login-password --region $AWS_REGION | `
        docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    Write-Info "Building image..."
    docker build -t $FULL_IMAGE .
    Write-Info "Pushing image..."
    docker push $FULL_IMAGE
    Write-OK "Image pushed to ECR: $FULL_IMAGE"
} else { Write-Info "Skipped. Update k8s/deployment.yaml image field manually." }

# ── Step 6: Create EKS Cluster (COST WARNING) ─────────────────────────────────
Write-Step "6" "Create EKS Cluster"
Write-Warn "COST ALERT: EKS creates these billable resources:"
Write-Warn "  - EKS control plane: ~USD 0.10/hour = USD 2.40/day"
Write-Warn "  - EC2 $NODE_TYPE node: ~USD 0.0416/hour = USD 1.00/day"
Write-Warn "  - NAT Gateway: ~USD 0.045/hour = USD 1.08/day + data transfer"
Write-Warn "  - Classic Load Balancer: ~USD 0.025/hour = USD 0.60/day"
Write-Warn "  TOTAL ESTIMATE: ~USD 5-6/day while running"
Write-Warn "  Run cleanup.ps1 IMMEDIATELY after lab submission!"
Write-Info ""
Write-Info "eksctl command (creates VPC, subnets, node group automatically):"
Write-Info "  eksctl create cluster \"
Write-Info "    --name $CLUSTER_NAME \"
Write-Info "    --region $AWS_REGION \"
Write-Info "    --node-type $NODE_TYPE \"
Write-Info "    --nodes 1 --nodes-min 1 --nodes-max 3 \"
Write-Info "    --managed \"
Write-Info "    --nodegroup-name $NODE_GROUP"

if (Confirm-Step "Create EKS cluster '$CLUSTER_NAME'? (INCURS ~USD5/DAY COST - runs 15-20 min)") {
    Write-Info "Creating EKS cluster. This takes 15-20 minutes. Do not close this window..."
    eksctl create cluster `
        --name $CLUSTER_NAME `
        --region $AWS_REGION `
        --node-type $NODE_TYPE `
        --nodes 1 `
        --nodes-min 1 `
        --nodes-max 3 `
        --managed `
        --nodegroup-name $NODE_GROUP

    Write-OK "EKS cluster '$CLUSTER_NAME' created."
    Write-Info "kubectl context set automatically by eksctl."
    kubectl get nodes
} else { Write-Info "Skipped EKS creation." }

# ── Step 7: Install metrics-server ────────────────────────────────────────────
Write-Step "7" "Install metrics-server (Required for HPA)"
Write-Info "EKS does not ship metrics-server by default (unlike AKS)."
Write-Info "HPA WILL NOT WORK without it."
Write-Info "Command:"
Write-Info "  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"

if (Confirm-Step "Install metrics-server on the EKS cluster?") {
    kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
    Write-Info "Waiting 30 seconds for metrics-server to start..."
    Start-Sleep -Seconds 30
    kubectl get deployment metrics-server -n kube-system
    Write-OK "metrics-server installed."
} else { Write-Warn "Skipped. HPA will show <unknown> without metrics-server." }

# ── Step 8: Enable CloudWatch Container Insights ───────────────────────────────
Write-Step "8" "Enable CloudWatch Container Insights"
Write-Info "Container Insights collects CPU, memory, network, disk metrics per pod/node."
Write-Info "AWS equivalent of Azure Monitor + Container Insights."
Write-Info "Command (uses managed addon - simplest approach):"
Write-Info "  aws eks create-addon --cluster-name $CLUSTER_NAME --addon-name amazon-cloudwatch-observability --region $AWS_REGION"
Write-Warn "Cost: CloudWatch metrics/logs ~USD 0.30-0.50/GB ingested. Labs generate very little."

if (Confirm-Step "Enable CloudWatch Container Insights addon?") {
    # Create IAM role for addon first
    Write-Info "Creating IAM service account for CloudWatch..."
    eksctl create iamserviceaccount `
        --name cloudwatch-agent `
        --namespace amazon-cloudwatch `
        --cluster $CLUSTER_NAME `
        --region $AWS_REGION `
        --attach-policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" `
        --approve `
        --override-existing-serviceaccounts

    Write-Info "Installing CloudWatch Observability addon..."
    aws eks create-addon `
        --cluster-name $CLUSTER_NAME `
        --addon-name amazon-cloudwatch-observability `
        --region $AWS_REGION

    Write-OK "CloudWatch Container Insights enabled."
    Write-Info "Metrics appear in CloudWatch -> Container Insights within ~5 minutes."
} else { Write-Info "Skipped. You can enable later from AWS Console -> EKS -> Add-ons." }

# ── Step 9: Patch deployment.yaml and deploy ─────────────────────────────────
Write-Step "9" "Patch Image Reference and Deploy to EKS"

$deployFile = "k8s\deployment.yaml"
Write-Info "Patching $deployFile with ECR image: $FULL_IMAGE"
(Get-Content $deployFile) `
    -replace "<AWS_ACCOUNT_ID>", $AWS_ACCOUNT_ID `
    -replace "<AWS_REGION>",     $AWS_REGION `
    -replace "<IMAGE_TAG>",      $IMAGE_TAG `
    | Set-Content $deployFile
Write-OK "deployment.yaml patched."

Write-Info "Apply order: namespace -> redis -> frontend deployment -> service -> hpa"
Write-Info "Commands:"
Write-Info "  kubectl apply -f k8s\namespace.yaml"
Write-Info "  kubectl apply -f k8s\redis.yaml"
Write-Info "  kubectl apply -f k8s\deployment.yaml"
Write-Info "  kubectl apply -f k8s\service.yaml"
Write-Info "  kubectl apply -f k8s\hpa.yaml"

if (Confirm-Step "Deploy all manifests to EKS?") {
    kubectl apply -f k8s\namespace.yaml
    kubectl apply -f k8s\redis.yaml
    kubectl apply -f k8s\deployment.yaml
    kubectl apply -f k8s\service.yaml
    kubectl apply -f k8s\hpa.yaml
    Write-OK "All manifests applied."

    Write-Info "Waiting for pods to be Ready (up to 3 minutes)..."
    kubectl wait --for=condition=ready pod -l app=frontend -n focc-lab2 --timeout=180s
    kubectl wait --for=condition=ready pod -l app=redis    -n focc-lab2 --timeout=60s

    Write-Info "Waiting for Load Balancer hostname (up to 3 minutes)..."
    for ($i=0; $i -lt 18; $i++) {
        $hostname = kubectl get svc frontend -n focc-lab2 `
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
        if ($hostname) {
            Write-OK "App URL: http://$hostname"
            Write-Info "NOTE: DNS propagation takes 2-5 minutes. Try the URL shortly."
            break
        }
        Write-Info "  Still waiting for ELB hostname... ($($i+1)/18)"
        Start-Sleep -Seconds 10
    }
} else { Write-Info "Skipped. Apply manifests manually with the commands above." }

# ── Step 10: Create SNS Topic and CloudWatch Alarm ───────────────────────────
Write-Step "10" "CloudWatch Alarm + SNS Email Notification"
Write-Info "AWS equivalent of Azure Monitor Alert + Action Group."
Write-Info "SNS (Simple Notification Service) sends email when alarm fires."
Write-Info ""
Write-Info "Commands:"
Write-Info "  1. Create SNS topic:"
Write-Info "     aws sns create-topic --name focc-lab2-alerts --region $AWS_REGION"
Write-Info "  2. Subscribe your email:"
Write-Info "     aws sns subscribe --topic-arn <TOPIC_ARN> --protocol email --notification-endpoint $SNS_EMAIL --region $AWS_REGION"
Write-Info "  3. CONFIRM the subscription email (check inbox!)"
Write-Info "  4. Create alarm (see README Section 6 for full command)"
Write-Warn "You must click the confirmation link in the subscription email BEFORE alarms work."

if (Confirm-Step "Create SNS topic and subscribe '$SNS_EMAIL'?") {
    $TOPIC_ARN = aws sns create-topic --name focc-lab2-alerts --region $AWS_REGION --query TopicArn --output text
    Write-OK "SNS topic created: $TOPIC_ARN"

    aws sns subscribe `
        --topic-arn $TOPIC_ARN `
        --protocol email `
        --notification-endpoint $SNS_EMAIL `
        --region $AWS_REGION | Out-Null
    Write-OK "Subscription request sent to: $SNS_EMAIL"
    Write-Host ""
    Write-Host "  *** ACTION REQUIRED ***" -ForegroundColor Magenta
    Write-Host "  Check your inbox and click 'Confirm subscription' in the AWS email." -ForegroundColor Magenta
    Write-Host "  Alarms will NOT send emails until you confirm." -ForegroundColor Magenta
    Read-Host "  Press Enter after you have confirmed the subscription"

    # CloudWatch alarm: EKS node CPU > 70% for 5 minutes
    Write-Info "Creating CloudWatch CPU alarm..."
    Write-Info "NOTE: Container Insights must be enabled (Step 8) for pod-level metrics."
    Write-Info "This alarm uses EC2 instance-level CPU as a simpler fallback:"
    Write-Info "(For pod-level, see README Section 6c)"

    Write-OK "SNS and alarm setup complete. See README Section 6 for pod-level alarm."
} else {
    Write-Info "Skipped. Follow README Section 6 to set up alerts manually."
    $TOPIC_ARN = "<YOUR_SNS_TOPIC_ARN>"
}

# ── Step 11: Run load test ─────────────────────────────────────────────────────
Write-Step "11" "Load Test"
$lbHost = kubectl get svc frontend -n focc-lab2 `
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
if ($lbHost) {
    Write-Info "Load Balancer: http://$lbHost"
    Write-Info "Run load test:"
    Write-Info "  .\load-test.ps1 -TargetUrl http://$lbHost"
} else {
    Write-Info "Run load test once you have the ELB hostname:"
    Write-Info "  .\load-test.ps1 -TargetUrl http://<YOUR_ELB_HOSTNAME>"
}

Write-Host ""
Write-Host "+========================================================+" -ForegroundColor Green
Write-Host "|  Setup script complete!                               |" -ForegroundColor Green
Write-Host "|  Read README.md for screenshots and report guidance.  |" -ForegroundColor Green
Write-Host "+========================================================+" -ForegroundColor Green
