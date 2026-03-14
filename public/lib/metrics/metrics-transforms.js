/**
 * Metrics Transforms - Data transformation utilities
 *
 * Converts data between:
 * - Backend API responses (JSON/CSV) -> DuckDB insert format
 * - DuckDB query results -> uPlot chart format
 * - Various metric formats
 */

class MetricsTransforms {
    /**
     * Parse CSV string to array of row objects
     * @param {string} csvString - CSV data with header row
     * @param {string} [tableName] - Optional table name for context
     * @returns {Array<Object>} Array of row objects
     */
    static parseCSVToRows(csvString, tableName = null) {
        if (!csvString || typeof csvString !== 'string') {
            return [];
        }

        const lines = csvString.trim().split('\n');
        if (lines.length < 2) {
            return []; // Need at least header + 1 data row
        }

        // Parse header
        const headers = lines[0].split(',').map(h => h.trim().toLowerCase());

        // Parse data rows
        const rows = [];
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;

            const values = this._parseCSVLine(line);
            if (values.length !== headers.length) {
                console.warn(`[MetricsTransforms] Row ${i} has ${values.length} values, expected ${headers.length}`);
                continue;
            }

            const row = {};
            for (let j = 0; j < headers.length; j++) {
                const header = headers[j];
                let value = values[j];

                // Type conversion
                if (header === 'timestamp') {
                    // Keep as string for DuckDB TIMESTAMP
                    row[header] = value;
                } else if (this._isNumericColumn(header)) {
                    row[header] = parseFloat(value) || 0;
                } else {
                    row[header] = value;
                }
            }

            rows.push(row);
        }

        return rows;
    }

    /**
     * Parse a single CSV line handling quoted values
     * @private
     */
    static _parseCSVLine(line) {
        const values = [];
        let current = '';
        let inQuotes = false;

        for (let i = 0; i < line.length; i++) {
            const char = line[i];

            if (char === '"') {
                inQuotes = !inQuotes;
            } else if (char === ',' && !inQuotes) {
                values.push(current.trim());
                current = '';
            } else {
                current += char;
            }
        }
        values.push(current.trim());

        return values;
    }

    /**
     * Check if column name suggests numeric data
     * @private
     */
    static _isNumericColumn(name) {
        const numericPatterns = [
            'percent', 'total', 'used', 'free', 'bytes', 'mb', 'gb',
            'cpu', 'memory', 'disk', 'network', 'count', 'value',
            'min', 'max', 'avg', 'sum'
        ];
        const lowerName = name.toLowerCase();
        return numericPatterns.some(p => lowerName.includes(p));
    }

    /**
     * Convert metrics API response to DuckDB insert rows
     * @param {Object} metricsObject - Metrics object from API
     * @returns {Array<{table: string, data: Object}>} Array of table/data pairs
     */
    static metricsToInsertRows(metricsObject) {
        const rows = [];
        const timestamp = metricsObject.timestamp || new Date().toISOString();
        const hostname = metricsObject.hostname || 'local';

        // CPU metrics
        if (metricsObject.cpu) {
            const cpu = metricsObject.cpu;
            rows.push({
                table: 'cpu_metrics',
                data: {
                    timestamp,
                    hostname,
                    cpu_total: cpu.total ?? cpu.TotalPercent ?? cpu.AvgPercent ?? 0
                }
            });
        }

        // Memory metrics
        if (metricsObject.memory) {
            const mem = metricsObject.memory;
            rows.push({
                table: 'memory_metrics',
                data: {
                    timestamp,
                    hostname,
                    used_mb: (mem.used ?? mem.UsedGB ?? 0) * (mem.UsedGB ? 1024 : 1),
                    total_mb: (mem.total ?? mem.TotalGB ?? 0) * (mem.TotalGB ? 1024 : 1),
                    percent_used: mem.percent ?? mem.PercentUsed ?? 0
                }
            });
        }

        // Disk metrics (per drive)
        if (metricsObject.disk) {
            const disks = Array.isArray(metricsObject.disk) ? metricsObject.disk : Object.entries(metricsObject.disk);

            for (const disk of disks) {
                let drive, data;
                if (Array.isArray(disk)) {
                    [drive, data] = disk;
                } else {
                    drive = disk.drive ?? disk.name ?? disk.Drive ?? 'C:';
                    data = disk;
                }

                rows.push({
                    table: 'disk_metrics',
                    data: {
                        timestamp,
                        hostname,
                        drive: drive,
                        used_gb: data.used ?? data.UsedGB ?? 0,
                        total_gb: data.total ?? data.TotalGB ?? 0,
                        percent_used: data.percent ?? data.PercentUsed ?? 0
                    }
                });
            }
        }

        // Network metrics (per interface)
        if (metricsObject.network) {
            const networks = Array.isArray(metricsObject.network) ? metricsObject.network : Object.entries(metricsObject.network);

            for (const net of networks) {
                let iface, data;
                if (Array.isArray(net)) {
                    [iface, data] = net;
                } else {
                    iface = net.interface ?? net.name ?? net.AdapterName ?? 'eth0';
                    data = net;
                }

                rows.push({
                    table: 'network_metrics',
                    data: {
                        timestamp,
                        hostname,
                        interface: iface,
                        bytes_per_sec: data.bytes ?? data.KBPerSec ? (data.KBPerSec * 1024) : (data.BytesPerSec ?? 0)
                    }
                });
            }
        }

        return rows;
    }

    /**
     * Convert DuckDB chart query results to uPlot format
     * @param {Array<Object>} queryResults - Results from chart query
     * @returns {Object} { timestamps: Float64Array, values: Float64Array }
     */
    static chartDataToUplotFormat(queryResults) {
        if (!queryResults || queryResults.length === 0) {
            return {
                timestamps: new Float64Array(0),
                values: new Float64Array(0)
            };
        }

        const timestamps = new Float64Array(queryResults.length);
        const values = new Float64Array(queryResults.length);

        for (let i = 0; i < queryResults.length; i++) {
            const row = queryResults[i];

            // Convert timestamp to Unix seconds
            const ts = row.bucket_time || row.timestamp;
            timestamps[i] = new Date(ts).getTime() / 1000;

            // Get value
            values[i] = row.value ?? row.avg ?? row.cpu_total ?? row.percent_used ?? 0;
        }

        return { timestamps, values };
    }

    /**
     * Convert uPlot format to array for charting libraries
     * @param {Object} uplotData - { timestamps: Float64Array, values: Float64Array }
     * @returns {Array} [timestamps[], values[]]
     */
    static uplotToArrayFormat(uplotData) {
        return [
            Array.from(uplotData.timestamps),
            Array.from(uplotData.values)
        ];
    }

    /**
     * Convert query results to Chart.js format
     * @param {Array<Object>} queryResults - Query results
     * @param {Object} options - Chart options
     * @returns {Object} Chart.js dataset format
     */
    static toChartJSFormat(queryResults, options = {}) {
        const {
            label = 'Metric',
            borderColor = '#3b82f6',
            backgroundColor = 'rgba(59, 130, 246, 0.1)',
            fill = true
        } = options;

        const data = queryResults.map(row => ({
            x: new Date(row.bucket_time || row.timestamp),
            y: row.value ?? row.avg ?? 0
        }));

        return {
            datasets: [{
                label,
                data,
                borderColor,
                backgroundColor,
                fill,
                tension: 0.1
            }]
        };
    }

    /**
     * Merge multiple data arrays, deduplicating by timestamp
     * @param {Array<Array>} dataArrays - Arrays to merge
     * @returns {Array} Merged and sorted array
     */
    static mergeByTimestamp(dataArrays) {
        const byTimestamp = new Map();

        for (const arr of dataArrays) {
            for (const item of arr) {
                const ts = item.timestamp || item.bucket_time;
                if (ts && !byTimestamp.has(ts)) {
                    byTimestamp.set(ts, item);
                }
            }
        }

        return Array.from(byTimestamp.values())
            .sort((a, b) => new Date(a.timestamp || a.bucket_time) - new Date(b.timestamp || b.bucket_time));
    }

    /**
     * Downsample data to target number of points
     * @param {Array} data - Data array
     * @param {number} targetPoints - Target number of points
     * @returns {Array} Downsampled data
     */
    static downsample(data, targetPoints) {
        if (!data || data.length <= targetPoints) {
            return data;
        }

        const step = data.length / targetPoints;
        const result = [];

        for (let i = 0; i < targetPoints; i++) {
            const startIdx = Math.floor(i * step);
            const endIdx = Math.floor((i + 1) * step);

            // Take average of bucket
            let sum = 0;
            let count = 0;
            let timestamp = null;

            for (let j = startIdx; j < endIdx && j < data.length; j++) {
                const item = data[j];
                const value = item.value ?? item.cpu_total ?? item.percent_used ?? 0;
                sum += value;
                count++;
                if (!timestamp) {
                    timestamp = item.timestamp || item.bucket_time;
                }
            }

            if (count > 0) {
                result.push({
                    timestamp,
                    value: sum / count
                });
            }
        }

        return result;
    }
}

// Export for ES modules and global
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { MetricsTransforms };
}
if (typeof window !== 'undefined') {
    window.MetricsTransforms = MetricsTransforms;
}
