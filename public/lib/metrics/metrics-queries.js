/**
 * Metrics Queries - Safe parameterized query builders
 *
 * Provides query construction with:
 * - SQL injection prevention via whitelist validation
 * - Resolution-aware downsampling for charts
 * - Optimized time-bounded queries
 */

// Import schema validation (works in both browser and worker contexts)
// In browser: window.MetricsSchema
// In worker: importScripts will make it available

/**
 * Get schema validator (works in browser and worker)
 * @private
 */
function getSchema() {
    if (typeof window !== 'undefined' && window.MetricsSchema) {
        return window.MetricsSchema;
    }
    if (typeof MetricsSchema !== 'undefined') {
        return MetricsSchema;
    }
    // Fallback inline validation
    const ALLOWED_TABLES = ['cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];
    const ALLOWED_COLUMNS = ['timestamp', 'hostname', 'cpu_total', 'used_mb', 'total_mb', 'percent_used', 'drive', 'used_gb', 'total_gb', 'interface', 'bytes_per_sec'];
    return {
        validateTable: (t) => {
            if (!ALLOWED_TABLES.includes(t)) throw new Error(`Invalid table: ${t}`);
            return t;
        },
        validateColumn: (c) => {
            if (!ALLOWED_COLUMNS.includes(c)) throw new Error(`Invalid column: ${c}`);
            return c;
        }
    };
}

class MetricsQueries {
    /**
     * Calculate optimal bucket interval for downsampling based on time range and display width
     * @param {Date|string|number} startTime - Start of time range
     * @param {Date|string|number} endTime - End of time range
     * @param {number} pixelWidth - Chart width in pixels
     * @returns {string} SQL interval string (e.g., '1 minute', '5 seconds')
     */
    static calculateBucketInterval(startTime, endTime, pixelWidth = 800) {
        const start = new Date(startTime).getTime();
        const end = new Date(endTime).getTime();
        const rangeMs = end - start;

        // Target: ~2 data points per pixel for smooth rendering
        const targetPoints = pixelWidth * 2;
        const intervalMs = rangeMs / targetPoints;

        // Choose appropriate bucket size
        if (intervalMs < 5000) {
            return '1 second';
        } else if (intervalMs < 15000) {
            return '5 seconds';
        } else if (intervalMs < 30000) {
            return '15 seconds';
        } else if (intervalMs < 60000) {
            return '30 seconds';
        } else if (intervalMs < 300000) {
            return '1 minute';
        } else if (intervalMs < 900000) {
            return '5 minutes';
        } else if (intervalMs < 1800000) {
            return '15 minutes';
        } else if (intervalMs < 3600000) {
            return '30 minutes';
        } else {
            return '1 hour';
        }
    }

    /**
     * Calculate strftime format for grouping (DuckDB compatible)
     * @param {Date|string|number} startTime
     * @param {Date|string|number} endTime
     * @param {number} pixelWidth
     * @returns {string} strftime format string
     */
    static calculateStrftimeFormat(startTime, endTime, pixelWidth = 800) {
        const start = new Date(startTime).getTime();
        const end = new Date(endTime).getTime();
        const rangeMs = end - start;
        const targetPoints = pixelWidth * 2;
        const intervalMs = rangeMs / targetPoints;

        if (intervalMs < 60000) {
            // Per second
            return '%Y-%m-%d %H:%M:%S';
        } else if (intervalMs < 3600000) {
            // Per minute
            return '%Y-%m-%d %H:%M:00';
        } else {
            // Per hour
            return '%Y-%m-%d %H:00:00';
        }
    }

    /**
     * Build a chart query with downsampling
     * @param {Object} options - Query options
     * @param {string} options.table - Table name (validated against whitelist)
     * @param {string} options.column - Value column name (validated)
     * @param {Date|string} options.startTime - Start timestamp
     * @param {Date|string} options.endTime - End timestamp
     * @param {number} [options.pixelWidth=800] - Chart width for downsampling
     * @param {string} [options.hostname] - Optional hostname filter
     * @param {string} [options.drive] - Optional drive filter (for disk_metrics)
     * @param {string} [options.interface] - Optional interface filter (for network_metrics)
     * @returns {Object} { sql: string, params: any[] }
     */
    static buildChartQuery(options) {
        const schema = getSchema();
        const { table, column, startTime, endTime, pixelWidth = 800, hostname, drive, interface: iface } = options;

        // Validate identifiers
        const validTable = schema.validateTable(table);
        const validColumn = schema.validateColumn(column);

        // Calculate bucket format
        const strftimeFormat = this.calculateStrftimeFormat(startTime, endTime, pixelWidth);

        // Build WHERE clause
        const conditions = ['timestamp >= ? AND timestamp <= ?'];
        const params = [new Date(startTime).toISOString(), new Date(endTime).toISOString()];

        if (hostname) {
            conditions.push('hostname = ?');
            params.push(hostname);
        }
        if (drive && validTable === 'disk_metrics') {
            conditions.push('drive = ?');
            params.push(drive);
        }
        if (iface && validTable === 'network_metrics') {
            conditions.push('interface = ?');
            params.push(iface);
        }

        const sql = `
            SELECT
                strftime(timestamp, '${strftimeFormat}') AS bucket_time,
                AVG(${validColumn}) AS value,
                MIN(${validColumn}) AS min_value,
                MAX(${validColumn}) AS max_value,
                COUNT(*) AS sample_count
            FROM ${validTable}
            WHERE ${conditions.join(' AND ')}
            GROUP BY bucket_time
            ORDER BY bucket_time ASC
        `;

        return { sql: sql.trim(), params };
    }

    /**
     * Build an INSERT query for metrics data
     * @param {string} table - Table name
     * @param {Object} data - Data to insert
     * @returns {Object} { sql: string, params: any[] }
     */
    static buildInsertQuery(table, data) {
        const schema = getSchema();
        const validTable = schema.validateTable(table);

        const columns = [];
        const placeholders = [];
        const params = [];

        // Always include timestamp
        if (!data.timestamp) {
            data.timestamp = new Date().toISOString();
        }

        for (const [key, value] of Object.entries(data)) {
            const validColumn = schema.validateColumn(key);
            columns.push(validColumn);
            placeholders.push('?');
            params.push(value);
        }

        const sql = `
            INSERT INTO ${validTable} (${columns.join(', ')})
            VALUES (${placeholders.join(', ')})
            ON CONFLICT DO UPDATE SET ${columns.map(c => `${c} = EXCLUDED.${c}`).join(', ')}
        `;

        return { sql: sql.trim(), params };
    }

    /**
     * Build a batch INSERT query
     * @param {string} table - Table name
     * @param {Array<Object>} rows - Array of data objects
     * @returns {Object} { sql: string, params: any[][] }
     */
    static buildBatchInsertQuery(table, rows) {
        if (!rows || rows.length === 0) {
            return { sql: null, params: [] };
        }

        const schema = getSchema();
        const validTable = schema.validateTable(table);

        // Get columns from first row
        const firstRow = rows[0];
        const columns = Object.keys(firstRow).map(k => schema.validateColumn(k));

        const placeholders = columns.map(() => '?').join(', ');
        const valueRows = [];
        const allParams = [];

        for (const row of rows) {
            valueRows.push(`(${placeholders})`);
            for (const col of columns) {
                allParams.push(row[col] ?? null);
            }
        }

        const sql = `
            INSERT INTO ${validTable} (${columns.join(', ')})
            VALUES ${valueRows.join(', ')}
            ON CONFLICT DO NOTHING
        `;

        return { sql: sql.trim(), params: allParams };
    }

    /**
     * Build a PRUNE (delete old records) query
     * @param {string} table - Table name (or 'all' for all tables)
     * @param {number} retentionHours - Keep records newer than this many hours
     * @returns {Object} { sql: string, params: any[] }
     */
    static buildPruneQuery(table, retentionHours) {
        const cutoff = new Date(Date.now() - retentionHours * 60 * 60 * 1000).toISOString();

        if (table === 'all') {
            // Return array of queries for all tables
            const tables = ['cpu_metrics', 'memory_metrics', 'disk_metrics', 'network_metrics'];
            return tables.map(t => ({
                sql: `DELETE FROM ${t} WHERE timestamp < ?`,
                params: [cutoff]
            }));
        }

        const schema = getSchema();
        const validTable = schema.validateTable(table);

        return {
            sql: `DELETE FROM ${validTable} WHERE timestamp < ?`,
            params: [cutoff]
        };
    }

    /**
     * Build a simple SELECT query
     * @param {string} table - Table name
     * @param {Object} [options] - Query options
     * @param {string} [options.orderBy='timestamp'] - Order by column
     * @param {string} [options.order='DESC'] - ASC or DESC
     * @param {number} [options.limit] - Max rows to return
     * @returns {Object} { sql: string, params: any[] }
     */
    static buildSelectQuery(table, options = {}) {
        const schema = getSchema();
        const validTable = schema.validateTable(table);

        const { orderBy = 'timestamp', order = 'DESC', limit } = options;
        const validOrderBy = schema.validateColumn(orderBy);
        const validOrder = order.toUpperCase() === 'ASC' ? 'ASC' : 'DESC';

        let sql = `SELECT * FROM ${validTable} ORDER BY ${validOrderBy} ${validOrder}`;

        if (limit && Number.isInteger(limit) && limit > 0) {
            sql += ` LIMIT ${limit}`;
        }

        return { sql, params: [] };
    }

    /**
     * Build a COUNT query
     * @param {string} table - Table name
     * @returns {Object} { sql: string, params: any[] }
     */
    static buildCountQuery(table) {
        const schema = getSchema();
        const validTable = schema.validateTable(table);

        return {
            sql: `SELECT COUNT(*) as count FROM ${validTable}`,
            params: []
        };
    }
}

// Export for ES modules and global
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { MetricsQueries };
}
if (typeof window !== 'undefined') {
    window.MetricsQueries = MetricsQueries;
}
