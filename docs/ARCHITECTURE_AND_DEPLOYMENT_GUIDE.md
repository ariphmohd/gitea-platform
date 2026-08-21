# 🏛️ Gitea Enterprise DevSecOps Platform: End-to-End Architecture & Deployment Guide

Welcome to the definitive **Engineering Deep Dive and Architectural Master Reference** for the Enterprise Gitea Platform on AWS EKS with ArgoCD GitOps, Prometheus/Grafana Monitoring, Amazon ECR, and GitHub Actions OIDC CI/CD.

This document serves as your **core reference manual, interview preparation guide, and SRE operational runbook**. It details every component, the exact architectural reasons for each decision, how components interconnect, security/cost trade-offs, and official industry documentation links.

---

## 📑 Table of Contents
1. [Master System Architecture Diagram](#-1-master-system-architecture-diagram)
2. [Stage 01: Cloud Infrastructure as Code (Terraform)](#-2-stage-01-cloud-infrastructure-as-code-terraform)
3. [Stage 02: EKS Cluster Bootstrap & Core Controllers](#-3-stage-02-eks-cluster-bootstrap--core-controllers)
4. [Stage 03: GitOps Control Plane (ArgoCD)](#-4-stage-03-gitops-control-plane-argocd)
5. [Stage 04: Production Gitea Microservice Deployment](#-5-stage-04-production-gitea-microservice-deployment)
6. [Stage 05: Full-Stack Observability (Prometheus & Grafana)](#-6-stage-05-full-stack-observability-prometheus--grafana)
7. [Stage 06: Enterprise Cloud APM (Datadog Observability)](#-7-stage-06-enterprise-cloud-apm-datadog-observability)
8. [Stage 07: Custom Domain, Public DNS & TLS Termination (Route 53 & ACM)](#-8-stage-07-custom-domain-public-dns--tls-termination-route-53--acm)
9. [Stage 08: Private Container Registry (Amazon ECR)](#-9-stage-08-private-container-registry-amazon-ecr)
10. [Stage 09: Passwordless CI/CD & Automated GitOps (GitHub Actions OIDC)](#-10-stage-09-passwordless-cicd--automated-gitops-github-actions-oidc)
11. [SRE Architecture Interview Cheat-Sheet: Top Questions & Answers](#-11-sre-architecture-interview-cheat-sheet-top-questions--answers)

---

# 🌐 1. Master System Architecture Diagram

```mermaid
flowchart TD
    subgraph Users ["🌐 Public Internet & End Users"]
        Developer["👨‍💻 SRE & Developers"]
        ClientHTTPS["🔒 HTTPS Traffic (*.ariphmohd.shop)"]
    end

    subgraph Edge ["🌍 Global DNS & Ingress Tier"]
        GoDaddy["GoDaddy Registrar (ariphmohd.shop)"]
        Route53["AWS Route 53 Public Hosted Zone\n(4 AWS Nameservers)"]
        ACM["AWS Certificate Manager (ACM)\nWildcard TLS Certificate (*.ariphmohd.shop)"]
        ALB["AWS Application Load Balancer (ALB)\n• Port 80 -> HTTP 301 Redirect to 443\n• Port 443 -> TLS Termination & Multi-Host Routing"]
    end

    subgraph AWSCloud ["☁️ AWS Cloud (ap-south-1 Mumbai)"]
        subgraph VPC ["AWS Virtual Private Cloud (10.0.0.0/16)"]
            subgraph PublicSubnets ["Public Subnets (Multi-AZ)"]
                NAT["NAT Gateway & Internet Gateway"]
                ALBInstance["ALB Listeners & Target Groups"]
            end

            subgraph PrivateSubnets ["Private Subnets (EKS Managed Node Groups)"]
                subgraph EKS ["☸️ Amazon EKS Cluster (v1.30 Graviton ARM64)"]
                    subgraph NS_Gitea ["Namespace: gitea"]
                        GiteaPod["Gitea Web/Git Application (1.22.1)\n• Rootless (UID 1000)\n• IRSA Role: S3 + Secrets Manager"]
                        EFS_PVC["EFS Dynamic PVC (/data)"]
                    end

                    subgraph NS_Argo ["Namespace: argocd"]
                        ArgoServer["ArgoCD Server (Web UI & API)"]
                        ArgoRepo["ArgoCD Repo Server (Git Manifests)"]
                        ArgoController["ArgoCD Application Controller (Auto-Reconciler)"]
                    end

                    subgraph NS_Monitoring ["Namespace: monitoring"]
                        Prometheus["Prometheus Operator & Server (TSDB)"]
                        Grafana["Grafana Visualizer (Dashboards & Metrics)"]
                        NodeExp["Prometheus Node-Exporter & KSM"]
                    end

                    subgraph NS_Datadog ["Namespace: datadog (Optional)"]
                        DDAgent["Datadog DaemonSet (APM & Cloud Observability)"]
                    end
                end
            end

            subgraph DataTier ["AWS Managed Data & Storage Tier (Isolated Multi-AZ)"]
                RDS["Amazon RDS PostgreSQL 16\n• db.t4g.micro (Single-AZ Free-Tier)\n• KMS Encrypted Storage\n• Auto Backups (7 Days)"]
                EFS["Amazon EFS File System\n• Elastic Throughput\n• Dynamic Multi-AZ PV/PVC"]
                S3["Amazon S3 Bucket\n• LFS, Avatars, Attachments, Packages\n• SSE-S3 Encrypted & Block Public Access"]
                SecretsMgr["AWS Secrets Manager\n• RDS Master DB Password\n• KMS Key Rotation"]
            end
        end

        subgraph Registry ["📦 Container Registry Tier"]
            ECR["Amazon Elastic Container Registry (ECR)\n• Repo: gitea-custom\n• Scan-on-Push CVE Detector\n• Lifecycle: Retain 10 Images"]
        end
    end

    subgraph CI_CD ["🚀 DevSecOps Continuous Integration Tier"]
        GitHub["GitHub Repository (ariphmohd/gitea)"]
        GHA["GitHub Actions Runner\n• Trivy CVE Security Scanner\n• Docker Multi-Stage Buildx"]
        OIDC["AWS IAM OpenID Connect (OIDC)\n(Passwordless 1-Hour STS Token)"]
    end

    Developer --> GitHub
    GitHub --> GHA
    GHA -->|1. OIDC Token Exchange| OIDC
    OIDC -->|2. STS AssumeRole| GHA
    GHA -->|3. Push Scanned Container| ECR
    GHA -->|4. Update Image Tag| ArgoRepo
    ArgoController -->|5. GitOps Pull & Deploy| GiteaPod

    GoDaddy --> Route53
    Route53 --> ALB
    ACM -.->|TLS Certificate| ALB
    ClientHTTPS --> ALB
    ALB -->|gitea.ariphmohd.shop| GiteaPod
    ALB -->|grafana.ariphmohd.shop| Grafana
    ALB -->|argocd.ariphmohd.shop| ArgoServer

    GiteaPod --> RDS
    GiteaPod --> EFS_PVC
    GiteaPod --> S3
    Prometheus -->|Scrapes /metrics| GiteaPod
    Prometheus -->|Scrapes Node Metrics| NodeExp
    Grafana -->|Queries TSDB| Prometheus
```

---

# 🏗️ 2. Stage 01: Cloud Infrastructure as Code (Terraform)

```mermaid
flowchart LR
    TF["Terraform Engine\n(HashiCorp v1.8+)"] --> VPC["1. VPC Module\n• 3 Public Subnets\n• 3 Private Subnets\n• NAT Gateway + IGW"]
    TF --> EKSMod["2. EKS Module\n• Control Plane v1.30\n• 3x t4g.small (ARM64)\n• OIDC Identity Provider"]
    TF --> RDSMod["3. RDS Module\n• PostgreSQL 16.3\n• AWS Secrets Manager\n• KMS Encryption"]
    TF --> EFSMod["4. EFS Storage\n• Elastic Multi-AZ NFS\n• Security Group (Port 2049)"]
    TF --> S3Mod["5. S3 Bucket\n• TLS Enforcement\n• Block Public Access"]
    TF --> IAMMod["6. IAM / IRSA\n• OIDC Role Mappings\n• GitHub OIDC Role"]
```

### 🧩 Components Provisioned & Why They Were Chosen
1. **AWS VPC (`10.0.0.0/16`)**:
   - **Why**: Isolates compute, database, and storage into secure private subnets. Workloads inside private subnets have zero public IP addresses, preventing direct internet attacks.
   - **Subnet Layout**: 3 Public subnets for Application Load Balancers and NAT Gateway; 3 Private subnets for EKS worker nodes and RDS.
2. **Amazon EKS (Kubernetes v1.30 on AWS Graviton `t4g.small`)**:
   - **Why Graviton ARM64**: Provides **40% better price-to-performance** compared to x86 instances, drastically reducing compute costs.
   - **Sizing**: 3 nodes distributed across 3 Availability Zones (`ap-south-1a`, `ap-south-1b`, `ap-south-1c`) for high availability.
3. **Amazon RDS PostgreSQL 16 (`db.t4g.micro`)**:
   - **Why Managed RDS over Pod DB**: Running databases inside Kubernetes pods risks data corruption during node failover. Managed RDS handles automated daily snapshots, multi-AZ standby, point-in-time recovery (PITR), and automated security patching.
4. **Amazon EFS (Elastic File System)**:
   - **Why EFS over EBS**: Standard AWS EBS volumes (`gp3`) are `ReadWriteOnce` (RWO) and bound to a single availability zone. Gitea requires `ReadWriteMany` (RWX) so multiple Git pods across different AZs can access repository repositories concurrently.
5. **Amazon S3 (`gitea-prod-storage-*`)**:
   - **Why S3**: Highly scalable, 11 9's durability storage for large Git LFS artifacts, avatars, and release packages at fraction of block storage cost.
6. **AWS Secrets Manager**:
   - **Why**: Automatically generates high-entropy random database passwords and stores them with AWS KMS hardware encryption. Zero database passwords exist in Terraform code or Git.

### 📚 Official References:
- [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [HashiCorp AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Amazon RDS Security & Secrets Manager Integration](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)

---

# ⚙️ 3. Stage 02: EKS Cluster Bootstrap & Core Controllers

```mermaid
flowchart LR
    Kubeconfig["1. Generate Kubeconfig\n(aws eks update-kubeconfig)"] --> CRDs["2. Install AWS Load Balancer Controller\n(v2.8.1 via Helm)"]
    CRDs --> EFS_CSI["3. Install AWS EFS CSI Driver\n(v3.0.7 via Helm)"]
    EFS_CSI --> StorageClass["4. Apply Dynamic EFS StorageClass\n(k8s/efs-storageclass.yaml)"]
    StorageClass --> IRSA_Check["5. Validate IAM Roles for Service Accounts\n(OIDC Web Identity)"]
```

### 🧩 Components Provisioned & Architectural Justification
1. **AWS Load Balancer Controller (ALBC)**:
   - **What it does**: Watches Kubernetes `Ingress` resources and dynamically provisions native AWS Application Load Balancers (ALB) and Target Groups via AWS APIs.
   - **Why Needed**: Enables Layer 7 traffic routing, path-based routing, ACM TLS termination, and AWS WAF integration directly from Kubernetes manifests.
2. **AWS EFS CSI Driver**:
   - **What it does**: Allows Kubernetes pods to dynamically mount AWS EFS Network File Systems as persistent volumes (`PV` & `PVC`).
   - **Why Needed**: Bridges the gap between EKS Kubernetes Pods and AWS managed NFS storage.
3. **IAM Roles for Service Accounts (IRSA)**:
   - **What it does**: Associates an AWS IAM Role directly with a Kubernetes ServiceAccount using OIDC cryptographic JWT verification.
   - **Why it matters**: **Eliminates IAM instance profiles and hardcoded AWS keys**. The EFS CSI driver and ALB Controller only have the exact minimum IAM permissions needed to operate.

### 📚 Official References:
- [Kubernetes IRSA Deep Dive](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AWS Load Balancer Controller Official Guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/)
- [AWS EFS CSI Driver GitHub Repository](https://github.com/kubernetes-sigs/aws-efs-csi-driver)

---

# 🐙 4. Stage 03: GitOps Control Plane (ArgoCD)

```mermaid
flowchart TD
    GitRepo["Git Repository\n(gitea-platform/argocd/)"] -->|Monitors 3-min Loop| ArgoController["ArgoCD Application Controller"]
    ArgoController -->|Calculates Diff| DiffEngine["Diff Engine (Live EKS vs Desired Git)"]
    DiffEngine -->|Out of Sync Detected| Reconciler["Automated Self-Healing Reconciler"]
    Reconciler -->|Deploys / Patches| K8sObjects["Kubernetes Deployments, Secrets, Ingresses"]
```

### 🧩 Components Provisioned & Architectural Justification
1. **ArgoCD Server (`v2.11.3`)**:
   - **Why GitOps**: In traditional CI/CD, deployment scripts push changes to clusters. If someone manually modifies the cluster via `kubectl`, the cluster drifts out of sync. ArgoCD implements **pull-based GitOps**: Git is the **single source of truth**. If anything in the cluster drifts, ArgoCD automatically detects it and reconciles state back to what Git specifies.
2. **App-of-Apps Architecture Pattern**:
   - **What it does**: A root `Application` manifest manages child applications (`gitea-app`, `monitoring-app`, `datadog-app`).
   - **Benefit**: Adding or removing microservices is done purely by committing a single YAML file to Git.

### 📚 Official References:
- [ArgoCD Official Core Concepts & Architecture](https://argo-cd.readthedocs.io/en/stable/core_concepts/)
- [The OpenGitOps Principles](https://opengitops.dev/)

---

# ☕ 5. Stage 04: Production Gitea Microservice Deployment

```mermaid
flowchart LR
    InitSec["1. Fetch RDS Password\n(AWS Secrets Manager)"] --> GenSec["2. Generate 256-bit Admin Secret\n(gitea-admin-secret)"]
    GenSec --> Render["3. Render Dynamic Helm Values\n(gitea-values.rendered.yaml)"]
    Render --> ArgoSync["4. ArgoCD GitOps Reconciliation"]
    ArgoSync --> GiteaPod["5. Gitea Pod Running\n• Rootless Container\n• EFS /data mounted\n• RDS PostgreSQL connected\n• mustChangePassword = true"]
```

### 🧩 Key Architecture Highlights
1. **Zero-Plaintext Secret Architecture**:
   - RDS master password is read dynamically from AWS Secrets Manager using IAM IRSA credentials.
   - Admin bootstrap password is dynamically generated using 256-bit entropy (`openssl rand -base64 18`) and stored strictly in Kubernetes Secret `gitea-admin-secret`.
2. **NIST 800-63B Compliant Password Rotation**:
   - The initial admin account is created with `--must-change-password=true`. Upon first login at `https://gitea.ariphmohd.shop`, Gitea immediately presents a mandatory password change screen before any actions can be performed.
3. **Rootless Security Profile**:
   - The Gitea container runs as non-root user `UID 1000:GID 1000` inside a minimal Alpine container, preventing container breakout attacks.

### 📚 Official References:
- [Gitea Helm Chart Official Documentation](https://gitea.com/gitea/helm-chart)
- [NIST Special Publication 800-63B: Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)

---

# 📈 6. Stage 05: Full-Stack Observability (Prometheus & Grafana)

```mermaid
flowchart TD
    GiteaMetrics["Gitea App (:3000/metrics)"] -->|Scraped every 15s| PromEngine["Prometheus Server (TSDB)"]
    NodeMetrics["EKS EC2 Nodes (:9100)"] -->|Scraped every 15s| PromEngine
    KubeState["Kubernetes API & Pod States"] -->|Scraped every 15s| PromEngine
    PromEngine -->|PromQL Queries| GrafanaUI["Grafana Dashboards\n(https://grafana.ariphmohd.shop)"]
```

### 🧩 Components & Critical SRE Fixes Applied
1. **Server-Side Apply for Prometheus CRDs**:
   - **The Problem**: Prometheus Operator CRDs exceed Kubernetes' standard **256KB metadata annotation limit**, causing `kubectl apply` and Helm to crash with `metadata.annotations: Too long`.
   - **The Solution**: Pre-installed CRDs using native Kubernetes **Server-Side Apply** (`kubectl apply --server-side --force-conflicts`), bypassing client-side annotation size limits.
2. **Automated Grafana Sidecar Dashboards**:
   - Dashboard providers and Prometheus datasources are automatically discovered using Kubernetes configmap labels (`grafana_dashboard: "1"`), eliminating duplicate datasource bugs.

### 📚 Official References:
- [kube-prometheus-stack GitHub Repository](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Kubernetes Server-Side Apply Documentation](https://kubernetes.io/docs/reference/using-api/server-side-apply/)

---

# 🐶 7. Stage 06: Enterprise Cloud APM (Datadog Observability)

```mermaid
flowchart LR
    EKSNodes["EKS Worker Nodes"] -->|Runs DaemonSet| DDAgent["Datadog Agent Pod\n(Host Port 8126 & Trace Agent)"]
    DDAgent -->|Collects Logs, APM, Traces| CloudDatadog["Datadog Cloud SaaS\n(app.datadoghq.com)"]
```

### 🧩 Key Architecture Highlights
- **Optional & Safe**: The script checks `DATADOG_ENABLED="true"` and validates API keys. If keys are missing, it gracefully skips without breaking infrastructure.
- **DaemonSet Architecture**: Runs exactly 1 lightweight agent pod per EKS worker node to collect real-time system metrics, container logs, eBPF network metrics, and distributed APM traces.

### 📚 Official References:
- [Datadog Kubernetes Agent Documentation](https://docs.datadoghq.com/containers/kubernetes/)

---

# 🌐 8. Stage 07: Custom Domain, Public DNS & TLS Termination (Route 53 & ACM)

```mermaid
flowchart LR
    subgraph Registrar ["GoDaddy Registrar"]
        Domain["ariphmohd.shop\n(Nameservers pointed to AWS)"]
    end

    subgraph AWS_DNS ["AWS Route 53 & ACM"]
        Zone["Route 53 Hosted Zone\n• ns-xxx.awsdns-xx.com\n• ns-xxx.awsdns-xx.net"]
        ACM["ACM Certificate (*.ariphmohd.shop)\n• Validated via DNS CNAME\n• Auto-Renews every 13 months"]
    end

    subgraph SharedALB ["AWS Application Load Balancer"]
        ALB["Shared ALB (group.name: platform)\n• Port 80: HTTP -> HTTPS Redirect\n• Port 443: TLS 1.3 Termination"]
    end

    subgraph Endpoints ["Subdomain Routing"]
        E1["gitea.ariphmohd.shop -> Gitea Service:3000"]
        E2["grafana.ariphmohd.shop -> Grafana Service:80"]
        E3["argocd.ariphmohd.shop -> ArgoCD Server:80"]
    end

    Domain --> Zone
    Zone --> ACM
    ACM -.->|TLS Certificate| ALB
    ALB --> E1
    ALB --> E2
    ALB --> E3
```

### 🧩 Why This Architecture Is Optimal
1. **Shared ALB Ingress Group (`group.name: platform`)**:
   - **Cost Saving**: Instead of creating 3 separate AWS Application Load Balancers ($25/month each = $75/month), the `alb.ingress.kubernetes.io/group.name: platform` annotation multiplexes all 3 services onto **a single shared ALB**, saving **$50/month**!
2. **Wildcard ACM Certificate (`*.ariphmohd.shop`)**:
   - Free, AWS-managed SSL certificate with automated DNS renewal.
3. **Decoupled Standalone Module**:
   - Route 53 and ACM are isolated in `terraform/custom-domain/` and `scripts/07-setup-custom-domain.sh`, ensuring the base platform remains 100% functional on raw HTTP/ALB if DNS is not yet configured.

### 📚 Official References:
- [AWS Route 53 Hosted Zones Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-working-with.html)
- [AWS ALB Ingress Grouping Specification](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/#ingressgroup)

---

# 📦 9. Stage 08: Private Container Registry (Amazon ECR)

```mermaid
flowchart LR
    DevPush["Docker / CI Runner"] --> ECR["Amazon ECR: gitea-custom\n• Region: ap-south-1\n• KMS Encryption at Rest"]
    ECR -->|Automatic Trigger| Inspector["AWS Inspector\n(CVE Vulnerability Scanner)"]
    ECR -->|Daily Automated Check| Lifecycle["Lifecycle Policy\n(Retains latest 10 tagged releases)"]
```

### 🧩 Components Provisioned:
1. **Repository**: `gitea-custom` in `ap-south-1` (`542697646590.dkr.ecr.ap-south-1.amazonaws.com/gitea-custom`).
2. **`scan_on_push = true`**: Triggers automated AWS vulnerability scanning on every image push.
3. **Lifecycle Rule**: Automatically expires untagged layers after 1 day and retains only the latest 10 releases, keeping storage under **$0.15/month**.

### 📚 Official References:
- [Amazon ECR Private Repositories & Image Scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/Repositories.html)

---

# 🔐 10. Stage 09: Passwordless CI/CD & Automated GitOps (GitHub Actions OIDC)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Developer (git push to ariphmohd/gitea)
    participant GHA as GitHub Actions CI Runner
    participant Trivy as Trivy CVE Scanner
    participant OIDC as GitHub OIDC Token Provider
    participant AWS as AWS IAM STS (ap-south-1)
    participant ECR as Amazon ECR (gitea-custom)
    participant GitOps as GitOps Repo (ariphmohd/gitea-platform)
    participant Argo as ArgoCD on AWS EKS

    Dev->>GHA: Trigger Workflow (push to main)
    GHA->>Trivy: Scan code & dependencies for CVEs
    Trivy-->>GHA: Scan Clean (Passed)
    GHA->>OIDC: Request Short-Lived JWT Token for 'repo:ariphmohd/gitea'
    OIDC-->>GHA: Cryptographically Signed JWT Token
    GHA->>AWS: AssumeRoleWithWebIdentity (gitea-prod-github-actions-ecr-role)
    AWS->>AWS: Verify JWT Signature from GitHub
    AWS-->>GHA: Ephemeral 1-Hour AWS Credentials
    GHA->>GHA: Build Multi-Stage Rootless Container Image
    GHA->>ECR: Push Image (gitea-custom:sha-4b32939 & latest)
    GHA->>GitOps: Clone & Update image.tag in gitea-values.yaml (via GITOPS_PAT)
    GitOps->>GitOps: Commit & Push (chore(gitops): auto-deploy sha-4b32939)
    Argo->>GitOps: Detect New Commit in 3-min Polling Loop
    Argo->>ECR: Pull New Image Tag (sha-4b32939)
    Argo->>Argo: Execute Zero-Downtime Rolling Update on EKS Pods!
```

### 🔒 Why AWS IAM OIDC (Zero Static Keys)?
- **The Problem**: Traditional CI/CD stored permanent `AWS_ACCESS_KEY_ID` & `AWS_SECRET_ACCESS_KEY` in GitHub. If stolen, attackers had permanent access to AWS.
- **The Solution**: GitHub Actions OIDC exchanges a signed JWT token for temporary 1-hour AWS STS credentials. **Zero permanent keys exist anywhere in GitHub**.

### 🔄 Why `GITOPS_PAT` Is Required?
- **Repository Isolation**: `ariphmohd/gitea` (Application Code) and `ariphmohd/gitea-platform` (GitOps Manifests) are separate repositories.
- **The Role of `GITOPS_PAT`**: Acts as the authenticated authorization token allowing the CI runner in Repo 1 to commit the updated image tag into Repo 2, completing the automated continuous delivery loop!

### 📚 Official References:
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS STS AssumeRoleWithWebIdentity API](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)

---

# 🧠 11. SRE Architecture Interview Cheat-Sheet: Top Questions & Answers

### Q1: Why use Amazon EFS for Gitea shared storage instead of Amazon EBS?
> **Answer**: Amazon EBS volumes are block storage devices with `ReadWriteOnce` (RWO) access mode, binding them to a single EC2 node in a single Availability Zone. Gitea requires `ReadWriteMany` (RWX) shared file storage across multiple Availability Zones so Git repositories remain accessible even if a pod is rescheduled onto a different worker node across AZs.

### Q2: Why use AWS IAM OIDC instead of storing AWS Access Keys in GitHub Secrets?
> **Answer**: AWS IAM OIDC eliminates static, long-lived credentials. GitHub acts as a trusted OpenID Connect Identity Provider that issues short-lived JWT tokens. AWS STS validates the token and issues temporary credentials that automatically expire in 1 hour. This eliminates the risk of credential leakage and complies with NIST and SOC2 zero-trust standards.

### Q3: Why use ArgoCD GitOps instead of executing `helm upgrade` in GitHub Actions?
> **Answer**: Running `helm upgrade` from CI is "push-based deployment," which creates cluster drift when changes occur directly in Kubernetes and requires granting CI runners admin access to the Kubernetes API. ArgoCD is "pull-based GitOps": Git is the single source of truth, ArgoCD runs inside the cluster with local RBAC, continuously reconciles cluster state against Git, and automatically self-heals any configuration drift.

### Q4: How do you solve the Kubernetes 256KB metadata annotation limit when installing Prometheus Operator CRDs?
> **Answer**: Standard `kubectl apply` records the entire manifest in the `kubectl.kubernetes.io/last-applied-configuration` annotation, which exceeds Kubernetes' 256KB limit for large CRDs. We solve this by using **Server-Side Apply** (`kubectl apply --server-side --force-conflicts`), which manages field ownership directly on the Kubernetes API server without client-side metadata annotations.

### Q5: How do we achieve zero hardcoded passwords and NIST 800-63B compliance?
> **Answer**: Database credentials are generated dynamically by Terraform into AWS Secrets Manager with KMS encryption. Application admin credentials are generated dynamically at runtime using 256-bit entropy into Kubernetes Secrets. Applications are configured with `--must-change-password=true`, enforcing a mandatory password reset on first login.
