# 🚀 Enterprise Gitea Platform on AWS EKS with ArgoCD GitOps, Observability & Custom Domain HTTPS

[![AWS](https://img.shields.io/badge/AWS-ap--south--1-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![EKS](https://img.shields.io/badge/Kubernetes-EKS_v1.30-326CE5?logo=kubernetes&logoColor=white)](https://aws.amazon.com/eks/)
[![Terraform](https://img.shields.io/badge/Terraform-v1.5+-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo&logoColor=white)](https://argo-cd.readthedocs.io/)
[![Gitea](https://img.shields.io/badge/Git-Gitea_v1.22-609926?logo=gitea&logoColor=white)](https://about.gitea.com/)
[![Route53](https://img.shields.io/badge/DNS-Route_53-8C4FFF?logo=amazon-route53&logoColor=white)](https://aws.amazon.com/route53/)
[![ACM](https://img.shields.io/badge/SSL-TLS_1.3_ACM-147EBA?logo=letsencrypt&logoColor=white)](https://aws.amazon.com/certificate-manager/)
[![Prometheus](https://img.shields.io/badge/Monitoring-Prometheus-E6522C?logo=prometheus&logoColor=white)](https://prometheus.io/)
[![Grafana](https://img.shields.io/badge/Visualization-Grafana-F46800?logo=grafana&logoColor=white)](https://grafana.com/)
[![Datadog](https://img.shields.io/badge/Observability-Datadog-632CA6?logo=datadog&logoColor=white)](https://www.datadoghq.com/)

A cost-optimized, enterprise-grade GitOps platform deploying **[Gitea](https://about.gitea.com/)** on **[Amazon Elastic Kubernetes Service (EKS)](https://aws.amazon.com/eks/)** in the **AWS Mumbai Region (`ap-south-1`)**. Managed via **[ArgoCD](https://argo-cd.readthedocs.io/)**, backed by **[Amazon RDS PostgreSQL](https://aws.amazon.com/rds/postgresql/)**, **[Amazon EFS Multi-AZ](https://aws.amazon.com/efs/)**, and **[Amazon S3](https://aws.amazon.com/s3/)**, secured with **[Route 53 & AWS ACM Wildcard SSL](https://aws.amazon.com/certificate-manager/)** (`*.ariphmohd.shop`), and observed with **[Prometheus & Grafana](https://prometheus-community.github.io/helm-charts/)** and **[Datadog APM](https://docs.datadoghq.com/containers/kubernetes/)**.

> 📖 **Comprehensive Engineering Manual**:
> For the complete, deep-dive architectural handbook explaining all 9 stages, component justifications, SRE interview Q&As, and official documentation links, see:
> 👉 **[`docs/ARCHITECTURE_AND_DEPLOYMENT_GUIDE.md`](./docs/ARCHITECTURE_AND_DEPLOYMENT_GUIDE.md)**

---

## 🏛 1. End-to-End System Architecture

```mermaid
flowchart TB
    subgraph Internet ["🌐 Public Internet & Developers"]
        Devs["Developers & SRE Team"]
        DomainUser["Browser Users (HTTPS / Port 443)"]
    end

    subgraph RegistrarDNS ["🌐 DNS & Certificate Management"]
        Registrar["GoDaddy Registrar (ariphmohd.shop)"]
        R53Zone["AWS Route 53 Public Hosted Zone\n• 100% SLA Anycast DNS\n• Subdomains: gitea, grafana, argocd"]
        ACMCert["AWS Certificate Manager (ACM)\n• Free Wildcard TLS 1.3 (*.ariphmohd.shop)\n• Auto-Renewing SSL Certificate"]
    end

    subgraph AWS ["☁️ AWS Cloud (ap-south-1 Mumbai Region)"]
        subgraph PublicSubnets ["Public Subnets (3 Availability Zones)"]
            ALB["AWS Application Load Balancer (Shared Ingress Group)\n• HTTPS: Port 443 (TLS 1.3 Offload)\n• HTTP: Port 80 (Auto-Redirect -> 443)\n• AWS Shield Standard (DDoS Protection)"]
            NAT["NAT Gateway (AZ-a)\n(Outbound Internet for Private Subnets)"]
        end

        subgraph PrivateSubnets ["Private Subnets (3 Availability Zones)"]
            subgraph EKS ["AWS EKS Cluster (3x t4g.small Graviton Nodes)"]
                subgraph CoreAddons ["Cluster Addons & Controllers"]
                    ALBCtrl["AWS Load Balancer Controller"]
                    EFSCtrl["AWS EFS CSI Driver"]
                    VPCCNI["AWS VPC CNI & CoreDNS"]
                end

                subgraph ArgoCDNS ["Namespace: argocd"]
                    ArgoServer["ArgoCD Server UI\n(https://argocd.ariphmohd.shop)"]
                    ArgoCtrl["ArgoCD Application Controller"]
                    ArgoRepo["ArgoCD Repo Server"]
                end

                subgraph GiteaNS ["Namespace: gitea"]
                    GiteaPod["Gitea Application Pod\n(https://gitea.ariphmohd.shop)"]
                    GiteaInit["Init Containers:\n• wait-db • configure-gitea"]
                    GiteaPVC["PVC: gitea-shared-storage\n(50Gi ReadWriteMany)"]
                end

                subgraph MonitoringNS ["Namespace: monitoring"]
                    PromOp["Prometheus Operator"]
                    PromServer["Prometheus Server StatefulSet"]
                    GrafanaApp["Grafana Visualization\n(https://grafana.ariphmohd.shop)"]
                    NodeExp["Node Exporter DaemonSet\n(3x Worker Nodes)"]
                    KSM["Kube-State-Metrics"]
                end

                subgraph DatadogNS ["Namespace: datadog (Optional)"]
                    DDAgent["Datadog Agent DaemonSet\n(APM Traces, Logs & Metrics)"]
                end
            end
        end

        subgraph DBSubnets ["Database Subnets (Isolated)"]
            RDS[("Amazon RDS PostgreSQL\n(db.t4g.micro, Private)")]
            SecretsMgr["AWS Secrets Manager\n(Auto-generated DB Passwords)"]
        end

        subgraph StorageLayer ["Managed Storage Tier"]
            EFS[("Amazon EFS File System\n(Multi-AZ Shared NFS Storage)")]
            S3[("Amazon S3 Bucket\n(LFS Artifacts & Backups)")]
        end
    end

    %% DNS & SSL Flow
    Registrar -->|Nameserver Delegation| R53Zone
    R53Zone -->|Auto-Validates CNAME| ACMCert
    ACMCert -->|Binds TLS 1.3 Cert| ALB
    R53Zone -->|Subdomain Routing| ALB

    %% Network & Traffic Routing
    Devs -->|HTTPS Traffic| ALB
    DomainUser -->|HTTPS Traffic| ALB
    ALB -->|Host: gitea.ariphmohd.shop| GiteaPod
    ALB -->|Host: grafana.ariphmohd.shop| GrafanaApp
    ALB -->|Host: argocd.ariphmohd.shop| ArgoServer

    GiteaPod -->|Port 5432 SQL Queries| RDS
    GiteaPod -->|Mounts /data| GiteaPVC
    GiteaPVC -->|NFS Protocol| EFS
    GiteaPod -->|IAM IRSA Auth| S3

    %% GitOps Automation
    ArgoCtrl -->|Reconciles State| GiteaNS
    ArgoCtrl -->|Reconciles State| MonitoringNS
    ArgoCtrl -->|Reconciles State| DatadogNS

    %% Observability Scraping
    PromServer -->|Scrapes 15s /metrics| GiteaPod
    PromServer -->|Scrapes Node Metrics| NodeExp
    PromServer -->|Scrapes Pod States| KSM
    GrafanaApp -->|Queries Data| PromServer
    DDAgent -->|Collects Logs & APM| GiteaPod
```

---

## 🧩 2. Serial Component Breakdown & Deep Dive

Each component in the platform is engineered to deliver high availability, enterprise security, and cost efficiency.

```mermaid
flowchart LR
    C1["1. Network VPC"] --> C2["2. AWS IAM IRSA"]
    C2 --> C3["3. RDS Database"]
    C3 --> C4["4. EFS & S3 Storage"]
    C4 --> C5["5. EKS Kubernetes"]
    C5 --> C6["6. ArgoCD GitOps"]
    C6 --> C7["7. Gitea Core"]
    C7 --> C8["8. Prometheus & Grafana"]
    C8 --> C9["9. Route 53 & ACM Custom Domain"]
```

---

### 1️⃣ Networking Tier: Custom AWS VPC
* **Official Docs**: [Amazon Virtual Private Cloud Documentation](https://docs.aws.amazon.com/vpc/)
* **Why We Use It**: Complete network isolation across **3 Availability Zones (`ap-south-1a`, `ap-south-1b`, `ap-south-1c`)**.
* **Architecture**:
  * **Public Subnets**: Host the Internet-Facing AWS Application Load Balancer and single NAT Gateway.
  * **Private Subnets**: Host the EKS Worker Nodes and EFS Mount Targets (no direct internet exposure).
  * **Database Subnets**: Fully isolated subnets dedicated strictly to Amazon RDS PostgreSQL.
* **Cost Optimization**: Single shared NAT Gateway in AZ-a saves ~$65/month compared to multi-NAT setups.
* **Dependencies**: AWS Internet Gateway (IGW) and Route Tables.

---

### 2️⃣ Security & Identity: AWS IAM & IRSA (IAM Roles for Service Accounts)
* **Official Docs**: [AWS EKS IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
* **Why We Use It**: Eliminates hardcoded AWS access keys inside Kubernetes pods by binding IAM policies directly to Kubernetes ServiceAccounts via OpenID Connect (OIDC).
* **Where It Operates**:
  * `gitea-prod-alb-controller-irsa-role`: Grants AWS Load Balancer Controller permissions to manage ALBs, target groups, and listener rules.
  * `gitea-prod-efs-csi-irsa-role`: Grants AWS EFS CSI Driver permissions to dynamically create and mount EFS access points.
  * `gitea-prod-gitea-irsa-role`: Grants the Gitea core container permissions to read/write to the Amazon S3 storage bucket.
* **Dependencies**: AWS IAM OIDC Identity Provider on the EKS cluster.

---

### 3️⃣ Relational Database: Amazon RDS PostgreSQL
* **Official Docs**: [Amazon RDS for PostgreSQL](https://aws.amazon.com/rds/postgresql/)
* **Why We Use It**: Fully managed ACID-compliant relational database for Gitea users, repositories, pull requests, issue trackers, and permissions.
* **Where It Operates**: Deployed as an `AWS Graviton db.t4g.micro` instance in private database subnets.
* **Security**: Master database credentials are generated on-the-fly, encrypted with AWS KMS, and stored in **[AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)**.
* **Dependencies**: Database Subnet Group, KMS Encryption Key, and Database Security Group allowing ingress from EKS worker nodes on port `5432`.

---

### 4️⃣ Persistent Storage: Amazon EFS Multi-AZ & Amazon S3
* **Official Docs**: [Amazon Elastic File System (EFS)](https://aws.amazon.com/efs/) & [Amazon Simple Storage Service (S3)](https://aws.amazon.com/s3/)
* **Why We Use It**: Hybrid storage tier decoupling hot Git repositories from cold attachments and backups.
  * **Amazon EFS (Multi-AZ)**: Shared POSIX-compliant NFS file system mounted at `/data` across all 3 Availability Zones with `ReadWriteMany` (RWX) access mode.
  * **Amazon S3**: High-durability object storage for Large File Storage (Git LFS), avatar uploads, and platform backups.
* **Dependencies**: AWS EFS Mount Targets in private subnets and AWS EFS CSI Driver on EKS.

---

### 5️⃣ Compute Engine: Amazon Elastic Kubernetes Service (EKS)
* **Official Docs**: [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/)
* **Why We Use It**: Production Kubernetes control plane (v1.30) managing container lifecycles, self-healing, and auto-scaling.
* **Worker Node Architecture**:
  * 3x **AWS Graviton2 (`t4g.small`)** EC2 instances spanning 3 Availability Zones.
  * Cost: ~$0.0168/hour per node (~$12/month) providing 64-bit ARM architecture with optimal price-performance.
* **Dependencies**: AWS VPC CNI, CoreDNS, and Kube-Proxy add-ons.

---

### 6️⃣ GitOps Engine: ArgoCD
* **Official Docs**: [ArgoCD Official Documentation](https://argo-cd.readthedocs.io/)
* **Why We Use It**: Declarative continuous delivery platform implementing the **App-of-Apps** pattern.
* **Where It Operates**: Watches Helm charts and values in Git and automatically reconciles the live Kubernetes cluster state.
* **Features**: Automated drift detection, self-healing (`selfHeal: true`), and pruning (`prune: true`).
* **Dependencies**: EKS Cluster and Kubernetes API.

---

### 7️⃣ Application Layer: Gitea Enterprise Git Service
* **Official Docs**: [Gitea Documentation](https://docs.gitea.com/)
* **Why We Use It**: Lightweight, ultra-fast self-hosted Git service providing code hosting, code review, issue tracking, and webhooks.
* **Container Lifecycle**:
  ```mermaid
  sequenceDiagram
      autonumber
      participant K8s as Kubernetes Kubelet
      participant Init1 as init: wait-for-db
      participant Init2 as init: configure-gitea
      participant Core as container: gitea (Core)
      participant RDS as Amazon RDS PostgreSQL
      participant EFS as Amazon EFS (/data)

      K8s->>Init1: Boot wait-for-db container
      Init1->>RDS: TCP Ping on Port 5432
      RDS-->>Init1: Connection Established
      Init1-->>K8s: Exit 0 (Success)

      K8s->>Init2: Boot configure-gitea container
      Init2->>EFS: Generate /data/gitea/conf/app.ini
      Init2->>RDS: Sync admin user (gitea_admin)
      Init2-->>K8s: Exit 0 (Success)

      K8s->>Core: Boot main Gitea container
      Core->>EFS: Mount repositories & sessions
      Core->>RDS: Execute database migrations
      Core-->>K8s: HTTP 200 on /api/v1/version (Readiness Passed)
  ```
* **Dependencies**: Amazon RDS PostgreSQL, Amazon EFS PVC, and Kubernetes Secrets.

---

### 8️⃣ Observability: Prometheus, Grafana & Datadog
* **Official Docs**: [Prometheus](https://prometheus.io/), [Grafana](https://grafana.com/), [Datadog](https://docs.datadoghq.com/)
* **Prometheus Operator**: Automates scraping of EKS worker nodes (Node-Exporter), Kubernetes pod lifecycles (Kube-State-Metrics), Kubelet container metrics (cAdvisor), and Gitea `/metrics` on port 3000.
* **Grafana Dashboards**: Pre-loaded with official **Gitea Overview Dashboard (#14757)** and Kubernetes Cluster Health dashboards.
* **Datadog Agent**: Optional DaemonSet collecting distributed APM traces and unified container logs.

---

### 9️⃣ Custom Domain, Route 53 & AWS Certificate Manager (ACM)
* **Official Docs**: [Amazon Route 53](https://docs.aws.amazon.com/route53/) & [AWS Certificate Manager (ACM)](https://docs.aws.amazon.com/acm/)
* **Why We Use It**: Enables production HTTPS endpoints with custom domains (`ariphmohd.shop`) backed by auto-renewing SSL/TLS 1.3 certificates.
* **Security & Ingress Architecture**:
  * **AWS ACM Wildcard Certificate**: Single certificate covering `ariphmohd.shop` and `*.ariphmohd.shop` at **$0.00 / month**.
  * **Shared ALB Ingress Group (`group.name: platform`)**: Consolidates `gitea`, `grafana`, and `argocd` under **ONE single Application Load Balancer** (saving ~$36/month).
  * **Automated Redirection**: Port 80 (HTTP) automatically 301-redirects to Port 443 (HTTPS).
  * **DDoS Mitigation**: Built-in Layer 3/4 protection via **AWS Shield Standard**.

---

## 📂 3. Repository Directory Structure

```
gitea-platform/
├── argocd/
│   ├── env.conf.example             # Central configuration file for single-point edits
│   ├── root-application.yaml        # App-of-Apps root sync manifest
│   ├── applications/                # Independent ArgoCD Application CRDs
│   │   ├── gitea-app.yaml           # Gitea GitOps application definition
│   │   ├── monitoring-app.yaml      # Prometheus & Grafana stack application
│   │   └── datadog-app.yaml         # Datadog Agent application
│   └── values/                      # Modular Helm values
│       ├── gitea-values.yaml        # Gitea configuration (DB, S3, EFS, Ingress)
│       ├── monitoring-values.yaml   # Prometheus scraping & Grafana credentials
│       └── datadog-values.yaml      # Datadog APM, logs, and container metrics
├── terraform/
│   ├── modules/
│   │   ├── vpc/                     # 3-AZ VPC, subnets, IGW, 1 NAT Gateway
│   │   ├── eks/                     # EKS 1.30, 3 worker nodes, addons, OIDC
│   │   ├── rds/                     # db.t4g.micro PostgreSQL, Secrets Manager
│   │   ├── storage/                 # EFS Multi-AZ & S3 storage bucket
│   │   └── iam/                     # IRSA roles for Gitea, ALB Controller, EFS
│   ├── custom-domain/               # 🌐 Standalone Route 53 & ACM Wildcard Module
│   │   ├── providers.tf             # AWS provider (ap-south-1)
│   │   ├── variables.tf             # Domain name (ariphmohd.shop) & subdomains
│   │   ├── main.tf                  # Route 53 Zone, ACM Cert, DNS validation
│   │   └── outputs.tf               # 4 Name Servers & Certificate ARN
│   ├── providers.tf                 # Base AWS, Helm, Kubernetes providers
│   ├── variables.tf                 # Configurable variables (defaults to ap-south-1)
│   ├── main.tf                      # Root orchestration & module linkage
│   ├── outputs.tf                   # Endpoints, ARNs, and connection strings
│   └── terraform.tfvars.example     # Example variable assignments
├── k8s/
│   ├── efs-storageclass.yaml        # Dynamic EFS Provisioner StorageClass
│   ├── alb-ingress.yaml             # Base AWS ALB Ingress
│   └── custom-domain-ingress.yaml   # Multi-Subdomain Shared ALB Ingress (HTTPS: 443)
├── scripts/
│   ├── 01-infra-terraform.sh        # Stage 1: Terraform Cloud Infrastructure
│   ├── 02-eks-bootstrap.sh          # Stage 2: AWS EKS Drivers & Core CRDs
│   ├── 03-deploy-argocd.sh          # Stage 3: ArgoCD Server & CLI Setup
│   ├── 04-deploy-gitea.sh           # Stage 4: Gitea Application GitOps Pipeline
│   ├── 05-deploy-monitoring.sh      # Stage 5: Prometheus & Grafana Stack
│   ├── 06-deploy-datadog.sh         # Stage 6: Datadog Observability Stack
│   ├── 07-setup-custom-domain.sh    # Stage 7: Custom Domain Setup & Multi-Host HTTPS
│   ├── reset-stage4.sh              # Fast 5-second teardown for Stage 4
│   ├── reset-stage5.sh              # Fast 5-second teardown for Stage 5
│   └── destroy.sh                   # Full AWS Cloud infrastructure teardown
├── .gitignore                       # Prevents secret leaks (tfstate, env.conf)
└── README.md                        # Platform documentation & operational guide
```

---

## 🚀 4. Deployment Pipeline (Stage-by-Stage)

```mermaid
flowchart LR
    S1["Stage 1: Terraform\n(Infra Provisioning)"] --> S2["Stage 2: EKS Bootstrap\n(CSI & ALB Drivers)"]
    S2 --> S3["Stage 3: ArgoCD\n(GitOps Engine)"]
    S3 --> S4["Stage 4: Gitea App\n(Git Platform & ALB)"]
    S4 --> S5["Stage 5: Monitoring\n(Prometheus & Grafana)"]
    S5 --> S6["Stage 6: Datadog\n(APM & Logs)"]
    S6 --> S7["Stage 7: Custom Domain\n(Route 53 & Wildcard HTTPS)"]
```

### 📋 Step 0: Prerequisites
1. **[AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)** configured (`aws configure` with region `ap-south-1`).
2. **[Terraform (>= 1.5.0)](https://developer.hashicorp.com/terraform/downloads)**
3. **[kubectl (>= 1.29)](https://kubernetes.io/docs/tasks/tools/)**
4. **[Helm v3](https://helm.sh/docs/intro/install/)**

---

### ☕ Stage 1: Deploy Cloud Infrastructure (Terraform)
Provisions the VPC, 3-node EKS cluster, RDS PostgreSQL, Multi-AZ EFS, S3 bucket, and IAM roles.

```bash
cd gitea-platform
./scripts/01-infra-terraform.sh
```

---

### 🔧 Stage 2: Bootstrap EKS Cluster & Drivers
Installs the AWS EFS CSI Driver, AWS Load Balancer Controller, and StorageClasses.

```bash
./scripts/02-eks-bootstrap.sh
```

---

### 🐙 Stage 3: Deploy ArgoCD GitOps Engine
Deploys ArgoCD and configures the initial administrative credentials.

```bash
./scripts/03-deploy-argocd.sh
```

---

### ☕ Stage 4: Deploy Gitea Application
Deploys Gitea via ArgoCD, binds the 50Gi Multi-AZ EFS volume, initializes RDS, and allocates the public AWS Application Load Balancer.

```bash
./scripts/04-deploy-gitea.sh
```

---

### 📈 Stage 5: Deploy Prometheus & Grafana Monitoring Stack
Installs Prometheus Operator, scrapes Gitea and EKS node metrics, and provisions Grafana with pre-loaded dashboards.

```bash
./scripts/05-deploy-monitoring.sh
```

---

### 🐶 Stage 6: Deploy Datadog Observability *(Optional)*
Configures the Datadog Agent DaemonSet on all 3 worker nodes.

```bash
# Add your API key in argocd/env.conf, then run:
./scripts/06-deploy-datadog.sh
```

---

### 🌐 Stage 7: Setup Custom Domain & Multi-Host HTTPS Ingress *(Standalone)*
Provisions the Route 53 zone, issues the wildcard ACM SSL certificate (`*.ariphmohd.shop`), displays GoDaddy nameserver instructions, and binds all subdomains to the shared ALB.

```bash
./scripts/07-setup-custom-domain.sh
```

---

### 📦 Stage 8: Provision Amazon ECR Private Container Registry
Provisions the private, KMS-encrypted container registry `gitea-custom` in `ap-south-1` with automatic CVE vulnerability scanning on push and automated lifecycle cleanup:

```bash
./scripts/08-provision-ecr.sh
```

---

### 🔐 Stage 9: Configure GitHub Actions AWS OIDC & Automated GitOps Pipeline
Configures passwordless, zero-static-key authentication between GitHub Actions and AWS STS, and activates the automated GitOps continuous delivery pipeline to ArgoCD.

```bash
./scripts/09-setup-github-oidc.sh
```

#### ❓ Why Are We Using AWS OIDC (OpenID Connect)?
* **🔴 The Old, Dangerous Way**: Storing permanent `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitHub repository settings. If those keys leak or get exposed, attackers gain permanent access to your AWS account.
* **🟢 The Modern Gold-Standard Way**: **Zero static keys exist anywhere!** GitHub acts as an identity provider. When a workflow runs, GitHub generates a cryptographically signed token. AWS STS validates the token and issues temporary, 1-hour credentials that automatically self-destruct after the build.

#### ❓ Why Do We Need the `GITOPS_PAT` Token?
In an enterprise GitOps setup, we maintain **two isolated repositories**:
1. **`ariphmohd/gitea`** *(App Repo)*: Houses the Go source code & Dockerfile.
2. **`ariphmohd/gitea-platform`** *(GitOps Repo)*: Houses the Helm values & ArgoCD manifests.

By default, GitHub security isolates repositories so workflows in Repo 1 cannot modify files in Repo 2. When Repo 1 builds a new container image and pushes it to Amazon ECR, it needs to update the image tag in `argocd/values/gitea-values.yaml` in Repo 2. The **`GITOPS_PAT` (Personal Access Token)** acts as the permission key allowing Repo 1 to update Repo 2, triggering ArgoCD to deploy the new image to EKS with zero downtime!

#### 📋 1-Time GitHub Secret Setup Guide (Takes 1 Minute):
1. **Generate Personal Access Token (PAT)**:
   - Go to: [https://github.com/settings/tokens](https://github.com/settings/tokens)
   - Click **Generate new token (classic)** $\rightarrow$ Note: `gitops-token` $\rightarrow$ Check **`repo`** scope $\rightarrow$ Click **Generate token** and copy `ghp_...`.
2. **Add Secret to your App Repository (`ariphmohd/gitea`)**:
   - Go to: `https://github.com/ariphmohd/gitea/settings/secrets/actions`
   - Click **New repository secret** $\rightarrow$ Name: **`GITOPS_PAT`** $\rightarrow$ Value: *Paste token* $\rightarrow$ Click **Add secret**.
3. **Trigger Workflow**:
   - Push any commit to `ariphmohd/gitea` (or click **Run workflow** in GitHub Actions), and watch ArgoCD roll out your custom image to EKS!

---

## 🌐 5. Production Service Access & Verification Guide

> [!TIP]
> **Zero-Plaintext Security & Mandatory First-Login Password Change**:
> Passwords are dynamically generated at deployment time into native Kubernetes Secrets. Each application requires you to set your permanent private password immediately upon first login (NIST 800-63B compliant).

| Service | Access Type | Production HTTPS / Local URL | Initial Username & Temporary Password Retrieval |
| :--- | :--- | :--- | :--- |
| **☕ Gitea Web UI** | **Custom Domain (HTTPS)** | [https://gitea.ariphmohd.shop](https://gitea.ariphmohd.shop) | **User**: `gitea_admin`<br>**Get Temp Password**: `kubectl -n gitea get secret gitea-admin-secret -o jsonpath="{.data.password}" \| base64 -d`<br>*(Mandatory change on first login)* |
| **📈 Grafana Dashboards** | **Custom Domain (HTTPS)** | [https://grafana.ariphmohd.shop](https://grafana.ariphmohd.shop) | **User**: `admin`<br>**Get Temp Password**: `kubectl -n monitoring get secret grafana-admin-credentials -o jsonpath="{.data.admin-password}" \| base64 -d`<br>*(Prompted to change on first login)* |
| **🐙 ArgoCD GitOps** | **Custom Domain (HTTPS)** | [https://argocd.ariphmohd.shop](https://argocd.ariphmohd.shop) | **User**: `admin`<br>**Get Temp Password**: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d`<br>*(Update via User Info or `argocd account update-password`)* |
| **🔍 Prometheus Targets** | Port-Forward | `kubectl port-forward svc/prometheus-operated -n monitoring 9090:9090`<br>URL: `http://localhost:9090/targets` | *No Authentication Required* |
| **☕ Gitea (Local Fallback)** | Port-Forward | `kubectl port-forward svc/gitea-http -n gitea 3000:3000`<br>URL: `http://localhost:3000` | Same as Gitea credentials |

---

## 🧹 6. Teardown & Reset Utilities

### ⚡ Fast Reset Stage 4 (Gitea Application Teardown - 5 Seconds)
Wipes only the Gitea Kubernetes deployment without touching your AWS infrastructure or RDS database:
```bash
./scripts/reset-stage4.sh
```

### ⚡ Fast Reset Stage 5 (Monitoring Stack Teardown - 5 Seconds)
Wipes only the Prometheus & Grafana stack without touching Gitea or EKS:
```bash
./scripts/reset-stage5.sh
```

### 💥 Complete Cloud Teardown (Destroy All Infrastructure)
Deletes all Kubernetes resources, RDS databases, EFS storage, EKS clusters, and VPCs to prevent ongoing AWS billing:
```bash
./scripts/destroy.sh
```

---

## 💰 7. Monthly AWS Cost Breakdown

| Component | AWS Resource Type | Monthly Estimate (ap-south-1) | Cost Optimization Strategy |
| :--- | :--- | :---: | :--- |
| **EKS Control Plane** | AWS Managed Kubernetes | $73.00 | High-availability SLA backed control plane |
| **Worker Nodes (3x)** | EC2 `t4g.small` (ARM64) | ~$36.60 | 3-AZ resilience at ~$0.0168/hour per node |
| **Relational Database** | RDS PostgreSQL `db.t4g.micro` | ~$12.50 | Graviton2 processor, private subnet isolation |
| **Network Address Translation** | Single NAT Gateway (AZ-a) | ~$32.00 | Single shared NAT saves ~$65/mo vs multi-NAT |
| **Shared Persistent Storage** | Amazon EFS Multi-AZ (50Gi) | ~$8.00 | Pay-per-use Elastic throughput |
| **Object Storage** | Amazon S3 Standard | ~$0.50 | S3 Intelligent-Tiering for LFS & backups |
| **Application Load Balancer** | AWS ELB (Shared ALB Group) | ~$18.00 | Ingress Grouping shares 1 ALB for Gitea, Grafana, ArgoCD |
| **Route 53 DNS Zone** | Route 53 Hosted Zone | $0.50 | 100% SLA global Anycast DNS for `ariphmohd.shop` |
| **Public SSL/TLS Certificates** | AWS Certificate Manager (ACM) | **$0.00 (Free)** | Free auto-renewing wildcard certificate (`*.ariphmohd.shop`) |
| **DDoS Protection** | AWS Shield Standard | **$0.00 (Free)** | Built-in Layer 3/4 DDoS protection |
| **Total Estimated Cost** | — | **~$181.10 / month** | **Over 60% savings vs standard multi-ALB architectures** |

---

## 📜 8. License & Acknowledgements

* Built with ❤️ for SRE & DevOps teams.
* **Gitea**: Licensed under the [MIT License](https://github.com/go-gitea/gitea/blob/main/LICENSE).
* **Prometheus Community**: Licensed under the [Apache 2.0 License](https://github.com/prometheus-community/helm-charts/blob/main/LICENSE).
