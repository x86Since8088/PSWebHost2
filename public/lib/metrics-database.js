// MetricsDatabase - sql.js wrapper for metrics storage
// Provides high-performance SQL storage for metrics with automatic persistence

class MetricsDatabase {
    constructor(options = {}) {
        this.db = null;
        this.SQL = null;
        this.isInitialized = false;
        this.config = {
            dbName: 'PSWebHostMetrics',
            indexedDBName: 'PSWebHostMetricsDB',
            autoSaveInterval: 30000, // Save to IndexedDB every 30 seconds
            retentionHours: 24,
            maxRecords: 100000,
            ...options
        };
        this.autoSaveTimer = null;
        this.changesSinceLastSave = 0;
    }

    // Initialize sql.js and create/load database
    async initialize() {
        if (this.isInitialized) return true;

        try {
            console.log('[MetricsDatabase] Initializing sql.js...');

            // Load sql.js library if not already loaded
            if (typeof initSqlJs === 'undefined') {
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/sql-wasm.js';
                    script.onload = () => {
                        console.log('[MetricsDatabase] sql-wasm.js loaded');
                        resolve();
                    };
                    script.onerror = () => reject(new Error('Failed to load sql-wasm.js'));
                    document.head.appendChild(script);
                });
            }

            // Initialize sql.js
            this.SQL = await initSqlJs({
                locateFile: file => `/public/lib/${file}`
            });

            // Try to load existing database from IndexedDB
            const savedData = await this.loadFromIndexedDB();

            if (savedData) {
                console.log('[MetricsDatabase] Loading existing database from IndexedDB');
                this.db = new this.SQL.Database(new Uint8Array(savedData));
                console.log('[MetricsDatabase] Database loaded successfully');
            } else {
                console.log('[MetricsDatabase] Creating new database');
                this.db = new this.SQL.Database();
                this.createSchema();
                console.log('[MetricsDatabase] Schema created');
            }

            // Verify schema
            this.verifySchema();

            // Start auto-save timer
            this.startAutoSave();

            this.isInitialized = true;
            console.log('[MetricsDatabase] Initialization complete');
            return true;

        } catch (error) {
            console.error('[MetricsDatabase] Initialization error:', error);
            throw error;
        }
    }

    // Create database schema
    createSchema() {
        console.log('[MetricsDatabase] Creating schema...');

        // Metrics table - stores all metric samples
        this.db.run(`
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                hostname TEXT,
                metric_type TEXT NOT NULL,
                metric_name TEXT,
                value REAL,
                value_json TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        `);

        // CPU metrics table - optimized for CPU data
        this.db.run(`
            CREATE TABLE IF NOT EXISTS cpu_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                hostname TEXT,
                cpu_total REAL,
                cpu_cores TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        `);

        // Memory metrics table
        this.db.run(`
            CREATE TABLE IF NOT EXISTS memory_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                hostname TEXT,
                used_percent REAL,
                total_gb REAL,
                available_gb REAL,
                used_gb REAL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        `);

        // Disk metrics table
        this.db.run(`
            CREATE TABLE IF NOT EXISTS disk_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                hostname TEXT,
                drive TEXT,
                used_percent REAL,
                total_gb REAL,
                available_gb REAL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        `);

        // Network metrics table
        this.db.run(`
            CREATE TABLE IF NOT EXISTS network_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                hostname TEXT,
                bytes_per_sec INTEGER,
                packets_per_sec INTEGER,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        `);

        // New Performance Tables (matching backend schema)
        // Perf_CPUCore - per-core CPU metrics with temperature
        this.db.run(`
            CREATE TABLE IF NOT EXISTS Perf_CPUCore (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                host TEXT NOT NULL,
                core_number INTEGER,
                percent_min REAL,
                percent_max REAL,
                percent_avg REAL,
                temp_min REAL,
                temp_max REAL,
                temp_avg REAL,
                seconds INTEGER NOT NULL
            )
        `);

        // Perf_MemoryUsage - memory metrics in MB
        this.db.run(`
            CREATE TABLE IF NOT EXISTS Perf_MemoryUsage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                host TEXT NOT NULL,
                mb_min REAL,
                mb_max REAL,
                mb_avg REAL,
                seconds INTEGER NOT NULL
            )
        `);

        // Perf_DiskIO - disk I/O metrics
        this.db.run(`
            CREATE TABLE IF NOT EXISTS Perf_DiskIO (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                host TEXT NOT NULL,
                drive TEXT,
                kb_per_sec_min REAL,
                kb_per_sec_max REAL,
                kb_per_sec_avg REAL,
                kb_per_sec_total REAL,
                io_per_sec_min REAL,
                io_per_sec_max REAL,
                io_per_sec_avg REAL,
                io_total INTEGER,
                seconds INTEGER NOT NULL
            )
        `);

        // Network - network adapter metrics with metadata
        this.db.run(`
            CREATE TABLE IF NOT EXISTS Network (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                host TEXT NOT NULL,
                adapter_name TEXT NOT NULL,
                adapter_type TEXT,
                vendor_name TEXT,
                mac_address TEXT,
                ingress_kb_min REAL,
                ingress_kb_max REAL,
                ingress_kb_avg REAL,
                ingress_kb_total REAL,
                egress_kb_min REAL,
                egress_kb_max REAL,
                egress_kb_avg REAL,
                egress_kb_total REAL,
                seconds INTEGER NOT NULL
            )
        `);

        // Create indexes for performance
        this.createIndexes();

        console.log('[MetricsDatabase] Schema created successfully');
    }

    // Create indexes for query performance
    createIndexes() {
        // Metrics table indexes
        this.db.run('CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics(timestamp)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_metrics_type ON metrics(metric_type)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_metrics_type_timestamp ON metrics(metric_type, timestamp)');

        // CPU metrics indexes
        this.db.run('CREATE INDEX IF NOT EXISTS idx_cpu_timestamp ON cpu_metrics(timestamp)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_cpu_hostname ON cpu_metrics(hostname)');

        // Memory metrics indexes
        this.db.run('CREATE INDEX IF NOT EXISTS idx_memory_timestamp ON memory_metrics(timestamp)');

        // Disk metrics indexes
        this.db.run('CREATE INDEX IF NOT EXISTS idx_disk_timestamp ON disk_metrics(timestamp)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_disk_drive ON disk_metrics(drive)');

        // Network metrics indexes
        this.db.run('CREATE INDEX IF NOT EXISTS idx_network_timestamp ON network_metrics(timestamp)');

        // Performance tables indexes
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_cpu_timestamp ON Perf_CPUCore(timestamp)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_cpu_host ON Perf_CPUCore(host)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_cpu_core ON Perf_CPUCore(core_number)');

        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_memory_timestamp ON Perf_MemoryUsage(timestamp)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_memory_host ON Perf_MemoryUsage(host)');

        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_diskio_timestamp ON Perf_DiskIO(timestamp)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_diskio_host ON Perf_DiskIO(host)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_diskio_drive ON Perf_DiskIO(drive)');

        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_network_timestamp ON Network(timestamp)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_network_host ON Network(host)');
        this.db.run('CREATE INDEX IF NOT EXISTS idx_perf_network_adapter ON Network(adapter_name)');
    }

    // Verify schema exists
    verifySchema() {
        const tables = this.db.exec(`
            SELECT name FROM sqlite_master
            WHERE type='table'
            ORDER BY name
        `);

        const tableNames = tables[0]?.values.map(row => row[0]) || [];
        console.log('[MetricsDatabase] Tables found:', tableNames);

        const requiredTables = ['metrics', 'cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];
        const missingTables = requiredTables.filter(t => !tableNames.includes(t));

        if (missingTables.length > 0) {
            console.warn('[MetricsDatabase] Missing tables:', missingTables);
            console.log('[MetricsDatabase] Recreating schema...');
            this.createSchema();
        }
    }

    // Insert metrics data
    insertMetrics(metricsData) {
        if (!this.isInitialized) {
            console.error('[MetricsDatabase] Not initialized');
            return false;
        }

        try {
            const timestamp = metricsData.timestamp || new Date().toISOString();
            const hostname = metricsData.hostname || window.location.hostname;

            // Insert CPU metrics
            if (metricsData.cpu) {
                this.insertCPUMetrics(timestamp, hostname, metricsData.cpu);
            }

            // Insert Memory metrics
            if (metricsData.memory) {
                this.insertMemoryMetrics(timestamp, hostname, metricsData.memory);
            }

            // Insert Disk metrics
            if (metricsData.disk) {
                this.insertDiskMetrics(timestamp, hostname, metricsData.disk);
            }

            // Insert Network metrics
            if (metricsData.network) {
                this.insertNetworkMetrics(timestamp, hostname, metricsData.network);
            }

            this.changesSinceLastSave++;

            // Cleanup old data periodically
            if (this.changesSinceLastSave % 100 === 0) {
                this.cleanup();
            }

            return true;

        } catch (error) {
            console.error('[MetricsDatabase] Insert error:', error);
            return false;
        }
    }

    // Insert CPU metrics
    insertCPUMetrics(timestamp, hostname, cpuData) {
        const total = cpuData.total || cpuData.Total || 0;
        const cores = cpuData.cores || cpuData.Cores || [];
        const coresJSON = JSON.stringify(cores);

        this.db.run(`
            INSERT INTO cpu_metrics (timestamp, hostname, cpu_total, cpu_cores)
            VALUES (?, ?, ?, ?)
        `, [timestamp, hostname, total, coresJSON]);
    }

    // Insert Memory metrics
    insertMemoryMetrics(timestamp, hostname, memoryData) {
        const usedPercent = memoryData.usedPercent || memoryData.UsedPercent || 0;
        const totalGB = memoryData.totalGB || memoryData.TotalGB || 0;
        const availableGB = memoryData.availableGB || memoryData.AvailableGB || 0;
        const usedGB = totalGB - availableGB;

        this.db.run(`
            INSERT INTO memory_metrics (timestamp, hostname, used_percent, total_gb, available_gb, used_gb)
            VALUES (?, ?, ?, ?, ?, ?)
        `, [timestamp, hostname, usedPercent, totalGB, availableGB, usedGB]);
    }

    // Insert Disk metrics
    insertDiskMetrics(timestamp, hostname, diskData) {
        const drives = diskData.drives || diskData.Drives || [];

        drives.forEach(drive => {
            const driveLetter = drive.drive || drive.Drive;
            const usedPercent = drive.usedPercent || drive.UsedPercent || 0;
            const totalGB = drive.totalGB || drive.TotalGB || 0;
            const availableGB = drive.availableGB || drive.AvailableGB || 0;

            this.db.run(`
                INSERT INTO disk_metrics (timestamp, hostname, drive, used_percent, total_gb, available_gb)
                VALUES (?, ?, ?, ?, ?, ?)
            `, [timestamp, hostname, driveLetter, usedPercent, totalGB, availableGB]);
        });
    }

    // Insert Network metrics
    insertNetworkMetrics(timestamp, hostname, networkData) {
        const bytesPerSec = networkData.bytesPerSec || networkData.BytesPerSec || 0;
        const packetsPerSec = networkData.packetsPerSec || networkData.PacketsPerSec || 0;

        this.db.run(`
            INSERT INTO network_metrics (timestamp, hostname, bytes_per_sec, packets_per_sec)
            VALUES (?, ?, ?, ?)
        `, [timestamp, hostname, bytesPerSec, packetsPerSec]);
    }

    // Query CPU metrics for time range
    queryCPUMetrics(startTime, endTime, limit = null) {
        let sql = `
            SELECT timestamp, hostname, cpu_total, cpu_cores
            FROM cpu_metrics
            WHERE timestamp BETWEEN ? AND ?
            ORDER BY timestamp ASC
        `;

        if (limit) {
            sql += ` LIMIT ${parseInt(limit)}`;
        }

        const stmt = this.db.prepare(sql);
        stmt.bind([startTime, endTime]);

        const results = [];
        while (stmt.step()) {
            const row = stmt.getAsObject();
            row.cpu_cores = JSON.parse(row.cpu_cores || '[]');
            results.push(row);
        }
        stmt.free();

        return results;
    }

    // Query Memory metrics for time range
    queryMemoryMetrics(startTime, endTime, limit = null) {
        let sql = `
            SELECT timestamp, hostname, used_percent, total_gb, available_gb, used_gb
            FROM memory_metrics
            WHERE timestamp BETWEEN ? AND ?
            ORDER BY timestamp ASC
        `;

        if (limit) {
            sql += ` LIMIT ${parseInt(limit)}`;
        }

        const stmt = this.db.prepare(sql);
        stmt.bind([startTime, endTime]);

        const results = [];
        while (stmt.step()) {
            results.push(stmt.getAsObject());
        }
        stmt.free();

        return results;
    }

    // Query Disk metrics for time range
    queryDiskMetrics(startTime, endTime, drive = null, limit = null) {
        let sql = `
            SELECT timestamp, hostname, drive, used_percent, total_gb, available_gb
            FROM disk_metrics
            WHERE timestamp BETWEEN ? AND ?
        `;

        const params = [startTime, endTime];

        if (drive) {
            sql += ` AND drive = ?`;
            params.push(drive);
        }

        sql += ` ORDER BY timestamp ASC`;

        if (limit) {
            sql += ` LIMIT ${parseInt(limit)}`;
        }

        const stmt = this.db.prepare(sql);
        stmt.bind(params);

        const results = [];
        while (stmt.step()) {
            results.push(stmt.getAsObject());
        }
        stmt.free();

        return results;
    }

    // Query Network metrics for time range
    queryNetworkMetrics(startTime, endTime, limit = null) {
        let sql = `
            SELECT timestamp, hostname, bytes_per_sec, packets_per_sec
            FROM network_metrics
            WHERE timestamp BETWEEN ? AND ?
            ORDER BY timestamp ASC
        `;

        if (limit) {
            sql += ` LIMIT ${parseInt(limit)}`;
        }

        const stmt = this.db.prepare(sql);
        stmt.bind([startTime, endTime]);

        const results = [];
        while (stmt.step()) {
            results.push(stmt.getAsObject());
        }
        stmt.free();

        return results;
    }

    // Execute raw SQL query
    query(sql, params = []) {
        if (!this.isInitialized) {
            throw new Error('Database not initialized');
        }

        try {
            const stmt = this.db.prepare(sql);
            stmt.bind(params);

            const results = [];
            while (stmt.step()) {
                results.push(stmt.getAsObject());
            }
            stmt.free();

            return results;

        } catch (error) {
            console.error('[MetricsDatabase] Query error:', error);
            throw error;
        }
    }

    // Execute raw SQL (for INSERT/UPDATE/DELETE)
    execute(sql, params = []) {
        if (!this.isInitialized) {
            throw new Error('Database not initialized');
        }

        try {
            this.db.run(sql, params);
            this.changesSinceLastSave++;
            return true;

        } catch (error) {
            console.error('[MetricsDatabase] Execute error:', error);
            throw error;
        }
    }

    // uPlot Formatter Methods (for high-performance chart rendering)

    /**
     * Query and format CPU metrics for uPlot
     * Returns uPlot data format: [[timestamps], [core0], [core1], ...]
     */
    queryForUPlot_CPU(startTime, endTime, granularity = '5s') {
        const secondsFilter = granularity === '5s' ? 5 : 60;

        const sql = `
            SELECT timestamp, core_number, percent_avg
            FROM Perf_CPUCore
            WHERE timestamp BETWEEN ? AND ?
              AND seconds = ?
            ORDER BY timestamp ASC, core_number ASC
        `;

        const results = this.query(sql, [startTime, endTime, secondsFilter]);

        // Group by core number
        const coreMap = new Map();
        const timestampSet = new Set();

        results.forEach(row => {
            const timestamp = new Date(row.timestamp).getTime() / 1000; // uPlot uses seconds
            const coreNum = row.core_number;

            timestampSet.add(timestamp);

            if (!coreMap.has(coreNum)) {
                coreMap.set(coreNum, new Map());
            }
            coreMap.get(coreNum).set(timestamp, row.percent_avg);
        });

        // Sort timestamps
        const timestamps = Array.from(timestampSet).sort((a, b) => a - b);

        // Build data arrays [timestamps, core0, core1, ...]
        const data = [timestamps];
        const series = [{ label: 'Time' }];

        const colors = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];

        // Sort cores numerically
        const sortedCores = Array.from(coreMap.keys()).sort((a, b) => a - b);

        sortedCores.forEach((coreNum, index) => {
            const coreData = coreMap.get(coreNum);
            const values = timestamps.map(ts => coreData.get(ts) || null);

            data.push(values);
            series.push({
                label: `CPU ${coreNum}`,
                stroke: colors[index % colors.length],
                width: 2,
                spanGaps: true
            });
        });

        // Add average line
        const avgValues = timestamps.map(ts => {
            const coreValues = sortedCores
                .map(core => coreMap.get(core).get(ts))
                .filter(v => v !== null && v !== undefined);

            if (coreValues.length === 0) return null;
            return coreValues.reduce((sum, val) => sum + val, 0) / coreValues.length;
        });

        data.push(avgValues);
        series.push({
            label: 'Average',
            stroke: '#ffffff',
            width: 3,
            spanGaps: true
        });

        return { data, series };
    }

    /**
     * Query and format Memory metrics for uPlot
     */
    queryForUPlot_Memory(startTime, endTime, granularity = '5s') {
        const secondsFilter = granularity === '5s' ? 5 : 60;

        const sql = `
            SELECT timestamp, mb_avg
            FROM Perf_MemoryUsage
            WHERE timestamp BETWEEN ? AND ?
              AND seconds = ?
            ORDER BY timestamp ASC
        `;

        const results = this.query(sql, [startTime, endTime, secondsFilter]);

        const timestamps = results.map(row => new Date(row.timestamp).getTime() / 1000);
        const values = results.map(row => row.mb_avg);

        return {
            data: [timestamps, values],
            series: [
                { label: 'Time' },
                { label: 'Memory (MB)', stroke: '#3b82f6', width: 2, fill: 'rgba(59, 130, 246, 0.2)' }
            ]
        };
    }

    /**
     * Query and format Disk I/O metrics for uPlot
     */
    queryForUPlot_DiskIO(startTime, endTime, granularity = '5s') {
        const secondsFilter = granularity === '5s' ? 5 : 60;

        const sql = `
            SELECT timestamp, drive, kb_per_sec_avg
            FROM Perf_DiskIO
            WHERE timestamp BETWEEN ? AND ?
              AND seconds = ?
            ORDER BY timestamp ASC, drive ASC
        `;

        const results = this.query(sql, [startTime, endTime, secondsFilter]);

        // Group by drive
        const driveMap = new Map();
        const timestampSet = new Set();

        results.forEach(row => {
            const timestamp = new Date(row.timestamp).getTime() / 1000;
            const drive = row.drive;

            timestampSet.add(timestamp);

            if (!driveMap.has(drive)) {
                driveMap.set(drive, new Map());
            }
            driveMap.get(drive).set(timestamp, row.kb_per_sec_avg);
        });

        const timestamps = Array.from(timestampSet).sort((a, b) => a - b);
        const data = [timestamps];
        const series = [{ label: 'Time' }];

        const colors = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#8b5cf6'];
        let driveIndex = 0;

        driveMap.forEach((driveData, drive) => {
            const values = timestamps.map(ts => driveData.get(ts) || null);
            data.push(values);
            series.push({
                label: `${drive} KB/s`,
                stroke: colors[driveIndex % colors.length],
                width: 2,
                spanGaps: true
            });
            driveIndex++;
        });

        return { data, series };
    }

    /**
     * Query and format Network metrics for uPlot
     */
    queryForUPlot_Network(startTime, endTime, granularity = '5s') {
        const secondsFilter = granularity === '5s' ? 5 : 60;

        const sql = `
            SELECT timestamp, adapter_name, ingress_kb_avg, egress_kb_avg
            FROM Network
            WHERE timestamp BETWEEN ? AND ?
              AND seconds = ?
            ORDER BY timestamp ASC, adapter_name ASC
        `;

        const results = this.query(sql, [startTime, endTime, secondsFilter]);

        // Group by adapter
        const adapterMap = new Map();
        const timestampSet = new Set();

        results.forEach(row => {
            const timestamp = new Date(row.timestamp).getTime() / 1000;
            const adapter = row.adapter_name;
            const totalKB = (row.ingress_kb_avg || 0) + (row.egress_kb_avg || 0);

            timestampSet.add(timestamp);

            if (!adapterMap.has(adapter)) {
                adapterMap.set(adapter, new Map());
            }
            adapterMap.get(adapter).set(timestamp, totalKB);
        });

        const timestamps = Array.from(timestampSet).sort((a, b) => a - b);
        const data = [timestamps];
        const series = [{ label: 'Time' }];

        const colors = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#8b5cf6', '#ec4899'];
        let adapterIndex = 0;

        adapterMap.forEach((adapterData, adapter) => {
            const values = timestamps.map(ts => adapterData.get(ts) || null);
            data.push(values);
            series.push({
                label: `${adapter} KB/s`,
                stroke: colors[adapterIndex % colors.length],
                width: 2,
                spanGaps: true
            });
            adapterIndex++;
        });

        return { data, series };
    }

    // Get database statistics
    getStats() {
        if (!this.isInitialized) return null;

        const stats = {
            cpu: this.query('SELECT COUNT(*) as count FROM cpu_metrics')[0]?.count || 0,
            memory: this.query('SELECT COUNT(*) as count FROM memory_metrics')[0]?.count || 0,
            disk: this.query('SELECT COUNT(*) as count FROM disk_metrics')[0]?.count || 0,
            network: this.query('SELECT COUNT(*) as count FROM network_metrics')[0]?.count || 0,
        };

        stats.total = stats.cpu + stats.memory + stats.disk + stats.network;

        // Get time range
        const timeRange = this.query(`
            SELECT
                MIN(timestamp) as earliest,
                MAX(timestamp) as latest
            FROM cpu_metrics
        `)[0] || {};

        stats.timeRange = timeRange;

        // Get database size estimate
        const exported = this.db.export();
        stats.sizeBytes = exported.length;
        stats.sizeKB = (exported.length / 1024).toFixed(2);
        stats.sizeMB = (exported.length / 1024 / 1024).toFixed(2);

        return stats;
    }

    // Cleanup old data beyond retention period
    cleanup() {
        if (!this.isInitialized) return;

        const cutoffTime = new Date(Date.now() - this.config.retentionHours * 60 * 60 * 1000).toISOString();

        console.log(`[MetricsDatabase] Cleaning up data older than ${cutoffTime}`);

        const tables = ['cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];

        tables.forEach(table => {
            const result = this.db.exec(`DELETE FROM ${table} WHERE timestamp < ?`, [cutoffTime]);
            console.log(`[MetricsDatabase] Deleted old records from ${table}`);
        });

        // Also limit total record count
        this.limitRecordCount();

        // Vacuum database to reclaim space
        this.db.run('VACUUM');

        this.changesSinceLastSave++;
    }

    // Limit total record count
    limitRecordCount() {
        const tables = ['cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];

        tables.forEach(table => {
            const count = this.query(`SELECT COUNT(*) as count FROM ${table}`)[0]?.count || 0;

            if (count > this.config.maxRecords) {
                const toDelete = count - this.config.maxRecords;
                this.db.run(`
                    DELETE FROM ${table}
                    WHERE id IN (
                        SELECT id FROM ${table}
                        ORDER BY timestamp ASC
                        LIMIT ${toDelete}
                    )
                `);
                console.log(`[MetricsDatabase] Deleted ${toDelete} oldest records from ${table}`);
            }
        });
    }

    // Save database to IndexedDB
    async saveToIndexedDB() {
        if (!this.isInitialized) return false;

        try {
            const data = this.db.export();
            const blob = new Blob([data], { type: 'application/x-sqlite3' });

            const db = await this.openIndexedDB();
            const tx = db.transaction(['databases'], 'readwrite');
            const store = tx.objectStore('databases');

            await new Promise((resolve, reject) => {
                const request = store.put({
                    id: this.config.dbName,
                    data: data,
                    timestamp: new Date().toISOString(),
                    size: data.length
                });

                request.onsuccess = () => {
                    console.log(`[MetricsDatabase] Saved to IndexedDB (${(data.length / 1024).toFixed(2)} KB)`);
                    this.changesSinceLastSave = 0;
                    resolve();
                };

                request.onerror = () => reject(request.error);
            });

            return true;

        } catch (error) {
            console.error('[MetricsDatabase] Save to IndexedDB error:', error);
            return false;
        }
    }

    // Load database from IndexedDB
    async loadFromIndexedDB() {
        try {
            const db = await this.openIndexedDB();
            const tx = db.transaction(['databases'], 'readonly');
            const store = tx.objectStore('databases');

            return new Promise((resolve, reject) => {
                const request = store.get(this.config.dbName);

                request.onsuccess = () => {
                    if (request.result) {
                        console.log(`[MetricsDatabase] Loaded from IndexedDB (${(request.result.size / 1024).toFixed(2)} KB)`);
                        resolve(request.result.data);
                    } else {
                        resolve(null);
                    }
                };

                request.onerror = () => {
                    console.error('[MetricsDatabase] Load from IndexedDB error:', request.error);
                    resolve(null);
                };
            });

        } catch (error) {
            console.error('[MetricsDatabase] Load from IndexedDB error:', error);
            return null;
        }
    }

    // Open IndexedDB
    openIndexedDB() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open(this.config.indexedDBName, 1);

            request.onupgradeneeded = (event) => {
                const db = event.target.result;
                if (!db.objectStoreNames.contains('databases')) {
                    db.createObjectStore('databases', { keyPath: 'id' });
                }
            };

            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
    }

    // Start auto-save timer
    startAutoSave() {
        if (this.autoSaveTimer) return;

        this.autoSaveTimer = setInterval(() => {
            if (this.changesSinceLastSave > 0) {
                console.log(`[MetricsDatabase] Auto-saving (${this.changesSinceLastSave} changes)...`);
                this.saveToIndexedDB();
            }
        }, this.config.autoSaveInterval);

        console.log(`[MetricsDatabase] Auto-save enabled (every ${this.config.autoSaveInterval / 1000}s)`);
    }

    // Stop auto-save timer
    stopAutoSave() {
        if (this.autoSaveTimer) {
            clearInterval(this.autoSaveTimer);
            this.autoSaveTimer = null;
            console.log('[MetricsDatabase] Auto-save disabled');
        }
    }

    // Export database to file
    exportToFile(filename = null) {
        if (!this.isInitialized) {
            throw new Error('Database not initialized');
        }

        const data = this.db.export();
        const blob = new Blob([data], { type: 'application/x-sqlite3' });
        const url = URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = filename || `pswebhost_metrics_${Date.now()}.db`;
        a.click();

        URL.revokeObjectURL(url);

        console.log(`[MetricsDatabase] Exported to ${a.download}`);
    }

    // Clean old data based on retention policy
    cleanOldData(retentionDays = 7) {
        if (!this.isInitialized) {
            console.warn('[MetricsDatabase] Cannot clean data - database not initialized');
            return 0;
        }

        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - retentionDays);
        const cutoffTimestamp = cutoffDate.toISOString();

        let totalDeleted = 0;

        // Clean new architecture tables (Perf_CPUCore, Perf_MemoryUsage, etc.)
        const newTables = ['Perf_CPUCore', 'Perf_MemoryUsage', 'Perf_DiskIO', 'Network'];
        newTables.forEach(table => {
            try {
                const result = this.db.exec(`DELETE FROM ${table} WHERE timestamp < '${cutoffTimestamp}'`);
                if (result && result[0]) {
                    totalDeleted += result[0].values.length;
                }
            } catch (err) {
                // Table might not exist yet, ignore
            }
        });

        // Clean legacy tables
        const legacyTables = ['metrics', 'cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];
        legacyTables.forEach(table => {
            try {
                const result = this.db.exec(`DELETE FROM ${table} WHERE timestamp < '${cutoffTimestamp}'`);
                if (result && result[0]) {
                    totalDeleted += result[0].values.length;
                }
            } catch (err) {
                // Table might not exist, ignore
            }
        });

        // Vacuum to reclaim space
        this.db.run('VACUUM');

        console.log(`[MetricsDatabase] Cleaned ${totalDeleted} old records (retention: ${retentionDays} days)`);
        this.changesSinceLastSave++;

        return totalDeleted;
    }

    // Close database
    async close() {
        if (!this.isInitialized) return;

        // Save before closing
        await this.saveToIndexedDB();

        // Stop auto-save
        this.stopAutoSave();

        // Close database
        if (this.db) {
            this.db.close();
            this.db = null;
        }

        this.isInitialized = false;
        console.log('[MetricsDatabase] Closed');
    }

    // Clear all data
    clearAllData() {
        if (!this.isInitialized) return;

        const tables = ['metrics', 'cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];

        tables.forEach(table => {
            this.db.run(`DELETE FROM ${table}`);
        });

        this.db.run('VACUUM');

        console.log('[MetricsDatabase] All data cleared');
        this.changesSinceLastSave++;
    }
}

// Export for use
window.MetricsDatabase = MetricsDatabase;
