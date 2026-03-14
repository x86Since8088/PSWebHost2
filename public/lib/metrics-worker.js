/**
 * metrics-worker.js - DuckDB-WASM Web Worker for metrics storage
 *
 * Runs DuckDB-WASM in a dedicated worker thread for non-blocking
 * database operations. Uses OPFS for persistent storage when available.
 *
 * Performance target: 100x improvement over sql.js
 * - Insert 1000 rows: 5ms (vs 500ms)
 * - Query 1h window: 2ms (vs 200ms)
 * - Downsample: 1ms (vs 100ms)
 */

// Import DuckDB-WASM and Apache Arrow with retry logic
// Try local copies first (installed via NPM), fallback to CDN with exponential backoff

/**
 * Load script with retry logic and exponential backoff
 * @param {string[]} urls - Array of URLs to try (local first, CDN as fallback)
 * @param {string} scriptName - Name for logging
 * @returns {Promise<void>}
 */
async function loadScriptWithRetry(urls, scriptName) {
    const delays = [1000, 1000, 5000, 10000, 30000]; // 1s, 1s, 5s, 10s, 30s
    let lastError = null;

    for (let urlIndex = 0; urlIndex < urls.length; urlIndex++) {
        const url = urls[urlIndex];
        const isLocal = url.startsWith('/');
        const isCDN = url.includes('cdn.jsdelivr.net');

        console.log(`[Worker] Attempting to load ${scriptName} from ${isLocal ? 'local' : 'CDN'}: ${url}`);

        for (let attempt = 0; attempt < delays.length; attempt++) {
            try {
                // Use synchronous importScripts in worker context
                importScripts(url);
                console.log(`[Worker] ✓ Successfully loaded ${scriptName} from ${isLocal ? 'local' : 'CDN'}`);
                return; // Success!

            } catch (err) {
                lastError = err;
                const delay = delays[attempt];
                const attemptInfo = `Attempt ${attempt + 1}/${delays.length}`;

                console.warn(`[Worker] ${attemptInfo} failed to load ${scriptName} from ${url}: ${err.message}`);

                // If this is not the last attempt for this URL, retry with delay
                if (attempt < delays.length - 1) {
                    console.log(`[Worker] Retrying ${scriptName} in ${delay}ms...`);
                    await sleep(delay);
                } else if (urlIndex < urls.length - 1) {
                    // Try next URL
                    console.log(`[Worker] Trying next source for ${scriptName}...`);
                    break;
                } else {
                    // Last URL, last attempt - continue with 1-minute retries
                    console.warn(`[Worker] All sources exhausted for ${scriptName}, entering 1-minute retry loop...`);

                    // Continue retrying every minute (non-blocking)
                    let minuteAttempt = 1;
                    while (true) {
                        await sleep(60000); // 1 minute
                        try {
                            importScripts(url);
                            console.log(`[Worker] ✓ Successfully loaded ${scriptName} after ${minuteAttempt} minute(s)`);
                            return;
                        } catch (retryErr) {
                            minuteAttempt++;
                            console.warn(`[Worker] Retry ${minuteAttempt} failed for ${scriptName}: ${retryErr.message}`);
                            // Continue loop
                        }
                    }
                }
            }
        }
    }

    throw new Error(`Failed to load ${scriptName} from all sources: ${lastError?.message}`);
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

// Modern DuckDB-WASM uses ES modules - load via dynamic import with retry
let DUCKDB_LOADED = false;

/**
 * Import with timeout - prevents hanging on unresolvable imports
 * @param {string} url - Module URL to import
 * @param {number} timeoutMs - Timeout in milliseconds
 */
async function importWithTimeout(url, timeoutMs = 10000) {
    return Promise.race([
        import(url),
        new Promise((_, reject) =>
            setTimeout(() => reject(new Error(`Import timeout after ${timeoutMs}ms`)), timeoutMs)
        )
    ]);
}

async function loadDuckDBModule() {
    const delays = [1000, 2000, 5000]; // Reduced retries - fail faster for stub fallback
    const moduleUrls = [
        '/public/lib/duckdb-browser.mjs'  // Local only - CDN has same dependency issue
    ];

    for (const url of moduleUrls) {
        const isLocal = url.startsWith('/');
        console.log(`[Worker] Attempting to load DuckDB module from ${isLocal ? 'local' : 'CDN'}: ${url}`);
        sendProgress(`Loading DuckDB module from ${isLocal ? 'local' : 'CDN'}`, 'module_load');

        for (let attempt = 0; attempt < delays.length; attempt++) {
            try {
                // Dynamic import with timeout - prevents hanging on unresolvable imports
                const module = await importWithTimeout(url, 15000);
                console.log(`[Worker] ✓ Successfully loaded DuckDB module from ${isLocal ? 'local' : 'CDN'}`);
                sendProgress('DuckDB module loaded successfully', 'module_loaded');
                DUCKDB_LOADED = true;
                return module;
            } catch (err) {
                console.warn(`[Worker] Attempt ${attempt + 1}/${delays.length} failed: ${err.message}`);
                sendProgress(`Module load attempt ${attempt + 1} failed: ${err.message}`, 'module_error');

                // Check for fatal errors that won't resolve with retry
                if (err.message.includes('apache-arrow') ||
                    err.message.includes('Module not found') ||
                    err.message.includes('Failed to resolve')) {
                    console.warn('[Worker] Fatal import error detected, skipping remaining retries');
                    sendProgress('Fatal import error - using stub storage', 'module_fatal');
                    throw err; // Exit immediately
                }

                if (attempt < delays.length - 1) {
                    await sleep(delays[attempt]);
                }
            }
        }
    }

    // All attempts failed - throw to trigger stub fallback
    throw new Error('DuckDB module failed to load after all retry attempts');
}

// Helper function to log errors to main thread (for window.logtoserver)
function logErrorToMainThread(error, context = {}) {
    try {
        self.postMessage({
            type: 'WORKER_ERROR_LOG',
            error: {
                message: error.message || String(error),
                stack: error.stack,
                name: error.name,
                context: context,
                timestamp: new Date().toISOString()
            }
        });
    } catch (e) {
        console.error('[Worker] Failed to send error to main thread:', e);
    }
}

// Helper to send progress/status updates to main thread
function sendProgress(message, phase = 'init') {
    try {
        self.postMessage({
            type: 'WORKER_LOG',
            level: 'Info',
            component: 'MetricsWorker',
            message: message,
            context: { phase }
        });
    } catch (e) {
        console.log('[Worker] Progress:', message);
    }
}

// Start loading DuckDB module (non-blocking)
// Track whether module load failed so we can skip retries
let duckdbModuleLoadFailed = false;
let duckdbModulePromise = loadDuckDBModule().catch(err => {
    duckdbModuleLoadFailed = true;
    logErrorToMainThread(err, { phase: 'module_load', location: 'loadDuckDBModule' });
    throw err;
});

let db = null;
let conn = null;
let storageType = 'memory';
let initialized = false;

// Prepared statement cache to prevent memory leaks
const preparedStatements = new Map();

function getPreparedStatement(key, sql) {
    if (!preparedStatements.has(key)) {
        preparedStatements.set(key, conn.prepare(sql));
    }
    return preparedStatements.get(key);
}

function cleanupPreparedStatements() {
    for (const stmt of preparedStatements.values()) {
        try {
            stmt.free();
        } catch (e) {
            console.warn('[Worker] Error freeing statement:', e);
        }
    }
    preparedStatements.clear();
}

// ============ TransactionGuard for Safe Transaction Management ============

// Track high water mark for activeOperations
let activeOperationsHighWaterMark = 0;
let transactionCount = 0;
let transactionTotalDuration = 0;

/**
 * Send log message to main thread for window.logtoserver
 * @param {string} level - 'info', 'warn', 'error'
 * @param {string} message - Log message
 * @param {Object} context - Additional context data
 */
function logToMainThread(level, message, context = {}) {
    try {
        self.postMessage({
            type: 'WORKER_LOG',
            level: level,
            component: 'MetricsWorker',
            message: message,
            context: context
        });
    } catch (e) {
        console.warn('[Worker] Failed to send log to main thread:', e);
    }
}

class TransactionGuard {
    constructor(conn) {
        this.conn = conn;
        this.active = false;
        this.timeout = null;
    }

    async withTransaction(operation, timeoutMs = 30000) {
        // DuckDB-WASM auto-commits each statement, so we use a simple mutex pattern
        // to prevent concurrent operations that could cause issues
        if (this.active) {
            logToMainThread('Warn', 'Operation already in progress - waiting', {
                activeOperations: activeOperations
            });
            // Wait for current operation to complete (up to timeout)
            const startWait = performance.now();
            while (this.active && (performance.now() - startWait) < timeoutMs) {
                await new Promise(resolve => setTimeout(resolve, 50));
            }
            if (this.active) {
                throw new Error('Operation timeout - previous operation still in progress');
            }
        }

        this.active = true;
        const txStartTime = performance.now();
        transactionCount++;
        const txId = transactionCount;

        this.timeout = setTimeout(() => {
            const duration = performance.now() - txStartTime;
            console.error('[Worker] Operation timeout');
            logToMainThread('Error', 'Operation timeout', {
                txId: txId,
                duration: duration.toFixed(2),
                timeoutMs: timeoutMs
            });
            this.active = false;
        }, timeoutMs);

        try {
            logToMainThread('Info', 'Operation started', {
                txId: txId,
                activeOperations: activeOperations
            });

            const result = await operation();

            const duration = performance.now() - txStartTime;
            transactionTotalDuration += duration;

            logToMainThread('Info', 'Operation completed', {
                txId: txId,
                duration: duration.toFixed(2),
                avgDuration: (transactionTotalDuration / transactionCount).toFixed(2),
                totalTransactions: transactionCount
            });

            return result;
        } catch (e) {
            const duration = performance.now() - txStartTime;
            logToMainThread('Error', 'Operation failed', {
                txId: txId,
                duration: duration.toFixed(2),
                error: e.message
            });
            throw e;
        } finally {
            clearTimeout(this.timeout);
            this.active = false;
        }
    }
}

let transactionGuard = null;
let activeOperations = 0;

// ============ Initialization ============

/**
 * Initialize DuckDB with retry logic for network failures
 * Falls back to in-memory stub storage if DuckDB fails after all retries
 */
async function initDuckDB(options) {
    const { dbName, retentionHours, maxRecords } = options;
    const delays = [1000, 2000, 5000]; // Reduced retries - if module fails, no point retrying
    let lastError = null;

    sendProgress('Starting DuckDB initialization', 'init_start');

    // Quick check: if module load already failed, go straight to stub
    if (duckdbModuleLoadFailed) {
        console.warn('[Worker] DuckDB module failed to load, using stub storage immediately');
        sendProgress('Module load failed, using stub storage', 'fallback');
        return initStubStorage(options);
    }

    for (let attempt = 0; attempt < delays.length; attempt++) {
        try {
            console.log(`[Worker] Initializing DuckDB-WASM (attempt ${attempt + 1}/${delays.length})...`);
            sendProgress(`DuckDB init attempt ${attempt + 1}/${delays.length}`, 'init_attempt');

            // Wait for module to finish loading
            console.log('[Worker] Waiting for DuckDB module to load...');
            const DUCKDB = await duckdbModulePromise;

            if (!DUCKDB) {
                throw new Error('DuckDB module failed to load');
            }

            console.log('[Worker] DuckDB module loaded, available exports:', Object.keys(DUCKDB));

            // DuckDB-WASM AsyncDuckDB requires spawning a nested worker
            // Since we're already in a worker, we need to use a different approach:
            // Create a worker using createWorker, then use AsyncDuckDB

            // Select the MVP bundle (smallest, fastest to load)
            const bundle = await DUCKDB.selectBundle({
                mvp: {
                    mainModule: '/public/lib/duckdb-mvp.wasm',
                    mainWorker: '/public/lib/duckdb-browser-mvp.worker.js'
                }
            });

            console.log('[Worker] Bundle selected:', bundle);

            // Create nested worker for DuckDB
            const worker = await DUCKDB.createWorker(bundle.mainWorker);
            console.log('[Worker] Nested DuckDB worker created');

            // Create logger
            const logger = new DUCKDB.ConsoleLogger();

            // Create AsyncDuckDB instance with the worker
            db = new DUCKDB.AsyncDuckDB(logger, worker);
            console.log('[Worker] AsyncDuckDB instance created');

            // Instantiate the database with the WASM module
            await db.instantiate(bundle.mainModule);
            console.log('[Worker] DuckDB WASM instantiated');

            // Open an in-memory database
            await db.open({
                path: ':memory:',
                query: {
                    castBigIntToDouble: true,
                    castTimestampToDate: false
                }
            });
            console.log('[Worker] Database opened');

            // Create connection - returns AsyncDuckDBConnection
            const rawConn = await db.connect();
            console.log('[Worker] Connection established');

            storageType = 'memory';

            // Create a wrapper for the connection with our expected interface
            conn = {
                exec: async (sql) => {
                    await rawConn.query(sql);
                },
                query: async (sql) => {
                    const result = await rawConn.query(sql);
                    // Convert Arrow Table to array of objects
                    return result.toArray().map(row => row.toJSON());
                },
                close: async () => {
                    await rawConn.close();
                },
                _rawConn: rawConn
            };

            transactionGuard = new TransactionGuard(conn);

            // Create schema
            await createSchema();

            initialized = true;
            console.log('[Worker] DuckDB-WASM initialized successfully with in-memory storage');
            sendProgress('DuckDB-WASM initialized successfully', 'init_success');

            return { storage: storageType };

        } catch (err) {
            lastError = err;
            console.error(`[Worker] DuckDB init failed (attempt ${attempt + 1}/${delays.length}):`, err.message);
            sendProgress(`DuckDB init failed: ${err.message}`, 'init_error');
            logErrorToMainThread(err, { phase: 'initDuckDB', step: 'initialization', attempt: attempt + 1 });

            // If it's a module load error, don't retry - go straight to stub
            if (err.message.includes('module') || err.message.includes('import') ||
                err.message.includes('apache-arrow') || duckdbModuleLoadFailed) {
                console.warn('[Worker] Module-related error detected, skipping retries');
                sendProgress('Module error, using stub storage', 'fallback');
                break; // Exit retry loop
            }

            // Clean up any partial initialization
            if (db) {
                try { await db.terminate?.(); } catch (e) { /* ignore */ }
                db = null;
            }
            conn = null;

            // If not the last attempt, wait and retry
            if (attempt < delays.length - 1) {
                const delay = delays[attempt];
                console.log(`[Worker] Retrying DuckDB initialization in ${delay}ms...`);
                sendProgress(`Retrying in ${delay}ms...`, 'init_retry');
                await sleep(delay);
            }
        }
    }

    // All retries exhausted - fall back to stub storage
    console.warn('[Worker] All DuckDB initialization attempts failed, falling back to stub storage');
    console.warn('[Worker] Last error:', lastError?.message);
    sendProgress('Falling back to stub storage', 'fallback');

    return initStubStorage(options);
}

/**
 * Fallback stub storage when DuckDB fails to initialize
 * Stores data in memory using simple arrays - no persistence
 */
async function initStubStorage(options) {
    console.log('[Worker] Initializing stub in-memory storage...');
    sendProgress('Initializing stub in-memory storage', 'stub_init');

    // In-memory table storage
    const tables = {
        cpu_metrics: [],
        memory_metrics: [],
        disk_metrics: [],
        network_metrics: []
    };

    const MAX_ROWS_PER_TABLE = options.maxRecords || 10000;

    storageType = 'stub';

    // Create stub connection interface
    conn = {
        exec: async (sql) => {
            // Parse simple INSERT/CREATE/DELETE statements
            const insertMatch = sql.match(/INSERT INTO (\w+)\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/i);
            if (insertMatch) {
                const table = insertMatch[1];
                const columns = insertMatch[2].split(',').map(c => c.trim());
                const values = insertMatch[3].split(',').map(v => {
                    v = v.trim();
                    // Remove quotes from strings
                    if ((v.startsWith("'") && v.endsWith("'")) || (v.startsWith('"') && v.endsWith('"'))) {
                        return v.slice(1, -1);
                    }
                    // Parse numbers
                    const num = parseFloat(v);
                    return isNaN(num) ? v : num;
                });

                if (tables[table]) {
                    const row = {};
                    columns.forEach((col, i) => { row[col] = values[i]; });
                    tables[table].push(row);

                    // Prune if over limit
                    if (tables[table].length > MAX_ROWS_PER_TABLE) {
                        tables[table] = tables[table].slice(-MAX_ROWS_PER_TABLE);
                    }
                }
                return;
            }

            const deleteMatch = sql.match(/DELETE FROM (\w+)\s+WHERE\s+timestamp\s*<\s*'([^']+)'/i);
            if (deleteMatch) {
                const table = deleteMatch[1];
                const cutoff = new Date(deleteMatch[2]);
                if (tables[table]) {
                    tables[table] = tables[table].filter(row => new Date(row.timestamp) >= cutoff);
                }
                return;
            }

            // Ignore CREATE TABLE and other statements
            console.log('[Worker/Stub] Ignoring exec:', sql.substring(0, 100));
        },

        query: async (sql) => {
            // Parse simple SELECT statements
            const selectMatch = sql.match(/SELECT\s+(.+?)\s+FROM\s+(\w+)(?:\s+WHERE\s+(.+?))?(?:\s+ORDER BY\s+(.+?))?(?:\s+LIMIT\s+(\d+))?$/is);
            if (selectMatch) {
                const table = selectMatch[2];
                let rows = tables[table] ? [...tables[table]] : [];

                // Apply WHERE clause (simple timestamp filtering)
                if (selectMatch[3]) {
                    const whereClause = selectMatch[3];
                    const betweenMatch = whereClause.match(/timestamp\s+BETWEEN\s+'([^']+)'\s+AND\s+'([^']+)'/i);
                    if (betweenMatch) {
                        const startTime = new Date(betweenMatch[1]);
                        const endTime = new Date(betweenMatch[2]);
                        rows = rows.filter(row => {
                            const ts = new Date(row.timestamp);
                            return ts >= startTime && ts <= endTime;
                        });
                    }
                }

                // Apply ORDER BY
                if (selectMatch[4]) {
                    const orderBy = selectMatch[4];
                    const descending = orderBy.toLowerCase().includes('desc');
                    const column = orderBy.replace(/\s+(asc|desc)/i, '').trim();
                    rows.sort((a, b) => {
                        const aVal = a[column];
                        const bVal = b[column];
                        if (descending) return aVal > bVal ? -1 : 1;
                        return aVal < bVal ? -1 : 1;
                    });
                }

                // Apply LIMIT
                if (selectMatch[5]) {
                    rows = rows.slice(0, parseInt(selectMatch[5], 10));
                }

                return rows;
            }

            console.log('[Worker/Stub] Unhandled query:', sql.substring(0, 100));
            return [];
        },

        close: async () => {
            console.log('[Worker/Stub] Connection closed');
        },

        _rawConn: null
    };

    transactionGuard = new TransactionGuard(conn);

    initialized = true;
    console.log('[Worker] Stub storage initialized successfully');
    sendProgress('Stub storage initialized successfully', 'stub_success');

    return { storage: storageType, fallback: true, error: 'DuckDB initialization failed' };
}

async function createSchema() {
    console.log('[Worker] Creating database schema...');

    // CPU metrics table with timestamp index
    await conn.exec(`
        CREATE TABLE IF NOT EXISTS cpu_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            cpu_total DOUBLE
        )
    `);

    // Memory metrics table
    await conn.exec(`
        CREATE TABLE IF NOT EXISTS memory_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            used_mb DOUBLE,
            total_mb DOUBLE,
            percent_used DOUBLE
        )
    `);

    // Disk metrics table
    await conn.exec(`
        CREATE TABLE IF NOT EXISTS disk_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            drive VARCHAR,
            used_gb DOUBLE,
            total_gb DOUBLE,
            percent_used DOUBLE
        )
    `);

    // Network metrics table
    await conn.exec(`
        CREATE TABLE IF NOT EXISTS network_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            interface VARCHAR,
            bytes_per_sec DOUBLE
        )
    `);

    console.log('[Worker] Schema created successfully');
}

// ============ Insert Operations ============

async function insertMetrics(payload) {
    if (!initialized) {
        throw new Error('Database not initialized');
    }

    activeOperations++;
    // Track high water mark
    if (activeOperations > activeOperationsHighWaterMark) {
        activeOperationsHighWaterMark = activeOperations;
        logToMainThread('Info', 'ActiveOperations high water mark', {
            highWaterMark: activeOperationsHighWaterMark
        });
    }

    try {
        const { rows } = payload;
        let insertCount = 0;
        const startTime = performance.now();
        const batchSize = rows.length;

        logToMainThread('Info', 'Batch insert starting', {
            batchSize: batchSize,
            activeOperations: activeOperations
        });

        // Use transaction guard for safe transaction management
        const result = await transactionGuard.withTransaction(async () => {
            for (const row of rows) {
                const { table, data } = row;

                // Validate table name for SQL injection prevention
                validateSqlIdentifier(table, ALLOWED_TABLES, 'table');

                // Use simple INSERT queries (DuckDB handles duplicates gracefully in append-only tables)
                // Note: For time-series data, duplicate timestamps are acceptable
                const hostname = data.hostname || 'local';
                const ts = data.timestamp;

                switch (table) {
                    case 'cpu_metrics':
                        await conn.exec(
                            `INSERT INTO cpu_metrics (timestamp, hostname, cpu_total) VALUES ('${ts}', '${hostname}', ${data.cpu_total})`
                        );
                        insertCount++;
                        break;

                    case 'memory_metrics':
                        await conn.exec(
                            `INSERT INTO memory_metrics (timestamp, hostname, used_mb, total_mb, percent_used) VALUES ('${ts}', '${hostname}', ${data.used_mb}, ${data.total_mb}, ${data.percent_used})`
                        );
                        insertCount++;
                        break;

                    case 'disk_metrics':
                        await conn.exec(
                            `INSERT INTO disk_metrics (timestamp, hostname, drive, used_gb, total_gb, percent_used) VALUES ('${ts}', '${hostname}', '${data.drive}', ${data.used_gb}, ${data.total_gb}, ${data.percent_used})`
                        );
                        insertCount++;
                        break;

                    case 'network_metrics':
                        await conn.exec(
                            `INSERT INTO network_metrics (timestamp, hostname, interface, bytes_per_sec) VALUES ('${ts}', '${hostname}', '${data.interface}', ${data.bytes_per_sec})`
                        );
                        insertCount++;
                        break;
                }
            }
            return insertCount;
        });

        const duration = performance.now() - startTime;
        const rowsPerMs = result > 0 ? (result / duration).toFixed(2) : 0;
        console.log(`[Worker] Inserted ${result} rows in ${duration.toFixed(2)}ms`);

        logToMainThread('Info', 'Batch insert completed', {
            recordCount: result,
            duration: duration.toFixed(2),
            rowsPerMs: rowsPerMs,
            activeOperations: activeOperations
        });

        return { count: result, duration: duration.toFixed(2) };
    } finally {
        activeOperations--;
    }
}

// ============ Security: SQL Injection Prevention ============

const ALLOWED_COLUMNS = ['cpu_total', 'used_mb', 'total_mb', 'percent_used', 'used_gb', 'total_gb', 'bytes_per_sec'];
const ALLOWED_TABLES = ['cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];

function validateSqlIdentifier(value, allowedValues, type) {
    if (!allowedValues.includes(value)) {
        throw new Error(`Invalid ${type}: ${value}. Allowed: ${allowedValues.join(', ')}`);
    }
}

// ============ Query Operations ============

async function executeQuery(payload) {
    if (!initialized) {
        throw new Error('Database not initialized');
    }

    const { sql, returnArrow } = payload;
    const startTime = performance.now();

    try {
        // Execute query using DuckDB connection wrapper
        // The wrapper already converts Arrow to JSON objects
        const rows = await conn.query(sql);

        const duration = performance.now() - startTime;
        console.log(`[Worker] Query returned ${rows.length} rows in ${duration.toFixed(2)}ms`);

        return { rows, duration: duration.toFixed(2) };

    } catch (err) {
        console.error('[Worker] Query error:', err);
        throw err;
    }
}

async function queryForChart(payload) {
    if (!initialized) {
        throw new Error('Database not initialized');
    }

    const { startTime, endTime, table, valueColumn, pixelWidth } = payload;
    const perfStart = performance.now();

    try {
        // SQL INJECTION PROTECTION: Validate identifiers
        validateSqlIdentifier(table, ALLOWED_TABLES, 'table');
        validateSqlIdentifier(valueColumn, ALLOWED_COLUMNS, 'column');

        // Calculate optimal bucket size based on pixel width
        const timeRangeMs = new Date(endTime) - new Date(startTime);
        const bucketInterval = calculateBucketInterval(timeRangeMs, pixelWidth);

        // Resolution-aware downsampling query using DuckDB's strftime
        // Note: Identifiers are validated above, so this is safe from SQL injection
        const sql = `
            SELECT
                strftime(timestamp, '${bucketInterval}') as bucket_time,
                AVG(${valueColumn}) as value
            FROM ${table}
            WHERE timestamp BETWEEN '${startTime}' AND '${endTime}'
            GROUP BY bucket_time
            ORDER BY bucket_time ASC
        `;

        // Execute query with DuckDB wrapper (returns array of objects)
        const rows = await conn.query(sql);
        const count = rows.length;

        // OPTIMIZATION: Create transferable typed arrays in worker
        // This avoids JSON serialization and enables zero-copy transfer
        const timestampBuffer = new Float64Array(count);
        const valueBuffer = new Float64Array(count);

        for (let i = 0; i < count; i++) {
            const row = rows[i];
            // Convert timestamp string to Unix seconds (uPlot format)
            timestampBuffer[i] = new Date(row.bucket_time).getTime() / 1000;
            valueBuffer[i] = row.value ?? 0;
        }

        const duration = performance.now() - perfStart;
        console.log(`[Worker] Chart query: ${count} points in ${duration.toFixed(2)}ms (transferable)`);

        // Return typed arrays with transfer list
        return {
            timestamps: timestampBuffer,
            values: valueBuffer,
            count: count,
            duration: duration.toFixed(2),
            bucketInterval,
            // Mark for transferable transfer
            _transferable: [timestampBuffer.buffer, valueBuffer.buffer]
        };

    } catch (err) {
        console.error('[Worker] Chart query error:', err);
        throw err;
    }
}

function calculateBucketInterval(timeRangeMs, pixelWidth) {
    const targetPoints = Math.min(pixelWidth * 2, 3840); // Max 3840 points
    const msPerPoint = timeRangeMs / targetPoints;

    // Return SQLite strftime format string
    if (msPerPoint < 5000) return '%Y-%m-%d %H:%M:%S'; // 1 second
    if (msPerPoint < 15000) return '%Y-%m-%d %H:%M:00'; // 1 minute
    if (msPerPoint < 60000) return '%Y-%m-%d %H:%M:00'; // 1 minute
    if (msPerPoint < 300000) return '%Y-%m-%d %H:%M:00'; // 5 minutes
    if (msPerPoint < 900000) return '%Y-%m-%d %H:%M:00'; // 15 minutes
    if (msPerPoint < 3600000) return '%Y-%m-%d %H:00:00'; // 1 hour
    return '%Y-%m-%d %H:00:00'; // 1 hour
}

// ============ Maintenance Operations ============

async function pruneOldRecords(payload) {
    if (!initialized) {
        throw new Error('Database not initialized');
    }

    activeOperations++;
    // Track high water mark
    if (activeOperations > activeOperationsHighWaterMark) {
        activeOperationsHighWaterMark = activeOperations;
        logToMainThread('Info', 'ActiveOperations high water mark', {
            highWaterMark: activeOperationsHighWaterMark
        });
    }

    try {
        const { table, retentionHours } = payload;
        const startTime = performance.now();
        logToMainThread('Info', 'Prune operation starting', {
            table: table || 'all',
            retentionHours: retentionHours,
            activeOperations: activeOperations
        });

        // SQL INJECTION PROTECTION: Validate table names
        const tables = table ? [table] : ['cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];

        for (const t of tables) {
            validateSqlIdentifier(t, ALLOWED_TABLES, 'table');
        }

        // Validate retention hours is a number
        const hours = parseInt(retentionHours, 10);
        if (isNaN(hours) || hours < 0) {
            throw new Error(`Invalid retentionHours: ${retentionHours}`);
        }

        let totalDeleted = 0;

        // Calculate cutoff timestamp
        const cutoffTime = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();

        // Use transaction guard for safe transaction management
        await transactionGuard.withTransaction(async () => {
            for (const t of tables) {
                // Delete old records (table name validated above)
                await conn.exec(`DELETE FROM ${t} WHERE timestamp < '${cutoffTime}'`);
            }
        });

        // Get remaining count (using wrapper that returns array of objects)
        const countResult = await conn.query(`SELECT COUNT(*) as cnt FROM cpu_metrics`);
        const remaining = countResult.length > 0 ? countResult[0].cnt : 0;

        const duration = performance.now() - startTime;
        console.log(`[Worker] Pruned old records in ${duration.toFixed(2)}ms, ${remaining} rows remain`);

        logToMainThread('Info', 'Prune operation completed', {
            deleted: totalDeleted,
            remaining: remaining,
            duration: duration.toFixed(2)
        });

        return { deleted: totalDeleted, remaining, duration: duration.toFixed(2) };
    } finally {
        activeOperations--;
    }
}

async function closeDatabase() {
    console.log('[Worker] Closing database, waiting for active operations...');

    logToMainThread('Info', 'Database close requested', {
        activeOperations: activeOperations,
        highWaterMark: activeOperationsHighWaterMark,
        totalTransactions: transactionCount
    });

    // Wait up to 10 seconds for operations to complete
    const maxWait = 10000;
    const startWait = performance.now();
    while (activeOperations > 0 && (performance.now() - startWait) < maxWait) {
        await new Promise(resolve => setTimeout(resolve, 100));
    }

    if (activeOperations > 0) {
        console.warn(`[Worker] Force closing with ${activeOperations} operations still active`);
        logToMainThread('Warn', 'Force closing with active operations', {
            activeOperations: activeOperations,
            waitTimeMs: (performance.now() - startWait).toFixed(2)
        });
    }

    // Cleanup prepared statements first
    cleanupPreparedStatements();

    // Reset transaction guard
    transactionGuard = null;

    // Close DuckDB connection and database
    if (conn && conn._rawConn) {
        try {
            await conn._rawConn.close();
        } catch (e) {
            console.warn('[Worker] Error closing connection:', e);
        }
        conn = null;
    }
    if (db) {
        try {
            await db.terminate();
        } catch (e) {
            console.warn('[Worker] Error terminating database:', e);
        }
        db = null;
    }
    initialized = false;
    console.log('[Worker] Database closed');
}

// ============ Message Handler ============

self.onmessage = async (event) => {
    const { id, type, payload } = event.data;

    try {
        let result;

        switch (type) {
            case 'INIT':
                result = await initDuckDB(payload);
                break;

            case 'INSERT':
                result = await insertMetrics(payload);
                break;

            case 'QUERY':
                result = await executeQuery(payload);
                break;

            case 'QUERY_FOR_CHART':
                result = await queryForChart(payload);
                break;

            case 'PRUNE':
                result = await pruneOldRecords(payload);
                break;

            case 'EXEC':
                conn.exec(payload.sql);
                result = { success: true };
                break;

            case 'CLOSE':
                await closeDatabase();
                result = { closed: true };
                break;

            default:
                throw new Error(`Unknown message type: ${type}`);
        }

        // OPTIMIZATION: Use transferable objects for zero-copy transfer
        const transfers = [];
        if (result._transferable && Array.isArray(result._transferable)) {
            transfers.push(...result._transferable);
            delete result._transferable; // Remove marker before sending
        }

        self.postMessage({
            id,
            type: `${type}_RESULT`,
            payload: result
        }, transfers); // Pass transfer list for zero-copy

    } catch (err) {
        console.error('[Worker] Error handling message:', err);

        // Log to main thread for window.logtoserver
        logErrorToMainThread(err, { messageType: type, messageId: id });

        self.postMessage({
            id,
            type: 'ERROR',
            error: {
                message: err.message || String(err),
                code: type
            }
        });
    }
};

// Signal that worker is loaded
console.log('[Worker] Metrics worker loaded and ready');
self.postMessage({ type: 'WORKER_LOADED' });
