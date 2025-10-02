# API Specification: Marketing Content Compliance Assistant

## Overview

This document provides the complete API specification for the Marketing Content Compliance Assistant. The API follows an asynchronous pattern where clients submit jobs, poll for status, and retrieve results when processing is complete.

**Base URL:** `https://apim-compliance-{region}.azure-api.net/api/v1`

**API Version:** v1

**Protocol:** HTTPS only

**Authentication:** Azure AD OAuth 2.0 + API Management Subscription Key

## Table of Contents

- [OpenAPI 3.0 Specification](#openapi-30-specification)
- [Authentication](#authentication)
- [Endpoints](#endpoints)
- [Request/Response Schemas](#requestresponse-schemas)
- [Error Handling](#error-handling)
- [Rate Limiting](#rate-limiting)
- [API Versioning Strategy](#api-versioning-strategy)

## OpenAPI 3.0 Specification

```yaml
openapi: 3.0.3
info:
  title: Marketing Content Compliance Assistant API
  description: |
    Asynchronous API for checking marketing content compliance against configurable guidelines.
    Uses Azure OpenAI and LangGraph for intelligent compliance analysis.
  version: 1.0.0
  contact:
    name: API Support
    email: api-support@company.com
  license:
    name: Proprietary

servers:
  - url: https://apim-compliance-westeurope.azure-api.net/api/v1
    description: Production (West Europe)
  - url: https://apim-compliance-staging.azure-api.net/api/v1
    description: Staging Environment

security:
  - OAuth2: [compliance.read, compliance.write]
  - ApiKeyAuth: []

tags:
  - name: Compliance
    description: Compliance check operations
  - name: Jobs
    description: Job status and results
  - name: Guidelines
    description: Compliance guidelines management

paths:
  /compliance/check:
    post:
      tags:
        - Compliance
      summary: Submit compliance check job
      description: |
        Submits a marketing article for asynchronous compliance checking.
        Returns a job ID that can be used to poll for status and results.
      operationId: submitComplianceCheck
      security:
        - OAuth2: [compliance.write]
        - ApiKeyAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ComplianceCheckRequest'
            examples:
              basic:
                summary: Basic compliance check
                value:
                  article_text: "Discover our new product line with exclusive discounts!"
                  guidelines: ["guideline-001", "guideline-002"]
              with_metadata:
                summary: Check with metadata
                value:
                  article_text: "Join us for an exclusive webinar on AI innovations."
                  guidelines: ["guideline-001", "guideline-002", "guideline-003"]
                  metadata:
                    campaign_id: "campaign-2024-q1"
                    author: "marketing@company.com"
                    content_type: "email"
              blob_reference:
                summary: Check from blob storage
                value:
                  article_blob_url: "https://stcompliance.blob.core.windows.net/articles/article-123.txt"
                  guidelines: ["guideline-001"]
      responses:
        '202':
          description: Job accepted for processing
          headers:
            Location:
              description: URL to check job status
              schema:
                type: string
                format: uri
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/JobAcceptedResponse'
              example:
                job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                status: "queued"
                status_url: "/api/v1/jobs/job-a1b2c3d4-e5f6-7890-abcd-ef1234567890/status"
                created_at: "2024-10-02T14:30:00Z"
                estimated_completion: "2024-10-02T14:30:30Z"
        '400':
          $ref: '#/components/responses/BadRequest'
        '401':
          $ref: '#/components/responses/Unauthorized'
        '403':
          $ref: '#/components/responses/Forbidden'
        '429':
          $ref: '#/components/responses/TooManyRequests'
        '500':
          $ref: '#/components/responses/InternalServerError'

  /jobs/{job_id}/status:
    get:
      tags:
        - Jobs
      summary: Get job status
      description: |
        Retrieves the current status of a compliance check job.
        Poll this endpoint to track job progress.
      operationId: getJobStatus
      security:
        - OAuth2: [compliance.read]
        - ApiKeyAuth: []
      parameters:
        - name: job_id
          in: path
          required: true
          description: Unique job identifier
          schema:
            type: string
            pattern: '^job-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
          example: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      responses:
        '200':
          description: Job status retrieved successfully
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/JobStatusResponse'
              examples:
                queued:
                  summary: Job is queued
                  value:
                    job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                    state: "queued"
                    created_at: "2024-10-02T14:30:00Z"
                    updated_at: "2024-10-02T14:30:00Z"
                processing:
                  summary: Job is processing
                  value:
                    job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                    state: "processing"
                    progress: 45
                    created_at: "2024-10-02T14:30:00Z"
                    updated_at: "2024-10-02T14:30:15Z"
                completed:
                  summary: Job completed
                  value:
                    job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                    state: "completed"
                    progress: 100
                    result_url: "/api/v1/jobs/job-a1b2c3d4-e5f6-7890-abcd-ef1234567890/result"
                    created_at: "2024-10-02T14:30:00Z"
                    updated_at: "2024-10-02T14:30:25Z"
                    completed_at: "2024-10-02T14:30:25Z"
                failed:
                  summary: Job failed
                  value:
                    job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                    state: "failed"
                    error:
                      code: "PROCESSING_ERROR"
                      message: "Failed to analyze content"
                    created_at: "2024-10-02T14:30:00Z"
                    updated_at: "2024-10-02T14:30:20Z"
        '404':
          $ref: '#/components/responses/NotFound'
        '401':
          $ref: '#/components/responses/Unauthorized'
        '500':
          $ref: '#/components/responses/InternalServerError'

  /jobs/{job_id}/result:
    get:
      tags:
        - Jobs
      summary: Get job result
      description: |
        Retrieves the compliance check results for a completed job.
        Only available when job status is 'completed'.
      operationId: getJobResult
      security:
        - OAuth2: [compliance.read]
        - ApiKeyAuth: []
      parameters:
        - name: job_id
          in: path
          required: true
          description: Unique job identifier
          schema:
            type: string
          example: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      responses:
        '200':
          description: Compliance check results
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ComplianceResultResponse'
              example:
                job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                overall_compliance_score: 0.85
                is_compliant: true
                guideline_results:
                  - guideline_id: "guideline-001"
                    guideline_name: "No Unsubstantiated Claims"
                    compliant: true
                    confidence: 0.92
                    explanation: "No unsubstantiated claims detected."
                    violations: []
                  - guideline_id: "guideline-002"
                    guideline_name: "Proper Disclosure Requirements"
                    compliant: false
                    confidence: 0.88
                    explanation: "Missing required disclosure statement."
                    violations:
                      - type: "missing_disclosure"
                        severity: "high"
                        location: "paragraph 3"
                        snippet: "exclusive offer for limited time"
                        suggestion: "Add disclosure: 'Terms and conditions apply.'"
                recommendations:
                  - "Add disclosure statement in paragraph 3"
                  - "Consider rephrasing promotional language"
                metadata:
                  processing_time_ms: 2450
                  model_version: "gpt-4-turbo-2024-04-09"
                  total_guidelines_checked: 2
                created_at: "2024-10-02T14:30:00Z"
                completed_at: "2024-10-02T14:30:25Z"
        '404':
          $ref: '#/components/responses/NotFound'
        '409':
          description: Job not yet completed
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ErrorResponse'
              example:
                error:
                  code: "JOB_NOT_COMPLETED"
                  message: "Job is still processing. Current state: processing"
                  details:
                    job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                    current_state: "processing"
                    status_url: "/api/v1/jobs/job-a1b2c3d4-e5f6-7890-abcd-ef1234567890/status"
        '401':
          $ref: '#/components/responses/Unauthorized'
        '500':
          $ref: '#/components/responses/InternalServerError'

  /guidelines:
    get:
      tags:
        - Guidelines
      summary: List available guidelines
      description: Retrieves all active compliance guidelines
      operationId: listGuidelines
      security:
        - OAuth2: [compliance.read]
        - ApiKeyAuth: []
      parameters:
        - name: active_only
          in: query
          description: Return only active guidelines
          schema:
            type: boolean
            default: true
      responses:
        '200':
          description: List of compliance guidelines
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/GuidelinesListResponse'
              example:
                guidelines:
                  - id: "guideline-001"
                    name: "No Unsubstantiated Claims"
                    description: "Marketing content must not make claims without evidence"
                    category: "advertising"
                    active: true
                    version: 1
                  - id: "guideline-002"
                    name: "Proper Disclosure Requirements"
                    description: "All promotional offers must include proper disclosures"
                    category: "advertising"
                    active: true
                    version: 1
                total_count: 2

components:
  schemas:
    ComplianceCheckRequest:
      type: object
      required:
        - guidelines
      properties:
        article_text:
          type: string
          description: Marketing article text to check
          maxLength: 50000
          example: "Discover our new product line with exclusive discounts!"
        article_blob_url:
          type: string
          format: uri
          description: URL to article in Azure Blob Storage (alternative to article_text)
          example: "https://stcompliance.blob.core.windows.net/articles/article-123.txt"
        guidelines:
          type: array
          description: List of guideline IDs to check against
          minItems: 1
          maxItems: 50
          items:
            type: string
          example: ["guideline-001", "guideline-002"]
        metadata:
          type: object
          description: Optional metadata about the content
          additionalProperties: true
          example:
            campaign_id: "campaign-2024-q1"
            author: "marketing@company.com"
      oneOf:
        - required: [article_text]
        - required: [article_blob_url]

    JobAcceptedResponse:
      type: object
      properties:
        job_id:
          type: string
          description: Unique job identifier
          example: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        status:
          type: string
          enum: [queued]
          example: "queued"
        status_url:
          type: string
          format: uri
          description: URL to check job status
          example: "/api/v1/jobs/job-a1b2c3d4-e5f6-7890-abcd-ef1234567890/status"
        created_at:
          type: string
          format: date-time
          example: "2024-10-02T14:30:00Z"
        estimated_completion:
          type: string
          format: date-time
          description: Estimated completion time
          example: "2024-10-02T14:30:30Z"

    JobStatusResponse:
      type: object
      properties:
        job_id:
          type: string
          example: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        state:
          type: string
          enum: [queued, processing, completed, failed]
          example: "processing"
        progress:
          type: integer
          minimum: 0
          maximum: 100
          description: Processing progress percentage
          example: 45
        result_url:
          type: string
          format: uri
          description: URL to retrieve results (only when completed)
          example: "/api/v1/jobs/job-a1b2c3d4-e5f6-7890-abcd-ef1234567890/result"
        error:
          $ref: '#/components/schemas/ErrorDetail'
        created_at:
          type: string
          format: date-time
          example: "2024-10-02T14:30:00Z"
        updated_at:
          type: string
          format: date-time
          example: "2024-10-02T14:30:15Z"
        completed_at:
          type: string
          format: date-time
          description: Completion timestamp (only when completed/failed)
          example: "2024-10-02T14:30:25Z"

    ComplianceResultResponse:
      type: object
      properties:
        job_id:
          type: string
          example: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        overall_compliance_score:
          type: number
          format: float
          minimum: 0
          maximum: 1
          description: Overall compliance score (0-1)
          example: 0.85
        is_compliant:
          type: boolean
          description: Whether content meets all guidelines
          example: true
        guideline_results:
          type: array
          items:
            $ref: '#/components/schemas/GuidelineResult'
        recommendations:
          type: array
          description: Suggested improvements
          items:
            type: string
          example:
            - "Add disclosure statement in paragraph 3"
        metadata:
          type: object
          properties:
            processing_time_ms:
              type: integer
              example: 2450
            model_version:
              type: string
              example: "gpt-4-turbo-2024-04-09"
            total_guidelines_checked:
              type: integer
              example: 2
        created_at:
          type: string
          format: date-time
        completed_at:
          type: string
          format: date-time

    GuidelineResult:
      type: object
      properties:
        guideline_id:
          type: string
          example: "guideline-001"
        guideline_name:
          type: string
          example: "No Unsubstantiated Claims"
        compliant:
          type: boolean
          example: true
        confidence:
          type: number
          format: float
          minimum: 0
          maximum: 1
          example: 0.92
        explanation:
          type: string
          example: "No unsubstantiated claims detected."
        violations:
          type: array
          items:
            $ref: '#/components/schemas/Violation'

    Violation:
      type: object
      properties:
        type:
          type: string
          example: "missing_disclosure"
        severity:
          type: string
          enum: [low, medium, high, critical]
          example: "high"
        location:
          type: string
          description: Location in the article
          example: "paragraph 3"
        snippet:
          type: string
          description: Relevant text snippet
          example: "exclusive offer for limited time"
        suggestion:
          type: string
          description: Suggested fix
          example: "Add disclosure: 'Terms and conditions apply.'"

    GuidelinesListResponse:
      type: object
      properties:
        guidelines:
          type: array
          items:
            $ref: '#/components/schemas/Guideline'
        total_count:
          type: integer
          example: 2

    Guideline:
      type: object
      properties:
        id:
          type: string
          example: "guideline-001"
        name:
          type: string
          example: "No Unsubstantiated Claims"
        description:
          type: string
          example: "Marketing content must not make claims without evidence"
        category:
          type: string
          example: "advertising"
        active:
          type: boolean
          example: true
        version:
          type: integer
          example: 1

    ErrorResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/ErrorDetail'

    ErrorDetail:
      type: object
      properties:
        code:
          type: string
          example: "INVALID_REQUEST"
        message:
          type: string
          example: "Invalid request parameters"
        details:
          type: object
          additionalProperties: true

  responses:
    BadRequest:
      description: Invalid request
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
          examples:
            missing_field:
              summary: Missing required field
              value:
                error:
                  code: "VALIDATION_ERROR"
                  message: "Missing required field: guidelines"
                  details:
                    field: "guidelines"
                    reason: "Required field is missing"
            invalid_format:
              summary: Invalid format
              value:
                error:
                  code: "VALIDATION_ERROR"
                  message: "Invalid guideline ID format"
                  details:
                    field: "guidelines[0]"
                    value: "invalid-id"
                    expected_format: "guideline-XXX"

    Unauthorized:
      description: Authentication required or failed
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
          example:
            error:
              code: "UNAUTHORIZED"
              message: "Invalid or missing authentication token"

    Forbidden:
      description: Insufficient permissions
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
          example:
            error:
              code: "FORBIDDEN"
              message: "Insufficient permissions to access this resource"
              details:
                required_scope: "compliance.write"

    NotFound:
      description: Resource not found
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
          example:
            error:
              code: "NOT_FOUND"
              message: "Job not found"
              details:
                job_id: "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    TooManyRequests:
      description: Rate limit exceeded
      headers:
        Retry-After:
          description: Seconds to wait before retrying
          schema:
            type: integer
          example: 60
        X-RateLimit-Limit:
          description: Request limit per minute
          schema:
            type: integer
          example: 100
        X-RateLimit-Remaining:
          description: Remaining requests in current window
          schema:
            type: integer
          example: 0
        X-RateLimit-Reset:
          description: Time when rate limit resets (Unix timestamp)
          schema:
            type: integer
          example: 1696262460
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
          example:
            error:
              code: "RATE_LIMIT_EXCEEDED"
              message: "Rate limit exceeded. Please try again later."
              details:
                limit: 100
                window: "1 minute"
                retry_after: 60

    InternalServerError:
      description: Internal server error
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/ErrorResponse'
          example:
            error:
              code: "INTERNAL_ERROR"
              message: "An unexpected error occurred"
              details:
                request_id: "req-123456"

  securitySchemes:
    OAuth2:
      type: oauth2
      description: Azure AD OAuth 2.0 authentication
      flows:
        authorizationCode:
          authorizationUrl: https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/authorize
          tokenUrl: https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token
          scopes:
            compliance.read: Read compliance check results
            compliance.write: Submit compliance checks
    ApiKeyAuth:
      type: apiKey
      in: header
      name: Ocp-Apim-Subscription-Key
      description: API Management subscription key
```

## Authentication

### Azure AD OAuth 2.0 Flow

The API uses Azure AD OAuth 2.0 with the authorization code flow for user authentication.

#### Step 1: Application Registration

Register your application in Azure AD:

```bash
az ad app create \
  --display-name "Compliance Assistant Client" \
  --sign-in-audience AzureADMyOrg \
  --web-redirect-uris "https://your-app.com/auth/callback"

# Note the Application (client) ID and create a client secret
az ad app credential reset \
  --id <app-id> \
  --append
```

#### Step 2: Configure API Permissions

```bash
# Add API permissions
az ad app permission add \
  --id <your-app-id> \
  --api <compliance-api-app-id> \
  --api-permissions <permission-id>=Scope

# Grant admin consent
az ad app permission admin-consent --id <your-app-id>
```

#### Step 3: Obtain Access Token

**Authorization Request:**

```http
GET https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/authorize?
  client_id={client-id}
  &response_type=code
  &redirect_uri=https://your-app.com/auth/callback
  &response_mode=query
  &scope=api://{compliance-api-app-id}/compliance.read api://{compliance-api-app-id}/compliance.write
  &state={random-state}
```

**Token Request:**

```http
POST https://login.microsoftonline.com/{tenant-id}/oauth2/v2.0/token
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code
&client_id={client-id}
&client_secret={client-secret}
&code={authorization-code}
&redirect_uri=https://your-app.com/auth/callback
&scope=api://{compliance-api-app-id}/compliance.read api://{compliance-api-app-id}/compliance.write
```

**Token Response:**

```json
{
  "token_type": "Bearer",
  "expires_in": 3600,
  "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6...",
  "refresh_token": "OAQABAAAAAABeAFzDwllzTYGDLh_qYbH8..."
}
```

#### Step 4: Use Access Token

Include the access token in API requests:

```bash
curl -X POST https://apim-compliance-westeurope.azure-api.net/api/v1/compliance/check \
  -H "Authorization: Bearer {access-token}" \
  -H "Ocp-Apim-Subscription-Key: {subscription-key}" \
  -H "Content-Type: application/json" \
  -d '{
    "article_text": "Your marketing content here",
    "guidelines": ["guideline-001", "guideline-002"]
  }'
```

### API Management Subscription Key

All requests must include the API Management subscription key:

```http
Ocp-Apim-Subscription-Key: your-subscription-key-here
```

Obtain subscription key from Azure Portal:
1. Navigate to API Management instance
2. Go to Subscriptions
3. Create new subscription or use existing
4. Copy primary or secondary key

### Python Authentication Example

```python
import requests
from msal import ConfidentialClientApplication

class ComplianceAPIClient:
    def __init__(
        self,
        tenant_id: str,
        client_id: str,
        client_secret: str,
        subscription_key: str,
        base_url: str
    ):
        self.subscription_key = subscription_key
        self.base_url = base_url

        # Initialize MSAL client
        self.msal_app = ConfidentialClientApplication(
            client_id=client_id,
            client_credential=client_secret,
            authority=f"https://login.microsoftonline.com/{tenant_id}"
        )

        # Define scopes
        self.scopes = [
            f"api://{client_id}/compliance.read",
            f"api://{client_id}/compliance.write"
        ]

    def get_access_token(self) -> str:
        """Acquire access token from Azure AD"""
        # Try to get cached token
        result = self.msal_app.acquire_token_silent(
            scopes=self.scopes,
            account=None
        )

        if not result:
            # Acquire new token
            result = self.msal_app.acquire_token_for_client(
                scopes=self.scopes
            )

        if "access_token" in result:
            return result["access_token"]
        else:
            raise Exception(f"Failed to acquire token: {result.get('error_description')}")

    def _get_headers(self) -> dict:
        """Get request headers with authentication"""
        return {
            "Authorization": f"Bearer {self.get_access_token()}",
            "Ocp-Apim-Subscription-Key": self.subscription_key,
            "Content-Type": "application/json"
        }

    def submit_compliance_check(self, article_text: str, guidelines: list) -> dict:
        """Submit compliance check job"""
        url = f"{self.base_url}/compliance/check"
        payload = {
            "article_text": article_text,
            "guidelines": guidelines
        }

        response = requests.post(url, json=payload, headers=self._get_headers())
        response.raise_for_status()
        return response.json()

    def get_job_status(self, job_id: str) -> dict:
        """Get job status"""
        url = f"{self.base_url}/jobs/{job_id}/status"
        response = requests.get(url, headers=self._get_headers())
        response.raise_for_status()
        return response.json()

    def get_job_result(self, job_id: str) -> dict:
        """Get job result"""
        url = f"{self.base_url}/jobs/{job_id}/result"
        response = requests.get(url, headers=self._get_headers())
        response.raise_for_status()
        return response.json()

# Usage
client = ComplianceAPIClient(
    tenant_id="your-tenant-id",
    client_id="your-client-id",
    client_secret="your-client-secret",
    subscription_key="your-subscription-key",
    base_url="https://apim-compliance-westeurope.azure-api.net/api/v1"
)

# Submit job
job = client.submit_compliance_check(
    article_text="Your marketing content",
    guidelines=["guideline-001", "guideline-002"]
)
print(f"Job submitted: {job['job_id']}")

# Poll for status
import time
while True:
    status = client.get_job_status(job['job_id'])
    print(f"Status: {status['state']}")

    if status['state'] == 'completed':
        result = client.get_job_result(job['job_id'])
        print(f"Compliance score: {result['overall_compliance_score']}")
        break
    elif status['state'] == 'failed':
        print(f"Job failed: {status.get('error')}")
        break

    time.sleep(2)  # Poll every 2 seconds
```

## Endpoints

### POST /api/v1/compliance/check

Submit a marketing article for compliance checking.

**Request Headers:**
- `Authorization: Bearer {token}` (required)
- `Ocp-Apim-Subscription-Key: {key}` (required)
- `Content-Type: application/json` (required)

**Request Body:**
```json
{
  "article_text": "string (max 50,000 chars)",
  "guidelines": ["guideline-id-1", "guideline-id-2"],
  "metadata": {
    "campaign_id": "optional-campaign-id",
    "author": "optional-author"
  }
}
```

**Success Response (202 Accepted):**
```json
{
  "job_id": "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "status": "queued",
  "status_url": "/api/v1/jobs/{job_id}/status",
  "created_at": "2024-10-02T14:30:00Z",
  "estimated_completion": "2024-10-02T14:30:30Z"
}
```

### GET /api/v1/jobs/{job_id}/status

Retrieve the current status of a compliance check job.

**Request Headers:**
- `Authorization: Bearer {token}` (required)
- `Ocp-Apim-Subscription-Key: {key}` (required)

**Path Parameters:**
- `job_id` (string, required): Unique job identifier

**Success Response (200 OK):**
```json
{
  "job_id": "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "state": "processing",
  "progress": 45,
  "created_at": "2024-10-02T14:30:00Z",
  "updated_at": "2024-10-02T14:30:15Z"
}
```

**Job States:**
- `queued`: Job is waiting to be processed
- `processing`: Job is currently being processed
- `completed`: Job has completed successfully
- `failed`: Job has failed

### GET /api/v1/jobs/{job_id}/result

Retrieve compliance check results for a completed job.

**Request Headers:**
- `Authorization: Bearer {token}` (required)
- `Ocp-Apim-Subscription-Key: {key}` (required)

**Path Parameters:**
- `job_id` (string, required): Unique job identifier

**Success Response (200 OK):**
```json
{
  "job_id": "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "overall_compliance_score": 0.85,
  "is_compliant": true,
  "guideline_results": [
    {
      "guideline_id": "guideline-001",
      "guideline_name": "No Unsubstantiated Claims",
      "compliant": true,
      "confidence": 0.92,
      "explanation": "No unsubstantiated claims detected.",
      "violations": []
    }
  ],
  "recommendations": [
    "Consider adding disclosure statement"
  ],
  "metadata": {
    "processing_time_ms": 2450,
    "model_version": "gpt-4-turbo-2024-04-09",
    "total_guidelines_checked": 2
  },
  "created_at": "2024-10-02T14:30:00Z",
  "completed_at": "2024-10-02T14:30:25Z"
}
```

## Request/Response Schemas

### ComplianceCheckRequest

```json
{
  "article_text": "string (optional, max 50,000 chars)",
  "article_blob_url": "string (optional, URI format)",
  "guidelines": ["string", "..."],
  "metadata": {
    "key": "value"
  }
}
```

**Validation Rules:**
- Must provide either `article_text` OR `article_blob_url`, not both
- `guidelines` array must contain 1-50 items
- Each guideline ID must match pattern: `^guideline-[0-9]{3,}$`
- `article_text` maximum length: 50,000 characters
- `metadata` is optional and can contain any JSON-serializable data

### ComplianceResultResponse

```json
{
  "job_id": "string",
  "overall_compliance_score": 0.0-1.0,
  "is_compliant": true|false,
  "guideline_results": [
    {
      "guideline_id": "string",
      "guideline_name": "string",
      "compliant": true|false,
      "confidence": 0.0-1.0,
      "explanation": "string",
      "violations": [
        {
          "type": "string",
          "severity": "low|medium|high|critical",
          "location": "string",
          "snippet": "string",
          "suggestion": "string"
        }
      ]
    }
  ],
  "recommendations": ["string"],
  "metadata": {
    "processing_time_ms": 0,
    "model_version": "string",
    "total_guidelines_checked": 0
  },
  "created_at": "ISO-8601 datetime",
  "completed_at": "ISO-8601 datetime"
}
```

## Error Handling

### Error Response Format

All errors follow a consistent format:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable error message",
    "details": {
      "additional": "context-specific information"
    }
  }
}
```

### HTTP Status Codes

| Status Code | Description | Common Error Codes |
|-------------|-------------|-------------------|
| 400 | Bad Request | `VALIDATION_ERROR`, `INVALID_REQUEST`, `MISSING_FIELD` |
| 401 | Unauthorized | `UNAUTHORIZED`, `INVALID_TOKEN`, `TOKEN_EXPIRED` |
| 403 | Forbidden | `FORBIDDEN`, `INSUFFICIENT_PERMISSIONS` |
| 404 | Not Found | `NOT_FOUND`, `JOB_NOT_FOUND`, `GUIDELINE_NOT_FOUND` |
| 409 | Conflict | `JOB_NOT_COMPLETED`, `DUPLICATE_REQUEST` |
| 429 | Too Many Requests | `RATE_LIMIT_EXCEEDED`, `QUOTA_EXCEEDED` |
| 500 | Internal Server Error | `INTERNAL_ERROR`, `SERVICE_UNAVAILABLE` |
| 502 | Bad Gateway | `UPSTREAM_ERROR`, `OPENAI_ERROR` |
| 503 | Service Unavailable | `SERVICE_UNAVAILABLE`, `MAINTENANCE_MODE` |

### Error Code Details

#### VALIDATION_ERROR (400)

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid guideline ID format",
    "details": {
      "field": "guidelines[0]",
      "value": "invalid-id",
      "expected_format": "guideline-XXX"
    }
  }
}
```

#### UNAUTHORIZED (401)

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid or missing authentication token"
  }
}
```

#### RATE_LIMIT_EXCEEDED (429)

```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Rate limit exceeded. Please try again later.",
    "details": {
      "limit": 100,
      "window": "1 minute",
      "retry_after": 60
    }
  }
}
```

**Response Headers:**
- `Retry-After: 60` (seconds)
- `X-RateLimit-Limit: 100`
- `X-RateLimit-Remaining: 0`
- `X-RateLimit-Reset: 1696262460` (Unix timestamp)

#### JOB_NOT_COMPLETED (409)

```json
{
  "error": {
    "code": "JOB_NOT_COMPLETED",
    "message": "Job is still processing. Current state: processing",
    "details": {
      "job_id": "job-a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "current_state": "processing",
      "status_url": "/api/v1/jobs/{job_id}/status"
    }
  }
}
```

### Error Handling Best Practices

```python
import requests
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

def create_resilient_session():
    """Create session with retry logic"""
    session = requests.Session()

    # Configure retry strategy
    retry_strategy = Retry(
        total=3,
        backoff_factor=1,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "POST"]
    )

    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("https://", adapter)
    session.mount("http://", adapter)

    return session

def submit_with_error_handling(client, article_text, guidelines):
    """Submit job with comprehensive error handling"""
    try:
        response = client.submit_compliance_check(article_text, guidelines)
        return response

    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 400:
            error_data = e.response.json()
            print(f"Validation error: {error_data['error']['message']}")
            # Handle validation errors

        elif e.response.status_code == 401:
            print("Authentication failed. Refreshing token...")
            # Refresh token and retry

        elif e.response.status_code == 429:
            retry_after = int(e.response.headers.get('Retry-After', 60))
            print(f"Rate limit exceeded. Retrying after {retry_after} seconds...")
            time.sleep(retry_after)
            # Retry request

        elif e.response.status_code >= 500:
            print("Server error. Retrying with exponential backoff...")
            # Implement exponential backoff

        raise

    except requests.exceptions.RequestException as e:
        print(f"Network error: {e}")
        raise
```

## Rate Limiting

### Rate Limit Tiers

| Scale Tier | Requests/Minute | Requests/Day | Concurrent Jobs |
|------------|-----------------|--------------|-----------------|
| Small | 100 | 10,000 | 10 |
| Medium | 500 | 50,000 | 50 |
| Large | 2,000 | 200,000 | 200 |

### Rate Limit Headers

Every API response includes rate limit information:

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1696262460
```

- `X-RateLimit-Limit`: Total requests allowed in current window
- `X-RateLimit-Remaining`: Requests remaining in current window
- `X-RateLimit-Reset`: Unix timestamp when rate limit resets

### Rate Limit Exceeded Response

When rate limit is exceeded (HTTP 429):

```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Rate limit exceeded. Please try again later.",
    "details": {
      "limit": 100,
      "window": "1 minute",
      "retry_after": 60
    }
  }
}
```

**Response Headers:**
```http
HTTP/1.1 429 Too Many Requests
Retry-After: 60
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1696262460
```

### Rate Limiting Strategies

#### Client-Side Rate Limiting

```python
import time
from collections import deque
from threading import Lock

class RateLimiter:
    def __init__(self, max_calls: int, period: int = 60):
        self.max_calls = max_calls
        self.period = period
        self.calls = deque()
        self.lock = Lock()

    def __call__(self, func):
        def wrapper(*args, **kwargs):
            with self.lock:
                now = time.time()

                # Remove calls outside the current window
                while self.calls and self.calls[0] <= now - self.period:
                    self.calls.popleft()

                # Check if we can make a call
                if len(self.calls) >= self.max_calls:
                    sleep_time = self.period - (now - self.calls[0])
                    print(f"Rate limit reached. Waiting {sleep_time:.2f}s...")
                    time.sleep(sleep_time)
                    return wrapper(*args, **kwargs)

                # Record this call
                self.calls.append(now)

            return func(*args, **kwargs)
        return wrapper

# Usage
@RateLimiter(max_calls=100, period=60)
def submit_compliance_check(client, article, guidelines):
    return client.submit_compliance_check(article, guidelines)
```

#### Exponential Backoff with Jitter

```python
import random
import time

def exponential_backoff_retry(func, max_retries=5):
    """Retry with exponential backoff and jitter"""
    for attempt in range(max_retries):
        try:
            return func()
        except requests.exceptions.HTTPError as e:
            if e.response.status_code == 429:
                if attempt == max_retries - 1:
                    raise

                # Calculate backoff with jitter
                base_delay = min(60, (2 ** attempt))
                jitter = random.uniform(0, 0.1 * base_delay)
                delay = base_delay + jitter

                print(f"Rate limited. Retrying in {delay:.2f}s (attempt {attempt + 1}/{max_retries})")
                time.sleep(delay)
            else:
                raise
```

## API Versioning Strategy

### Version Format

API versions follow the format: `/api/v{major}`

- Current version: `v1`
- Example: `https://apim-compliance-westeurope.azure-api.net/api/v1/compliance/check`

### Versioning Policy

1. **Major Version (v1, v2, etc.):**
   - Breaking changes that are not backward compatible
   - Changed response schemas
   - Removed endpoints or fields
   - Changed authentication methods

2. **Minor Updates (within v1):**
   - New optional fields
   - New endpoints
   - Enhanced functionality
   - Bug fixes

3. **Version Support:**
   - Each major version is supported for minimum 12 months after next version release
   - Deprecation notices provided 6 months in advance
   - Security updates provided for all supported versions

### Version Lifecycle

```
v1 (Current) ──────────────────────────────────>
                    │
                    v2 Release (2025-Q2)
                    │
                    ├── v1 Deprecated (2025-Q4)
                    │
                    ├── v1 End-of-Life (2026-Q2)
                    │
                    v2 (Current) ──────────────>
```

### Deprecation Headers

Deprecated versions include warning headers:

```http
X-API-Deprecated: true
X-API-Deprecation-Date: 2025-10-01
X-API-Sunset-Date: 2026-04-01
X-API-Upgrade-Guide: https://docs.company.com/api/migration/v1-to-v2
```

### Version Detection

```python
def check_api_version(response):
    """Check if API version is deprecated"""
    if response.headers.get('X-API-Deprecated') == 'true':
        deprecation_date = response.headers.get('X-API-Deprecation-Date')
        sunset_date = response.headers.get('X-API-Sunset-Date')
        upgrade_guide = response.headers.get('X-API-Upgrade-Guide')

        print(f"⚠️  API version deprecated as of {deprecation_date}")
        print(f"   End-of-life: {sunset_date}")
        print(f"   Upgrade guide: {upgrade_guide}")
```

### Future Versions (Planned)

**v2 (Planned Q2 2025):**
- GraphQL support
- Webhook notifications for job completion
- Batch job submission
- Real-time compliance checking (WebSocket)
- Enhanced guideline customization

**Migration Support:**
- Dual-version support during transition period
- Automated migration tools
- Comprehensive migration documentation
- Backward compatibility layer where possible

---

## Additional Resources

- [Authentication Guide](./MICROSOFT_WORD_INTEGRATION.md#authentication)
- [Error Handling Best Practices](#error-handling)
- [Rate Limiting Strategies](#rate-limiting-strategies)
- [SDK Documentation](https://github.com/company/compliance-api-sdk)
- [Postman Collection](https://www.postman.com/company/compliance-api)

## Support

For API support:
- Email: api-support@company.com
- Developer Portal: https://developer.company.com
- Status Page: https://status.company.com
- GitHub Issues: https://github.com/company/compliance-api/issues
