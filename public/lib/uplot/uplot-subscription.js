/**
 * UPlot Subscription Manager - Shared polling for multiple charts
 *
 * Manages multiple chart subscriptions with a single polling loop to reduce
 * network requests and coordinate data updates.
 *
 * Usage:
 *   const manager = new UPlotSubscriptionManager({
 *       pollInterval: 5000,
 *       realtimeEndpoint: '/apps/WebHostMetrics/api/v1/metrics'
 *   });
 *
 *   manager.subscribe('cpu-chart', {
 *       metric: 'cpu',
 *       onData: (data) => chart.update(data)
 *   });
 *
 *   manager.subscribe('mem-chart', {
 *       metric: 'memory',
 *       onData: (data) => memChart.update(data)
 *   });
 */

class UPlotSubscriptionManager {
    constructor(options = {}) {
        this.pollInterval = options.pollInterval || 5000;
        this.realtimeEndpoint = options.realtimeEndpoint || '/apps/WebHostMetrics/api/v1/metrics';
        this.historyEndpoint = options.historyEndpoint || '/apps/WebHostMetrics/api/v1/metrics/history';

        this.subscriptions = new Map();
        this.pollTimer = null;
        this.isPolling = false;
        this.metricsDB = null;

        // Stats
        this.pollCount = 0;
        this.errorCount = 0;
        this.lastPollTime = null;
    }

    /**
     * Initialize the manager with shared database
     */
    async initialize() {
        if (window.MetricsDatabase && !this.metricsDB) {
            this.metricsDB = new window.MetricsDatabase({
                dbName: 'PSWebHostMetrics',
                retentionHours: 24,
                maxRecords: 100000
            });
            await this.metricsDB.initialize();
        }
    }

    /**
     * Subscribe a chart to receive metric updates
     * @param {string} chartId - Unique chart identifier
     * @param {Object} options - Subscription options
     * @param {string} options.metric - Metric type (cpu, memory, disk, network)
     * @param {Function} options.onData - Callback for data updates
     * @param {Function} options.onError - Callback for errors
     * @param {string} options.timeRange - Time range (5m, 1h, 24h)
     */
    subscribe(chartId, options) {
        const subscription = {
            metric: options.metric || 'cpu',
            onData: options.onData,
            onError: options.onError,
            timeRange: options.timeRange || '1h',
            lastUpdate: null
        };

        this.subscriptions.set(chartId, subscription);
        console.log(`[SubscriptionManager] Subscribed ${chartId} to ${subscription.metric}`);

        // Start polling if not already running
        if (!this.isPolling && this.subscriptions.size > 0) {
            this._startPolling();
        }

        return this;
    }

    /**
     * Unsubscribe a chart
     */
    unsubscribe(chartId) {
        this.subscriptions.delete(chartId);
        console.log(`[SubscriptionManager] Unsubscribed ${chartId}`);

        // Stop polling if no subscriptions
        if (this.subscriptions.size === 0) {
            this._stopPolling();
        }

        return this;
    }

    /**
     * Get current status
     */
    getStatus() {
        return {
            isPolling: this.isPolling,
            subscriptionCount: this.subscriptions.size,
            pollInterval: this.pollInterval,
            pollCount: this.pollCount,
            errorCount: this.errorCount,
            lastPollTime: this.lastPollTime,
            subscriptions: Array.from(this.subscriptions.keys())
        };
    }

    /**
     * Get shared database instance
     */
    getDatabase() {
        return this.metricsDB;
    }

    /**
     * Destroy and clean up
     */
    destroy() {
        this._stopPolling();
        this.subscriptions.clear();

        if (this.metricsDB) {
            this.metricsDB.close();
            this.metricsDB = null;
        }

        console.log('[SubscriptionManager] Destroyed');
    }

    // =========== Private Methods ===========

    _startPolling() {
        if (this.isPolling) return;

        this.isPolling = true;
        this._poll();
        this.pollTimer = setInterval(() => this._poll(), this.pollInterval);

        console.log(`[SubscriptionManager] Started polling every ${this.pollInterval}ms`);
    }

    _stopPolling() {
        if (!this.isPolling) return;

        this.isPolling = false;
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }

        console.log('[SubscriptionManager] Stopped polling');
    }

    async _poll() {
        if (this.subscriptions.size === 0) return;

        const startTime = performance.now();

        try {
            // Get unique metrics needed
            const metricsNeeded = new Set();
            for (const sub of this.subscriptions.values()) {
                metricsNeeded.add(sub.metric);
            }

            // Fetch all needed metrics in one request
            const params = new URLSearchParams({
                metrics: Array.from(metricsNeeded).join(','),
                action: 'realtime'
            });

            const url = `${this.realtimeEndpoint}?${params}`;
            const response = await this._fetch(url);

            if (!response.ok) {
                throw new Error(`Poll failed: ${response.status}`);
            }

            const data = await response.json();

            // Store in shared database
            if (this.metricsDB) {
                await this.metricsDB.insertMetrics(this._normalizeMetrics(data));
            }

            // Notify all subscriptions
            for (const [chartId, sub] of this.subscriptions) {
                if (sub.onData) {
                    try {
                        const metricData = this._extractMetric(data, sub.metric);
                        sub.onData(metricData, data);
                        sub.lastUpdate = new Date();
                    } catch (err) {
                        console.error(`[SubscriptionManager] Error in ${chartId} callback:`, err);
                    }
                }
            }

            this.pollCount++;
            this.lastPollTime = new Date();

        } catch (err) {
            this.errorCount++;
            console.error('[SubscriptionManager] Poll error:', err);

            // Notify error handlers
            for (const [chartId, sub] of this.subscriptions) {
                if (sub.onError) {
                    try {
                        sub.onError(err);
                    } catch (cbErr) {
                        console.error(`[SubscriptionManager] Error in ${chartId} error callback:`, cbErr);
                    }
                }
            }
        }
    }

    _extractMetric(data, metric) {
        const metricMapping = {
            cpu: data.Cpu || data.cpu,
            memory: data.Memory || data.memory,
            disk: data.Disk || data.disk,
            network: data.Network || data.network
        };
        return metricMapping[metric] || null;
    }

    _normalizeMetrics(sample) {
        const timestamp = sample.Timestamp || sample.timestamp || new Date().toISOString();
        const hostname = sample.Hostname || sample.hostname || 'local';

        const normalized = { timestamp, hostname };

        if (sample.Cpu || sample.cpu) {
            const cpu = sample.Cpu || sample.cpu;
            normalized.cpu = { total: cpu.Total || cpu.total || 0 };
        }

        if (sample.Memory || sample.memory) {
            const mem = sample.Memory || sample.memory;
            normalized.memory = {
                used_mb: (mem.UsedGB || mem.usedGB || 0) * 1024,
                total_mb: (mem.TotalGB || mem.totalGB || 0) * 1024,
                percent_used: mem.UsedPercent || mem.usedPercent || 0
            };
        }

        if (sample.Disk || sample.disk) {
            const disk = sample.Disk || sample.disk;
            normalized.disk = (disk.Drives || disk.drives || []).map(d => ({
                drive: d.Name || d.name || 'C:',
                used_gb: d.UsedGB || d.usedGB || 0,
                total_gb: d.TotalGB || d.totalGB || 0,
                percent_used: d.UsedPercent || d.usedPercent || 0
            }));
        }

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
        if (typeof window !== 'undefined' && window.psweb_fetchWithAuthHandling) {
            return window.psweb_fetchWithAuthHandling(url);
        }
        return fetch(url);
    }
}

// Export
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { UPlotSubscriptionManager };
}
if (typeof window !== 'undefined') {
    window.UPlotSubscriptionManager = UPlotSubscriptionManager;
}
