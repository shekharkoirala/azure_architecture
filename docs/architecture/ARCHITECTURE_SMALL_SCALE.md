# Small Scale Architecture (MVP)

**Target Scale**: 0-1000 users per day
**Monthly Cost Estimate**: €100-300
**Region**: West Europe (primary)
**Use Case**: Proof of concept, initial launch, internal testing

## Architecture Overview

This architecture is optimized for **minimal cost** while providing a functional compliance checking system. It uses consumption-based pricing wherever possible and avoids redundancy.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Microsoft Word Add-in                        │
│                       (Office.js + JavaScript)                       │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │ HTTPS
                                   │
┌──────────────────────────────────▼──────────────────────────────────┐
│               Azure API Management (Consumption Tier)                │
│          • Authentication (Azure AD)                                 │
│          • Rate Limiting (100 req/min per user)                      │
│          • CORS for Word Add-in                                      │
└──────────────────────────────────┬──────────────────────────────────┘
                                   │
┌──────────────────────────────────▼──────────────────────────────────┐
│            Azure Container Apps (Consumption Plan)                   │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              FastAPI Application                             │   │
│  │    • Async job handling                                      │   │
│  │    • LangGraph agent orchestration                           │   │
│  │    • Parallel guideline checks (configurable set)            │   │
│  │    • MLflow tracking                                         │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  CPU: 0.25 vCPU, Memory: 0.5 GB                                     │
│  Min Replicas: 0 (scale to zero)                                    │
│  Max Replicas: 3                                                     │
└───────────────────────────┬───────────────────────────────────────┬─┘
                            │                                       │
        ┌───────────────────┼───────────────────┐                  │
        │                   │                   │                  │
        ▼                   ▼                   ▼                  │
┌───────────────┐  ┌────────────────┐  ┌────────────────┐         │
│ Azure Blob    │  │ PostgreSQL     │  │ MLflow Storage │         │
│ Storage       │  │ Flexible Server│  │ (Blob Storage) │         │
│ (LRS)         │  │                │  │                │         │
│               │  │ Tier: Burstable│  │                │         │
│ • Articles    │  │ SKU: B1ms      │  │                │         │
│ • Logs        │  │ vCore: 1       │  │                │         │
│ • MLflow data │  │ RAM: 2 GB      │  │                │         │
│               │  │ Storage: 32 GB │  │                │         │
└───────────────┘  └────────────────┘  └────────────────┘         │
                                                                    │
                                                                    │
┌────────────────────────────────────────────────────────────┐     │
│                  Azure Key Vault (Standard)                │     │
│                                                            │     │
│  • CUDAAP_OPENAI_API_KEY                                  │◄────┘
│  • DB_CONNECTION_STRING                                    │
│  • JWT_SECRET_KEY                                          │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│            Application Insights (Basic Tier)               │
│                                                            │
│  • Request tracing                                         │
│  • Error logging                                           │
│  • Basic metrics                                           │
└────────────────────────────────────────────────────────────┘

                    External Services
┌────────────────────────────────────────────────────────────┐
│            CUDAAP-hosted Azure OpenAI                      │
│                  (Claude LLM)                              │
└────────────────────────────────────────────────────────────┘
```

## Azure Resources

### 1. Azure Container Apps
- **Tier**: Consumption Plan
- **Configuration**:
  - Min instances: 0 (scale to zero when idle)
  - Max instances: 3
  - CPU: 0.25 vCPU per instance
  - Memory: 0.5 GB per instance
  - Cold start: ~5-10 seconds (acceptable for MVP)
- **Cost**: Pay per second of execution (~€0.000015/vCPU-second, ~€0.000002/GB-second)
- **Estimated Monthly Cost**: €20-50 (based on usage patterns)

### 2. Azure API Management
- **Tier**: Consumption
- **Features**:
  - 1 million calls/month included
  - Auto-scaling
  - OAuth 2.0 / Azure AD authentication
  - Rate limiting: 100 requests/minute per user
  - CORS configuration
- **Cost**: €0.0028 per 10,000 calls after free tier
- **Estimated Monthly Cost**: €0-10

### 3. Azure Database for PostgreSQL - Flexible Server
- **Tier**: Burstable (B1ms)
- **Configuration**:
  - vCore: 1
  - RAM: 2 GB
  - Storage: 32 GB
  - Backup retention: 7 days
  - Geo-redundancy: No
- **Cost**: ~€25/month
- **Tables**:
  - `jobs`: job_id, status, user_id, created_at, updated_at
  - `compliance_results`: job_id, guideline_id, status, suggestions, explanation
  - `users`: user_id, email, created_at (optional for MVP)

### 4. Azure Blob Storage
- **Tier**: Standard (Hot tier)
- **Redundancy**: LRS (Locally Redundant Storage)
- **Containers**:
  - `articles`: Store article content
  - `compliance-reports`: Detailed compliance reports
  - `mlflow-artifacts`: MLflow experiment artifacts
  - `logs`: Application logs (if needed)
- **Cost**: ~€0.018 per GB/month + transaction costs
- **Estimated Monthly Cost**: €5-10

### 5. Azure Key Vault
- **Tier**: Standard
- **Secrets**:
  - `CUDAAP-OPENAI-API-KEY`
  - `DB-CONNECTION-STRING`
  - `JWT-SECRET-KEY`
  - `BLOB-STORAGE-CONNECTION-STRING`
- **Cost**: ~€0.03 per 10,000 operations
- **Estimated Monthly Cost**: €1-3

### 6. Application Insights
- **Tier**: Pay-as-you-go (Basic)
- **Data Ingestion**: Up to 5 GB/month (often sufficient for MVP)
- **Features**:
  - Request/response logging
  - Exception tracking
  - Basic performance metrics
  - Custom events
- **Cost**: €2.30/GB after 5 GB free
- **Estimated Monthly Cost**: €10-20

### 7. Azure Container Registry
- **Tier**: Basic
- **Storage**: 10 GB included
- **Usage**: Store Docker images for FastAPI app
- **Cost**: ~€4.25/month
- **Estimated Monthly Cost**: €5

### 8. Azure Monitor (Basic)
- **Usage**: Infrastructure-level monitoring
- **Cost**: Included with other services for basic metrics
- **Estimated Monthly Cost**: €0-5

## Total Cost Breakdown (Monthly)

| Service | Estimated Cost (EUR) |
|---------|---------------------|
| Azure Container Apps | €20-50 |
| Azure API Management | €0-10 |
| Azure Database for PostgreSQL | €25 |
| Azure Blob Storage | €5-10 |
| Azure Key Vault | €1-3 |
| Application Insights | €10-20 |
| Azure Container Registry | €5 |
| Azure Monitor | €0-5 |
| **Total** | **€66-128/month** |

**Contingency Buffer (30%)**: €20-40
**Final Estimate**: **€100-300/month**

## Data Flow

### Article Submission Flow

```
1. User clicks "Check Compliance" in Word Add-in
   ↓
2. Add-in extracts article text (max 50 KB for MVP)
   ↓
3. Add-in sends POST /api/v1/compliance/check
   Headers: Authorization: Bearer <azure_ad_token>
   Body: { "article_content": "...", "user_id": "..." }
   ↓
4. API Management validates token → routes to Container Apps
   ↓
5. FastAPI receives request:
   - Generates job_id (UUID)
   - Stores article in Blob Storage
   - Creates job record in PostgreSQL (status: "pending")
   - Returns 202 Accepted with job_id
   ↓
6. FastAPI async worker processes job:
   - Loads article from Blob Storage
   - Initializes LangGraph agent
   - Executes N guideline checks in parallel (configurable set)
   - Each check calls CUDAAP Azure OpenAI
   - MLflow logs experiment data
   - Aggregates results
   - Updates job status to "completed"
   - Stores results in PostgreSQL
   ↓
7. Word Add-in polls GET /api/v1/jobs/{job_id}/status every 3 seconds
   ↓
8. When status = "completed", Add-in fetches GET /api/v1/jobs/{job_id}/result
   ↓
9. Add-in displays compliance suggestions in Word
```

### Parallel Guideline Checking (LangGraph)

```python
# Pseudo-code for LangGraph agent
async def check_compliance(article_content: str, guidelines: List[Guideline]):
    with mlflow.start_run():
        mlflow.log_param("article_length", len(article_content))
        mlflow.log_param("num_guidelines", len(guidelines))

        # Parallel execution of N guidelines (configurable)
        tasks = [
            check_guideline(article_content, guideline)
            for guideline in guidelines
        ]

        results = await asyncio.gather(*tasks)

        # Aggregate results
        compliance_report = aggregate_results(results)
        mlflow.log_metric("compliance_score", compliance_report.score)

        return compliance_report
```

## Deployment Configuration

### Container Apps Configuration

```yaml
# container-app-config.yaml
properties:
  managedEnvironmentId: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.App/managedEnvironments/{env}
  configuration:
    ingress:
      external: false  # Only accessible via API Management
      targetPort: 8000
      transport: http
    secrets:
      - name: openai-api-key
        keyVaultUrl: https://{vault}.vault.azure.net/secrets/CUDAAP-OPENAI-API-KEY
      - name: db-connection-string
        keyVaultUrl: https://{vault}.vault.azure.net/secrets/DB-CONNECTION-STRING
    registries:
      - server: {acr}.azurecr.io
        identity: system
  template:
    containers:
      - name: fastapi-app
        image: {acr}.azurecr.io/compliance-api:latest
        resources:
          cpu: 0.25
          memory: 0.5Gi
        env:
          - name: CUDAAP_OPENAI_API_KEY
            secretRef: openai-api-key
          - name: DB_CONNECTION_STRING
            secretRef: db-connection-string
          - name: ENVIRONMENT
            value: "production"
    scale:
      minReplicas: 0
      maxReplicas: 3
      rules:
        - name: http-rule
          http:
            metadata:
              concurrentRequests: "10"
```

### PostgreSQL Schema

```sql
-- jobs table
CREATE TABLE jobs (
    job_id UUID PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    article_blob_url TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    error_message TEXT
);

CREATE INDEX idx_jobs_user_id ON jobs(user_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at);

-- compliance_results table
CREATE TABLE compliance_results (
    result_id SERIAL PRIMARY KEY,
    job_id UUID NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
    guideline_id INTEGER NOT NULL,
    guideline_name VARCHAR(255),
    status VARCHAR(50) CHECK (status IN ('pass', 'fail', 'warning')),
    suggestions JSONB,
    explanation TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_results_job_id ON compliance_results(job_id);
```

## API Endpoints (MVP)

### 1. Submit Compliance Check
```http
POST /api/v1/compliance/check
Authorization: Bearer <azure_ad_token>
Content-Type: application/json

{
  "article_content": "Marketing article text here...",
  "user_id": "user@company.com"
}

Response (202 Accepted):
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "created_at": "2025-10-02T10:30:00Z"
}
```

### 2. Check Job Status
```http
GET /api/v1/jobs/{job_id}/status
Authorization: Bearer <azure_ad_token>

Response (200 OK):
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "processing",
  "created_at": "2025-10-02T10:30:00Z",
  "updated_at": "2025-10-02T10:30:15Z"
}
```

### 3. Get Compliance Results
```http
GET /api/v1/jobs/{job_id}/result
Authorization: Bearer <azure_ad_token>

Response (200 OK):
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "compliance_score": 0.85,
  "guidelines": [
    {
      "guideline_id": 1,
      "guideline_name": "Brand Voice Consistency",
      "status": "pass",
      "suggestions": [],
      "explanation": "Article maintains consistent brand voice."
    },
    {
      "guideline_id": 2,
      "guideline_name": "Legal Compliance",
      "status": "warning",
      "suggestions": [
        "Add disclaimer about product limitations",
        "Include required regulatory information"
      ],
      "explanation": "Article is missing required legal disclaimers."
    }
  ],
  "created_at": "2025-10-02T10:30:00Z",
  "completed_at": "2025-10-02T10:30:45Z"
}
```

## Security Configuration

### Azure AD Authentication Flow
```
1. User signs into Word Add-in with Microsoft 365 account
   ↓
2. Add-in requests Azure AD token (OAuth 2.0)
   Scope: api://{app_id}/Compliance.Check
   ↓
3. User grants consent (one-time)
   ↓
4. Add-in receives access token
   ↓
5. Add-in includes token in Authorization header for API calls
   ↓
6. API Management validates token with Azure AD
   ↓
7. If valid, request proceeds to Container Apps
```

### Key Vault Access
- **Managed Identity**: Container Apps uses system-assigned managed identity
- **Access Policy**: Grant "Get Secret" permission to managed identity
- **No hardcoded secrets** in code or environment variables

## Monitoring and Alerts

### Application Insights Queries

**Track Average Processing Time**:
```kusto
requests
| where name contains "compliance/check"
| summarize avg(duration) by bin(timestamp, 1h)
```

**Track Failed Jobs**:
```kusto
customEvents
| where name == "JobFailed"
| summarize count() by bin(timestamp, 1h)
```

### Basic Alerts

1. **High Error Rate**: Alert if error rate > 5% in 5 minutes
2. **Slow Response Time**: Alert if average response time > 60 seconds
3. **Database Connection Issues**: Alert on repeated DB connection failures

## Limitations and Constraints

### Performance
- **Cold Start**: 5-10 seconds when scaling from zero
- **Concurrent Jobs**: Max 3 concurrent compliance checks (3 replicas × 1 job each)
- **Processing Time**: 20-45 seconds per article (depends on number of guidelines)
- **Article Size**: Max 50 KB per article (configurable)
- **Guidelines**: Configurable set (processing time scales with number of guidelines)

### Scalability
- **Max Users**: 1000 users/day (~500 articles/day)
- **Rate Limit**: 100 requests/minute per user
- **No caching**: Direct API calls every time (add Redis in Medium Scale)

### Availability
- **Single Region**: No failover to other regions
- **Uptime**: ~99% (Container Apps consumption tier SLA)
- **Backup**: 7-day database backup retention

### Data Retention
- **Job History**: 30 days (cleanup old records)
- **MLflow Experiments**: 90 days
- **Blob Storage**: 90 days for articles, 30 days for logs

## Deployment Steps (Quick Start)

### 1. Prerequisites
```bash
# Install Azure CLI
az login
az account set --subscription {subscription_id}

# Install Terraform
brew install terraform  # macOS
```

### 2. Deploy Infrastructure
```bash
cd infrastructure/small-scale
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 3. Build and Push Docker Image
```bash
# Build Docker image
docker build -t compliance-api:latest .

# Tag and push to ACR
az acr login --name {acr_name}
docker tag compliance-api:latest {acr_name}.azurecr.io/compliance-api:latest
docker push {acr_name}.azurecr.io/compliance-api:latest
```

### 4. Configure Secrets
```bash
# Store CUDAAP API key
az keyvault secret set --vault-name {vault_name} \
  --name CUDAAP-OPENAI-API-KEY \
  --value "{your_api_key}"

# Store DB connection string
az keyvault secret set --vault-name {vault_name} \
  --name DB-CONNECTION-STRING \
  --value "{connection_string}"
```

### 5. Deploy Container App
```bash
az containerapp update \
  --name compliance-api \
  --resource-group {rg_name} \
  --image {acr_name}.azurecr.io/compliance-api:latest
```

### 6. Initialize Database
```bash
# Run schema migration
psql -h {postgres_host} -U {admin_user} -d compliance_db -f schema.sql
```

## When to Scale to Medium Architecture

Migrate to Medium Scale when you observe:
- **User Growth**: Approaching 800-1000 users/day
- **Cold Starts**: Users complaining about slow initial response
- **Concurrent Limit**: Hitting max 3 replicas frequently
- **Database Load**: PostgreSQL CPU > 70% consistently
- **Repeated Queries**: Same articles checked multiple times (need caching)

See [Migration Guide](./MIGRATION_GUIDE.md) for step-by-step upgrade path.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-02
**Target Audience**: MVP deployment, internal testing
