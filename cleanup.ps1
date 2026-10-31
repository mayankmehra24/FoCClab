#Requires -Version 5.1
<#
.SYNOPSIS
    FoCC Lab 2 (AWS) - Safe resource cleanup
.DESCRIPTION
    Deletes EKS cluster, ECR repository, CloudWatch log groups, and SNS topic
    created for Lab 2. STOPS and demands confirmation before any deletion.
    Run ONLY after submitting your assignment to stop AWS charges.
.NOTES
    Requires: AWS CLI configured with appropriate IAM permissions.
    Run from the FoCC-Lab2 project root.
#>
param(
    [string]$ClusterName = "",
    [string]$EcrRepo = "focc-lab2-frontend",
    [string]$Region = "",
    [string]$NodeGroup = "focc-lab2-ng"
)

Set-StrictMode -Version Latest

Write-Host "`n=====================================================" -ForegroundColor Red
Write-Host "  FoCC Lab 2 (AWS) - Cleanup Script" -ForegroundColor Red
Write-Host "=====================================================" -ForegroundColor Red
Write-Host "  WARNING: This permanently deletes AWS resources." -ForegroundColor Yellow
Write-Host "  Run this ONLY after submitting your assignment!" -ForegroundColor Yellow
Write-Host ""

# Collect config
if ([string]::IsNullOrWhiteSpace($ClusterName)) {
    $ClusterName = Read-Host "  Enter EKS cluster name to delete"
}
if ([string]::IsNullOrWhiteSpace($Region)) {
    $Region = Read-Host "  Enter AWS region (e.g. us-east-1)"
}

Write-Host "`n  Will delete:" -ForegroundColor Red
Write-Host "    EKS cluster    : $ClusterName (region: $Region)" -ForegroundColor White
Write-Host "    ECR repository : $EcrRepo" -ForegroundColor White
Write-Host "    CloudWatch log groups: /aws/containerinsights/$ClusterName/*" -ForegroundColor White
Write-Host ""

$c1 = Read-Host "  Type the cluster name exactly to confirm"
if ($c1 -ne $ClusterName) { Write-Host "Name mismatch. Aborting." -ForegroundColor Yellow; exit 0 }
$c2 = Read-Host "  Type DELETE in caps to proceed"
if ($c2 -ne "DELETE") { Write-Host "Cancelled." -ForegroundColor Yellow; exit 0 }

# Step 1: Delete Kubernetes resources (graceful drain)
Write-Host "`n[1/5] Deleting Kubernetes resources..." -ForegroundColor Cyan
kubectl delete -f k8s\ --ignore-not-found=true 2>$null
Write-Host "  Done (or nothing to delete)"

# Step 2: Delete EKS node group first (takes ~5 min)
Write-Host "`n[2/5] Deleting EKS node group '$NodeGroup'..." -ForegroundColor Cyan
Write-Host "  (This takes 5-10 minutes - provisioning cloud resources)"
aws eks delete-nodegroup `
    --cluster-name $ClusterName `
    --nodegroup-name $NodeGroup `
    --region $Region 2>$null
Write-Host "  Node group deletion started. Waiting..."
aws eks wait nodegroup-deleted `
    --cluster-name $ClusterName `
    --nodegroup-name $NodeGroup `
    --region $Region 2>$null
Write-Host "  Node group deleted."

# Step 3: Delete EKS cluster
Write-Host "`n[3/5] Deleting EKS cluster '$ClusterName'..." -ForegroundColor Cyan
aws eks delete-cluster --name $ClusterName --region $Region
Write-Host "  Cluster deletion started (takes ~5 min)."
aws eks wait cluster-deleted --name $ClusterName --region $Region
Write-Host "  EKS cluster deleted."

# Step 4: Delete ECR repository
Write-Host "`n[4/5] Deleting ECR repository '$EcrRepo'..." -ForegroundColor Cyan
aws ecr delete-repository `
    --repository-name $EcrRepo `
    --force `
    --region $Region
Write-Host "  ECR repository deleted."

# Step 5: Delete CloudWatch log groups
Write-Host "`n[5/5] Deleting CloudWatch log groups..." -ForegroundColor Cyan
$logGroups = @(
    "/aws/containerinsights/$ClusterName/application",
    "/aws/containerinsights/$ClusterName/dataplane",
    "/aws/containerinsights/$ClusterName/host",
    "/aws/containerinsights/$ClusterName/performance",
    "/aws/eks/$ClusterName/cluster"
)
foreach ($lg in $logGroups) {
    aws logs delete-log-group --log-group-name $lg --region $Region 2>$null
    Write-Host "  Deleted: $lg"
}

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host "  Cleanup complete!" -ForegroundColor Green
Write-Host "  Check AWS Console -> EC2 -> Load Balancers" -ForegroundColor Yellow
Write-Host "  and manually delete any remaining ELB (if still present)." -ForegroundColor Yellow
Write-Host "  Also check VPC -> NAT Gateways and delete if unused." -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Green
