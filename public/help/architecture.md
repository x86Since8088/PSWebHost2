# PSWebHost Architecture

This document describes the architecture of PSWebHost.

## System Overview

PSWebHost is a PowerShell-based web server designed for system administration and monitoring tasks.

```mermaid
graph TB
    subgraph Client
        Browser[Web Browser]
    end

    subgraph PSWebHost
        HTTP[HTTP Listener]
        Router[Route Handler]
        Auth[Authentication]
        API[API Endpoints]
        Static[Static Files]
    end

    subgraph Backend
        PS[PowerShell Scripts]
        DB[(SQLite DB)]
        FS[File System]
    end

    Browser --> HTTP
    HTTP --> Router
    Router --> Auth
    Auth --> API
    Auth --> Static
    API --> PS
    PS --> DB
    PS --> FS
```

## Request Flow

When a request comes in, it follows this sequence:

```mermaid
sequenceDiagram
    participant B as Browser
    participant H as HTTP Listener
    participant R as Router
    participant A as Auth
    participant E as Endpoint

    B->>H: HTTP Request
    H->>R: Parse URL
    R->>A: Check Session
    A-->>R: Session Data
    R->>E: Execute Script
    E-->>R: Response Data
    R-->>H: Format Response
    H-->>B: HTTP Response
```

## Component Types

| Component | Description | Location |
|-----------|-------------|----------|
| Routes | API endpoints | `routes/` |
| Elements | UI components | `public/elements/` |
| Modules | PowerShell modules | `modules/` |
| Static | CSS, JS, images | `public/` |

## Module Dependencies

```mermaid
graph LR
    Support[PSWebHost_Support]
    Metrics[PSWebHost_Metrics]
    Auth[PSWebHost_Auth]

    Support --> Auth
    Metrics --> Support
```

## State Diagram

The server can be in the following states:

```mermaid
stateDiagram-v2
    [*] --> Initializing
    Initializing --> Running: Start Complete
    Running --> Processing: Request Received
    Processing --> Running: Response Sent
    Running --> Stopping: Shutdown Signal
    Stopping --> [*]
```

## Key Features

- **Hot Reload**: API endpoints and UI components can be modified without restart
- **Role-Based Access**: Security configured per-endpoint
- **Background Jobs**: Timer-based metrics collection
- **Session Management**: Cookie-based with SQLite persistence

## Getting Started

1. Clone the repository
2. Run `system/init.ps1`
3. Access `http://localhost:8080`

For more information, see the individual component help files.
