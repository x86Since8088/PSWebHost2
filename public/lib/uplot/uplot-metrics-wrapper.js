/**
 * UPlot Metrics Wrapper - Unified chart rendering with DuckDB storage and polling
 *
 * Combines:
 * - DuckDB-WASM for in-browser metrics storage
 * - uPlot for high-performance chart rendering
 * - Automatic polling and data updates
 *
 * Usage:
 *   const chart = new UPlotMetricsWrapper({
 *       container: document.getElementById('cpu-chart'),
 *       metric: 'cpu',
 *       timeRange: '1h',
 *       pollInterval: 5000
 *   });
 *   await chart.initialize();
 *   chart.start();
 */

class UPlotMetricsWrapper {
    constructor(options = {}) {
        this.container = options.container;
        this.metric = options.metric || 'cpu';
        this.timeRange = options.timeRange || '1h';
        this.pollInterval = options.pollInterval || 5000;
        this.historyRefreshInterval = options.historyRefreshInterval || 15 * 60 * 1000; // 15 min

        // Endpoints
        this.historyEndpoint = options.historyEndpoint || '/apps/WebHostMetrics/api/v1/metrics/history';
        this.realtimeEndpoint = options.realtimeEndpoint || '/apps/WebHostMetrics/api/v1/metrics';

        // State
        this.uplot = null;
        this.metricsDB = null;
        this.pollTimer = null;
        this.historyTimer = null;
        this.isPaused = false;
        this.isInitialized = false;

        // Event handlers
        this._handlers = {
            data: [],
            error: []
        };

        // Chart configuration
        this.chartOptions = {
            width: options.width || 800,
            height: options.height || 300,
            title: options.title || this._getDefaultTitle(),
            ...options.chartOptions
        };
    }

    /**
     * Initialize the wrapper - loads history and creates chart
     */
    async initialize() {
        if (this.isInitialized) return;

        try {
            // Initialize MetricsDatabase if not provided
            if (!this.metricsDB && window.MetricsDatabase) {
                this.metricsDB = new window.MetricsDatabase({
                    dbName: 'PSWebHostMetrics',
                    retentionHours: 24,
                    maxRecords: 100000
                });
                await this.metricsDB.initialize();
            }

            // Load historical data
            await this._loadHistory();

            // Create uPlot chart
            this._createChart();

            this.isInitialized = true;
            console.log(`[UPlotMetricsWrapper] Initialized for ${this.metric}`);

        } catch (err) {
            console.error('[UPlotMetricsWrapper] Initialization failed:', err);
            this._emit('error', err);
            throw err;
        }
    }

    /**
     * Start polling for new data
     */
    start() {
        if (!this.isInitialized) {
            console.warn('[UPlotMetricsWrapper] Not initialized, call initialize() first');
            return;
        }

        this.isPaused = false;

        // Start realtime polling
        this._poll();
        this.pollTimer = setInterval(() => this._poll(), this.pollInterval);

        // Start periodic history refresh
        this.historyTimer = setInterval(() => this._loadHistory(), this.historyRefreshInterval);

        console.log(`[UPlotMetricsWrapper] Started polling ${this.metric} every ${this.pollInterval}ms`);
    }

    /**
     * Pause polling
     */
    pause() {
        this.isPaused = true;
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
        console.log(`[UPlotMetricsWrapper] Paused ${this.metric}`);
    }

    /**
     * Resume polling
     */
    resume() {
        if (!this.isPaused) return;
        this.start();
    }

    /**
     * Change time range and refresh data
     */
    async setTimeRange(range) {
        this.timeRange = range;
        await this._loadHistory();
        this._updateChart();
    }

    /**
     * Destroy the wrapper and clean up resources
     */
    destroy() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
        if (this.historyTimer) {
            clearInterval(this.historyTimer);
            this.historyTimer = null;
        }
        if (this.uplot) {
            this.uplot.destroy();
            this.uplot = null;
        }

        this._handlers = { data: [], error: [] };
        this.isInitialized = false;
        console.log(`[UPlotMetricsWrapper] Destroyed ${this.metric}`);
    }

    /**
     * Register event handler
     */
    on(event, callback) {
        if (this._handlers[event]) {
            this._handlers[event].push(callback);
        }
        return this;
    }

    /**
     * Remove event handler
     */
    off(event, callback) {
        if (this._handlers[event]) {
            this._handlers[event] = this._handlers[event].filter(cb => cb !== callback);
        }
        return this;
    }

    // =========== Private Methods ===========

    _emit(event, data) {
        if (this._handlers[event]) {
            this._handlers[event].forEach(cb => cb(data));
        }
    }

    _getDefaultTitle() {
        const titles = {
            cpu: 'CPU Usage',
            memory: 'Memory Usage',
            disk: 'Disk Usage',
            network: 'Network Throughput'
        };
        return titles[this.metric] || this.metric;
    }

    _getTimeRangeMs() {
        const ranges = {
            '5m': 5 * 60 * 1000,
            '15m': 15 * 60 * 1000,
            '30m': 30 * 60 * 1000,
            '1h': 60 * 60 * 1000,
            '6h': 6 * 60 * 60 * 1000,
            '24h': 24 * 60 * 60 * 1000
        };
        return ranges[this.timeRange] || 60 * 60 * 1000;
    }

    _getTableAndColumn() {
        const mapping = {
            cpu: { table: 'cpu_metrics', column: 'cpu_total' },
            memory: { table: 'memory_metrics', column: 'percent_used' },
            disk: { table: 'disk_metrics', column: 'percent_used' },
            network: { table: 'network_metrics', column: 'bytes_per_sec' }
        };
        return mapping[this.metric] || mapping.cpu;
    }

    async _loadHistory() {
        try {
            const params = new URLSearchParams({
                metric: this.metric,
                timerange: this.timeRange,
                format: 'json'
            });

            const url = `${this.historyEndpoint}?${params}`;
            const response = await this._fetch(url);

            if (!response.ok) {
                throw new Error(`History fetch failed: ${response.status}`);
            }

            const data = await response.json();

            // Store in DuckDB
            if (this.metricsDB && Array.isArray(data)) {
                for (const sample of data) {
                    await this.metricsDB.insertMetrics(this._normalizeMetrics(sample));
                }
            }

            console.log(`[UPlotMetricsWrapper] Loaded ${data.length} historical samples for ${this.metric}`);

        } catch (err) {
            console.error('[UPlotMetricsWrapper] History load failed:', err);
            this._emit('error', err);
        }
    }

    async _poll() {
        if (this.isPaused) return;

        try {
            const params = new URLSearchParams({
                metrics: this.metric,
                action: 'realtime'
            });

            const url = `${this.realtimeEndpoint}?${params}`;
            const response = await this._fetch(url);

            if (!response.ok) {
                throw new Error(`Realtime fetch failed: ${response.status}`);
            }

            const data = await response.json();

            // Store in DuckDB
            if (this.metricsDB) {
                await this.metricsDB.insertMetrics(this._normalizeMetrics(data));
            }

            // Update chart
            this._updateChart();

            this._emit('data', data);

        } catch (err) {
            console.error('[UPlotMetricsWrapper] Poll failed:', err);
            this._emit('error', err);
        }
    }

    _normalizeMetrics(sample) {
        const timestamp = sample.Timestamp || sample.timestamp || new Date().toISOString();
        const hostname = sample.Hostname || sample.hostname || 'local';

        const normalized = { timestamp, hostname };

        // CPU
        if (sample.Cpu || sample.cpu) {
            const cpu = sample.Cpu || sample.cpu;
            normalized.cpu = { total: cpu.Total || cpu.total || 0 };
        }

        // Memory
        if (sample.Memory || sample.memory) {
            const mem = sample.Memory || sample.memory;
            normalized.memory = {
                used_mb: (mem.UsedGB || mem.usedGB || 0) * 1024,
                total_mb: (mem.TotalGB || mem.totalGB || 0) * 1024,
                percent_used: mem.UsedPercent || mem.usedPercent || mem.PercentUsed || 0
            };
        }

        // Disk
        if (sample.Disk || sample.disk) {
            const disk = sample.Disk || sample.disk;
            normalized.disk = (disk.Drives || disk.drives || disk || []).map(d => ({
                drive: d.Name || d.name || d.Drive || 'C:',
                used_gb: d.UsedGB || d.usedGB || 0,
                total_gb: d.TotalGB || d.totalGB || 0,
                percent_used: d.UsedPercent || d.usedPercent || 0
            }));
        }

        // Network
        if (sample.Network || sample.network) {
            const net = sample.Network || sample.network;
            normalized.network = [{
                interface: 'default',
                bytes_per_sec: net.BytesPerSec || net.bytesPerSec || 0
            }];
        }

        return normalized;
    }

    async _fetch(url) {
        // Use authenticated fetch if available
        if (typeof window !== 'undefined' && window.psweb_fetchWithAuthHandling) {
            return window.psweb_fetchWithAuthHandling(url);
        }
        return fetch(url);
    }

    _createChart() {
        if (!this.container) {
            console.warn('[UPlotMetricsWrapper] No container specified');
            return;
        }

        // Clear container
        this.container.innerHTML = '';

        const { table, column } = this._getTableAndColumn();

        // Default uPlot options
        const opts = {
            width: this.chartOptions.width,
            height: this.chartOptions.height,
            title: this.chartOptions.title,
            cursor: {
                drag: { x: true, y: false }
            },
            scales: {
                x: { time: true },
                y: { auto: true }
            },
            axes: [
                { stroke: '#888', grid: { stroke: '#333' } },
                { stroke: '#888', grid: { stroke: '#333' }, size: 50 }
            ],
            series: [
                {},
                {
                    stroke: '#3b82f6',
                    fill: 'rgba(59, 130, 246, 0.1)',
                    width: 2
                }
            ],
            ...this.chartOptions
        };

        // Create with empty data initially
        const data = [[], []];
        this.uplot = new uPlot(opts, data, this.container);
    }

    async _updateChart() {
        if (!this.uplot || !this.metricsDB) return;

        try {
            const { table, column } = this._getTableAndColumn();
            const endTime = new Date();
            const startTime = new Date(endTime.getTime() - this._getTimeRangeMs());

            const result = await this.metricsDB.queryForChart({
                table,
                valueColumn: column,
                startTime: startTime.toISOString(),
                endTime: endTime.toISOString(),
                pixelWidth: this.chartOptions.width
            });

            if (result && result.timestamps && result.values) {
                const data = [
                    Array.from(result.timestamps),
                    Array.from(result.values)
                ];
                this.uplot.setData(data);
            }

        } catch (err) {
            console.error('[UPlotMetricsWrapper] Chart update failed:', err);
        }
    }
}

// Export
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { UPlotMetricsWrapper };
}
if (typeof window !== 'undefined') {
    window.UPlotMetricsWrapper = UPlotMetricsWrapper;
}
