<div align="center">

# 🎼 Orchestra Deployment

Repositorio de infraestructura y despliegue **GitOps** para la plataforma Orchestra.
Aprovisiona AWS con Terraform y despliega la aplicación en Kubernetes mediante GitHub Actions.

![Terraform](https://img.shields.io/badge/Terraform-≥1.0-7B42BC?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-eu--west--3-FF9900?logo=amazon-aws&logoColor=white)
![EKS](https://img.shields.io/badge/EKS-v1.31-326CE5?logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14-336791?logo=postgresql&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub_Actions-2088FF?logo=github-actions&logoColor=white)

</div>

---

## 📋 Índice

- [Arquitectura general](#-arquitectura-general)
- [Requisitos previos](#-requisitos-previos)
- [Estructura del repositorio](#-estructura-del-repositorio)
- [Infraestructura — Terraform](#-infraestructura--terraform)
  - [Dependencias entre módulos](#dependencias-entre-módulos)
  - [Módulo: network](#módulo-network)
  - [Módulo: eks](#módulo-eks)
  - [Módulo: ecr](#módulo-ecr)
  - [Módulo: iam](#módulo-iam)
  - [Módulo: storage](#módulo-storage)
- [Kubernetes](#-kubernetes)
  - [Vista general del clúster](#vista-general-del-clúster)
  - [Despliegues y recursos](#despliegues-y-recursos)
  - [Enrutamiento con ALB](#enrutamiento-con-alb)
  - [RBAC y Service Accounts](#rbac-y-service-accounts)
- [CI/CD — GitHub Actions](#-cicd--github-actions)
  - [Flujo GitOps completo](#flujo-gitops-completo)
  - [Autenticación OIDC](#autenticación-oidc)
- [Secretos requeridos](#-secretos-requeridos)
- [Despliegue paso a paso](#-despliegue-paso-a-paso)
- [Seguridad](#-seguridad)

---

## 🏗 Arquitectura general

Vista de alto nivel de todos los componentes AWS y cómo se relacionan entre sí.

```mermaid
graph TB
    Internet(["🌐 Internet"])

    subgraph AWS ["☁️ AWS — eu-west-3 (París)"]

        subgraph VPC ["🔒 VPC  10.0.0.0/16"]

            subgraph PUB ["Subnets Públicas — eu-west-3a/3b"]
                IGW["🔀 Internet Gateway"]
                NAT["🔁 NAT Gateway + EIP"]
                ALB["⚖️ ALB\norchestra-alb\n(internet-facing)"]
            end

            subgraph APP ["Subnets Privadas — App  10.0.3-4.0/24"]
                EKS["☸️ EKS  cluster_app  v1.31\n━━━━━━━━━━━━━━━━━━\nNode Group: 1–2 nodos\n3 pods backend · 3 pods frontend"]
            end

            subgraph DATA ["Subnets Privadas — Datos  10.0.5-6.0/24"]
                RDS[("🐘 RDS PostgreSQL 14\ndb.t3.micro\npublicly_accessible: false")]
            end
        end

        ECR["📦 ECR\necr-frontend  IMMUTABLE\necr-backend   IMMUTABLE"]
        SM["🔐 Secrets Manager\nCredenciales RDS (rotación auto)"]
        S3["🗄️ S3\nTerraform state\norchestra-bucket-…"]
    end

    Internet -->|"HTTPS"| ALB
    ALB -->|"/ → frontend :80"| EKS
    ALB -->|"/api → backend :8080"| EKS
    EKS -->|"TCP 5432 (SG permitido)"| RDS
    EKS -->|"Pull imágenes"| ECR
    EKS -->|"GetSecretValue (IRSA)"| SM
    APP -.->|"Egress vía NAT"| NAT
    NAT --> IGW
    IGW <--> Internet

    style AWS fill:#f0f7ff,stroke:#0066cc,stroke-width:2px
    style VPC fill:#e8f4e8,stroke:#33a033,stroke-width:1px
    style PUB fill:#fff9e6,stroke:#cc9900,stroke-width:1px
    style APP fill:#e6f0ff,stroke:#0055cc,stroke-width:1px
    style DATA fill:#ffe6e6,stroke:#cc0000,stroke-width:1px
```

| Capa | Tecnología |
|------|------------|
| Infraestructura como código | Terraform ≥ 1.0 · provider AWS `~> 5.0` |
| Orquestación de contenedores | Amazon EKS v1.31 |
| Registro de imágenes | Amazon ECR — 2 repositorios (frontend + backend) |
| Base de datos | Amazon RDS PostgreSQL 14 (`db.t3.micro`) |
| Networking | VPC · IGW · NAT GW · Route Tables · Security Groups |
| Identidad | IAM Roles · OIDC (IRSA + GitHub Actions) |
| Ingress | AWS Load Balancer Controller (ALB) |
| Gestión de secretos | AWS Secrets Manager + Secrets Store CSI Driver |
| CI/CD | GitHub Actions (GitOps) |

---

## ✅ Requisitos previos

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) v2 con credenciales de administrador
- [kubectl](https://kubernetes.io/docs/tasks/tools/) y [Kustomize](https://kustomize.io/)
- [Helm](https://helm.sh/) (para instalar ALB Controller y CSI Driver)
- Bucket S3 `orchestra-bucket-622370466117-eu-west-3-an` creado previamente (backend de Terraform)
- Permisos IAM suficientes para crear VPC, EKS, ECR, RDS e IAM roles

---

## 📁 Estructura del repositorio

```
orchestra-deployment/
├── .github/
│   └── workflows/
│       └── deploy.yaml              # Pipeline GitOps → EKS
├── despliegue/
│   ├── k8s/                         # Manifiestos de Kubernetes
│   │   ├── namespace.yaml           # orchestra-namespace
│   │   ├── backend-deployment.yaml  # 3 réplicas, puerto 8080
│   │   ├── backend-service.yaml
│   │   ├── frontend-deployment.yaml # 3 réplicas, puerto 80 (Nginx)
│   │   ├── frontend-service.yaml
│   │   ├── ingress.yaml             # ALB internet-facing
│   │   ├── rbac.yaml                # Role + RoleBinding CSI Driver
│   │   ├── serviceAccount.yaml      # IRSA backend + frontend
│   │   └── kustomization.yaml       # Gestión dinámica de image tags
│   └── terraform/
│       ├── main.tf                  # Composición de módulos
│       ├── backend.tf               # Estado remoto en S3
│       ├── providers.tf             # AWS provider eu-west-3
│       └── modules/
│           ├── network/             # VPC · Subnets · IGW · NAT · SGs
│           ├── eks/                 # Clúster · Node Group · OIDC
│           ├── ecr/                 # Repositorios de imágenes Docker
│           ├── iam/                 # Roles · Políticas · OIDC providers
│           └── storage/             # RDS PostgreSQL + Subnet Group
└── .gitignore                       # Excluye secretos, tfstate, .env…
```

---

## 🔧 Infraestructura — Terraform

El estado se almacena de forma remota en S3:

```hcl
# despliegue/terraform/backend.tf
bucket = "orchestra-bucket-622370466117-eu-west-3-an"
key    = "proyect/proyect.tfstate"
region = "eu-west-3"
```

### Dependencias entre módulos

`main.tf` actúa como raíz que orquesta los cinco módulos pasando outputs entre ellos:

```mermaid
graph LR
    ROOT(["⚙️ main.tf\nraíz"])

    ROOT --> NET
    ROOT --> STOR
    ROOT --> IAM
    ROOT --> EKS
    ROOT --> ECR

    NET["📡 module.network\n─────────────────\nVPC · Subnets\nIGW · NAT GW · SGs"]
    STOR["🗄️ module.storage\n─────────────────\nRDS PostgreSQL\nSubnet Group"]
    IAM["🔑 module.iam\n─────────────────\nRoles IAM\nOIDC Providers\nPolíticas"]
    EKS["☸️ module.eks\n─────────────────\nClúster EKS\nNode Group\nOIDC Provider"]
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

### Módulo: network

**Ruta:** `despliegue/terraform/modules/network/`

```mermaid
graph TB
    subgraph VPC ["🔒 VPC — 10.0.0.0/16   (DNS support + hostnames activados)"]

        IGW["🔀 Internet Gateway"]

        subgraph AZA ["🟦 eu-west-3a"]
            direction TB
            PUB_A["Subnet Pública\n10.0.1.0/24"]
            APP_A["Subnet App EKS\n10.0.3.0/24"]
            DAT_A["Subnet Datos RDS\n10.0.5.0/24"]
        end

        subgraph AZB ["🟥 eu-west-3b"]
            direction TB
            PUB_B["Subnet Pública\n10.0.2.0/24"]
            APP_B["Subnet App EKS\n10.0.4.0/24"]
            DAT_B["Subnet Datos RDS\n10.0.6.0/24"]
        end

        NAT["🔁 NAT GW + EIP\nen PUB_A"]

        SG_BE["SG: backend\negress all → 0.0.0.0/0"]
        SG_DB["SG: database\ningress TCP:5432 ← SG_BE\negress → VPC local only"]
    end

    IGW <-->|"tráfico público"| PUB_A & PUB_B
    PUB_A --> NAT --> IGW
    APP_A & APP_B -->|"RT privada → NAT"| NAT
    SG_BE -->|"TCP 5432"| SG_DB

    style VPC  fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style AZA  fill:#e3f2fd,stroke:#1976d2
    style AZB  fill:#fce4ec,stroke:#c62828
    style SG_BE fill:#fff9c4,stroke:#f57f17
    style SG_DB fill:#ffe0b2,stroke:#e65100
```

| Recurso | CIDR / Valor |
|---------|-------------|
| VPC | `10.0.0.0/16` |
| Subnets públicas | `10.0.1.0/24`, `10.0.2.0/24` |
| Subnets app (EKS) | `10.0.3.0/24`, `10.0.4.0/24` |
| Subnets datos (RDS) | `10.0.5.0/24`, `10.0.6.0/24` |
| AZs | `eu-west-3a`, `eu-west-3b` |
| SG Backend | Egress total hacia `0.0.0.0/0` |
| SG Database | Ingress solo TCP:5432 desde SG Backend |

---

### Módulo: eks

**Ruta:** `despliegue/terraform/modules/eks/`

```mermaid
graph TB
    subgraph EKS_MOD ["☸️ EKS — cluster_app"]
        CTRL["Control Plane\nEKS v1.31\nauthn: API mode"]
        NG["Node Group: ng-cluster\ndesired: 1 · min: 1 · max: 2"]
        OIDC["OIDC Provider\npara IRSA"]
        ADMIN["Access Entry\neks-venganza → ClusterAdmin"]
    end

    ROLE_CTRL["IAM Role\neks-cluster-role"]
    ROLE_NODE["IAM Role\neks-worker-node-role"]
    SUBNETS["Subnets Privadas App\n10.0.3-4.0/24"]

    ROLE_CTRL --> CTRL
    ROLE_NODE --> NG
    SUBNETS --> CTRL & NG
    CTRL --> OIDC
    CTRL --> ADMIN
    NG --> CTRL

    style EKS_MOD fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
```

| Parámetro | Valor |
|-----------|-------|
| Nombre | `cluster_app` |
| Versión | `1.31` |
| Autenticación | Modo `API` |
| Node Group | `ng-cluster` — desired 1, min 1, max 2 |
| Subnets | Privadas de app (multi-AZ) |
| Admin IAM | `eks-venganza` con `AmazonEKSClusterAdminPolicy` |

---

### Módulo: ecr

**Ruta:** `despliegue/terraform/modules/ecr/`

```mermaid
graph LR
    GHA["GitHub Actions\nCI del repo de app"] -->|"docker push :sha-abc"| ECR_FE & ECR_BE

    subgraph ECR ["📦 Amazon ECR"]
        ECR_FE["ecr-frontend\n──────────────\nIMMUTABLE tags\nscan_on_push ✅"]
        ECR_BE["ecr-backend\n──────────────\nIMMUTABLE tags\nscan_on_push ✅"]
    end

    ECR_FE & ECR_BE -->|"docker pull"| EKS["☸️ EKS Node Group"]

    style ECR fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px
```

> **Tags inmutables:** una vez publicada una imagen con un tag concreto no puede sobreescribirse, garantizando trazabilidad completa y rollbacks seguros.

---

### Módulo: iam

**Ruta:** `despliegue/terraform/modules/iam/`

```mermaid
graph TB
    subgraph GH_OIDC_BOX ["OIDC Provider — GitHub Actions"]
        GH_OIDC["token.actions.githubusercontent.com"]
        GH_ROLE["IAM Role\ngithub-actions-eks-role\ncondición: repo:chelu-cloud/orchestra-deployment:*"]
        GH_POL["AmazonEKSClusterAdminPolicy"]
        GH_ROLE --> GH_POL
        GH_OIDC --> GH_ROLE
    end

    subgraph EKS_OIDC_BOX ["OIDC Provider — EKS / IRSA"]
        EKS_OIDC["OIDC Provider EKS"]
        K8_ROLE["IAM Role\nkubernetes-oidc-role\nIRSA: sa-orchestra-backend"]
        K8_POL["IAM Policy: app-to-db-policy\nGetSecretValue ✅  DescribeSecret ✅"]
        ALB_ROLE["IAM Role\naws-load-balancer-controller-role\nIRSA: aws-load-balancer-controller"]
        ALB_POL["AWSLoadBalancerControllerIAMPolicy"]
        EKS_OIDC --> K8_ROLE --> K8_POL
        EKS_OIDC --> ALB_ROLE --> ALB_POL
    end

    subgraph CLUSTER_ROLES ["Roles del Clúster EKS"]
        CTRL_ROLE["IAM Role: eks-cluster-role\nAmazonEKSClusterPolicy"]
        NODE_ROLE["IAM Role: eks-worker-node-role\nAmazonEKSWorkerNodePolicy\nAmazonEKS_CNI_Policy\nAmazonEC2ContainerRegistryReadOnly"]
    end

    style GH_OIDC_BOX fill:#e8f5e9,stroke:#388e3c,stroke-width:1px
    style EKS_OIDC_BOX fill:#e3f2fd,stroke:#1565c0,stroke-width:1px
    style CLUSTER_ROLES fill:#fff9c4,stroke:#f9a825,stroke-width:1px
```

---

### Módulo: storage

**Ruta:** `despliegue/terraform/modules/storage/`

```mermaid
graph LR
    subgraph RDS_MOD ["🐘 RDS PostgreSQL"]
        DB["postgres-test2\nengine: postgres 14\ninstance: db.t3.micro\n10 GB · publicly_accessible: false"]
        SNG["DB Subnet Group\n10.0.5.0/24 · 10.0.6.0/24"]
        SG_DB["SG: database\nTCP:5432 ← backend SG"]
    end

    SM["🔐 AWS Secrets Manager\nmanage_master_user_password: true\nrotación automática"]
    POD["Pod Backend\nCSI Driver"]

    SNG --> DB
    SG_DB --> DB
    DB -->|"ARN del secreto"| SM
    SM -->|"GetSecretValue IRSA"| POD

    style RDS_MOD fill:#ffebee,stroke:#c62828,stroke-width:2px
    style SM fill:#fff9c4,stroke:#f57f17
```

| Parámetro | Valor |
|-----------|-------|
| Identificador | `postgres-test2` |
| Motor | PostgreSQL 14 |
| Instancia | `db.t3.micro` |
| Almacenamiento | 10 GB |
| Acceso público | `false` |
| Contraseña | Gestionada por AWS Secrets Manager (rotación automática) |

---

## ☸️ Kubernetes

Todos los manifiestos pertenecen al namespace `orchestra-namespace`.

### Vista general del clúster

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
            FE_DEP["Deployment\nfrontend-deployment\n3 réplicas · Nginx :80"]
            FE_SVC["Service\nfrontend-service :8080"]
            SA_FE["ServiceAccount\nsa-orchestra-frontend"]
        end

        subgraph BE ["Backend"]
            BE_DEP["Deployment\nbackend-deployment\n3 réplicas · Spring Boot :8080"]
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
    FE_DEP & BE_DEP -->|"Pull imagen"| ECR
    ROLE --> RB --> CSI
    ALBC -->|"Provisiona"| ALB_AWS

    style NS  fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style KS  fill:#fff3e0,stroke:#e65100,stroke-width:1px
    style FE  fill:#e3f2fd,stroke:#1976d2
    style BE  fill:#fce4ec,stroke:#c62828
```

---

### Despliegues y recursos

| Parámetro | Backend | Frontend |
|-----------|---------|----------|
| Réplicas | 3 | 3 |
| Imagen base | `ecr-backend` | `ecr-frontend` (Nginx) |
| Puerto contenedor | `8080` | `80` |
| CPU request / limit | `250m` / `1` | `250m` / `1` |
| Memory request / limit | `512Mi` / `1Gi` | `512Mi` / `1Gi` |
| Service Account | `sa-orchestra-backend` | `sa-orchestra-frontend` |
| Secretos DB | CSI Driver → `/mnt/secrets-store` | — |

---

### Enrutamiento con ALB

```mermaid
sequenceDiagram
    actor U as 🌐 Usuario
    participant ALB as ⚖️ ALB (orchestra-alb)
    participant FE as frontend-service :8080
    participant BE as backend-service :80

    Note over U,BE: Petición de página web
    U->>ALB: GET /
    ALB->>FE: path Prefix "/"
    FE-->>U: 200 HTML/SPA (Nginx)

    Note over U,BE: Llamada a la API
    U->>ALB: GET /api/concerts
    ALB->>BE: path Prefix "/api"
    BE-->>U: 200 JSON (Spring Boot)

    Note over U,BE: Recurso estático
    U->>ALB: GET /assets/main.js
    ALB->>FE: path Prefix "/"
    FE-->>U: 200 JS (Nginx static)
```

---

### RBAC y Service Accounts

El backend usa **IRSA (IAM Roles for Service Accounts)** para acceder a Secrets Manager sin credenciales estáticas:

```mermaid
sequenceDiagram
    participant POD as Pod Backend
    participant K8 as Kubernetes API
    participant EKS_OIDC as OIDC Provider EKS
    participant IAM as AWS IAM
    participant SM as 🔐 Secrets Manager

    POD->>K8: Token projection (ServiceAccount)
    K8-->>POD: JWT firmado por OIDC
    POD->>IAM: AssumeRoleWithWebIdentity (JWT + kubernetes-oidc-role)
    IAM->>EKS_OIDC: Verificar JWT
    EKS_OIDC-->>IAM: ✅ válido
    IAM-->>POD: Credenciales STS temporales
    POD->>SM: GetSecretValue (ARN del secreto DB)
    SM-->>POD: username + password de RDS
```

**RBAC para el CSI Driver:**

```mermaid
graph LR
    ROLE["Role\ncsi-driver-token-creator\n────────────────────────\nresources: serviceaccounts/token\nverbs: create"]
    RB["RoleBinding\ncsi-driver-token-binding"]
    SA["ServiceAccount\nsecrets-store-csi-driver\n@ kube-system"]
    CSI["DaemonSet CSI Driver"]
    BE["Pod Backend\n/mnt/secrets-store"]

    ROLE --> RB --> SA --> CSI --> BE
```

---

## 🔄 CI/CD — GitHub Actions

**Workflow:** `.github/workflows/deploy.yaml`

| Trigger | Condición |
|---------|-----------|
| `push` a `main` | Solo si hay cambios en `k8s/**` |
| `workflow_dispatch` | Ejecución manual desde GitHub UI |
| `repository_dispatch` | Evento `deploy-trigger` enviado desde el repo de la app |

### Flujo GitOps completo

```mermaid
flowchart TD
    DEV(["👨‍💻 Developer\ngit push a main"])
    APP_REPO["🏗️ Repo de la App\nbuild + test + docker build"]
    ECR_PUSH["📦 docker push\necr-backend:sha-abc123"]
    DISPATCH["📡 repository_dispatch\n{ app_name, image_tag }"]

    subgraph GHA ["🔄 GitHub Actions — orchestra-deployment"]
        A["1️⃣ actions/checkout@v4"]
        B["2️⃣ configure-aws-credentials\nOIDC → github-actions-eks-role\nsin Access Keys estáticas"]
        C["3️⃣ aws eks update-kubeconfig\ncluster_app · eu-west-3"]
        D["4️⃣ Inyectar DB_SECRET_ARN\nen secretProviderClass vía sed"]
        E{"¿repository_dispatch?"}
        F["5️⃣ kustomize edit set image\nECR_URL = ECR_URL:sha-abc123"]
        G["6️⃣ kubectl apply -k k8s/"]
    end

    EKS["☸️ EKS cluster_app\nRolling Update\n3 réplicas backend + 3 frontend"]

    DEV -->|"cambio en k8s/**"| A
    DEV -->|"push código app"| APP_REPO
    APP_REPO --> ECR_PUSH --> DISPATCH --> A
    A --> B --> C --> D --> E
    E -->|"Sí"| F --> G
    E -->|"No"| G
    G --> EKS

    style GHA fill:#f0f0ff,stroke:#6666cc,stroke-width:2px
    style EKS fill:#e8f5e9,stroke:#2e7d32
    style ECR_PUSH fill:#f3e5f5,stroke:#6a1b9a
    style DISPATCH fill:#fff9c4,stroke:#f9a825
```

---

### Autenticación OIDC

El proyecto usa OIDC en **dos capas independientes** para eliminar completamente el uso de credenciales AWS de larga duración:

```mermaid
sequenceDiagram
    participant GHA as GitHub Actions
    participant GH_OIDC as OIDC Provider<br/>token.actions.githubusercontent.com
    participant IAM as AWS IAM
    participant EKS_API as EKS API

    rect rgb(232, 245, 233)
        Note over GHA,EKS_API: 🔐 Capa 1 — GitHub Actions → AWS (sin Access Keys)
        GHA->>GH_OIDC: Solicita token OIDC
        GH_OIDC-->>GHA: JWT (sub: repo:chelu-cloud/orchestra-deployment:*)
        GHA->>IAM: AssumeRoleWithWebIdentity (JWT)
        IAM-->>GHA: Credenciales STS temporales
        GHA->>EKS_API: kubectl apply (credenciales STS)
        EKS_API-->>GHA: ✅ Despliegue aplicado
    end

    rect rgb(227, 242, 253)
        Note over GHA,EKS_API: 🔐 Capa 2 — Pod Backend → Secrets Manager (IRSA)
        participant POD as Pod Backend
        participant EKS_OIDC as OIDC Provider EKS
        participant SM as Secrets Manager

        POD->>EKS_OIDC: Token del ServiceAccount
        EKS_OIDC-->>POD: JWT firmado
        POD->>IAM: AssumeRoleWithWebIdentity → kubernetes-oidc-role
        IAM-->>POD: Credenciales STS temporales
        POD->>SM: GetSecretValue (ARN secreto DB)
        SM-->>POD: username + password
    end
```

---

## 🔑 Secretos requeridos

Configura en **GitHub → Settings → Secrets and variables → Actions:**

| Secreto | Descripción | Cómo obtenerlo |
|---------|-------------|----------------|
| `AWS_DB_SECRET_ARN` | ARN del secreto de RDS en Secrets Manager | Output `db_secret_arn_final` de `terraform apply` |

> ℹ️ **No se necesitan** `AWS_ACCESS_KEY_ID` ni `AWS_SECRET_ACCESS_KEY`. La autenticación a AWS se gestiona mediante OIDC.

---

## 🚀 Despliegue paso a paso

### 1 — Aprovisionar infraestructura con Terraform

```bash
cd despliegue/terraform

# Inicializar — descarga providers y configura backend S3
terraform init

# Revisar el plan antes de aplicar
terraform plan

# Aprovisionar
terraform apply
```

> Anota el output `db_secret_arn_final` y configúralo como secreto `AWS_DB_SECRET_ARN` en GitHub.

### 2 — Conectar kubectl al clúster

```bash
aws eks update-kubeconfig --name cluster_app --region eu-west-3
kubectl get nodes   # verificar nodos en estado Ready
```

### 3 — Instalar componentes del clúster (Helm)

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

### 4 — Desplegar manifiestos de Kubernetes

El despliegue se ejecuta **automáticamente vía GitHub Actions**. Para un despliegue manual:

```bash
cd despliegue/k8s
kubectl apply -k .
```

### 5 — Verificar el despliegue

```bash
# Ver pods en ejecución
kubectl get pods -n orchestra-namespace

# Ver servicios e ingress
kubectl get svc,ingress -n orchestra-namespace

# Obtener URL pública del ALB
kubectl get ingress orchestra-ingress -n orchestra-namespace \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Ver logs del backend
kubectl logs -l app=backend-deployment -n orchestra-namespace --tail=50
```

---

## 🛡 Seguridad

```mermaid
mindmap
  root((🛡 Seguridad))
    Sin credenciales estáticas
      GitHub Actions usa OIDC
      Pods usan IRSA
      STS temporales
    Secrets Manager
      Contraseña RDS gestionada por AWS
      Rotación automática
      Sin valores en manifiestos
    Red aislada
      RDS en subnet privada
      publicly_accessible false
      SG DB solo TCP:5432 desde SG Backend
      Subnets datos sin ruta a internet
    Imágenes inmutables
      ECR IMMUTABLE tags
      Escaneo on push
      Rollbacks seguros
    gitignore estricto
      Excluye pem key env
      Excluye terraform.tfvars
      Excluye credentials y secrets
    RBAC mínimo
      CSI Driver solo crea tokens SA
      Namespaces aislados
      ServiceAccounts dedicados
```

| Medida | Detalle |
|--------|---------|
| 🔑 Sin credenciales estáticas | GitHub Actions y pods EKS se autentican via OIDC/IRSA |
| 🔐 Secrets Manager | Credenciales de RDS rotadas por AWS; nunca en texto plano |
| 🌐 Red aislada | RDS en subnets privadas; SG de BD solo acepta TCP:5432 desde SG backend |
| 📦 Imágenes inmutables | ECR con `IMMUTABLE` tags y escaneo automático de vulnerabilidades |
| 🚫 `.gitignore` estricto | Excluidos: `*.pem`, `*.key`, `*credentials*`, `terraform.tfvars`, `.env` |
| 🔒 RBAC mínimo | El CSI Driver solo tiene permiso de crear tokens de ServiceAccount |

---

<div align="center">

**Orchestra Deployment** · Infraestructura gestionada con Terraform · Despliegues con GitOps

Developed with ❤️ by chelucloud / cheludev (my other github) · [LinkedIn](https://www.linkedin.com/in/jose-luis-salvador-martin-b88ba3292/)

</div>