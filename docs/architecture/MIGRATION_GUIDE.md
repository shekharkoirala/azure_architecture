# Migration Guide: Scaling Marketing Content Compliance Assistant

## Overview

This guide provides step-by-step instructions for migrating the Marketing Content Compliance Assistant across different scale tiers: Small, Medium, and Large. Each migration is designed to minimize downtime and ensure data integrity throughout the process.

## Table of Contents

- [Migration Paths](#migration-paths)
- [Small to Medium Scale Migration](#small-to-medium-scale-migration)
- [Medium to Large Scale Migration](#medium-to-large-scale-migration)
- [Zero-Downtime Deployment Strategies](#zero-downtime-deployment-strategies)
- [Data Migration Procedures](#data-migration-procedures)
- [Testing and Validation](#testing-and-validation)
- [Rollback Procedures](#rollback-procedures)
- [Timeline Estimates](#timeline-estimates)
- [Risk Mitigation](#risk-mitigation)

## Migration Paths

### Available Migration Paths

```
Small Scale (MVP) → Medium Scale (Production) → Large Scale (Enterprise)
```

**Small Scale Characteristics:**
- Single region (West Europe)
- Azure Container Apps: 0.5 vCPU, 1GB RAM, 1-3 replicas
- PostgreSQL Flexible: Basic tier (1-2 vCores)
- No Redis cache
- API Gateway: Consumption tier

**Medium Scale Characteristics:**
- Single region (West Europe)
- Azure Container Apps: 1 vCPU, 2GB RAM, 3-10 replicas
- PostgreSQL Flexible: General Purpose (2-4 vCores)
- Azure Cache for Redis: Basic C1 (250MB)
- API Gateway: Standard tier

**Large Scale Characteristics:**
- Multi-region (West Europe + North Europe)
- Azure Container Apps: 2 vCPU, 4GB RAM, 10-50 replicas per region
- PostgreSQL Flexible: General Purpose (4-8 vCores) with read replicas
- Azure Cache for Redis: Standard C3 (1GB) per region
- API Gateway: Premium tier with multi-region deployment
- Azure Front Door for global load balancing

## Small to Medium Scale Migration

### Prerequisites

- [ ] Access to Azure subscription with appropriate permissions
- [ ] Current system health check completed
- [ ] Backup of PostgreSQL database created
- [ ] Backup of Blob Storage container created
- [ ] Migration window scheduled (recommended: 2-4 hours)
- [ ] Stakeholder notifications sent

### Phase 1: Infrastructure Preparation (30-45 minutes)

#### Step 1.1: Deploy Redis Cache

```bash
# Create Azure Cache for Redis
az redis create \
  --name compliance-cache-medium \
  --resource-group rg-compliance-westeurope \
  --location westeurope \
  --sku Basic \
  --vm-size C1 \
  --enable-non-ssl-port false \
  --minimum-tls-version 1.2

# Retrieve connection string
az redis list-keys \
  --name compliance-cache-medium \
  --resource-group rg-compliance-westeurope
```

Store the Redis connection string in Azure Key Vault:

```bash
az keyvault secret set \
  --vault-name kv-compliance-westeurope \
  --name redis-connection-string \
  --value "<redis-connection-string>"
```

#### Step 1.2: Upgrade PostgreSQL

```bash
# Scale up PostgreSQL to General Purpose tier
az postgres flexible-server update \
  --name pg-compliance-westeurope \
  --resource-group rg-compliance-westeurope \
  --tier GeneralPurpose \
  --sku-name Standard_D2ds_v4

# Update connection pool settings
az postgres flexible-server parameter set \
  --name max_connections \
  --value 200 \
  --resource-group rg-compliance-westeurope \
  --server-name pg-compliance-westeurope
```

#### Step 1.3: Upgrade API Management

```bash
# Upgrade API Management to Standard tier
az apim update \
  --name apim-compliance-westeurope \
  --resource-group rg-compliance-westeurope \
  --sku-name Standard \
  --sku-capacity 1
```

**Note:** This operation can take 15-30 minutes.

### Phase 2: Application Update (45-60 minutes)

#### Step 2.1: Update Application Configuration

Update the application configuration to include Redis:

```python
# config/medium_scale.py
from pydantic_settings import BaseSettings

class MediumScaleSettings(BaseSettings):
    # Existing settings
    database_url: str
    blob_storage_connection: str

    # New settings for Medium scale
    redis_url: str
    cache_ttl: int = 300  # 5 minutes
    enable_caching: bool = True
    max_concurrent_jobs: int = 50

    class Config:
        env_file = ".env.medium"
```

#### Step 2.2: Update Application Code

Add Redis caching layer:

```python
# app/cache.py
import redis.asyncio as redis
from typing import Optional
import json

class CacheManager:
    def __init__(self, redis_url: str, ttl: int = 300):
        self.redis_client = redis.from_url(redis_url, decode_responses=True)
        self.ttl = ttl

    async def get(self, key: str) -> Optional[dict]:
        """Retrieve cached value"""
        value = await self.redis_client.get(key)
        if value:
            return json.loads(value)
        return None

    async def set(self, key: str, value: dict, ttl: Optional[int] = None):
        """Cache value with TTL"""
        await self.redis_client.setex(
            key,
            ttl or self.ttl,
            json.dumps(value)
        )

    async def delete(self, key: str):
        """Invalidate cache"""
        await self.redis_client.delete(key)

    async def close(self):
        """Close Redis connection"""
        await self.redis_client.close()
```

Integrate caching into API endpoints:

```python
# app/api/compliance.py
from fastapi import APIRouter, Depends
from app.cache import CacheManager

router = APIRouter()

@router.get("/api/v1/jobs/{job_id}/status")
async def get_job_status(
    job_id: str,
    cache: CacheManager = Depends(get_cache_manager)
):
    # Try cache first
    cached_status = await cache.get(f"job_status:{job_id}")
    if cached_status:
        return cached_status

    # Fetch from database
    status = await fetch_job_status_from_db(job_id)

    # Cache for 5 minutes if job is not complete
    if status["state"] not in ["completed", "failed"]:
        await cache.set(f"job_status:{job_id}", status, ttl=60)

    return status
```

#### Step 2.3: Build and Push New Container Image

```bash
# Build new image with Medium scale optimizations
docker build -t compliance-api:v2.0.0-medium -f Dockerfile.medium .

# Tag for Azure Container Registry
docker tag compliance-api:v2.0.0-medium \
  acrcompliancewesteurope.azurecr.io/compliance-api:v2.0.0-medium

# Push to ACR
az acr login --name acrcompliancewesteurope
docker push acrcompliancewesteurope.azurecr.io/compliance-api:v2.0.0-medium
```

#### Step 2.4: Update Container Apps Configuration

```bash
# Update Container Apps with new image and increased resources
az containerapp update \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --image acrcompliancewesteurope.azurecr.io/compliance-api:v2.0.0-medium \
  --cpu 1 \
  --memory 2Gi \
  --min-replicas 3 \
  --max-replicas 10 \
  --set-env-vars \
    REDIS_URL=secretref:redis-connection-string \
    ENABLE_CACHING=true \
    SCALE_TIER=medium
```

### Phase 3: Data Migration (15-30 minutes)

#### Step 3.1: Database Schema Updates

```sql
-- Add indexes for improved query performance
CREATE INDEX CONCURRENTLY idx_jobs_created_at ON compliance_jobs(created_at DESC);
CREATE INDEX CONCURRENTLY idx_jobs_user_id_status ON compliance_jobs(user_id, status);
CREATE INDEX CONCURRENTLY idx_results_job_id ON compliance_results(job_id);

-- Add partitioning for job history (optional, for future growth)
-- This can be done during a maintenance window
```

#### Step 3.2: Warm Up Cache

```python
# scripts/cache_warmup.py
import asyncio
from app.cache import CacheManager
from app.db import get_db_session

async def warm_up_cache():
    """Pre-populate cache with frequently accessed data"""
    cache = CacheManager(redis_url="...")
    db = get_db_session()

    # Cache active compliance guidelines
    guidelines = await db.fetch_all("SELECT * FROM compliance_guidelines WHERE active = true")
    for guideline in guidelines:
        await cache.set(f"guideline:{guideline['id']}", dict(guideline), ttl=3600)

    # Cache recent job statuses
    recent_jobs = await db.fetch_all(
        "SELECT * FROM compliance_jobs WHERE created_at > NOW() - INTERVAL '1 hour'"
    )
    for job in recent_jobs:
        await cache.set(f"job_status:{job['id']}", dict(job), ttl=300)

    await cache.close()

if __name__ == "__main__":
    asyncio.run(warm_up_cache())
```

### Phase 4: Validation and Testing (30-45 minutes)

Run comprehensive validation tests (see [Testing and Validation](#testing-and-validation) section).

### Phase 5: Go-Live (15 minutes)

#### Step 5.1: Update API Gateway Policies

```bash
# Update rate limiting policy
az apim api operation update \
  --resource-group rg-compliance-westeurope \
  --service-name apim-compliance-westeurope \
  --api-id compliance-api \
  --operation-id submit-job \
  --set policies=@policies/medium_scale_policy.xml
```

Medium scale rate limiting policy:

```xml
<!-- policies/medium_scale_policy.xml -->
<policies>
    <inbound>
        <rate-limit-by-key calls="500" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
        <quota-by-key calls="10000" renewal-period="86400" counter-key="@(context.Subscription.Id)" />
    </inbound>
</policies>
```

#### Step 5.2: Monitor Initial Traffic

```bash
# Monitor application logs
az containerapp logs show \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --follow

# Monitor Application Insights metrics
az monitor metrics list \
  --resource apim-compliance-westeurope \
  --metric-names Requests,Errors \
  --start-time 2024-01-01T00:00:00Z \
  --interval PT1M
```

### Phase 6: Post-Migration Cleanup (15 minutes)

- [ ] Remove old container images from ACR
- [ ] Update documentation with new endpoints and limits
- [ ] Send completion notification to stakeholders
- [ ] Schedule post-migration review meeting

## Medium to Large Scale Migration

### Prerequisites

- [ ] Multi-region deployment plan approved
- [ ] Network topology designed (VNet peering, Private Link)
- [ ] DR strategy documented
- [ ] Budget approval for increased costs
- [ ] Migration window scheduled (recommended: 4-8 hours)

### Phase 1: Infrastructure Preparation (2-3 hours)

#### Step 1.1: Deploy Secondary Region (North Europe)

```bash
# Create resource group in North Europe
az group create \
  --name rg-compliance-northeurope \
  --location northeurope

# Deploy infrastructure using Bicep/Terraform
az deployment group create \
  --name large-scale-deployment-ne \
  --resource-group rg-compliance-northeurope \
  --template-file infrastructure/large_scale.bicep \
  --parameters region=northeurope
```

#### Step 1.2: Configure PostgreSQL Read Replicas

```bash
# Create read replica in North Europe
az postgres flexible-server replica create \
  --replica-name pg-compliance-northeurope-replica \
  --resource-group rg-compliance-northeurope \
  --source-server pg-compliance-westeurope \
  --location northeurope

# Verify replication lag
az postgres flexible-server replica list \
  --name pg-compliance-westeurope \
  --resource-group rg-compliance-westeurope
```

#### Step 1.3: Deploy Redis in North Europe

```bash
# Create Redis cache in North Europe
az redis create \
  --name compliance-cache-northeurope \
  --resource-group rg-compliance-northeurope \
  --location northeurope \
  --sku Standard \
  --vm-size C3 \
  --enable-non-ssl-port false

# Configure geo-replication (if using Premium tier)
az redis server-link create \
  --name link-westeurope-northeurope \
  --resource-group rg-compliance-westeurope \
  --server compliance-cache-westeurope \
  --server-to-link compliance-cache-northeurope
```

#### Step 1.4: Configure Blob Storage Geo-Replication

```bash
# Verify geo-replication is enabled (should already be GRS/GZRS)
az storage account show \
  --name stcompliancewesteurope \
  --resource-group rg-compliance-westeurope \
  --query "sku.name"

# For active-active scenarios, consider creating a second storage account
az storage account create \
  --name stcompliancenortheurope \
  --resource-group rg-compliance-northeurope \
  --location northeurope \
  --sku Standard_GZRS
```

#### Step 1.5: Deploy Azure Front Door

```bash
# Create Azure Front Door Premium
az afd profile create \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --sku Premium_AzureFrontDoor

# Create endpoint
az afd endpoint create \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --endpoint-name compliance-api-global \
  --enabled-state Enabled

# Create origin group
az afd origin-group create \
  --origin-group-name api-origins \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --probe-request-type GET \
  --probe-protocol Https \
  --probe-interval-in-seconds 30 \
  --probe-path /health

# Add origins
az afd origin create \
  --origin-name westeurope-origin \
  --origin-group-name api-origins \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --host-name apim-compliance-westeurope.azure-api.net \
  --priority 1 \
  --weight 50 \
  --enabled-state Enabled

az afd origin create \
  --origin-name northeurope-origin \
  --origin-group-name api-origins \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --host-name apim-compliance-northeurope.azure-api.net \
  --priority 1 \
  --weight 50 \
  --enabled-state Enabled
```

### Phase 2: Application Deployment (1-2 hours)

#### Step 2.1: Deploy Container Apps to North Europe

```bash
# Create Container Apps Environment in North Europe
az containerapp env create \
  --name cae-compliance-northeurope \
  --resource-group rg-compliance-northeurope \
  --location northeurope

# Deploy API container
az containerapp create \
  --name ca-compliance-api-northeurope \
  --resource-group rg-compliance-northeurope \
  --environment cae-compliance-northeurope \
  --image acrcompliancewesteurope.azurecr.io/compliance-api:v3.0.0-large \
  --cpu 2 \
  --memory 4Gi \
  --min-replicas 10 \
  --max-replicas 50 \
  --target-port 8000 \
  --ingress external
```

#### Step 2.2: Configure Cross-Region Communication

Update application to handle multi-region architecture:

```python
# app/config/large_scale.py
from pydantic_settings import BaseSettings
from typing import List

class LargeScaleSettings(BaseSettings):
    # Primary region configuration
    primary_region: str = "westeurope"
    current_region: str  # Set via environment variable

    # Database configuration
    database_url: str  # Primary database
    read_replica_urls: List[str]  # Read replicas

    # Redis configuration
    redis_primary_url: str
    redis_replica_url: str

    # Blob storage configuration
    blob_storage_primary: str
    blob_storage_secondary: str

    # Front Door configuration
    front_door_endpoint: str

    # Scaling configuration
    max_concurrent_jobs: int = 200
    enable_cross_region_failover: bool = True
```

#### Step 2.3: Implement Read/Write Splitting

```python
# app/db/connection_manager.py
import random
from typing import List
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession

class DatabaseConnectionManager:
    def __init__(
        self,
        primary_url: str,
        replica_urls: List[str],
        primary_region: str,
        current_region: str
    ):
        self.primary_engine = create_async_engine(primary_url, pool_size=20)
        self.replica_engines = [
            create_async_engine(url, pool_size=10) for url in replica_urls
        ]
        self.primary_region = primary_region
        self.current_region = current_region

    async def get_write_session(self) -> AsyncSession:
        """Always use primary database for writes"""
        return AsyncSession(self.primary_engine)

    async def get_read_session(self) -> AsyncSession:
        """Use local replica for reads when possible"""
        if self.current_region != self.primary_region and self.replica_engines:
            # Use local replica for reads
            engine = random.choice(self.replica_engines)
        else:
            # Use primary if no replicas or in primary region
            engine = self.primary_engine
        return AsyncSession(engine)
```

### Phase 3: Data Synchronization (1-2 hours)

#### Step 3.1: Verify Database Replication

```bash
# Check replication lag
az postgres flexible-server replica list \
  --name pg-compliance-westeurope \
  --resource-group rg-compliance-westeurope \
  --query "[].{Name:name, ReplicationLag:replicationLagInSeconds}"
```

#### Step 3.2: Synchronize Blob Storage

```bash
# Use AzCopy to sync data to secondary region storage
azcopy sync \
  "https://stcompliancewesteurope.blob.core.windows.net/articles" \
  "https://stcompliancenortheurope.blob.core.windows.net/articles" \
  --recursive=true

# Verify sync
az storage blob list \
  --account-name stcompliancenortheurope \
  --container-name articles \
  --query "length([*])"
```

### Phase 4: Traffic Migration (30-60 minutes)

#### Step 4.1: Configure Traffic Routing

```bash
# Create Front Door route
az afd route create \
  --route-name api-route \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --endpoint-name compliance-api-global \
  --origin-group api-origins \
  --supported-protocols Https \
  --https-redirect Enabled \
  --forwarding-protocol HttpsOnly
```

#### Step 4.2: Gradual Traffic Shift

Update origin weights to gradually shift traffic:

```bash
# Week 1: 80% West Europe, 20% North Europe
az afd origin update \
  --origin-name westeurope-origin \
  --origin-group-name api-origins \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --weight 80

az afd origin update \
  --origin-name northeurope-origin \
  --origin-group-name api-origins \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --weight 20

# Week 2: 50% West Europe, 50% North Europe (after validation)
# Update weights to 50/50
```

### Phase 5: Validation and Monitoring (Ongoing)

- Monitor replication lag continuously
- Track error rates in both regions
- Validate failover scenarios
- Test disaster recovery procedures

## Zero-Downtime Deployment Strategies

### Blue-Green Deployment

```bash
# Deploy new version (green) alongside existing (blue)
az containerapp revision copy \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --image acrcompliancewesteurope.azurecr.io/compliance-api:v2.0.0

# Split traffic: 90% blue, 10% green (canary)
az containerapp ingress traffic set \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision-weight <blue-revision>=90 <green-revision>=10

# Monitor green deployment for issues
# If successful, shift 100% traffic to green
az containerapp ingress traffic set \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision-weight <green-revision>=100

# Deactivate blue revision after validation period
az containerapp revision deactivate \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision <blue-revision>
```

### Rolling Update Strategy

```bash
# Configure rolling update settings
az containerapp update \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --image acrcompliancewesteurope.azurecr.io/compliance-api:v2.0.0 \
  --scale-rule-name rolling-update \
  --scale-rule-type http \
  --scale-rule-http-concurrency 100
```

Container Apps automatically performs rolling updates with these characteristics:
- Creates new replicas with new version
- Waits for health checks to pass
- Routes traffic to new replicas
- Terminates old replicas gracefully

## Data Migration Procedures

### PostgreSQL Migration

#### Backup Before Migration

```bash
# Create full backup
az postgres flexible-server backup create \
  --name backup-pre-migration-$(date +%Y%m%d) \
  --resource-group rg-compliance-westeurope \
  --server-name pg-compliance-westeurope

# Export to local file for additional safety
pg_dump -h pg-compliance-westeurope.postgres.database.azure.com \
  -U adminuser \
  -d compliance_db \
  -F c \
  -f backup-pre-migration.dump
```

#### Schema Migration with Alembic

```python
# migrations/versions/002_add_caching_support.py
"""Add caching support for medium scale

Revision ID: 002
Revises: 001
Create Date: 2024-01-15 10:00:00
"""
from alembic import op
import sqlalchemy as sa

def upgrade():
    # Add indexes for better query performance
    op.create_index(
        'idx_jobs_created_at',
        'compliance_jobs',
        ['created_at'],
        postgresql_using='btree',
        postgresql_concurrently=True
    )

    op.create_index(
        'idx_jobs_user_status',
        'compliance_jobs',
        ['user_id', 'status'],
        postgresql_using='btree',
        postgresql_concurrently=True
    )

    # Add cache metadata table
    op.create_table(
        'cache_metadata',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('key', sa.String(255), nullable=False, unique=True),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now())
    )

def downgrade():
    op.drop_index('idx_jobs_created_at', table_name='compliance_jobs')
    op.drop_index('idx_jobs_user_status', table_name='compliance_jobs')
    op.drop_table('cache_metadata')
```

Run migration:

```bash
# Test migration on staging
alembic upgrade head --sql > migration.sql
# Review migration.sql

# Apply migration
alembic upgrade head
```

### Redis Data Migration

For Small to Medium migration (introducing Redis):

```python
# scripts/redis_initial_load.py
import asyncio
from app.cache import CacheManager
from app.db import DatabaseConnectionManager

async def populate_initial_cache():
    """Populate Redis with initial data from PostgreSQL"""
    cache = CacheManager(redis_url="...")
    db = DatabaseConnectionManager(...)

    # Cache compliance guidelines
    async with await db.get_read_session() as session:
        guidelines = await session.execute(
            "SELECT * FROM compliance_guidelines WHERE active = true"
        )
        for guideline in guidelines:
            await cache.set(
                f"guideline:{guideline.id}",
                guideline.to_dict(),
                ttl=3600
            )

    print("Initial cache populated successfully")

if __name__ == "__main__":
    asyncio.run(populate_initial_cache())
```

For Medium to Large migration (Redis replication):

```bash
# Verify geo-replication is working
redis-cli -h compliance-cache-westeurope.redis.cache.windows.net \
  -p 6380 \
  --tls \
  -a <access-key> \
  INFO replication
```

### Blob Storage Migration

```bash
# Create migration script
cat > migrate_blobs.sh << 'EOF'
#!/bin/bash

SOURCE_ACCOUNT="stcompliancewesteurope"
TARGET_ACCOUNT="stcompliancenortheurope"
CONTAINER="articles"

# Sync all blobs
azcopy sync \
  "https://${SOURCE_ACCOUNT}.blob.core.windows.net/${CONTAINER}" \
  "https://${TARGET_ACCOUNT}.blob.core.windows.net/${CONTAINER}" \
  --recursive=true \
  --delete-destination=false

# Verify blob count
SOURCE_COUNT=$(az storage blob list \
  --account-name ${SOURCE_ACCOUNT} \
  --container-name ${CONTAINER} \
  --query "length([*])" -o tsv)

TARGET_COUNT=$(az storage blob list \
  --account-name ${TARGET_ACCOUNT} \
  --container-name ${CONTAINER} \
  --query "length([*])" -o tsv)

if [ "$SOURCE_COUNT" -eq "$TARGET_COUNT" ]; then
  echo "Migration successful: $SOURCE_COUNT blobs copied"
  exit 0
else
  echo "Migration verification failed: Source=$SOURCE_COUNT, Target=$TARGET_COUNT"
  exit 1
fi
EOF

chmod +x migrate_blobs.sh
./migrate_blobs.sh
```

## Testing and Validation

### Pre-Migration Testing Checklist

- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] Performance tests baseline established
- [ ] Backup restoration tested
- [ ] Rollback procedure tested in staging

### Post-Migration Validation

#### Health Check Script

```bash
#!/bin/bash
# scripts/validate_migration.sh

ENDPOINT="https://apim-compliance-westeurope.azure-api.net"
API_KEY="your-api-key"

echo "=== Migration Validation Tests ==="

# Test 1: Health endpoint
echo "1. Testing health endpoint..."
HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" ${ENDPOINT}/health)
if [ "$HEALTH_STATUS" -eq 200 ]; then
  echo "✓ Health check passed"
else
  echo "✗ Health check failed (Status: $HEALTH_STATUS)"
  exit 1
fi

# Test 2: Submit test job
echo "2. Submitting test compliance job..."
JOB_RESPONSE=$(curl -s -X POST ${ENDPOINT}/api/v1/compliance/check \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "article_text": "This is a test marketing article.",
    "guidelines": ["guideline-1", "guideline-2"]
  }')

JOB_ID=$(echo $JOB_RESPONSE | jq -r '.job_id')
echo "Job ID: $JOB_ID"

if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
  echo "✗ Job submission failed"
  exit 1
fi
echo "✓ Job submission successful"

# Test 3: Check job status
echo "3. Checking job status..."
sleep 2
STATUS_RESPONSE=$(curl -s ${ENDPOINT}/api/v1/jobs/${JOB_ID}/status \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}")
JOB_STATE=$(echo $STATUS_RESPONSE | jq -r '.state')
echo "Job State: $JOB_STATE"
echo "✓ Status check successful"

# Test 4: Verify Redis caching (if medium+)
if [ "$SCALE_TIER" != "small" ]; then
  echo "4. Testing Redis cache..."
  STATUS_RESPONSE_2=$(curl -s ${ENDPOINT}/api/v1/jobs/${JOB_ID}/status \
    -H "Ocp-Apim-Subscription-Key: ${API_KEY}")
  # Second request should be faster (cached)
  echo "✓ Cache test completed"
fi

# Test 5: Database connectivity
echo "5. Testing database connectivity..."
DB_TEST=$(curl -s ${ENDPOINT}/api/v1/health/db \
  -H "Ocp-Apim-Subscription-Key: ${API_KEY}")
DB_STATUS=$(echo $DB_TEST | jq -r '.status')
if [ "$DB_STATUS" == "healthy" ]; then
  echo "✓ Database connectivity verified"
else
  echo "✗ Database connectivity issue"
  exit 1
fi

echo ""
echo "=== All validation tests passed ==="
```

#### Performance Testing

```python
# tests/performance/load_test.py
import asyncio
import aiohttp
import time
from typing import List

async def submit_job(session: aiohttp.ClientSession, endpoint: str, api_key: str):
    """Submit a single compliance job"""
    headers = {
        "Ocp-Apim-Subscription-Key": api_key,
        "Content-Type": "application/json"
    }
    payload = {
        "article_text": "Test marketing content for compliance check.",
        "guidelines": ["guideline-1", "guideline-2", "guideline-3"]
    }

    start = time.time()
    async with session.post(f"{endpoint}/api/v1/compliance/check",
                           json=payload, headers=headers) as response:
        result = await response.json()
        latency = time.time() - start
        return {
            "status": response.status,
            "latency": latency,
            "job_id": result.get("job_id")
        }

async def run_load_test(endpoint: str, api_key: str, concurrent_requests: int, duration_seconds: int):
    """Run load test with specified parameters"""
    async with aiohttp.ClientSession() as session:
        start_time = time.time()
        results = []

        while time.time() - start_time < duration_seconds:
            tasks = [
                submit_job(session, endpoint, api_key)
                for _ in range(concurrent_requests)
            ]
            batch_results = await asyncio.gather(*tasks)
            results.extend(batch_results)

            # Brief pause between batches
            await asyncio.sleep(0.1)

        # Calculate statistics
        successful = [r for r in results if r["status"] == 202]
        failed = [r for r in results if r["status"] != 202]
        latencies = [r["latency"] for r in successful]

        print(f"\n=== Load Test Results ===")
        print(f"Total requests: {len(results)}")
        print(f"Successful: {len(successful)}")
        print(f"Failed: {len(failed)}")
        print(f"Success rate: {len(successful)/len(results)*100:.2f}%")
        print(f"Avg latency: {sum(latencies)/len(latencies)*1000:.2f}ms")
        print(f"Min latency: {min(latencies)*1000:.2f}ms")
        print(f"Max latency: {max(latencies)*1000:.2f}ms")

if __name__ == "__main__":
    asyncio.run(run_load_test(
        endpoint="https://apim-compliance-westeurope.azure-api.net",
        api_key="your-api-key",
        concurrent_requests=10,  # Adjust based on scale tier
        duration_seconds=60
    ))
```

### Expected Performance Benchmarks

| Metric | Small Scale | Medium Scale | Large Scale |
|--------|-------------|--------------|-------------|
| API Latency (p95) | < 500ms | < 300ms | < 200ms |
| Job Processing Time | < 30s | < 20s | < 15s |
| Throughput | 100 req/min | 500 req/min | 2000 req/min |
| Database Query Time | < 100ms | < 50ms | < 30ms |
| Cache Hit Rate | N/A | > 80% | > 90% |

## Rollback Procedures

### Rollback from Medium to Small

#### Prerequisites for Rollback

- Original small-scale configuration documented
- Database backup verified
- Rollback decision made within 24 hours of migration

#### Rollback Steps

```bash
# 1. Revert Container Apps configuration
az containerapp revision copy \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --image acrcompliancewesteurope.azurecr.io/compliance-api:v1.0.0-small

# Switch 100% traffic to old version
az containerapp ingress traffic set \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --revision-weight <old-revision>=100

# 2. Scale down resources
az containerapp update \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --cpu 0.5 \
  --memory 1Gi \
  --min-replicas 1 \
  --max-replicas 3

# 3. Downgrade PostgreSQL (if necessary)
az postgres flexible-server update \
  --name pg-compliance-westeurope \
  --resource-group rg-compliance-westeurope \
  --tier Burstable \
  --sku-name Standard_B1ms

# 4. Remove Redis dependency from application
az containerapp update \
  --name ca-compliance-api-westeurope \
  --resource-group rg-compliance-westeurope \
  --remove-env-vars REDIS_URL ENABLE_CACHING

# 5. Downgrade API Management (takes time)
az apim update \
  --name apim-compliance-westeurope \
  --resource-group rg-compliance-westeurope \
  --sku-name Consumption

# 6. Verify application health
curl https://apim-compliance-westeurope.azure-api.net/health
```

### Rollback from Large to Medium

```bash
# 1. Remove traffic from secondary region
az afd origin update \
  --origin-name northeurope-origin \
  --origin-group-name api-origins \
  --profile-name afd-compliance-global \
  --resource-group rg-compliance-westeurope \
  --enabled-state Disabled

# 2. Route all traffic through primary region API Management
# Update DNS or Front Door configuration

# 3. Shutdown secondary region resources
az containerapp update \
  --name ca-compliance-api-northeurope \
  --resource-group rg-compliance-northeurope \
  --min-replicas 0 \
  --max-replicas 0

# 4. Verify primary region handling all traffic
# Monitor Application Insights

# 5. Consider keeping infrastructure for future migration
# Don't delete resources immediately
```

### Database Rollback

```bash
# Restore from backup
az postgres flexible-server restore \
  --name pg-compliance-westeurope-restored \
  --resource-group rg-compliance-westeurope \
  --source-server pg-compliance-westeurope \
  --restore-time "2024-01-15T10:00:00Z"

# After verification, promote restored database
# Update connection strings in Key Vault and application
```

## Timeline Estimates

### Small to Medium Migration Timeline

| Phase | Duration | Can Run Off-Hours? |
|-------|----------|-------------------|
| Infrastructure Preparation | 30-45 min | Yes |
| Application Update | 45-60 min | Yes |
| Data Migration | 15-30 min | Partial |
| Validation and Testing | 30-45 min | No |
| Go-Live | 15 min | No |
| Post-Migration | 15 min | Yes |
| **Total** | **2.5-3.5 hours** | - |

**Recommended Window:** Saturday 02:00-06:00 UTC (low traffic period)

### Medium to Large Migration Timeline

| Phase | Duration | Can Run Off-Hours? |
|-------|----------|-------------------|
| Infrastructure Preparation | 2-3 hours | Yes |
| Application Deployment | 1-2 hours | Yes |
| Data Synchronization | 1-2 hours | Yes |
| Traffic Migration | 30-60 min | Gradual (1-2 weeks) |
| Validation and Monitoring | Ongoing | No |
| **Total (Initial)** | **4-7 hours** | - |
| **Total (Complete)** | **1-2 weeks** | - |

**Recommended Approach:**
- Initial deployment: Weekend maintenance window
- Traffic migration: Gradual over 2 weeks during business hours with monitoring

## Risk Mitigation

### Identified Risks and Mitigation Strategies

#### Risk 1: Database Performance Degradation

**Likelihood:** Medium | **Impact:** High

**Mitigation:**
- Perform schema changes with `CONCURRENTLY` option
- Test index creation on staging database first
- Monitor query performance during and after migration
- Keep database backup for quick rollback
- Schedule migration during low-traffic period

#### Risk 2: Cache Miss Storm (Medium Scale)

**Likelihood:** High | **Impact:** Medium

**Mitigation:**
- Implement cache warming script before go-live
- Use gradual cache TTL increase (start with 1 min, increase to 5 min)
- Implement cache stampede protection (locking)
- Monitor database load closely after cache introduction

```python
# Cache stampede protection
import asyncio
from typing import Optional

class CacheWithStampedeProtection(CacheManager):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._locks = {}

    async def get_or_compute(self, key: str, compute_fn, ttl: Optional[int] = None):
        """Get from cache or compute with stampede protection"""
        # Try cache first
        value = await self.get(key)
        if value is not None:
            return value

        # Acquire lock for this key
        if key not in self._locks:
            self._locks[key] = asyncio.Lock()

        async with self._locks[key]:
            # Double-check cache (another coroutine might have populated it)
            value = await self.get(key)
            if value is not None:
                return value

            # Compute and cache
            value = await compute_fn()
            await self.set(key, value, ttl)
            return value
```

#### Risk 3: Multi-Region Data Inconsistency

**Likelihood:** Medium | **Impact:** High

**Mitigation:**
- Implement read-after-write consistency checks
- Use primary region for all writes
- Monitor replication lag continuously
- Set alerts for lag > 5 seconds
- Implement eventual consistency handling in application

```python
# Consistency check
async def write_with_consistency_check(data: dict, max_retries: int = 3):
    """Write to primary and verify replication"""
    # Write to primary
    async with db_manager.get_write_session() as session:
        result = await session.execute("INSERT INTO ... RETURNING id")
        record_id = result.scalar()
        await session.commit()

    # Verify replication
    for attempt in range(max_retries):
        await asyncio.sleep(0.5 * (attempt + 1))  # Exponential backoff

        async with db_manager.get_read_session() as session:
            check = await session.execute(
                "SELECT id FROM ... WHERE id = :id", {"id": record_id}
            )
            if check.scalar():
                return record_id

    # Replication lag detected
    logger.warning(f"Replication lag detected for record {record_id}")
    return record_id
```

#### Risk 4: Network Connectivity Issues

**Likelihood:** Low | **Impact:** High

**Mitigation:**
- Implement circuit breaker pattern
- Configure appropriate timeouts
- Set up health checks and auto-healing
- Have rollback plan ready

```python
# Circuit breaker implementation
from enum import Enum
import time

class CircuitState(Enum):
    CLOSED = "closed"  # Normal operation
    OPEN = "open"      # Failing, reject requests
    HALF_OPEN = "half_open"  # Testing if service recovered

class CircuitBreaker:
    def __init__(self, failure_threshold: int = 5, timeout: int = 60):
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.failure_count = 0
        self.last_failure_time = None
        self.state = CircuitState.CLOSED

    async def call(self, func, *args, **kwargs):
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time > self.timeout:
                self.state = CircuitState.HALF_OPEN
            else:
                raise Exception("Circuit breaker is OPEN")

        try:
            result = await func(*args, **kwargs)
            self.on_success()
            return result
        except Exception as e:
            self.on_failure()
            raise e

    def on_success(self):
        self.failure_count = 0
        self.state = CircuitState.CLOSED

    def on_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitState.OPEN
```

#### Risk 5: Cost Overrun

**Likelihood:** Medium | **Impact:** Medium

**Mitigation:**
- Set up Azure Cost Management alerts
- Monitor resource utilization before full-scale deployment
- Use auto-scaling with upper limits
- Review costs weekly during first month
- Consider reserved instances for predictable workloads

```bash
# Set up cost alert
az consumption budget create \
  --budget-name compliance-monthly-budget \
  --category Cost \
  --amount 5000 \
  --time-grain Monthly \
  --start-date 2024-01-01 \
  --end-date 2024-12-31 \
  --resource-group rg-compliance-westeurope \
  --notifications \
    actual-threshold=80 \
    forecasted-threshold=100 \
    contact-emails=devops@company.com
```

### Communication Plan

#### Pre-Migration Communication

**T-7 days:**
- Send migration announcement to all stakeholders
- Schedule go/no-go meeting for T-1 day
- Share migration runbook with team

**T-1 day:**
- Confirm migration window with stakeholders
- Verify all prerequisites completed
- Run final checklist

**T-0 (Migration Day):**
- Send "migration starting" notification
- Update status page to "maintenance mode"

#### During Migration Communication

- Post updates every 30 minutes
- Immediate notification if issues encountered
- Share real-time metrics dashboard

#### Post-Migration Communication

- Send "migration complete" notification
- Share validation test results
- Schedule post-mortem meeting within 48 hours

### Contact List Template

| Role | Name | Contact | Responsibility |
|------|------|---------|----------------|
| Migration Lead | TBD | TBD | Overall coordination |
| Database Admin | TBD | TBD | PostgreSQL migration |
| DevOps Engineer | TBD | TBD | Infrastructure & deployment |
| Application Developer | TBD | TBD | Code changes & validation |
| Product Owner | TBD | TBD | Business approval |
| On-Call Support | TBD | TBD | Incident response |

## Conclusion

This migration guide provides a comprehensive framework for scaling the Marketing Content Compliance Assistant from Small to Medium to Large scale. Key success factors:

1. **Thorough Testing:** Validate each phase in staging before production
2. **Incremental Approach:** Migrate in phases with validation checkpoints
3. **Monitoring:** Continuously monitor metrics during and after migration
4. **Rollback Readiness:** Always have a tested rollback plan
5. **Communication:** Keep all stakeholders informed throughout the process

For questions or issues during migration, refer to the troubleshooting section in MONITORING_AND_OPERATIONS.md or contact the DevOps team.
