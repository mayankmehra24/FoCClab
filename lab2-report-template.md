# FoCC Lab 2 - Report (AWS Version)

**Student Name:** [Mayank Dehariya]
**Student ID:** [PU02424EUG10048]
**Date Submitted:** [DD-MM-YYYY]
**Module:** Fundamentals of Cloud Computing
**Lab:** Lab 2 - Containerisation and Orchestration on AWS

---

## Part A: Azure-to-AWS Service Substitutions

This lab was completed using AWS services. The table below maps each required
Azure service to the equivalent AWS service used.

| Azure Service (Assignment) | AWS Equivalent Used | Notes |
|---|---|---|
| Azure Container Registry (ACR) | Amazon ECR | Stores Docker images |
| Azure Kubernetes Service (AKS) | Amazon EKS | Runs Kubernetes cluster |
| Azure Monitor | Amazon CloudWatch | Metrics, alarms, dashboards |
| Azure Log Analytics Workspace | CloudWatch Log Groups | Centralised log storage |
| Azure Container Insights | CloudWatch Container Insights | Pod/node metrics |
| Azure Alert Rules | CloudWatch Alarms | Threshold-based alerting |
| Azure Action Groups (email) | Amazon SNS | Email notification |
| Azure Load Balancer | AWS Classic/Network Load Balancer | External traffic |
| Azure RBAC | AWS IAM | Access control |
| Azure Resource Group | AWS region + tags | Resource grouping |

---

## Part B: Measured Values

Fill these in with your **actual observed values** from the lab.

| Metric | Measured Value |
|---|---|
| ECR repository URI | `<account>.dkr.ecr.<region>.amazonaws.com/focc-lab2-frontend` |
| EKS cluster name | |
| ELB DNS hostname | |
| Docker image size (multi-stage) | ___ MB |
| Docker image size (estimated single-stage) | ___ MB |
| Multi-stage size reduction | ___ % |
| Initial pod count (before load test) | 1 |
| Peak pod count (during load test) | ___ / 5 max |
| Pod count after scale-down | 1 |
| Load test RPS (requests/second) | |
| Total requests in 3 minutes | |
| Successful requests | |
| Error count | |
| Average latency | ___ ms |
| P50 latency | ___ ms |
| P95 latency | ___ ms |
| P99 latency | ___ ms |
| Max CPU utilisation (CloudWatch) | ___ % |
| HPA scale-up time | ___ seconds after load began |
| HPA scale-down time | ___ seconds after load ended |
| CloudWatch alarm triggered (yes/no) | |
| SNS email received (yes/no) | |

---

## Part C: Reflection Questions

### Question 1
**"Explain the benefits of using a multi-stage Dockerfile. How does it reduce image size and improve security?"**

**Your Answer:**

[Write in your own words. Key points to address:]

1. **Two stages explained:**
   - Stage 1 (builder): installs gcc and pip, compiles Python packages
   - Stage 2 (runtime): copies only the pre-built /opt/venv virtual environment
   - Build tools (gcc, compilers) are NOT present in the final image

2. **Size impact:**
   - Single-stage would include: build tools + dev headers + pip cache
   - Multi-stage only includes: Python slim + pre-installed packages
   - My measured sizes: builder ≈ [?] MB → runtime ≈ [?] MB

3. **Security benefits:**
   - No compiler in production image = attacker cannot compile exploits
   - Fewer packages = smaller attack surface
   - Non-root user (UID 1001) = no privilege escalation via app process
   - .dockerignore keeps source control, scripts, k8s configs out of image

4. **ECR image scanning:**
   - Created ECR with scanOnPush=true
   - Any known CVEs in base image are reported in AWS Console

---

### Question 2
**"Describe how Kubernetes HPA works in this deployment. What happened during and after the load test?"**

**Your Answer:**

[Write in your own words. Key points to address:]

1. **How HPA works:**
   - The HPA controller queries metrics-server every 15 seconds
   - It calculates: current_avg_cpu / target_cpu = scale_factor
   - Config: minReplicas=1, maxReplicas=5, target=50% of 100m = 50m CPU per pod
   - If avg CPU across pods > 50m, HPA adds replicas

2. **What I observed during the load test:**
   - Before test: 1 replica, CPU ≈ [?]%
   - After ~[?] seconds: CPU exceeded 50m threshold
   - HPA scaled to [?] replicas (record from kubectl get hpa -w output)
   - scaleUp.stabilizationWindowSeconds=30 controls how quickly it reacts

3. **After the test:**
   - Load stopped, CPU dropped
   - scaleDown.stabilizationWindowSeconds=120 kept pods up for 2 minutes
   - After 120 seconds, HPA scaled back down to 1 replica
   - Time to full scale-down: approximately [?] minutes

4. **Difference from static scaling:**
   - Elastic scaling is a key cloud benefit - pay only for what you use
   - Without HPA, you would need to manually resize the deployment

---

### Question 3
**"Why is the Redis service type ClusterIP while the frontend service is type LoadBalancer? What are the security implications?"**

**Your Answer:**

[Write in your own words. Key points to address:]

1. **ClusterIP (Redis):**
   - Only reachable from inside the Kubernetes cluster (CIDR: 10.x.x.x)
   - No AWS Load Balancer is created - no external IP assigned
   - Only the frontend pods (same cluster, same namespace) can reach Redis
   - Exposes Redis externally would allow anyone on the internet to FLUSHALL

2. **LoadBalancer (Frontend):**
   - EKS creates an AWS Classic Load Balancer (ELB)
   - Assigns a public DNS hostname (*.elb.amazonaws.com)
   - Routes port 80 to port 5000 on Flask pods
   - Health checks ensure only Ready pods receive traffic

3. **Security principle:**
   - Principle of Least Exposure / Network Segmentation
   - Only the service that NEEDS to be public is exposed
   - In a stricter setup, you would add a NetworkPolicy to block inter-namespace traffic
   - Redis in production should also use password auth (REDIS_PASSWORD env var)

4. **AWS-specific note:**
   - ELB security group automatically restricts inbound to port 80
   - EKS worker node security group only allows ELB → node traffic on 5000

---

### Question 4
**"Describe how AWS CloudWatch Container Insights was configured and what metrics you collected."**

**Your Answer:**

[Write in your own words. Key points to address:]

1. **Setup method:**
   - Enabled via: aws eks create-addon --addon-name amazon-cloudwatch-observability
   - This installs: CloudWatch Agent DaemonSet + Fluent Bit DaemonSet
   - IAM service account with CloudWatchAgentServerPolicy attached

2. **Metrics collected automatically:**
   - Pod CPU utilisation (used for HPA trigger evidence)
   - Pod memory usage (working set bytes)
   - Node CPU and memory
   - Container restart count (detects crashes)
   - Network bytes in/out per pod

3. **Custom metrics from /metrics endpoint:**
   - http_requests_total (Prometheus counter)
   - http_request_duration_seconds (Prometheus histogram → P95)
   - redis_visit_count (current counter value)

4. **How I accessed the data:**
   - AWS Console → CloudWatch → Container Insights → EKS Pods view
   - Selected cluster: [your cluster name], namespace: focc-lab2
   - CPU graph showed spike during load test
   - Created alarm: CPU > 70% for 5 minutes → SNS → email

5. **Log access:**
   - CloudWatch → Log Groups → /aws/containerinsights/[cluster]/application
   - KQL equivalent (CloudWatch Insights query):
     ```
     fields @timestamp, @message
     | filter kubernetes.namespace_name = "focc-lab2"
     | sort @timestamp desc
     | limit 50
     ```

6. **Alarm + notification:**
   - CloudWatch alarm created for CPU threshold
   - SNS topic: focc-lab2-alerts
   - Email subscription confirmed
   - Alert received during load test: [yes/no - fill in actual result]

---

### Question 5
**"Reflect on the challenges you faced during this AWS lab and what you learned about cloud-native architecture."**

**Your Answer:**

[Write your personal reflection. Suggested structure:]

1. **Challenges encountered:**
   - Challenge: [e.g. EKS cluster creation took 20 minutes - longer than expected]
     Resolution: [e.g. Used eksctl which automated VPC + subnet creation]
   - Challenge: [e.g. HPA showed <unknown> for CPU]
     Resolution: [e.g. metrics-server was not installed by default on EKS (unlike AKS)]
   - Challenge: [e.g. ELB hostname took 3 minutes to appear]
     Resolution: [e.g. Waited and polled with kubectl get svc -w]
   - Challenge: [add your own]

2. **Key learnings:**
   - Containers make the app identical locally and on cloud (same Docker image)
   - Kubernetes separates concerns: deployment = pods, service = networking, HPA = scaling
   - Cloud elasticity means you pay per use - HPA shrank back to 1 pod after load ended
   - Security requires deliberate network design (Redis internal, frontend external)
   - Observability must be configured - metrics don't appear without Container Insights

3. **AWS vs Azure comparison (brief):**
   - EKS requires metrics-server to be installed manually (AKS includes it)
   - ECR authentication uses `aws ecr get-login-password | docker login` (more steps than az acr login)
   - CloudWatch Container Insights provides equivalent observability to Azure Monitor
   - eksctl simplifies cluster creation but adds a tool dependency

4. **What I would do differently:**
   - [Your honest reflection on process, timing, cost management, etc.]

---

## Part D: Screenshots Checklist

Attach all screenshots below or as separate image files.

- [ ] `docker compose up` - both services showing `Up (healthy)`
- [ ] Browser at `http://localhost:5000` - visit counter UI
- [ ] `aws ecr describe-repositories` output in terminal
- [ ] ECR repository in AWS Console showing pushed image tag
- [ ] `eksctl create cluster` completion output
- [ ] `kubectl get nodes` showing node in Ready state
- [ ] `kubectl get pods -n focc-lab2` all pods Running
- [ ] `kubectl get svc -n focc-lab2` showing LoadBalancer hostname
- [ ] Browser at `http://<ELB_HOSTNAME>` - app live on AWS
- [ ] `kubectl get hpa frontend-hpa -n focc-lab2` before load test
- [ ] Load test terminal output (RPS, P95 latency values)
- [ ] `kubectl get hpa frontend-hpa -n focc-lab2 -w` during test (replica increase)
- [ ] CloudWatch Container Insights - CPU spike graph (pod view)
- [ ] CloudWatch Container Insights - memory graph
- [ ] CloudWatch Alarm configuration (Console screenshot)
- [ ] SNS subscription confirmed (Console or email screenshot)
- [ ] Alert email received (email client screenshot - mask personal details)
- [ ] CloudWatch Logs Insights query result
- [ ] `kubectl get pods -n focc-lab2` after scale-down (back to 1)

---

## Part E: Architecture Overview

```
          Internet
             |
             | HTTP :80
             v
    AWS Classic Load Balancer
    (*.elb.amazonaws.com)
             |
             | :5000
             v
+------ EKS Cluster (focc-lab2-eks) ------+
|  Namespace: focc-lab2                    |
|                                          |
|  [frontend Pod 1..5]  <-- HPA (1-5)     |
|   Flask + Gunicorn                       |
|   /metrics (Prometheus fmt)              |
|        |                                 |
|        | ClusterIP :6379                 |
|        v                                 |
|  [redis Pod]                             |
|   Redis 7.2-alpine                       |
|        |                                 |
|   emptyDir (ephemeral)                   |
+------------------------------------------+
|                                          |
|  CloudWatch Container Insights           |
|  (CloudWatch Agent + Fluent Bit DS)      |
|  -> Log Groups -> CloudWatch Alarms      |
|  -> SNS Topic -> Email Notification      |
+------------------------------------------+
```

**Monitoring Data Flow:**
```
Pod metrics/logs
  --> CloudWatch Agent DaemonSet
      --> CloudWatch Log Groups (/aws/containerinsights/...)
          --> CloudWatch Container Insights (CPU/memory graphs)
              --> CloudWatch Alarm (CPU > threshold)
                  --> SNS Topic (focc-lab2-alerts)
                      --> Email (your@email.com)
```

---

*Template generated by FoCC Lab 2 AWS setup. Fill ALL [YOUR ...] placeholders with real values before submission.*
