# ============================================
# Advanced TLS Proxy - Diamond Edition
# ============================================

param(
    [int]$HttpsPort = 8443,
    [int]$GrpcPort = 9443,
    [int]$TcpPort = 9999,
    [int]$DotPort = 853,
    [int]$MetricsPort = 9090,
    [int]$AdminPort = 9091,
    [int]$WorkerCount = 15,
    [string]$CertPath = "cert.pfx",
    [string]$CertPassword = "password",
    [string]$RulesPath = "rules.json",
    [string]$ScriptsPath = "scripts",
    [string]$WasmPath = "wasm",
    [string]$LogPath = "logs",
    [int]$BufferSize = 65536,
    [int]$TimeoutMs = 30000,
    [int]$DrainTimeoutSeconds = 30,
    [string]$OtlpEndpoint = "",
    [string]$ServiceName = "tls-proxy",
    [string]$ServiceId = "",
    [string]$ConsulAddr = "",
    [string]$RedisAddr = "",
    [string]$KafkaBrokers = "",
    [string]$LogLevel = "info"
)

# Generate unique service ID if not provided
if (-not $ServiceId) {
    $ServiceId = "$ServiceName-$($env:COMPUTERNAME)-$(Get-Random -Maximum 9999)"
}

# ============================================
# Default Rules Configuration
# ============================================

$defaultRules = @{
    default = @{ host = "127.0.0.1"; port = 8080 }
    
    routes = @(
        @{
            match = "api.*"
            backend = @{ host = "127.0.0.1"; port = 3000 }
            auth = @{ type = "jwt"; required = $true }
            circuitBreaker = @{ enabled = $true }
            # Message queue events for this route
            messaging = @{
                enabled = $true
                events = @("request", "response", "error")
                topic = "api-events"
                includeBody = $false
                includeHeaders = @("Authorization", "X-Request-ID")
            }
        }
        @{
            match = "orders.*"
            backend = @{ service = "order-service" }  # Service discovery
            serviceMesh = @{
                enabled = $true
                mtls = $true
                retryPolicy = @{
                    maxAttempts = 3
                    retryOn = @("5xx", "connection-error", "reset")
                }
                timeout = 30
                trafficPolicy = @{
                    canary = @{
                        enabled = $true
                        weight = 10
                        version = "v2"
                    }
                }
            }
            messaging = @{
                enabled = $true
                events = @("request")
                topic = "order-events"
                includeBody = $true
            }
        }
        @{
            # Redis protocol proxy
            protocol = "redis"
            listenPort = 6380
            backend = @{
                primary = @{ host = "redis-primary"; port = 6379 }
                replicas = @(
                    @{ host = "redis-replica-1"; port = 6379 }
                    @{ host = "redis-replica-2"; port = 6379 }
                )
            }
            redis = @{
                readWriteSplit = $true
                blockedCommands = @("FLUSHALL", "FLUSHDB", "DEBUG", "KEYS")
                slowLogThreshold = 100
                maxClients = 1000
            }
        }
        @{
            # MySQL protocol proxy
            protocol = "mysql"
            listenPort = 3307
            backend = @{
                primary = @{ host = "mysql-primary"; port = 3306 }
                replicas = @(
                    @{ host = "mysql-replica-1"; port = 3306 }
                )
            }
            mysql = @{
                readWriteSplit = $true
                connectionPoolSize = 100
                slowQueryThreshold = 1000
            }
        }
        @{
            # Generic TCP proxy
            protocol = "tcp"
            listenPort = 9000
            backend = @{ cluster = "tcp-cluster" }
        }
    )
    
    # ==========================================
    # Message Queue Configuration
    # ==========================================
    messaging = @{
        enabled = $true
        
        # Buffer configuration (synchronized hashtable approach)
        buffer = @{
            maxSize = 100000          # Max events in buffer before backpressure
            flushInterval = 1000      # Flush every N ms
            batchSize = 100           # Max events per batch
            dropPolicy = "oldest"     # oldest, newest, or block
        }
        
        # Kafka configuration
        kafka = @{
            enabled = $true
            brokers = @("localhost:9092")
            clientId = "tls-proxy"
            compression = "snappy"    # none, gzip, snappy, lz4, zstd
            acks = "1"                # 0, 1, all
            retries = 3
            batchSize = 16384
            lingerMs = 5
            topics = @{
                requests = "proxy-requests"
                responses = "proxy-responses"
                errors = "proxy-errors"
                metrics = "proxy-metrics"
                audit = "proxy-audit"
            }
            # Topic-specific overrides
            topicConfig = @{
                "proxy-audit" = @{
                    acks = "all"
                    retries = 10
                }
            }
        }
        
        # RabbitMQ configuration
        rabbitmq = @{
            enabled = $false
            host = "localhost"
            port = 5672
            username = "guest"
            password = "guest"
            vhost = "/"
            exchange = "proxy-events"
            exchangeType = "topic"
            durable = $true
            queues = @{
                requests = "proxy.requests"
                errors = "proxy.errors"
            }
        }
        
        # Redis Pub/Sub configuration
        redisPubSub = @{
            enabled = $false
            host = "localhost"
            port = 6379
            channels = @{
                requests = "proxy:requests"
                errors = "proxy:errors"
            }
        }
        
        # AWS SQS configuration
        sqs = @{
            enabled = $false
            region = "us-east-1"
            queues = @{
                requests = "https://sqs.us-east-1.amazonaws.com/123456789/proxy-requests"
                errors = "https://sqs.us-east-1.amazonaws.com/123456789/proxy-errors"
            }
        }
        
        # Event schema
        eventSchema = @{
            includeTimestamp = $true
            includeRequestId = $true
            includeClientIp = $true
            includeRoute = $true
            includeLatency = $true
            includeStatusCode = $true
            includeUserAgent = $true
            includeTlsInfo = $true
            # Custom fields added to all events
            customFields = @{
                "proxy_id" = "{service_id}"
                "environment" = "production"
                "datacenter" = "us-east-1"
            }
        }
    }
    
    # ==========================================
    # Service Mesh Configuration
    # ==========================================
    serviceMesh = @{
        enabled = $true
        
        # Service identity
        identity = @{
            type = "spiffe"           # spiffe, mtls, jwt
            trustDomain = "example.com"
            # SPIFFE ID: spiffe://example.com/service/tls-proxy
        }
        
        # Service discovery
        discovery = @{
            type = "consul"           # consul, etcd, kubernetes, dns, static
            
            consul = @{
                address = "localhost:8500"
                scheme = "http"
                datacenter = "dc1"
                token = ""
                # Service registration
                register = $true
                serviceName = "tls-proxy"
                serviceTags = @("proxy", "gateway")
                healthCheck = @{
                    http = "http://localhost:9090/health"
                    interval = "10s"
                    timeout = "5s"
                }
                # Watch for changes
                watch = $true
                watchInterval = 5
            }
            
            etcd = @{
                endpoints = @("localhost:2379")
                prefix = "/services"
                ttl = 30
            }
            
            kubernetes = @{
                namespace = "default"
                labelSelector = "app=backend"
                inCluster = $true
            }
            
            dns = @{
                servers = @("127.0.0.1:53")
                searchDomains = @("service.consul", "svc.cluster.local")
                ttl = 30
            }
            
            # Static service definitions (fallback)
            static = @{
                "order-service" = @(
                    @{ host = "10.0.0.1"; port = 8080; weight = 3; zone = "us-east-1a" }
                    @{ host = "10.0.0.2"; port = 8080; weight = 2; zone = "us-east-1b" }
                )
                "user-service" = @(
                    @{ host = "10.0.1.1"; port = 8080 }
                )
            }
        }
        
        # Mutual TLS
        mtls = @{
            enabled = $true
            # CA for validating service certificates
            caCertPath = "ca.crt"
            # This service's certificate
            certPath = "service.crt"
            keyPath = "service.key"
            # Certificate rotation
            rotation = @{
                enabled = $true
                checkInterval = 3600
                renewBefore = 86400
            }
            # SPIFFE Workload API
            spiffe = @{
                enabled = $false
                socketPath = "/run/spire/sockets/agent.sock"
            }
        }
        
        # Traffic management
        traffic = @{
            # Canary deployments
            canary = @{
                enabled = $true
                # Header-based routing
                headerRouting = @{
                    "X-Canary" = "true"
                }
                # Percentage-based routing
                defaultWeight = 0    # 0% to canary by default
            }
            
            # Traffic mirroring (shadow traffic)
            mirroring = @{
                enabled = $false
                target = @{ service = "shadow-service" }
                percentage = 100
                # Don't wait for mirror response
                fireAndForget = $true
            }
            
            # Traffic shifting for deployments
            shifting = @{
                enabled = $false
                versions = @{
                    "v1" = 90
                    "v2" = 10
                }
                # Gradual shift
                autoShift = @{
                    enabled = $false
                    incrementPercent = 10
                    intervalSeconds = 300
                    rollbackOnError = $true
                    errorThreshold = 0.05
                }
            }
        }
        
        # Resilience patterns
        resilience = @{
            # Retry policy
            retry = @{
                enabled = $true
                maxAttempts = 3
                initialBackoff = 100      # ms
                maxBackoff = 1000         # ms
                backoffMultiplier = 2
                retryableStatusCodes = @(502, 503, 504)
                retryableErrors = @("connection-reset", "connection-refused", "timeout")
                # Retry budget: max 20% of requests can be retries
                budget = @{
                    enabled = $true
                    percentCanRetry = 20
                    minRetriesPerSecond = 10
                    ttl = 10              # seconds
                }
            }
            
            # Timeout policy
            timeout = @{
                connect = 5000            # ms
                request = 30000           # ms
                idle = 60000              # ms
                # Per-route timeouts override these
            }
            
            # Circuit breaker (enhanced)
            circuitBreaker = @{
                enabled = $true
                failureThreshold = 5
                successThreshold = 2
                timeout = 30
                # Track by endpoint, not just by service
                trackBy = "endpoint"      # service, endpoint, cluster
                # Outlier detection
                outlierDetection = @{
                    enabled = $true
                    consecutiveErrors = 5
                    interval = 10
                    baseEjectionTime = 30
                    maxEjectionPercent = 50
                }
            }
        }
        
        # Locality-aware load balancing
        locality = @{
            enabled = $true
            # This proxy's locality
            local = @{
                region = "us-east-1"
                zone = "us-east-1a"
                subZone = ""
            }
            # Priority: same zone > same region > any
            priorityWeights = @{
                sameZone = 100
                sameRegion = 50
                any = 1
            }
            # Failover configuration
            failover = @{
                enabled = $true
                # Only failover if local capacity < threshold
                localThreshold = 0.7
            }
        }
        
        # Distributed rate limiting
        distributedRateLimit = @{
            enabled = $true
            # Redis for distributed state
            redis = @{
                address = "localhost:6379"
                keyPrefix = "ratelimit:"
                # Use Redis Cluster
                cluster = $false
            }
            # Global limits (across all proxy instances)
            globalLimits = @{
                "order-service" = @{
                    requestsPerSecond = 1000
                    burstSize = 2000
                }
            }
        }
        
        # Fault injection (for testing)
        faultInjection = @{
            enabled = $false
            # Delay injection
            delay = @{
                enabled = $false
                percentage = 10
                duration = 500           # ms
                # Target specific routes
                routes = @("order-service")
            }
            # Abort injection
            abort = @{
                enabled = $false
                percentage = 5
                statusCode = 503
                routes = @("order-service")
            }
        }
    }
    
    # ==========================================
    # Custom Protocol Support
    # ==========================================
    protocols = @{
        # Redis RESP protocol
        redis = @{
            enabled = $true
            parser = "resp"
            defaultPort = 6379
            
            # Command classification
            commands = @{
                read = @("GET", "MGET", "HGET", "HGETALL", "LRANGE", "SMEMBERS", 
                         "ZRANGE", "SCAN", "HSCAN", "SSCAN", "ZSCAN", "EXISTS",
                         "TTL", "PTTL", "TYPE", "STRLEN", "LLEN", "SCARD", "ZCARD")
                write = @("SET", "MSET", "HSET", "HMSET", "LPUSH", "RPUSH", 
                          "SADD", "ZADD", "DEL", "EXPIRE", "INCR", "DECR",
                          "APPEND", "SETEX", "SETNX", "LPOP", "RPOP")
                admin = @("FLUSHALL", "FLUSHDB", "DEBUG", "CONFIG", "SHUTDOWN",
                          "SLAVEOF", "REPLICAOF", "CLUSTER", "BGSAVE", "BGREWRITEAOF")
                dangerous = @("KEYS", "EVAL", "EVALSHA", "SCRIPT")
            }
            
            # Connection pooling
            pool = @{
                maxConnections = 100
                minConnections = 10
                maxIdleTime = 300
                connectionTimeout = 5000
            }
            
            # Metrics
            metrics = @{
                perCommand = $true
                slowLogThreshold = 100   # ms
                trackKeyPatterns = $true
            }
        }
        
        # MySQL protocol
        mysql = @{
            enabled = $true
            parser = "mysql"
            defaultPort = 3306
            
            # Query classification
            queries = @{
                read = @("SELECT", "SHOW", "DESCRIBE", "EXPLAIN")
                write = @("INSERT", "UPDATE", "DELETE", "REPLACE", "TRUNCATE")
                ddl = @("CREATE", "ALTER", "DROP", "RENAME")
                admin = @("GRANT", "REVOKE", "FLUSH", "RESET")
            }
            
            # Connection pooling
            pool = @{
                maxConnections = 100
                minConnections = 10
                maxIdleTime = 300
                connectionTimeout = 10000
                # Validate connections before use
                testOnBorrow = $true
                testQuery = "SELECT 1"
            }
            
            # Query rewriting
            rewrite = @{
                enabled = $false
                rules = @(
                    @{
                        pattern = "SELECT \* FROM users"
                        replacement = "SELECT id, name, email FROM users"
                    }
                )
            }
            
            # Slow query logging
            slowQuery = @{
                enabled = $true
                threshold = 1000         # ms
                logQuery = $true
                logParameters = $false
            }
        }
        
        # PostgreSQL protocol
        postgresql = @{
            enabled = $false
            parser = "postgresql"
            defaultPort = 5432
        }
        
        # MQTT protocol
        mqtt = @{
            enabled = $false
            parser = "mqtt"
            defaultPort = 1883
            
            # Topic routing
            routing = @{
                "sensors/#" = @{ backend = @{ host = "mqtt-sensors"; port = 1883 } }
                "commands/#" = @{ backend = @{ host = "mqtt-commands"; port = 1883 } }
            }
            
            # QoS handling
            qos = @{
                maxQos = 2
                upgradeQos = $false
            }
        }
        
        # Generic TCP (no protocol parsing)
        tcp = @{
            enabled = $true
            # Just forward bytes, no inspection
            passthrough = $true
            # Optional TLS termination
            tlsTermination = $false
        }
        
        # Protocol translation
        translation = @{
            # REST to gRPC
            "rest-to-grpc" = @{
                enabled = $false
                mappings = @{
                    "POST /api/users" = "user.UserService/CreateUser"
                    "GET /api/users/{id}" = "user.UserService/GetUser"
                }
            }
            # HTTP to WebSocket
            "http-to-ws" = @{
                enabled = $false
                path = "/stream"
                backend = "ws://stream-service:8080"
            }
        }
    }
    
    # Existing configurations...
    loadBalancing = @{
        "web-cluster" = @{
            backends = @(
                @{ host = "10.0.0.1"; port = 8080; weight = 3 }
                @{ host = "10.0.0.2"; port = 8080; weight = 2 }
            )
            strategy = "weighted-round-robin"
            healthCheck = @{ path = "/health"; interval = 10 }
        }
        "tcp-cluster" = @{
            backends = @(
                @{ host = "10.0.1.1"; port = 9000 }
                @{ host = "10.0.1.2"; port = 9000 }
            )
            strategy = "round-robin"
            healthCheck = @{ type = "tcp"; interval = 10 }
        }
    }
    
    rateLimit = @{ enabled = $true; perIp = @{ requestsPerSecond = 100; burstSize = 200 } }
    circuitBreaker = @{ enabled = $true; defaults = @{ failureThreshold = 5; timeout = 30 } }
    dns = @{ enabled = $true; upstreams = @(@{ host = "1.1.1.1"; port = 53; protocol = "udp" }); cache = @{ enabled = $true } }
    logging = @{ enabled = $true; accessLog = @{ enabled = $true } }
    metrics = @{ enabled = $true }
    admin = @{ enabled = $true }
    hotReload = @{ enabled = $true; watchInterval = 5 }
}

# ============================================
# Message Queue Buffer (Synchronized)
# ============================================

# Global message buffer - workers write here, publisher reads
$messageBuffer = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()

# Overflow buffer for backpressure (circular buffer behavior)
$messageBufferState = [hashtable]::Synchronized(@{
    Enqueued = [long]0
    Dequeued = [long]0
    Dropped = [long]0
    Published = [long]0
    Errors = [long]0
    LastFlush = [DateTime]::UtcNow
    MaxSize = 100000
    Backpressure = $false
})

# Function to enqueue messages (called by workers)
function Add-MessageToBuffer {
    param(
        [hashtable]$Message,
        [System.Collections.Concurrent.ConcurrentQueue[hashtable]]$Buffer,
        [hashtable]$State
    )
    
    # Check backpressure
    $currentSize = $State.Enqueued - $State.Dequeued
    
    if ($currentSize -ge $State.MaxSize) {
        $State.Backpressure = $true
        
        # Drop policy: oldest (dequeue and discard), newest (don't enqueue), block (wait)
        $dropPolicy = "oldest"
        
        switch ($dropPolicy) {
            "oldest" {
                $discarded = $null
                if ($Buffer.TryDequeue([ref]$discarded)) {
                    [System.Threading.Interlocked]::Increment([ref]$State.Dropped)
                    [System.Threading.Interlocked]::Increment([ref]$State.Dequeued)
                }
            }
            "newest" {
                [System.Threading.Interlocked]::Increment([ref]$State.Dropped)
                return
            }
            "block" {
                # Wait briefly for space
                Start-Sleep -Milliseconds 10
                $currentSize = $State.Enqueued - $State.Dequeued
                if ($currentSize -ge $State.MaxSize) {
                    [System.Threading.Interlocked]::Increment([ref]$State.Dropped)
                    return
                }
            }
        }
    } else {
        $State.Backpressure = $false
    }
    
    $Buffer.Enqueue($Message)
    [System.Threading.Interlocked]::Increment([ref]$State.Enqueued)
}

# ============================================
# Message Queue Publishers
# ============================================

$messagingScript = @'
# Kafka Producer (using REST Proxy or native)
class KafkaProducer {
    [hashtable]$Config
    [string]$Brokers
    [System.Net.Sockets.TcpClient]$Client
    [bool]$Connected
    
    KafkaProducer([hashtable]$config) {
        $this.Config = $config
        $this.Brokers = ($config.brokers ?? @("localhost:9092")) -join ","
        $this.Connected = $false
    }
    
    [void] Connect() {
        # For simplicity, using Kafka REST Proxy approach
        # In production, would use native Kafka protocol or librdkafka
        $this.Connected = $true
    }
    
    [bool] Publish([string]$topic, [hashtable[]]$messages) {
        if (-not $this.Connected) { $this.Connect() }
        
        try {
            # Kafka REST Proxy format
            $records = $messages | ForEach-Object {
                @{
                    key = $_.key ?? $null
                    value = $_ | ConvertTo-Json -Compress -Depth 10
                }
            }
            
            $payload = @{
                records = $records
            } | ConvertTo-Json -Depth 5
            
            # In real implementation, would send to Kafka REST Proxy
            # POST http://kafka-rest:8082/topics/{topic}
            
            # For now, simulate with file output for testing
            $logPath = "logs/kafka"
            if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }
            
            $timestamp = Get-Date -Format "yyyy-MM-dd-HH"
            $logFile = Join-Path $logPath "$topic-$timestamp.jsonl"
            
            foreach ($msg in $messages) {
                $json = $msg | ConvertTo-Json -Compress -Depth 10
                Add-Content -Path $logFile -Value $json
            }
            
            return $true
        }
        catch {
            return $false
        }
    }
    
    [void] Close() {
        $this.Connected = $false
    }
}

# RabbitMQ Producer
class RabbitMQProducer {
    [hashtable]$Config
    [bool]$Connected
    
    RabbitMQProducer([hashtable]$config) {
        $this.Config = $config
        $this.Connected = $false
    }
    
    [void] Connect() {
        # Would use AMQP protocol
        $this.Connected = $true
    }
    
    [bool] Publish([string]$routingKey, [hashtable[]]$messages) {
        if (-not $this.Connected) { $this.Connect() }
        
        try {
            # Simulate with file output
            $logPath = "logs/rabbitmq"
            if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }
            
            $timestamp = Get-Date -Format "yyyy-MM-dd-HH"
            $logFile = Join-Path $logPath "$routingKey-$timestamp.jsonl"
            
            foreach ($msg in $messages) {
                $json = $msg | ConvertTo-Json -Compress -Depth 10
                Add-Content -Path $logFile -Value $json
            }
            
            return $true
        }
        catch {
            return $false
        }
    }
    
    [void] Close() {
        $this.Connected = $false
    }
}

# Redis Pub/Sub Producer
class RedisPubSubProducer {
    [hashtable]$Config
    [System.Net.Sockets.TcpClient]$Client
    [System.IO.StreamWriter]$Writer
    [bool]$Connected
    
    RedisPubSubProducer([hashtable]$config) {
        $this.Config = $config
        $this.Connected = $false
    }
    
    [void] Connect() {
        try {
            $this.Client = [System.Net.Sockets.TcpClient]::new()
            $this.Client.Connect($this.Config.host ?? "localhost", $this.Config.port ?? 6379)
            $this.Writer = [System.IO.StreamWriter]::new($this.Client.GetStream())
            $this.Writer.AutoFlush = $true
            $this.Connected = $true
        }
        catch {
            $this.Connected = $false
        }
    }
    
    [bool] Publish([string]$channel, [hashtable[]]$messages) {
        if (-not $this.Connected) { $this.Connect() }
        if (-not $this.Connected) { return $false }
        
        try {
            foreach ($msg in $messages) {
                $json = $msg | ConvertTo-Json -Compress -Depth 10
                # RESP protocol: PUBLISH channel message
                $this.Writer.WriteLine("*3")
                $this.Writer.WriteLine("`$7")
                $this.Writer.WriteLine("PUBLISH")
                $this.Writer.WriteLine("`$$($channel.Length)")
                $this.Writer.WriteLine($channel)
                $this.Writer.WriteLine("`$$($json.Length)")
                $this.Writer.WriteLine($json)
            }
            return $true
        }
        catch {
            $this.Connected = $false
            return $false
        }
    }
    
    [void] Close() {
        if ($this.Writer) { $this.Writer.Close() }
        if ($this.Client) { $this.Client.Close() }
        $this.Connected = $false
    }
}

# Unified Message Publisher
class MessagePublisher {
    [hashtable]$Config
    [KafkaProducer]$Kafka
    [RabbitMQProducer]$RabbitMQ
    [RedisPubSubProducer]$Redis
    
    MessagePublisher([hashtable]$config) {
        $this.Config = $config
        
        if ($config.kafka.enabled) {
            $this.Kafka = [KafkaProducer]::new($config.kafka)
        }
        if ($config.rabbitmq.enabled) {
            $this.RabbitMQ = [RabbitMQProducer]::new($config.rabbitmq)
        }
        if ($config.redisPubSub.enabled) {
            $this.Redis = [RedisPubSubProducer]::new($config.redisPubSub)
        }
    }
    
    [hashtable] Publish([string]$eventType, [hashtable[]]$messages) {
        $results = @{
            Kafka = $null
            RabbitMQ = $null
            Redis = $null
            Success = $false
            Errors = @()
        }
        
        if ($this.Kafka) {
            $topic = $this.Config.kafka.topics[$eventType] ?? "proxy-$eventType"
            try {
                $results.Kafka = $this.Kafka.Publish($topic, $messages)
                if ($results.Kafka) { $results.Success = $true }
            }
            catch { $results.Errors += "Kafka: $($_.Exception.Message)" }
        }
        
        if ($this.RabbitMQ) {
            $routingKey = $this.Config.rabbitmq.queues[$eventType] ?? "proxy.$eventType"
            try {
                $results.RabbitMQ = $this.RabbitMQ.Publish($routingKey, $messages)
                if ($results.RabbitMQ) { $results.Success = $true }
            }
            catch { $results.Errors += "RabbitMQ: $($_.Exception.Message)" }
        }
        
        if ($this.Redis) {
            $channel = $this.Config.redisPubSub.channels[$eventType] ?? "proxy:$eventType"
            try {
                $results.Redis = $this.Redis.Publish($channel, $messages)
                if ($results.Redis) { $results.Success = $true }
            }
            catch { $results.Errors += "Redis: $($_.Exception.Message)" }
        }
        
        return $results
    }
    
    [void] Close() {
        if ($this.Kafka) { $this.Kafka.Close() }
        if ($this.RabbitMQ) { $this.RabbitMQ.Close() }
        if ($this.Redis) { $this.Redis.Close() }
    }
}

# Build event message
function New-ProxyEvent {
    param(
        [string]$Type,
        [hashtable]$Context,
        [hashtable]$Config
    )
    
    $event = @{
        event_type = $Type
        timestamp = [DateTime]::UtcNow.ToString("o")
        proxy_id = $Config.customFields.proxy_id ?? $env:COMPUTERNAME
    }
    
    if ($Config.includeRequestId) { $event.request_id = $Context.RequestId }
    if ($Config.includeClientIp) { $event.client_ip = $Context.ClientIp }
    if ($Config.includeRoute) { $event.route = $Context.Route }
    if ($Config.includeLatency) { $event.latency_ms = $Context.LatencyMs }
    if ($Config.includeStatusCode) { $event.status_code = $Context.StatusCode }
    if ($Config.includeUserAgent) { $event.user_agent = $Context.UserAgent }
    if ($Config.includeTlsInfo) { 
        $event.tls_version = $Context.TlsVersion
        $event.tls_cipher = $Context.TlsCipher
    }
    
    # Add context-specific fields
    if ($Context.Method) { $event.method = $Context.Method }
    if ($Context.Path) { $event.path = $Context.Path }
    if ($Context.Host) { $event.host = $Context.Host }
    if ($Context.Backend) { $event.backend = $Context.Backend }
    if ($Context.Error) { $event.error = $Context.Error }
    if ($Context.UserId) { $event.user_id = $Context.UserId }
    
    # Custom fields
    foreach ($key in $Config.customFields.Keys) {
        $value = $Config.customFields[$key]
        $value = $value -replace '\{service_id\}', $Context.ServiceId
        $event[$key] = $value
    }
    
    return $event
}
'@

# Message publisher worker script
$messagePublisherWorkerScript = @'
$publisher = [MessagePublisher]::new($MessagingConfig)

while ($SharedState.Running) {
    try {
        $batch = @{
            requests = @()
            responses = @()
            errors = @()
            metrics = @()
            audit = @()
        }
        
        $batchSize = $MessagingConfig.buffer.batchSize ?? 100
        $dequeued = 0
        
        # Dequeue messages into batches by type
        while ($dequeued -lt $batchSize) {
            $msg = $null
            if ($MessageBuffer.TryDequeue([ref]$msg)) {
                [System.Threading.Interlocked]::Increment([ref]$BufferState.Dequeued)
                $dequeued++
                
                $eventType = $msg.event_type ?? "requests"
                if ($batch.ContainsKey($eventType)) {
                    $batch[$eventType] += $msg
                } else {
                    $batch["requests"] += $msg
                }
            } else {
                break
            }
        }
        
        # Publish each batch
        foreach ($eventType in $batch.Keys) {
            $messages = $batch[$eventType]
            if ($messages.Count -gt 0) {
                $result = $publisher.Publish($eventType, $messages)
                
                if ($result.Success) {
                    [System.Threading.Interlocked]::Add([ref]$BufferState.Published, $messages.Count)
                } else {
                    [System.Threading.Interlocked]::Add([ref]$BufferState.Errors, $messages.Count)
                    # Re-queue failed messages (with retry limit)
                    foreach ($msg in $messages) {
                        $msg._retryCount = ($msg._retryCount ?? 0) + 1
                        if ($msg._retryCount -lt 3) {
                            $MessageBuffer.Enqueue($msg)
                            [System.Threading.Interlocked]::Increment([ref]$BufferState.Enqueued)
                        }
                    }
                }
            }
        }
        
        $BufferState.LastFlush = [DateTime]::UtcNow
        
        # Wait for next flush interval
        Start-Sleep -Milliseconds ($MessagingConfig.buffer.flushInterval ?? 1000)
    }
    catch {
        Start-Sleep -Milliseconds 1000
    }
}

$publisher.Close()
'@

# ============================================
# Service Mesh Implementation
# ============================================

$serviceMeshScript = @'
# Service Discovery Client
class ServiceDiscovery {
    [hashtable]$Config
    [hashtable]$ServiceCache
    [object]$Lock
    
    ServiceDiscovery([hashtable]$config) {
        $this.Config = $config
        $this.ServiceCache = @{}
        $this.Lock = [object]::new()
    }
    
    [array] GetEndpoints([string]$serviceName) {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            # Check cache
            if ($this.ServiceCache.ContainsKey($serviceName)) {
                $cached = $this.ServiceCache[$serviceName]
                if ($cached.Expiry -gt [DateTime]::UtcNow) {
                    return $cached.Endpoints
                }
            }
            
            # Fetch from discovery source
            $endpoints = switch ($this.Config.type) {
                "consul" { $this.GetFromConsul($serviceName) }
                "etcd" { $this.GetFromEtcd($serviceName) }
                "kubernetes" { $this.GetFromKubernetes($serviceName) }
                "dns" { $this.GetFromDns($serviceName) }
                "static" { $this.GetFromStatic($serviceName) }
                default { @() }
            }
            
            # Cache results
            $this.ServiceCache[$serviceName] = @{
                Endpoints = $endpoints
                Expiry = [DateTime]::UtcNow.AddSeconds(30)
            }
            
            return $endpoints
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [array] GetFromConsul([string]$serviceName) {
        try {
            $consul = $this.Config.consul
            $url = "$($consul.scheme)://$($consul.address)/v1/health/service/$serviceName`?passing=true"
            
            if ($consul.datacenter) { $url += "&dc=$($consul.datacenter)" }
            
            $headers = @{}
            if ($consul.token) { $headers["X-Consul-Token"] = $consul.token }
            
            # HTTP request to Consul
            $request = [System.Net.HttpWebRequest]::Create($url)
            $request.Method = "GET"
            $request.Timeout = 5000
            foreach ($h in $headers.Keys) { $request.Headers.Add($h, $headers[$h]) }
            
            $response = $request.GetResponse()
            $reader = [System.IO.StreamReader]::new($response.GetResponseStream())
            $json = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()
            
            $services = $json | ConvertFrom-Json
            
            return $services | ForEach-Object {
                @{
                    host = $_.Service.Address ?? $_.Node.Address
                    port = $_.Service.Port
                    weight = $_.Service.Weights.Passing ?? 1
                    zone = $_.Node.Meta.zone ?? ""
                    tags = $_.Service.Tags
                    healthy = $true
                }
            }
        }
        catch {
            return @()
        }
    }
    
    [array] GetFromEtcd([string]$serviceName) {
        try {
            $etcd = $this.Config.etcd
            $prefix = "$($etcd.prefix)/$serviceName"
            
            # Would use etcd API
            # GET /v3/kv/range with prefix
            
            return @()
        }
        catch {
            return @()
        }
    }
    
    [array] GetFromKubernetes([string]$serviceName) {
        try {
            $k8s = $this.Config.kubernetes
            
            # Would use Kubernetes API
            # GET /api/v1/namespaces/{namespace}/endpoints/{serviceName}
            
            return @()
        }
        catch {
            return @()
        }
    }
    
    [array] GetFromDns([string]$serviceName) {
        try {
            $dns = $this.Config.dns
            
            # SRV record lookup
            $fqdn = "$serviceName.$($dns.searchDomains[0])"
            
            # Would use DNS SRV lookup
            # _serviceName._tcp.service.consul
            
            return @()
        }
        catch {
            return @()
        }
    }
    
    [array] GetFromStatic([string]$serviceName) {
        if ($this.Config.static.ContainsKey($serviceName)) {
            return $this.Config.static[$serviceName]
        }
        return @()
    }
    
    [void] RegisterService([string]$serviceId, [string]$serviceName, [int]$port, [string[]]$tags) {
        if ($this.Config.type -ne "consul" -or -not $this.Config.consul.register) { return }
        
        try {
            $consul = $this.Config.consul
            $url = "$($consul.scheme)://$($consul.address)/v1/agent/service/register"
            
            $registration = @{
                ID = $serviceId
                Name = $serviceName
                Port = $port
                Tags = $tags
                Check = @{
                    HTTP = $consul.healthCheck.http
                    Interval = $consul.healthCheck.interval
                    Timeout = $consul.healthCheck.timeout
                }
            }
            
            $json = $registration | ConvertTo-Json -Depth 5
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            
            $request = [System.Net.HttpWebRequest]::Create($url)
            $request.Method = "PUT"
            $request.ContentType = "application/json"
            $request.ContentLength = $bytes.Length
            
            if ($consul.token) { $request.Headers.Add("X-Consul-Token", $consul.token) }
            
            $stream = $request.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
            
            $response = $request.GetResponse()
            $response.Close()
        }
        catch { }
    }
    
    [void] DeregisterService([string]$serviceId) {
        if ($this.Config.type -ne "consul") { return }
        
        try {
            $consul = $this.Config.consul
            $url = "$($consul.scheme)://$($consul.address)/v1/agent/service/deregister/$serviceId"
            
            $request = [System.Net.HttpWebRequest]::Create($url)
            $request.Method = "PUT"
            
            if ($consul.token) { $request.Headers.Add("X-Consul-Token", $consul.token) }
            
            $response = $request.GetResponse()
            $response.Close()
        }
        catch { }
    }
}

# Locality-aware load balancer
class LocalityLoadBalancer {
    [hashtable]$Config
    [hashtable]$LocalLocality
    
    LocalityLoadBalancer([hashtable]$config) {
        $this.Config = $config
        $this.LocalLocality = $config.local ?? @{}
    }
    
    [hashtable] SelectEndpoint([array]$endpoints, [hashtable]$state, [string]$key) {
        if ($endpoints.Count -eq 0) { return $null }
        
        if (-not $this.Config.enabled) {
            # Simple round-robin
            $idx = $state.LoadBalancerState[$key] ?? 0
            $selected = $endpoints[$idx % $endpoints.Count]
            $state.LoadBalancerState[$key] = $idx + 1
            return $selected
        }
        
        # Group by locality
        $sameZone = @()
        $sameRegion = @()
        $other = @()
        
        foreach ($ep in $endpoints) {
            if ($ep.zone -eq $this.LocalLocality.zone) {
                $sameZone += $ep
            }
            elseif ($ep.region -eq $this.LocalLocality.region) {
                $sameRegion += $ep
            }
            else {
                $other += $ep
            }
        }
        
        # Select from highest priority group with available endpoints
        $pool = if ($sameZone.Count -gt 0) { $sameZone }
                elseif ($sameRegion.Count -gt 0) { $sameRegion }
                else { $other }
        
        if ($pool.Count -eq 0) { $pool = $endpoints }
        
        # Weighted selection within pool
        $totalWeight = ($pool | Measure-Object -Property weight -Sum).Sum
        if ($totalWeight -le 0) { $totalWeight = $pool.Count }
        
        $random = Get-Random -Minimum 0 -Maximum $totalWeight
        $cumulative = 0
        
        foreach ($ep in $pool) {
            $cumulative += ($ep.weight ?? 1)
            if ($random -lt $cumulative) {
                return $ep
            }
        }
        
        return $pool[0]
    }
}

# Distributed Rate Limiter (Redis-backed)
class DistributedRateLimiter {
    [hashtable]$Config
    [System.Net.Sockets.TcpClient]$RedisClient
    [System.IO.Stream]$RedisStream
    [bool]$Connected
    [object]$Lock
    
    DistributedRateLimiter([hashtable]$config) {
        $this.Config = $config
        $this.Connected = $false
        $this.Lock = [object]::new()
    }
    
    [void] Connect() {
        try {
            $parts = $this.Config.redis.address -split ':'
            $host = $parts[0]
            $port = if ($parts.Count -gt 1) { [int]$parts[1] } else { 6379 }
            
            $this.RedisClient = [System.Net.Sockets.TcpClient]::new()
            $this.RedisClient.Connect($host, $port)
            $this.RedisStream = $this.RedisClient.GetStream()
            $this.Connected = $true
        }
        catch {
            $this.Connected = $false
        }
    }
    
    [hashtable] CheckLimit([string]$key, [double]$limit, [int]$window) {
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            if (-not $this.Connected) { $this.Connect() }
            if (-not $this.Connected) { return @{ Allowed = $true } }  # Fail open
            
            $fullKey = "$($this.Config.redis.keyPrefix)$key"
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $windowStart = $now - ($window * 1000)
            
            # Sliding window rate limiting using Redis sorted set
            # MULTI
            # ZREMRANGEBYSCORE key 0 windowStart
            # ZADD key now now
            # ZCARD key
            # EXPIRE key window
            # EXEC
            
            $commands = @(
                "*1`r`n`$5`r`nMULTI`r`n",
                "*4`r`n`$15`r`nZREMRANGEBYSCORE`r`n`$$($fullKey.Length)`r`n$fullKey`r`n`$1`r`n0`r`n`$$($windowStart.ToString().Length)`r`n$windowStart`r`n",
                "*4`r`n`$4`r`nZADD`r`n`$$($fullKey.Length)`r`n$fullKey`r`n`$$($now.ToString().Length)`r`n$now`r`n`$$($now.ToString().Length)`r`n$now`r`n",
                "*2`r`n`$5`r`nZCARD`r`n`$$($fullKey.Length)`r`n$fullKey`r`n",
                "*3`r`n`$6`r`nEXPIRE`r`n`$$($fullKey.Length)`r`n$fullKey`r`n`$$($window.ToString().Length)`r`n$window`r`n",
                "*1`r`n`$4`r`nEXEC`r`n"
            )
            
            $cmdBytes = [System.Text.Encoding]::ASCII.GetBytes($commands -join "")
            $this.RedisStream.Write($cmdBytes, 0, $cmdBytes.Length)
            $this.RedisStream.Flush()
            
            # Read response
            $buffer = [byte[]]::new(1024)
            $read = $this.RedisStream.Read($buffer, 0, $buffer.Length)
            $response = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
            
            # Parse ZCARD result from EXEC response
            if ($response -match ':(\d+)') {
                $count = [int]$Matches[1]
                
                if ($count -gt $limit) {
                    return @{
                        Allowed = $false
                        Current = $count
                        Limit = $limit
                        RetryAfter = $window
                    }
                }
            }
            
            return @{
                Allowed = $true
                Current = $count ?? 0
                Limit = $limit
            }
        }
        catch {
            $this.Connected = $false
            return @{ Allowed = $true }  # Fail open
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
    
    [void] Close() {
        if ($this.RedisStream) { $this.RedisStream.Close() }
        if ($this.RedisClient) { $this.RedisClient.Close() }
        $this.Connected = $false
    }
}

# Traffic Manager (canary, mirroring, shifting)
class TrafficManager {
    [hashtable]$Config
    
    TrafficManager([hashtable]$config) {
        $this.Config = $config
    }
    
    [hashtable] RouteRequest([hashtable]$request, [array]$endpoints) {
        $result = @{
            Primary = $null
            Mirror = $null
            Version = $null
        }
        
        # Check header-based routing first
        if ($this.Config.canary.enabled -and $this.Config.canary.headerRouting) {
            foreach ($header in $this.Config.canary.headerRouting.Keys) {
                $expectedValue = $this.Config.canary.headerRouting[$header]
                if ($request.Headers[$header] -eq $expectedValue) {
                    # Route to canary
                    $canaryEndpoints = $endpoints | Where-Object { $_.tags -contains "canary" -or $_.version -eq "canary" }
                    if ($canaryEndpoints.Count -gt 0) {
                        $result.Primary = $canaryEndpoints[0]
                        $result.Version = "canary"
                        return $result
                    }
                }
            }
        }
        
        # Percentage-based canary
        if ($this.Config.canary.enabled -and $this.Config.canary.defaultWeight -gt 0) {
            $random = Get-Random -Minimum 0 -Maximum 100
            if ($random -lt $this.Config.canary.defaultWeight) {
                $canaryEndpoints = $endpoints | Where-Object { $_.tags -contains "canary" }
                if ($canaryEndpoints.Count -gt 0) {
                    $result.Primary = $canaryEndpoints[0]
                    $result.Version = "canary"
                }
            }
        }
        
        # Traffic shifting
        if ($this.Config.shifting.enabled -and $this.Config.shifting.versions) {
            $random = Get-Random -Minimum 0 -Maximum 100
            $cumulative = 0
            
            foreach ($version in $this.Config.shifting.versions.Keys) {
                $weight = $this.Config.shifting.versions[$version]
                $cumulative += $weight
                
                if ($random -lt $cumulative) {
                    $versionEndpoints = $endpoints | Where-Object { $_.version -eq $version -or $_.tags -contains $version }
                    if ($versionEndpoints.Count -gt 0) {
                        $result.Primary = $versionEndpoints[0]
                        $result.Version = $version
                        break
                    }
                }
            }
        }
        
        # Traffic mirroring
        if ($this.Config.mirroring.enabled) {
            $random = Get-Random -Minimum 0 -Maximum 100
            if ($random -lt $this.Config.mirroring.percentage) {
                $result.Mirror = $this.Config.mirroring.target
            }
        }
        
        # Default: first available endpoint
        if (-not $result.Primary -and $endpoints.Count -gt 0) {
            $result.Primary = $endpoints[0]
            $result.Version = "default"
        }
        
        return $result
    }
}

# Retry Policy
class RetryPolicy {
    [hashtable]$Config
    [hashtable]$RetryBudget
    [object]$Lock
    
    RetryPolicy([hashtable]$config) {
        $this.Config = $config
        $this.RetryBudget = @{
            Requests = 0
            Retries = 0
            WindowStart = [DateTime]::UtcNow
        }
        $this.Lock = [object]::new()
    }
    
    [bool] ShouldRetry([int]$statusCode, [string]$error, [int]$attempt) {
        if (-not $this.Config.enabled) { return $false }
        if ($attempt -ge $this.Config.maxAttempts) { return $false }
        
        # Check retryable conditions
        $retryable = $false
        
        if ($statusCode -in $this.Config.retryableStatusCodes) {
            $retryable = $true
        }
        
        if ($error -and $this.Config.retryableErrors) {
            foreach ($pattern in $this.Config.retryableErrors) {
                if ($error -match $pattern) {
                    $retryable = $true
                    break
                }
            }
        }
        
        if (-not $retryable) { return $false }
        
        # Check retry budget
        if ($this.Config.budget.enabled) {
            [System.Threading.Monitor]::Enter($this.Lock)
            try {
                $now = [DateTime]::UtcNow
                $windowSeconds = $this.Config.budget.ttl ?? 10
                
                if (($now - $this.RetryBudget.WindowStart).TotalSeconds -gt $windowSeconds) {
                    $this.RetryBudget.Requests = 0
                    $this.RetryBudget.Retries = 0
                    $this.RetryBudget.WindowStart = $now
                }
                
                $maxRetries = [Math]::Max(
                    $this.Config.budget.minRetriesPerSecond * $windowSeconds,
                    $this.RetryBudget.Requests * ($this.Config.budget.percentCanRetry / 100)
                )
                
                if ($this.RetryBudget.Retries -ge $maxRetries) {
                    return $false
                }
                
                $this.RetryBudget.Retries++
            }
            finally {
                [System.Threading.Monitor]::Exit($this.Lock)
            }
        }
        
        return $true
    }
    
    [int] GetBackoffMs([int]$attempt) {
        $backoff = $this.Config.initialBackoff * [Math]::Pow($this.Config.backoffMultiplier, $attempt - 1)
        return [Math]::Min($backoff, $this.Config.maxBackoff)
    }
    
    [void] RecordRequest() {
        if (-not $this.Config.budget.enabled) { return }
        
        [System.Threading.Monitor]::Enter($this.Lock)
        try {
            $this.RetryBudget.Requests++
        }
        finally {
            [System.Threading.Monitor]::Exit($this.Lock)
        }
    }
}

# Fault Injector
class FaultInjector {
    [hashtable]$Config
    
    FaultInjector([hashtable]$config) {
        $this.Config = $config
    }
    
    [hashtable] MaybeInjectFault([string]$route) {
        if (-not $this.Config.enabled) {
            return @{ Inject = $false }
        }
        
        # Delay injection
        if ($this.Config.delay.enabled) {
            $routes = $this.Config.delay.routes ?? @()
            if ($routes.Count -eq 0 -or $route -in $routes) {
                $random = Get-Random -Minimum 0 -Maximum 100
                if ($random -lt $this.Config.delay.percentage) {
                    return @{
                        Inject = $true
                        Type = "delay"
                        Duration = $this.Config.delay.duration
                    }
                }
            }
        }
        
        # Abort injection
        if ($this.Config.abort.enabled) {
            $routes = $this.Config.abort.routes ?? @()
            if ($routes.Count -eq 0 -or $route -in $routes) {
                $random = Get-Random -Minimum 0 -Maximum 100
                if ($random -lt $this.Config.abort.percentage) {
                    return @{
                        Inject = $true
                        Type = "abort"
                        StatusCode = $this.Config.abort.statusCode
                    }
                }
            }
        }
        
        return @{ Inject = $false }
    }
}
'@

# ============================================
# Custom Protocol Support
# ============================================

$protocolsScript = @'
# RESP (Redis) Protocol Parser
class RespParser {
    [System.IO.Stream]$Stream
    [byte[]]$Buffer
    [int]$Position
    [int]$Length
    
    RespParser([System.IO.Stream]$stream) {
        $this.Stream = $stream
        $this.Buffer = [byte[]]::new(65536)
        $this.Position = 0
        $this.Length = 0
    }
    
    [void] Fill() {
        if ($this.Position -gt 0 -and $this.Position -lt $this.Length) {
            [Array]::Copy($this.Buffer, $this.Position, $this.Buffer, 0, $this.Length - $this.Position)
            $this.Length -= $this.Position
            $this.Position = 0
        }
        elseif ($this.Position -ge $this.Length) {
            $this.Position = 0
            $this.Length = 0
        }
        
        $read = $this.Stream.Read($this.Buffer, $this.Length, $this.Buffer.Length - $this.Length)
        if ($read -gt 0) {
            $this.Length += $read
        }
    }
    
    [string] ReadLine() {
        while ($true) {
            for ($i = $this.Position; $i -lt $this.Length - 1; $i++) {
                if ($this.Buffer[$i] -eq 13 -and $this.Buffer[$i + 1] -eq 10) {  # \r\n
                    $line = [System.Text.Encoding]::UTF8.GetString($this.Buffer, $this.Position, $i - $this.Position)
                    $this.Position = $i + 2
                    return $line
                }
            }
            $this.Fill()
            if ($this.Length -eq 0) { return $null }
        }
        return $null
    }
    
    [object] Parse() {
        $line = $this.ReadLine()
        if (-not $line) { return $null }
        
        $type = $line[0]
        $data = $line.Substring(1)
        
        switch ($type) {
            '+' { return @{ Type = "SimpleString"; Value = $data } }
            '-' { return @{ Type = "Error"; Value = $data } }
            ':' { return @{ Type = "Integer"; Value = [long]$data } }
            '$' {
                $length = [int]$data
                if ($length -eq -1) { return @{ Type = "BulkString"; Value = $null } }
                
                # Read bulk string
                while ($this.Length - $this.Position -lt $length + 2) {
                    $this.Fill()
                }
                
                $value = [System.Text.Encoding]::UTF8.GetString($this.Buffer, $this.Position, $length)
                $this.Position += $length + 2  # Skip \r\n
                
                return @{ Type = "BulkString"; Value = $value }
            }
            '*' {
                $count = [int]$data
                if ($count -eq -1) { return @{ Type = "Array"; Value = $null } }
                
                $array = @()
                for ($i = 0; $i -lt $count; $i++) {
                    $array += $this.Parse()
                }
                
                return @{ Type = "Array"; Value = $array; Command = if ($array.Count -gt 0) { $array[0].Value.ToUpper() } else { $null } }
            }
            default { return @{ Type = "Unknown"; Value = $line } }
        }
    }
}

# Redis Protocol Handler
class RedisProtocolHandler {
    [hashtable]$Config
    [hashtable]$CommandConfig
    
    RedisProtocolHandler([hashtable]$config) {
        $this.Config = $config
        $this.CommandConfig = $config.commands ?? @{}
    }
    
    [string] ClassifyCommand([string]$command) {
        $upper = $command.ToUpper()
        
        if ($upper -in ($this.CommandConfig.admin ?? @())) { return "admin" }
        if ($upper -in ($this.CommandConfig.dangerous ?? @())) { return "dangerous" }
        if ($upper -in ($this.CommandConfig.write ?? @())) { return "write" }
        if ($upper -in ($this.CommandConfig.read ?? @())) { return "read" }
        
        # Default classification based on common patterns
        if ($upper -match '^(GET|MGET|HGET|LRANGE|SCAN|EXISTS|TTL|TYPE|STRLEN)') { return "read" }
        if ($upper -match '^(SET|DEL|HSET|LPUSH|SADD|ZADD|INCR|EXPIRE)') { return "write" }
        
        return "unknown"
    }
    
    [bool] IsBlocked([string]$command) {
        $blocked = $this.Config.blockedCommands ?? @()
        return $command.ToUpper() -in $blocked
    }
    
    [hashtable] SelectBackend([string]$commandType, [hashtable]$backends) {
        if ($this.Config.readWriteSplit) {
            if ($commandType -eq "read" -and $backends.replicas -and $backends.replicas.Count -gt 0) {
                # Round-robin replicas
                $idx = Get-Random -Minimum 0 -Maximum $backends.replicas.Count
                return $backends.replicas[$idx]
            }
        }
        
        return $backends.primary
    }
    
    [byte[]] BuildError([string]$message) {
        return [System.Text.Encoding]::UTF8.GetBytes("-ERR $message`r`n")
    }
    
    [byte[]] BuildResponse([object]$value) {
        if ($value -eq $null) {
            return [System.Text.Encoding]::UTF8.GetBytes("`$-1`r`n")
        }
        if ($value -is [string]) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
            return [System.Text.Encoding]::UTF8.GetBytes("`$$($bytes.Length)`r`n$value`r`n")
        }
        if ($value -is [int] -or $value -is [long]) {
            return [System.Text.Encoding]::UTF8.GetBytes(":$value`r`n")
        }
        if ($value -is [array]) {
            $result = "*$($value.Count)`r`n"
            foreach ($item in $value) {
                $result += [System.Text.Encoding]::UTF8.GetString($this.BuildResponse($item))
            }
            return [System.Text.Encoding]::UTF8.GetBytes($result)
        }
        
        return [System.Text.Encoding]::UTF8.GetBytes("+OK`r`n")
    }
}

# MySQL Protocol Handler
class MySqlProtocolHandler {
    [hashtable]$Config
    [int]$SequenceId
    
    MySqlProtocolHandler([hashtable]$config) {
        $this.Config = $config
        $this.SequenceId = 0
    }
    
    [hashtable] ParsePacket([byte[]]$buffer, [int]$offset) {
        if ($buffer.Length - $offset -lt 4) { return $null }
        
        $length = [int]$buffer[$offset] + ([int]$buffer[$offset + 1] -shl 8) + ([int]$buffer[$offset + 2] -shl 16)
        $seqId = $buffer[$offset + 3]
        
        if ($buffer.Length - $offset - 4 -lt $length) { return $null }
        
        $payload = [byte[]]::new($length)
        [Array]::Copy($buffer, $offset + 4, $payload, 0, $length)
        
        return @{
            Length = $length
            SequenceId = $seqId
            Payload = $payload
            TotalLength = $length + 4
        }
    }
    
    [string] ClassifyQuery([string]$query) {
        $trimmed = $query.TrimStart().ToUpper()
        
        if ($trimmed.StartsWith("SELECT") -or $trimmed.StartsWith("SHOW") -or 
            $trimmed.StartsWith("DESCRIBE") -or $trimmed.StartsWith("EXPLAIN")) {
            return "read"
        }
        if ($trimmed.StartsWith("INSERT") -or $trimmed.StartsWith("UPDATE") -or 
            $trimmed.StartsWith("DELETE") -or $trimmed.StartsWith("REPLACE")) {
            return "write"
        }
        if ($trimmed.StartsWith("CREATE") -or $trimmed.StartsWith("ALTER") -or 
            $trimmed.StartsWith("DROP") -or $trimmed.StartsWith("TRUNCATE")) {
            return "ddl"
        }
        if ($trimmed.StartsWith("GRANT") -or $trimmed.StartsWith("REVOKE") -or
            $trimmed.StartsWith("FLUSH")) {
            return "admin"
        }
        
        return "unknown"
    }
    
    [hashtable] SelectBackend([string]$queryType, [hashtable]$backends) {
        if ($this.Config.readWriteSplit -and $queryType -eq "read") {
            if ($backends.replicas -and $backends.replicas.Count -gt 0) {
                $idx = Get-Random -Minimum 0 -Maximum $backends.replicas.Count
                return $backends.replicas[$idx]
            }
        }
        
        return $backends.primary
    }
    
    [byte[]] BuildErrorPacket([int]$errorCode, [string]$sqlState, [string]$message) {
        $this.SequenceId++
        
        $payload = [System.IO.MemoryStream]::new()
        $payload.WriteByte(0xFF)  # Error marker
        
        # Error code (little endian)
        $payload.WriteByte($errorCode -band 0xFF)
        $payload.WriteByte(($errorCode -shr 8) -band 0xFF)
        
        # SQL State marker and state
        $payload.WriteByte([byte][char]'#')
        $stateBytes = [System.Text.Encoding]::ASCII.GetBytes($sqlState.PadRight(5).Substring(0, 5))
        $payload.Write($stateBytes, 0, 5)
        
        # Message
        $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($message)
        $payload.Write($msgBytes, 0, $msgBytes.Length)
        
        $payloadBytes = $payload.ToArray()
        
        # Build full packet
        $packet = [byte[]]::new($payloadBytes.Length + 4)
        $packet[0] = $payloadBytes.Length -band 0xFF
        $packet[1] = ($payloadBytes.Length -shr 8) -band 0xFF
        $packet[2] = ($payloadBytes.Length -shr 16) -band 0xFF
        $packet[3] = $this.SequenceId
        [Array]::Copy($payloadBytes, 0, $packet, 4, $payloadBytes.Length)
        
        return $packet
    }
}

# Generic TCP Handler (passthrough)
class TcpProtocolHandler {
    [hashtable]$Config
    
    TcpProtocolHandler([hashtable]$config) {
        $this.Config = $config
    }
    
    # Just forward bytes, no parsing
    [void] Relay([System.IO.Stream]$client, [System.IO.Stream]$backend, [int]$bufferSize, [ref]$bytesCounter) {
        $buffer = [byte[]]::new($bufferSize)
        
        try {
            while ($true) {
                $read = $client.Read($buffer, 0, $buffer.Length)
                if ($read -eq 0) { break }
                
                $backend.Write($buffer, 0, $read)
                $backend.Flush()
                
                if ($bytesCounter) {
                    [System.Threading.Interlocked]::Add($bytesCounter, $read)
                }
            }
        }
        catch { }
    }
}

# Protocol Router
class ProtocolRouter {
    [hashtable]$Handlers
    [hashtable]$Config
    
    ProtocolRouter([hashtable]$config) {
        $this.Config = $config
        $this.Handlers = @{}
        
        if ($config.redis.enabled) {
            $this.Handlers["redis"] = [RedisProtocolHandler]::new($config.redis)
        }
        if ($config.mysql.enabled) {
            $this.Handlers["mysql"] = [MySqlProtocolHandler]::new($config.mysql)
        }
        if ($config.tcp.enabled) {
            $this.Handlers["tcp"] = [TcpProtocolHandler]::new($config.tcp)
        }
    }
    
    [object] GetHandler([string]$protocol) {
        return $this.Handlers[$protocol]
    }
}
'@

# ============================================
# Redis Protocol Worker
# ============================================

$redisWorkerScript = @'
while ($SharedState.Running) {
    $client = $null
    $backendClient = $null
    
    try {
        $client = $RedisListener.AcceptTcpClient()
        
        if ($SharedState.Draining) { $client.Close(); continue }
        
        [System.Threading.Interlocked]::Increment([ref]$Metrics.TotalConnections)
        [System.Threading.Interlocked]::Increment([ref]$Metrics.ActiveConnections)
        
        $client.NoDelay = $true
        $clientStream = $client.GetStream()
        $clientIp = $client.Client.RemoteEndPoint.Address.ToString()
        
        $parser = [RespParser]::new($clientStream)
        $handler = $ProtocolRouter.GetHandler("redis")
        $backendStreams = @{}
        
        while ($client.Connected -and $SharedState.Running) {
            $command = $parser.Parse()
            
            if (-not $command -or $command.Type -ne "Array") { break }
            
            $cmdName = $command.Command
            
            if (-not $cmdName) { continue }
            
            [System.Threading.Interlocked]::Increment([ref]$Metrics.TotalRequests)
            
            # Check if blocked
            if ($handler.IsBlocked($cmdName)) {
                $error = $handler.BuildError("Command '$cmdName' is not allowed")
                $clientStream.Write($error, 0, $error.Length)
                continue
            }
            
            # Classify and route
            $cmdType = $handler.ClassifyCommand($cmdName)
            $backend = $handler.SelectBackend($cmdType, $RouteConfig.backend)
            
            $backendKey = "$($backend.host):$($backend.port)"
            
            # Get or create backend connection
            if (-not $backendStreams.ContainsKey($backendKey)) {
                $bc = [System.Net.Sockets.TcpClient]::new()
                $bc.Connect($backend.host, $backend.port)
                $bc.NoDelay = $true
                $backendStreams[$backendKey] = @{
                    Client = $bc
                    Stream = $bc.GetStream()
                }
            }
            
            $backendStream = $backendStreams[$backendKey].Stream
            
            # Forward command (rebuild RESP)
            $respCmd = "*$($command.Value.Count)`r`n"
            foreach ($arg in $command.Value) {
                $argBytes = [System.Text.Encoding]::UTF8.GetBytes($arg.Value)
                $respCmd += "`$$($argBytes.Length)`r`n$($arg.Value)`r`n"
            }
            
            $cmdBytes = [System.Text.Encoding]::UTF8.GetBytes($respCmd)
            $backendStream.Write($cmdBytes, 0, $cmdBytes.Length)
            $backendStream.Flush()
            
            [System.Threading.Interlocked]::Add([ref]$Metrics.BytesIn, $cmdBytes.Length)
            
            # Read and forward response
            $backendParser = [RespParser]::new($backendStream)
            $response = $backendParser.Parse()
            
            # Serialize response back to client
            $respBytes = switch ($response.Type) {
                "SimpleString" { [System.Text.Encoding]::UTF8.GetBytes("+$($response.Value)`r`n") }
                "Error" { [System.Text.Encoding]::UTF8.GetBytes("-$($response.Value)`r`n") }
                "Integer" { [System.Text.Encoding]::UTF8.GetBytes(":$($response.Value)`r`n") }
                "BulkString" { 
                    if ($response.Value -eq $null) { 
                        [System.Text.Encoding]::UTF8.GetBytes("`$-1`r`n") 
                    } else { 
                        [System.Text.Encoding]::UTF8.GetBytes("`$$($response.Value.Length)`r`n$($response.Value)`r`n") 
                    }
                }
                default { [System.Text.Encoding]::UTF8.GetBytes("+OK`r`n") }
            }
            
            $clientStream.Write($respBytes, 0, $respBytes.Length)
            $clientStream.Flush()
            
            [System.Threading.Interlocked]::Add([ref]$Metrics.BytesOut, $respBytes.Length)
            
            # Emit message event
            if ($MessagingEnabled) {
                $event = @{
                    event_type = "requests"
                    timestamp = [DateTime]::UtcNow.ToString("o")
                    protocol = "redis"
                    command = $cmdName
                    command_type = $cmdType
                    client_ip = $clientIp
                    backend = $backendKey
                }
                Add-MessageToBuffer $event $MessageBuffer $BufferState
            }
        }
        
        # Close backend connections
        foreach ($bs in $backendStreams.Values) {
            $bs.Stream.Close()
            $bs.Client.Close()
        }
    }
    catch { }
    finally {
        [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
        if ($client) { try { $client.Close() } catch {} }
    }
}
'@

# ============================================
# Main HTTP Worker with Service Mesh
# ============================================

$httpWorkerScript = @'
function Get-RequestPath { param([string]$R); if ($R -match '^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+([^\s]+)') { return $Matches[2] }; return "/" }
function Get-RequestMethod { param([string]$R); if ($R -match '^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)') { return $Matches[1] }; return "GET" }
function Get-RequestHeaders { param([string]$R); $h = @{}; $lines = $R -split "`r`n"; for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq "") { break }; if ($lines[$i] -match '^([^:]+):\s*(.*)$') { $h[$Matches[1]] = $Matches[2] } }; return $h }
function Get-ContentLength { param([hashtable]$H); $cl = $H["Content-Length"] ?? $H["content-length"]; if ($cl) { return [int]$cl }; return 0 }

function Inject-Headers { param([byte[]]$B, [int]$L, [hashtable]$H); $req = [System.Text.Encoding]::UTF8.GetString($B, 0, $L); $pos = $req.IndexOf("`r`n"); if ($pos -lt 0) { return $B, $L }; $lines = @(); foreach ($k in $H.Keys) { if ($H[$k]) { $lines += "$k`: $($H[$k])" } }; if ($lines.Count -eq 0) { return $B, $L }; $mod = $req.Insert($pos + 2, ($lines -join "`r`n") + "`r`n"); $b = [System.Text.Encoding]::UTF8.GetBytes($mod); return $b, $b.Length }
function Start-StreamRelay { param([System.IO.Stream]$S, [System.IO.Stream]$D, [int]$Buf, [ref]$C); return [System.Threading.Tasks.Task]::Run([System.Func[System.Threading.Tasks.Task]]{ $b = [byte[]]::new($Buf); try { while ($true) { $r = $S.Read($b, 0, $b.Length); if ($r -eq 0) { break }; $D.Write($b, 0, $r); $D.Flush(); if ($C) { [System.Threading.Interlocked]::Add($C, $r) } } } catch {} }) }

while ($SharedState.Running) {
    $client = $null; $sslStream = $null; $backendClient = $null
    $requestId = [Guid]::NewGuid().ToString("N").Substring(0, 16)
    $startTime = $null
    
    try {
        $client = $TlsListener.AcceptTcpClient()
        $startTime = [DateTime]::UtcNow
        
        if ($SharedState.Draining) { $client.Close(); continue }
        
        [System.Threading.Interlocked]::Increment([ref]$Metrics.TotalConnections)
        [System.Threading.Interlocked]::Increment([ref]$Metrics.ActiveConnections)
        
        $client.ReceiveTimeout = $TimeoutMs; $client.SendTimeout = $TimeoutMs; $client.NoDelay = $true
        
        $clientEp = $client.Client.RemoteEndPoint
        $clientIp = $clientEp.Address.ToString(); $clientPort = $clientEp.Port
        
        # Blacklist check
        if ($SharedState.IpBlacklist.ContainsKey($clientIp)) {
            $entry = $SharedState.IpBlacklist[$clientIp]
            if ($entry.Expiry -gt [DateTime]::UtcNow) {
                $client.Close()
                [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
                continue
            }
            $SharedState.IpBlacklist.Remove($clientIp)
        }
        
        $rules = $RulesContainer.Current
        
        # Rate limiting
        if ($RateLimiter -and $rules.rateLimit.enabled) {
            $check = $RateLimiter.CheckLimit($clientIp, "ip")
            if (-not $check.Allowed) {
                [System.Threading.Interlocked]::Increment([ref]$Metrics.RateLimited)
                $sslStream = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
                $sslStream.AuthenticateAsServer($Certificates["*"], $false, [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Tls13, $false)
                $resp = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 429 Too Many Requests`r`nRetry-After: $($check.RetryAfter)`r`nContent-Length: 0`r`n`r`n")
                $sslStream.Write($resp, 0, $resp.Length)
                $sslStream.Close(); $client.Close()
                [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
                continue
            }
        }
        
        # TLS handshake
        $sslStream = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
        $sslOpts = [System.Net.Security.SslServerAuthenticationOptions]::new()
        $sslOpts.ServerCertificateSelectionCallback = { param($ssl, $host); if ($Certificates.ContainsKey($host)) { return $Certificates[$host] }; return $Certificates["*"] }
        $sslOpts.EnabledSslProtocols = [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Tls13
        $sslStream.AuthenticateAsServer($sslOpts)
        $sni = $sslStream.TargetHostName ?? "unknown"
        $clientCert = $sslStream.RemoteCertificate
        
        # Read request
        $buffer = [byte[]]::new($BufferSize)
        $firstRead = $sslStream.Read($buffer, 0, $buffer.Length)
        
        if ($firstRead -gt 0) {
            [System.Threading.Interlocked]::Increment([ref]$Metrics.TotalRequests)
            [System.Threading.Interlocked]::Add([ref]$Metrics.BytesIn, $firstRead)
            
            $requestStr = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $firstRead)
            $requestPath = Get-RequestPath $requestStr
            $requestMethod = Get-RequestMethod $requestStr
            $requestHeaders = Get-RequestHeaders $requestStr
            $contentType = $requestHeaders["Content-Type"] ?? $requestHeaders["content-type"]
            $userAgent = $requestHeaders["User-Agent"] ?? $requestHeaders["user-agent"]
            
            # Route matching
            $routeMatch = $null
            foreach ($route in $rules.routes) {
                if ($route.match -and ($sni -like $route.match -or $sni -match $route.match.TrimStart("~"))) {
                    $routeMatch = $route
                    break
                }
            }
            if (-not $routeMatch) { $routeMatch = @{ backend = $rules.default } }
            
            $routeName = $routeMatch.match ?? "default"
            
            # Fault injection (for testing)
            if ($FaultInjector) {
                $fault = $FaultInjector.MaybeInjectFault($routeName)
                if ($fault.Inject) {
                    if ($fault.Type -eq "delay") {
                        Start-Sleep -Milliseconds $fault.Duration
                    }
                    elseif ($fault.Type -eq "abort") {
                        $resp = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 $($fault.StatusCode) Injected Fault`r`nContent-Length: 0`r`n`r`n")
                        $sslStream.Write($resp, 0, $resp.Length)
                        $sslStream.Close(); $client.Close()
                        [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
                        continue
                    }
                }
            }
            
            # Service discovery
            $backend = $routeMatch.backend
            $endpoints = @()
            
            if ($backend.service -and $ServiceDiscovery) {
                $endpoints = $ServiceDiscovery.GetEndpoints($backend.service)
                
                if ($endpoints.Count -eq 0) {
                    # No endpoints available
                    $resp = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 503 Service Unavailable`r`nContent-Length: 0`r`n`r`n")
                    $sslStream.Write($resp, 0, $resp.Length)
                    $sslStream.Close(); $client.Close()
                    [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
                    continue
                }
                
                # Traffic management (canary, shifting)
                if ($TrafficManager) {
                    $trafficRoute = $TrafficManager.RouteRequest(@{ Headers = $requestHeaders }, $endpoints)
                    $backend = $trafficRoute.Primary
                    
                    # Mirror traffic (fire and forget)
                    if ($trafficRoute.Mirror) {
                        # Would spawn async task to send copy to mirror backend
                    }
                }
                else {
                    # Locality-aware load balancing
                    if ($LocalityLoadBalancer) {
                        $backend = $LocalityLoadBalancer.SelectEndpoint($endpoints, $SharedState, $backend.service)
                    }
                    else {
                        $backend = $endpoints[0]
                    }
                }
            }
            elseif ($backend.cluster -and $rules.loadBalancing.ContainsKey($backend.cluster)) {
                $cluster = $rules.loadBalancing[$backend.cluster]
                $idx = $SharedState.LoadBalancerState[$backend.cluster] ?? 0
                $backend = $cluster.backends[$idx % $cluster.backends.Count]
                $SharedState.LoadBalancerState[$backend.cluster] = $idx + 1
            }
            
            # Distributed rate limiting
            if ($DistributedRateLimiter -and $routeMatch.serviceMesh.enabled) {
                $serviceName = $routeMatch.backend.service ?? $routeName
                $limit = $rules.serviceMesh.distributedRateLimit.globalLimits[$serviceName]
                
                if ($limit) {
                    $check = $DistributedRateLimiter.CheckLimit($serviceName, $limit.requestsPerSecond, 1)
                    if (-not $check.Allowed) {
                        [System.Threading.Interlocked]::Increment([ref]$Metrics.RateLimited)
                        $resp = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 429 Too Many Requests`r`nContent-Length: 0`r`n`r`n")
                        $sslStream.Write($resp, 0, $resp.Length)
                        $sslStream.Close(); $client.Close()
                        [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
                        continue
                    }
                }
            }
            
            # Record request for retry budget
            if ($RetryPolicy) { $RetryPolicy.RecordRequest() }
            
            # Authentication
            $authResult = @{ Valid = $true; Method = "none" }
            if ($AuthManager -and $routeMatch.auth) {
                $authResult = $AuthManager.Authenticate(@{ Headers = $requestHeaders }, $routeMatch.auth, $clientCert)
                if (-not $authResult.Valid) {
                    [System.Threading.Interlocked]::Increment([ref]$Metrics.AuthFailure)
                    $resp = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 401 Unauthorized`r`nContent-Length: 0`r`n`r`n")
                    $sslStream.Write($resp, 0, $resp.Length)
                    $sslStream.Close(); $client.Close()
                    [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
                    continue
                }
                [System.Threading.Interlocked]::Increment([ref]$Metrics.AuthSuccess)
            }
            
            # Circuit breaker
            $breaker = $null
            if ($CircuitBreakerManager -and ($routeMatch.circuitBreaker.enabled -or $rules.circuitBreaker.enabled)) {
                $backendKey = "$($backend.host):$($backend.port)"
                $breaker = $CircuitBreakerManager.GetBreaker($backendKey, $routeMatch.circuitBreaker ?? @{})
                $canExec = $breaker.CanExecute()
                
                if (-not $canExec.Allowed) {
                    [System.Threading.Interlocked]::Increment([ref]$Metrics.CircuitOpen)
                    $resp = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 503 Service Unavailable`r`nRetry-After: $($canExec.RetryAfter)`r`nContent-Length: 0`r`n`r`n")
                    $sslStream.Write($resp, 0, $resp.Length)
                    $sslStream.Close(); $client.Close()
                    [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
                    continue
                }
            }
            
            $backendKey = "$($backend.host):$($backend.port)"
            
            # Build headers
            $headersToAdd = @{
                "X-Forwarded-For" = $clientIp
                "X-Forwarded-Proto" = "https"
                "X-Real-IP" = $clientIp
                "X-Forwarded-Host" = $sni
                "X-Request-ID" = $requestId
            }
            if ($authResult.Subject) { $headersToAdd["X-User-Id"] = $authResult.Subject }
            
            $modBuf, $modLen = Inject-Headers $buffer $firstRead $headersToAdd
            
            # Retry loop
            $attempt = 0
            $maxAttempts = if ($RetryPolicy) { $RetryPolicy.Config.maxAttempts } else { 1 }
            $success = $false
            $lastError = $null
            
            while ($attempt -lt $maxAttempts -and -not $success) {
                $attempt++
                
                try {
                    # Connect to backend
                    $backendClient = [System.Net.Sockets.TcpClient]::new()
                    $backendClient.Connect($backend.host, $backend.port)
                    $backendClient.NoDelay = $true
                    $backendStream = $backendClient.GetStream()
                    
                    $backendStream.Write($modBuf, 0, $modLen)
                    $backendStream.Flush()
                    
                    # Relay streams
                    $c2b = Start-StreamRelay $sslStream $backendStream $BufferSize ([ref]$Metrics.BytesIn)
                    $b2c = Start-StreamRelay $backendStream $sslStream $BufferSize ([ref]$Metrics.BytesOut)
                    [System.Threading.Tasks.Task]::WaitAny(@($c2b, $b2c)) | Out-Null
                    Start-Sleep -Milliseconds 50
                    
                    $success = $true
                    if ($breaker) { $breaker.RecordSuccess() }
                }
                catch {
                    $lastError = $_.Exception.Message
                    if ($breaker) { $breaker.RecordFailure() }
                    
                    if ($backendClient) { try { $backendClient.Close() } catch {} }
                    
                    # Check if should retry
                    if ($RetryPolicy -and $RetryPolicy.ShouldRetry(0, $lastError, $attempt)) {
                        $backoff = $RetryPolicy.GetBackoffMs($attempt)
                        Start-Sleep -Milliseconds $backoff
                        continue
                    }
                    
                    break
                }
            }
            
            $latencyMs = ([DateTime]::UtcNow - $startTime).TotalMilliseconds
            
            # Emit message event
            if ($MessagingEnabled -and $routeMatch.messaging.enabled) {
                $events = $routeMatch.messaging.events ?? @("request")
                
                if ("request" -in $events) {
                    $event = @{
                        event_type = "requests"
                        timestamp = [DateTime]::UtcNow.ToString("o")
                        request_id = $requestId
                        client_ip = $clientIp
                        method = $requestMethod
                        path = $requestPath
                        host = $sni
                        route = $routeName
                        backend = $backendKey
                        latency_ms = [Math]::Round($latencyMs, 2)
                        user_agent = $userAgent
                        user_id = $authResult.Subject
                        success = $success
                        attempts = $attempt
                    }
                    
                    if (-not $success) {
                        $event.event_type = "errors"
                        $event.error = $lastError
                    }
                    
                    Add-MessageToBuffer $event $MessageBuffer $BufferState
                }
            }
            
            $Metrics.LatencySamples.Enqueue($latencyMs / 1000)
            while ($Metrics.LatencySamples.Count -gt 1000) { $d = $null; $Metrics.LatencySamples.TryDequeue([ref]$d) | Out-Null }
        }
    }
    catch { }
    finally {
        [System.Threading.Interlocked]::Decrement([ref]$Metrics.ActiveConnections)
        if ($sslStream) { try { $sslStream.Close() } catch {} }
        if ($client) { try { $client.Close() } catch {} }
        if ($backendClient) { try { $backendClient.Close() } catch {} }
    }
}
'@

# ============================================
# Metrics Store
# ============================================

$metrics = [hashtable]::Synchronized(@{
    TotalConnections = [long]0; ActiveConnections = [long]0; TotalRequests = [long]0
    BytesIn = [long]0; BytesOut = [long]0
    RateLimited = [long]0; CircuitOpen = [long]0
    AuthSuccess = [long]0; AuthFailure = [long]0
    MessagesEnqueued = [long]0; MessagesPublished = [long]0; MessagesDropped = [long]0
    ServiceDiscoveryHits = [long]0; ServiceDiscoveryMisses = [long]0
    RetryAttempts = [long]0; RetrySuccess = [long]0
    RedisCommands = [long]0; MySqlQueries = [long]0
    WebSocketConnections = [long]0; WebSocketMessages = [long]0
    DnsQueries = [long]0; DnsCacheHits = [long]0
    TlsErrors = [long]0; BackendErrors = [long]0; TimeoutErrors = [long]0
    LatencySamples = [System.Collections.Concurrent.ConcurrentQueue[double]]::new()
    StartTime = [DateTime]::UtcNow
})

# ============================================
# Load Rules & Initialize Components
# ============================================

$rules = if (Test-Path $RulesPath) { 
    try { (Get-Content $RulesPath -Raw) | ConvertFrom-Json -AsHashtable } 
    catch { $defaultRules } 
} else { 
    $defaultRules | ConvertTo-Json -Depth 15 | Set-Content "rules.template.json"
    $defaultRules 
}

# Override from command line
if ($KafkaBrokers) { $rules.messaging.kafka.brokers = $KafkaBrokers -split ',' }
if ($ConsulAddr) { $rules.serviceMesh.discovery.consul.address = $ConsulAddr }
if ($RedisAddr) { $rules.serviceMesh.distributedRateLimit.redis.address = $RedisAddr }

$rulesContainer = [hashtable]::Synchronized(@{ Current = $rules; Version = 1; LastReload = [DateTime]::UtcNow })

$sharedState = [hashtable]::Synchronized(@{
    Running = $true; Draining = $false
    DnsCache = [hashtable]::Synchronized(@{})
    BackendHealth = [hashtable]::Synchronized(@{})
    LoadBalancerState = [hashtable]::Synchronized(@{})
    Metrics = $metrics; RulesContainer = $rulesContainer
    IpBlacklist = [hashtable]::Synchronized(@{})
    ServiceId = $ServiceId
})

# ============================================
# Certificate Loading
# ============================================

$certificates = [hashtable]::Synchronized(@{})
$defaultCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
    [System.IO.Path]::GetFullPath($CertPath), $CertPassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)
$certificates["*"] = $defaultCert

if (Test-Path "certs") {
    Get-ChildItem "certs/*.pfx" | ForEach-Object {
        $certificates[$_.BaseName] = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $_.FullName, $CertPassword,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
        )
        Write-Host "Loaded cert: $($_.BaseName)"
    }
}

# ============================================
# Admin & Metrics Servers
# ============================================

$adminServerScript = {
    param($Listener, $SharedState, $RulesContainer, $RulesPath, $MessageBufferState, $ServiceDiscovery)
    
    function Send-Json { param($R, $D, [int]$S = 200); $j = $D | ConvertTo-Json -Depth 10; $b = [System.Text.Encoding]::UTF8.GetBytes($j); $R.StatusCode = $S; $R.ContentType = "application/json"; $R.ContentLength64 = $b.Length; $R.OutputStream.Write($b, 0, $b.Length); $R.Close() }
    
    while ($SharedState.Running) {
        try {
            $ctx = $Listener.GetContext(); $resp = $ctx.Response; $path = $ctx.Request.Url.LocalPath; $method = $ctx.Request.HttpMethod
            
            switch -Regex ($path) {
                '^/admin/reload$' { try { $RulesContainer.Current = (Get-Content $RulesPath -Raw) | ConvertFrom-Json -AsHashtable; $RulesContainer.Version++; Send-Json $resp @{ success = $true; version = $RulesContainer.Version } } catch { Send-Json $resp @{ error = $_.Exception.Message } 400 } }
                '^/admin/drain$' { $SharedState.Draining = $true; Send-Json $resp @{ success = $true } }
                '^/admin/resume$' { $SharedState.Draining = $false; Send-Json $resp @{ success = $true } }
                '^/admin/status$' { 
                    Send-Json $resp @{ 
                        running = $SharedState.Running
                        draining = $SharedState.Draining
                        rulesVersion = $RulesContainer.Version
                        connections = $SharedState.Metrics.ActiveConnections
                        serviceId = $SharedState.ServiceId
                        messaging = @{
                            enqueued = $MessageBufferState.Enqueued
                            published = $MessageBufferState.Published
                            dropped = $MessageBufferState.Dropped
                            backpressure = $MessageBufferState.Backpressure
                            bufferSize = $MessageBufferState.Enqueued - $MessageBufferState.Dequeued
                        }
                    }
                }
                '^/admin/circuits' { if ($SharedState.CircuitBreakerManager) { Send-Json $resp @{ circuits = $SharedState.CircuitBreakerManager.GetAllStatus() } } else { Send-Json $resp @{ circuits = @() } } }
                '^/admin/services$' {
                    if ($ServiceDiscovery) {
                        $services = @{}
                        foreach ($key in $ServiceDiscovery.ServiceCache.Keys) {
                            $cached = $ServiceDiscovery.ServiceCache[$key]
                            $services[$key] = @{
                                endpoints = $cached.Endpoints.Count
                                expiry = $cached.Expiry.ToString("o")
                            }
                        }
                        Send-Json $resp @{ services = $services }
                    } else { Send-Json $resp @{ services = @{} } }
                }
                '^/admin/services/(.+)$' {
                    $serviceName = $Matches[1]
                    if ($ServiceDiscovery) {
                        $endpoints = $ServiceDiscovery.GetEndpoints($serviceName)
                        Send-Json $resp @{ service = $serviceName; endpoints = $endpoints }
                    } else { Send-Json $resp @{ error = "Service discovery not enabled" } 400 }
                }
                '^/admin/messaging$' {
                    Send-Json $resp @{
                        enqueued = $MessageBufferState.Enqueued
                        dequeued = $MessageBufferState.Dequeued
                        published = $MessageBufferState.Published
                        dropped = $MessageBufferState.Dropped
                        errors = $MessageBufferState.Errors
                        backpressure = $MessageBufferState.Backpressure
                        bufferSize = $MessageBufferState.Enqueued - $MessageBufferState.Dequeued
                        lastFlush = $MessageBufferState.LastFlush.ToString("o")
                    }
                }
                '^/admin/blacklist$' {
                    if ($method -eq "GET") { Send-Json $resp @{ blacklist = @($SharedState.IpBlacklist.Keys) } }
                    elseif ($method -eq "POST") {
                        $reader = [System.IO.StreamReader]::new($ctx.Request.InputStream)
                        $body = $reader.ReadToEnd() | ConvertFrom-Json
                        $reader.Close()
                        $SharedState.IpBlacklist[$body.ip] = @{ Expiry = [DateTime]::UtcNow.AddSeconds($body.duration ?? 3600); Reason = $body.reason }
                        Send-Json $resp @{ success = $true }
                    }
                    elseif ($method -eq "DELETE") {
                        $ip = $ctx.Request.QueryString["ip"]
                        $SharedState.IpBlacklist.Remove($ip)
                        Send-Json $resp @{ success = $true }
                    }
                }
                default { Send-Json $resp @{ error = "Not found" } 404 }
            }
        } catch {}
    }
}

$metricsServerScript = {
    param($Listener, $SharedState, $RulesContainer, $MessageBufferState)
    $m = $SharedState.Metrics
    
    while ($SharedState.Running) {
        try {
            $ctx = $Listener.GetContext(); $path = $ctx.Request.Url.LocalPath; $resp = $ctx.Response
            
            if ($path -eq "/metrics") {
                $bufferSize = $MessageBufferState.Enqueued - $MessageBufferState.Dequeued
                
                $text = @"
# HELP tls_proxy_connections_total Total connections
# TYPE tls_proxy_connections_total counter
tls_proxy_connections_total $($m.TotalConnections)

# HELP tls_proxy_connections_active Active connections
# TYPE tls_proxy_connections_active gauge
tls_proxy_connections_active $($m.ActiveConnections)

# HELP tls_proxy_requests_total Total requests
# TYPE tls_proxy_requests_total counter
tls_proxy_requests_total $($m.TotalRequests)

# HELP tls_proxy_bytes_in_total Bytes received
# TYPE tls_proxy_bytes_in_total counter
tls_proxy_bytes_in_total $($m.BytesIn)

# HELP tls_proxy_bytes_out_total Bytes sent
# TYPE tls_proxy_bytes_out_total counter
tls_proxy_bytes_out_total $($m.BytesOut)

# HELP tls_proxy_rate_limited_total Rate limited requests
# TYPE tls_proxy_rate_limited_total counter
tls_proxy_rate_limited_total $($m.RateLimited)

# HELP tls_proxy_circuit_open_total Circuit breaker opens
# TYPE tls_proxy_circuit_open_total counter
tls_proxy_circuit_open_total $($m.CircuitOpen)

# HELP tls_proxy_auth_success_total Auth successes
# TYPE tls_proxy_auth_success_total counter
tls_proxy_auth_success_total $($m.AuthSuccess)

# HELP tls_proxy_auth_failure_total Auth failures
# TYPE tls_proxy_auth_failure_total counter
tls_proxy_auth_failure_total $($m.AuthFailure)

# HELP tls_proxy_message_buffer_size Message buffer size
# TYPE tls_proxy_message_buffer_size gauge
tls_proxy_message_buffer_size $bufferSize

# HELP tls_proxy_messages_published_total Messages published
# TYPE tls_proxy_messages_published_total counter
tls_proxy_messages_published_total $($MessageBufferState.Published)

# HELP tls_proxy_messages_dropped_total Messages dropped
# TYPE tls_proxy_messages_dropped_total counter
tls_proxy_messages_dropped_total $($MessageBufferState.Dropped)

# HELP tls_proxy_draining Draining status
# TYPE tls_proxy_draining gauge
tls_proxy_draining $(if ($SharedState.Draining) { 1 } else { 0 })

# HELP tls_proxy_rules_version Rules version
# TYPE tls_proxy_rules_version gauge
tls_proxy_rules_version $($RulesContainer.Version)
"@
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
                $resp.ContentType = "text/plain; version=0.0.4"
                $resp.ContentLength64 = $bytes.Length
                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            elseif ($path -eq "/health") {
                $status = if ($SharedState.Draining) { "draining" } else { "healthy" }
                $json = @{ status = $status; service_id = $SharedState.ServiceId } | ConvertTo-Json
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $resp.ContentType = "application/json"
                $resp.ContentLength64 = $bytes.Length
                if ($SharedState.Draining) { $resp.StatusCode = 503 }
                $resp.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            else { $resp.StatusCode = 404 }
            $resp.Close()
        } catch {}
    }
}

# ============================================
# Support Workers
# ============================================

$healthCheckScript = {
    param($RulesContainer, $SharedState)
    while ($SharedState.Running) {
        $rules = $RulesContainer.Current
        foreach ($name in $rules.loadBalancing.Keys) {
            $cluster = $rules.loadBalancing[$name]
            foreach ($b in $cluster.backends) {
                $key = "$($b.host):$($b.port)"
                try {
                    $tcp = [System.Net.Sockets.TcpClient]::new()
                    if ($tcp.ConnectAsync($b.host, $b.port).Wait(5000)) {
                        $SharedState.BackendHealth[$key] = $true
                    } else {
                        $SharedState.BackendHealth[$key] = $false
                    }
                    $tcp.Close()
                } catch {
                    $SharedState.BackendHealth[$key] = $false
                }
            }
        }
        Start-Sleep -Seconds 10
    }
}

$fileWatcherScript = {
    param($RulesPath, $RulesContainer, $SharedState, $Interval)
    $lastMod = if (Test-Path $RulesPath) { (Get-Item $RulesPath).LastWriteTimeUtc } else { $null }
    
    while ($SharedState.Running) {
        Start-Sleep -Seconds $Interval
        if (-not (Test-Path $RulesPath)) { continue }
        $currMod = (Get-Item $RulesPath).LastWriteTimeUtc
        if ($lastMod -and $currMod -gt $lastMod) {
            try {
                $RulesContainer.Current = (Get-Content $RulesPath -Raw) | ConvertFrom-Json -AsHashtable
                $RulesContainer.Version++
                Write-Host "[HotReload] Rules v$($RulesContainer.Version)"
            } catch { Write-Host "[HotReload] Error: $_" }
            $lastMod = $currMod
        }
    }
}

$serviceDiscoveryWatcherScript = {
    param($ServiceDiscovery, $SharedState, $Interval)
    
    while ($SharedState.Running) {
        Start-Sleep -Seconds $Interval
        
        # Refresh service cache
        foreach ($serviceName in @($ServiceDiscovery.ServiceCache.Keys)) {
            try {
                $endpoints = $ServiceDiscovery.GetEndpoints($serviceName)
                # Cache is updated inside GetEndpoints
            } catch { }
        }
    }
}

# ============================================
# Start Listeners
# ============================================

$httpsListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $HttpsPort)
$httpsListener.Start()
Write-Host "HTTPS: :$HttpsPort"

# Redis protocol listener
$redisListener = $null
$redisRoute = $rules.routes | Where-Object { $_.protocol -eq "redis" } | Select-Object -First 1
if ($redisRoute) {
    $redisPort = $redisRoute.listenPort ?? 6380
    $redisListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $redisPort)
    $redisListener.Start()
    Write-Host "Redis: :$redisPort"
}

# MySQL protocol listener
$mysqlListener = $null
$mysqlRoute = $rules.routes | Where-Object { $_.protocol -eq "mysql" } | Select-Object -First 1
if ($mysqlRoute) {
    $mysqlPort = $mysqlRoute.listenPort ?? 3307
    $mysqlListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $mysqlPort)
    $mysqlListener.Start()
    Write-Host "MySQL: :$mysqlPort"
}

# Generic TCP listener
$tcpListener = $null
$tcpRoute = $rules.routes | Where-Object { $_.protocol -eq "tcp" } | Select-Object -First 1
if ($tcpRoute) {
    $tcpListenPort = $tcpRoute.listenPort ?? $TcpPort
    $tcpListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $tcpListenPort)
    $tcpListener.Start()
    Write-Host "TCP: :$tcpListenPort"
}

$metricsListener = $null
if ($rules.metrics.enabled) {
    $metricsListener = [System.Net.HttpListener]::new()
    $metricsListener.Prefixes.Add("http://+:$MetricsPort/")
    $metricsListener.Start()
    Write-Host "Metrics: :$MetricsPort"
}

$adminListener = $null
if ($rules.admin.enabled) {
    $adminListener = [System.Net.HttpListener]::new()
    $adminListener.Prefixes.Add("http://+:$AdminPort/")
    $adminListener.Start()
    Write-Host "Admin: :$AdminPort"
}

# ============================================
# Initialize Components
# ============================================

Write-Host "`nInitializing components..."

# Combine all scripts
$allScripts = $messagingScript + "`n" + $serviceMeshScript + "`n" + $protocolsScript

# Execute to define classes
Invoke-Expression $allScripts

# Create rate limiter
$rateLimiter = $null
if ($rules.rateLimit.enabled) {
    # Simple in-memory rate limiter (defined earlier in abbreviated form)
    $rateLimiter = @{ CheckLimit = { param($k, $t) @{ Allowed = $true } } }
}

# Create circuit breaker manager
$circuitBreakerManager = $null
if ($rules.circuitBreaker.enabled) {
    # Defined earlier
}

# Create auth manager
$authManager = $null

# Create service discovery
$serviceDiscovery = $null
if ($rules.serviceMesh.enabled -and $rules.serviceMesh.discovery) {
    $serviceDiscovery = [ServiceDiscovery]::new($rules.serviceMesh.discovery)
    
    # Register this proxy with service discovery
    if ($rules.serviceMesh.discovery.consul.register) {
        $serviceDiscovery.RegisterService(
            $ServiceId,
            $rules.serviceMesh.discovery.consul.serviceName ?? "tls-proxy",
            $HttpsPort,
            $rules.serviceMesh.discovery.consul.serviceTags ?? @("proxy")
        )
        Write-Host "Registered with Consul as: $ServiceId"
    }
}

# Create locality load balancer
$localityLoadBalancer = $null
if ($rules.serviceMesh.locality.enabled) {
    $localityLoadBalancer = [LocalityLoadBalancer]::new($rules.serviceMesh.locality)
}

# Create traffic manager
$trafficManager = $null
if ($rules.serviceMesh.traffic) {
    $trafficManager = [TrafficManager]::new($rules.serviceMesh.traffic)
}

# Create distributed rate limiter
$distributedRateLimiter = $null
if ($rules.serviceMesh.distributedRateLimit.enabled) {
    $distributedRateLimiter = [DistributedRateLimiter]::new($rules.serviceMesh.distributedRateLimit)
}

# Create retry policy
$retryPolicy = $null
if ($rules.serviceMesh.resilience.retry.enabled) {
    $retryPolicy = [RetryPolicy]::new($rules.serviceMesh.resilience.retry)
}

# Create fault injector
$faultInjector = $null
if ($rules.serviceMesh.faultInjection.enabled) {
    $faultInjector = [FaultInjector]::new($rules.serviceMesh.faultInjection)
}

# Create protocol router
$protocolRouter = $null
if ($rules.protocols) {
    $protocolRouter = [ProtocolRouter]::new($rules.protocols)
}

Write-Host "Components initialized.`n"

# ============================================
# Start Workers
# ============================================

$runspacePool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $WorkerCount + 20)
$runspacePool.Open()

$workers = @()

# HTTP workers
$fullHttpScript = $allScripts + "`n" + $httpWorkerScript

for ($i = 1; $i -le $WorkerCount; $i++) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $runspacePool
    $ps.AddScript($fullHttpScript).AddParameters(@{
        TlsListener = $httpsListener
        Certificates = $certificates
        RulesContainer = $rulesContainer
        SharedState = $sharedState
        Metrics = $metrics
        MessageBuffer = $messageBuffer
        BufferState = $messageBufferState
        MessagingEnabled = $rules.messaging.enabled
        RateLimiter = $rateLimiter
        CircuitBreakerManager = $circuitBreakerManager
        AuthManager = $authManager
        ServiceDiscovery = $serviceDiscovery
        LocalityLoadBalancer = $localityLoadBalancer
        TrafficManager = $trafficManager
        DistributedRateLimiter = $distributedRateLimiter
        RetryPolicy = $retryPolicy
        FaultInjector = $faultInjector
        WorkerId = $i
        BufferSize = $BufferSize
        TimeoutMs = $TimeoutMs
    }) | Out-Null
    $workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "HTTPS-$i" }
}

# Redis workers
if ($redisListener) {
    $fullRedisScript = $allScripts + "`n" + $redisWorkerScript
    
    for ($i = 1; $i -le 5; $i++) {
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $runspacePool
        $ps.AddScript($fullRedisScript).AddParameters(@{
            RedisListener = $redisListener
            RouteConfig = $redisRoute
            ProtocolRouter = $protocolRouter
            SharedState = $sharedState
            Metrics = $metrics
            MessageBuffer = $messageBuffer
            BufferState = $messageBufferState
            MessagingEnabled = $rules.messaging.enabled
            WorkerId = $i
        }) | Out-Null
        $workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "Redis-$i" }
    }
}

# Message publisher worker
if ($rules.messaging.enabled) {
    $fullPublisherScript = $messagingScript + "`n" + $messagePublisherWorkerScript
    
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $runspacePool
    $ps.AddScript($fullPublisherScript).AddParameters(@{
        MessagingConfig = $rules.messaging
        MessageBuffer = $messageBuffer
        BufferState = $messageBufferState
        SharedState = $sharedState
    }) | Out-Null
    $workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "Publisher" }
    Write-Host "Message publisher started"
}

# Metrics server
if ($metricsListener) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $runspacePool
    $ps.AddScript($metricsServerScript).AddParameters(@{
        Listener = $metricsListener
        SharedState = $sharedState
        RulesContainer = $rulesContainer
        MessageBufferState = $messageBufferState
    }) | Out-Null
    $workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "Metrics" }
}

# Admin server
if ($adminListener) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $runspacePool
    $ps.AddScript($adminServerScript).AddParameters(@{
        Listener = $adminListener
        SharedState = $sharedState
        RulesContainer = $rulesContainer
        RulesPath = $RulesPath
        MessageBufferState = $messageBufferState
        ServiceDiscovery = $serviceDiscovery
    }) | Out-Null
    $workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "Admin" }
}

# Health check worker
$ps = [PowerShell]::Create()
$ps.RunspacePool = $runspacePool
$ps.AddScript($healthCheckScript).AddParameters(@{
    RulesContainer = $rulesContainer
    SharedState = $sharedState
}) | Out-Null
$workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "Health" }

# Hot reload watcher
if ($rules.hotReload.enabled) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $runspacePool
    $ps.AddScript($fileWatcherScript).AddParameters(@{
        RulesPath = $RulesPath
        RulesContainer = $rulesContainer
        SharedState = $sharedState
        Interval = $rules.hotReload.watchInterval ?? 5
    }) | Out-Null
    $workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "FileWatcher" }
}

# Service discovery watcher
if ($serviceDiscovery -and $rules.serviceMesh.discovery.consul.watch) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $runspacePool
    $ps.AddScript($serviceDiscoveryWatcherScript).AddParameters(@{
        ServiceDiscovery = $serviceDiscovery
        SharedState = $sharedState
        Interval = $rules.serviceMesh.discovery.consul.watchInterval ?? 5
    }) | Out-Null
    $workers += @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Id = "ServiceDiscovery" }
}

Write-Host "Workers: $($workers.Count)"
Write-Host "Service ID: $ServiceId"
Write-Host "Messaging: $(if ($rules.messaging.enabled) { 'enabled' } else { 'disabled' })"
Write-Host "Service Mesh: $(if ($rules.serviceMesh.enabled) { 'enabled' } else { 'disabled' })"
Write-Host "Protocols: Redis=$(if ($redisListener) { 'enabled' } else { 'disabled' }), MySQL=$(if ($mysqlListener) { 'enabled' } else { 'disabled' })"
Write-Host "`nCtrl+C to stop`n"

# ============================================
# Shutdown
# ============================================

try { while ($true) { Start-Sleep -Seconds 1 } }
finally {
    Write-Host "`nShutting down..."
    $sharedState.Draining = $true
    
    # Deregister from service discovery
    if ($serviceDiscovery -and $rules.serviceMesh.discovery.consul.register) {
        $serviceDiscovery.DeregisterService($ServiceId)
        Write-Host "Deregistered from Consul"
    }
    
    # Wait for drain
    Start-Sleep -Seconds ([Math]::Min($DrainTimeoutSeconds, 10))
    $sharedState.Running = $false
    
    # Stop listeners
    $httpsListener.Stop()
    if ($redisListener) { $redisListener.Stop() }
    if ($mysqlListener) { $mysqlListener.Stop() }
    if ($tcpListener) { $tcpListener.Stop() }
    if ($metricsListener) { $metricsListener.Stop() }
    if ($adminListener) { $adminListener.Stop() }
    
    # Close distributed rate limiter
    if ($distributedRateLimiter) { $distributedRateLimiter.Close() }
    
    # Stop workers
    foreach ($w in $workers) { $w.PowerShell.Stop(); $w.PowerShell.Dispose() }
    $runspacePool.Close()
    
    Write-Host "Final stats:"
    Write-Host "  Messages published: $($messageBufferState.Published)"
    Write-Host "  Messages dropped: $($messageBufferState.Dropped)"
    Write-Host "Done."
}