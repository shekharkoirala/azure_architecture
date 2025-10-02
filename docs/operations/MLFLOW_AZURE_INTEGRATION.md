# MLflow Azure Integration Guide

## Overview

This document describes the integration of MLflow with the Marketing Content Compliance Assistant on Azure. MLflow provides experiment tracking, model versioning, and monitoring capabilities for the LangGraph-based compliance checking pipeline.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [MLflow Setup on Azure Container Apps](#mlflow-setup-on-azure-container-apps)
- [PostgreSQL Backend Configuration](#postgresql-backend-configuration)
- [Blob Storage for Artifacts](#blob-storage-for-artifacts)
- [Experiment Tracking](#experiment-tracking)
- [Model Registry Integration](#model-registry-integration)
- [Python Integration Examples](#python-integration-examples)
- [Dashboard and Visualization](#dashboard-and-visualization)
- [Best Practices](#best-practices)

## Architecture Overview

### MLflow Components

```
┌──────────────────────────────────────────────────────────────┐
│                     MLflow Architecture                       │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────┐         ┌────────────────┐              │
│  │   MLflow UI    │         │  MLflow API    │              │
│  │ (Container App)│◄────────┤  (REST/gRPC)   │              │
│  └────────┬───────┘         └────────┬───────┘              │
│           │                          │                       │
│           ▼                          ▼                       │
│  ┌────────────────────────────────────────────┐             │
│  │       MLflow Tracking Server               │             │
│  │      (Azure Container Apps)                │             │
│  └────────┬────────────────────┬───────────────┘            │
│           │                    │                             │
│           ▼                    ▼                             │
│  ┌────────────────┐   ┌────────────────┐                   │
│  │   PostgreSQL   │   │  Blob Storage  │                   │
│  │   (Metadata)   │   │  (Artifacts)   │                   │
│  └────────────────┘   └────────────────┘                   │
│                                                               │
└──────────────────────────────────────────────────────────────┘
          ▲                                    ▲
          │                                    │
    ┌─────┴─────┐                      ┌──────┴──────┐
    │ FastAPI   │                      │   LangGraph │
    │ App       │                      │   Pipeline  │
    └───────────┘                      └─────────────┘
```

### Component Responsibilities

| Component | Responsibility | Storage |
|-----------|---------------|---------|
| **MLflow Tracking Server** | Logs experiments, parameters, metrics | PostgreSQL |
| **MLflow UI** | Visualize experiments, compare runs | N/A |
| **PostgreSQL** | Metadata, parameters, metrics, tags | Managed Database |
| **Blob Storage** | Model artifacts, plots, large files | Object Storage |
| **MLflow API** | Programmatic access to tracking | N/A |

## MLflow Setup on Azure Container Apps

### Infrastructure Deployment

**mlflow-deployment.bicep:**

```bicep
param location string = 'westeurope'
param environmentName string = 'cae-compliance-westeurope'
param postgresServer string = 'pg-compliance-westeurope'
param postgresDatabaseName string = 'mlflow_db'
param storageAccountName string = 'stcompliancewesteurope'
param mlflowContainerName string = 'mlflow-artifacts'

// MLflow Tracking Server Container App
resource mlflowApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'ca-mlflow-westeurope'
  location: location
  properties: {
    managedEnvironmentId: resourceId('Microsoft.App/managedEnvironments', environmentName)
    configuration: {
      ingress: {
        external: true
        targetPort: 5000
        transport: 'http'
        allowInsecure: false
      }
      secrets: [
        {
          name: 'postgres-connection-string'
          value: 'postgresql://${postgresUsername}:${postgresPassword}@${postgresServer}.postgres.database.azure.com:5432/${postgresDatabaseName}?sslmode=require'
        }
        {
          name: 'storage-connection-string'
          value: listKeys(resourceId('Microsoft.Storage/storageAccounts', storageAccountName), '2023-01-01').keys[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'mlflow-server'
          image: 'ghcr.io/mlflow/mlflow:v2.9.2'
          command: [
            'mlflow'
            'server'
            '--host'
            '0.0.0.0'
            '--port'
            '5000'
            '--backend-store-uri'
            'postgresql://${postgresServer}.postgres.database.azure.com:5432/${postgresDatabaseName}'
            '--default-artifact-root'
            'wasbs://${mlflowContainerName}@${storageAccountName}.blob.core.windows.net/'
            '--serve-artifacts'
          ]
          env: [
            {
              name: 'AZURE_STORAGE_CONNECTION_STRING'
              secretRef: 'storage-connection-string'
            }
            {
              name: 'MLFLOW_TRACKING_USERNAME'
              value: 'admin'
            }
            {
              name: 'MLFLOW_TRACKING_PASSWORD'
              secretRef: 'mlflow-password'
            }
          ]
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Output MLflow endpoint
output mlflowEndpoint string = mlflowApp.properties.configuration.ingress.fqdn
```

### Deployment via Azure CLI

```bash
# Create resource group (if not exists)
az group create \
  --name rg-compliance-westeurope \
  --location westeurope

# Create Blob Storage container for MLflow artifacts
az storage container create \
  --name mlflow-artifacts \
  --account-name stcompliancewesteurope \
  --public-access off

# Create PostgreSQL database for MLflow
az postgres flexible-server db create \
  --resource-group rg-compliance-westeurope \
  --server-name pg-compliance-westeurope \
  --database-name mlflow_db

# Deploy MLflow using Docker
az containerapp create \
  --name ca-mlflow-westeurope \
  --resource-group rg-compliance-westeurope \
  --environment cae-compliance-westeurope \
  --image ghcr.io/mlflow/mlflow:v2.9.2 \
  --target-port 5000 \
  --ingress external \
  --cpu 1 \
  --memory 2Gi \
  --min-replicas 1 \
  --max-replicas 3 \
  --env-vars \
    MLFLOW_BACKEND_STORE_URI="secretref:postgres-connection-string" \
    MLFLOW_DEFAULT_ARTIFACT_ROOT="wasbs://mlflow-artifacts@stcompliancewesteurope.blob.core.windows.net/" \
    AZURE_STORAGE_CONNECTION_STRING="secretref:storage-connection-string" \
  --secrets \
    postgres-connection-string="postgresql://adminuser:password@pg-compliance-westeurope.postgres.database.azure.com:5432/mlflow_db?sslmode=require" \
    storage-connection-string="DefaultEndpointsProtocol=https;AccountName=..."

# Get MLflow endpoint
az containerapp show \
  --name ca-mlflow-westeurope \
  --resource-group rg-compliance-westeurope \
  --query properties.configuration.ingress.fqdn \
  --output tsv
```

### Custom MLflow Dockerfile

For production deployments, create a custom Dockerfile with additional dependencies:

**Dockerfile.mlflow:**

```dockerfile
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install MLflow and dependencies
RUN pip install --no-cache-dir \
    mlflow==2.9.2 \
    psycopg2-binary==2.9.9 \
    azure-storage-blob==12.19.0 \
    azure-identity==1.15.0 \
    gunicorn==21.2.0

# Create mlflow user
RUN useradd -m -u 1000 mlflow
USER mlflow

# Set working directory
WORKDIR /home/mlflow

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import requests; requests.get('http://localhost:5000/health')"

# Start MLflow server
CMD ["mlflow", "server", \
     "--host", "0.0.0.0", \
     "--port", "5000", \
     "--backend-store-uri", "${MLFLOW_BACKEND_STORE_URI}", \
     "--default-artifact-root", "${MLFLOW_DEFAULT_ARTIFACT_ROOT}", \
     "--serve-artifacts", \
     "--gunicorn-opts", "--workers=4 --timeout=120"]
```

Build and push:

```bash
# Build
docker build -t mlflow-azure:v1.0.0 -f Dockerfile.mlflow .

# Tag for ACR
docker tag mlflow-azure:v1.0.0 acrcompliancewesteurope.azurecr.io/mlflow:v1.0.0

# Push to ACR
az acr login --name acrcompliancewesteurope
docker push acrcompliancewesteurope.azurecr.io/mlflow:v1.0.0
```

## PostgreSQL Backend Configuration

### Database Schema Initialization

MLflow automatically creates the necessary tables, but you can verify:

```sql
-- Connect to mlflow_db
\c mlflow_db

-- List MLflow tables
\dt

-- Expected tables:
-- experiments
-- runs
-- metrics
-- params
-- tags
-- experiment_tags
-- registered_models
-- model_versions
-- latest_metrics
```

### PostgreSQL Optimization for MLflow

```sql
-- Create indexes for better query performance
CREATE INDEX idx_runs_experiment_id ON runs(experiment_id);
CREATE INDEX idx_runs_start_time ON runs(start_time DESC);
CREATE INDEX idx_runs_user_id ON runs(user_id);
CREATE INDEX idx_metrics_run_uuid ON metrics(run_uuid);
CREATE INDEX idx_metrics_key ON metrics(key);
CREATE INDEX idx_params_run_uuid ON params(run_uuid);
CREATE INDEX idx_tags_run_uuid ON tags(run_uuid);

-- Set connection pool parameters
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET work_mem = '16MB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';

-- Reload configuration
SELECT pg_reload_conf();

-- Enable query logging for debugging
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_duration = on;
```

### Connection String Configuration

**config/mlflow_config.py:**

```python
from pydantic_settings import BaseSettings
from typing import Optional

class MLflowConfig(BaseSettings):
    # PostgreSQL backend store
    postgres_host: str
    postgres_port: int = 5432
    postgres_db: str = "mlflow_db"
    postgres_user: str
    postgres_password: str
    postgres_ssl_mode: str = "require"

    # Azure Blob Storage artifact store
    storage_account_name: str
    storage_account_key: str
    artifacts_container: str = "mlflow-artifacts"

    # MLflow server
    mlflow_tracking_uri: str
    mlflow_tracking_username: Optional[str] = None
    mlflow_tracking_password: Optional[str] = None

    @property
    def backend_store_uri(self) -> str:
        """PostgreSQL connection string"""
        return (
            f"postgresql://{self.postgres_user}:{self.postgres_password}"
            f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
            f"?sslmode={self.postgres_ssl_mode}"
        )

    @property
    def artifact_root(self) -> str:
        """Azure Blob Storage artifact root"""
        return (
            f"wasbs://{self.artifacts_container}"
            f"@{self.storage_account_name}.blob.core.windows.net/"
        )

    @property
    def azure_storage_connection_string(self) -> str:
        """Azure Storage connection string"""
        return (
            f"DefaultEndpointsProtocol=https;"
            f"AccountName={self.storage_account_name};"
            f"AccountKey={self.storage_account_key};"
            f"EndpointSuffix=core.windows.net"
        )

    class Config:
        env_file = ".env"
        env_prefix = "MLFLOW_"
```

## Blob Storage for Artifacts

### Container Structure

```
mlflow-artifacts/
├── 0/                          # Experiment ID
│   ├── abc123.../              # Run ID
│   │   ├── artifacts/
│   │   │   ├── model/          # Model files
│   │   │   │   ├── model.pkl
│   │   │   │   ├── requirements.txt
│   │   │   │   └── conda.yaml
│   │   │   ├── plots/          # Visualization plots
│   │   │   │   ├── confusion_matrix.png
│   │   │   │   └── feature_importance.png
│   │   │   └── data/           # Data snapshots
│   │   │       └── sample.json
│   │   └── metrics/            # Metric files (if any)
│   └── def456.../
└── 1/
    └── ...
```

### Blob Storage Configuration

```bash
# Create container with lifecycle management
az storage container create \
  --name mlflow-artifacts \
  --account-name stcompliancewesteurope \
  --public-access off

# Set lifecycle policy (optional - archive old artifacts)
cat > lifecycle-policy.json << 'EOF'
{
  "rules": [
    {
      "enabled": true,
      "name": "archive-old-artifacts",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 90
            },
            "delete": {
              "daysAfterModificationGreaterThan": 365
            }
          }
        },
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["mlflow-artifacts/"]
        }
      }
    }
  ]
}
EOF

az storage account management-policy create \
  --account-name stcompliancewesteurope \
  --policy @lifecycle-policy.json
```

### Artifact Logging

```python
import mlflow
import matplotlib.pyplot as plt
import json

# Log model artifacts
mlflow.log_artifact("path/to/model.pkl", artifact_path="model")

# Log plots
fig, ax = plt.subplots()
ax.plot([1, 2, 3], [4, 5, 6])
plt.savefig("plot.png")
mlflow.log_artifact("plot.png", artifact_path="plots")
plt.close()

# Log JSON data
data = {"key": "value"}
with open("data.json", "w") as f:
    json.dump(data, f)
mlflow.log_artifact("data.json", artifact_path="data")

# Log entire directory
mlflow.log_artifacts("local_dir", artifact_path="artifacts")
```

## Experiment Tracking

### Experiment Organization

```python
import mlflow
from mlflow_config import MLflowConfig

# Initialize configuration
config = MLflowConfig()
mlflow.set_tracking_uri(config.mlflow_tracking_uri)

# Create experiments for different use cases
EXPERIMENTS = {
    "compliance_check": "Compliance Check Pipeline",
    "guideline_optimization": "Guideline Optimization",
    "model_comparison": "Model A/B Testing"
}

def create_experiments():
    """Create MLflow experiments"""
    for exp_name, description in EXPERIMENTS.items():
        try:
            experiment_id = mlflow.create_experiment(
                name=exp_name,
                artifact_location=f"{config.artifact_root}{exp_name}/",
                tags={
                    "team": "ml-engineering",
                    "project": "compliance-assistant",
                    "environment": "production"
                }
            )
            print(f"Created experiment '{exp_name}' with ID: {experiment_id}")
        except Exception as e:
            print(f"Experiment '{exp_name}' already exists or error: {e}")
```

### Logging Parameters and Metrics

```python
import mlflow
from datetime import datetime
from typing import Dict, Any

class ComplianceTracker:
    """MLflow tracking wrapper for compliance checks"""

    def __init__(self, experiment_name: str = "compliance_check"):
        self.experiment_name = experiment_name
        mlflow.set_experiment(experiment_name)

    def start_run(self, run_name: str, tags: Dict[str, str] = None) -> str:
        """Start a new MLflow run"""
        run = mlflow.start_run(run_name=run_name, tags=tags)
        return run.info.run_id

    def log_compliance_job(
        self,
        job_id: str,
        article_text: str,
        guidelines: list,
        model_config: dict
    ):
        """Log compliance check job details"""
        with mlflow.start_run(run_name=f"compliance_{job_id}") as run:
            # Log parameters
            mlflow.log_param("job_id", job_id)
            mlflow.log_param("article_length", len(article_text))
            mlflow.log_param("word_count", len(article_text.split()))
            mlflow.log_param("num_guidelines", len(guidelines))
            mlflow.log_param("guidelines", ",".join(guidelines))

            # Log model configuration
            mlflow.log_param("model_name", model_config.get("model_name"))
            mlflow.log_param("temperature", model_config.get("temperature"))
            mlflow.log_param("max_tokens", model_config.get("max_tokens"))

            # Log tags
            mlflow.set_tag("job_type", "compliance_check")
            mlflow.set_tag("timestamp", datetime.utcnow().isoformat())

            return run.info.run_id

    def log_compliance_result(
        self,
        run_id: str,
        result: Dict[str, Any],
        processing_time_ms: int
    ):
        """Log compliance check results"""
        with mlflow.start_run(run_id=run_id):
            # Log metrics
            mlflow.log_metric("compliance_score", result["overall_compliance_score"])
            mlflow.log_metric("processing_time_ms", processing_time_ms)
            mlflow.log_metric("num_violations", sum(
                len(gr["violations"]) for gr in result["guideline_results"]
            ))

            # Log individual guideline scores
            for gr in result["guideline_results"]:
                metric_name = f"guideline_{gr['guideline_id']}_score"
                mlflow.log_metric(metric_name, 1.0 if gr["compliant"] else 0.0)
                mlflow.log_metric(f"{metric_name}_confidence", gr["confidence"])

            # Log summary metrics
            mlflow.log_metric("is_compliant", 1.0 if result["is_compliant"] else 0.0)

            # Log artifacts
            import json
            with open("result.json", "w") as f:
                json.dump(result, f, indent=2)
            mlflow.log_artifact("result.json", artifact_path="results")

    def log_error(self, run_id: str, error: Exception):
        """Log error information"""
        with mlflow.start_run(run_id=run_id):
            mlflow.set_tag("status", "failed")
            mlflow.set_tag("error_type", type(error).__name__)
            mlflow.set_tag("error_message", str(error))
            mlflow.log_metric("success", 0.0)
```

### Integration with FastAPI

```python
from fastapi import FastAPI, BackgroundTasks
from app.tracking import ComplianceTracker
from app.compliance import ComplianceChecker

app = FastAPI()
tracker = ComplianceTracker()

@app.post("/api/v1/compliance/check")
async def submit_compliance_check(
    request: ComplianceCheckRequest,
    background_tasks: BackgroundTasks
):
    """Submit compliance check with MLflow tracking"""
    job_id = generate_job_id()

    # Start MLflow run
    run_id = tracker.log_compliance_job(
        job_id=job_id,
        article_text=request.article_text,
        guidelines=request.guidelines,
        model_config={
            "model_name": "gpt-4-turbo",
            "temperature": 0.0,
            "max_tokens": 4000
        }
    )

    # Process in background
    background_tasks.add_task(
        process_compliance_check,
        job_id,
        run_id,
        request
    )

    return {
        "job_id": job_id,
        "mlflow_run_id": run_id,
        "status": "queued"
    }

async def process_compliance_check(
    job_id: str,
    run_id: str,
    request: ComplianceCheckRequest
):
    """Process compliance check and log to MLflow"""
    import time
    start_time = time.time()

    try:
        # Run compliance check
        checker = ComplianceChecker()
        result = await checker.check_compliance(
            article_text=request.article_text,
            guidelines=request.guidelines
        )

        # Calculate processing time
        processing_time_ms = int((time.time() - start_time) * 1000)

        # Log results to MLflow
        tracker.log_compliance_result(run_id, result, processing_time_ms)

        # Update job status
        await update_job_status(job_id, "completed", result)

    except Exception as e:
        # Log error to MLflow
        tracker.log_error(run_id, e)
        await update_job_status(job_id, "failed", str(e))
```

### LangGraph Integration

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict, Annotated
import mlflow
import operator

class ComplianceState(TypedDict):
    article_text: str
    guidelines: list
    current_guideline: int
    results: Annotated[list, operator.add]
    mlflow_run_id: str

def log_to_mlflow(key: str, value: Any):
    """Helper to log to current MLflow run"""
    mlflow.log_metric(key, value)

# Define nodes
def initialize_check(state: ComplianceState) -> ComplianceState:
    """Initialize compliance check"""
    mlflow.log_param("total_guidelines", len(state["guidelines"]))
    mlflow.log_param("article_length", len(state["article_text"]))
    return state

def check_guideline(state: ComplianceState) -> ComplianceState:
    """Check single guideline"""
    import time
    start = time.time()

    guideline_id = state["guidelines"][state["current_guideline"]]

    # Perform check
    result = perform_guideline_check(
        state["article_text"],
        guideline_id
    )

    # Log metrics for this guideline
    mlflow.log_metric(
        f"guideline_{guideline_id}_time_ms",
        int((time.time() - start) * 1000),
        step=state["current_guideline"]
    )
    mlflow.log_metric(
        f"guideline_{guideline_id}_score",
        result["score"],
        step=state["current_guideline"]
    )

    state["results"].append(result)
    state["current_guideline"] += 1

    return state

def should_continue(state: ComplianceState) -> str:
    """Check if more guidelines to process"""
    if state["current_guideline"] < len(state["guidelines"]):
        return "check_guideline"
    return END

def aggregate_results(state: ComplianceState) -> ComplianceState:
    """Aggregate all guideline results"""
    overall_score = sum(r["score"] for r in state["results"]) / len(state["results"])

    mlflow.log_metric("overall_compliance_score", overall_score)
    mlflow.log_metric("num_violations", sum(
        len(r.get("violations", [])) for r in state["results"]
    ))

    return state

# Build graph
workflow = StateGraph(ComplianceState)

workflow.add_node("initialize", initialize_check)
workflow.add_node("check_guideline", check_guideline)
workflow.add_node("aggregate", aggregate_results)

workflow.set_entry_point("initialize")
workflow.add_edge("initialize", "check_guideline")
workflow.add_conditional_edges(
    "check_guideline",
    should_continue,
    {
        "check_guideline": "check_guideline",
        END: "aggregate"
    }
)
workflow.add_edge("aggregate", END)

app = workflow.compile()

# Run with MLflow tracking
def run_compliance_check(article_text: str, guidelines: list):
    """Run compliance check with MLflow tracking"""
    with mlflow.start_run(run_name="compliance_check") as run:
        state = {
            "article_text": article_text,
            "guidelines": guidelines,
            "current_guideline": 0,
            "results": [],
            "mlflow_run_id": run.info.run_id
        }

        result = app.invoke(state)
        return result
```

## Model Registry Integration

### Registering Models

```python
import mlflow
from mlflow.models import infer_signature

class ModelRegistry:
    """Manage ML models in MLflow registry"""

    @staticmethod
    def register_compliance_model(
        model,
        model_name: str,
        model_version: str,
        signature=None,
        tags: dict = None
    ):
        """Register a compliance model"""
        with mlflow.start_run() as run:
            # Log model
            if signature is None:
                # Infer signature from sample data
                sample_input = {"text": "Sample article", "guidelines": ["g1"]}
                sample_output = {"score": 0.95, "compliant": True}
                signature = infer_signature(sample_input, sample_output)

            mlflow.pyfunc.log_model(
                artifact_path="model",
                python_model=model,
                signature=signature,
                registered_model_name=model_name
            )

            # Add tags
            if tags:
                for key, value in tags.items():
                    mlflow.set_tag(key, value)

            # Transition to staging
            client = mlflow.tracking.MlflowClient()
            model_version_obj = client.search_model_versions(
                f"name='{model_name}'"
            )[0]

            client.transition_model_version_stage(
                name=model_name,
                version=model_version_obj.version,
                stage="Staging"
            )

            return model_version_obj.version

    @staticmethod
    def promote_to_production(model_name: str, version: str):
        """Promote model to production"""
        client = mlflow.tracking.MlflowClient()

        # Archive current production models
        for mv in client.search_model_versions(f"name='{model_name}'"):
            if mv.current_stage == "Production":
                client.transition_model_version_stage(
                    name=model_name,
                    version=mv.version,
                    stage="Archived"
                )

        # Promote new version
        client.transition_model_version_stage(
            name=model_name,
            version=version,
            stage="Production"
        )

    @staticmethod
    def load_production_model(model_name: str):
        """Load current production model"""
        model_uri = f"models:/{model_name}/Production"
        model = mlflow.pyfunc.load_model(model_uri)
        return model
```

## Python Integration Examples

### Complete Integration Example

**app/mlflow_integration.py:**

```python
import mlflow
import mlflow.pyfunc
from mlflow.tracking import MlflowClient
from typing import Dict, Any, List
from datetime import datetime
import json
import time

class MLflowIntegration:
    """Complete MLflow integration for Compliance Assistant"""

    def __init__(self, tracking_uri: str, experiment_name: str):
        mlflow.set_tracking_uri(tracking_uri)
        mlflow.set_experiment(experiment_name)
        self.client = MlflowClient()

    def track_compliance_check(
        self,
        job_id: str,
        article_text: str,
        guidelines: List[str],
        model_config: Dict[str, Any],
        metadata: Dict[str, Any] = None
    ):
        """Complete tracking for compliance check"""

        run = mlflow.start_run(run_name=f"compliance_{job_id}")
        run_id = run.info.run_id

        try:
            # Log parameters
            self._log_parameters(
                job_id, article_text, guidelines, model_config, metadata
            )

            # Log system info
            self._log_system_info()

            # Execute compliance check
            start_time = time.time()
            result = self._execute_compliance_check(
                article_text, guidelines, model_config
            )
            processing_time = time.time() - start_time

            # Log metrics
            self._log_metrics(result, processing_time)

            # Log artifacts
            self._log_artifacts(result, article_text)

            # Success
            mlflow.set_tag("status", "success")

            return run_id, result

        except Exception as e:
            # Log error
            mlflow.set_tag("status", "failed")
            mlflow.set_tag("error_type", type(e).__name__)
            mlflow.set_tag("error_message", str(e))
            raise

        finally:
            mlflow.end_run()

    def _log_parameters(
        self,
        job_id: str,
        article_text: str,
        guidelines: List[str],
        model_config: Dict[str, Any],
        metadata: Dict[str, Any]
    ):
        """Log all parameters"""
        # Job info
        mlflow.log_param("job_id", job_id)
        mlflow.log_param("timestamp", datetime.utcnow().isoformat())

        # Article info
        mlflow.log_param("article_length", len(article_text))
        mlflow.log_param("word_count", len(article_text.split()))
        mlflow.log_param("num_guidelines", len(guidelines))

        # Guidelines (as comma-separated string if not too long)
        guidelines_str = ",".join(guidelines)
        if len(guidelines_str) < 500:  # MLflow param limit
            mlflow.log_param("guidelines", guidelines_str)
        else:
            mlflow.log_param("guidelines", f"{len(guidelines)} guidelines")

        # Model config
        for key, value in model_config.items():
            mlflow.log_param(f"model_{key}", value)

        # Metadata
        if metadata:
            for key, value in metadata.items():
                if isinstance(value, (str, int, float, bool)):
                    mlflow.log_param(f"meta_{key}", value)

    def _log_system_info(self):
        """Log system information"""
        import platform
        import psutil

        mlflow.log_param("python_version", platform.python_version())
        mlflow.log_param("platform", platform.platform())
        mlflow.log_param("cpu_count", psutil.cpu_count())
        mlflow.log_param("memory_gb", round(psutil.virtual_memory().total / 1e9, 2))

    def _log_metrics(self, result: Dict[str, Any], processing_time: float):
        """Log all metrics"""
        # Overall metrics
        mlflow.log_metric("overall_compliance_score", result["overall_compliance_score"])
        mlflow.log_metric("is_compliant", 1.0 if result["is_compliant"] else 0.0)
        mlflow.log_metric("processing_time_seconds", processing_time)
        mlflow.log_metric("processing_time_ms", int(processing_time * 1000))

        # Guideline metrics
        total_violations = 0
        for idx, gr in enumerate(result["guideline_results"]):
            prefix = f"guideline_{idx}"
            mlflow.log_metric(f"{prefix}_compliant", 1.0 if gr["compliant"] else 0.0)
            mlflow.log_metric(f"{prefix}_confidence", gr["confidence"])
            mlflow.log_metric(f"{prefix}_violations", len(gr["violations"]))
            total_violations += len(gr["violations"])

        mlflow.log_metric("total_violations", total_violations)

        # Violation severity breakdown
        severity_counts = {"low": 0, "medium": 0, "high": 0, "critical": 0}
        for gr in result["guideline_results"]:
            for v in gr["violations"]:
                severity_counts[v["severity"]] += 1

        for severity, count in severity_counts.items():
            mlflow.log_metric(f"violations_{severity}", count)

    def _log_artifacts(self, result: Dict[str, Any], article_text: str):
        """Log artifacts"""
        # Save result as JSON
        with open("compliance_result.json", "w") as f:
            json.dump(result, f, indent=2)
        mlflow.log_artifact("compliance_result.json", artifact_path="results")

        # Save article text
        with open("article.txt", "w") as f:
            f.write(article_text)
        mlflow.log_artifact("article.txt", artifact_path="input")

        # Create and log visualization
        self._create_visualization(result)
        mlflow.log_artifact("compliance_chart.png", artifact_path="visualizations")

    def _create_visualization(self, result: Dict[str, Any]):
        """Create compliance visualization"""
        import matplotlib.pyplot as plt
        import numpy as np

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

        # Overall score gauge
        score = result["overall_compliance_score"]
        ax1.pie(
            [score, 1 - score],
            labels=["Compliant", "Non-Compliant"],
            autopct='%1.1f%%',
            colors=['#107c10', '#d13438'],
            startangle=90
        )
        ax1.set_title(f'Overall Compliance: {score:.1%}')

        # Guideline results bar chart
        guideline_names = [gr["guideline_name"][:20] for gr in result["guideline_results"]]
        scores = [gr["confidence"] if gr["compliant"] else 0 for gr in result["guideline_results"]]

        y_pos = np.arange(len(guideline_names))
        ax2.barh(y_pos, scores, color=['#107c10' if s > 0 else '#d13438' for s in scores])
        ax2.set_yticks(y_pos)
        ax2.set_yticklabels(guideline_names)
        ax2.set_xlabel('Compliance Score')
        ax2.set_title('Guideline Results')
        ax2.set_xlim([0, 1])

        plt.tight_layout()
        plt.savefig('compliance_chart.png', dpi=150, bbox_inches='tight')
        plt.close()

    def _execute_compliance_check(
        self,
        article_text: str,
        guidelines: List[str],
        model_config: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Execute the actual compliance check"""
        # This would call your actual compliance checking logic
        from app.compliance import ComplianceChecker

        checker = ComplianceChecker(model_config)
        result = checker.check(article_text, guidelines)
        return result

    def compare_runs(self, run_ids: List[str]) -> Dict[str, Any]:
        """Compare multiple runs"""
        runs_data = []

        for run_id in run_ids:
            run = self.client.get_run(run_id)
            runs_data.append({
                "run_id": run_id,
                "params": run.data.params,
                "metrics": run.data.metrics,
                "tags": run.data.tags
            })

        return runs_data

    def get_best_run(self, metric_name: str = "overall_compliance_score") -> str:
        """Get best run by metric"""
        experiment = mlflow.get_experiment_by_name(mlflow.get_experiment().name)
        runs = self.client.search_runs(
            experiment_ids=[experiment.experiment_id],
            order_by=[f"metrics.{metric_name} DESC"],
            max_results=1
        )

        if runs:
            return runs[0].info.run_id
        return None
```

## Dashboard and Visualization

### MLflow UI Access

Access MLflow UI at: `https://ca-mlflow-westeurope.azurecontainerapp.io`

### Custom Dashboards

Create custom dashboards using MLflow API:

**dashboard/compliance_dashboard.py:**

```python
import streamlit as st
import mlflow
from mlflow.tracking import MlflowClient
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# Set up MLflow
mlflow.set_tracking_uri("https://ca-mlflow-westeurope.azurecontainerapp.io")
client = MlflowClient()

st.title("Compliance Check Analytics Dashboard")

# Sidebar filters
experiment_name = st.sidebar.selectbox(
    "Select Experiment",
    ["compliance_check", "guideline_optimization", "model_comparison"]
)

# Get experiment runs
experiment = mlflow.get_experiment_by_name(experiment_name)
runs = client.search_runs(
    experiment_ids=[experiment.experiment_id],
    max_results=100,
    order_by=["start_time DESC"]
)

# Convert to DataFrame
runs_df = pd.DataFrame([
    {
        "run_id": run.info.run_id,
        "start_time": pd.to_datetime(run.info.start_time, unit='ms'),
        "compliance_score": run.data.metrics.get("overall_compliance_score", 0),
        "processing_time_ms": run.data.metrics.get("processing_time_ms", 0),
        "num_violations": run.data.metrics.get("total_violations", 0),
        "article_length": run.data.params.get("article_length", 0),
        "num_guidelines": run.data.params.get("num_guidelines", 0),
        "status": run.data.tags.get("status", "unknown")
    }
    for run in runs
])

# Metrics Overview
col1, col2, col3, col4 = st.columns(4)
col1.metric("Total Runs", len(runs_df))
col2.metric("Avg Compliance Score", f"{runs_df['compliance_score'].mean():.2%}")
col3.metric("Avg Processing Time", f"{runs_df['processing_time_ms'].mean():.0f}ms")
col4.metric("Total Violations", int(runs_df['num_violations'].sum()))

# Compliance Score Over Time
fig_timeline = px.line(
    runs_df,
    x="start_time",
    y="compliance_score",
    title="Compliance Score Over Time",
    labels={"compliance_score": "Compliance Score", "start_time": "Time"}
)
st.plotly_chart(fig_timeline, use_container_width=True)

# Processing Time vs Article Length
fig_scatter = px.scatter(
    runs_df,
    x="article_length",
    y="processing_time_ms",
    size="num_guidelines",
    color="compliance_score",
    title="Processing Time vs Article Length",
    labels={
        "article_length": "Article Length (chars)",
        "processing_time_ms": "Processing Time (ms)",
        "num_guidelines": "# Guidelines"
    }
)
st.plotly_chart(fig_scatter, use_container_width=True)

# Recent Runs Table
st.subheader("Recent Runs")
st.dataframe(runs_df[["run_id", "start_time", "compliance_score", "processing_time_ms", "status"]])
```

## Best Practices

### 1. Experiment Naming

```python
# Good: Descriptive experiment names
mlflow.set_experiment("compliance_check_gpt4_v1")
mlflow.set_experiment("ab_test_temperature_0.0_vs_0.3")

# Bad: Generic names
mlflow.set_experiment("experiment1")
mlflow.set_experiment("test")
```

### 2. Parameter Logging

```python
# Log all relevant parameters
mlflow.log_params({
    "model_name": "gpt-4-turbo",
    "temperature": 0.0,
    "max_tokens": 4000,
    "num_guidelines": len(guidelines),
    "article_word_count": word_count,
    "deployment_env": "production"
})
```

### 3. Metric Logging

```python
# Log metrics at different steps
for i, guideline in enumerate(guidelines):
    score = check_guideline(article, guideline)
    mlflow.log_metric("guideline_score", score, step=i)

# Log summary metrics
mlflow.log_metrics({
    "overall_score": overall_score,
    "processing_time_seconds": processing_time,
    "total_violations": total_violations
})
```

### 4. Tagging

```python
# Use tags for organization and filtering
mlflow.set_tags({
    "team": "ml-engineering",
    "priority": "high",
    "customer_id": "customer_123",
    "deployment_region": "westeurope",
    "model_version": "v2.1.0"
})
```

### 5. Artifact Management

```python
# Organize artifacts in directories
mlflow.log_artifact("model.pkl", artifact_path="model")
mlflow.log_artifact("plot.png", artifact_path="visualizations")
mlflow.log_artifact("config.json", artifact_path="config")

# Log entire directories
mlflow.log_artifacts("results/", artifact_path="results")
```

### 6. Error Handling

```python
with mlflow.start_run():
    try:
        result = process_compliance_check(article, guidelines)
        mlflow.log_metric("success", 1.0)
    except Exception as e:
        mlflow.log_metric("success", 0.0)
        mlflow.set_tag("error", str(e))
        raise
```

### 7. Run Cleanup

```python
# Delete old runs (e.g., failed runs older than 30 days)
from datetime import datetime, timedelta

cutoff_date = datetime.now() - timedelta(days=30)
cutoff_timestamp = int(cutoff_date.timestamp() * 1000)

runs = client.search_runs(
    experiment_ids=[experiment.experiment_id],
    filter_string=f"tags.status = 'failed' AND attributes.start_time < {cutoff_timestamp}"
)

for run in runs:
    client.delete_run(run.info.run_id)
```

---

## Additional Resources

- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)
- [MLflow Azure Integration](https://docs.microsoft.com/en-us/azure/machine-learning/how-to-use-mlflow)
- [LangGraph Documentation](https://langchain-ai.github.io/langgraph/)
- [PostgreSQL on Azure](https://docs.microsoft.com/en-us/azure/postgresql/)

## Support

For MLflow integration support:
- Email: ml-ops@company.com
- Documentation: https://docs.company.com/mlflow
- GitHub: https://github.com/company/compliance-mlflow
