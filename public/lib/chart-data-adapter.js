// ChartDataAdapter - Manages incremental chart updates without destroying/recreating
// Provides efficient data management for Chart.js instances

class ChartDataAdapter {
    constructor(chartInstance, options = {}) {
        this.chart = chartInstance;
        this.config = {
            maxDataPoints: 1000,
            updateMode: 'none', // Chart.js update mode: 'none', 'resize', 'reset', 'active'
            timeWindow: null, // Time window in milliseconds (null = no limit)
            ...options
        };
        this.lastUpdate = Date.now();
    }

    // Append new data points to all datasets
    appendData(newData) {
        if (!this.chart || !newData) return false;

        try {
            const timestamp = newData.timestamp || new Date().toISOString();

            // Add data to each dataset
            if (Array.isArray(newData.datasets)) {
                newData.datasets.forEach((newDataset, index) => {
                    if (this.chart.data.datasets[index]) {
                        // Append data points
                        if (Array.isArray(newDataset.data)) {
                            newDataset.data.forEach(point => {
                                this.chart.data.datasets[index].data.push(point);
                            });
                        }
                    }
                });
            } else if (newData.values) {
                // Single value for all datasets
                newData.values.forEach((value, index) => {
                    if (this.chart.data.datasets[index]) {
                        this.chart.data.datasets[index].data.push({
                            x: timestamp,
                            y: value
                        });
                    }
                });
            }

            // Trim old data if needed
            this.trimOldData();

            // Update chart
            this.chart.update(this.config.updateMode);

            this.lastUpdate = Date.now();
            return true;

        } catch (error) {
            console.error('[ChartDataAdapter] Append error:', error);
            return false;
        }
    }

    // Replace all data (for time range changes)
    replaceData(newData) {
        if (!this.chart || !newData) return false;

        try {
            // Clear existing data
            this.chart.data.datasets.forEach(dataset => {
                dataset.data = [];
            });

            // Add new datasets if structure changed
            if (newData.datasets && newData.datasets.length !== this.chart.data.datasets.length) {
                this.chart.data.datasets = newData.datasets;
            } else if (newData.datasets) {
                // Update existing datasets with new data
                newData.datasets.forEach((newDataset, index) => {
                    if (this.chart.data.datasets[index]) {
                        this.chart.data.datasets[index].data = [...newDataset.data];
                    }
                });
            }

            // Update chart
            this.chart.update(this.config.updateMode);

            this.lastUpdate = Date.now();
            return true;

        } catch (error) {
            console.error('[ChartDataAdapter] Replace error:', error);
            return false;
        }
    }

    // Update single data point
    updateDataPoint(datasetIndex, pointIndex, newValue) {
        if (!this.chart) return false;

        try {
            if (this.chart.data.datasets[datasetIndex] &&
                this.chart.data.datasets[datasetIndex].data[pointIndex]) {

                if (typeof newValue === 'object') {
                    this.chart.data.datasets[datasetIndex].data[pointIndex] = newValue;
                } else {
                    this.chart.data.datasets[datasetIndex].data[pointIndex].y = newValue;
                }

                this.chart.update(this.config.updateMode);
                return true;
            }

            return false;

        } catch (error) {
            console.error('[ChartDataAdapter] Update point error:', error);
            return false;
        }
    }

    // Trim old data based on time window or max points
    trimOldData() {
        if (!this.chart) return;

        const now = Date.now();

        this.chart.data.datasets.forEach(dataset => {
            if (!dataset.data || dataset.data.length === 0) return;

            // Trim by time window
            if (this.config.timeWindow) {
                const cutoffTime = now - this.config.timeWindow;

                dataset.data = dataset.data.filter(point => {
                    const pointTime = new Date(point.x).getTime();
                    return pointTime >= cutoffTime;
                });
            }

            // Trim by max points
            if (this.config.maxDataPoints && dataset.data.length > this.config.maxDataPoints) {
                const excess = dataset.data.length - this.config.maxDataPoints;
                dataset.data.splice(0, excess);
            }
        });
    }

    // Remove oldest N points from all datasets
    removeOldestPoints(count) {
        if (!this.chart) return false;

        try {
            this.chart.data.datasets.forEach(dataset => {
                if (dataset.data && dataset.data.length > 0) {
                    dataset.data.splice(0, count);
                }
            });

            this.chart.update(this.config.updateMode);
            return true;

        } catch (error) {
            console.error('[ChartDataAdapter] Remove oldest error:', error);
            return false;
        }
    }

    // Get current data count
    getDataCount() {
        if (!this.chart || !this.chart.data.datasets[0]) return 0;
        return this.chart.data.datasets[0].data.length;
    }

    // Get time range of current data
    getTimeRange() {
        if (!this.chart || !this.chart.data.datasets[0] || !this.chart.data.datasets[0].data.length) {
            return null;
        }

        const data = this.chart.data.datasets[0].data;
        const timestamps = data.map(point => new Date(point.x).getTime()).filter(t => !isNaN(t));

        if (timestamps.length === 0) return null;

        return {
            start: new Date(Math.min(...timestamps)).toISOString(),
            end: new Date(Math.max(...timestamps)).toISOString(),
            count: timestamps.length,
            duration: Math.max(...timestamps) - Math.min(...timestamps)
        };
    }

    // Clear all data
    clearData() {
        if (!this.chart) return false;

        try {
            this.chart.data.datasets.forEach(dataset => {
                dataset.data = [];
            });

            this.chart.update(this.config.updateMode);
            return true;

        } catch (error) {
            console.error('[ChartDataAdapter] Clear error:', error);
            return false;
        }
    }

    // Update time window setting
    setTimeWindow(milliseconds) {
        this.config.timeWindow = milliseconds;
        this.trimOldData();
        this.chart.update(this.config.updateMode);
    }

    // Update max data points setting
    setMaxDataPoints(count) {
        this.config.maxDataPoints = count;
        this.trimOldData();
        this.chart.update(this.config.updateMode);
    }

    // Get statistics
    getStats() {
        if (!this.chart) return null;

        const stats = {
            datasets: this.chart.data.datasets.length,
            dataPoints: [],
            totalPoints: 0,
            timeRange: this.getTimeRange(),
            lastUpdate: new Date(this.lastUpdate).toISOString()
        };

        this.chart.data.datasets.forEach((dataset, index) => {
            const count = dataset.data?.length || 0;
            stats.dataPoints.push({
                index: index,
                label: dataset.label,
                count: count
            });
            stats.totalPoints += count;
        });

        return stats;
    }
}

// ChartDataManager - Manages data flow from sql.js to charts
class ChartDataManager {
    constructor(metricsDatabase) {
        this.db = metricsDatabase;
        this.charts = new Map(); // chartId -> { adapter, config }
        this.updateIntervals = new Map(); // chartId -> intervalId
    }

    // Register a chart for automatic updates
    registerChart(chartId, chartInstance, config = {}) {
        const adapter = new ChartDataAdapter(chartInstance, {
            maxDataPoints: config.maxDataPoints || 1000,
            updateMode: config.updateMode || 'none',
            timeWindow: config.timeWindow || null
        });

        this.charts.set(chartId, {
            adapter: adapter,
            config: {
                metricType: config.metricType || 'cpu', // cpu, memory, disk, network
                updateInterval: config.updateInterval || 5000,
                query: config.query || null,
                ...config
            }
        });

        console.log(`[ChartDataManager] Registered chart: ${chartId}`);

        // Start automatic updates if configured
        if (config.autoUpdate !== false) {
            this.startAutoUpdate(chartId);
        }

        return adapter;
    }

    // Unregister a chart
    unregisterChart(chartId) {
        this.stopAutoUpdate(chartId);
        this.charts.delete(chartId);
        console.log(`[ChartDataManager] Unregistered chart: ${chartId}`);
    }

    // Start automatic updates for a chart
    startAutoUpdate(chartId) {
        const chart = this.charts.get(chartId);
        if (!chart) return;

        // Stop existing interval
        this.stopAutoUpdate(chartId);

        // Get latest data timestamp
        let lastTimestamp = null;

        // Set up interval
        const intervalId = setInterval(async () => {
            try {
                // Query new data since last update
                const newData = await this.queryNewData(chartId, lastTimestamp);

                if (newData && newData.length > 0) {
                    // Convert to chart format
                    const chartData = this.convertToChartFormat(newData, chart.config.metricType);

                    // Append to chart
                    chart.adapter.appendData(chartData);

                    // Update last timestamp
                    lastTimestamp = newData[newData.length - 1].timestamp;
                }

            } catch (error) {
                console.error(`[ChartDataManager] Auto-update error for ${chartId}:`, error);
            }

        }, chart.config.updateInterval);

        this.updateIntervals.set(chartId, intervalId);
        console.log(`[ChartDataManager] Auto-update started for ${chartId}`);
    }

    // Stop automatic updates
    stopAutoUpdate(chartId) {
        const intervalId = this.updateIntervals.get(chartId);
        if (intervalId) {
            clearInterval(intervalId);
            this.updateIntervals.delete(chartId);
            console.log(`[ChartDataManager] Auto-update stopped for ${chartId}`);
        }
    }

    // Query new data for a chart
    async queryNewData(chartId, sinceTimestamp) {
        const chart = this.charts.get(chartId);
        if (!chart) return null;

        // If custom query provided, use it
        if (chart.config.query) {
            return this.db.query(chart.config.query);
        }

        // Otherwise use default queries
        const now = new Date().toISOString();
        const start = sinceTimestamp || new Date(Date.now() - 60000).toISOString(); // Last minute

        switch (chart.config.metricType) {
            case 'cpu':
                return this.db.queryCPUMetrics(start, now);
            case 'memory':
                return this.db.queryMemoryMetrics(start, now);
            case 'disk':
                return this.db.queryDiskMetrics(start, now, chart.config.drive);
            case 'network':
                return this.db.queryNetworkMetrics(start, now);
            default:
                return null;
        }
    }

    // Load historical data for a chart
    async loadHistoricalData(chartId, startTime, endTime) {
        const chart = this.charts.get(chartId);
        if (!chart) return null;

        let data = null;

        switch (chart.config.metricType) {
            case 'cpu':
                data = this.db.queryCPUMetrics(startTime, endTime);
                break;
            case 'memory':
                data = this.db.queryMemoryMetrics(startTime, endTime);
                break;
            case 'disk':
                data = this.db.queryDiskMetrics(startTime, endTime, chart.config.drive);
                break;
            case 'network':
                data = this.db.queryNetworkMetrics(startTime, endTime);
                break;
        }

        if (data && data.length > 0) {
            const chartData = this.convertToChartFormat(data, chart.config.metricType);
            chart.adapter.replaceData(chartData);
        }

        return data;
    }

    // Convert database results to Chart.js format
    convertToChartFormat(data, metricType) {
        if (!data || data.length === 0) return null;

        switch (metricType) {
            case 'cpu':
                return this.convertCPUData(data);
            case 'memory':
                return this.convertMemoryData(data);
            case 'disk':
                return this.convertDiskData(data);
            case 'network':
                return this.convertNetworkData(data);
            default:
                return null;
        }
    }

    // Convert CPU data to chart format
    convertCPUData(data) {
        const colors = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];

        // Get max core count
        const maxCores = Math.max(...data.map(d => d.cpu_cores?.length || 0));

        // Create datasets for each core
        const datasets = [];

        for (let i = 0; i < maxCores; i++) {
            datasets.push({
                label: `CPU ${i}`,
                data: data.map(d => ({
                    x: d.timestamp,
                    y: d.cpu_cores && d.cpu_cores[i] !== undefined ? d.cpu_cores[i] : 0
                })),
                borderColor: colors[i % colors.length],
                backgroundColor: colors[i % colors.length] + '40',
                fill: false,
                borderWidth: 2,
                tension: 0.4,
                pointRadius: 0
            });
        }

        // Add average line
        datasets.push({
            label: 'Average',
            data: data.map(d => ({
                x: d.timestamp,
                y: d.cpu_total || 0
            })),
            borderColor: '#ffffff',
            backgroundColor: 'rgba(255, 255, 255, 0.3)',
            fill: false,
            borderWidth: 3,
            tension: 0.4,
            pointRadius: 0
        });

        return { datasets };
    }

    // Convert Memory data to chart format
    convertMemoryData(data) {
        return {
            datasets: [{
                label: 'Memory Usage %',
                data: data.map(d => ({
                    x: d.timestamp,
                    y: d.used_percent || 0
                })),
                borderColor: '#ef4444',
                backgroundColor: 'rgba(239, 68, 68, 0.2)',
                fill: true,
                borderWidth: 2,
                tension: 0.4,
                pointRadius: 0
            }]
        };
    }

    // Convert Disk data to chart format
    convertDiskData(data) {
        const colors = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b'];

        // Group by drive
        const drives = [...new Set(data.map(d => d.drive))];

        const datasets = drives.map((drive, index) => {
            const driveData = data.filter(d => d.drive === drive);

            return {
                label: `${drive} Usage %`,
                data: driveData.map(d => ({
                    x: d.timestamp,
                    y: d.used_percent || 0
                })),
                borderColor: colors[index % colors.length],
                backgroundColor: colors[index % colors.length] + '40',
                fill: false,
                borderWidth: 2,
                tension: 0.4,
                pointRadius: 0
            };
        });

        return { datasets };
    }

    // Convert Network data to chart format
    convertNetworkData(data) {
        return {
            datasets: [{
                label: 'Network (MB/s)',
                data: data.map(d => ({
                    x: d.timestamp,
                    y: (d.bytes_per_sec || 0) / 1048576 // Convert to MB/s
                })),
                borderColor: '#22c55e',
                backgroundColor: 'rgba(34, 197, 94, 0.2)',
                fill: true,
                borderWidth: 2,
                tension: 0.4,
                pointRadius: 0
            }]
        };
    }

    // Get all registered charts
    getCharts() {
        return Array.from(this.charts.keys());
    }

    // Get chart statistics
    getChartStats(chartId) {
        const chart = this.charts.get(chartId);
        if (!chart) return null;

        return {
            id: chartId,
            config: chart.config,
            stats: chart.adapter.getStats()
        };
    }
}

// Export for use
window.ChartDataAdapter = ChartDataAdapter;
window.ChartDataManager = ChartDataManager;
