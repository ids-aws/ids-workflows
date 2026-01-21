# Configuration AWS OIDC pour GitHub Actions

Bonjour,

Pour automatiser le déploiement de nos microservices, nous avons besoin de configurer un accès sécurisé entre GitHub Actions et AWS.

Cela permet à notre CI/CD de :
- Push les images Docker vers ECR
- Déployer les services sur ECS Fargate

Merci de suivre les 4 étapes ci-dessous et de me communiquer l'ARN du rôle créé.

---

## Étape 1 : Créer le fournisseur d'identité OIDC

**IAM** → **Identity providers** → **Add provider**

| Champ | Valeur |
|-------|--------|
| Provider type | `OpenID Connect` |
| Provider URL | `https://token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |

→ **Add provider**

---

## Étape 2 : Créer la policy

**IAM** → **Policies** → **Create policy** → onglet **JSON**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "arn:aws:ecr:eu-west-1:857736876208:repository/app/*"
    },
    {
      "Sid": "ECSDeploy",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeTaskDefinition",
        "ecs:RegisterTaskDefinition",
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassRole",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::857736876208:role/ecsTaskExecutionRole"
    }
  ]
}
```

**Policy name** : `github-actions-cicd-policy` → **Create policy**

---

## Étape 3 : Créer le rôle IAM

**IAM** → **Roles** → **Create role**

| Champ | Valeur |
|-------|--------|
| Trusted entity type | `Web identity` |
| Identity provider | `token.actions.githubusercontent.com` |
| Audience | `sts.amazonaws.com` |

→ **Next** → Cocher `github-actions-cicd-policy` → **Next**

**Role name** : `github-actions-role` → **Create role**

---

## Étape 4 : Restreindre à l'organisation GitHub

**IAM** → **Roles** → `github-actions-role` → **Trust relationships** → **Edit trust policy**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::857736876208:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:ids-aws/*:*"
        }
      }
    }
  ]
}
```

→ **Update policy**

---

## Résultat attendu

Copier l'ARN du rôle : **IAM** → **Roles** → `github-actions-role`

```
arn:aws:iam::857736876208:role/github-actions-role
```

---

## Pourquoi OIDC ?

GitHub Actions obtient des credentials AWS **temporaires** (15 min) sans stocker de secrets.

| Méthode | Credentials | Stockage | Rotation |
|---------|-------------|----------|----------|
| OIDC | Temporaires | Aucun | Automatique |
| Static keys | Permanents | GitHub Secrets | Manuelle |
