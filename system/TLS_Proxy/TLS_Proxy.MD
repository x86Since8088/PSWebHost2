# TLS Proxy - Enterprise Gateway

A production-grade TLS terminating proxy with service mesh capabilities, multi-protocol support, and enterprise features implemented in PowerShell.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Components](#components)
- [Protocols](#protocols)
- [Service Mesh](#service-mesh)
- [Message Queue Integration](#message-queue-integration)
- [Operations](#operations)
- [Metrics & Monitoring](#metrics--monitoring)
- [Security](#security)
- [Performance Tuning](#performance-tuning)
- [Troubleshooting](#troubleshooting)
- [Future Enhancements](#future-enhancements)

---

## Overview

TLS Proxy is a Layer 4/7 proxy designed for enterprise environments requiring:

- **TLS Termination** with SNI-based routing and certificate management
- **Multi-Protocol Support** including HTTP/HTTPS, gRPC, Redis, MySQL, and generic TCP
- **Service Mesh Capabilities** with service discovery, traffic management, and resilience patterns
- **Enterprise Observability** through distributed tracing, structured logging, and Prometheus metrics
- **Event-Driven Architecture** via Kafka, RabbitMQ, and Redis Pub/Sub integration

### Key Differentiators

| Feature | Description |
|---------|-------------|
| **Pure PowerShell** | No external dependencies required for core functionality |
| **Multi-Protocol** | Single proxy handles HTTP, gRPC, Redis, MySQL, TCP |
| **Service Mesh Native** | Built-in Consul/etcd integration, not a sidecar |
| **Event Streaming** | Async message publishing with backpressure handling |
| **Hot Reload** | Configuration changes without restart |

---

## Architecture

### High-Level Architecture

```
                                    ┌─────────────────────────────────────────────────────────┐
                                    │                    TLS PROXY                            │
                                    │                                                         │
    ┌─────────┐                     │  ┌─────────────────────────────────────────────────┐   │
    │ Clients │─────HTTPS/gRPC─────────▶│              TLS Listener (:8443)               │   │
    └─────────┘                     │  │         SNI-based Certificate Selection          │   │
                                    │  └───────────────────────┬─────────────────────────┘   │
    ┌─────────┐                     │                          │                             │
    │  Redis  │────────TCP─────────────▶│   Redis Listener (:6380)                         │   │
    │ Clients │                     │  └───────────────────────┬─────────────────────────┘   │
    └─────────┘                     │                          │                             │
                                    │                          ▼                             │
    ┌─────────┐                     │  ┌─────────────────────────────────────────────────┐   │
    │  MySQL  │────────TCP─────────────▶│   MySQL Listener (:3307)                        │   │
    │ Clients │                     │  └───────────────────────┬─────────────────────────┘   │
    └─────────┘                     │                          │                             │
                                    │                          ▼                             │
                                    │  ┌─────────────────────────────────────────────────┐   │
                                    │  │              WORKER POOL (N Runspaces)           │   │
                                    │  │                                                   │   │
                                    │  │  ┌─────────┐ ┌─────────┐ ┌─────────┐            │   │
                                    │  │  │ Worker 1│ │ Worker 2│ │ Worker N│            │   │
                                    │  │  └────┬────┘ └────┬────┘ └────┬────┘            │   │
                                    │  │       │           │           │                  │   │
                                    │  │       ▼           ▼           ▼                  │   │
                                    │  │  ┌─────────────────────────────────────────┐    │   │
                                    │  │  │            Request Pipeline              │    │   │
                                    │  │  │                                          │    │   │
                                    │  │  │  Rate Limit → Auth → Circuit Breaker    │    │   │
                                    │  │  │       ↓                                  │    │   │
                                    │  │  │  Route Match → Load Balance → Relay     │    │   │
                                    │  │  └─────────────────────────────────────────┘    │   │
                                    │  └───────────────────────┬─────────────────────────┘   │
                                    │                          │                             │
                                    │                          ▼                             │
                                    │  ┌─────────────────────────────────────────────────┐   │
                                    │  │           MESSAGE BUFFER (ConcurrentQueue)       │   │
                                    │  │                                                   │   │
                                    │  │   [Event] [Event] [Event] [Event] [Event] ...   │   │
                                    │  └───────────────────────┬─────────────────────────┘   │
                                    │                          │                             │
                                    │                          ▼                             │
                                    │  ┌─────────────────────────────────────────────────┐   │
                                    │  │           PUBLISHER RUNSPACE (Dedicated)         │   │
                                    │  │                                                   │   │
                                    │  │   Batch → Serialize → Publish → Retry           │   │
                                    │  └───────────────────────┬─────────────────────────┘   │
                                    │                          │                             │
                                    └──────────────────────────┼─────────────────────────────┘
                                                               │
                    ┌──────────────────────────────────────────┼──────────────────────────────┐
                    │                                          │                              │
                    ▼                                          ▼                              ▼
             ┌───────────┐                              ┌───────────┐                  ┌───────────┐
             │   Kafka   │                              │ RabbitMQ  │                  │   Redis   │
             │  Cluster  │                              │  Cluster  │                  │  Pub/Sub  │
             └───────────┘                              └───────────┘                  └───────────┘
```

### Request Flow

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│                                    REQUEST PIPELINE                                       │
└──────────────────────────────────────────────────────────────────────────────────────────┘

  Client                                                                              Backend
    │                                                                                    │
    │  1. TCP Connect                                                                    │
    ├──────────────────────▶ Accept Connection                                           │
    │                              │                                                     │
    │  2. TLS Handshake            │ Check IP Blacklist                                  │
    ├──────────────────────▶       │ Check Global Rate Limit                             │
    │                              │ SNI Certificate Selection                           │
    │                              │                                                     │
    │  3. HTTP Request             │                                                     │
    ├──────────────────────▶       │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │                        │  Router   │ Match SNI, Path, Headers                      │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │                        │ Rate Limit│ Per-route token bucket                        │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │                        │   Auth    │ JWT / OAuth2 / API Key / mTLS                 │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │                        │  Circuit  │ Check backend health                          │
    │                        │  Breaker  │                                               │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │                        │  Service  │ Consul / etcd / K8s / DNS                     │
    │                        │ Discovery │                                               │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │                        │   Load    │ Round-robin, Weighted, Locality-aware         │
    │                        │ Balancer  │                                               │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐       Inject Headers                          │
    │                        │  Traffic  │ ─────────────────────────────────────────────▶│
    │                        │  Manager  │       PROXY Protocol                          │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              │◀─────────────────────────────────────────────────── │
    │                              │       Response                                      │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │                        │  Metrics  │ Latency, Status, Bytes                        │
    │                        │  Logging  │                                               │
    │                        └─────┬─────┘                                               │
    │                              │                                                     │
    │                              ▼                                                     │
    │                        ┌───────────┐                                               │
    │◀─────────────────────  │  Message  │ Async enqueue to buffer                       │
    │      Response          │   Queue   │                                               │
    │                        └───────────┘                                               │
```

### Thread Model

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    RUNSPACE POOL                                         │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐    │
│  │  HTTPS Worker 1 │  │  HTTPS Worker 2 │  │  HTTPS Worker N │  │  Redis Worker 1 │    │
│  │                 │  │                 │  │                 │  │                 │    │
│  │  Accept → Route │  │  Accept → Route │  │  Accept → Route │  │  Parse → Route  │    │
│  │  → Relay → Log  │  │  → Relay → Log  │  │  → Relay → Log  │  │  → Relay → Log  │    │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘    │
│           │                    │                    │                    │              │
│           └──────────────────┬─┴────────────────────┴────────────────────┘              │
│                              │                                                          │
│                              ▼                                                          │
│                    ┌─────────────────────┐                                              │
│                    │   Message Buffer    │  ConcurrentQueue<hashtable>                  │
│                    │   (Lock-free)       │                                              │
│                    └──────────┬──────────┘                                              │
│                               │                                                         │
│                               ▼                                                         │
│                    ┌─────────────────────┐                                              │
│                    │  Publisher Worker   │  Dedicated runspace                          │
│                    │                     │  Batches & publishes                         │
│                    │  Kafka / RabbitMQ   │                                              │
│                    └─────────────────────┘                                              │
│                                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐    │
│  │  Metrics Server │  │  Admin Server   │  │  Health Checker │  │  File Watcher   │    │
│  │     (:9090)     │  │     (:9091)     │  │  (Background)   │  │  (Hot Reload)   │    │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘    │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Features

### Core Features

| Feature | Description | Status |
|---------|-------------|--------|
| TLS Termination | SNI-based routing, TLS 1.2/1.3 | ✅ Complete |
| HTTP/HTTPS Proxy | Full HTTP/1.1 support | ✅ Complete |
| WebSocket Proxy | Bidirectional relay | ✅ Complete |
| gRPC Proxy | HTTP/2 framing, service routing | ✅ Complete |
| Load Balancing | Round-robin, weighted, IP-hash, locality-aware | ✅ Complete |
| Health Checks | TCP, HTTP, gRPC health probes | ✅ Complete |
| Hot Reload | Configuration changes without restart | ✅ Complete |
| Graceful Shutdown | Connection draining | ✅ Complete |

### Security Features

| Feature | Description | Status |
|---------|-------------|--------|
| JWT Authentication | RS256, ES256, HS256 with claims validation | ✅ Complete |
| OAuth2 Introspection | RFC 7662 token validation | ✅ Complete |
| API Key Auth | Header-based key validation | ✅ Complete |
| mTLS | Client certificate validation | ✅ Complete |
| Rate Limiting | Token bucket per-IP and per-route | ✅ Complete |
| IP Blacklisting | Dynamic block list with expiry | ✅ Complete |
| Header Redaction | Sensitive data removal from logs | ✅ Complete |

### Observability Features

| Feature | Description | Status |
|---------|-------------|--------|
| Prometheus Metrics | Counters, gauges, histograms | ✅ Complete |
| Access Logging | JSON, CLF, combined formats | ✅ Complete |
| Audit Logging | Security events | ✅ Complete |
| Distributed Tracing | OpenTelemetry, Jaeger, Zipkin | ✅ Complete |
| Request Body Logging | Configurable with redaction | ✅ Complete |
| Log Rotation | Size-based with compression | ✅ Complete |

### Service Mesh Features

| Feature | Description | Status |
|---------|-------------|--------|
| Service Discovery | Consul, etcd, Kubernetes, DNS | ✅ Complete |
| Circuit Breaker | Failure detection, recovery | ✅ Complete |
| Retry Policy | Exponential backoff, budget | ✅ Complete |
| Traffic Shifting | Canary, blue-green | ✅ Complete |
| Traffic Mirroring | Shadow traffic | ✅ Complete |
| Fault Injection | Delay, abort injection | ✅ Complete |
| Distributed Rate Limiting | Redis-backed global limits | ✅ Complete |
| Locality-Aware Routing | Zone/region preference | ✅ Complete |

### Protocol Support

| Protocol | Features | Status |
|----------|----------|--------|
| HTTP/HTTPS | Full proxy with transformations | ✅ Complete |
| gRPC | Service/method routing, metadata | ✅ Complete |
| Redis | Command routing, read/write split | ✅ Complete |
| MySQL | Query routing, connection pooling | ✅ Complete |
| PostgreSQL | Basic proxy | 🔄 Planned |
| MQTT | Topic routing | 🔄 Planned |
| Generic TCP | Passthrough mode | ✅ Complete |

### Message Queue Integration

| System | Features | Status |
|--------|----------|--------|
| Kafka | Async publishing, batching | ✅ Complete |
| RabbitMQ | Exchange/queue routing | ✅ Complete |
| Redis Pub/Sub | Channel publishing | ✅ Complete |
| AWS SQS | Queue integration | 🔄 Planned |

---

## Installation

### Prerequisites

- PowerShell 7.0+ (Windows, Linux, macOS)
- .NET 6.0+ Runtime
- TLS Certificate (PFX format)

### Quick Start

```powershell
# Clone or download the proxy script
# Create a self-signed certificate for testing
$cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "Cert:\CurrentUser\My"
Export-PfxCertificate -Cert $cert -FilePath "cert.pfx" -Password (ConvertTo-SecureString -String "password" -Force -AsPlainText)

# Start the proxy
./TLS_Proxy.ps1 -HttpsPort 8443 -CertPath "cert.pfx" -CertPassword "password"
```

### Production Installation

```powershell
# With all features enabled
./TLS_Proxy.ps1 `
    -HttpsPort 443 `
    -GrpcPort 9443 `
    -MetricsPort 9090 `
    -AdminPort 9091 `
    -WorkerCount 50 `
    -CertPath "/etc/ssl/proxy.pfx" `
    -CertPassword $env:CERT_PASSWORD `
    -RulesPath "/etc/proxy/rules.json" `
    -LogPath "/var/log/proxy" `
    -KafkaBrokers "kafka1:9092,kafka2:9092" `
    -ConsulAddr "consul.service.consul:8500" `
    -RedisAddr "redis.service.consul:6379" `
    -OtlpEndpoint "http://jaeger:4318/v1/traces" `
    -ServiceName "api-gateway" `
    -DrainTimeoutSeconds 60
```

### Docker Installation

```dockerfile
FROM mcr.microsoft.com/powershell:latest

WORKDIR /app
COPY TLS_Proxy.ps1 .
COPY rules.json .
COPY certs/ ./certs/

EXPOSE 8443 9090 9091

ENTRYPOINT ["pwsh", "-File", "TLS_Proxy.ps1"]
CMD ["-HttpsPort", "8443", "-RulesPath", "rules.json"]
```

---

## Configuration

### Configuration File Structure

```json
{
  "default": {
    "host": "127.0.0.1",
    "port": 8080
  },
  
  "routes": [],
  "loadBalancing": {},
  "rateLimit": {},
  "circuitBreaker": {},
  "auth": {},
  "logging": {},
  "tracing": {},
  "messaging": {},
  "serviceMesh": {},
  "protocols": {},
  "dns": {},
  "metrics": {},
  "admin": {},
  "hotReload": {}
}
```

### Route Configuration

```json
{
  "routes": [
    {
      "match": "api.example.com",
      "matchPath": "/v1/*",
      "backend": {
        "host": "backend-server",
        "port": 8080
      },
      "headers": {
        "X-Custom-Header": "value"
      },
      "auth": {
        "type": "jwt",
        "required": true,
        "issuer": "https://auth.example.com",
        "audience": "api.example.com",
        "algorithms": ["RS256"],
        "claims": {
          "required": ["sub", "exp"],
          "match": { "aud": "api.example.com" }
        },
        "passHeaders": {
          "X-User-Id": "sub",
          "X-User-Email": "email"
        }
      },
      "rateLimit": {
        "requestsPerSecond": 100,
        "burstSize": 200
      },
      "circuitBreaker": {
        "enabled": true,
        "failureThreshold": 5,
        "timeout": 30
      },
      "messaging": {
        "enabled": true,
        "events": ["request", "response", "error"],
        "topic": "api-events"
      },
      "logging": {
        "enabled": true,
        "logRequestBody": true,
        "maxBodySize": 65536,
        "redactHeaders": ["Authorization"]
      }
    },
    {
      "match": "*.example.com",
      "backend": {
        "service": "web-service"
      },
      "serviceMesh": {
        "enabled": true,
        "mtls": true
      }
    },
    {
      "match": "~^grpc\\.",
      "protocol": "grpc",
      "backend": {
        "cluster": "grpc-cluster"
      },
      "grpc": {
        "enabled": true,
        "services": {
          "myapp.UserService": {
            "backend": { "host": "user-service", "port": 50051 }
          }
        }
      }
    }
  ]
}
```

### Load Balancing Configuration

```json
{
  "loadBalancing": {
    "web-cluster": {
      "backends": [
        { "host": "web-1", "port": 8080, "weight": 3, "zone": "us-east-1a" },
        { "host": "web-2", "port": 8080, "weight": 2, "zone": "us-east-1b" },
        { "host": "web-3", "port": 8080, "weight": 1, "zone": "us-east-1c" }
      ],
      "strategy": "weighted-round-robin",
      "healthCheck": {
        "type": "http",
        "path": "/health",
        "interval": 10,
        "timeout": 5,
        "unhealthyThreshold": 3,
        "healthyThreshold": 2
      }
    },
    "grpc-cluster": {
      "backends": [
        { "host": "grpc-1", "port": 50051 },
        { "host": "grpc-2", "port": 50051 }
      ],
      "strategy": "round-robin",
      "healthCheck": {
        "type": "grpc",
        "service": "grpc.health.v1.Health"
      }
    }
  }
}
```

### Service Mesh Configuration

```json
{
  "serviceMesh": {
    "enabled": true,
    
    "identity": {
      "type": "spiffe",
      "trustDomain": "example.com"
    },
    
    "discovery": {
      "type": "consul",
      "consul": {
        "address": "consul:8500",
        "datacenter": "dc1",
        "register": true,
        "serviceName": "api-gateway",
        "healthCheck": {
          "http": "http://localhost:9090/health",
          "interval": "10s"
        }
      }
    },
    
    "mtls": {
      "enabled": true,
      "caCertPath": "ca.crt",
      "certPath": "service.crt",
      "keyPath": "service.key"
    },
    
    "traffic": {
      "canary": {
        "enabled": true,
        "headerRouting": { "X-Canary": "true" },
        "defaultWeight": 10
      },
      "mirroring": {
        "enabled": false,
        "target": { "service": "shadow-service" },
        "percentage": 100
      }
    },
    
    "resilience": {
      "retry": {
        "enabled": true,
        "maxAttempts": 3,
        "retryableStatusCodes": [502, 503, 504],
        "budget": {
          "enabled": true,
          "percentCanRetry": 20
        }
      },
      "circuitBreaker": {
        "enabled": true,
        "outlierDetection": {
          "enabled": true,
          "consecutiveErrors": 5,
          "baseEjectionTime": 30
        }
      }
    },
    
    "locality": {
      "enabled": true,
      "local": {
        "region": "us-east-1",
        "zone": "us-east-1a"
      }
    },
    
    "distributedRateLimit": {
      "enabled": true,
      "redis": {
        "address": "redis:6379"
      },
      "globalLimits": {
        "order-service": {
          "requestsPerSecond": 1000
        }
      }
    }
  }
}
```

### Message Queue Configuration

```json
{
  "messaging": {
    "enabled": true,
    
    "buffer": {
      "maxSize": 100000,
      "flushInterval": 1000,
      "batchSize": 100,
      "dropPolicy": "oldest"
    },
    
    "kafka": {
      "enabled": true,
      "brokers": ["kafka1:9092", "kafka2:9092"],
      "topics": {
        "requests": "proxy-requests",
        "errors": "proxy-errors",
        "audit": "proxy-audit"
      }
    },
    
    "rabbitmq": {
      "enabled": false,
      "host": "rabbitmq",
      "exchange": "proxy-events"
    },
    
    "eventSchema": {
      "includeTimestamp": true,
      "includeRequestId": true,
      "includeLatency": true,
      "customFields": {
        "environment": "production",
        "datacenter": "us-east-1"
      }
    }
  }
}
```

---

## Components

### Rate Limiter

Token bucket algorithm with configurable refill rate:

```
┌─────────────────────────────────────────────────────────────┐
│                     TOKEN BUCKET                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   Capacity: 200 tokens (burst size)                         │
│   Refill Rate: 100 tokens/second                            │
│                                                              │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●  │   │
│   │ ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●  │   │
│   │ ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ○ ○ ○ ○ ○ ○ ○  │   │
│   │ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○ ○  │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                              │
│   ● = Available token    ○ = Used token                     │
│                                                              │
│   Request arrives:                                           │
│   1. Calculate tokens to add since last request              │
│   2. If tokens >= 1, consume and allow                       │
│   3. Else, reject with 429 and Retry-After header           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Circuit Breaker

State machine protecting backends from cascading failures:

```
                         ┌───────────────┐
                         │    CLOSED     │
                         │   (Normal)    │
                         └───────┬───────┘
                                 │
                    Failure count >= threshold
                                 │
                                 ▼
                         ┌───────────────┐
              ┌──────────│     OPEN      │──────────┐
              │          │  (Rejecting)  │          │
              │          └───────────────┘          │
              │                                     │
         Any failure                         Timeout expires
              │                                     │
              │          ┌───────────────┐          │
              └──────────│   HALF-OPEN   │◀─────────┘
                         │  (Testing)    │
                         └───────┬───────┘
                                 │
                    Success count >= threshold
                                 │
                                 ▼
                         ┌───────────────┐
                         │    CLOSED     │
                         └───────────────┘
```

### Message Buffer

Lock-free concurrent queue with backpressure:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           MESSAGE BUFFER                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PRODUCERS (Worker Runspaces)                                                │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐                            │
│  │Worker 1 │ │Worker 2 │ │Worker 3 │ │Worker N │                            │
│  └────┬────┘ └────┬────┘ └────┬────┘ └────┬────┘                            │
│       │           │           │           │                                  │
│       └───────────┴─────┬─────┴───────────┘                                  │
│                         │                                                    │
│                         ▼ Enqueue (Lock-free)                                │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  CONCURRENT QUEUE                                                      │  │
│  │  ┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐  │  │
│  │  │ Evt │ Evt │ Evt │ Evt │ Evt │ Evt │ Evt │ Evt │ Evt │ ... │     │  │  │
│  │  └─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘  │  │
│  │                                                                        │  │
│  │  Max Size: 100,000 events                                              │  │
│  │  Current:  45,230 events                                               │  │
│  │  Backpressure: OFF                                                     │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                         │                                                    │
│                         ▼ TryDequeue (Batched)                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  CONSUMER (Publisher Runspace)                                          ││
│  │                                                                          ││
│  │  1. Dequeue up to 100 events                                            ││
│  │  2. Group by event type                                                  ││
│  │  3. Serialize to JSON                                                   ││
│  │  4. Publish to Kafka/RabbitMQ                                           ││
│  │  5. On failure, re-queue with retry count                               ││
│  │  6. Sleep until next flush interval                                      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  BACKPRESSURE HANDLING:                                                      │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  When buffer size >= maxSize:                                           ││
│  │                                                                          ││
│  │  Policy: "oldest"  → Dequeue oldest, enqueue new                        ││
│  │  Policy: "newest"  → Reject new event                                    ││
│  │  Policy: "block"   → Brief wait, then reject                            ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Protocols

### Redis Protocol

Read/write splitting with command classification:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          REDIS PROTOCOL HANDLER                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  CLIENT                           PROXY                          BACKENDS   │
│    │                                │                                │       │
│    │  GET user:123                  │                                │       │
│    ├───────────────────────────────▶│                                │       │
│    │                                │ Parse RESP                     │       │
│    │                                │ Classify: READ                 │       │
│    │                                │ Route to: REPLICA              │       │
│    │                                ├───────────────────────────────▶│       │
│    │                                │                   replica-1    │       │
│    │                                │◀───────────────────────────────┤       │
│    │◀───────────────────────────────│                                │       │
│    │  $5\r\nvalue\r\n               │                                │       │
│    │                                │                                │       │
│    │  SET user:123 "data"           │                                │       │
│    ├───────────────────────────────▶│                                │       │
│    │                                │ Parse RESP                     │       │
│    │                                │ Classify: WRITE                │       │
│    │                                │ Route to: PRIMARY              │       │
│    │                                ├───────────────────────────────▶│       │
│    │                                │                   primary      │       │
│    │                                │◀───────────────────────────────┤       │
│    │◀───────────────────────────────│                                │       │
│    │  +OK\r\n                       │                                │       │
│    │                                │                                │       │
│    │  FLUSHALL                      │                                │       │
│    ├───────────────────────────────▶│                                │       │
│    │                                │ Parse RESP                     │       │
│    │                                │ Classify: ADMIN                │       │
│    │                                │ BLOCKED!                       │       │
│    │◀───────────────────────────────│                                │       │
│    │  -ERR Command not allowed      │                                │       │
│                                                                              │
│  COMMAND CLASSIFICATION:                                                     │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │ READ:  GET, MGET, HGET, LRANGE, SMEMBERS, ZRANGE, EXISTS, TTL, SCAN   │ │
│  │ WRITE: SET, MSET, HSET, LPUSH, SADD, ZADD, DEL, EXPIRE, INCR          │ │
│  │ ADMIN: FLUSHALL, FLUSHDB, DEBUG, CONFIG, SHUTDOWN, SLAVEOF            │ │
│  │ DANGEROUS: KEYS, EVAL, EVALSHA, SCRIPT                                 │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### gRPC Protocol

Service and method-level routing:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          gRPC PROTOCOL HANDLER                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  REQUEST PATH: /myapp.UserService/GetUser                                    │
│                 └──────┬───────┘ └───┬───┘                                   │
│                     Service       Method                                     │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  SERVICE ROUTING TABLE                                                   ││
│  ├─────────────────────────────────────────────────────────────────────────┤│
│  │  Service                  │ Backend           │ Config                   ││
│  ├───────────────────────────┼───────────────────┼─────────────────────────┤│
│  │  myapp.UserService        │ user-service:50051│ timeout=5s              ││
│  │  myapp.OrderService       │ cluster:orders    │ timeout=30s, auth=true  ││
│  │  myapp.PaymentService     │ payment:50051     │ mtls=true               ││
│  │  grpc.health.v1.Health    │ (local)           │ internal                ││
│  └───────────────────────────┴───────────────────┴─────────────────────────┘│
│                                                                              │
│  gRPC FRAME FORMAT:                                                          │
│  ┌─────────┬─────────────────────────┬──────────────────────────────────────┐│
│  │Compress │     Message Length      │            Message Data              ││
│  │ (1 byte)│       (4 bytes)         │           (N bytes)                  ││
│  └─────────┴─────────────────────────┴──────────────────────────────────────┘│
│                                                                              │
│  METADATA INJECTION:                                                         │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  x-request-id: {generated}                                              │ │
│  │  x-client-ip: {client_ip}                                               │ │
│  │  x-forwarded-for: {client_ip}                                           │ │
│  │  authorization: {forwarded from client}                                 │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  gRPC STATUS CODES:                                                          │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  0  OK              │  7  PERMISSION_DENIED  │  13 INTERNAL             │ │
│  │  1  CANCELLED       │  8  RESOURCE_EXHAUSTED │  14 UNAVAILABLE          │ │
│  │  2  UNKNOWN         │  9  FAILED_PRECONDITION│  15 DATA_LOSS            │ │
│  │  3  INVALID_ARGUMENT│  10 ABORTED            │  16 UNAUTHENTICATED      │ │
│  │  4  DEADLINE_EXCEED │  11 OUT_OF_RANGE       │                          │ │
│  │  5  NOT_FOUND       │  12 UNIMPLEMENTED      │                          │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### GraphQL Protocol

Query parsing with complexity analysis:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        GRAPHQL PROTOCOL HANDLER                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  QUERY ANALYSIS:                                                             │
│                                                                              │
│  query GetUserWithPosts($id: ID!) {                                          │
│    user(id: $id) {              ← Depth: 1, Cost: 1                          │
│      name                       ← Depth: 2, Cost: 1                          │
│      email                      ← Depth: 2, Cost: 1                          │
│      posts {                    ← Depth: 2, Cost: 10 (list multiplier)       │
│        title                    ← Depth: 3, Cost: 1                          │
│        comments {               ← Depth: 3, Cost: 10 (list multiplier)       │
│          author                 ← Depth: 4, Cost: 1                          │
│        }                                                                     │
│      }                                                                       │
│    }                                                                         │
│  }                                                                           │
│                                                                              │
│  Total Depth: 4                                                              │
│  Total Complexity: 1 + 1 + 1 + 10 + 1 + 10 + 1 = 25                         │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  VALIDATION RULES                                                        ││
│  ├─────────────────────────────────────────────────────────────────────────┤│
│  │  Max Depth:      10      │ Reject if depth > 10                         ││
│  │  Max Complexity: 1000    │ Reject if complexity > 1000                  ││
│  │  Max Query Size: 100KB   │ Reject oversized queries                     ││
│  │  Introspection:  true    │ Allow __schema queries                       ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  OPERATION-SPECIFIC RATE LIMITING:                                           │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  Query.users         │ 10 req/sec  │ List operations are expensive      ││
│  │  Query.user          │ 100 req/sec │ Single lookups are cheap           ││
│  │  Mutation.*          │ 5 req/sec   │ Mutations need protection          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  PERSISTED QUERIES:                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  Client sends:  { "extensions": { "persistedQuery": { "sha256Hash":     ││
│  │                    "abc123..." } } }                                     ││
│  │                                                                          ││
│  │  Proxy looks up hash → Returns cached query                              ││
│  │  Benefits: Reduced bandwidth, prevents arbitrary queries                 ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Service Mesh

### Service Discovery Integration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          SERVICE DISCOVERY                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  CONSUL INTEGRATION:                                                         │
│                                                                              │
│  ┌─────────────┐         ┌─────────────┐         ┌─────────────┐            │
│  │  TLS Proxy  │◀───────▶│   Consul    │◀───────▶│  Services   │            │
│  │             │  HTTP   │   Agent     │  Gossip │             │            │
│  └──────┬──────┘         └─────────────┘         └─────────────┘            │
│         │                                                                    │
│         │  1. Register on startup                                            │
│         │     PUT /v1/agent/service/register                                 │
│         │     { "ID": "proxy-1", "Name": "api-gateway", ... }               │
│         │                                                                    │
│         │  2. Query healthy endpoints                                        │
│         │     GET /v1/health/service/order-service?passing=true             │
│         │                                                                    │
│         │  3. Watch for changes (long-poll or blocking query)               │
│         │     GET /v1/health/service/order-service?index=123&wait=30s       │
│         │                                                                    │
│         │  4. Deregister on shutdown                                         │
│         │     PUT /v1/agent/service/deregister/proxy-1                       │
│                                                                              │
│  SERVICE CACHE:                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  Service           │ Endpoints              │ TTL     │ Last Update     ││
│  ├────────────────────┼────────────────────────┼─────────┼─────────────────┤│
│  │  order-service     │ 10.0.0.1:8080 (w=3)   │ 30s     │ 2024-01-15 10:30││
│  │                    │ 10.0.0.2:8080 (w=2)   │         │                  ││
│  │  user-service      │ 10.0.1.1:8080         │ 30s     │ 2024-01-15 10:29││
│  │  payment-service   │ 10.0.2.1:8080         │ 30s     │ 2024-01-15 10:28││
│  └────────────────────┴────────────────────────┴─────────┴─────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Management

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TRAFFIC MANAGEMENT                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  CANARY DEPLOYMENT:                                                          │
│                                                                              │
│     100% Traffic                                                             │
│         │                                                                    │
│         ▼                                                                    │
│    ┌─────────┐                                                               │
│    │ Router  │                                                               │
│    └────┬────┘                                                               │
│         │                                                                    │
│    ┌────┴────┐                                                               │
│    │         │                                                               │
│    ▼         ▼                                                               │
│   90%       10%                                                              │
│    │         │                                                               │
│    ▼         ▼                                                               │
│ ┌─────┐  ┌─────┐                                                             │
│ │ v1  │  │ v2  │  ← Canary                                                   │
│ │     │  │     │                                                             │
│ └─────┘  └─────┘                                                             │
│                                                                              │
│  HEADER-BASED ROUTING:                                                       │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  X-Canary: true  → Route to v2 (canary)                                 ││
│  │  X-Version: v2   → Route to v2                                           ││
│  │  No header       → Route based on weight percentage                      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  TRAFFIC MIRRORING (Shadow Traffic):                                         │
│                                                                              │
│     Request                                                                  │
│         │                                                                    │
│         ▼                                                                    │
│    ┌─────────┐                                                               │
│    │  Proxy  │───────────────┐                                               │
│    └────┬────┘               │                                               │
│         │                    │ Fire-and-forget                               │
│         ▼                    ▼                                               │
│    ┌─────────┐          ┌─────────┐                                          │
│    │ Primary │          │ Shadow  │                                          │
│    │ Backend │          │ Backend │                                          │
│    └────┬────┘          └─────────┘                                          │
│         │                    │                                               │
│         ▼                    ✗ Response discarded                            │
│     Response                                                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Locality-Aware Routing

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       LOCALITY-AWARE ROUTING                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PROXY LOCATION: us-east-1a                                                  │
│                                                                              │
│  ENDPOINT SELECTION PRIORITY:                                                │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  Priority │ Locality      │ Weight │ Endpoints                          ││
│  ├───────────┼───────────────┼────────┼────────────────────────────────────┤│
│  │  1 (High) │ Same Zone     │ 100    │ 10.0.0.1 (us-east-1a)              ││
│  │           │ us-east-1a    │        │ 10.0.0.2 (us-east-1a)              ││
│  ├───────────┼───────────────┼────────┼────────────────────────────────────┤│
│  │  2 (Med)  │ Same Region   │ 50     │ 10.0.1.1 (us-east-1b)              ││
│  │           │ us-east-1*    │        │ 10.0.1.2 (us-east-1c)              ││
│  ├───────────┼───────────────┼────────┼────────────────────────────────────┤│
│  │  3 (Low)  │ Any           │ 1      │ 10.0.2.1 (us-west-2a)              ││
│  │           │               │        │ 10.0.2.2 (eu-west-1a)              ││
│  └───────────┴───────────────┴────────┴────────────────────────────────────┘│
│                                                                              │
│  FAILOVER:                                                                   │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  1. Prefer same-zone endpoints (lowest latency)                         ││
│  │  2. If same-zone < 70% capacity, include same-region                    ││
│  │  3. If same-region unavailable, fall back to any zone                   ││
│  │  4. Never route to unhealthy endpoints                                  ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Message Queue Integration

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     MESSAGE QUEUE ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  REQUEST PROCESSING                          MESSAGE PUBLISHING              │
│  ─────────────────                          ──────────────────               │
│                                                                              │
│  ┌─────────────┐    ┌─────────────────────┐    ┌─────────────────────────┐  │
│  │   Worker    │───▶│   Message Buffer    │───▶│   Publisher Runspace    │  │
│  │  Runspace   │    │  (ConcurrentQueue)  │    │                         │  │
│  └─────────────┘    └─────────────────────┘    │  ┌─────────────────┐    │  │
│                                                 │  │  Kafka Producer │    │  │
│  ┌─────────────┐                               │  └────────┬────────┘    │  │
│  │   Worker    │───▶                           │           │             │  │
│  │  Runspace   │                               │  ┌────────▼────────┐    │  │
│  └─────────────┘                               │  │ RabbitMQ Prod.  │    │  │
│                                                 │  └────────┬────────┘    │  │
│  ┌─────────────┐                               │           │             │  │
│  │   Worker    │───▶                           │  ┌────────▼────────┐    │  │
│  │  Runspace   │                               │  │  Redis Pub/Sub  │    │  │
│  └─────────────┘                               │  └─────────────────┘    │  │
│                                                 └─────────────────────────┘  │
│                                                                              │
│  EVENT FLOW:                                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                          ││
│  │  1. Request completes in worker                                          ││
│  │  2. Worker creates event hashtable                                       ││
│  │  3. Worker calls Add-MessageToBuffer (lock-free enqueue)                ││
│  │  4. Publisher wakes on interval (1 second default)                       ││
│  │  5. Publisher dequeues batch (100 events max)                           ││
│  │  6. Publisher groups by event type                                       ││
│  │  7. Publisher serializes to JSON                                        ││
│  │  8. Publisher sends to Kafka/RabbitMQ/Redis                             ││
│  │  9. On failure, re-queue with retry count                               ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Event Schema

```json
{
  "event_type": "requests",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "request_id": "a1b2c3d4e5f6",
  "proxy_id": "api-gateway-prod-1",
  
  "client": {
    "ip": "192.168.1.100",
    "port": 54321,
    "user_agent": "Mozilla/5.0..."
  },
  
  "request": {
    "method": "POST",
    "path": "/api/v1/orders",
    "host": "api.example.com",
    "content_type": "application/json",
    "content_length": 256
  },
  
  "response": {
    "status_code": 201,
    "content_length": 128,
    "latency_ms": 45.23
  },
  
  "routing": {
    "route": "api.example.com",
    "backend": "10.0.0.1:8080",
    "service": "order-service",
    "version": "v1"
  },
  
  "auth": {
    "method": "jwt",
    "user_id": "user-123",
    "success": true
  },
  
  "tls": {
    "version": "TLS1.3",
    "cipher": "TLS_AES_256_GCM_SHA384",
    "sni": "api.example.com"
  },
  
  "custom": {
    "environment": "production",
    "datacenter": "us-east-1"
  }
}
```

### Downstream Consumers

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DOWNSTREAM CONSUMERS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                           KAFKA TOPICS                                       │
│                                                                              │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐       │
│  │  proxy-requests  │    │   proxy-errors   │    │   proxy-audit    │       │
│  └────────┬─────────┘    └────────┬─────────┘    └────────┬─────────┘       │
│           │                       │                       │                  │
│           ▼                       ▼                       ▼                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                                                                          ││
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     ││
│  │  │ Elasticsearch│  │   Flink     │  │   Splunk    │  │    S3       │     ││
│  │  │   (Logs)    │  │ (Analytics) │  │  (SIEM)     │  │ (Archive)   │     ││
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘     ││
│  │        │                │                │                │              ││
│  │        ▼                ▼                ▼                ▼              ││
│  │  ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌───────────┐       ││
│  │  │  Kibana   │    │ Dashboard │    │  Alerts   │    │ Athena    │       ││
│  │  │   UI      │    │           │    │           │    │ Queries   │       ││
│  │  └───────────┘    └───────────┘    └───────────┘    └───────────┘       ││
│  │                                                                          ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  USE CASES:                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  • Real-time dashboards: Request rates, latency percentiles             ││
│  │  • Anomaly detection: Unusual traffic patterns, auth failures           ││
│  │  • Compliance auditing: Who accessed what, when                         ││
│  │  • Debugging: Trace requests through the system                         ││
│  │  • Billing: Usage-based pricing, API call counting                      ││
│  │  • Capacity planning: Traffic forecasting, scaling decisions            ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Operations

### Command Line Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-HttpsPort` | 8443 | HTTPS listener port |
| `-GrpcPort` | 9443 | Dedicated gRPC port (optional) |
| `-TcpPort` | 9999 | Generic TCP proxy port |
| `-DotPort` | 853 | DNS over TLS port |
| `-MetricsPort` | 9090 | Prometheus metrics port |
| `-AdminPort` | 9091 | Admin API port |
| `-WorkerCount` | 15 | Number of worker runspaces |
| `-CertPath` | cert.pfx | TLS certificate path |
| `-CertPassword` | password | Certificate password |
| `-RulesPath` | rules.json | Configuration file path |
| `-LogPath` | logs | Log directory |
| `-BufferSize` | 65536 | Network buffer size |
| `-TimeoutMs` | 30000 | Request timeout |
| `-DrainTimeoutSeconds` | 30 | Graceful shutdown timeout |
| `-KafkaBrokers` | | Kafka broker addresses |
| `-ConsulAddr` | | Consul agent address |
| `-RedisAddr` | | Redis address for distributed state |
| `-OtlpEndpoint` | | OpenTelemetry collector endpoint |
| `-ServiceName` | tls-proxy | Service name for registration |
| `-ServiceId` | | Unique service instance ID |

### Admin API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/admin/status` | GET | Proxy status and stats |
| `/admin/reload` | POST | Reload configuration |
| `/admin/drain` | POST | Start connection draining |
| `/admin/resume` | POST | Resume accepting connections |
| `/admin/circuits` | GET | Circuit breaker states |
| `/admin/circuits/reset` | POST | Reset all circuit breakers |
| `/admin/services` | GET | Discovered services |
| `/admin/services/{name}` | GET | Endpoints for a service |
| `/admin/messaging` | GET | Message buffer stats |
| `/admin/blacklist` | GET/POST/DELETE | IP blacklist management |

### Example Admin Commands

```bash
# Check proxy status
curl http://localhost:9091/admin/status | jq .

# Reload configuration
curl -X POST http://localhost:9091/admin/reload

# Start graceful shutdown
curl -X POST http://localhost:9091/admin/drain

# View circuit breaker states
curl http://localhost:9091/admin/circuits | jq .

# Reset circuit breakers
curl -X POST http://localhost:9091/admin/circuits/reset

# Block an IP for 1 hour
curl -X POST http://localhost:9091/admin/blacklist \
  -H "Content-Type: application/json" \
  -d '{"ip": "1.2.3.4", "duration": 3600, "reason": "abuse"}'

# View discovered services
curl http://localhost:9091/admin/services | jq .

# Get endpoints for a service
curl http://localhost:9091/admin/services/order-service | jq .

# Check message queue buffer
curl http://localhost:9091/admin/messaging | jq .
```

---

## Metrics & Monitoring

### Prometheus Metrics

```
# Connection metrics
tls_proxy_connections_total          # Total connections accepted
tls_proxy_connections_active         # Currently active connections
tls_proxy_requests_total             # Total requests processed

# Data transfer
tls_proxy_bytes_in_total             # Total bytes received
tls_proxy_bytes_out_total            # Total bytes sent

# Security
tls_proxy_rate_limited_total         # Requests rejected by rate limiter
tls_proxy_auth_success_total         # Successful authentications
tls_proxy_auth_failure_total         # Failed authentications

# Reliability
tls_proxy_circuit_open_total         # Circuit breaker open events
tls_proxy_backend_errors_total       # Backend connection failures
tls_proxy_timeout_errors_total       # Request timeouts

# Messaging
tls_proxy_message_buffer_size        # Current message buffer size
tls_proxy_messages_published_total   # Messages published to queues
tls_proxy_messages_dropped_total     # Messages dropped due to backpressure

# Protocol-specific
tls_proxy_redis_commands_total       # Redis commands proxied
tls_proxy_mysql_queries_total        # MySQL queries proxied
tls_proxy_grpc_requests_total        # gRPC requests proxied
tls_proxy_graphql_queries_total      # GraphQL queries processed

# Status
tls_proxy_draining                   # 1 if draining, 0 otherwise
tls_proxy_rules_version              # Current configuration version
```

### Grafana Dashboard Queries

```promql
# Request rate
rate(tls_proxy_requests_total[5m])

# Error rate
rate(tls_proxy_backend_errors_total[5m]) / rate(tls_proxy_requests_total[5m])

# P99 latency (requires histogram)
histogram_quantile(0.99, rate(tls_proxy_request_duration_seconds_bucket[5m]))

# Active connections
tls_proxy_connections_active

# Rate limiting pressure
rate(tls_proxy_rate_limited_total[5m]) / rate(tls_proxy_requests_total[5m])

# Message queue backlog
tls_proxy_message_buffer_size

# Circuit breaker health
sum(tls_proxy_circuit_open_total) by (backend)
```

### Alerting Rules

```yaml
groups:
  - name: tls-proxy
    rules:
      - alert: HighErrorRate
        expr: rate(tls_proxy_backend_errors_total[5m]) / rate(tls_proxy_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: High error rate on TLS proxy
          
      - alert: CircuitBreakerOpen
        expr: increase(tls_proxy_circuit_open_total[5m]) > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: Circuit breaker opened
          
      - alert: MessageBufferBackpressure
        expr: tls_proxy_message_buffer_size > 50000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: Message buffer approaching capacity
          
      - alert: HighRateLimiting
        expr: rate(tls_proxy_rate_limited_total[5m]) > 100
        for: 5m
        labels:
          severity: info
        annotations:
          summary: High rate limiting activity
```

---

## Security

### TLS Configuration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          TLS CONFIGURATION                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  SUPPORTED PROTOCOLS:                                                        │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  ✅ TLS 1.3 (Preferred)                                                 ││
│  │  ✅ TLS 1.2 (Supported)                                                 ││
│  │  ❌ TLS 1.1 (Disabled)                                                  ││
│  │  ❌ TLS 1.0 (Disabled)                                                  ││
│  │  ❌ SSLv3  (Disabled)                                                   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  SNI-BASED CERTIFICATE SELECTION:                                            │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  Client SNI              │ Certificate                                  ││
│  ├──────────────────────────┼──────────────────────────────────────────────┤│
│  │  api.example.com         │ certs/api.example.com.pfx                    ││
│  │  www.example.com         │ certs/www.example.com.pfx                    ││
│  │  *.internal.example.com  │ certs/wildcard.internal.pfx                  ││
│  │  (default)               │ cert.pfx                                      ││
│  └──────────────────────────┴──────────────────────────────────────────────┘│
│                                                                              │
│  mTLS (CLIENT CERTIFICATES):                                                 │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  • Enabled per-route via auth.type = "mtls"                             ││
│  │  • Validate CN against allowedCNs list                                  ││
│  │  • Validate OU against allowedOUs list                                  ││
│  │  • Check certificate expiry                                              ││
│  │  • Optional CRL verification                                             ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Authentication Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AUTHENTICATION FLOW                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  JWT AUTHENTICATION:                                                         │
│                                                                              │
│  Client                    Proxy                      Backend                │
│    │                         │                           │                   │
│    │  Authorization: Bearer eyJ...                       │                   │
│    ├────────────────────────▶│                           │                   │
│    │                         │                           │                   │
│    │                         │ 1. Split JWT header.payload.signature        │
│    │                         │ 2. Decode payload (base64url)                │
│    │                         │ 3. Validate exp > now                        │
│    │                         │ 4. Validate iss matches config               │
│    │                         │ 5. Validate aud matches config               │
│    │                         │ 6. Extract claims (sub, email, roles)        │
│    │                         │                           │                   │
│    │                         │  X-User-Id: user-123      │                   │
│    │                         │  X-User-Email: u@e.com    │                   │
│    │                         │  X-Auth-Method: jwt       │                   │
│    │                         ├──────────────────────────▶│                   │
│    │                         │                           │                   │
│    │◀────────────────────────┼───────────────────────────│                   │
│    │                         │                           │                   │
│                                                                              │
│  OAUTH2 INTROSPECTION:                                                       │
│                                                                              │
│  Client                    Proxy                   Auth Server               │
│    │                         │                           │                   │
│    │  Authorization: Bearer opaque-token                 │                   │
│    ├────────────────────────▶│                           │                   │
│    │                         │                           │                   │
│    │                         │  POST /oauth/introspect   │                   │
│    │                         │  token=opaque-token       │                   │
│    │                         ├──────────────────────────▶│                   │
│    │                         │                           │                   │
│    │                         │  { "active": true,        │                   │
│    │                         │    "sub": "user-123",     │                   │
│    │                         │    "scope": "read write"} │                   │
│    │                         │◀──────────────────────────┤                   │
│    │                         │                           │                   │
│    │                         │ Cache result (TTL: 5min)  │                   │
│    │                         │                           │                   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Security Best Practices

1. **TLS Configuration**
   - Use TLS 1.3 where possible
   - Disable weak cipher suites
   - Enable OCSP stapling
   - Use strong certificates (RSA 2048+ or ECDSA P-256+)

2. **Authentication**
   - Prefer JWT with short expiry (15-60 minutes)
   - Use OAuth2 introspection for opaque tokens
   - Enable mTLS for service-to-service communication
   - Rotate API keys regularly

3. **Rate Limiting**
   - Set appropriate limits per route
   - Use distributed rate limiting for multi-instance deployments
   - Monitor rate limiting metrics for attacks

4. **Logging**
   - Redact sensitive headers (Authorization, Cookie)
   - Enable audit logging for security events
   - Ship logs to centralized SIEM

5. **Network**
   - Run proxy in private subnet
   - Use IP whitelisting for admin endpoints
   - Enable IP blacklisting for abuse prevention

---

## Performance Tuning

### Worker Pool Sizing

```
Recommended workers = (CPU cores × 2) + 1

Example:
- 4 core machine: 9 workers
- 8 core machine: 17 workers
- 16 core machine: 33 workers

For I/O-heavy workloads (slow backends):
workers = CPU cores × 4
```

### Buffer Sizes

| Parameter | Default | High Throughput | Low Latency |
|-----------|---------|-----------------|-------------|
| BufferSize | 65536 | 131072 | 32768 |
| Message Buffer Max | 100000 | 500000 | 50000 |
| Batch Size | 100 | 500 | 50 |
| Flush Interval | 1000ms | 5000ms | 100ms |

### Connection Pooling

```json
{
  "protocols": {
    "redis": {
      "pool": {
        "maxConnections": 100,
        "minConnections": 10,
        "maxIdleTime": 300
      }
    },
    "mysql": {
      "pool": {
        "maxConnections": 100,
        "minConnections": 10,
        "testOnBorrow": true
      }
    }
  }
}
```

### OS Tuning (Linux)

```bash
# Increase file descriptor limit
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf

# Network tuning
sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.core.netdev_max_backlog=65535
sysctl -w net.ipv4.tcp_fin_timeout=30
sysctl -w net.ipv4.tcp_keepalive_time=300
```

---

## Troubleshooting

### Common Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| TLS Handshake Failure | `AuthenticationException` | Check certificate validity, supported protocols |
| Backend Connection Refused | `SocketException` | Verify backend is running, check firewall rules |
| Rate Limiting | 429 responses | Increase limits or whitelist IPs |
| Circuit Breaker Open | 503 responses | Check backend health, reset circuit breaker |
| Message Buffer Full | Events dropped | Increase buffer size or add Kafka partitions |
| High Latency | Slow responses | Check backend health, increase workers |

### Debug Mode

```powershell
# Enable verbose logging
./TLS_Proxy.ps1 -LogLevel debug

# Check worker status
curl http://localhost:9091/admin/status | jq .

# View circuit breaker states
curl http://localhost:9091/admin/circuits | jq .

# Check message buffer
curl http://localhost:9091/admin/messaging | jq .

# Tail access logs
tail -f logs/access.log | jq .

# Tail error logs
tail -f logs/error.log
```

### Health Checks

```bash
# Basic health check
curl http://localhost:9090/health

# Prometheus metrics
curl http://localhost:9090/metrics | grep tls_proxy

# Backend health
curl http://localhost:9091/admin/services/order-service | jq '.endpoints[].healthy'
```

---

## Future Enhancements

### Planned Features

| Feature | Priority | Description | Status |
|---------|----------|-------------|--------|
| **HTTP/2 Support** | High | Full HTTP/2 multiplexing for non-gRPC traffic | 🔄 Planned |
| **HTTP/3 (QUIC)** | Medium | QUIC protocol support for improved performance | 🔄 Planned |
| **Let's Encrypt Integration** | High | Automatic certificate provisioning via ACME | 🔄 Planned |
| **WebAssembly Filters** | Medium | WASM-based request/response transformations | 🔄 Planned |
| **Lua Scripting** | Medium | Lua scripts for custom routing logic | 🔄 Planned |
| **PostgreSQL Protocol** | Medium | PostgreSQL wire protocol support | 🔄 Planned |
| **MQTT Protocol** | Low | IoT message broker proxying | 🔄 Planned |
| **AWS SQS Integration** | Medium | SQS as message queue backend | 🔄 Planned |
| **GeoIP Routing** | Medium | Route based on client location | 🔄 Planned |
| **Request Replay** | Low | Replay failed requests from queue | 🔄 Planned |
| **A/B Testing Framework** | Medium | Built-in experiment management | 🔄 Planned |
| **API Versioning** | Low | Automatic version negotiation | 🔄 Planned |

### HTTP/2 Support Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HTTP/2 SUPPORT (PLANNED)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  FEATURES:                                                                   │
│  • Full multiplexing (multiple requests per connection)                      │
│  • Header compression (HPACK)                                                │
│  • Server push support                                                       │
│  • Stream prioritization                                                     │
│  • Flow control per stream                                                   │
│                                                                              │
│  ARCHITECTURE:                                                               │
│                                                                              │
│     Client ──── HTTP/2 ────▶ Proxy ──── HTTP/2 ────▶ Backend                │
│                               │                                              │
│                               │ OR                                           │
│                               │                                              │
│     Client ──── HTTP/2 ────▶ Proxy ──── HTTP/1.1 ──▶ Backend                │
│                                                                              │
│  CONFIGURATION:                                                              │
│  {                                                                           │
│    "http2": {                                                                │
│      "enabled": true,                                                        │
│      "maxConcurrentStreams": 100,                                            │
│      "maxFrameSize": 16384,                                                  │
│      "maxHeaderListSize": 8192,                                              │
│      "initialWindowSize": 65535                                              │
│    }                                                                         │
│  }                                                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Let's Encrypt Integration Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     LET'S ENCRYPT INTEGRATION (PLANNED)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  AUTOMATIC CERTIFICATE MANAGEMENT:                                           │
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                    │
│  │  TLS Proxy  │◀───▶│ ACME Client │◀───▶│ Let's Encrypt│                   │
│  └──────┬──────┘     └─────────────┘     └─────────────┘                    │
│         │                                                                    │
│         │  1. Check certificate expiry (daily)                               │
│         │  2. If expires in < 30 days, request renewal                       │
│         │  3. Complete HTTP-01 or DNS-01 challenge                          │
│         │  4. Store new certificate                                          │
│         │  5. Hot-reload certificate (no restart)                           │
│         │                                                                    │
│  CONFIGURATION:                                                              │
│  {                                                                           │
│    "acme": {                                                                 │
│      "enabled": true,                                                        │
│      "email": "admin@example.com",                                           │
│      "domains": ["api.example.com", "www.example.com"],                      │
│      "challengeType": "http-01",                                             │
│      "renewBefore": 30,                                                      │
│      "staging": false                                                        │
│    }                                                                         │
│  }                                                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### WebAssembly Filters Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      WEBASSEMBLY FILTERS (PLANNED)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  USE CASES:                                                                  │
│  • Custom authentication logic                                               │
│  • Request/response transformation                                           │
│  • Dynamic routing decisions                                                 │
│  • Rate limiting with custom algorithms                                      │
│  • Header manipulation                                                       │
│  • Body inspection and modification                                          │
│                                                                              │
│  FILTER CHAIN:                                                               │
│                                                                              │
│     Request ──▶ [Auth Filter] ──▶ [Transform Filter] ──▶ [Route Filter]     │
│                                                              │               │
│                                                              ▼               │
│     Response ◀── [Log Filter] ◀── [Transform Filter] ◀── Backend            │
│                                                                              │
│  EXAMPLE FILTER (Rust):                                                      │
│                                                                              │
│  #[no_mangle]                                                                │
│  pub extern "C" fn on_request_headers() -> i32 {                             │
│      // Get header                                                           │
│      let auth = get_header("authorization");                                 │
│                                                                              │
│      // Custom validation                                                    │
│      if !validate_custom_token(&auth) {                                      │
│          send_response(401, "Unauthorized");                                 │
│          return 0; // Stop processing                                        │
│      }                                                                       │
│                                                                              │
│      // Add header for backend                                               │
│      set_header("x-validated", "true");                                      │
│      return 1; // Continue                                                   │
│  }                                                                           │
│                                                                              │
│  CONFIGURATION:                                                              │
│  {                                                                           │
│    "wasm": {                                                                 │
│      "filters": [                                                            │
│        {                                                                     │
│          "name": "custom-auth",                                              │
│          "path": "filters/auth.wasm",                                        │
│          "phase": "request_headers"                                          │
│        },                                                                    │
│        {                                                                     │
│          "name": "transform",                                                │
│          "path": "filters/transform.wasm",                                   │
│          "phase": "request_body"                                             │
│        }                                                                     │
│      ]                                                                       │
│    }                                                                         │
│  }                                                                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### GeoIP Routing Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GEOIP ROUTING (PLANNED)                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  FEATURES:                                                                   │
│  • Route to nearest datacenter                                               │
│  • Comply with data residency requirements                                   │
│  • Block traffic from specific countries                                     │
│  • Custom rate limits by geography                                           │
│                                                                              │
│  ROUTING RULES:                                                              │
│  {                                                                           │
│    "geoip": {                                                                │
│      "database": "/var/lib/geoip/GeoLite2-City.mmdb",                        │
│      "rules": [                                                              │
│        {                                                                     │
│          "countries": ["US", "CA"],                                          │
│          "backend": { "datacenter": "us-east-1" }                            │
│        },                                                                    │
│        {                                                                     │
│          "countries": ["DE", "FR", "GB"],                                    │
│          "backend": { "datacenter": "eu-west-1" }                            │
│        },                                                                    │
│        {                                                                     │
│          "countries": ["CN", "RU"],                                          │
│          "action": "block"                                                   │
│        }                                                                     │
│      ],                                                                      │
│      "default": { "datacenter": "us-east-1" }                                │
│    }                                                                         │
│  }                                                                           │
│                                                                              │
│  HEADERS ADDED:                                                              │
│  • X-Geo-Country: US                                                         │
│  • X-Geo-Region: California                                                  │
│  • X-Geo-City: San Francisco                                                 │
│  • X-Geo-Lat: 37.7749                                                        │
│  • X-Geo-Lon: -122.4194                                                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Contribution Guidelines

1. **Code Style**
   - Use consistent PowerShell naming conventions
   - Add XML documentation for public functions
   - Include unit tests for new features

2. **Testing**
   - Test with multiple backend types
   - Verify hot reload functionality
   - Load test with expected production traffic

3. **Documentation**
   - Update this document for new features
   - Include configuration examples
   - Document breaking changes

---

## License

MIT License - See LICENSE file for details.

## Support

- GitHub Issues: Report bugs and feature requests
- Documentation: This file and inline comments
- Community: Discussions and Q&A

---

*Last Updated: January 2026*
*Version: 1.0.0*