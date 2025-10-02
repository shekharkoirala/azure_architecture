# Medium Scale Architecture (Production)

**Target Scale**: 1,000-10,000 users per day
**Monthly Cost Estimate**: €500-1500
**Region**: West Europe (primary)
**Use Case**: Production launch, growing user base, enhanced reliability

## Architecture Overview

This architecture introduces **auto-scaling**, **caching**, and **enhanced monitoring** to handle increased load while maintaining acceptable response times and reliability.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Microsoft Word Add-in                        │
│                       (Office.js + JavaScript)                       │
└──────────────────────────────────────┬──────────────────────────────┘
                                       │ HTTPS
                                       │
┌──────────────────────────────────────▼──────────────────────────────┐
│            Azure API Management (Standard Tier)                      │
│          • Azure AD authentication                                   │
│          • Rate limiting (500 req/min per user)                      │
│          • Response caching (5 min TTL)                              │
│          • Request throttling                                        │
│          • Advanced analytics                                        │
└──────────────────────────────────────┬──────────────────────────────┘
                                       │
┌──────────────────────────────────────▼──────────────────────────────┐
│         Azure Container Apps (Dedicated Workload Profile)            │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              FastAPI Application                             │   │
│  │    • Async job handling with queue                           │   │
│  │    • LangGraph agent orchestration                           │   │
│  │    • Parallel guideline checks (configurable set)            │   │
│  │    • MLflow tracking                                         │   │
│  │    • Redis caching integration                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  CPU: 0.5 vCPU per instance, Memory: 1 GB per instance              │
│  Min Replicas: 2 (always-on)                                        │
│  Max Replicas: 10                                                    │
│  Auto-scale on: CPU > 70% or Request Queue > 100                    │
└───────────────────────────┬───────────────────────────────────────┬─┘
                            │                                       │
        ┌───────────────────┼───────────────────┬──────────────┐   │
        │                   │                   │              │   │
        ▼                   ▼                   ▼              ▼   │
┌───────────────┐  ┌────────────────┐  ┌────────────┐  ┌──────────┐ │
│ Azure Blob    │  │ PostgreSQL     │  │ Redis Cache│  │ MLflow   │ │
│ Storage       │  │ Flexible Server│  │ (Basic)    │  │ Storage  │ │
│ (ZRS)         │  │                │  │            │  │          │ │
│               │  │ Tier: General  │  │ 1 GB cache │  │          │ │
│ • Articles    │  │       Purpose  │  │            │  │          │ │
│ • Logs        │  │ SKU: D2ds_v4   │  │ Use cases: │  │          │ │
│ • MLflow data │  │ vCore: 2       │  │ • Job      │  │          │ │
│               │  │ RAM: 8 GB      │  │   status   │  │          │ │
│ Hot tier      │  │ Storage: 128GB │  │ • Results  │  │          │ │
│ + Cool tier   │  │ IOPS: 3500     │  │ • Session  │  │          │ │
│               │  │                │  │   tokens   │  │          │ │
└───────────────┘  └────────────────┘  └────────────┘  └──────────┘ │
                           │                                          │
                           │ (Read replica for reporting)             │
                           ▼                                          │
                   ┌────────────────┐                                 │
                   │ PostgreSQL     │                                 │
                   │ Read Replica   │                                 │
                   │ (Optional)     │                                 │
                   └────────────────┘                                 │
                                                                       │
┌────────────────────────────────────────────────────────────┐        │
│                  Azure Key Vault (Standard)                │        │
│                                                            │◄───────┘
│  • CUDAAP_OPENAI_API_KEY                                  │
│  • DB_CONNECTION_STRING                                    │
│  • REDIS_CONNECTION_STRING                                 │
│  • JWT_SECRET_KEY                                          │
└────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────┐
│         Application Insights + Azure Monitor               │
│                                                            │
│  • Distributed tracing                                     │
│  • Custom metrics and dashboards                           │
│  • Alerts and notifications                                │
│  • Performance profiling                                   │
│  • Live metrics stream                                     │
└────────────────────────────────────────────────────────────┘

                    External Services
┌────────────────────────────────────────────────────────────┐
│            CUDAAP-hosted Azure OpenAI                      │
│                  (Claude LLM)                              │
└────────────────────────────────────────────────────────────┘
```

## Key Improvements Over Small Scale

### 1. **Always-On Instances**
- **Small Scale**: Min 0 replicas (scale to zero)
- **Medium Scale**: Min 2 replicas (always-on)
- **Benefit**: Eliminates cold start delays, instant response

### 2. **Redis Caching Layer**
- Cache frequently requested job results
- Cache job status to reduce DB queries
- Cache user session tokens
- TTL: 5-15 minutes depending on data type

### 3. **Enhanced Auto-Scaling**
- Scale based on CPU, memory, and request queue depth
- Faster scale-up response time
- Predictive scaling based on historical patterns

### 4. **Improved Database**
- General Purpose tier with more vCores and RAM
- Higher IOPS for faster queries
- Optional read replica for analytics/reporting
- Connection pooling optimizations

### 5. **Advanced Monitoring**
- Custom dashboards for key metrics
- Proactive alerts (before issues impact users)
- Performance profiling and bottleneck detection
- User-facing status page integration

### 6. **Storage Optimization**
- Zone-redundant storage (ZRS) for higher availability
- Lifecycle policies: Hot → Cool tier after 30 days
- Automated cleanup of old job data

## Azure Resources

### 1. Azure Container Apps (Dedicated)
- **Tier**: Dedicated Workload Profile
- **Configuration**:
  - Min instances: 2 (always-on)
  - Max instances: 10
  - CPU: 0.5 vCPU per instance
  - Memory: 1 GB per instance
  - Auto-scale rules:
    - CPU utilization > 70%
    - Request queue depth > 100
    - Custom metric: Job processing time > 60s
- **Cost**: ~€0.16/vCPU-hour, ~€0.02/GB-hour
- **Estimated Monthly Cost**: €150-300

### 2. Azure API Management
- **Tier**: Standard (or Developer for non-prod)
- **Features**:
  - 1 unit = 1,000 req/sec capacity
  - Built-in caching (up to 1 GB)
  - Advanced policies and transformations
  - Custom domains and SSL
  - Rate limiting: 500 requests/minute per user
- **Cost**: ~€0.25/hour (~€180/month for 1 unit)
- **Estimated Monthly Cost**: €180-200

### 3. Azure Database for PostgreSQL - Flexible Server
- **Tier**: General Purpose (D2ds_v4)
- **Configuration**:
  - vCore: 2
  - RAM: 8 GB
  - Storage: 128 GB
  - IOPS: 3500
  - Backup retention: 14 days
  - Geo-redundant backup: Yes
  - High Availability: Zone-redundant (optional, +€50/month)
  - Read Replica: Optional (for reporting, +€80/month)
- **Cost**: ~€120/month (base)
- **Estimated Monthly Cost**: €120-250 (with HA and replica)

### 4. Azure Cache for Redis
- **Tier**: Basic (C1)
- **Configuration**:
  - Cache size: 1 GB
  - SSL enabled
  - Persistence: Optional (RDB snapshots)
- **Use Cases**:
  - Job status caching (reduce DB load)
  - Recent results caching (5 min TTL)
  - Session token caching
  - Rate limiting counters
- **Cost**: ~€40/month
- **Estimated Monthly Cost**: €40-50

### 5. Azure Blob Storage
- **Tier**: Standard (Hot + Cool)
- **Redundancy**: ZRS (Zone-Redundant Storage)
- **Lifecycle Policy**:
  - Articles: Hot tier → Cool tier after 30 days → Delete after 180 days
  - Logs: Hot tier → Cool tier after 7 days → Delete after 90 days
  - MLflow artifacts: Hot tier → Cool tier after 60 days
- **Cost**: Hot: €0.018/GB/month, Cool: €0.01/GB/month
- **Estimated Monthly Cost**: €15-30

### 6. Azure Key Vault
- **Tier**: Standard
- **Operations**: ~50,000/month
- **Cost**: €0.03 per 10,000 operations
- **Estimated Monthly Cost**: €3-5

### 7. Application Insights
- **Tier**: Pay-as-you-go
- **Data Ingestion**: 20-50 GB/month
- **Features**:
  - Distributed tracing
  - Custom dashboards
  - Smart detection (anomalies)
  - Profiler and snapshot debugger
- **Cost**: €2.30/GB after 5 GB free
- **Estimated Monthly Cost**: €50-100

### 8. Azure Container Registry
- **Tier**: Standard
- **Storage**: 100 GB included
- **Geo-replication**: No (single region)
- **Cost**: ~€17/month
- **Estimated Monthly Cost**: €20

### 9. Azure Monitor
- **Usage**: Alerts, action groups, log queries
- **Cost**: Pay per alert rule, log data ingestion
- **Estimated Monthly Cost**: €10-20

## Total Cost Breakdown (Monthly)

| Service | Estimated Cost (EUR) |
|---------|---------------------|
| Azure Container Apps (Dedicated) | €150-300 |
| Azure API Management (Standard) | €180-200 |
| Azure Database for PostgreSQL | €120-250 |
| Azure Cache for Redis | €40-50 |
| Azure Blob Storage (ZRS) | €15-30 |
| Azure Key Vault | €3-5 |
| Application Insights | €50-100 |
| Azure Container Registry | €20 |
| Azure Monitor | €10-20 |
| **Total** | **€588-975/month** |

**Contingency Buffer (20%)**: €120-200
**Final Estimate**: **€500-1500/month**

## Performance Targets

### Latency
- **Job Submission**: < 500ms (99th percentile)
- **Job Status Check**: < 200ms (cached), < 500ms (uncached)
- **Job Result Retrieval**: < 1s (99th percentile)
- **Total Processing Time**: 15-40 seconds (depends on number of guidelines)

### Throughput
- **Concurrent Jobs**: Up to 10 simultaneous compliance checks
- **Daily Capacity**: 5,000-10,000 articles/day
- **Peak Load**: 50-100 requests/minute

### Availability
- **Uptime Target**: 99.5% (monthly)
- **Allowed Downtime**: ~3.6 hours/month
- **Recovery Time Objective (RTO)**: < 15 minutes
- **Recovery Point Objective (RPO)**: < 5 minutes

## Data Flow with Caching

```
1. User triggers compliance check in Word Add-in
   ↓
2. Add-in sends POST /api/v1/compliance/check
   ↓
3. API Management checks cache for duplicate article (optional)
   ↓
4. If cache miss → Forward to Container Apps
   ↓
5. FastAPI creates job_id, stores in Redis + PostgreSQL
   ↓
6. FastAPI returns 202 Accepted with job_id
   ↓
7. Add-in polls GET /jobs/{job_id}/status
   ↓
8. API Management returns cached status (if available, 5 min TTL)
   ↓
9. If cache miss → Query Redis for job status
   ↓
10. If Redis miss → Query PostgreSQL
    ↓
11. Cache result in Redis for next poll
    ↓
12. FastAPI async worker processes job in background
    - Load article from Blob Storage
    - Execute N parallel guideline checks
    - Cache intermediate results in Redis
    - Update job status in Redis + PostgreSQL
    - Store final results in PostgreSQL
    ↓
13. Add-in fetches GET /jobs/{job_id}/result
    ↓
14. API Management serves cached result (if recent, 15 min TTL)
    ↓
15. If cache miss → Query PostgreSQL and cache result
```

## Redis Caching Strategy

### Cache Keys
```
job:status:{job_id}          → Job status (TTL: 5 min)
job:result:{job_id}          → Compliance results (TTL: 15 min)
user:ratelimit:{user_id}     → Rate limit counter (TTL: 1 min)
article:hash:{content_hash}  → Duplicate detection (TTL: 1 hour)
```

### Cache Invalidation
- **On Job Completion**: Update `job:status:{job_id}` and `job:result:{job_id}`
- **On Job Failure**: Remove cached entries
- **Manual**: Admin API to clear cache for specific job

## Auto-Scaling Configuration

### Scale-Out Rules (Add Instances)
```yaml
scale_rules:
  - name: cpu-scale-out
    type: cpu
    metadata:
      type: Utilization
      value: "70"

  - name: memory-scale-out
    type: memory
    metadata:
      type: Utilization
      value: "75"

  - name: queue-depth-scale-out
    type: http
    metadata:
      concurrentRequests: "100"
```

### Scale-In Rules (Remove Instances)
```yaml
scale_rules:
  - name: cpu-scale-in
    type: cpu
    metadata:
      type: Utilization
      value: "30"
    cooldown_period: 300  # 5 minutes before scaling in
```

## Monitoring and Alerts

### Key Metrics to Track

#### Application Metrics
- **Request Rate**: Requests/second
- **Error Rate**: % failed requests
- **Response Time**: P50, P95, P99 latency
- **Job Processing Time**: Average time per guideline check
- **Queue Depth**: Number of pending jobs

#### Infrastructure Metrics
- **CPU Utilization**: Per instance and aggregate
- **Memory Usage**: Per instance and aggregate
- **Database Connections**: Active connections count
- **Redis Hit Rate**: % cache hits vs misses
- **Blob Storage Throughput**: Read/write operations

### Alert Configuration

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| High Error Rate | Error rate > 5% for 5 min | Critical | Page on-call engineer |
| Slow Response | P99 latency > 5s for 10 min | High | Send Slack notification |
| Database CPU High | CPU > 85% for 15 min | High | Alert DBA team |
| Redis Unavailable | Redis down for 1 min | Critical | Page on-call engineer |
| Low Cache Hit Rate | Cache hit rate < 50% | Medium | Investigate caching strategy |
| Scaling Limit | Max replicas reached | High | Consider architecture upgrade |

### Custom Dashboards

**Operations Dashboard**:
- Real-time request rate and error rate
- Active job count and queue depth
- Instance count and auto-scaling events
- Resource utilization (CPU, memory)

**Business Metrics Dashboard**:
- Daily active users
- Articles checked per day
- Average compliance score
- Most frequently triggered guidelines

## Enhanced Security

### Network Security
- **Private Endpoints**: Container Apps → PostgreSQL, Redis (optional, +€50/month)
- **VNet Integration**: Isolate backend services
- **API Management IP Restrictions**: Whitelist known IPs (if applicable)

### Authentication & Authorization
- **Azure AD B2C**: For external users (if needed)
- **API Keys**: For service-to-service calls
- **JWT Token Validation**: Strict token expiration (15 min)

### Secrets Rotation
- **Automated**: Key Vault secrets auto-rotation (90 days)
- **Manual**: Database passwords, API keys (on schedule)

## Database Optimization

### Connection Pooling
```python
# FastAPI database connection pool
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

engine = create_engine(
    DB_CONNECTION_STRING,
    poolclass=QueuePool,
    pool_size=20,         # Max connections per instance
    max_overflow=10,      # Extra connections if needed
    pool_pre_ping=True,   # Verify connection before use
    pool_recycle=3600     # Recycle connections every hour
)
```

### Index Optimization
```sql
-- Add indexes for frequent queries
CREATE INDEX idx_jobs_status_created ON jobs(status, created_at DESC);
CREATE INDEX idx_jobs_user_status ON jobs(user_id, status);
CREATE INDEX idx_results_job_guideline ON compliance_results(job_id, guideline_id);

-- Covering index for job status checks
CREATE INDEX idx_jobs_status_lookup ON jobs(job_id, status, updated_at);
```

### Query Optimization
- Use `EXPLAIN ANALYZE` to identify slow queries
- Implement pagination for large result sets
- Use read replica for analytics queries

## Deployment Strategy

### Blue-Green Deployment
```bash
# Deploy new version to "green" environment
az containerapp update \
  --name compliance-api-green \
  --image {acr}.azurecr.io/compliance-api:v2.0

# Run smoke tests on green environment
./scripts/smoke-test.sh https://green.compliance-api.com

# Switch traffic to green (API Management routing)
az apim api update \
  --backend-url https://green.compliance-api.com

# Monitor for 10 minutes
# If issues: rollback to blue
# If success: decommission blue
```

### Zero-Downtime Migration
- Use API versioning (`/api/v1`, `/api/v2`)
- Maintain backward compatibility for 1 release cycle
- Gradual traffic shift (10% → 50% → 100%)

## When to Scale to Large Architecture

Migrate to Large Scale when you observe:
- **User Growth**: Approaching 8,000-10,000 users/day
- **Geographic Expansion**: Users from multiple regions experiencing latency
- **Scaling Limits**: Frequently hitting max 10 replicas
- **Database Bottleneck**: Read queries slowing down despite optimization
- **Compliance Requirements**: Need for multi-region data residency
- **Availability Requirements**: Need for 99.9%+ uptime SLA

See [Migration Guide](./MIGRATION_GUIDE.md) for step-by-step upgrade path to Large Scale.

---

**Document Version**: 1.0
**Last Updated**: 2025-10-02
**Target Audience**: Production deployment, 1K-10K users/day
