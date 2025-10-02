# Microsoft Word Add-in Integration Guide

## Overview

This document describes the integration architecture for the Marketing Content Compliance Assistant Word Add-in. The Add-in allows users to check compliance of marketing documents directly from Microsoft Word using Office.js APIs.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Office.js API Usage](#officejs-api-usage)
- [API Contract](#api-contract)
- [Authentication Flow](#authentication-flow)
- [Data Flow and Security](#data-flow-and-security)
- [Implementation Guide](#implementation-guide)
- [Polling Strategy](#polling-strategy)
- [Error Handling](#error-handling)
- [UI/UX Recommendations](#uiux-recommendations)

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Microsoft Word                          │
│  ┌───────────────────────────────────────────────────────┐ │
│  │         Compliance Assistant Add-in                   │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐ │ │
│  │  │   UI Task   │  │   Auth      │  │   Content    │ │ │
│  │  │   Pane      │  │   Manager   │  │   Extractor  │ │ │
│  │  └─────────────┘  └─────────────┘  └──────────────┘ │ │
│  │           │              │                  │         │ │
│  │           └──────────────┴──────────────────┘         │ │
│  │                          │                             │ │
│  │                  ┌───────▼────────┐                   │ │
│  │                  │  API Client    │                   │ │
│  │                  └───────┬────────┘                   │ │
│  └──────────────────────────┼──────────────────────────┘ │
└─────────────────────────────┼────────────────────────────┘
                              │ HTTPS
                              ▼
              ┌───────────────────────────┐
              │   Azure API Management    │
              │   (Compliance API)        │
              └───────────┬───────────────┘
                          │
                          ▼
              ┌───────────────────────────┐
              │   Azure Container Apps    │
              │   (FastAPI Backend)       │
              └───────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|---------------|
| **UI Task Pane** | Display results, show progress, user interactions |
| **Auth Manager** | Handle Azure AD authentication, token management |
| **Content Extractor** | Extract text from Word document using Office.js |
| **API Client** | Communicate with backend API, handle retries |

## Office.js API Usage

### Manifest Configuration

**manifest.xml:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<OfficeApp
  xmlns="http://schemas.microsoft.com/office/appforoffice/1.1"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:bt="http://schemas.microsoft.com/office/officeappbasictypes/1.0"
  xmlns:ov="http://schemas.microsoft.com/office/taskpaneappversionoverrides"
  xsi:type="TaskPaneApp">

  <Id>12345678-1234-1234-1234-123456789abc</Id>
  <Version>1.0.0.0</Version>
  <ProviderName>Your Company</ProviderName>
  <DefaultLocale>en-US</DefaultLocale>
  <DisplayName DefaultValue="Compliance Assistant"/>
  <Description DefaultValue="Check marketing content compliance"/>
  <IconUrl DefaultValue="https://your-cdn.com/assets/icon-32.png"/>
  <HighResolutionIconUrl DefaultValue="https://your-cdn.com/assets/icon-64.png"/>
  <SupportUrl DefaultValue="https://support.yourcompany.com"/>

  <AppDomains>
    <AppDomain>https://login.microsoftonline.com</AppDomain>
    <AppDomain>https://apim-compliance-westeurope.azure-api.net</AppDomain>
  </AppDomains>

  <Hosts>
    <Host Name="Document"/>
  </Hosts>

  <DefaultSettings>
    <SourceLocation DefaultValue="https://your-addin.com/taskpane.html"/>
  </DefaultSettings>

  <Permissions>ReadWriteDocument</Permissions>

  <VersionOverrides xmlns="http://schemas.microsoft.com/office/taskpaneappversionoverrides" xsi:type="VersionOverridesV1_0">
    <Hosts>
      <Host xsi:type="Document">
        <DesktopFormFactor>
          <GetStarted>
            <Title resid="GetStarted.Title"/>
            <Description resid="GetStarted.Description"/>
            <LearnMoreUrl resid="GetStarted.LearnMoreUrl"/>
          </GetStarted>

          <FunctionFile resid="Commands.Url"/>

          <ExtensionPoint xsi:type="PrimaryCommandSurface">
            <OfficeTab id="TabHome">
              <Group id="CommandsGroup">
                <Label resid="CommandsGroup.Label"/>
                <Icon>
                  <bt:Image size="16" resid="Icon.16x16"/>
                  <bt:Image size="32" resid="Icon.32x32"/>
                  <bt:Image size="80" resid="Icon.80x80"/>
                </Icon>

                <Control xsi:type="Button" id="TaskpaneButton">
                  <Label resid="TaskpaneButton.Label"/>
                  <Supertip>
                    <Title resid="TaskpaneButton.Label"/>
                    <Description resid="TaskpaneButton.Tooltip"/>
                  </Supertip>
                  <Icon>
                    <bt:Image size="16" resid="Icon.16x16"/>
                    <bt:Image size="32" resid="Icon.32x32"/>
                    <bt:Image size="80" resid="Icon.80x80"/>
                  </Icon>
                  <Action xsi:type="ShowTaskpane">
                    <TaskpaneId>ButtonId1</TaskpaneId>
                    <SourceLocation resid="Taskpane.Url"/>
                  </Action>
                </Control>
              </Group>
            </OfficeTab>
          </ExtensionPoint>
        </DesktopFormFactor>
      </Host>
    </Hosts>

    <Resources>
      <bt:Images>
        <bt:Image id="Icon.16x16" DefaultValue="https://your-cdn.com/assets/icon-16.png"/>
        <bt:Image id="Icon.32x32" DefaultValue="https://your-cdn.com/assets/icon-32.png"/>
        <bt:Image id="Icon.80x80" DefaultValue="https://your-cdn.com/assets/icon-80.png"/>
      </bt:Images>
      <bt:Urls>
        <bt:Url id="GetStarted.LearnMoreUrl" DefaultValue="https://docs.yourcompany.com"/>
        <bt:Url id="Commands.Url" DefaultValue="https://your-addin.com/commands.html"/>
        <bt:Url id="Taskpane.Url" DefaultValue="https://your-addin.com/taskpane.html"/>
      </bt:Urls>
      <bt:ShortStrings>
        <bt:String id="GetStarted.Title" DefaultValue="Get started with Compliance Assistant"/>
        <bt:String id="CommandsGroup.Label" DefaultValue="Compliance"/>
        <bt:String id="TaskpaneButton.Label" DefaultValue="Check Compliance"/>
      </bt:ShortStrings>
      <bt:LongStrings>
        <bt:String id="GetStarted.Description" DefaultValue="Your add-in loaded successfully."/>
        <bt:String id="TaskpaneButton.Tooltip" DefaultValue="Click to check document compliance"/>
      </bt:LongStrings>
    </Resources>
  </VersionOverrides>
</OfficeApp>
```

### Content Extraction

**contentExtractor.js:**

```javascript
/**
 * Content extraction utilities using Office.js
 */

class ContentExtractor {
  /**
   * Extract all text from the Word document
   * @returns {Promise<string>} Document text content
   */
  static async extractFullDocument() {
    return Word.run(async (context) => {
      const body = context.document.body;
      body.load('text');

      await context.sync();

      return body.text;
    });
  }

  /**
   * Extract text from selected portion of document
   * @returns {Promise<string>} Selected text content
   */
  static async extractSelection() {
    return Word.run(async (context) => {
      const selection = context.document.getSelection();
      selection.load('text');

      await context.sync();

      if (!selection.text || selection.text.trim() === '') {
        throw new Error('No text selected');
      }

      return selection.text;
    });
  }

  /**
   * Extract text with formatting information
   * @returns {Promise<Object>} Document structure with formatting
   */
  static async extractWithFormatting() {
    return Word.run(async (context) => {
      const paragraphs = context.document.body.paragraphs;
      paragraphs.load('text,font/bold,font/italic,style');

      await context.sync();

      const content = [];
      for (let i = 0; i < paragraphs.items.length; i++) {
        const para = paragraphs.items[i];
        content.push({
          text: para.text,
          style: para.style,
          bold: para.font.bold,
          italic: para.font.italic
        });
      }

      return content;
    });
  }

  /**
   * Get document metadata
   * @returns {Promise<Object>} Document metadata
   */
  static async getDocumentMetadata() {
    return Word.run(async (context) => {
      const properties = context.document.properties;
      properties.load('title,author,subject,keywords,creationDate,lastModifiedDate');

      await context.sync();

      return {
        title: properties.title,
        author: properties.author,
        subject: properties.subject,
        keywords: properties.keywords,
        createdDate: properties.creationDate,
        lastModifiedDate: properties.lastModifiedDate
      };
    });
  }

  /**
   * Count words in document
   * @returns {Promise<number>} Word count
   */
  static async getWordCount() {
    return Word.run(async (context) => {
      const body = context.document.body;
      const wordCount = body.getRange().getTextRanges([" "], false);
      wordCount.load('items');

      await context.sync();

      return wordCount.items.length;
    });
  }

  /**
   * Highlight text in document
   * @param {Array} violations - Array of violation objects with location info
   */
  static async highlightViolations(violations) {
    return Word.run(async (context) => {
      for (const violation of violations) {
        if (violation.snippet) {
          // Search for the snippet in the document
          const searchResults = context.document.body.search(
            violation.snippet,
            { matchCase: false, matchWholeWord: false }
          );
          searchResults.load('items');

          await context.sync();

          if (searchResults.items.length > 0) {
            // Highlight the first match
            const range = searchResults.items[0];
            range.font.highlightColor = getSeverityColor(violation.severity);

            // Add comment
            range.insertComment(
              `${violation.type}: ${violation.suggestion || violation.explanation}`
            );
          }
        }
      }

      await context.sync();
    });
  }

  /**
   * Insert compliance summary at cursor
   * @param {Object} result - Compliance check result
   */
  static async insertComplianceSummary(result) {
    return Word.run(async (context) => {
      const selection = context.document.getSelection();

      // Create summary text
      let summary = `\n\nCompliance Check Summary\n`;
      summary += `${'='.repeat(50)}\n`;
      summary += `Overall Score: ${(result.overall_compliance_score * 100).toFixed(1)}%\n`;
      summary += `Status: ${result.is_compliant ? 'COMPLIANT' : 'NON-COMPLIANT'}\n`;
      summary += `Guidelines Checked: ${result.metadata.total_guidelines_checked}\n\n`;

      // Add guideline results
      result.guideline_results.forEach((gr, index) => {
        summary += `${index + 1}. ${gr.guideline_name}: ${gr.compliant ? 'PASS' : 'FAIL'}\n`;
        if (!gr.compliant && gr.violations.length > 0) {
          gr.violations.forEach(v => {
            summary += `   - ${v.type} (${v.severity}): ${v.suggestion}\n`;
          });
        }
      });

      // Insert at selection
      selection.insertText(summary, Word.InsertLocation.after);

      await context.sync();
    });
  }
}

/**
 * Get highlight color based on severity
 * @param {string} severity - Violation severity
 * @returns {string} Color code
 */
function getSeverityColor(severity) {
  const colors = {
    'critical': '#FF0000',  // Red
    'high': '#FFA500',      // Orange
    'medium': '#FFFF00',    // Yellow
    'low': '#90EE90'        // Light green
  };
  return colors[severity] || '#FFFF00';
}

export default ContentExtractor;
```

### Document Manipulation

**documentManipulator.js:**

```javascript
/**
 * Document manipulation utilities
 */

class DocumentManipulator {
  /**
   * Create compliance report as new document
   * @param {Object} result - Compliance check result
   */
  static async createComplianceReport(result) {
    return Word.run(async (context) => {
      // Create new document
      const newDoc = context.application.createDocument();
      const body = newDoc.body;

      // Add title
      const title = body.insertParagraph('Compliance Check Report', Word.InsertLocation.start);
      title.styleBuiltIn = Word.Style.title;

      // Add timestamp
      const timestamp = body.insertParagraph(
        `Generated: ${new Date().toLocaleString()}`,
        Word.InsertLocation.end
      );
      timestamp.styleBuiltIn = Word.Style.subtitle;

      // Add overall score
      const scoreSection = body.insertParagraph('Overall Compliance Score', Word.InsertLocation.end);
      scoreSection.styleBuiltIn = Word.Style.heading1;

      const scoreValue = body.insertParagraph(
        `${(result.overall_compliance_score * 100).toFixed(1)}% - ${result.is_compliant ? 'COMPLIANT' : 'NON-COMPLIANT'}`,
        Word.InsertLocation.end
      );
      scoreValue.font.size = 14;
      scoreValue.font.bold = true;
      scoreValue.font.color = result.is_compliant ? '#008000' : '#FF0000';

      // Add guidelines section
      const guidelinesHeader = body.insertParagraph('Guideline Results', Word.InsertLocation.end);
      guidelinesHeader.styleBuiltIn = Word.Style.heading1;

      // Create table for results
      const table = body.insertTable(result.guideline_results.length + 1, 4, Word.InsertLocation.end, [
        ['Guideline', 'Status', 'Confidence', 'Violations']
      ]);

      table.headerRowCount = 1;
      table.styleBuiltIn = Word.Style.gridTable1Light;

      // Fill table
      result.guideline_results.forEach((gr, index) => {
        const row = table.rows.items[index + 1];
        row.cells.items[0].body.insertText(gr.guideline_name, Word.InsertLocation.replace);
        row.cells.items[1].body.insertText(gr.compliant ? 'PASS' : 'FAIL', Word.InsertLocation.replace);
        row.cells.items[2].body.insertText(`${(gr.confidence * 100).toFixed(0)}%`, Word.InsertLocation.replace);
        row.cells.items[3].body.insertText(gr.violations.length.toString(), Word.InsertLocation.replace);

        // Color code status
        row.cells.items[1].body.font.color = gr.compliant ? '#008000' : '#FF0000';
      });

      // Add violations section
      if (result.guideline_results.some(gr => gr.violations.length > 0)) {
        const violationsHeader = body.insertParagraph('Detailed Violations', Word.InsertLocation.end);
        violationsHeader.styleBuiltIn = Word.Style.heading1;

        result.guideline_results.forEach(gr => {
          if (gr.violations.length > 0) {
            const guidelineHeader = body.insertParagraph(gr.guideline_name, Word.InsertLocation.end);
            guidelineHeader.styleBuiltIn = Word.Style.heading2;

            gr.violations.forEach(v => {
              const violationPara = body.insertParagraph(
                `• ${v.type} (${v.severity}): ${v.suggestion}`,
                Word.InsertLocation.end
              );
              violationPara.leftIndent = 20;
            });
          }
        });
      }

      // Add recommendations
      if (result.recommendations && result.recommendations.length > 0) {
        const recommendationsHeader = body.insertParagraph('Recommendations', Word.InsertLocation.end);
        recommendationsHeader.styleBuiltIn = Word.Style.heading1;

        result.recommendations.forEach(rec => {
          body.insertParagraph(`• ${rec}`, Word.InsertLocation.end);
        });
      }

      // Open the new document
      newDoc.open();

      await context.sync();
    });
  }

  /**
   * Insert content control for tracking
   * @param {string} jobId - Job ID to track
   */
  static async insertTrackingControl(jobId) {
    return Word.run(async (context) => {
      const selection = context.document.getSelection();
      const contentControl = selection.insertContentControl();
      contentControl.title = 'Compliance Check';
      contentControl.tag = `compliance:${jobId}`;
      contentControl.appearance = Word.ContentControlAppearance.tags;
      contentControl.color = '#0078D4';

      await context.sync();

      return contentControl.id;
    });
  }
}

export default DocumentManipulator;
```

## API Contract

### Request/Response Flow

```
User Action → Extract Content → Authenticate → Submit Job → Poll Status → Display Results
```

### Data Models

**Compliance Check Request:**

```typescript
interface ComplianceCheckRequest {
  article_text: string;
  guidelines: string[];
  metadata?: {
    document_title?: string;
    author?: string;
    word_count?: number;
    [key: string]: any;
  };
}
```

**Job Status Response:**

```typescript
interface JobStatusResponse {
  job_id: string;
  state: 'queued' | 'processing' | 'completed' | 'failed';
  progress?: number;
  result_url?: string;
  error?: {
    code: string;
    message: string;
  };
  created_at: string;
  updated_at: string;
  completed_at?: string;
}
```

**Compliance Result Response:**

```typescript
interface ComplianceResultResponse {
  job_id: string;
  overall_compliance_score: number;
  is_compliant: boolean;
  guideline_results: GuidelineResult[];
  recommendations: string[];
  metadata: {
    processing_time_ms: number;
    model_version: string;
    total_guidelines_checked: number;
  };
  created_at: string;
  completed_at: string;
}

interface GuidelineResult {
  guideline_id: string;
  guideline_name: string;
  compliant: boolean;
  confidence: number;
  explanation: string;
  violations: Violation[];
}

interface Violation {
  type: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  location: string;
  snippet: string;
  suggestion: string;
}
```

## Authentication Flow

### Azure AD Authentication for Office Add-ins

**authManager.js:**

```javascript
import * as msal from '@azure/msal-browser';

/**
 * Authentication manager for Azure AD
 */
class AuthManager {
  constructor(config) {
    this.msalConfig = {
      auth: {
        clientId: config.clientId,
        authority: `https://login.microsoftonline.com/${config.tenantId}`,
        redirectUri: config.redirectUri
      },
      cache: {
        cacheLocation: 'localStorage',
        storeAuthStateInCookie: true
      }
    };

    this.msalInstance = new msal.PublicClientApplication(this.msalConfig);
    this.loginRequest = {
      scopes: [
        `api://${config.apiAppId}/compliance.read`,
        `api://${config.apiAppId}/compliance.write`
      ]
    };
  }

  /**
   * Initialize MSAL and handle redirect response
   */
  async initialize() {
    await this.msalInstance.initialize();
    await this.msalInstance.handleRedirectPromise();
  }

  /**
   * Sign in user with popup
   * @returns {Promise<string>} Access token
   */
  async signInPopup() {
    try {
      const response = await this.msalInstance.loginPopup(this.loginRequest);
      return response.accessToken;
    } catch (error) {
      console.error('Sign in failed:', error);
      throw error;
    }
  }

  /**
   * Sign in user with redirect
   */
  async signInRedirect() {
    try {
      await this.msalInstance.loginRedirect(this.loginRequest);
    } catch (error) {
      console.error('Sign in redirect failed:', error);
      throw error;
    }
  }

  /**
   * Get access token silently
   * @returns {Promise<string>} Access token
   */
  async getAccessToken() {
    const accounts = this.msalInstance.getAllAccounts();

    if (accounts.length === 0) {
      throw new Error('No accounts found. Please sign in.');
    }

    const silentRequest = {
      ...this.loginRequest,
      account: accounts[0]
    };

    try {
      const response = await this.msalInstance.acquireTokenSilent(silentRequest);
      return response.accessToken;
    } catch (error) {
      if (error instanceof msal.InteractionRequiredAuthError) {
        // Fall back to interactive method
        return this.signInPopup();
      }
      throw error;
    }
  }

  /**
   * Sign out user
   */
  async signOut() {
    const accounts = this.msalInstance.getAllAccounts();
    if (accounts.length > 0) {
      await this.msalInstance.logoutPopup({
        account: accounts[0]
      });
    }
  }

  /**
   * Get current user info
   * @returns {Object|null} User information
   */
  getCurrentUser() {
    const accounts = this.msalInstance.getAllAccounts();
    if (accounts.length > 0) {
      return {
        username: accounts[0].username,
        name: accounts[0].name,
        id: accounts[0].localAccountId
      };
    }
    return null;
  }

  /**
   * Check if user is authenticated
   * @returns {boolean}
   */
  isAuthenticated() {
    return this.msalInstance.getAllAccounts().length > 0;
  }
}

export default AuthManager;
```

### Authentication Configuration

**config.js:**

```javascript
const config = {
  // Azure AD App Registration
  clientId: 'your-client-id',
  tenantId: 'your-tenant-id',
  apiAppId: 'compliance-api-app-id',

  // Redirect URIs
  redirectUri: 'https://your-addin.com/auth-callback.html',

  // API Configuration
  apiBaseUrl: 'https://apim-compliance-westeurope.azure-api.net/api/v1',
  subscriptionKey: 'your-subscription-key',

  // Polling Configuration
  pollingInterval: 2000,  // 2 seconds
  maxPollingAttempts: 150  // 5 minutes max (150 * 2s)
};

export default config;
```

## Data Flow and Security

### End-to-End Data Flow

```
1. User clicks "Check Compliance" button
   ↓
2. Add-in extracts document text using Office.js
   ↓
3. Add-in authenticates with Azure AD
   ↓
4. Add-in sends request to API Management
   - Headers: Authorization (Bearer token), Subscription Key
   - Body: article_text, guidelines, metadata
   - Transport: HTTPS (TLS 1.2+)
   ↓
5. API Management validates token and subscription
   ↓
6. Backend API processes request
   - Stores job in PostgreSQL
   - Uploads article to Blob Storage (encrypted)
   - Returns job ID
   ↓
7. Add-in polls for status every 2 seconds
   ↓
8. When complete, Add-in retrieves and displays results
   ↓
9. User views results in task pane
```

### Security Considerations

#### Data Encryption

1. **In Transit:**
   - All API communication uses HTTPS (TLS 1.2+)
   - Certificate pinning recommended for production

2. **At Rest:**
   - Blob Storage encrypted with Microsoft-managed keys
   - PostgreSQL encrypted at rest
   - Tokens stored in browser localStorage (encrypted by OS)

#### Token Management

```javascript
class SecureTokenManager {
  /**
   * Store token securely
   * @param {string} token - Access token
   */
  static storeToken(token) {
    // Token is stored in localStorage by MSAL
    // Additional encryption layer (optional)
    const encrypted = this.encrypt(token);
    sessionStorage.setItem('enc_token', encrypted);
  }

  /**
   * Retrieve token securely
   * @returns {string|null} Access token
   */
  static getToken() {
    const encrypted = sessionStorage.getItem('enc_token');
    if (!encrypted) return null;
    return this.decrypt(encrypted);
  }

  /**
   * Clear token
   */
  static clearToken() {
    sessionStorage.removeItem('enc_token');
    localStorage.clear();  // Clear MSAL cache
  }

  /**
   * Simple encryption (use proper crypto library in production)
   */
  static encrypt(text) {
    // Use Web Crypto API or similar
    return btoa(text);  // Base64 encoding (NOT secure, use proper encryption)
  }

  static decrypt(encrypted) {
    return atob(encrypted);
  }
}
```

#### Content Sanitization

```javascript
/**
 * Sanitize extracted content before sending to API
 */
class ContentSanitizer {
  /**
   * Remove sensitive information from content
   * @param {string} content - Document content
   * @returns {string} Sanitized content
   */
  static sanitize(content) {
    // Remove email addresses
    content = content.replace(/[\w.-]+@[\w.-]+\.\w+/g, '[EMAIL REDACTED]');

    // Remove phone numbers (US format)
    content = content.replace(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/g, '[PHONE REDACTED]');

    // Remove credit card numbers
    content = content.replace(/\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b/g, '[CC REDACTED]');

    // Remove SSN (US format)
    content = content.replace(/\b\d{3}-\d{2}-\d{4}\b/g, '[SSN REDACTED]');

    return content;
  }

  /**
   * Check if content contains sensitive data
   * @param {string} content - Document content
   * @returns {boolean}
   */
  static containsSensitiveData(content) {
    const patterns = [
      /[\w.-]+@[\w.-]+\.\w+/,  // Email
      /\b\d{3}[-.]?\d{3}[-.]?\d{4}\b/,  // Phone
      /\b\d{4}[- ]?\d{4}[- ]?\d{4}[- ]?\d{4}\b/,  // Credit card
      /\b\d{3}-\d{2}-\d{4}\b/  // SSN
    ];

    return patterns.some(pattern => pattern.test(content));
  }
}
```

## Implementation Guide

### Complete Add-in Implementation

**taskpane.html:**

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <meta http-equiv="X-UA-Compatible" content="IE=Edge" />
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Compliance Assistant</title>

  <!-- Office.js -->
  <script src="https://appsforoffice.microsoft.com/lib/1/hosted/office.js"></script>

  <!-- Fluent UI -->
  <link rel="stylesheet" href="https://static2.sharepointonline.com/files/fabric/office-ui-fabric-core/11.0.0/css/fabric.min.css" />

  <!-- Custom CSS -->
  <link rel="stylesheet" href="taskpane.css" />
</head>
<body class="ms-Fabric">
  <div class="container">
    <!-- Header -->
    <header class="header">
      <h1 class="ms-font-xl">Compliance Assistant</h1>
      <div id="userInfo" class="user-info"></div>
    </header>

    <!-- Main Content -->
    <main class="main-content">
      <!-- Authentication Section -->
      <section id="authSection" class="section" style="display: none;">
        <p>Please sign in to check compliance</p>
        <button id="signInBtn" class="ms-Button ms-Button--primary">
          <span class="ms-Button-label">Sign In</span>
        </button>
      </section>

      <!-- Guideline Selection -->
      <section id="guidelineSection" class="section" style="display: none;">
        <h2 class="ms-font-l">Select Guidelines</h2>
        <div id="guidelineList" class="guideline-list"></div>

        <div class="action-buttons">
          <button id="checkFullDocBtn" class="ms-Button ms-Button--primary">
            <span class="ms-Button-label">Check Full Document</span>
          </button>
          <button id="checkSelectionBtn" class="ms-Button">
            <span class="ms-Button-label">Check Selection</span>
          </button>
        </div>
      </section>

      <!-- Progress Section -->
      <section id="progressSection" class="section" style="display: none;">
        <h2 class="ms-font-l">Checking Compliance...</h2>
        <div class="ms-Spinner ms-Spinner--large"></div>
        <p id="progressText" class="progress-text">Submitting job...</p>
        <div class="ms-ProgressIndicator">
          <div class="ms-ProgressIndicator-itemProgress">
            <div id="progressBar" class="ms-ProgressIndicator-progressBar" style="width: 0%"></div>
          </div>
        </div>
      </section>

      <!-- Results Section -->
      <section id="resultsSection" class="section" style="display: none;">
        <h2 class="ms-font-l">Compliance Results</h2>

        <!-- Overall Score -->
        <div id="overallScore" class="overall-score"></div>

        <!-- Guidelines Results -->
        <div id="guidelineResults" class="guideline-results"></div>

        <!-- Violations -->
        <div id="violations" class="violations"></div>

        <!-- Recommendations -->
        <div id="recommendations" class="recommendations"></div>

        <!-- Actions -->
        <div class="action-buttons">
          <button id="highlightBtn" class="ms-Button">
            <span class="ms-Button-label">Highlight Issues</span>
          </button>
          <button id="exportBtn" class="ms-Button">
            <span class="ms-Button-label">Export Report</span>
          </button>
          <button id="newCheckBtn" class="ms-Button ms-Button--primary">
            <span class="ms-Button-label">New Check</span>
          </button>
        </div>
      </section>

      <!-- Error Section -->
      <section id="errorSection" class="section" style="display: none;">
        <div class="ms-MessageBar ms-MessageBar--error">
          <div class="ms-MessageBar-content">
            <div class="ms-MessageBar-icon">
              <i class="ms-Icon ms-Icon--ErrorBadge"></i>
            </div>
            <div class="ms-MessageBar-text">
              <span id="errorMessage"></span>
            </div>
          </div>
        </div>
        <button id="retryBtn" class="ms-Button ms-Button--primary">
          <span class="ms-Button-label">Retry</span>
        </button>
      </section>
    </main>
  </div>

  <!-- Scripts -->
  <script src="https://unpkg.com/@azure/msal-browser@2.32.0/lib/msal-browser.min.js"></script>
  <script type="module" src="taskpane.js"></script>
</body>
</html>
```

**taskpane.js:**

```javascript
import config from './config.js';
import AuthManager from './authManager.js';
import ContentExtractor from './contentExtractor.js';
import APIClient from './apiClient.js';
import DocumentManipulator from './documentManipulator.js';

let authManager;
let apiClient;
let currentJob = null;

/**
 * Initialize Office Add-in
 */
Office.onReady((info) => {
  if (info.host === Office.HostType.Word) {
    initializeAddin();
  }
});

/**
 * Initialize the add-in
 */
async function initializeAddin() {
  // Initialize auth manager
  authManager = new AuthManager({
    clientId: config.clientId,
    tenantId: config.tenantId,
    apiAppId: config.apiAppId,
    redirectUri: config.redirectUri
  });

  await authManager.initialize();

  // Initialize API client
  apiClient = new APIClient({
    baseUrl: config.apiBaseUrl,
    subscriptionKey: config.subscriptionKey,
    authManager: authManager
  });

  // Check authentication status
  if (authManager.isAuthenticated()) {
    showGuidelineSelection();
    updateUserInfo();
  } else {
    showAuthSection();
  }

  // Event listeners
  document.getElementById('signInBtn').addEventListener('click', handleSignIn);
  document.getElementById('checkFullDocBtn').addEventListener('click', () => handleCheckCompliance(false));
  document.getElementById('checkSelectionBtn').addEventListener('click', () => handleCheckCompliance(true));
  document.getElementById('highlightBtn').addEventListener('click', handleHighlight);
  document.getElementById('exportBtn').addEventListener('click', handleExport);
  document.getElementById('newCheckBtn').addEventListener('click', handleNewCheck);
  document.getElementById('retryBtn').addEventListener('click', handleRetry);
}

/**
 * Handle sign in
 */
async function handleSignIn() {
  try {
    await authManager.signInPopup();
    showGuidelineSelection();
    updateUserInfo();
    await loadGuidelines();
  } catch (error) {
    showError(`Sign in failed: ${error.message}`);
  }
}

/**
 * Update user info display
 */
function updateUserInfo() {
  const user = authManager.getCurrentUser();
  if (user) {
    document.getElementById('userInfo').textContent = `Signed in as: ${user.name}`;
  }
}

/**
 * Load available guidelines
 */
async function loadGuidelines() {
  try {
    const guidelines = await apiClient.getGuidelines();
    displayGuidelines(guidelines);
  } catch (error) {
    showError(`Failed to load guidelines: ${error.message}`);
  }
}

/**
 * Display guidelines as checkboxes
 */
function displayGuidelines(guidelines) {
  const container = document.getElementById('guidelineList');
  container.innerHTML = '';

  guidelines.forEach(guideline => {
    const checkbox = document.createElement('div');
    checkbox.className = 'ms-CheckBox';
    checkbox.innerHTML = `
      <input type="checkbox" class="ms-CheckBox-input" id="guideline-${guideline.id}" value="${guideline.id}" checked>
      <label class="ms-CheckBox-label" for="guideline-${guideline.id}">
        <span class="ms-Label">${guideline.name}</span>
        <p class="guideline-description">${guideline.description}</p>
      </label>
    `;
    container.appendChild(checkbox);
  });
}

/**
 * Handle compliance check
 */
async function handleCheckCompliance(selectionOnly) {
  try {
    showProgress();

    // Extract content
    updateProgress('Extracting content...', 10);
    const content = selectionOnly
      ? await ContentExtractor.extractSelection()
      : await ContentExtractor.extractFullDocument();

    if (!content || content.trim().length === 0) {
      throw new Error('No content to check');
    }

    // Get selected guidelines
    const selectedGuidelines = getSelectedGuidelines();
    if (selectedGuidelines.length === 0) {
      throw new Error('Please select at least one guideline');
    }

    // Get document metadata
    const metadata = await ContentExtractor.getDocumentMetadata();

    // Submit job
    updateProgress('Submitting compliance check...', 20);
    const job = await apiClient.submitComplianceCheck({
      article_text: content,
      guidelines: selectedGuidelines,
      metadata: {
        ...metadata,
        word_count: await ContentExtractor.getWordCount(),
        selection_only: selectionOnly
      }
    });

    currentJob = job;

    // Start polling
    pollJobStatus(job.job_id);

  } catch (error) {
    showError(`Compliance check failed: ${error.message}`);
  }
}

/**
 * Get selected guidelines
 */
function getSelectedGuidelines() {
  const checkboxes = document.querySelectorAll('#guidelineList input:checked');
  return Array.from(checkboxes).map(cb => cb.value);
}

/**
 * Poll job status
 */
async function pollJobStatus(jobId) {
  let attempts = 0;
  const maxAttempts = config.maxPollingAttempts;

  const poll = async () => {
    try {
      attempts++;

      const status = await apiClient.getJobStatus(jobId);

      // Update progress
      const progress = 20 + (status.progress || 0) * 0.7;  // 20-90%
      updateProgress(`Processing... (${status.state})`, progress);

      if (status.state === 'completed') {
        updateProgress('Retrieving results...', 95);
        const result = await apiClient.getJobResult(jobId);
        showResults(result);
      } else if (status.state === 'failed') {
        throw new Error(status.error?.message || 'Job failed');
      } else if (attempts >= maxAttempts) {
        throw new Error('Timeout: Job took too long to complete');
      } else {
        // Continue polling
        setTimeout(poll, config.pollingInterval);
      }

    } catch (error) {
      showError(`Status check failed: ${error.message}`);
    }
  };

  poll();
}

/**
 * Show results
 */
function showResults(result) {
  hideAllSections();
  document.getElementById('resultsSection').style.display = 'block';

  // Overall score
  const scoreDiv = document.getElementById('overallScore');
  const scorePercent = (result.overall_compliance_score * 100).toFixed(1);
  const scoreClass = result.is_compliant ? 'compliant' : 'non-compliant';
  scoreDiv.innerHTML = `
    <div class="score-circle ${scoreClass}">
      <span class="score-value">${scorePercent}%</span>
      <span class="score-label">${result.is_compliant ? 'COMPLIANT' : 'NON-COMPLIANT'}</span>
    </div>
  `;

  // Guideline results
  const guidelineResultsDiv = document.getElementById('guidelineResults');
  guidelineResultsDiv.innerHTML = '<h3>Guideline Results</h3>';
  result.guideline_results.forEach(gr => {
    const resultCard = document.createElement('div');
    resultCard.className = `guideline-result-card ${gr.compliant ? 'pass' : 'fail'}`;
    resultCard.innerHTML = `
      <div class="result-header">
        <span class="result-status">${gr.compliant ? '✓' : '✗'}</span>
        <span class="result-name">${gr.guideline_name}</span>
      </div>
      <div class="result-details">
        <p>Confidence: ${(gr.confidence * 100).toFixed(0)}%</p>
        <p>${gr.explanation}</p>
        ${gr.violations.length > 0 ? `<p class="violation-count">${gr.violations.length} violation(s) found</p>` : ''}
      </div>
    `;
    guidelineResultsDiv.appendChild(resultCard);
  });

  // Violations
  const allViolations = result.guideline_results.flatMap(gr =>
    gr.violations.map(v => ({ ...v, guideline: gr.guideline_name }))
  );

  if (allViolations.length > 0) {
    const violationsDiv = document.getElementById('violations');
    violationsDiv.innerHTML = '<h3>Violations</h3>';
    allViolations.forEach(v => {
      const violationCard = document.createElement('div');
      violationCard.className = `violation-card severity-${v.severity}`;
      violationCard.innerHTML = `
        <div class="violation-header">
          <span class="violation-type">${v.type}</span>
          <span class="violation-severity">${v.severity}</span>
        </div>
        <p class="violation-location">${v.location}</p>
        <p class="violation-snippet">"${v.snippet}"</p>
        <p class="violation-suggestion"><strong>Suggestion:</strong> ${v.suggestion}</p>
      `;
      violationsDiv.appendChild(violationCard);
    });
  }

  // Recommendations
  if (result.recommendations && result.recommendations.length > 0) {
    const recommendationsDiv = document.getElementById('recommendations');
    recommendationsDiv.innerHTML = '<h3>Recommendations</h3><ul>';
    result.recommendations.forEach(rec => {
      recommendationsDiv.innerHTML += `<li>${rec}</li>`;
    });
    recommendationsDiv.innerHTML += '</ul>';
  }

  // Store result for later use
  window.currentResult = result;
}

/**
 * Handle highlight violations
 */
async function handleHighlight() {
  if (!window.currentResult) return;

  try {
    const allViolations = window.currentResult.guideline_results.flatMap(gr => gr.violations);
    await ContentExtractor.highlightViolations(allViolations);
    showNotification('Violations highlighted in document');
  } catch (error) {
    showError(`Failed to highlight: ${error.message}`);
  }
}

/**
 * Handle export report
 */
async function handleExport() {
  if (!window.currentResult) return;

  try {
    await DocumentManipulator.createComplianceReport(window.currentResult);
    showNotification('Report exported to new document');
  } catch (error) {
    showError(`Failed to export: ${error.message}`);
  }
}

/**
 * Handle new check
 */
function handleNewCheck() {
  currentJob = null;
  window.currentResult = null;
  showGuidelineSelection();
}

/**
 * Handle retry
 */
function handleRetry() {
  if (currentJob) {
    pollJobStatus(currentJob.job_id);
  } else {
    showGuidelineSelection();
  }
}

/**
 * UI Helper Functions
 */
function hideAllSections() {
  const sections = ['authSection', 'guidelineSection', 'progressSection', 'resultsSection', 'errorSection'];
  sections.forEach(id => {
    document.getElementById(id).style.display = 'none';
  });
}

function showAuthSection() {
  hideAllSections();
  document.getElementById('authSection').style.display = 'block';
}

function showGuidelineSelection() {
  hideAllSections();
  document.getElementById('guidelineSection').style.display = 'block';
  loadGuidelines();
}

function showProgress() {
  hideAllSections();
  document.getElementById('progressSection').style.display = 'block';
}

function updateProgress(text, percent) {
  document.getElementById('progressText').textContent = text;
  document.getElementById('progressBar').style.width = `${percent}%`;
}

function showError(message) {
  hideAllSections();
  document.getElementById('errorSection').style.display = 'block';
  document.getElementById('errorMessage').textContent = message;
}

function showNotification(message) {
  // Could use Office.context.ui.displayDialogAsync or toast notification
  console.log(message);
}
```

**apiClient.js:**

```javascript
/**
 * API client for Compliance Assistant
 */
class APIClient {
  constructor({ baseUrl, subscriptionKey, authManager }) {
    this.baseUrl = baseUrl;
    this.subscriptionKey = subscriptionKey;
    this.authManager = authManager;
  }

  /**
   * Get request headers
   */
  async getHeaders() {
    const token = await this.authManager.getAccessToken();
    return {
      'Authorization': `Bearer ${token}`,
      'Ocp-Apim-Subscription-Key': this.subscriptionKey,
      'Content-Type': 'application/json'
    };
  }

  /**
   * Submit compliance check
   */
  async submitComplianceCheck({ article_text, guidelines, metadata }) {
    const headers = await this.getHeaders();
    const response = await fetch(`${this.baseUrl}/compliance/check`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ article_text, guidelines, metadata })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error?.message || 'Failed to submit job');
    }

    return response.json();
  }

  /**
   * Get job status
   */
  async getJobStatus(jobId) {
    const headers = await this.getHeaders();
    const response = await fetch(`${this.baseUrl}/jobs/${jobId}/status`, {
      method: 'GET',
      headers
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error?.message || 'Failed to get status');
    }

    return response.json();
  }

  /**
   * Get job result
   */
  async getJobResult(jobId) {
    const headers = await this.getHeaders();
    const response = await fetch(`${this.baseUrl}/jobs/${jobId}/result`, {
      method: 'GET',
      headers
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error?.message || 'Failed to get result');
    }

    return response.json();
  }

  /**
   * Get guidelines
   */
  async getGuidelines() {
    const headers = await this.getHeaders();
    const response = await fetch(`${this.baseUrl}/guidelines`, {
      method: 'GET',
      headers
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error?.message || 'Failed to get guidelines');
    }

    const data = await response.json();
    return data.guidelines;
  }
}

export default APIClient;
```

## Polling Strategy

### Optimized Polling Implementation

```javascript
class JobPoller {
  constructor(apiClient, config) {
    this.apiClient = apiClient;
    this.pollingInterval = config.pollingInterval || 2000;  // 2 seconds
    this.maxAttempts = config.maxAttempts || 150;  // 5 minutes
    this.backoffMultiplier = config.backoffMultiplier || 1.5;
    this.maxInterval = config.maxInterval || 10000;  // 10 seconds
  }

  /**
   * Poll job status with exponential backoff
   */
  async poll(jobId, onProgress, onComplete, onError) {
    let attempts = 0;
    let currentInterval = this.pollingInterval;

    const pollOnce = async () => {
      try {
        attempts++;

        const status = await this.apiClient.getJobStatus(jobId);

        // Callback with progress
        if (onProgress) {
          onProgress(status, attempts);
        }

        if (status.state === 'completed') {
          // Job completed successfully
          const result = await this.apiClient.getJobResult(jobId);
          if (onComplete) {
            onComplete(result);
          }
        } else if (status.state === 'failed') {
          // Job failed
          const error = new Error(status.error?.message || 'Job failed');
          if (onError) {
            onError(error);
          }
        } else if (attempts >= this.maxAttempts) {
          // Timeout
          const error = new Error('Polling timeout: job took too long');
          if (onError) {
            onError(error);
          }
        } else {
          // Continue polling with backoff
          currentInterval = Math.min(
            currentInterval * this.backoffMultiplier,
            this.maxInterval
          );
          setTimeout(pollOnce, currentInterval);
        }

      } catch (error) {
        if (onError) {
          onError(error);
        }
      }
    };

    // Start polling
    pollOnce();
  }

  /**
   * Cancel polling (for cleanup)
   */
  cancel() {
    // Implementation depends on how you track the timeout
    // Could use a flag or clear timeout ID
  }
}

// Usage
const poller = new JobPoller(apiClient, {
  pollingInterval: 2000,
  maxAttempts: 150,
  backoffMultiplier: 1.2,
  maxInterval: 10000
});

poller.poll(
  jobId,
  // onProgress
  (status, attempt) => {
    console.log(`Attempt ${attempt}: ${status.state}`);
    updateUI(status);
  },
  // onComplete
  (result) => {
    console.log('Job completed!');
    showResults(result);
  },
  // onError
  (error) => {
    console.error('Job failed:', error);
    showError(error.message);
  }
);
```

## Error Handling

### Comprehensive Error Handling

```javascript
class ErrorHandler {
  /**
   * Handle API errors
   */
  static handleAPIError(error, context) {
    // Network errors
    if (error instanceof TypeError && error.message.includes('fetch')) {
      return {
        title: 'Network Error',
        message: 'Unable to connect to the service. Please check your internet connection.',
        recoverable: true,
        retry: true
      };
    }

    // HTTP errors
    if (error.response) {
      const status = error.response.status;

      switch (status) {
        case 400:
          return {
            title: 'Invalid Request',
            message: error.response.data?.error?.message || 'The request was invalid',
            recoverable: true,
            retry: false
          };

        case 401:
          return {
            title: 'Authentication Required',
            message: 'Please sign in to continue',
            recoverable: true,
            retry: false,
            action: 'SIGN_IN'
          };

        case 403:
          return {
            title: 'Access Denied',
            message: 'You don\'t have permission to access this resource',
            recoverable: false,
            retry: false
          };

        case 404:
          return {
            title: 'Not Found',
            message: 'The requested resource was not found',
            recoverable: false,
            retry: false
          };

        case 429:
          const retryAfter = error.response.headers['retry-after'] || 60;
          return {
            title: 'Rate Limit Exceeded',
            message: `Too many requests. Please try again in ${retryAfter} seconds`,
            recoverable: true,
            retry: true,
            retryAfter: retryAfter * 1000
          };

        case 500:
        case 502:
        case 503:
          return {
            title: 'Server Error',
            message: 'The service is temporarily unavailable. Please try again later',
            recoverable: true,
            retry: true
          };

        default:
          return {
            title: 'Unexpected Error',
            message: error.response.data?.error?.message || 'An unexpected error occurred',
            recoverable: true,
            retry: true
          };
      }
    }

    // Office.js errors
    if (error.name === 'OfficeError') {
      return {
        title: 'Word Error',
        message: `Failed to access document: ${error.message}`,
        recoverable: true,
        retry: true
      };
    }

    // Generic errors
    return {
      title: 'Error',
      message: error.message || 'An unknown error occurred',
      recoverable: true,
      retry: true
    };
  }

  /**
   * Display error to user
   */
  static displayError(errorInfo) {
    // Update UI with error information
    const errorSection = document.getElementById('errorSection');
    const errorMessage = document.getElementById('errorMessage');

    errorMessage.innerHTML = `
      <strong>${errorInfo.title}</strong><br>
      ${errorInfo.message}
    `;

    // Show/hide retry button
    const retryBtn = document.getElementById('retryBtn');
    retryBtn.style.display = errorInfo.retry ? 'block' : 'none';

    // Show error section
    errorSection.style.display = 'block';
  }
}
```

## UI/UX Recommendations

### Design Guidelines

1. **Fluent UI Components:** Use Microsoft's Fluent UI for consistent look and feel
2. **Progressive Disclosure:** Show information gradually to avoid overwhelming users
3. **Inline Help:** Provide contextual help and tooltips
4. **Accessibility:** Follow WCAG 2.1 AA standards

### Key UX Patterns

#### Loading States

```html
<!-- Skeleton loading for guidelines -->
<div class="skeleton-loader">
  <div class="skeleton-item"></div>
  <div class="skeleton-item"></div>
  <div class="skeleton-item"></div>
</div>
```

#### Empty States

```html
<div class="empty-state">
  <img src="assets/empty-state.svg" alt="No results">
  <h3>No compliance checks yet</h3>
  <p>Select guidelines and check your document to get started</p>
</div>
```

#### Success States

```html
<div class="success-state">
  <div class="success-icon">✓</div>
  <h2>Document is Compliant!</h2>
  <p>Your content meets all selected guidelines</p>
</div>
```

### Responsive Layout

```css
/* taskpane.css */
.container {
  display: flex;
  flex-direction: column;
  height: 100vh;
  padding: 16px;
}

.header {
  border-bottom: 1px solid #edebe9;
  padding-bottom: 12px;
  margin-bottom: 16px;
}

.main-content {
  flex: 1;
  overflow-y: auto;
}

.score-circle {
  width: 120px;
  height: 120px;
  border-radius: 50%;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  margin: 20px auto;
}

.score-circle.compliant {
  background: #107c10;
  color: white;
}

.score-circle.non-compliant {
  background: #d13438;
  color: white;
}

.guideline-result-card {
  border: 1px solid #edebe9;
  border-radius: 4px;
  padding: 12px;
  margin-bottom: 8px;
}

.guideline-result-card.pass {
  border-left: 4px solid #107c10;
}

.guideline-result-card.fail {
  border-left: 4px solid #d13438;
}

.violation-card {
  background: #fff4ce;
  border-left: 4px solid #ffb900;
  padding: 12px;
  margin-bottom: 8px;
  border-radius: 4px;
}

.violation-card.severity-critical {
  border-left-color: #d13438;
  background: #fde7e9;
}

.violation-card.severity-high {
  border-left-color: #ff8c00;
  background: #fff4e5;
}
```

---

## Additional Resources

- [Office Add-ins Documentation](https://docs.microsoft.com/en-us/office/dev/add-ins/)
- [Office.js API Reference](https://docs.microsoft.com/en-us/javascript/api/office)
- [MSAL.js Documentation](https://github.com/AzureAD/microsoft-authentication-library-for-js)
- [Fluent UI Components](https://developer.microsoft.com/en-us/fluentui)

## Support

For integration support:
- Email: addin-support@company.com
- Developer Portal: https://developer.company.com/word-addin
- Sample Code: https://github.com/company/compliance-addin-sample
