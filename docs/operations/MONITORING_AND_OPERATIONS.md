# Monitoring and Operations Guide

## Overview

This guide provides comprehensive instructions for monitoring, operating, and troubleshooting the Marketing Content Compliance Assistant on Azure. It covers Application Insights configuration, key metrics, dashboards, alerting, and incident response procedures.

## Table of Contents

- [Application Insights Setup](#application-insights-setup)
- [Key Metrics and KPIs](#key-metrics-and-kpis)
- [Dashboard Configuration](#dashboard-configuration)
- [Alert Rules and Thresholds](#alert-rules-and-thresholds)
- [Troubleshooting Guide](#troubleshooting-guide)
- [Performance Optimization](#performance-optimization)
- [Incident Response](#incident-response)
- [Log Analytics](#log-analytics)
- [Custom Kusto Queries](#custom-kusto-queries)

## Application Insights Setup

### Create Application Insights

```bash
# Set variables
RESOURCE_GROUP="rg-compliance-westeurope"
LOCATION="westeurope"
APP_INSIGHTS_NAME="appi-compliance-westeurope"
LOG_ANALYTICS_WORKSPACE="log-compliance-westeurope"

# Create Log Analytics Workspace
az monitor log-analytics workspace create \
  --resource-group ${RESOURCE_GROUP} \
  --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
  --location ${LOCATION}

# Get workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group ${RESOURCE_GROUP} \
  --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
  --query id -o tsv)

# Create Application Insights
az monitor app-insights component create \
  --app ${APP_INSIGHTS_NAME} \
  --location ${LOCATION} \
  --resource-group ${RESOURCE_GROUP} \
  --workspace ${WORKSPACE_ID} \
  --application-type web

# Get instrumentation key and connection string
INSTRUMENTATION_KEY=$(az monitor app-insights component show \
  --app ${APP_INSIGHTS_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query instrumentationKey -o tsv)

CONNECTION_STRING=$(az monitor app-insights component show \
  --app ${APP_INSIGHTS_NAME} \
  --resource-group ${RESOURCE_GROUP} \
  --query connectionString -o tsv)

echo "Instrumentation Key: ${INSTRUMENTATION_KEY}"
echo "Connection String: ${CONNECTION_STRING}"
```

### Configure Application Code

**app/monitoring.py:**

```python
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry import trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
import logging
import os

# Configure Azure Monitor
def configure_monitoring(app):
    """Configure Application Insights monitoring"""
    connection_string = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")

    if connection_string:
        # Configure Azure Monitor
        configure_azure_monitor(
            connection_string=connection_string,
            logger_name="compliance_api"
        )

        # Instrument FastAPI
        FastAPIInstrumentor.instrument_app(app)

        # Instrument HTTP clients
        HTTPXClientInstrumentor().instrument()

        # Instrument database
        SQLAlchemyInstrumentor().instrument()

        # Instrument Redis
        RedisInstrumentor().instrument()

        # Configure logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )

        logger = logging.getLogger("compliance_api")
        logger.info("Application Insights configured successfully")

        return logger
    else:
        logging.warning("Application Insights connection string not found")
        return logging.getLogger("compliance_api")

# Custom telemetry
def track_custom_event(name: str, properties: dict = None):
    """Track custom event"""
    tracer = trace.get_tracer(__name__)
    with tracer.start_as_current_span(name) as span:
        if properties:
            for key, value in properties.items():
                span.set_attribute(key, value)

def track_custom_metric(name: str, value: float, properties: dict = None):
    """Track custom metric"""
    from opentelemetry import metrics
    meter = metrics.get_meter(__name__)
    counter = meter.create_counter(name)
    counter.add(value, properties or {})
```

**app/main.py:**

```python
from fastapi import FastAPI, Request
from app.monitoring import configure_monitoring, track_custom_event, track_custom_metric
import time
import logging

app = FastAPI(title="Compliance API")

# Configure monitoring
logger = configure_monitoring(app)

# Middleware for request tracking
@app.middleware("http")
async def track_requests(request: Request, call_next):
    """Track request metrics"""
    start_time = time.time()

    # Process request
    response = await call_next(request)

    # Calculate duration
    duration = time.time() - start_time

    # Track metrics
    track_custom_metric(
        "request_duration_seconds",
        duration,
        {
            "method": request.method,
            "path": request.url.path,
            "status_code": str(response.status_code)
        }
    )

    # Log request
    logger.info(
        f"{request.method} {request.url.path} - {response.status_code} - {duration:.3f}s"
    )

    return response

# Track compliance job
@app.post("/api/v1/compliance/check")
async def submit_compliance_check(request: ComplianceCheckRequest):
    """Submit compliance check with tracking"""
    job_id = generate_job_id()

    # Track event
    track_custom_event(
        "compliance_job_submitted",
        {
            "job_id": job_id,
            "num_guidelines": len(request.guidelines),
            "article_length": len(request.article_text)
        }
    )

    # Track metric
    track_custom_metric("compliance_jobs_submitted", 1)

    # Process job
    # ...

    return {"job_id": job_id, "status": "queued"}
```

### Enable Distributed Tracing

```python
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

async def check_compliance(article_text: str, guidelines: list):
    """Check compliance with distributed tracing"""
    tracer = trace.get_tracer(__name__)

    with tracer.start_as_current_span("compliance_check") as span:
        span.set_attribute("article_length", len(article_text))
        span.set_attribute("num_guidelines", len(guidelines))

        try:
            # Extract content
            with tracer.start_as_current_span("extract_content") as extract_span:
                content = extract_content(article_text)
                extract_span.set_attribute("content_length", len(content))

            # Check each guideline
            results = []
            for i, guideline in enumerate(guidelines):
                with tracer.start_as_current_span(f"check_guideline_{i}") as gl_span:
                    gl_span.set_attribute("guideline_id", guideline)

                    result = await check_single_guideline(content, guideline)
                    results.append(result)

                    gl_span.set_attribute("compliant", result["compliant"])
                    gl_span.set_attribute("confidence", result["confidence"])

            # Aggregate results
            with tracer.start_as_current_span("aggregate_results") as agg_span:
                overall_score = sum(r["score"] for r in results) / len(results)
                agg_span.set_attribute("overall_score", overall_score)

            span.set_status(Status(StatusCode.OK))
            return {"overall_score": overall_score, "results": results}

        except Exception as e:
            span.set_status(Status(StatusCode.ERROR, str(e)))
            span.record_exception(e)
            raise
```

## Key Metrics and KPIs

### Application Metrics

| Metric | Description | Target | Critical Threshold |
|--------|-------------|--------|-------------------|
| **Request Rate** | Requests per minute | N/A | > 500/min (small), > 2000/min (large) |
| **Error Rate** | Failed requests % | < 1% | > 5% |
| **Latency (p50)** | 50th percentile response time | < 200ms | > 500ms |
| **Latency (p95)** | 95th percentile response time | < 500ms | > 2000ms |
| **Latency (p99)** | 99th percentile response time | < 1000ms | > 5000ms |
| **Availability** | Uptime percentage | > 99.9% | < 99% |

### Business Metrics

| Metric | Description | Target | Alert Threshold |
|--------|-------------|--------|----------------|
| **Job Success Rate** | Completed jobs % | > 95% | < 90% |
| **Job Processing Time** | Average time to complete | < 30s | > 60s |
| **Compliance Score Avg** | Average compliance score | N/A | < 0.5 |
| **Active Users** | Daily active users | N/A | Trend down > 20% |

### Infrastructure Metrics

| Metric | Description | Target | Alert Threshold |
|--------|-------------|--------|----------------|
| **CPU Usage** | Container CPU utilization | < 70% | > 85% |
| **Memory Usage** | Container memory utilization | < 80% | > 90% |
| **Database Connections** | Active DB connections | < 80% of pool | > 90% of pool |
| **Cache Hit Rate** | Redis cache hit rate | > 80% | < 50% |
| **Blob Storage Ops** | Storage operations/sec | N/A | > 10000/sec |

### Custom Metrics Implementation

**app/metrics.py:**

```python
from opentelemetry import metrics
from typing import Dict, Any
import time

class MetricsCollector:
    """Collect and track custom metrics"""

    def __init__(self):
        self.meter = metrics.get_meter(__name__)

        # Request metrics
        self.request_counter = self.meter.create_counter(
            "http_requests_total",
            description="Total HTTP requests"
        )

        self.request_duration = self.meter.create_histogram(
            "http_request_duration_seconds",
            description="HTTP request duration"
        )

        # Job metrics
        self.job_submitted_counter = self.meter.create_counter(
            "compliance_jobs_submitted_total",
            description="Total compliance jobs submitted"
        )

        self.job_completed_counter = self.meter.create_counter(
            "compliance_jobs_completed_total",
            description="Total compliance jobs completed"
        )

        self.job_failed_counter = self.meter.create_counter(
            "compliance_jobs_failed_total",
            description="Total compliance jobs failed"
        )

        self.job_duration = self.meter.create_histogram(
            "compliance_job_duration_seconds",
            description="Compliance job processing duration"
        )

        # Compliance metrics
        self.compliance_score = self.meter.create_histogram(
            "compliance_score",
            description="Compliance score distribution"
        )

        self.violations_counter = self.meter.create_counter(
            "compliance_violations_total",
            description="Total compliance violations"
        )

        # Azure OpenAI metrics
        self.openai_requests_counter = self.meter.create_counter(
            "openai_requests_total",
            description="Total OpenAI API requests"
        )

        self.openai_tokens_counter = self.meter.create_counter(
            "openai_tokens_total",
            description="Total OpenAI tokens used"
        )

    def track_request(self, method: str, path: str, status_code: int, duration: float):
        """Track HTTP request"""
        attributes = {
            "method": method,
            "path": path,
            "status_code": str(status_code)
        }

        self.request_counter.add(1, attributes)
        self.request_duration.record(duration, attributes)

    def track_job_submitted(self, num_guidelines: int, article_length: int):
        """Track job submission"""
        attributes = {
            "num_guidelines": str(num_guidelines),
            "article_length_bucket": self._get_length_bucket(article_length)
        }

        self.job_submitted_counter.add(1, attributes)

    def track_job_completed(self, duration: float, score: float, num_violations: int):
        """Track job completion"""
        self.job_completed_counter.add(1)
        self.job_duration.record(duration)
        self.compliance_score.record(score)
        self.violations_counter.add(num_violations, {"severity": "all"})

    def track_job_failed(self, error_type: str):
        """Track job failure"""
        self.job_failed_counter.add(1, {"error_type": error_type})

    def track_openai_request(self, model: str, tokens: int, success: bool):
        """Track OpenAI API request"""
        attributes = {
            "model": model,
            "success": str(success)
        }

        self.openai_requests_counter.add(1, attributes)
        if success:
            self.openai_tokens_counter.add(tokens, {"model": model})

    def _get_length_bucket(self, length: int) -> str:
        """Bucket article length"""
        if length < 1000:
            return "small"
        elif length < 5000:
            return "medium"
        else:
            return "large"

# Global metrics collector
metrics_collector = MetricsCollector()
```

## Dashboard Configuration

### Azure Portal Dashboard

Create a custom dashboard in Azure Portal:

```json
{
  "properties": {
    "lenses": {
      "0": {
        "order": 0,
        "parts": {
          "0": {
            "position": {
              "x": 0,
              "y": 0,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "type": "Extension/HubsExtension/PartType/MonitorChartPart",
              "settings": {
                "content": {
                  "options": {
                    "chart": {
                      "metrics": [
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{sub-id}/resourceGroups/rg-compliance-westeurope/providers/Microsoft.App/containerApps/ca-compliance-api-westeurope"
                          },
                          "name": "Requests",
                          "aggregationType": 1,
                          "namespace": "microsoft.app/containerapps",
                          "metricVisualization": {
                            "displayName": "Requests"
                          }
                        }
                      ],
                      "title": "Request Rate",
                      "titleKind": 2,
                      "visualization": {
                        "chartType": 2
                      }
                    }
                  }
                }
              }
            }
          },
          "1": {
            "position": {
              "x": 6,
              "y": 0,
              "colSpan": 6,
              "rowSpan": 4
            },
            "metadata": {
              "type": "Extension/HubsExtension/PartType/MonitorChartPart",
              "settings": {
                "content": {
                  "options": {
                    "chart": {
                      "metrics": [
                        {
                          "resourceMetadata": {
                            "id": "/subscriptions/{sub-id}/resourceGroups/rg-compliance-westeurope/providers/Microsoft.Insights/components/appi-compliance-westeurope"
                          },
                          "name": "requests/failed",
                          "aggregationType": 1,
                          "namespace": "microsoft.insights/components",
                          "metricVisualization": {
                            "displayName": "Failed Requests"
                          }
                        }
                      ],
                      "title": "Error Rate",
                      "titleKind": 2
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

### Grafana Dashboard

Install Grafana and configure Azure Monitor data source:

**grafana-dashboard.json:**

```json
{
  "dashboard": {
    "title": "Compliance API Monitoring",
    "panels": [
      {
        "id": 1,
        "title": "Request Rate",
        "type": "graph",
        "targets": [
          {
            "queryType": "Azure Monitor",
            "azureMonitor": {
              "resourceGroup": "rg-compliance-westeurope",
              "resourceName": "appi-compliance-westeurope",
              "metricName": "requests/count",
              "aggregation": "count"
            }
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 0
        }
      },
      {
        "id": 2,
        "title": "Response Time (p95)",
        "type": "graph",
        "targets": [
          {
            "queryType": "Azure Monitor",
            "azureMonitor": {
              "resourceGroup": "rg-compliance-westeurope",
              "resourceName": "appi-compliance-westeurope",
              "metricName": "requests/duration",
              "aggregation": "percentile",
              "dimensionFilters": [
                {
                  "dimension": "percentile",
                  "operator": "eq",
                  "filter": "95"
                }
              ]
            }
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 12,
          "y": 0
        }
      },
      {
        "id": 3,
        "title": "Error Rate",
        "type": "stat",
        "targets": [
          {
            "queryType": "Azure Monitor",
            "azureMonitor": {
              "resourceGroup": "rg-compliance-westeurope",
              "resourceName": "appi-compliance-westeurope",
              "metricName": "requests/failed",
              "aggregation": "sum"
            }
          }
        ],
        "gridPos": {
          "h": 4,
          "w": 6,
          "x": 0,
          "y": 8
        }
      },
      {
        "id": 4,
        "title": "Job Processing Time",
        "type": "graph",
        "targets": [
          {
            "queryType": "Azure Log Analytics",
            "query": "customMetrics | where name == 'compliance_job_duration_seconds' | summarize avg(value) by bin(timestamp, 5m)"
          }
        ],
        "gridPos": {
          "h": 8,
          "w": 12,
          "x": 0,
          "y": 12
        }
      }
    ]
  }
}
```

## Alert Rules and Thresholds

### Create Alert Rules

**High Error Rate Alert:**

```bash
# Create action group
az monitor action-group create \
  --name ag-compliance-alerts \
  --resource-group rg-compliance-westeurope \
  --short-name CompAlerts \
  --email-receiver name=DevOps email=devops@company.com \
  --webhook-receiver name=Slack uri=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Create alert for high error rate
az monitor metrics alert create \
  --name alert-high-error-rate \
  --resource-group rg-compliance-westeurope \
  --scopes /subscriptions/{sub-id}/resourceGroups/rg-compliance-westeurope/providers/Microsoft.Insights/components/appi-compliance-westeurope \
  --condition "avg requests/failed > 10" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action ag-compliance-alerts \
  --description "Error rate exceeds 10 requests per 5 minutes"
```

**High Latency Alert:**

```bash
az monitor metrics alert create \
  --name alert-high-latency \
  --resource-group rg-compliance-westeurope \
  --scopes /subscriptions/{sub-id}/resourceGroups/rg-compliance-westeurope/providers/Microsoft.Insights/components/appi-compliance-westeurope \
  --condition "avg requests/duration > 2000" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action ag-compliance-alerts \
  --description "Average response time exceeds 2 seconds"
```

**Low Availability Alert:**

```bash
az monitor metrics alert create \
  --name alert-low-availability \
  --resource-group rg-compliance-westeurope \
  --scopes /subscriptions/{sub-id}/resourceGroups/rg-compliance-westeurope/providers/Microsoft.App/containerApps/ca-compliance-api-westeurope \
  --condition "avg Replicas < 1" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action ag-compliance-alerts \
  --severity 0 \
  --description "No active replicas - service is down"
```

**Database Connection Alert:**

```bash
# Log-based alert
az monitor scheduled-query create \
  --name alert-high-db-connections \
  --resource-group rg-compliance-westeurope \
  --scopes /subscriptions/{sub-id}/resourceGroups/rg-compliance-westeurope/providers/Microsoft.Insights/components/appi-compliance-westeurope \
  --condition "count > 0" \
  --condition-query "customMetrics | where name == 'database_connections' and value > 180" \
  --window-size 5m \
  --evaluation-frequency 5m \
  --action ag-compliance-alerts \
  --description "Database connections exceed 90% of pool size (180/200)"
```

### Alert Configuration as Code

**alerts.bicep:**

```bicep
param location string = 'westeurope'
param appInsightsName string = 'appi-compliance-westeurope'
param actionGroupName string = 'ag-compliance-alerts'

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' existing = {
  name: actionGroupName
}

// High Error Rate Alert
resource highErrorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-error-rate'
  location: 'global'
  properties: {
    description: 'Error rate exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighErrorRate'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// High Latency Alert
resource highLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-latency'
  location: 'global'
  properties: {
    description: 'Response time exceeds 2 seconds'
    severity: 2
    enabled: true
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighLatency'
          metricName: 'requests/duration'
          operator: 'GreaterThan'
          threshold: 2000
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}
```

## Troubleshooting Guide

### Common Issues

#### Issue 1: High Latency

**Symptoms:**
- Response times > 2 seconds
- Slow API responses
- User complaints about performance

**Diagnosis:**

```kusto
// Check request duration distribution
requests
| where timestamp > ago(1h)
| summarize
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99),
    avg = avg(duration),
    count = count()
  by bin(timestamp, 5m)
| render timechart

// Find slowest operations
requests
| where timestamp > ago(1h)
| where duration > 2000
| project timestamp, name, duration, resultCode
| order by duration desc
| take 20
```

**Solutions:**

1. **Database Query Optimization:**
   ```sql
   -- Add missing indexes
   CREATE INDEX CONCURRENTLY idx_jobs_created_at ON compliance_jobs(created_at DESC);

   -- Analyze slow queries
   SELECT query, mean_exec_time, calls
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 10;
   ```

2. **Enable Caching:**
   ```python
   # Add Redis caching for frequently accessed data
   @cache.memoize(timeout=300)
   async def get_guidelines():
       return await db.fetch_all("SELECT * FROM guidelines")
   ```

3. **Scale Resources:**
   ```bash
   # Increase replicas
   az containerapp update \
     --name ca-compliance-api-westeurope \
     --resource-group rg-compliance-westeurope \
     --min-replicas 5 \
     --max-replicas 20
   ```

#### Issue 2: High Error Rate

**Symptoms:**
- Increased 500 errors
- Failed requests
- Application crashes

**Diagnosis:**

```kusto
// Analyze error types
exceptions
| where timestamp > ago(1h)
| summarize count() by type, outerMessage
| order by count_ desc

// Check failed requests
requests
| where timestamp > ago(1h)
| where success == false
| summarize count() by resultCode, name
| order by count_ desc
```

**Solutions:**

1. **Check Dependencies:**
   ```bash
   # Test database connectivity
   az postgres flexible-server show-connection-string \
     --server-name pg-compliance-westeurope \
     --database-name compliance_db

   # Test Redis connectivity
   redis-cli -h compliance-cache-westeurope.redis.cache.windows.net \
     -p 6380 --tls PING
   ```

2. **Review Logs:**
   ```kusto
   traces
   | where timestamp > ago(1h)
   | where severityLevel >= 3
   | order by timestamp desc
   | take 100
   ```

3. **Check Resource Limits:**
   ```bash
   # Check container resource usage
   az containerapp show \
     --name ca-compliance-api-westeurope \
     --resource-group rg-compliance-westeurope \
     --query properties.template.containers[0].resources
   ```

#### Issue 3: Database Connection Pool Exhausted

**Symptoms:**
- "Too many connections" errors
- Slow database operations
- Connection timeouts

**Diagnosis:**

```sql
-- Check active connections
SELECT count(*) as active_connections
FROM pg_stat_activity
WHERE state = 'active';

-- Check connection by application
SELECT application_name, count(*)
FROM pg_stat_activity
WHERE state != 'idle'
GROUP BY application_name;
```

**Solutions:**

1. **Increase Connection Pool:**
   ```python
   # app/database.py
   engine = create_async_engine(
       database_url,
       pool_size=30,  # Increase from 20
       max_overflow=50,  # Increase from 40
       pool_pre_ping=True,
       pool_recycle=3600
   )
   ```

2. **Fix Connection Leaks:**
   ```python
   # Ensure connections are properly closed
   async def get_db_session():
       async with AsyncSession(engine) as session:
           try:
               yield session
           finally:
               await session.close()
   ```

3. **Scale Database:**
   ```bash
   az postgres flexible-server update \
     --name pg-compliance-westeurope \
     --resource-group rg-compliance-westeurope \
     --sku-name Standard_D4ds_v4
   ```

#### Issue 4: Memory Leaks

**Symptoms:**
- Increasing memory usage
- Container restarts
- Out of memory errors

**Diagnosis:**

```kusto
// Monitor memory usage
performanceCounters
| where timestamp > ago(6h)
| where name == "% Process\\Private Bytes"
| summarize avg(value) by bin(timestamp, 5m)
| render timechart
```

**Solutions:**

1. **Profile Memory Usage:**
   ```python
   # Add memory profiling
   import tracemalloc

   tracemalloc.start()

   # Your code here

   snapshot = tracemalloc.take_snapshot()
   top_stats = snapshot.statistics('lineno')
   for stat in top_stats[:10]:
       print(stat)
   ```

2. **Fix Common Memory Leaks:**
   ```python
   # Close file handles
   with open("file.txt") as f:
       data = f.read()

   # Close HTTP clients
   async with httpx.AsyncClient() as client:
       response = await client.get(url)

   # Clear caches periodically
   @app.on_event("startup")
   async def clear_cache_periodically():
       while True:
           await asyncio.sleep(3600)
           cache.clear()
   ```

## Performance Optimization

### Database Optimization

```sql
-- Create partial indexes for common queries
CREATE INDEX idx_jobs_active ON compliance_jobs(status)
  WHERE status IN ('queued', 'processing');

-- Create covering indexes
CREATE INDEX idx_jobs_status_created ON compliance_jobs(status, created_at DESC)
  INCLUDE (id, user_id);

-- Partition large tables
CREATE TABLE compliance_jobs_2024 PARTITION OF compliance_jobs
  FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

-- Analyze tables
ANALYZE compliance_jobs;
ANALYZE compliance_results;

-- Vacuum tables
VACUUM ANALYZE compliance_jobs;
```

### Caching Strategy

```python
# Multi-level caching
from functools import lru_cache
import redis.asyncio as redis

# L1: In-memory cache (LRU)
@lru_cache(maxsize=1000)
def get_guideline_sync(guideline_id: str):
    """In-memory cache for guidelines"""
    return fetch_guideline_from_db(guideline_id)

# L2: Redis cache
class CachingService:
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.ttl = 600  # 10 minutes

    async def get_or_set(self, key: str, fetch_fn, ttl: int = None):
        """Get from cache or fetch and cache"""
        # Try cache
        cached = await self.redis.get(key)
        if cached:
            return json.loads(cached)

        # Fetch and cache
        value = await fetch_fn()
        await self.redis.setex(
            key,
            ttl or self.ttl,
            json.dumps(value)
        )
        return value

    async def invalidate(self, pattern: str):
        """Invalidate cache by pattern"""
        keys = await self.redis.keys(pattern)
        if keys:
            await self.redis.delete(*keys)

# Usage
cache = CachingService(redis_client)

async def get_guidelines():
    return await cache.get_or_set(
        "guidelines:all",
        lambda: db.fetch_all("SELECT * FROM guidelines"),
        ttl=3600
    )
```

### API Optimization

```python
# Enable HTTP compression
from fastapi.middleware.gzip import GZipMiddleware
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Add response caching
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from fastapi_cache.decorator import cache

@app.on_event("startup")
async def startup():
    redis_client = redis.from_url("redis://localhost")
    FastAPICache.init(RedisBackend(redis_client), prefix="fastapi-cache")

@app.get("/api/v1/guidelines")
@cache(expire=3600)
async def get_guidelines():
    return await fetch_guidelines()

# Implement pagination
@app.get("/api/v1/jobs")
async def list_jobs(skip: int = 0, limit: int = 20):
    jobs = await db.fetch_all(
        "SELECT * FROM compliance_jobs ORDER BY created_at DESC LIMIT :limit OFFSET :skip",
        {"limit": limit, "skip": skip}
    )
    return jobs
```

### Async Processing

```python
# Use background tasks for async processing
from fastapi import BackgroundTasks

@app.post("/api/v1/compliance/check")
async def submit_job(
    request: ComplianceCheckRequest,
    background_tasks: BackgroundTasks
):
    job_id = generate_job_id()

    # Queue job for background processing
    background_tasks.add_task(
        process_compliance_check,
        job_id,
        request
    )

    return {"job_id": job_id, "status": "queued"}

# Use connection pooling
async def process_batch_jobs(jobs: list):
    """Process multiple jobs concurrently"""
    async with asyncio.TaskGroup() as tg:
        tasks = [
            tg.create_task(process_single_job(job))
            for job in jobs
        ]

    return [task.result() for task in tasks]
```

## Incident Response

### Incident Response Procedure

**1. Detection (0-5 minutes)**
- Alert triggered
- On-call engineer notified
- Initial assessment

**2. Triage (5-15 minutes)**
- Determine severity
- Assemble response team
- Create incident ticket

**3. Investigation (15-60 minutes)**
- Review logs and metrics
- Identify root cause
- Test hypothesis

**4. Mitigation (60-120 minutes)**
- Implement fix or workaround
- Deploy changes
- Verify resolution

**5. Post-Mortem (24-48 hours)**
- Document incident
- Identify preventive measures
- Update runbooks

### Severity Levels

| Severity | Description | Response Time | Example |
|----------|-------------|---------------|---------|
| **P0 - Critical** | Complete service outage | < 15 min | API down, database unavailable |
| **P1 - High** | Major feature unavailable | < 30 min | High error rate, critical bugs |
| **P2 - Medium** | Degraded performance | < 2 hours | Slow responses, minor errors |
| **P3 - Low** | Minor issues | < 24 hours | UI glitches, cosmetic bugs |

### Incident Response Checklist

```markdown
## Incident Response Checklist

### Initial Response
- [ ] Acknowledge alert
- [ ] Check monitoring dashboards
- [ ] Verify incident is real (not false positive)
- [ ] Determine severity
- [ ] Create incident ticket
- [ ] Notify team if P0/P1

### Investigation
- [ ] Review recent deployments
- [ ] Check application logs
- [ ] Review error traces
- [ ] Check infrastructure metrics
- [ ] Identify affected users/regions
- [ ] Document findings

### Mitigation
- [ ] Implement rollback if needed
- [ ] Apply hotfix
- [ ] Scale resources if needed
- [ ] Failover to backup region (if applicable)
- [ ] Verify fix in staging
- [ ] Deploy to production
- [ ] Monitor metrics post-deployment

### Communication
- [ ] Update status page
- [ ] Notify stakeholders
- [ ] Send customer communications
- [ ] Update incident ticket

### Post-Incident
- [ ] Schedule post-mortem
- [ ] Document root cause
- [ ] Create action items
- [ ] Update runbooks
- [ ] Close incident ticket
```

## Log Analytics

### Log Analytics Workspace Setup

```bash
# Create workspace
az monitor log-analytics workspace create \
  --resource-group rg-compliance-westeurope \
  --workspace-name log-compliance-westeurope \
  --location westeurope \
  --retention-time 90

# Link Application Insights to Log Analytics
az monitor app-insights component update \
  --app appi-compliance-westeurope \
  --resource-group rg-compliance-westeurope \
  --workspace /subscriptions/{sub-id}/resourceGroups/rg-compliance-westeurope/providers/Microsoft.OperationalInsights/workspaces/log-compliance-westeurope
```

### Common Log Queries

**View Recent Errors:**

```kusto
traces
| where timestamp > ago(1h)
| where severityLevel >= 3
| project timestamp, message, severityLevel, operation_Name
| order by timestamp desc
```

**Analyze Request Patterns:**

```kusto
requests
| where timestamp > ago(24h)
| summarize
    count(),
    avg(duration),
    percentile(duration, 95)
  by bin(timestamp, 1h), name
| render timechart
```

**Track Job Processing:**

```kusto
customEvents
| where timestamp > ago(24h)
| where name == "compliance_job_completed"
| extend
    job_id = tostring(customDimensions.job_id),
    duration = todouble(customDimensions.duration),
    score = todouble(customDimensions.compliance_score)
| summarize
    count(),
    avg(duration),
    avg(score)
  by bin(timestamp, 1h)
| render timechart
```

## Custom Kusto Queries

### Performance Analysis

**Request Duration by Endpoint:**

```kusto
requests
| where timestamp > ago(24h)
| summarize
    count = count(),
    avg_duration = avg(duration),
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99)
  by name
| order by count desc
```

**Slow Requests:**

```kusto
requests
| where timestamp > ago(1h)
| where duration > 2000
| project
    timestamp,
    name,
    duration,
    resultCode,
    operation_Id
| join kind=inner (
    dependencies
    | where timestamp > ago(1h)
  ) on operation_Id
| project
    timestamp,
    request_name = name,
    request_duration = duration,
    dependency_name = name1,
    dependency_duration = duration1,
    dependency_type = type
| order by request_duration desc
```

### Error Analysis

**Error Rate by Type:**

```kusto
exceptions
| where timestamp > ago(24h)
| summarize count() by type, bin(timestamp, 1h)
| render timechart
```

**Correlated Errors:**

```kusto
let ErrorOperations = exceptions
| where timestamp > ago(1h)
| distinct operation_Id;
requests
| where timestamp > ago(1h)
| where operation_Id in (ErrorOperations)
| project timestamp, name, duration, resultCode, operation_Id
| join kind=inner (
    exceptions
    | where timestamp > ago(1h)
  ) on operation_Id
| project
    timestamp,
    request = name,
    error_type = type,
    error_message = outerMessage
```

### Business Metrics

**Compliance Score Distribution:**

```kusto
customMetrics
| where timestamp > ago(7d)
| where name == "compliance_score"
| summarize
    count(),
    avg(value),
    min(value),
    max(value),
    percentile(value, 50),
    percentile(value, 95)
  by bin(timestamp, 1d)
| render timechart
```

**Jobs by Status:**

```kusto
customEvents
| where timestamp > ago(24h)
| where name in ("job_submitted", "job_completed", "job_failed")
| summarize count() by name, bin(timestamp, 1h)
| render timechart
```

### Resource Utilization

**Container CPU Usage:**

```kusto
performanceCounters
| where timestamp > ago(6h)
| where name == "% Processor Time"
| summarize avg(value) by bin(timestamp, 5m)
| render timechart
```

**Database Query Performance:**

```kusto
dependencies
| where timestamp > ago(1h)
| where type == "SQL"
| summarize
    count = count(),
    avg_duration = avg(duration),
    p95 = percentile(duration, 95)
  by name
| order by count desc
```

---

## Summary

This monitoring and operations guide covers:

1. **Application Insights Setup**: Complete configuration for telemetry
2. **Key Metrics**: Critical KPIs to track
3. **Dashboards**: Azure Portal and Grafana configurations
4. **Alerting**: Alert rules and thresholds
5. **Troubleshooting**: Common issues and solutions
6. **Performance Optimization**: Database, caching, and API optimizations
7. **Incident Response**: Procedures and checklists
8. **Log Analytics**: Workspace setup and queries
9. **Kusto Queries**: Custom queries for analysis

For additional support:
- Azure Monitor Documentation: https://docs.microsoft.com/en-us/azure/azure-monitor/
- Kusto Query Language: https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/
- Application Insights: https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview
