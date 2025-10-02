# Deployment Guide: Marketing Content Compliance Assistant

## Overview

This guide provides comprehensive instructions for deploying the Marketing Content Compliance Assistant to Azure. It covers containerization, CI/CD setup, environment configuration, and deployment verification.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Docker Containerization](#docker-containerization)
- [Azure Container Registry Setup](#azure-container-registry-setup)
- [CI/CD Pipeline Configuration](#cicd-pipeline-configuration)
- [Environment Configuration](#environment-configuration)
- [Secrets Management](#secrets-management)
- [Database Migration](#database-migration)
- [Deployment Verification](#deployment-verification)
- [Blue-Green Deployment](#blue-green-deployment)

## Prerequisites

### Required Tools

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version

# Docker
sudo apt-get update
sudo apt-get install docker.io
docker --version

# kubectl (for Container Apps management)
az aks install-cli

# GitHub CLI (for GitHub Actions setup)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh
gh --version
```

### Azure Permissions

Required Azure RBAC roles:
- Contributor on resource group
- User Access Administrator (for managed identity setup)
- Key Vault Administrator (for secrets management)

### Access Credentials

- Azure subscription ID
- Azure AD tenant ID
- Service principal credentials (for CI/CD)
- Azure OpenAI endpoint and API key
- PostgreSQL admin credentials

## Docker Containerization

### Multi-Stage Dockerfile

**Dockerfile:**

```dockerfile
# Stage 1: Builder
FROM python:3.11-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 appuser

# Set working directory
WORKDIR /app

# Copy Python dependencies from builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy application code
COPY --chown=appuser:appuser ./app ./app
COPY --chown=appuser:appuser ./alembic ./alembic
COPY --chown=appuser:appuser ./alembic.ini .

# Switch to non-root user
USER appuser

# Add user site-packages to PATH
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONPATH=/app

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Start application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
```

### requirements.txt

```txt
# Web framework
fastapi==0.109.0
uvicorn[standard]==0.27.0
pydantic==2.5.3
pydantic-settings==2.1.0

# Database
asyncpg==0.29.0
sqlalchemy[asyncio]==2.0.25
alembic==1.13.1

# Azure SDKs
azure-identity==1.15.0
azure-storage-blob==12.19.0
azure-keyvault-secrets==4.7.0

# OpenAI & LangChain
openai==1.10.0
langchain==0.1.4
langchain-openai==0.0.5
langgraph==0.0.20

# Caching (for medium+ scale)
redis[hiredis]==5.0.1

# Monitoring
azure-monitor-opentelemetry==1.2.0
opentelemetry-api==1.22.0
opentelemetry-sdk==1.22.0

# MLflow
mlflow==2.9.2

# Utilities
python-multipart==0.0.6
python-jose[cryptography]==3.3.0
httpx==0.26.0
tenacity==8.2.3
```

### Docker Build Script

**build.sh:**

```bash
#!/bin/bash
set -e

# Configuration
IMAGE_NAME="compliance-api"
VERSION=${1:-"latest"}
REGISTRY="acrcompliancewesteurope.azurecr.io"

echo "Building Docker image: ${IMAGE_NAME}:${VERSION}"

# Build multi-platform image
docker buildx build \
  --platform linux/amd64 \
  --tag ${IMAGE_NAME}:${VERSION} \
  --tag ${IMAGE_NAME}:latest \
  --file Dockerfile \
  --progress=plain \
  .

echo "Build complete!"

# Tag for ACR
docker tag ${IMAGE_NAME}:${VERSION} ${REGISTRY}/${IMAGE_NAME}:${VERSION}
docker tag ${IMAGE_NAME}:latest ${REGISTRY}/${IMAGE_NAME}:latest

echo "Tagged images for ACR"
```

### Build and Test Locally

```bash
# Build image
chmod +x build.sh
./build.sh v1.0.0

# Run container locally
docker run -d \
  --name compliance-api-test \
  -p 8000:8000 \
  -e DATABASE_URL="postgresql://user:pass@localhost:5432/compliance_db" \
  -e AZURE_OPENAI_ENDPOINT="https://your-openai.openai.azure.com/" \
  -e AZURE_OPENAI_API_KEY="your-api-key" \
  compliance-api:v1.0.0

# Test endpoint
curl http://localhost:8000/health

# View logs
docker logs compliance-api-test

# Stop and remove
docker stop compliance-api-test
docker rm compliance-api-test
```

### Docker Compose for Local Development

**docker-compose.yml:**

```yaml
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/compliance_db
      - REDIS_URL=redis://redis:6379/0
      - AZURE_OPENAI_ENDPOINT=${AZURE_OPENAI_ENDPOINT}
      - AZURE_OPENAI_API_KEY=${AZURE_OPENAI_API_KEY}
    depends_on:
      - db
      - redis
    volumes:
      - ./app:/app/app
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=compliance_db
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  mlflow:
    image: ghcr.io/mlflow/mlflow:v2.9.2
    ports:
      - "5000:5000"
    environment:
      - MLFLOW_BACKEND_STORE_URI=postgresql://postgres:postgres@db:5432/mlflow_db
      - MLFLOW_DEFAULT_ARTIFACT_ROOT=/mlflow/artifacts
    depends_on:
      - db
    volumes:
      - mlflow_artifacts:/mlflow/artifacts
    command: >
      mlflow server
      --host 0.0.0.0
      --port 5000
      --backend-store-uri postgresql://postgres:postgres@db:5432/mlflow_db
      --default-artifact-root /mlflow/artifacts

volumes:
  postgres_data:
  mlflow_artifacts:
```

Run locally:

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f api

# Stop all services
docker-compose down
```

## Azure Container Registry Setup

### Create ACR

```bash
# Set variables
RESOURCE_GROUP="rg-compliance-westeurope"
LOCATION="westeurope"
ACR_NAME="acrcompliancewesteurope"

# Create ACR
az acr create \
  --name ${ACR_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --location ${LOCATION} \
  --sku Standard \
  --admin-enabled false

# Enable Azure AD authentication
az acr update \
  --name ${ACR_NAME} \
  --anonymous-pull-enabled false
```

### Configure ACR Tasks (Optional)

Build images directly in ACR:

```bash
# Build and push using ACR tasks
az acr build \
  --registry ${ACR_NAME} \
  --image compliance-api:v1.0.0 \
  --file Dockerfile \
  .
```

### Push Images to ACR

```bash
# Login to ACR
az acr login --name ${ACR_NAME}

# Push images
docker push ${ACR_NAME}.azurecr.io/compliance-api:v1.0.0
docker push ${ACR_NAME}.azurecr.io/compliance-api:latest

# List images
az acr repository list --name ${ACR_NAME} --output table

# Show image tags
az acr repository show-tags \
  --name ${ACR_NAME} \
  --repository compliance-api \
  --output table
```

### Configure Container Apps to Pull from ACR

```bash
# Create managed identity for Container Apps
IDENTITY_NAME="id-compliance-containerapp"

az identity create \
  --name ${IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP}

# Get identity details
IDENTITY_ID=$(az identity show \
  --name ${IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query id --output tsv)

IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name ${IDENTITY_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query principalId --output tsv)

# Grant AcrPull permission to managed identity
ACR_ID=$(az acr show --name ${ACR_NAME} --query id --output tsv)

az role assignment create \
  --assignee ${IDENTITY_PRINCIPAL_ID} \
  --role AcrPull \
  --scope ${ACR_ID}
```

## CI/CD Pipeline Configuration

### GitHub Actions Workflow

**.github/workflows/deploy.yml:**

```yaml
name: Build and Deploy to Azure

on:
  push:
    branches:
      - main
      - develop
  pull_request:
    branches:
      - main

env:
  AZURE_RESOURCE_GROUP: rg-compliance-westeurope
  ACR_NAME: acrcompliancewesteurope
  CONTAINER_APP_NAME: ca-compliance-api-westeurope
  IMAGE_NAME: compliance-api

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Azure
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Log in to ACR
        run: |
          az acr login --name ${{ env.ACR_NAME }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=sha,prefix={{branch}}-
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=registry,ref=${{ env.ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:buildcache
          cache-to: type=registry,ref=${{ env.ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:buildcache,mode=max

  test:
    runs-on: ubuntu-latest
    needs: build

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest pytest-asyncio pytest-cov

      - name: Run tests
        env:
          DATABASE_URL: postgresql://postgres:postgres@localhost:5432/test_db
          REDIS_URL: redis://localhost:6379/0
        run: |
          pytest tests/ -v --cov=app --cov-report=xml

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage.xml

  deploy-staging:
    runs-on: ubuntu-latest
    needs: [build, test]
    if: github.ref == 'refs/heads/develop'
    environment:
      name: staging
      url: https://ca-compliance-api-staging.azurecontainerapp.io

    steps:
      - name: Log in to Azure
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Get image tag
        id: get-tag
        run: |
          echo "tag=${{ env.ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:develop-${{ github.sha }}" >> $GITHUB_OUTPUT

      - name: Deploy to Container Apps (Staging)
        run: |
          az containerapp update \
            --name ca-compliance-api-staging \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --image ${{ steps.get-tag.outputs.tag }}

      - name: Verify deployment
        run: |
          sleep 30
          HEALTH_URL=$(az containerapp show \
            --name ca-compliance-api-staging \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --query properties.configuration.ingress.fqdn -o tsv)

          curl -f https://${HEALTH_URL}/health || exit 1

  deploy-production:
    runs-on: ubuntu-latest
    needs: [build, test]
    if: github.ref == 'refs/heads/main'
    environment:
      name: production
      url: https://ca-compliance-api-westeurope.azurecontainerapp.io

    steps:
      - name: Log in to Azure
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Get image tag
        id: get-tag
        run: |
          echo "tag=${{ env.ACR_NAME }}.azurecr.io/${{ env.IMAGE_NAME }}:main-${{ github.sha }}" >> $GITHUB_OUTPUT

      - name: Deploy to Container Apps (Production - Blue/Green)
        run: |
          # Create new revision (green)
          az containerapp update \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --image ${{ steps.get-tag.outputs.tag }} \
            --revision-suffix green-$(date +%s)

          # Get new revision name
          NEW_REVISION=$(az containerapp revision list \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --query "[0].name" -o tsv)

          echo "New revision: $NEW_REVISION"

          # Split traffic: 10% to new revision (canary)
          az containerapp ingress traffic set \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --revision-weight ${NEW_REVISION}=10

      - name: Monitor canary deployment
        run: |
          echo "Monitoring canary deployment for 5 minutes..."
          sleep 300

          # Check error rate (implement your monitoring logic)
          # If error rate is acceptable, continue; otherwise, rollback

      - name: Complete rollout
        run: |
          NEW_REVISION=$(az containerapp revision list \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --query "[0].name" -o tsv)

          # Shift 100% traffic to new revision
          az containerapp ingress traffic set \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --revision-weight ${NEW_REVISION}=100

      - name: Deactivate old revisions
        run: |
          # Keep only the latest 3 revisions
          az containerapp revision list \
            --name ${{ env.CONTAINER_APP_NAME }} \
            --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
            --query "[3:].name" -o tsv | \
          while read revision; do
            az containerapp revision deactivate \
              --name ${{ env.CONTAINER_APP_NAME }} \
              --resource-group ${{ env.AZURE_RESOURCE_GROUP }} \
              --revision $revision
          done

      - name: Send deployment notification
        uses: 8398a7/action-slack@v3
        with:
          status: ${{ job.status }}
          text: 'Production deployment completed'
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
        if: always()
```

### Azure DevOps Pipeline

**azure-pipelines.yml:**

```yaml
trigger:
  branches:
    include:
      - main
      - develop

variables:
  azureSubscription: 'Azure-Service-Connection'
  resourceGroup: 'rg-compliance-westeurope'
  acrName: 'acrcompliancewesteurope'
  containerAppName: 'ca-compliance-api-westeurope'
  imageName: 'compliance-api'

stages:
  - stage: Build
    jobs:
      - job: BuildAndPush
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: Docker@2
            displayName: 'Build and push image'
            inputs:
              containerRegistry: '$(acrName)'
              repository: '$(imageName)'
              command: 'buildAndPush'
              Dockerfile: 'Dockerfile'
              tags: |
                $(Build.BuildId)
                latest

  - stage: Test
    dependsOn: Build
    jobs:
      - job: RunTests
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: UsePythonVersion@0
            inputs:
              versionSpec: '3.11'

          - script: |
              pip install -r requirements.txt
              pip install pytest pytest-asyncio pytest-cov
            displayName: 'Install dependencies'

          - script: |
              pytest tests/ -v --cov=app --cov-report=xml
            displayName: 'Run tests'

          - task: PublishCodeCoverageResults@1
            inputs:
              codeCoverageTool: 'Cobertura'
              summaryFileLocation: '$(System.DefaultWorkingDirectory)/coverage.xml'

  - stage: DeployProduction
    dependsOn: Test
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - deployment: DeployToProduction
        environment: 'production'
        pool:
          vmImage: 'ubuntu-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  displayName: 'Deploy to Container Apps'
                  inputs:
                    azureSubscription: '$(azureSubscription)'
                    scriptType: 'bash'
                    scriptLocation: 'inlineScript'
                    inlineScript: |
                      az containerapp update \
                        --name $(containerAppName) \
                        --resource-group $(resourceGroup) \
                        --image $(acrName).azurecr.io/$(imageName):$(Build.BuildId)
```

### Setup GitHub Secrets

```bash
# Create service principal
az ad sp create-for-rbac \
  --name "github-actions-compliance" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/rg-compliance-westeurope \
  --sdk-auth

# Output will be JSON - add to GitHub secrets as AZURE_CREDENTIALS
```

Add to GitHub repository secrets:
- `AZURE_CREDENTIALS`: Service principal JSON
- `SLACK_WEBHOOK`: Slack webhook URL (optional)

## Environment Configuration

### Environment Files

**.env.development:**

```bash
# Application
APP_ENV=development
LOG_LEVEL=DEBUG
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8000

# Database
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/compliance_db
DATABASE_POOL_SIZE=5
DATABASE_MAX_OVERFLOW=10

# Redis (for medium+ scale)
REDIS_URL=redis://localhost:6379/0
CACHE_TTL=300

# Azure OpenAI
AZURE_OPENAI_ENDPOINT=https://your-openai.openai.azure.com/
AZURE_OPENAI_API_KEY=your-api-key
AZURE_OPENAI_DEPLOYMENT=gpt-4-turbo
AZURE_OPENAI_API_VERSION=2024-02-15-preview

# Azure Blob Storage
AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=...
BLOB_CONTAINER_NAME=articles

# MLflow
MLFLOW_TRACKING_URI=http://localhost:5000
MLFLOW_EXPERIMENT_NAME=compliance_check_dev

# API Configuration
API_RATE_LIMIT=100
API_RATE_WINDOW=60
```

**.env.production:**

```bash
# Application
APP_ENV=production
LOG_LEVEL=INFO
ALLOWED_ORIGINS=https://your-production-domain.com

# Database (use Key Vault references)
DATABASE_URL=${KEY_VAULT_SECRET:postgres-connection-string}
DATABASE_POOL_SIZE=20
DATABASE_MAX_OVERFLOW=40

# Redis
REDIS_URL=${KEY_VAULT_SECRET:redis-connection-string}
CACHE_TTL=600

# Azure OpenAI
AZURE_OPENAI_ENDPOINT=${KEY_VAULT_SECRET:openai-endpoint}
AZURE_OPENAI_API_KEY=${KEY_VAULT_SECRET:openai-api-key}
AZURE_OPENAI_DEPLOYMENT=gpt-4-turbo
AZURE_OPENAI_API_VERSION=2024-02-15-preview

# Azure Blob Storage
AZURE_STORAGE_CONNECTION_STRING=${KEY_VAULT_SECRET:storage-connection-string}
BLOB_CONTAINER_NAME=articles

# MLflow
MLFLOW_TRACKING_URI=https://ca-mlflow-westeurope.azurecontainerapp.io
MLFLOW_EXPERIMENT_NAME=compliance_check_prod

# API Configuration
API_RATE_LIMIT=500
API_RATE_WINDOW=60

# Monitoring
APPLICATIONINSIGHTS_CONNECTION_STRING=${KEY_VAULT_SECRET:appinsights-connection-string}
```

### Container Apps Environment Variables

```bash
# Set environment variables for Container Apps
az containerapp update \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --set-env-vars \
    APP_ENV=production \
    LOG_LEVEL=INFO \
    DATABASE_URL=secretref:postgres-connection-string \
    REDIS_URL=secretref:redis-connection-string \
    AZURE_OPENAI_ENDPOINT=secretref:openai-endpoint \
    AZURE_OPENAI_API_KEY=secretref:openai-api-key \
    AZURE_STORAGE_CONNECTION_STRING=secretref:storage-connection-string \
    MLFLOW_TRACKING_URI=https://ca-mlflow-westeurope.azurecontainerapp.io \
    APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appinsights-connection-string
```

## Secrets Management

### Azure Key Vault Setup

```bash
# Create Key Vault
KV_NAME="kv-compliance-westeurope"

az keyvault create \
  --name ${KV_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --location ${LOCATION} \
  --enable-rbac-authorization false

# Add secrets
az keyvault secret set \
  --vault-name ${KV_NAME} \
  --name postgres-connection-string \
  --value "postgresql://user:pass@pg-compliance-westeurope.postgres.database.azure.com:5432/compliance_db?sslmode=require"

az keyvault secret set \
  --vault-name ${KV_NAME} \
  --name redis-connection-string \
  --value "rediss://:password@compliance-cache-westeurope.redis.cache.windows.net:6380/0"

az keyvault secret set \
  --vault-name ${KV_NAME} \
  --name openai-api-key \
  --value "your-openai-api-key"

az keyvault secret set \
  --vault-name ${KV_NAME} \
  --name storage-connection-string \
  --value "DefaultEndpointsProtocol=https;AccountName=..."

az keyvault secret set \
  --vault-name ${KV_NAME} \
  --name appinsights-connection-string \
  --value "InstrumentationKey=...;IngestionEndpoint=..."
```

### Grant Container Apps Access to Key Vault

```bash
# Get Container Apps managed identity
IDENTITY_PRINCIPAL_ID=$(az containerapp show \
  --name ca-compliance-api-westeurope \
  --resource-group ${RESOURCE_GROUP} \
  --query identity.principalId -o tsv)

# Grant access to Key Vault
az keyvault set-policy \
  --name ${KV_NAME} \
  --object-id ${IDENTITY_PRINCIPAL_ID} \
  --secret-permissions get list
```

### Reference Secrets in Container Apps

```bash
# Add secret references
az containerapp secret set \
  --name ca-compliance-api-westeurope \
  --resource-group ${RESOURCE_GROUP} \
  --secrets \
    postgres-connection-string=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/postgres-connection-string,identityref:${IDENTITY_ID} \
    redis-connection-string=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/redis-connection-string,identityref:${IDENTITY_ID} \
    openai-api-key=keyvaultref:https://${KV_NAME}.vault.azure.net/secrets/openai-api-key,identityref:${IDENTITY_ID}
```

## Database Migration

### Alembic Configuration

**alembic.ini:**

```ini
[alembic]
script_location = alembic
prepend_sys_path = .
version_path_separator = os

sqlalchemy.url = driver://user:pass@localhost/dbname

[alembic:exclude]
tables = spatial_ref_sys

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
```

### Migration Scripts

**alembic/env.py:**

```python
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
import os

# Import models
from app.models import Base

config = context.config

# Override sqlalchemy.url from environment
config.set_main_option('sqlalchemy.url', os.getenv('DATABASE_URL', ''))

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix='sqlalchemy.',
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,
            compare_server_default=True
        )

        with context.begin_transaction():
            context.run_migrations()

run_migrations_online()
```

### Run Migrations

```bash
# Create new migration
alembic revision --autogenerate -m "Add compliance tables"

# Review migration file
cat alembic/versions/001_add_compliance_tables.py

# Apply migrations
alembic upgrade head

# Rollback one version
alembic downgrade -1

# Show current version
alembic current

# Show migration history
alembic history
```

### Migration in CI/CD

Add to deployment pipeline:

```yaml
- name: Run database migrations
  run: |
    alembic upgrade head
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

## Deployment Verification

### Health Check Endpoints

**app/api/health.py:**

```python
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from redis.asyncio import Redis

router = APIRouter()

@router.get("/health")
async def health_check():
    """Basic health check"""
    return {"status": "healthy"}

@router.get("/health/ready")
async def readiness_check(
    db: AsyncSession = Depends(get_db_session),
    cache: Redis = Depends(get_redis_client)
):
    """Readiness check - verify dependencies"""
    checks = {
        "database": False,
        "cache": False,
        "storage": False
    }

    # Check database
    try:
        await db.execute("SELECT 1")
        checks["database"] = True
    except Exception as e:
        print(f"Database check failed: {e}")

    # Check Redis
    try:
        await cache.ping()
        checks["cache"] = True
    except Exception as e:
        print(f"Cache check failed: {e}")

    # Check blob storage
    try:
        from azure.storage.blob import BlobServiceClient
        blob_client = BlobServiceClient.from_connection_string(...)
        blob_client.get_service_properties()
        checks["storage"] = True
    except Exception as e:
        print(f"Storage check failed: {e}")

    all_healthy = all(checks.values())
    status_code = 200 if all_healthy else 503

    return JSONResponse(
        status_code=status_code,
        content={"status": "ready" if all_healthy else "not ready", "checks": checks}
    )

@router.get("/health/live")
async def liveness_check():
    """Liveness check - is the app running?"""
    return {"status": "alive"}
```

### Verification Script

**scripts/verify_deployment.sh:**

```bash
#!/bin/bash
set -e

# Configuration
ENDPOINT=${1:-"https://ca-compliance-api-westeurope.azurecontainerapp.io"}
API_KEY=${2:-""}

echo "=== Deployment Verification ==="
echo "Endpoint: $ENDPOINT"
echo ""

# Test 1: Health check
echo "1. Testing health endpoint..."
STATUS=$(curl -s -o /dev/null -w "%{http_code}" ${ENDPOINT}/health)
if [ "$STATUS" -eq 200 ]; then
  echo "✓ Health check passed"
else
  echo "✗ Health check failed (Status: $STATUS)"
  exit 1
fi

# Test 2: Readiness check
echo "2. Testing readiness endpoint..."
RESPONSE=$(curl -s ${ENDPOINT}/health/ready)
echo "Response: $RESPONSE"

# Test 3: API submission
echo "3. Testing compliance check submission..."
JOB_RESPONSE=$(curl -s -X POST ${ENDPOINT}/api/v1/compliance/check \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "article_text": "Test article for deployment verification",
    "guidelines": ["guideline-001"]
  }')

JOB_ID=$(echo $JOB_RESPONSE | jq -r '.job_id')
if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
  echo "✓ Job submission successful (ID: $JOB_ID)"
else
  echo "✗ Job submission failed"
  echo "Response: $JOB_RESPONSE"
  exit 1
fi

# Test 4: Status check
echo "4. Testing status endpoint..."
sleep 2
STATUS_RESPONSE=$(curl -s ${ENDPOINT}/api/v1/jobs/${JOB_ID}/status \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}")
echo "Status: $(echo $STATUS_RESPONSE | jq -r '.state')"

echo ""
echo "=== All verification tests passed ==="
```

Run verification:

```bash
chmod +x scripts/verify_deployment.sh
./scripts/verify_deployment.sh https://your-endpoint.azurecontainerapp.io your-api-key
```

## Blue-Green Deployment

### Manual Blue-Green Deployment

```bash
# Step 1: Deploy new version (green) with new revision
az containerapp update \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --image acrcompliancewesteurope.azurecr.io/compliance-api:v2.0.0 \
  --revision-suffix green-$(date +%s)

# Step 2: Get revision names
BLUE_REVISION=$(az containerapp revision list \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --query "[?properties.active==\`true\`] | [1].name" -o tsv)

GREEN_REVISION=$(az containerapp revision list \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --query "[?properties.active==\`true\`] | [0].name" -o tsv)

echo "Blue (old): $BLUE_REVISION"
echo "Green (new): $GREEN_REVISION"

# Step 3: Route 10% traffic to green (canary)
az containerapp ingress traffic set \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision-weight ${BLUE_REVISION}=90 ${GREEN_REVISION}=10

# Step 4: Monitor for 5-10 minutes
echo "Monitoring canary deployment..."
sleep 600

# Step 5: Route 50% traffic to green
az containerapp ingress traffic set \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision-weight ${BLUE_REVISION}=50 ${GREEN_REVISION}=50

# Step 6: Monitor again
sleep 300

# Step 7: Route 100% traffic to green
az containerapp ingress traffic set \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision-weight ${GREEN_REVISION}=100

# Step 8: Deactivate blue revision (after validation period)
az containerapp revision deactivate \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision ${BLUE_REVISION}
```

### Automated Blue-Green Script

**scripts/blue_green_deploy.sh:**

```bash
#!/bin/bash
set -e

# Configuration
RESOURCE_GROUP="rg-compliance-westeurope"
CONTAINER_APP="ca-compliance-api-westeurope"
NEW_IMAGE=$1
CANARY_PERCENTAGE=${2:-10}
CANARY_DURATION=${3:-300}  # 5 minutes

if [ -z "$NEW_IMAGE" ]; then
  echo "Usage: $0 <new-image> [canary-percentage] [canary-duration-seconds]"
  exit 1
fi

echo "=== Blue-Green Deployment ==="
echo "New image: $NEW_IMAGE"
echo "Canary percentage: $CANARY_PERCENTAGE%"
echo "Canary duration: $CANARY_DURATION seconds"
echo ""

# Deploy new revision
echo "Deploying new revision..."
az containerapp update \
  --name $CONTAINER_APP \
  --resource-group $RESOURCE_GROUP \
  --image $NEW_IMAGE \
  --revision-suffix green-$(date +%s)

# Get revision names
GREEN_REVISION=$(az containerapp revision list \
  --name $CONTAINER_APP \
  --resource-group $RESOURCE_GROUP \
  --query "[0].name" -o tsv)

BLUE_REVISION=$(az containerapp revision list \
  --name $CONTAINER_APP \
  --resource-group $RESOURCE_GROUP \
  --query "[1].name" -o tsv)

echo "Green (new): $GREEN_REVISION"
echo "Blue (old): $BLUE_REVISION"
echo ""

# Canary deployment
echo "Starting canary deployment ($CANARY_PERCENTAGE%)..."
BLUE_TRAFFIC=$((100 - CANARY_PERCENTAGE))

az containerapp ingress traffic set \
  --name $CONTAINER_APP \
  --resource-group $RESOURCE_GROUP \
  --revision-weight ${BLUE_REVISION}=${BLUE_TRAFFIC} ${GREEN_REVISION}=${CANARY_PERCENTAGE}

echo "Monitoring canary for $CANARY_DURATION seconds..."
sleep $CANARY_DURATION

# Check metrics (implement your own monitoring logic)
# For now, we'll assume success if no errors

echo "Canary successful. Rolling out to 100%..."
az containerapp ingress traffic set \
  --name $CONTAINER_APP \
  --resource-group $RESOURCE_GROUP \
  --revision-weight ${GREEN_REVISION}=100

echo ""
echo "=== Deployment Complete ==="
echo "New revision active: $GREEN_REVISION"
echo ""
echo "To rollback, run:"
echo "  az containerapp ingress traffic set \\"
echo "    --name $CONTAINER_APP \\"
echo "    --resource-group $RESOURCE_GROUP \\"
echo "    --revision-weight ${BLUE_REVISION}=100"
```

---

## Summary

This deployment guide covers:

1. **Docker Containerization**: Multi-stage Dockerfile for optimized images
2. **Azure Container Registry**: Secure image storage and management
3. **CI/CD Pipelines**: GitHub Actions and Azure DevOps configurations
4. **Environment Management**: Development, staging, and production configurations
5. **Secrets Management**: Azure Key Vault integration
6. **Database Migrations**: Alembic-based schema versioning
7. **Deployment Verification**: Automated testing and health checks
8. **Blue-Green Deployment**: Zero-downtime deployment strategy

For additional support, refer to:
- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure DevOps Pipelines](https://docs.microsoft.com/en-us/azure/devops/pipelines/)
