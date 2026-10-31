# FoCC Lab 2 (AWS) - Cloud Visit Counter
## Fundamentals of Cloud Computing | Flask + Redis on Amazon EKS

[![AWS](https://img.shields.io/badge/AWS-EKS%20%7C%20ECR%20%7C%20CloudWatch-FF9900?logo=amazonaws)](setup.ps1)
[![Docker](https://img.shields.io/badge/Docker-multi--stage-2496ED?logo=docker)](Dockerfile)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-326CE5?logo=kubernetes)](k8s/)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)](requirements.txt)

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Project File Structure](#2-project-file-structure)
3. [Azure-to-AWS Service Mapping](#3-azure-to-aws-service-mapping)
4. [Local Development (Docker Compose)](#4-local-development-docker-compose)
5. [AWS Deployment (Step by Step)](#5-aws-deployment-step-by-step)
6. [CloudWatch Monitoring and Alerts](#6-cloudwatch-monitoring-and-alerts)
7. [Load Test](#7-load-test)
8. [Kubernetes Reference Commands](#8-kubernetes-reference-commands)
9. [Cost Awareness](#9-cost-awareness)
10. [Troubleshooting](#10-troubleshooting)
11. [Screenshot Checklist](#11-screenshot-checklist)
12. [Cleanup (IMPORTANT)](#12-cleanup-important)
13. [Submission Checklist](#13-submission-checklist)

---

## 1. Architecture

```
           Internet
              |
        HTTP port 80
              |
              v
  +---------------------------+
  | AWS Classic Load Balancer |   <-- created automatically by EKS
  |  *.us-east-1.elb.amazonaws.com |
  +---------------------------+
              |
         port 5000
              |
              v
  +===========================================================+
  ||             Amazon EKS Cluster (focc-lab2-eks)         ||
  ||                                                         ||
  ||   Namespace: focc-lab2                                  ||
  ||                                                         ||
  ||   +-----------+  +-----------+  +-----------+          ||
  ||   | frontend  |  | frontend  |  | frontend  |  ...     ||
  ||   |  Pod 1    |  |  Pod 2    |  |  Pod 3-5  |          ||
  ||   | Flask +   |  | (HPA      |  | (HPA auto)|          ||
  ||   | Gunicorn  |  |  scaled)  |  |           |          ||
  ||   +-----------+  +-----------+  +-----------+          ||
  ||          |              |              |                ||
  ||          +-------+------+--------------+               ||
  ||                  |                                      ||
  ||            ClusterIP:6379                               ||
  ||                  v                                      ||
  ||           +------------+                                ||
  ||           | Redis Pod  |  (single, no external IP)     ||
  ||           | redis:7.2  |                                ||
  ||           +------------+                                ||
  ||                  |                                      ||
  ||             emptyDir volume                             ||
  ||                                                         ||
  ||  HPA: 1-5 replicas, scale at 50% of 100m CPU           ||
  +===========================================================+
              |
  +===========================================================+
  ||          AWS Monitoring Stack                           ||
  ||                                                         ||
  ||  CloudWatch Agent DS  ->  CloudWatch Log Groups         ||
  ||  Fluent Bit DS        ->  /aws/containerinsights/...    ||
  ||                           CloudWatch Container Insights  ||
  ||                           (CPU/memory/network graphs)   ||
  ||                                |                        ||
  ||                        CloudWatch Alarms                ||
  ||                                |                        ||
  ||                         SNS Topic                       ||
  ||                                |                        ||
  ||                      Email Notification                 ||
  +===========================================================+
              |
  +===========================================================+
  ||           Amazon ECR                                    ||
  ||  focc-lab2-frontend:v1.0.0  (Docker image store)       ||
  +===========================================================+
```

---

## 2. Project File Structure

```
FoCC-Lab2/
|-- app.py                          # Flask app (/, /health/live, /health/ready, /metrics, /api/stats)
|-- requirements.txt                # flask==3.0.3, redis==5.0.7, gunicorn==22.0.0
|-- Dockerfile                      # Multi-stage: builder (gcc+pip) + runtime (slim, non-root)
|-- docker-compose.yml              # Local two-tier dev: Flask + Redis
|-- .dockerignore                   # Excludes k8s/, scripts, venv, IDE files from image
|
|-- k8s/
|   |-- namespace.yaml              # focc-lab2 namespace
|   |-- redis.yaml                  # Redis Deployment + ClusterIP Service (combined)
|   |-- deployment.yaml             # Frontend Flask Deployment (100m CPU, 128Mi mem, probes)
|   |-- service.yaml                # Frontend LoadBalancer Service (port 80 -> 5000)
|   `-- hpa.yaml                    # HPA: 1-5 replicas, 50% CPU target
|
|-- aws/
|   `-- cloudwatch-agent-config.json  # Reference CloudWatch agent config
|
|-- setup.ps1                       # Interactive AWS deployment guide (11 steps)
|-- load-test.ps1                   # 3-min parallel load test (pure PowerShell)
|-- cleanup.ps1                     # Safe AWS resource cleanup with confirmation
|
|-- reports/
|   `-- lab2-report-template.md    # Report with 5 reflection questions + screenshot list
|
`-- README.md                       # This file
```

---

## 3. Azure-to-AWS Service Mapping

If your lab assignment references Azure, here are the direct equivalents used:

| Azure Service | AWS Equivalent | How Used in This Lab |
|---|---|---|
| Azure Container Registry | **Amazon ECR** | Stores the Flask Docker image |
| Azure Kubernetes Service | **Amazon EKS** | Runs the Kubernetes cluster |
| Azure Monitor | **Amazon CloudWatch** | Metrics, alarms, dashboards |
| Log Analytics Workspace | **CloudWatch Log Groups** | Centralised pod/node logs |
| Container Insights (Azure) | **CloudWatch Container Insights** | Pod CPU/memory/network graphs |
| Azure Monitor Alert Rules | **CloudWatch Alarms** | CPU threshold alerting |
| Action Groups (email) | **Amazon SNS** | Email notification on alarm |
| Azure Load Balancer | **AWS Classic/Network LB** | Public traffic ingress |
| Azure RBAC | **AWS IAM** | Access control |
| az CLI | **aws CLI + eksctl** | Resource management |

---

## 4. Local Development (Docker Compose)

Test the app locally **before** spending money on AWS.

### Prerequisites (local only)
- [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/)
- PowerShell 5.1+

### Commands

```powershell
# Navigate to project root
cd FoCC-Lab2

# Build and start the two-tier stack
docker compose up --build

# In another terminal - verify it works
Invoke-WebRequest http://localhost:5000/health/live -UseBasicParsing
# Expected: {"pod":"...","status":"ok"}

Invoke-WebRequest http://localhost:5000/api/stats -UseBasicParsing
# Expected JSON with request counts and redis_visit_count

# Open in browser
Start-Process http://localhost:5000

# View metrics (Prometheus format)
Start-Process http://localhost:5000/metrics

# View logs
docker compose logs frontend
docker compose logs redis

# Stop
docker compose down
# Stop and clear Redis data (resets visit counter)
docker compose down -v
```

### Application Endpoints

| Endpoint | Returns | Purpose |
|---|---|---|
| `GET /` | HTML page | Visit counter UI (increments Redis) |
| `GET /health/live` | JSON 200 | Kubernetes liveness probe |
| `GET /health/ready` | JSON 200 or 503 | Readiness probe (503 if Redis down) |
| `GET /metrics` | Prometheus text | HTTP request count, latency histogram, redis count |
| `GET /api/stats` | JSON | Quick stats for testing |

---

## 5. AWS Deployment (Step by Step)

> **Quick start**: run `.\setup.ps1` for an interactive guide. Or follow below manually.

### 5a. Install Required Tools

```powershell
# 1. AWS CLI v2
winget install Amazon.AWSCLI
# Verify:
aws --version   # Should show aws-cli/2.x.x

# 2. eksctl (creates EKS clusters simply)
winget install eksctl
# OR download from: https://eksctl.io/installation/
eksctl version

# 3. kubectl
winget install Kubernetes.kubectl
kubectl version --client

# 4. Docker Desktop
# Download from: https://www.docker.com/products/docker-desktop/
docker --version
```

### 5b. Configure AWS CLI

```powershell
# Configure with your IAM user credentials
# (Get these from AWS Console -> IAM -> Users -> your user -> Security credentials)
aws configure
# Prompts:
#   AWS Access Key ID:     [paste your key - never share this]
#   AWS Secret Access Key: [paste your secret - never share this]
#   Default region:        us-east-1  (or your preferred region)
#   Default output format: json

# Verify login (shows Account ID and ARN - safe to show in screenshots)
aws sts get-caller-identity
```

### 5c. Required IAM Permissions

Your IAM user needs these AWS managed policies attached (or AdministratorAccess for a lab):
- `AmazonEKSClusterPolicy`
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryFullAccess`
- `CloudWatchFullAccess`
- `AmazonSNSFullAccess`
- `IAMFullAccess` (needed by eksctl to create node IAM roles)

To attach in Console: IAM -> Users -> [your user] -> Add permissions -> Attach policies

### 5d. Create ECR Repository

```powershell
$AWS_REGION = "us-east-1"    # change to your region
$ECR_REPO   = "focc-lab2-frontend"

aws ecr create-repository `
    --repository-name $ECR_REPO `
    --region $AWS_REGION `
    --image-scanning-configuration scanOnPush=true

# Get your account ID (12 digits) - safe to use in commands, don't share publicly
$AWS_ACCOUNT_ID = aws sts get-caller-identity --query Account --output text
$ECR_URI = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO"
Write-Host "ECR URI: $ECR_URI"
```

### 5e. Build and Push Docker Image

```powershell
$IMAGE_TAG  = "v1.0.0"
$FULL_IMAGE = "${ECR_URI}:${IMAGE_TAG}"

# Authenticate Docker with ECR (token expires in 12 hours)
aws ecr get-login-password --region $AWS_REGION | `
    docker login --username AWS --password-stdin `
    "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Build the multi-stage image
docker build -t $FULL_IMAGE .

# Push to ECR
docker push $FULL_IMAGE

# Verify it's there
aws ecr list-images --repository-name $ECR_REPO --region $AWS_REGION
```

### 5f. Create EKS Cluster

> **COST WARNING**: See Section 9 before proceeding. EKS costs ~USD 5/day.

```powershell
$CLUSTER_NAME = "focc-lab2-eks"
$NODE_GROUP   = "focc-lab2-ng"
$NODE_TYPE    = "t3.medium"

# This takes 15-20 minutes and creates: VPC, subnets, IGW, NAT Gateway,
# EKS control plane, EC2 node, security groups. eksctl handles all of it.
eksctl create cluster `
    --name $CLUSTER_NAME `
    --region $AWS_REGION `
    --node-type $NODE_TYPE `
    --nodes 1 `
    --nodes-min 1 `
    --nodes-max 3 `
    --managed `
    --nodegroup-name $NODE_GROUP

# Verify (eksctl sets kubectl context automatically)
kubectl get nodes
# Should show: Ready
```

### 5g. Install metrics-server (REQUIRED for HPA)

Unlike Azure AKS, EKS does NOT include metrics-server by default.
HPA will show `<unknown>` for CPU without this.

```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait 30 seconds, then verify
Start-Sleep -Seconds 30
kubectl get deployment metrics-server -n kube-system
kubectl top nodes   # should return CPU/memory data
```

### 5h. Update Image Reference in deployment.yaml

```powershell
# Patch the placeholder values in deployment.yaml
$deployFile = "k8s\deployment.yaml"
(Get-Content $deployFile) `
    -replace "<AWS_ACCOUNT_ID>", $AWS_ACCOUNT_ID `
    -replace "<AWS_REGION>",     $AWS_REGION `
    -replace "<IMAGE_TAG>",      $IMAGE_TAG `
    | Set-Content $deployFile

# Verify
Select-String "image:" $deployFile
```

### 5i. Deploy to EKS

```powershell
# Apply in order (namespace first, then workloads)
kubectl apply -f k8s\namespace.yaml
kubectl apply -f k8s\redis.yaml
kubectl apply -f k8s\deployment.yaml
kubectl apply -f k8s\service.yaml
kubectl apply -f k8s\hpa.yaml

# Watch pods start
kubectl get pods -n focc-lab2 -w

# Wait for pods to be Ready
kubectl wait --for=condition=ready pod -l app=frontend -n focc-lab2 --timeout=180s
kubectl wait --for=condition=ready pod -l app=redis    -n focc-lab2 --timeout=60s

# Get Load Balancer hostname (takes 2-5 min for ELB to provision)
kubectl get svc frontend -n focc-lab2 -w
# Look for EXTERNAL-IP column to change from <pending> to *.elb.amazonaws.com

# Save the hostname
$ELB_HOST = kubectl get svc frontend -n focc-lab2 `
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Write-Host "App URL: http://$ELB_HOST"
Start-Process "http://$ELB_HOST"
```

---

## 6. CloudWatch Monitoring and Alerts

### 6a. Enable CloudWatch Container Insights

```powershell
# Create IAM service account for CloudWatch agent
eksctl create iamserviceaccount `
    --name cloudwatch-agent `
    --namespace amazon-cloudwatch `
    --cluster $CLUSTER_NAME `
    --region $AWS_REGION `
    --attach-policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" `
    --approve `
    --override-existing-serviceaccounts

# Install the Container Insights addon
aws eks create-addon `
    --cluster-name $CLUSTER_NAME `
    --addon-name amazon-cloudwatch-observability `
    --region $AWS_REGION

# Wait for addon to be active (~2 minutes)
aws eks describe-addon `
    --cluster-name $CLUSTER_NAME `
    --addon-name amazon-cloudwatch-observability `
    --region $AWS_REGION `
    --query addon.status
```

### 6b. View Metrics in CloudWatch Console

1. Open [AWS Console](https://console.aws.amazon.com) -> **CloudWatch**
2. Left sidebar -> **Container Insights** -> **Performance monitoring**
3. Dropdown: Select **EKS Pods**, cluster: `focc-lab2-eks`, namespace: `focc-lab2`
4. Graphs available: **CPU utilisation**, **Memory utilisation**, **Network I/O**
5. During/after load test, set time range to **Last 30 minutes** to see CPU spike

### 6c. Query Logs in CloudWatch Logs Insights

```
# Open: CloudWatch -> Logs -> Logs Insights
# Select log group: /aws/containerinsights/focc-lab2-eks/application

# Query 1: All frontend logs, newest first
fields @timestamp, @message
| filter kubernetes.namespace_name = "focc-lab2"
| filter kubernetes.container_name = "frontend"
| sort @timestamp desc
| limit 50

# Query 2: Count HTTP requests per minute
fields @timestamp, @message
| filter @message like /GET \//
| stats count() as requests by bin(1m)
| sort @timestamp asc

# Query 3: Errors only
fields @timestamp, @message
| filter kubernetes.namespace_name = "focc-lab2"
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

### 6d. Create SNS Topic and Subscribe Email

```powershell
$SNS_EMAIL = "your-real-email@example.com"  # replace with your email

# Create SNS topic
$TOPIC_ARN = aws sns create-topic `
    --name focc-lab2-alerts `
    --region $AWS_REGION `
    --query TopicArn `
    --output text
Write-Host "Topic ARN: $TOPIC_ARN"

# Subscribe your email
aws sns subscribe `
    --topic-arn $TOPIC_ARN `
    --protocol email `
    --notification-endpoint $SNS_EMAIL `
    --region $AWS_REGION

Write-Host ""
Write-Host "ACTION REQUIRED: Check $SNS_EMAIL and click 'Confirm subscription'!" -ForegroundColor Red
Write-Host "Alerts will NOT work until you confirm." -ForegroundColor Red
```

### 6e. Create CloudWatch Alarm

For Container Insights pod CPU metric (most accurate for this lab):

```powershell
# Note: Container Insights must be active for ~5 min before metrics appear.
# Alarm: average pod CPU > 70% for 2 periods of 5 minutes each.

aws cloudwatch put-metric-alarm `
    --alarm-name "focc-lab2-frontend-cpu-high" `
    --alarm-description "Frontend pod CPU above 70% - possible HPA scaling needed" `
    --namespace "ContainerInsights" `
    --metric-name "pod_cpu_utilization" `
    --dimensions `
        Name=ClusterName,Value=$CLUSTER_NAME `
        Name=Namespace,Value=focc-lab2 `
        Name=PodName,Value=frontend `
    --statistic Average `
    --period 300 `
    --evaluation-periods 2 `
    --threshold 70 `
    --comparison-operator GreaterThanOrEqualToThreshold `
    --alarm-actions $TOPIC_ARN `
    --ok-actions    $TOPIC_ARN `
    --region $AWS_REGION

Write-Host "Alarm created. View in CloudWatch -> Alarms."
```

### 6f. HTTP Request Count and P95 Latency Graphs

The app's `/metrics` endpoint exposes Prometheus-format metrics. To visualise these in CloudWatch:

**Option A (Simple): View from /api/stats during load test**
```powershell
# Poll the stats endpoint during load test
while ($true) {
    $s = Invoke-WebRequest "http://$ELB_HOST/api/stats" -UseBasicParsing | ConvertFrom-Json
    Write-Host "$(Get-Date -Format HH:mm:ss) | Requests: $($s.http_requests_total) | Avg latency: $($s.avg_latency_ms)ms"
    Start-Sleep -Seconds 5
}
```

**Option B (Advanced): CloudWatch Embedded Metric Format**
The app emits Prometheus metrics at `/metrics`. For full CloudWatch integration
with custom dashboards, you can scrape these with the CloudWatch Agent using
the Prometheus configuration. See:
https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-PrometheusEC2.html

For the lab scope, the Container Insights pod CPU graph + load test terminal output
is sufficient to demonstrate P95 latency in your report.

---

## 7. Load Test

> **Prerequisite**: App must be deployed on EKS with an ELB hostname.

```powershell
# Get the hostname
$ELB_HOST = kubectl get svc frontend -n focc-lab2 `
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
Write-Host "Target: http://$ELB_HOST"

# Run the 3-minute load test
.\load-test.ps1 -TargetUrl "http://$ELB_HOST"

# Increase concurrency for more CPU load (if HPA isn't triggering)
.\load-test.ps1 -TargetUrl "http://$ELB_HOST" -Concurrency 20
```

### Monitor During Load Test (separate PowerShell window)

```powershell
# Watch HPA in real-time
kubectl get hpa frontend-hpa -n focc-lab2 -w

# Watch pod count change
kubectl get pods -n focc-lab2 -w

# Check current resource usage
kubectl top pods -n focc-lab2
kubectl top nodes
```

### Expected Load Test Observations

| Time | Expected Behaviour |
|---|---|
| 0-30s | 1 replica, low CPU |
| 30-60s | CPU rises above 50m (50% of 100m request) |
| 60-90s | HPA creates pod 2 (stabilization: 30s) |
| 90-180s | Scales to 3-5 pods depending on load |
| 180s | Load test ends, CPU drops |
| 180-300s | HPA stabilization (120s window) before scaling down |
| 300s+ | Returns to 1 replica |

---

## 8. Kubernetes Reference Commands

```powershell
# ── Status ──────────────────────────────────────────────────────────────────
kubectl get all -n focc-lab2
kubectl get pods -n focc-lab2 -o wide
kubectl get svc  -n focc-lab2
kubectl get hpa  -n focc-lab2

# ── Logs ────────────────────────────────────────────────────────────────────
kubectl logs -l app=frontend -n focc-lab2 --tail=50
kubectl logs -l app=redis    -n focc-lab2 --tail=20
kubectl logs <pod-name>      -n focc-lab2 --previous   # crashed pod

# ── Describe (events, config, errors) ───────────────────────────────────────
kubectl describe pod        -l app=frontend -n focc-lab2
kubectl describe hpa        frontend-hpa    -n focc-lab2
kubectl describe svc        frontend        -n focc-lab2

# ── Resource usage ──────────────────────────────────────────────────────────
kubectl top pods  -n focc-lab2
kubectl top nodes

# ── Exec into pod ───────────────────────────────────────────────────────────
kubectl exec -it <pod-name> -n focc-lab2 -- /bin/sh

# ── Manual scaling (for testing) ────────────────────────────────────────────
kubectl scale deployment frontend --replicas=3 -n focc-lab2

# ── Re-apply after changes ──────────────────────────────────────────────────
kubectl apply -f k8s\

# ── Delete all lab resources (keep cluster) ─────────────────────────────────
kubectl delete -f k8s\
```

---

## 9. Cost Awareness

> **Read this before creating AWS resources!**

| Resource | When Charged | Estimated Cost |
|---|---|---|
| EKS Control Plane | Per hour the cluster exists | ~USD 0.10/hr = USD 2.40/day |
| EC2 t3.medium node | Per hour the node runs | ~USD 0.0416/hr = USD 1.00/day |
| NAT Gateway | Per hour + per GB data | ~USD 0.045/hr = USD 1.08/day |
| Classic Load Balancer | Per hour + per GB | ~USD 0.025/hr = USD 0.60/day |
| ECR | Per GB stored | ~USD 0.10/GB-month (minimal) |
| CloudWatch | Per GB logs ingested | ~USD 0.50/GB (lab = very low) |
| CloudWatch Alarms | Per alarm per month | USD 0.10/alarm/month |
| **Lab total (~4-6 hours)** | | **~USD 2.50 - 4.00** |

### Cost-Saving Rules for Students

1. **Delete the cluster IMMEDIATELY** after taking screenshots (run `cleanup.ps1`)
2. Do NOT leave EKS running overnight - cost accumulates even with 0 traffic
3. The NAT Gateway is the sneakiest cost - it runs even when pods are idle
4. Check your AWS billing dashboard before and after the lab
5. Set a billing alert: AWS Console -> Billing -> Budgets -> Create budget

```powershell
# Set a USD 10 budget alert (do this FIRST)
aws budgets create-budget `
    --account-id $AWS_ACCOUNT_ID `
    --budget '{
        "BudgetName": "focc-lab2-budget",
        "BudgetLimit": {"Amount": "10", "Unit": "USD"},
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST"
    }' `
    --notifications-with-subscribers '[{
        "Notification": {
            "NotificationType": "ACTUAL",
            "ComparisonOperator": "GREATER_THAN",
            "Threshold": 80
        },
        "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "your@email.com"}]
    }]'
```

---

## 10. Troubleshooting

### Problem: `eksctl` or `aws` not recognized after install
```powershell
# Reload PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
# Or close and reopen PowerShell
```

### Problem: `kubectl get nodes` shows no resources or wrong cluster
```powershell
# Check current context
kubectl config current-context
# Should show: email@focc-lab2-eks.us-east-1.eksctl.io (or similar)

# Update kubeconfig to point to your EKS cluster
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION
```

### Problem: Pods in `ImagePullBackOff` state
```powershell
# Check error message
kubectl describe pod -l app=frontend -n focc-lab2
# Look for "Events:" section

# Common causes:
# 1. Wrong image URI in deployment.yaml (check <AWS_ACCOUNT_ID> was replaced)
# 2. ECR token expired (re-run: aws ecr get-login-password | docker login)
# 3. Node IAM role missing ECR permissions (check eksctl node IAM role in Console)

# Fix: add ECR read permissions to node role
aws iam attach-role-policy `
    --role-name eksctl-$CLUSTER_NAME-nodegroup-$NODE_GROUP-NodeInstanceRole-XXXXX `
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### Problem: HPA shows `<unknown>/50%` for CPU target
```powershell
# metrics-server not installed or not ready
kubectl get deployment metrics-server -n kube-system
# If missing, install it:
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# Wait 60 seconds then check:
kubectl top pods -n focc-lab2
kubectl get hpa frontend-hpa -n focc-lab2
```

### Problem: LoadBalancer EXTERNAL-IP stays `<pending>`
```powershell
# EKS needs a specific IAM permission for ELB creation
# Usually auto-handled by eksctl but check:
kubectl describe svc frontend -n focc-lab2
# Look for events with "Error syncing load balancer"

# Fix: ensure node IAM role has AmazonEKSLoadBalancingPolicy
# Or check: EC2 -> Load Balancers in AWS Console to see if it's creating
```

### Problem: Visit counter shows "N/A (Redis down)"
```powershell
# Check Redis pod is running
kubectl get pods -n focc-lab2
# If redis pod is in CrashLoopBackOff:
kubectl logs -l app=redis -n focc-lab2
kubectl describe pod -l app=redis -n focc-lab2

# Check frontend can reach redis service
kubectl exec -it <frontend-pod> -n focc-lab2 -- nslookup redis
# Should resolve to a ClusterIP
```

### Problem: CloudWatch Container Insights shows no data
```powershell
# Check addon status
aws eks describe-addon --cluster-name $CLUSTER_NAME `
    --addon-name amazon-cloudwatch-observability --region $AWS_REGION

# Check cloudwatch agent pods
kubectl get pods -n amazon-cloudwatch

# Metrics take 5-10 minutes to appear after installation
# Set CloudWatch console time range to "Last 1 hour"
```

### Problem: SNS email alert never arrives
- Check your spam folder
- Verify subscription status: AWS Console -> SNS -> Subscriptions (must say "Confirmed")
- Check alarm state: CloudWatch -> Alarms (must be "In alarm" state to trigger)
- Manually trigger test: SNS -> Topics -> [your topic] -> Publish message

---

## 11. Screenshot Checklist

Take screenshots at each point for your report. Use Win+Shift+S (Snipping Tool).

**Local Testing:**
- [ ] `docker compose ps` showing both services `Up (healthy)`
- [ ] Browser at `http://localhost:5000` - visit counter UI with glassmorphism design
- [ ] Terminal: `Invoke-WebRequest http://localhost:5000/health/live` returning 200

**AWS Setup:**
- [ ] `aws sts get-caller-identity` output (shows Account ID, ARN - NOT keys)
- [ ] `aws ecr list-images --repository-name focc-lab2-frontend` output
- [ ] AWS Console: ECR -> Repositories -> focc-lab2-frontend -> Images (shows v1.0.0 tag)
- [ ] `eksctl create cluster` completion message in terminal
- [ ] `kubectl get nodes` showing node in `Ready` state

**Application Running:**
- [ ] `kubectl get pods -n focc-lab2` all pods in `Running` state (2/2 or 1/1)
- [ ] `kubectl get svc -n focc-lab2` showing LoadBalancer with ELB hostname
- [ ] Browser at `http://<ELB_HOSTNAME>` - app live on AWS (visit counter working)
- [ ] `kubectl get hpa frontend-hpa -n focc-lab2` showing 1/5 replicas, CPU metric

**Load Test:**
- [ ] Load test terminal - progress bar running
- [ ] `kubectl get hpa frontend-hpa -n focc-lab2 -w` showing replicas increasing
- [ ] `kubectl get pods -n focc-lab2` showing multiple frontend pods
- [ ] Load test final summary (RPS, P95 latency values)

**CloudWatch:**
- [ ] CloudWatch Console: Container Insights -> EKS Pods -> CPU graph (showing spike)
- [ ] CloudWatch Console: Container Insights -> memory graph
- [ ] CloudWatch Console: Alarms -> focc-lab2-frontend-cpu-high (created)
- [ ] SNS Console: Subscription confirmed
- [ ] Alert email received in inbox (can mask email address)
- [ ] CloudWatch Logs Insights query result showing pod logs

**Scale Down:**
- [ ] `kubectl get pods -n focc-lab2` after load test - back to 1 frontend pod
- [ ] `kubectl get hpa frontend-hpa -n focc-lab2` showing minReplicas (1)

---

## 12. Cleanup (IMPORTANT)

**Run this IMMEDIATELY after completing the lab to stop AWS charges.**

```powershell
# Option 1: Interactive cleanup script (safe, with double confirmation)
.\cleanup.ps1

# Option 2: Manual cleanup commands

# Delete Kubernetes resources first
kubectl delete -f k8s\ --ignore-not-found=true

# Delete EKS cluster and node group (~10 minutes)
eksctl delete cluster --name $CLUSTER_NAME --region $AWS_REGION

# Delete ECR repository
aws ecr delete-repository `
    --repository-name $ECR_REPO `
    --force `
    --region $AWS_REGION

# Delete CloudWatch log groups
aws logs delete-log-group `
    --log-group-name "/aws/containerinsights/$CLUSTER_NAME/application" `
    --region $AWS_REGION

# Delete SNS topic
aws sns delete-topic --topic-arn $TOPIC_ARN --region $AWS_REGION

# Verify no load balancers remain (check manually in Console):
# EC2 -> Load Balancers -> delete any remaining focc-* entries
# VPC -> NAT Gateways -> delete if no longer needed
```

### Verify Cleanup

1. AWS Console -> **EKS** -> Clusters (should be empty)
2. AWS Console -> **EC2** -> Instances (no running t3.medium instances)
3. AWS Console -> **EC2** -> Load Balancers (no ELBs)
4. AWS Console -> **VPC** -> NAT Gateways (delete if exists)
5. AWS Console -> **Billing** -> Cost Explorer -> last 24h (verify no surprise charges)

---

## 13. Submission Checklist

Before submitting, verify all these items are complete:

**Application files:**
- [ ] `app.py` - Flask with Redis counter, /health/live, /health/ready, /metrics, /api/stats
- [ ] `requirements.txt` - flask, redis, gunicorn pinned to specific versions
- [ ] `Dockerfile` - multi-stage (builder + runtime), non-root user, HEALTHCHECK
- [ ] `docker-compose.yml` - two services with healthchecks and depends_on
- [ ] `.dockerignore` - excludes k8s, venv, scripts, IDE files

**Kubernetes manifests:**
- [ ] `k8s/namespace.yaml` - focc-lab2 namespace
- [ ] `k8s/redis.yaml` - Redis Deployment + ClusterIP Service
- [ ] `k8s/deployment.yaml` - Flask, 100m/128Mi requests, liveness + readiness probes
- [ ] `k8s/service.yaml` - LoadBalancer type, port 80 -> 5000
- [ ] `k8s/hpa.yaml` - 1-5 replicas, 50% CPU target

**Report:**
- [ ] All 5 reflection questions answered in your own words
- [ ] Azure-to-AWS substitution table filled in
- [ ] Measured values table filled with real numbers from your load test
- [ ] All 20 screenshots collected and labelled

---

*FoCC Lab 2 (AWS) | Fundamentals of Cloud Computing | Two-Tier Cloud-Native App on EKS*
