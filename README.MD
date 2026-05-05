<div align="center">

# 🎼 Orchestra Deployment

**GitOps** infrastructure and deployment repository for the Orchestra platform.
Provisions AWS with Terraform and deploys the application on Kubernetes via GitHub Actions.

![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-eu--west--3-FF9900?logo=amazon-aws&logoColor=white)
![EKS](https://img.shields.io/badge/EKS-v1.31-326CE5?logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-336791?logo=postgresql&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=github-actions&logoColor=white)

</div>

---

## 📋 Table of Contents

- [General Architecture](#-general-architecture)
- [Prerequisites](#-prerequisites)
- [Repository Structure](#-repository-structure)
- [Infrastructure — Terraform](#-infrastructure--terraform)
  - [Module Dependencies](#module-dependencies)
  - [Module: network](#module-network)
  - [Module: eks](#module-eks)
  - [Module: ecr](#module-ecr)
  - [Module: iam](#module-iam)
  - [Module: storage](#module-storage)
- [Kubernetes](#-kubernetes)
  - [Cluster Overview](#cluster-overview)
  - [Deployments & Resources](#deployments--resources)
  - [ALB Routing](#alb-routing)
  - [RBAC & Service Accounts](#rbac--service-accounts)
- [CI/CD — GitHub Actions](#-cicd--github-actions)
  - [Full GitOps Flow](#full-gitops-flow)
  - [OIDC Authentication](#oidc-authentication)
- [Required Secrets](#-required-secrets)
- [Step-by-Step Deployment](#-step-by-step-deployment)
- [Security](#-security)

---

## 🏗 General Architecture

High-level view of all AWS components and how they relate to each other.

```mermaid
graph TB
    Internet(["🌐 Internet"])

    subgraph AWS ["☁️ AWS — eu-west-3 (Paris)"]

        subgraph VPC ["🔒 VPC  10.0.0.0/16"]

            subgraph PUB ["Public Subnets — eu-west-3a/3b"]
                IGW["🔀 Internet Gateway"]
                NAT["🔁 NAT Gateway + EIP"]
                ALB["⚖️ ALB\norchestra-alb\n(internet-facing)"]
            end

            subgraph APP ["Private Subnets — App  10.0.3-4.0/24"]
                EKS["☸️ EKS  cluster_app  v1.31\n━━━━━━━━━━━━━━━━━━\nNode Group: 1–2 nodes\n3 backend pods · 3 frontend pods"]
            end

            subgraph DATA ["Private Subnets — Data  10.0.5-6.0/24"]
                RDS[("🐘 RDS PostgreSQL 14\ndb.t3.micro\npublicly_accessible: false")]
            end
        end

        ECR["📦 ECR\necr-frontend  IMMUTABLE\necr-backend   IMMUTABLE"]
        SM["🔐 Secrets Manager\nRDS credentials (auto-rotation)"]
        S3["🗄️ S3\nTerraform state\norchestra-bucket-…"]
    end

    Internet -->|"HTTPS"| ALB
    ALB -->|"/ → frontend :80"| EKS
    ALB -->|"/api → backend :8080"| EKS
    EKS -->|"TCP 5432 (SG allowed)"| RDS
    EKS -->|"Pull images"| ECR
    EKS -->|"GetSecretValue (IRSA)"| SM
    APP -.->|"Egress via NAT"| NAT
    NAT --> IGW
    IGW <--> Internet

    style AWS fill:#f0f7ff,stroke:#0066cc,stroke-width:2px
    style VPC fill:#e8f4e8,stroke:#33a033,stroke-width:1px
    style PUB fill:#fff9e6,stroke:#cc9900,stroke-width:1px
    style APP fill:#e6f0ff,stroke:#0055cc,stroke-width:1px
    style DATA fill:#ffe6e6,stroke:#cc0000,stroke-width:1px
```

| Layer | Technology |
|-------|------------|
| Infrastructure as Code | Terraform ≥ 1.0 · AWS provider `~> 5.0` |
| Container Orchestration | Amazon EKS v1.31 |
| Image Registry | Amazon ECR — 2 repositories (frontend + backend) |
| Database | Amazon RDS PostgreSQL 14 (`db.t3.micro`) |
| Networking | VPC · IGW · NAT GW · Route Tables · Security Groups |
| Identity | IAM Roles · OIDC (IRSA + GitHub Actions) |
| Ingress | AWS Load Balancer Controller (ALB) |
| Secret Management | AWS Secrets Manager + Secrets Store CSI Driver |
| CI/CD | GitHub Actions (GitOps) |

---

## ✅ Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) v2 configured with admin credentials
- [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Kustomize](https://kustomize.io/)
- [Helm](https://helm.sh/) (to install ALB Controller and CSI Driver)
- S3 bucket `orchestra-bucket-622370466117-eu-west-3-an` created beforehand (Terraform backend)
- IAM permissions to create VPC, EKS, ECR, RDS, and IAM roles

---

## 📁 Repository Structure

```
orchestra-deployment/
├── .github/
│   └── workflows/
│       └── deploy.yaml              # GitOps pipeline → EKS
├── despliegue/
│   ├── k8s/                         # Kubernetes manifests
│   │   ├── namespace.yaml           # orchestra-namespace
│   │   ├── backend-deployment.yaml  # 3 replicas, port 8080
│   │   ├── backend-service.yaml
│   │   ├── frontend-deployment.yaml # 3 replicas, port 80 (Nginx)
│   │   ├── frontend-service.yaml
│   │   ├── ingress.yaml             # internet-facing ALB
│   │   ├── rbac.yaml                # Role + RoleBinding CSI Driver
│   │   ├── serviceAccount.yaml      # IRSA backend + frontend
│   │   └── kustomization.yaml       # Dynamic image tag management
│   └── terraform/
│       ├── main.tf                  # Module composition
│       ├── backend.tf               # Remote state in S3
│       ├── providers.tf             # AWS provider eu-west-3
│       └── modules/
│           ├── network/             # VPC · Subnets · IGW · NAT · SGs
│           ├── eks/                 # Cluster · Node Group · OIDC
│           ├── ecr/                 # Docker image repositories
│           ├── iam/                 # Roles · Policies · OIDC providers
│           └── storage/             # RDS PostgreSQL + Subnet Group
└── .gitignore                       # Excludes secrets, tfstate, .env…
```

---

## 🔧 Infrastructure — Terraform

State is stored remotely in S3:

```hcl
# despliegue/terraform/backend.tf
bucket = "orchestra-bucket-622370466117-eu-west-3-an"
key    = "proyect/proyect.tfstate"
region = "eu-west-3"
```

### Module Dependencies

`main.tf` acts as the root that orchestrates all five modules, passing outputs between them:

```mermaid
graph LR
    ROOT(["⚙️ main.tf\nroot"])

    ROOT --> NET
    ROOT --> STOR
    ROOT --> IAM
    ROOT --> EKS
    ROOT --> ECR

    NET["📡 module.network\n─────────────────\nVPC · Subnets\nIGW · NAT GW · SGs"]
    STOR["🗄️ module.storage\n─────────────────\nRDS PostgreSQL\nSubnet Group"]
    IAM["🔑 module.iam\n─────────────────\nIAM Roles\nOIDC Providers\nPolicies"]
    EKS["☸️ module.eks\n─────────────────\nEKS Cluster\nNode Group\nOIDC Provider"]
    ECR["📦 module.ecr\n─────────────────\necr-frontend\necr-backend"]

    NET -->|"private_data_subnet_ids\ndb_security_group_id"| STOR
    NET -->|"private_app_subnet_ids"| EKS
    IAM -->|"eks_cluster_role\neks_worker_node_role"| EKS
    EKS -->|"oidc_provider_arn\noidc_provider_url"| IAM
    STOR -->|"db_arn"| IAM

    style ROOT fill:#ffd700,stroke:#996600,color:#000,font-weight:bold
    style NET  fill:#c8e6c9,stroke:#388e3c
    style STOR fill:#ffcdd2,stroke:#c62828
    style IAM  fill:#fff9c4,stroke:#f9a825
    style EKS  fill:#bbdefb,stroke:#1565c0
    style ECR  fill:#e1bee7,stroke:#6a1b9a
```

---

### Module: network

**Path:** `despliegue/terraform/modules/network/`

```mermaid
graph TB
    subgraph VPC ["🔒 VPC — 10.0.0.0/16   (DNS support + hostnames enabled)"]

        IGW["🔀 Internet Gateway"]

        subgraph AZA ["🟦 eu-west-3a"]
            direction TB
            PUB_A["Public Subnet\n10.0.1.0/24"]
            APP_A["App Subnet EKS\n10.0.3.0/24"]
            DAT_A["Data Subnet RDS\n10.0.5.0/24"]
        end

        subgraph AZB ["🟥 eu-west-3b"]
            direction TB
            PUB_B["Public Subnet\n10.0.2.0/24"]
            APP_B["App Subnet EKS\n10.0.4.0/24"]
            DAT_B["Data Subnet RDS\n10.0.6.0/24"]
        end

        NAT["🔁 NAT GW + EIP\nin PUB_A"]

        SG_BE["SG: backend\negress all → 0.0.0.0/0"]
        SG_DB["SG: database\ningress TCP:5432 ← SG_BE\negress → VPC local only"]
    end

    IGW <-->|"public traffic"| PUB_A & PUB_B
    PUB_A --> NAT --> IGW
    APP_A & APP_B -->|"private RT → NAT"| NAT
    SG_BE -->|"TCP 5432"| SG_DB

    style VPC  fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style AZA  fill:#e3f2fd,stroke:#1976d2
    style AZB  fill:#fce4ec,stroke:#c62828
    style SG_BE fill:#fff9c4,stroke:#f57f17
    style SG_DB fill:#ffe0b2,stroke:#e65100
```

| Resource | CIDR / Value |
|----------|-------------|
| VPC | `10.0.0.0/16` |
| Public subnets | `10.0.1.0/24`, `10.0.2.0/24` |
| App subnets (EKS) | `10.0.3.0/24`, `10.0.4.0/24` |
| Data subnets (RDS) | `10.0.5.0/24`, `10.0.6.0/24` |
| AZs | `eu-west-3a`, `eu-west-3b` |
| SG Backend | Full egress to `0.0.0.0/0` |
| SG Database | Ingress only TCP:5432 from SG Backend |

---

### Module: eks

**Path:** `despliegue/terraform/modules/eks/`

```mermaid
graph TB
    subgraph EKS_MOD ["☸️ EKS — cluster_app"]
        CTRL["Control Plane\nEKS v1.31\nauthn: API mode"]
        NG["Node Group: ng-cluster\ndesired: 1 · min: 1 · max: 2"]
        OIDC["OIDC Provider\nfor IRSA"]
        ADMIN["Access Entry\neks-venganza → ClusterAdmin"]
    end

    ROLE_CTRL["IAM Role\neks-cluster-role"]
    ROLE_NODE["IAM Role\neks-worker-node-role"]
    SUBNETS["Private App Subnets\n10.0.3-4.0/24"]

    ROLE_CTRL --> CTRL
    ROLE_NODE --> NG
    SUBNETS --> CTRL & NG
    CTRL --> OIDC
    CTRL --> ADMIN
    NG --> CTRL

    style EKS_MOD fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
```

| Parameter | Value |
|-----------|-------|
| Name | `cluster_app` |
| Version | `1.31` |
| Authentication | `API` mode |
| Node Group | `ng-cluster` — desired 1, min 1, max 2 |
| Subnets | Private app subnets (multi-AZ) |
| IAM Admin | `eks-venganza` with `AmazonEKSClusterAdminPolicy` |

---

### Module: ecr

**Path:** `despliegue/terraform/modules/ecr/`

```mermaid
graph LR
    GHA["GitHub Actions\nApp repo CI"] -->|"docker push :sha-abc"| ECR_FE & ECR_BE

    subgraph ECR ["📦 Amazon ECR"]
        ECR_FE["ecr-frontend\n──────────────\nIMMUTABLE tags\nscan_on_push ✅"]
        ECR_BE["ecr-backend\n──────────────\nIMMUTABLE tags\nscan_on_push ✅"]
    end

    ECR_FE & ECR_BE -->|"docker pull"| EKS["☸️ EKS Node Group"]

    style ECR fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
```

> **Immutable tags:** once an image is published with a specific tag it cannot be overwritten, ensuring full traceability and safe rollbacks.

---

### Module: iam

**Path:** `despliegue/terraform/modules/iam/`

```mermaid
graph TB
    subgraph GH_OIDC_BOX ["OIDC Provider — GitHub Actions"]
        GH_OIDC["token.actions.githubusercontent.com"]
        GH_ROLE["IAM Role\ngithub-actions-eks-role\ncondition: repo:chelu-cloud/orchestra-deployment:*"]
        GH_POL["AmazonEKSClusterAdminPolicy"]
        GH_ROLE --> GH_POL
        GH_OIDC --> GH_ROLE
    end

    subgraph EKS_OIDC_BOX ["OIDC Provider — EKS / IRSA"]
        EKS_OIDC["EKS OIDC Provider"]
        K8_ROLE["IAM Role\nkubernetes-oidc-role\nIRSA: sa-orchestra-backend"]
        K8_POL["IAM Policy: app-to-db-policy\nGetSecretValue ✅  DescribeSecret ✅"]
        ALB_ROLE["IAM Role\naws-load-balancer-controller-role\nIRSA: aws-load-balancer-controller"]
        ALB_POL["AWSLoadBalancerControllerIAMPolicy"]
        EKS_OIDC --> K8_ROLE --> K8_POL
        EKS_OIDC --> ALB_ROLE --> ALB_POL
    end

    subgraph CLUSTER_ROLES ["EKS Cluster Roles"]
        CTRL_ROLE["IAM Role: eks-cluster-role\nAmazonEKSClusterPolicy"]
        NODE_ROLE["IAM Role: eks-worker-node-role\nAmazonEKSWorkerNodePolicy\nAmazonEKS_CNI_Policy\nAmazonEC2ContainerRegistryReadOnly"]
    end

    style GH_OIDC_BOX fill:#e8f5e9,stroke:#388e3c,stroke-width:1px
    style EKS_OIDC_BOX fill:#e3f2fd,stroke:#1565c0,stroke-width:1px
    style CLUSTER_ROLES fill:#fff9c4,stroke:#f9a825,stroke-width:1px
```

---

### Module: storage

**Path:** `despliegue/terraform/modules/storage/`

```mermaid
graph LR
    subgraph RDS_MOD ["🐘 RDS PostgreSQL"]
        DB["postgres-test2\nengine: postgres 14\ninstance: db.t3.micro\n10 GB · publicly_accessible: false"]
        SNG["DB Subnet Group\n10.0.5.0/24 · 10.0.6.0/24"]
        SG_DB["SG: database\nTCP:5432 ← backend SG"]
    end

    SM["🔐 AWS Secrets Manager\nmanage_master_user_password: true\nauto-rotation enabled"]
    POD["Backend Pod\nCSI Driver"]

    SNG --> DB
    SG_DB --> DB
    DB -->|"secret ARN"| SM
    SM -->|"GetSecretValue IRSA"| POD

    style RDS_MOD fill:#ffebee,stroke:#c62828,stroke-width:2px
    style SM fill:#fff9c4,stroke:#f57f17
```

| Parameter | Value |
|-----------|-------|
| Identifier | `postgres-test2` |
| Engine | PostgreSQL 14 |
| Instance | `db.t3.micro` |
| Storage | 10 GB |
| Public access | `false` |
| Password | Managed by AWS Secrets Manager (auto-rotation) |

---

## ☸️ Kubernetes

All manifests belong to the `orchestra-namespace` namespace.

### Cluster Overview

```mermaid
graph TB
    subgraph KS ["🟠 kube-system"]
        ALBC["Deployment\naws-load-balancer-controller"]
        CSI["DaemonSet\nsecrets-store-csi-driver"]
        SA_ALB["ServiceAccount\naws-load-balancer-controller\nIRSA → ALB role"]
        SA_ALB --> ALBC
    end

    subgraph NS ["🟢 orchestra-namespace"]
        ING["Ingress\norchestra-ingress\nALB internet-facing"]

        subgraph FE ["Frontend"]
            FE_DEP["Deployment\nfrontend-deployment\n3 replicas · Nginx :80"]
            FE_SVC["Service\nfrontend-service :8080"]
            SA_FE["ServiceAccount\nsa-orchestra-frontend"]
        end

        subgraph BE ["Backend"]
            BE_DEP["Deployment\nbackend-deployment\n3 replicas · Spring Boot :8080"]
            BE_SVC["Service\nbackend-service :80"]
            SA_BE["ServiceAccount\nsa-orchestra-backend\nIRSA → kubernetes-oidc-role"]
            VOL["Volume: secrets-store-inline\nCSI Driver → /mnt/secrets-store"]
        end

        ROLE["Role: csi-driver-token-creator"]
        RB["RoleBinding"]
    end

    SM["🔐 Secrets Manager"]
    RDS[("🐘 RDS PostgreSQL\nTCP:5432")]
    ECR["📦 ECR"]
    ALB_AWS["⚖️ AWS ALB\norchestra-alb"]

    ALB_AWS --> ING
    ING -->|"/ → :8080"| FE_SVC --> FE_DEP
    ING -->|"/api → :80"| BE_SVC --> BE_DEP
    SA_FE --> FE_DEP
    SA_BE --> BE_DEP
    BE_DEP -->|"GetSecretValue IRSA"| SM
    BE_DEP -->|"TCP 5432"| RDS
    CSI -->|"/mnt/secrets-store"| VOL --> BE_DEP
    FE_DEP & BE_DEP -->|"Pull image"| ECR
    ROLE --> RB --> CSI
    ALBC -->|"Provisions"| ALB_AWS

    style NS  fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style KS  fill:#fff3e0,stroke:#e65100,stroke-width:1px
    style FE  fill:#e3f2fd,stroke:#1976d2
    style BE  fill:#fce4ec,stroke:#c62828
```

---

### Deployments & Resources

| Parameter | Backend | Frontend |
|-----------|---------|----------|
| Replicas | 3 | 3 |
| Base image | `ecr-backend` | `ecr-frontend` (Nginx) |
| Container port | `8080` | `80` |
| CPU request / limit | `250m` / `1` | `250m` / `1` |
| Memory request / limit | `512Mi` / `1Gi` | `512Mi` / `1Gi` |
| Service Account | `sa-orchestra-backend` | `sa-orchestra-frontend` |
| DB Secrets | CSI Driver → `/mnt/secrets-store` | — |

---

### ALB Routing

```mermaid
sequenceDiagram
    actor U as 🌐 User
    participant ALB as ⚖️ ALB (orchestra-alb)
    participant FE as frontend-service :8080
    participant BE as backend-service :80

    Note over U,BE: Web page request
    U->>ALB: GET /
    ALB->>FE: path Prefix "/"
    FE-->>U: 200 HTML/SPA (Nginx)

    Note over U,BE: API call
    U->>ALB: GET /api/concerts
    ALB->>BE: path Prefix "/api"
    BE-->>U: 200 JSON (Spring Boot)

    Note over U,BE: Static asset
    U->>ALB: GET /assets/main.js
    ALB->>FE: path Prefix "/"
    FE-->>U: 200 JS (Nginx static)
```

---

### RBAC & Service Accounts

The backend uses **IRSA (IAM Roles for Service Accounts)** to access Secrets Manager without static credentials:

```mermaid
sequenceDiagram
    participant POD as Backend Pod
    participant K8 as Kubernetes API
    participant EKS_OIDC as EKS OIDC Provider
    participant IAM as AWS IAM
    participant SM as 🔐 Secrets Manager

    POD->>K8: Token projection (ServiceAccount)
    K8-->>POD: OIDC-signed JWT
    POD->>IAM: AssumeRoleWithWebIdentity (JWT + kubernetes-oidc-role)
    IAM->>EKS_OIDC: Verify JWT
    EKS_OIDC-->>IAM: ✅ valid
    IAM-->>POD: Temporary STS credentials
    POD->>SM: GetSecretValue (DB secret ARN)
    SM-->>POD: RDS username + password
```

**RBAC for the CSI Driver:**

```mermaid
graph LR
    ROLE["Role\ncsi-driver-token-creator\n────────────────────────\nresources: serviceaccounts/token\nverbs: create"]
    RB["RoleBinding\ncsi-driver-token-binding"]
    SA["ServiceAccount\nsecrets-store-csi-driver\n@ kube-system"]
    CSI["CSI Driver DaemonSet"]
    BE["Backend Pod\n/mnt/secrets-store"]

    ROLE --> RB --> SA --> CSI --> BE
```

---

## 🔄 CI/CD — GitHub Actions

**Workflow:** `.github/workflows/deploy.yaml`

| Trigger | Condition |
|---------|-----------|
| `push` to `main` | Only when changes are made under `k8s/**` |
| `workflow_dispatch` | Manual run from GitHub UI |
| `repository_dispatch` | `deploy-trigger` event sent from the app repo |

### Full GitOps Flow

```mermaid
flowchart TD
    DEV(["👨‍💻 Developer\ngit push to main"])
    APP_REPO["🏗️ App Repository\nbuild + test + docker build"]
    ECR_PUSH["📦 docker push\necr-backend:sha-abc123"]
    DISPATCH["📡 repository_dispatch\n{ app_name, image_tag }"]

    subgraph GHA ["🔄 GitHub Actions — orchestra-deployment"]
        A["1️⃣ actions/checkout@v4"]
        B["2️⃣ configure-aws-credentials\nOIDC → github-actions-eks-role\nno static Access Keys"]
        C["3️⃣ aws eks update-kubeconfig\ncluster_app · eu-west-3"]
        D["4️⃣ Inject DB_SECRET_ARN\ninto secretProviderClass via sed"]
        E{"repository_dispatch?"}
        F["5️⃣ kustomize edit set image\nECR_URL = ECR_URL:sha-abc123"]
        G["6️⃣ kubectl apply -k k8s/"]
    end

    EKS["☸️ EKS cluster_app\nRolling Update\n3 backend replicas + 3 frontend"]

    DEV -->|"change in k8s/**"| A
    DEV -->|"push app code"| APP_REPO
    APP_REPO --> ECR_PUSH --> DISPATCH --> A
    A --> B --> C --> D --> E
    E -->|"Yes"| F --> G
    E -->|"No"| G
    G --> EKS

    style GHA fill:#f0f0ff,stroke:#6666cc,stroke-width:2px
    style EKS fill:#e8f5e9,stroke:#2e7d32
    style ECR_PUSH fill:#f3e5f5,stroke:#6a1b9a
    style DISPATCH fill:#fff9c4,stroke:#f9a825
```

---

### OIDC Authentication

The project uses OIDC in **two independent layers** to completely eliminate the use of long-lived AWS credentials:

```mermaid
sequenceDiagram
    participant GHA as GitHub Actions
    participant GH_OIDC as OIDC Provider<br/>token.actions.githubusercontent.com
    participant IAM as AWS IAM
    participant EKS_API as EKS API

    rect rgb(232, 245, 233)
        Note over GHA,EKS_API: 🔐 Layer 1 — GitHub Actions → AWS (no Access Keys)
        GHA->>GH_OIDC: Request OIDC token
        GH_OIDC-->>GHA: JWT (sub: repo:chelu-cloud/orchestra-deployment:*)
        GHA->>IAM: AssumeRoleWithWebIdentity (JWT)
        IAM-->>GHA: Temporary STS credentials
        GHA->>EKS_API: kubectl apply (STS credentials)
        EKS_API-->>GHA: ✅ Deployment applied
    end

    rect rgb(227, 242, 253)
        Note over GHA,EKS_API: 🔐 Layer 2 — Backend Pod → Secrets Manager (IRSA)
        participant POD as Backend Pod
        participant EKS_OIDC as EKS OIDC Provider
        participant SM as Secrets Manager

        POD->>EKS_OIDC: ServiceAccount token
        EKS_OIDC-->>POD: Signed JWT
        POD->>IAM: AssumeRoleWithWebIdentity → kubernetes-oidc-role
        IAM-->>POD: Temporary STS credentials
        POD->>SM: GetSecretValue (DB secret ARN)
        SM-->>POD: username + password
    end
```

---

## 🔑 Required Secrets

Configure in **GitHub → Settings → Secrets and variables → Actions:**

| Secret | Description | How to get it |
|--------|-------------|---------------|
| `AWS_DB_SECRET_ARN` | ARN of the RDS secret in Secrets Manager | `db_secret_arn_final` output from `terraform apply` |

> ℹ️ `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are **not needed**. AWS authentication is handled via OIDC.

---

## 🚀 Step-by-Step Deployment

### 1 — Provision infrastructure with Terraform

```bash
cd despliegue/terraform

# Initialize — downloads providers and configures the S3 backend
terraform init

# Review the plan before applying
terraform plan

# Provision
terraform apply
```

> Note the `db_secret_arn_final` output and set it as the `AWS_DB_SECRET_ARN` secret in GitHub.

### 2 — Connect kubectl to the cluster

```bash
aws eks update-kubeconfig --name cluster_app --region eu-west-3
kubectl get nodes   # verify nodes are in Ready state
```

### 3 — Install cluster components (Helm)

```bash
# AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cluster_app \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Secrets Store CSI Driver
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system \
  --set syncSecret.enabled=true
```

### 4 — Deploy Kubernetes manifests

Deployment runs **automatically via GitHub Actions**. For a manual deployment:

```bash
cd despliegue/k8s
kubectl apply -k .
```

### 5 — Verify the deployment

```bash
# Check running pods
kubectl get pods -n orchestra-namespace

# Check services and ingress
kubectl get svc,ingress -n orchestra-namespace

# Get the public ALB URL
kubectl get ingress orchestra-ingress -n orchestra-namespace \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Tail backend logs
kubectl logs -l app=backend-deployment -n orchestra-namespace --tail=50
```

---

## 🛡 Security

```mermaid
mindmap
  root((🛡 Security))
    No static credentials
      GitHub Actions uses OIDC
      Pods use IRSA
      Temporary STS credentials
    Secrets Manager
      RDS password managed by AWS
      Auto-rotation enabled
      No values in manifests
    Isolated network
      RDS in private subnet
      publicly_accessible false
      DB SG allows only TCP:5432 from backend SG
      Data subnets have no internet route
    Immutable images
      ECR IMMUTABLE tags
      Scan on push
      Safe rollbacks
    Strict gitignore
      Excludes pem key env
      Excludes terraform.tfvars
      Excludes credentials and secrets
    Least privilege RBAC
      CSI Driver only creates SA tokens
      Isolated namespaces
      Dedicated ServiceAccounts per component
```

| Measure | Detail |
|---------|---------|
| 🔑 No static credentials | GitHub Actions and EKS pods authenticate via OIDC/IRSA |
| 🔐 Secrets Manager | RDS credentials rotated by AWS; never stored in plain text |
| 🌐 Isolated network | RDS in private subnets; DB SG only accepts TCP:5432 from backend SG |
| 📦 Immutable images | ECR with `IMMUTABLE` tags and automatic vulnerability scanning |
| 🚫 Strict `.gitignore` | Excluded: `*.pem`, `*.key`, `*credentials*`, `terraform.tfvars`, `.env` |
| 🔒 Least privilege RBAC | CSI Driver only has permission to create ServiceAccount tokens |

---

<div align="center">

**Orchestra Deployment** · Infrastructure managed with Terraform · Deployments with GitOps

Developed with ❤️ by chelucloud / cheludev (my other github) · [LinkedIn](https://www.linkedin.com/in/jose-luis-salvador-martin-b88ba3292/)

</div>