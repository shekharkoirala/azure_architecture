graph TD
    Start([User Opens Word Document]) --> Auth{Authenticated?}
    
    Auth -->|No| Login[Login via Azure AD OAuth 2.0]
    Login --> GetToken[Obtain Access Token]
    GetToken --> Auth
    
    Auth -->|Yes| OpenAddin[Open Word Add-in]
    OpenAddin --> SelectContent[Select/Write Marketing Content]
    SelectContent --> ChooseGuidelines[Choose Compliance Guidelines]
    
    ChooseGuidelines --> Submit[Click 'Check Compliance']
    Submit --> APISubmit[POST /api/v1/compliance/check]
    
    APISubmit --> ValidateReq{Valid Request?}
    ValidateReq -->|No| ShowError400[Show Validation Error]
    ShowError400 --> SelectContent
    
    ValidateReq -->|Yes| RateCheck{Within Rate Limit?}
    RateCheck -->|No| ShowError429[Show Rate Limit Error]
    ShowError429 --> Wait[Wait for Retry-After Period]
    Wait --> Submit
    
    RateCheck -->|Yes| JobCreated[202 Accepted<br/>Job ID Returned]
    JobCreated --> ShowProgress[Display Progress Indicator]
    
    ShowProgress --> PollStatus[GET /api/v1/jobs/ID/status]
    PollStatus --> CheckState{Job State?}
    
    CheckState -->|queued| Wait2[Wait 2 seconds]
    Wait2 --> PollStatus
    
    CheckState -->|processing| UpdateProgress[Update Progress Bar]
    UpdateProgress --> Wait3[Wait 2 seconds]
    Wait3 --> PollStatus
    
    CheckState -->|failed| ShowErrorFailed[Display Error Message]
    ShowErrorFailed --> Retry{Retry?}
    Retry -->|Yes| Submit
    Retry -->|No| End([End])
    
    CheckState -->|completed| FetchResults[GET /api/v1/jobs/ID/result]
    FetchResults --> ParseResults[Parse Compliance Results]
    
    ParseResults --> DisplayScore[Display Overall Compliance Score]
    DisplayScore --> ShowGuidelines[Show Individual Guideline Results]
    ShowGuidelines --> HighlightViolations[Highlight Violations in Document]
    
    HighlightViolations --> ShowSuggestions[Display Suggestions Panel]
    ShowSuggestions --> UserAction{User Action?}
    
    UserAction -->|Apply Suggestion| UpdateDocument[Update Document Content]
    UpdateDocument --> UserAction
    
    UserAction -->|View GTC| DownloadGTC[Download Referenced GTC PDF]
    DownloadGTC --> ShowGTC[Display GTC Document]
    ShowGTC --> UserAction
    
    UserAction -->|Recheck| Submit
    UserAction -->|Export Report| ExportPDF[Export Compliance Report]
    ExportPDF --> SaveLocal[Save to Local Storage]
    SaveLocal --> End
    
    UserAction -->|Close| End
    
    style Start fill:#e1f5ff
    style End fill:#e1f5ff
    style JobCreated fill:#c8e6c9
    style ShowError400 fill:#ffcdd2
    style ShowError429 fill:#ffcdd2
    style ShowErrorFailed fill:#ffcdd2
    style FetchResults fill:#fff9c4
    style DisplayScore fill:#c8e6c9