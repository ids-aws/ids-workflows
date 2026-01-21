# Plan CI/CD Multi-environnement (INT → STG → PROD)

## Contexte

- **Branche principale** : `main`
- **Infra** : AWS Fargate (ECS)
- **Registry** : ECR (`857736876208.dkr.ecr.eu-west-1.amazonaws.com`)
- **Config** : Config server externalisé, commun à tous les envs
- **Variables runtime** : Gérées par AWS Fargate (Task Definition)
- **Variables build** : Gérées par GitHub (secrets/variables)
- **Microservices** : 10+ MS → nécessite factorisation
- **Principe** : Build once, deploy everywhere (même image promue entre envs)
- **GitHub Plan** : Organization Free
- **Repo workflows** : PUBLIC (permet cross-repo pour les MS privés)

---

## Phase 1 : Repository central des workflows partagés

> Approche hybride : Reusable Workflows + Composite Actions

### 1.1 Créer le repo `ids-workflows` (PUBLIC)

- [ ] Créer le repo `ids-workflows` — **PUBLIC** (requis pour GitHub Free)
- [ ] Structure :
  ```
  ids-workflows/                    # ← PUBLIC (pas de secrets, juste YAML)
  ├── .github/
  │   └── workflows/
  │       ├── ci.yml               # Reusable: CI pour PR (tests)
  │       ├── build-push.yml       # Reusable: Build + Push ECR
  │       ├── deploy.yml           # Reusable: Deploy sur Fargate
  │       └── promote.yml          # Reusable: Promotion d'image entre envs
  ├── actions/
  │   ├── setup-java/              # Composite: Setup Java 21 + Maven cache
  │   │   └── action.yml
  │   ├── docker-build/            # Composite: Build image multi-arch
  │   │   └── action.yml
  │   ├── ecr-push/                # Composite: Login ECR + Push
  │   │   └── action.yml
  │   └── ecs-deploy/              # Composite: Update ECS service
  │       └── action.yml
  └── README.md                    # Documentation des inputs/outputs
  ```

> **Note sécurité** : Le repo est public mais ne contient AUCUN secret.
> Les secrets restent dans chaque repo MS (privés) ou dans les GitHub Environments.

### 1.2 Définir les inputs/outputs standards

- [ ] Inputs communs :
  - `service-name` : nom du microservice
  - `ecr-repository` : repo ECR
  - `environment` : int/stg/prod
  - `image-tag` : tag de l'image (sha)

---

## Phase 2 : Workflows réutilisables (Reusable Workflows)

### 2.1 Workflow CI (`_ci.yml`)

- [ ] Trigger : `workflow_call`
- [ ] Jobs :
  - Checkout
  - Setup Java 21 + Maven cache
  - Run tests (`./mvnw test`)
  - Build (sans push) pour valider Dockerfile
  - (Optionnel) SonarQube / CodeQL
- [ ] Outputs : `tests-passed: true/false`

### 2.2 Workflow Build & Push (`_build-push.yml`)

- [ ] Trigger : `workflow_call`
- [ ] Inputs : `service-name`, `ecr-repo`
- [ ] Jobs :
  - Login ECR (OIDC)
  - Build image multi-arch
  - Push avec tags `:sha-xxx` et `:int`
- [ ] Outputs : `image-tag`, `image-uri`

### 2.3 Workflow Deploy Fargate (`_deploy-fargate.yml`)

- [ ] Trigger : `workflow_call`
- [ ] Inputs : `service-name`, `environment`, `image-tag`, `cluster-name`
- [ ] Jobs :
  - Update Task Definition avec nouvelle image
  - Update ECS Service
  - Wait for stable
  - Health check
- [ ] Gestion rollback si échec

### 2.4 Workflow Promote Image (`_promote-image.yml`)

- [ ] Trigger : `workflow_call`
- [ ] Inputs : `source-tag`, `target-env`
- [ ] Jobs :
  - Récupérer manifest de l'image source
  - Ajouter tag environnement (`:stg`, `:prod`)
  - Pas de rebuild !

---

## Phase 3 : Configuration GitHub (Organisation)

### 3.1 Secrets organisation (partagés)

- [ ] `AWS_ACCOUNT_ID` : 857736876208
- [ ] `AWS_REGION` : eu-west-1
- [ ] `AWS_ROLE_TO_ASSUME` : rôle OIDC pour GitHub Actions

### 3.2 Variables organisation

- [ ] `ECR_REGISTRY` : 857736876208.dkr.ecr.eu-west-1.amazonaws.com
- [ ] `ECS_CLUSTER_INT` : nom du cluster INT
- [ ] `ECS_CLUSTER_STG` : nom du cluster STG
- [ ] `ECS_CLUSTER_PROD` : nom du cluster PROD

### 3.3 Environments GitHub

- [ ] **int** :
  - Secrets spécifiques INT
  - Pas d'approbation requise
  - Deployment auto sur push main

- [ ] **stg** :
  - Secrets spécifiques STG
  - Approbation optionnelle (1 reviewer)
  - Deployment manuel

- [ ] **prod** :
  - Secrets spécifiques PROD
  - Approbation requise (2+ reviewers)
  - Deployment manuel uniquement

### 3.4 Branch protection (`main`)

- [ ] Require PR before merging
- [ ] Require status checks : `ci` (obligatoire)
- [ ] Require up-to-date branches
- [ ] Require code review (1+ approvals)
- [ ] No bypass allowed

---

## Phase 4 : Implémentation dans chaque microservice

### 4.1 Workflow CI (PR) - `ci.yml`

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
    branches: [main]

jobs:
  ci:
    uses: ids-org/ids-github-workflows/.github/workflows/_ci.yml@main
    with:
      java-version: '21'
    secrets: inherit
```

### 4.2 Workflow Build + Deploy INT - `build-deploy.yml`

```yaml
# .github/workflows/build-deploy.yml
name: Build & Deploy INT
on:
  push:
    branches: [main]

jobs:
  build:
    uses: ids-org/ids-github-workflows/.github/workflows/_build-push.yml@main
    with:
      service-name: iam-ms
      ecr-repository: app/iam-ms
    secrets: inherit

  deploy-int:
    needs: build
    uses: ids-org/ids-github-workflows/.github/workflows/_deploy-fargate.yml@main
    with:
      service-name: iam-ms
      environment: int
      image-tag: ${{ needs.build.outputs.image-tag }}
    secrets: inherit
```

### 4.3 Workflow Deploy STG - `deploy-stg.yml`

```yaml
# .github/workflows/deploy-stg.yml
name: Deploy STG
on:
  workflow_dispatch:
    inputs:
      image-tag:
        description: 'Image tag to deploy (sha-xxx)'
        required: true

jobs:
  promote:
    uses: ids-org/ids-github-workflows/.github/workflows/_promote-image.yml@main
    with:
      source-tag: ${{ inputs.image-tag }}
      target-env: stg
    secrets: inherit

  deploy:
    needs: promote
    uses: ids-org/ids-github-workflows/.github/workflows/_deploy-fargate.yml@main
    with:
      service-name: iam-ms
      environment: stg
      image-tag: ${{ inputs.image-tag }}
    secrets: inherit
```

### 4.4 Workflow Deploy PROD - `deploy-prod.yml`

```yaml
# .github/workflows/deploy-prod.yml
name: Deploy PROD
on:
  workflow_dispatch:
    inputs:
      image-tag:
        description: 'Image tag to deploy (sha-xxx)'
        required: true

jobs:
  deploy:
    uses: ids-org/ids-github-workflows/.github/workflows/_deploy-fargate.yml@main
    with:
      service-name: iam-ms
      environment: prod
      image-tag: ${{ inputs.image-tag }}
    secrets: inherit
    # Environment 'prod' requiert approbation manuelle
```

---

## Phase 5 : Fichiers de config par microservice

### 5.1 Fichier de metadata `.github/service.yml`

```yaml
# Chaque MS définit ses spécificités
service:
  name: iam-ms
  ecr-repository: app/iam-ms
  ecs-service-int: iam-ms-int
  ecs-service-stg: iam-ms-stg
  ecs-service-prod: iam-ms-prod
  health-check-path: /actuator/health
```

---

## Phase 6 : Sécurité AWS (OIDC)

### 6.1 Configurer OIDC AWS ↔ GitHub

- [ ] Créer Identity Provider dans IAM pour GitHub Actions
- [ ] Créer rôle IAM `github-actions-role` avec :
  - Trust policy pour GitHub OIDC
  - Permissions ECR (push/pull)
  - Permissions ECS (update service, describe)
  - Scope par repo/org

### 6.2 Permissions IAM minimales

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:PutImage",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
    "ecr:BatchGetImage",
    "ecr:GetDownloadUrlForLayer"
  ],
  "Resource": "arn:aws:ecr:eu-west-1:857736876208:repository/app/*"
}
```

---

## Résumé du flux final

```
┌─────────────────────────────────────────────────────────────────────┐
│ PR → main                                                           │
│   └── CI (tests obligatoires) ← Bloque merge si échec              │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓ merge
┌─────────────────────────────────────────────────────────────────────┐
│ Push main                                                           │
│   └── Build :sha-abc123 → Push ECR → Deploy INT (auto)             │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓ workflow_dispatch (manuel)
┌─────────────────────────────────────────────────────────────────────┐
│ Deploy STG                                                          │
│   └── Promote image :sha-abc123 → :stg → Deploy STG                │
│       (même image, pas de rebuild)                                  │
└─────────────────────────────────────────────────────────────────────┘
                                    ↓ workflow_dispatch + approbation
┌─────────────────────────────────────────────────────────────────────┐
│ Deploy PROD                                                         │
│   └── Promote image :sha-abc123 → :prod → Deploy PROD              │
│       (même image, approbation 2+ reviewers)                        │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Checklist d'implémentation

### Repo central `ids-workflows` (PUBLIC)
- [ ] Créer le repository PUBLIC
- [ ] Créer les composite actions :
  - [ ] `actions/setup-java/action.yml`
  - [ ] `actions/docker-build/action.yml`
  - [ ] `actions/ecr-push/action.yml`
  - [ ] `actions/ecs-deploy/action.yml`
- [ ] Créer les reusable workflows :
  - [ ] `.github/workflows/ci.yml`
  - [ ] `.github/workflows/build-push.yml`
  - [ ] `.github/workflows/deploy.yml`
  - [ ] `.github/workflows/promote.yml`
- [ ] Documenter les inputs/outputs (README)

### Configuration GitHub Organisation
- [ ] Configurer secrets organisation
- [ ] Configurer variables organisation
- [ ] Créer environments (int, stg, prod)
- [ ] Configurer approbations par env

### Configuration AWS
- [ ] Configurer OIDC GitHub ↔ AWS
- [ ] Créer rôle IAM avec permissions minimales
- [ ] Vérifier Task Definitions par env

### Par microservice (iam-ms en premier)
- [ ] Créer `.github/workflows/ci.yml`
- [ ] Créer `.github/workflows/build-deploy.yml`
- [ ] Créer `.github/workflows/deploy-stg.yml`
- [ ] Créer `.github/workflows/deploy-prod.yml`
- [ ] Créer `.github/service.yml` (metadata)
- [ ] Configurer branch protection sur `main`
- [ ] Tester le flux complet

### Rollout autres microservices
- [ ] Copier les workflows (ou template repo)
- [ ] Adapter `service.yml` par MS
- [ ] Valider chaque MS

---

## Décisions prises

- ✅ **GitHub Plan** : Organization Free
- ✅ **Repo workflows** : PUBLIC (`ids-workflows`)
- ✅ **Approche** : Hybride (Reusable Workflows + Composite Actions)
- ✅ **Principe** : Build once, deploy everywhere

## Questions ouvertes

1. **Nom de l'organisation GitHub** : `ids-org` ? Autre ?
2. **Clusters ECS** : Noms exacts des clusters par env ?
3. **Notifications** : Slack/Teams sur échec déploiement ? (optionnel)
4. **Rollback** : Automatique sur health check KO ? (optionnel)
