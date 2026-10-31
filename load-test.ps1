#Requires -Version 5.1
<#
.SYNOPSIS
    FoCC Lab 2 (AWS) - Safe 3-minute load test
.DESCRIPTION
    Sends parallel HTTP GET requests to trigger HPA CPU scaling on EKS.
    Pure PowerShell - no external tools needed. Runs exactly 180 seconds.
    Only sends read-only GET requests. Does NOT create or delete AWS resources.
.PARAMETER TargetUrl
    Your EKS LoadBalancer DNS or localhost for local testing.
    Example: http://a1b2c3.us-east-1.elb.amazonaws.com
.PARAMETER Concurrency
    Parallel workers (default 10). Increase to generate more CPU load.
.PARAMETER DurationSeconds
    Test duration (default 180 = 3 minutes).
.EXAMPLE
    .\load-test.ps1 -TargetUrl http://a1b2c3.us-east-1.elb.amazonaws.com
    .\load-test.ps1 -TargetUrl http://localhost:5000 -Concurrency 5
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetUrl,
    [int]$Concurrency = 10,
    [int]$DurationSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"
$TargetUrl = $TargetUrl.TrimEnd('/')

Write-Host "`n=====================================================" -ForegroundColor Cyan
Write-Host "  FoCC Lab 2 (AWS) - Load Test" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Target   : $TargetUrl" -ForegroundColor White
Write-Host "  Workers  : $Concurrency" -ForegroundColor White
Write-Host "  Duration : $DurationSeconds sec ($([math]::Round($DurationSeconds/60,1)) min)" -ForegroundColor White
Write-Host ""
Write-Host "  In a separate terminal, watch HPA scaling:" -ForegroundColor Yellow
Write-Host "  kubectl get hpa frontend-hpa -n focc-lab2 -w" -ForegroundColor Yellow
Write-Host "  kubectl get pods -n focc-lab2 -w" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Watch CloudWatch metrics (Container Insights):" -ForegroundColor Yellow
Write-Host "  AWS Console -> CloudWatch -> Container Insights -> EKS Pods" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Press Ctrl+C to abort early." -ForegroundColor Gray
Write-Host ""

$startTime = Get-Date
$endTime   = $startTime.AddSeconds($DurationSeconds)

$sharedData = [hashtable]::Synchronized(@{
    Total   = [int]0
    Success = [int]0
    Errors  = [int]0
    Latencies = [System.Collections.Concurrent.ConcurrentBag[double]]::new()
})

$workerScript = {
    param($Url, $EndTime, $Data)
    $sw = New-Object System.Diagnostics.Stopwatch
    while ((Get-Date) -lt $EndTime) {
        $sw.Restart()
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop
            $sw.Stop()
            [System.Threading.Interlocked]::Increment([ref]$Data.Total) | Out-Null
            if ($r.StatusCode -lt 400) {
                [System.Threading.Interlocked]::Increment([ref]$Data.Success) | Out-Null
            } else {
                [System.Threading.Interlocked]::Increment([ref]$Data.Errors) | Out-Null
            }
            $Data.Latencies.Add($sw.Elapsed.TotalMilliseconds) | Out-Null
        } catch {
            $sw.Stop()
            [System.Threading.Interlocked]::Increment([ref]$Data.Errors) | Out-Null
        }
    }
}

$pool = [runspacefactory]::CreateRunspacePool(1, $Concurrency)
$pool.Open()
$jobs = [System.Collections.Generic.List[hashtable]]::new()

for ($i = 0; $i -lt $Concurrency; $i++) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($workerScript).AddArgument($TargetUrl).AddArgument($endTime).AddArgument($sharedData)
    $jobs.Add(@{ PS=$ps; Handle=$ps.BeginInvoke() })
}

# Progress display
while ((Get-Date) -lt $endTime) {
    $elapsed   = [int]((Get-Date) - $startTime).TotalSeconds
    $remaining = $DurationSeconds - $elapsed
    $pct       = [math]::Min(100, [int](($elapsed / $DurationSeconds) * 100))
    $bar       = ("#" * [int]($pct / 5)).PadRight(20, '-')
    Write-Host "`r  [$bar] $pct% | ${elapsed}s | req:$($sharedData.Total) ok:$($sharedData.Success) err:$($sharedData.Errors) | ${remaining}s left  " -NoNewline -ForegroundColor Cyan
    Start-Sleep -Milliseconds 1000
}

foreach ($j in $jobs) { $j.PS.EndInvoke($j.Handle) | Out-Null; $j.PS.Dispose() }
$pool.Close(); $pool.Dispose()

Write-Host "`n`n=====================================================" -ForegroundColor Green
Write-Host "  Load Test Complete - Record these values in your report!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green

$total = $sharedData.Total
$ok    = $sharedData.Success
$err   = $sharedData.Errors
$rps   = [math]::Round($total / $DurationSeconds, 2)

Write-Host "  Total Requests : $total" -ForegroundColor White
Write-Host "  Successful     : $ok"    -ForegroundColor Green
Write-Host "  Errors         : $err"   -ForegroundColor Red
Write-Host "  Req/sec (RPS)  : $rps"   -ForegroundColor White

if ($sharedData.Latencies.Count -gt 0) {
    $lats  = @($sharedData.Latencies | Sort-Object)
    $cnt   = $lats.Count
    $avg   = [math]::Round(($lats | Measure-Object -Sum).Sum / $cnt, 2)
    $p50   = [math]::Round($lats[[math]::Max(0,[math]::Floor($cnt*0.50)-1)], 2)
    $p95   = [math]::Round($lats[[math]::Max(0,[math]::Floor($cnt*0.95)-1)], 2)
    $p99   = [math]::Round($lats[[math]::Max(0,[math]::Floor($cnt*0.99)-1)], 2)
    Write-Host "  Avg Latency    : $avg ms"  -ForegroundColor White
    Write-Host "  P50 Latency    : $p50 ms"  -ForegroundColor White
    Write-Host "  P95 Latency    : $p95 ms"  -ForegroundColor Yellow
    Write-Host "  P99 Latency    : $p99 ms"  -ForegroundColor Red
}

Write-Host ""
Write-Host "  Next: check HPA scale-down (takes ~2 min after test ends):" -ForegroundColor Yellow
Write-Host "  kubectl get hpa frontend-hpa -n focc-lab2 -w" -ForegroundColor Yellow
Write-Host "  Also check CloudWatch -> Container Insights for CPU spike graph." -ForegroundColor Yellow
Write-Host ""
