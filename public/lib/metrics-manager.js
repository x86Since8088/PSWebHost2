// Metrics Manager - Unified data management for metrics
// Handles historical loading from perfhistorylogs and periodic polling from /metrics
// Now integrated with sql.js for persistent metrics storage

class MetricsManager {
    constructor(options = {}) {
        this.datasets = new Map(); // dataset name -> data
        this.pollIntervals = new Map(); // dataset name -> interval ID
        this.cacheEnabled = options.cache !== false;
        this.sqlEnabled = options.sql !== false; // Enable sql.js storage by default
        this.metricsDB = null; // Will hold MetricsDatabase instance
        this.isInitializing = false;
        this.initPromise = null;

        // Configuration
        this.config = {
            historicalEndpoint: '/api/v1/perfhistorylogs',
            pollingEndpoint: '/apps/WebHostMetrics/api/v1/metrics',
            defaultPollInterval: 5000, // 5 seconds
            maxCacheAge: 24 * 60 * 60 * 1000, // 24 hours
            ...options
        };

        // Initialize IndexedDB cache if enabled
        if (this.cacheEnabled) {
            this.initCache();
        }

        // Initialize sql.js database if enabled
        if (this.sqlEnabled) {
            this.initSqlDatabase();
        }
    }

    // Initialize IndexedDB for caching
    async initCache() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open('MetricsManagerDB', 1);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                this.db = request.result;
                resolve();
            };

            request.onupgradeneeded = (event) => {
                const db = event.target.result;

                // Store for historical data
                if (!db.objectStoreNames.contains('historical')) {
                    const historicalStore = db.createObjectStore('historical', { keyPath: 'id' });
                    historicalStore.createIndex('dataset', 'dataset', { unique: false });
                    historicalStore.createIndex('timestamp', 'timestamp', { unique: false });
                }

                // Store for latest samples
                if (!db.objectStoreNames.contains('samples')) {
                    const samplesStore = db.createObjectStore('samples', { keyPath: 'id' });
                    samplesStore.createIndex('dataset', 'dataset', { unique: false });
                }
            };
        });
    }

    // Initialize sql.js database for metrics storage
    async initSqlDatabase() {
        if (this.isInitializing || this.metricsDB) return this.initPromise;

        this.isInitializing = true;
        this.initPromise = (async () => {
            try {
                // Load MetricsDatabase class if not already loaded
                if (typeof window.MetricsDatabase === 'undefined') {
                    await new Promise((resolve, reject) => {
                        const script = document.createElement('script');
                        script.src = '/public/lib/metrics-database.js';
                        script.onload = () => {
                            console.log('[MetricsManager] MetricsDatabase loaded');
                            resolve();
                        };
                        script.onerror = () => reject(new Error('Failed to load MetricsDatabase'));
                        document.head.appendChild(script);
                    });
                }

                // Create and initialize database
                this.metricsDB = new window.MetricsDatabase({
                    dbName: 'PSWebHostMetrics',
                    autoSaveInterval: 30000,
                    retentionHours: 24,
                    maxRecords: 100000
                });

                await this.metricsDB.initialize();
                console.log('[MetricsManager] sql.js database initialized');
                this.isInitializing = false;
                return this.metricsDB;

            } catch (error) {
                console.error('[MetricsManager] Error initializing sql.js:', error);
                this.sqlEnabled = false;
                this.isInitializing = false;
                throw error;
            }
        })();

        return this.initPromise;
    }

    // Load historical data from perfhistorylogs API
    async loadHistorical(options = {}) {
        const {
            datasetname = 'system_metrics',
            starttime,
            endtime,
            granularity,
            metrics = ['cpu', 'memory', 'disk', 'network'],
            format = 'json',
            aggregation = 'avg'
        } = options;

        try {
            // Build query string
            const params = new URLSearchParams();
            if (starttime) params.append('starttime', starttime);
            if (endtime) params.append('endtime', endtime);
            if (datasetname) params.append('datasetname', datasetname);
            if (granularity) params.append('granularity', granularity);
            if (aggregation) params.append('aggregation', aggregation);
            if (format) params.append('format', format);
            if (metrics.length) params.append('metrics', metrics.join(','));

            const url = `${this.config.historicalEndpoint}?${params.toString()}`;
            console.log(`[MetricsManager] Loading historical data: ${url}`);

            const response = await window.psweb_fetchWithAuthHandling(url);
            if (!response.ok) {
                throw new Error(`Historical data request failed: ${response.status}`);
            }

            const data = await response.json();

            // Store in memory
            this.datasets.set(datasetname, {
                type: 'historical',
                data: data,
                loadedAt: new Date(),
                options: options
            });

            // Store in sql.js database
            if (this.sqlEnabled && this.metricsDB) {
                await this.storeInSql(data);
            }

            // Cache in IndexedDB
            if (this.cacheEnabled && this.db) {
                await this.cacheHistorical(datasetname, data, options);
            }

            console.log(`[MetricsManager] Loaded ${data.length || 0} historical samples for ${datasetname}`);
            return data;

        } catch (error) {
            console.error('[MetricsManager] Error loading historical data:', error);
            throw error;
        }
    }

    // Start polling current metrics
    startPolling(options = {}) {
        const {
            datasetname = 'current_metrics',
            interval = this.config.defaultPollInterval,
            metrics = ['cpu', 'memory', 'disk', 'network'],
            onUpdate = null
        } = options;

        // Stop existing poll if any
        this.stopPolling(datasetname);

        const poll = async () => {
            try {
                const params = new URLSearchParams();
                if (metrics.length) params.append('metrics', metrics.join(','));

                const url = `${this.config.pollingEndpoint}?${params.toString()}`;
                const response = await window.psweb_fetchWithAuthHandling(url);

                if (!response.ok) {
                    console.error(`[MetricsManager] Polling failed: ${response.status}`);
                    return;
                }

                const data = await response.json();

                // Store in memory
                const existing = this.datasets.get(datasetname);
                if (existing && existing.type === 'polling') {
                    // Append to existing samples
                    existing.samples.push({
                        timestamp: new Date(),
                        data: data
                    });

                    // Keep only recent samples (last hour)
                    const cutoff = Date.now() - (60 * 60 * 1000);
                    existing.samples = existing.samples.filter(s => s.timestamp >= cutoff);
                } else {
                    this.datasets.set(datasetname, {
                        type: 'polling',
                        samples: [{
                            timestamp: new Date(),
                            data: data
                        }],
                        options: options
                    });
                }

                // Store in sql.js database
                if (this.sqlEnabled && this.metricsDB) {
                    await this.storeInSql([{
                        Timestamp: new Date().toISOString(),
                        ...data
                    }]);
                }

                // Callback for updates
                if (onUpdate && typeof onUpdate === 'function') {
                    onUpdate(data);
                }

            } catch (error) {
                console.error('[MetricsManager] Polling error:', error);
            }
        };

        // Initial poll
        poll();

        // Set up interval
        const intervalId = setInterval(poll, interval);
        this.pollIntervals.set(datasetname, intervalId);

        console.log(`[MetricsManager] Started polling ${datasetname} every ${interval}ms`);
        return intervalId;
    }

    // Stop polling
    stopPolling(datasetname) {
        const intervalId = this.pollIntervals.get(datasetname);
        if (intervalId) {
            clearInterval(intervalId);
            this.pollIntervals.delete(datasetname);
            console.log(`[MetricsManager] Stopped polling ${datasetname}`);
        }
    }

    // Get data for a dataset
    getData(datasetname) {
        return this.datasets.get(datasetname);
    }

    // Get specific metric from dataset
    getMetric(datasetname, metricName) {
        const dataset = this.datasets.get(datasetname);
        if (!dataset) return null;

        if (dataset.type === 'historical') {
            // Extract specific metric from historical data
            return this.extractMetricFromHistorical(dataset.data, metricName);
        } else if (dataset.type === 'polling') {
            // Extract from polling samples
            return this.extractMetricFromPolling(dataset.samples, metricName);
        }

        return null;
    }

    // Extract metric from historical data
    extractMetricFromHistorical(data, metricName) {
        if (!data || !Array.isArray(data)) return [];

        return data.map(sample => ({
            timestamp: sample.Timestamp || sample.timestamp,
            value: this.getMetricValue(sample, metricName)
        })).filter(s => s.value !== null);
    }

    // Extract metric from polling samples
    extractMetricFromPolling(samples, metricName) {
        if (!samples || !Array.isArray(samples)) return [];

        return samples.map(sample => ({
            timestamp: sample.timestamp,
            value: this.getMetricValue(sample.data, metricName)
        })).filter(s => s.value !== null);
    }

    // Get metric value from sample data
    getMetricValue(sample, metricName) {
        if (!sample) return null;

        switch (metricName.toLowerCase()) {
            case 'cpu':
            case 'cpu_total':
                return sample.Cpu?.Total || sample.cpu?.total || null;

            case 'cpu_cores':
                return sample.Cpu?.Cores || sample.cpu?.cores || null;

            case 'memory':
            case 'memory_used':
                return sample.Memory?.UsedPercent || sample.memory?.usedPercent || null;

            case 'memory_total':
                return sample.Memory?.TotalGB || sample.memory?.totalGB || null;

            case 'memory_available':
                return sample.Memory?.AvailableGB || sample.memory?.availableGB || null;

            case 'disk':
                // Return all drives
                return sample.Disk?.Drives || sample.disk?.drives || null;

            case 'network':
            case 'network_bytes':
                return sample.Network?.BytesPerSec || sample.network?.bytesPerSec || null;

            default:
                // Try direct property access
                return sample[metricName] || null;
        }
    }

    // Convert data to Chart.js format
    toChartFormat(datasetname, metricName, options = {}) {
        const data = this.getMetric(datasetname, metricName);
        if (!data) return { datasets: [] };

        const {
            label = metricName,
            borderColor = '#3b82f6',
            backgroundColor = 'rgba(59, 130, 246, 0.2)',
            fill = false
        } = options;

        // Handle CPU cores specially (multi-line chart)
        if (metricName === 'cpu_cores') {
            return this.cpuCoresToChartFormat(data, options);
        }

        // Single metric line
        const chartData = data.map(d => ({
            x: d.timestamp,
            y: d.value
        }));

        return {
            datasets: [{
                label: label,
                data: chartData,
                borderColor: borderColor,
                backgroundColor: backgroundColor,
                fill: fill,
                borderWidth: 2,
                tension: 0.4,
                pointRadius: 0
            }]
        };
    }

    // Convert CPU cores to multi-line chart format
    cpuCoresToChartFormat(data, options = {}) {
        if (!data || data.length === 0) return { datasets: [] };

        const colors = [
            '#3b82f6', '#ef4444', '#22c55e', '#f59e0b',
            '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'
        ];

        // Get core count from first sample
        const firstSample = data[0];
        const coreCount = Array.isArray(firstSample.value) ? firstSample.value.length : 0;

        const datasets = [];

        // Create dataset for each core
        for (let i = 0; i < coreCount; i++) {
            const coreData = data.map(sample => ({
                x: sample.timestamp,
                y: Array.isArray(sample.value) && sample.value[i] !== undefined ? sample.value[i] : 0
            }));

            datasets.push({
                label: `CPU ${i}`,
                data: coreData,
                borderColor: colors[i % colors.length],
                backgroundColor: colors[i % colors.length] + '40',
                fill: false,
                borderWidth: 2,
                tension: 0.4,
                pointRadius: 0
            });
        }

        // Add average line if requested
        if (options.includeAverage !== false) {
            const avgData = data.map(sample => {
                if (!Array.isArray(sample.value)) return { x: sample.timestamp, y: 0 };
                const avg = sample.value.reduce((a, b) => a + b, 0) / sample.value.length;
                return { x: sample.timestamp, y: avg };
            });

            datasets.push({
                label: 'Average',
                data: avgData,
                borderColor: '#ffffff',
                backgroundColor: 'rgba(255, 255, 255, 0.3)',
                fill: false,
                borderWidth: 3,
                tension: 0.4,
                pointRadius: 0
            });
        }

        return { datasets };
    }

    // Cache historical data in IndexedDB
    async cacheHistorical(datasetname, data, options) {
        if (!this.db) return;

        try {
            const tx = this.db.transaction(['historical'], 'readwrite');
            const store = tx.objectStore('historical');

            // Clear old data for this dataset
            const index = store.index('dataset');
            const range = IDBKeyRange.only(datasetname);
            const oldKeys = await new Promise((resolve, reject) => {
                const keys = [];
                const request = index.openKeyCursor(range);
                request.onsuccess = (e) => {
                    const cursor = e.target.result;
                    if (cursor) {
                        keys.push(cursor.primaryKey);
                        cursor.continue();
                    } else {
                        resolve(keys);
                    }
                };
                request.onerror = () => reject(request.error);
            });

            // Delete old entries
            for (const key of oldKeys) {
                store.delete(key);
            }

            // Add new data
            if (Array.isArray(data)) {
                for (const sample of data) {
                    store.put({
                        id: `${datasetname}_${sample.Timestamp || sample.timestamp || Date.now()}`,
                        dataset: datasetname,
                        timestamp: sample.Timestamp || sample.timestamp,
                        data: sample
                    });
                }
            }

            await new Promise((resolve, reject) => {
                tx.oncomplete = resolve;
                tx.onerror = () => reject(tx.error);
            });

            console.log(`[MetricsManager] Cached ${data.length} samples for ${datasetname}`);

        } catch (error) {
            console.error('[MetricsManager] Cache error:', error);
        }
    }

    // Store metrics data in sql.js database
    async storeInSql(data) {
        if (!this.metricsDB || !Array.isArray(data)) return;

        try {
            for (const sample of data) {
                const timestamp = sample.Timestamp || sample.timestamp || new Date().toISOString();
                const hostname = sample.Hostname || sample.hostname || window.location.hostname;

                // Build metrics object
                const metrics = {
                    timestamp: timestamp,
                    hostname: hostname
                };

                // Add CPU metrics
                if (sample.Cpu || sample.cpu) {
                    const cpu = sample.Cpu || sample.cpu;
                    metrics.cpu = {
                        total: cpu.Total || cpu.total || 0,
                        cores: cpu.Cores || cpu.cores || []
                    };
                }

                // Add Memory metrics
                if (sample.Memory || sample.memory) {
                    const mem = sample.Memory || sample.memory;
                    metrics.memory = {
                        totalGB: mem.TotalGB || mem.totalGB || 0,
                        usedGB: mem.UsedGB || mem.usedGB || 0,
                        availableGB: mem.AvailableGB || mem.availableGB || 0,
                        usedPercent: mem.UsedPercent || mem.usedPercent || 0
                    };
                }

                // Add Disk metrics
                if (sample.Disk || sample.disk) {
                    const disk = sample.Disk || sample.disk;
                    metrics.disk = disk.Drives || disk.drives || [];
                }

                // Add Network metrics
                if (sample.Network || sample.network) {
                    const net = sample.Network || sample.network;
                    metrics.network = {
                        bytesPerSec: net.BytesPerSec || net.bytesPerSec || 0,
                        packetsPerSec: net.PacketsPerSec || net.packetsPerSec || 0
                    };
                }

                // Insert into sql.js
                this.metricsDB.insertMetrics(metrics);
            }

            console.log(`[MetricsManager] Stored ${data.length} samples in sql.js`);

        } catch (error) {
            console.error('[MetricsManager] Error storing in sql.js:', error);
        }
    }

    // Query metrics from sql.js database
    async queryFromSql(metricType, startTime, endTime, options = {}) {
        if (!this.metricsDB) {
            console.warn('[MetricsManager] sql.js database not initialized');
            return null;
        }

        try {
            const start = startTime || new Date(Date.now() - 3600000).toISOString(); // Last hour
            const end = endTime || new Date().toISOString();

            switch (metricType) {
                case 'cpu':
                    return this.metricsDB.queryCPUMetrics(start, end);
                case 'memory':
                    return this.metricsDB.queryMemoryMetrics(start, end);
                case 'disk':
                    return this.metricsDB.queryDiskMetrics(start, end, options.drive);
                case 'network':
                    return this.metricsDB.queryNetworkMetrics(start, end);
                default:
                    console.warn(`[MetricsManager] Unknown metric type: ${metricType}`);
                    return null;
            }

        } catch (error) {
            console.error('[MetricsManager] Error querying sql.js:', error);
            return null;
        }
    }

    // Get sql.js database stats
    getDbStats() {
        if (!this.metricsDB) return null;
        return this.metricsDB.getStats();
    }

    // Export sql.js database
    async exportDb() {
        if (!this.metricsDB) return null;
        return this.metricsDB.exportToJSON();
    }

    // Clean up - stop all polling
    destroy() {
        for (const [datasetname] of this.pollIntervals) {
            this.stopPolling(datasetname);
        }
        this.datasets.clear();

        // Clean up sql.js database
        if (this.metricsDB) {
            this.metricsDB.close();
            this.metricsDB = null;
        }

        console.log('[MetricsManager] Destroyed');
    }
}

// Export for use
window.MetricsManager = MetricsManager;
