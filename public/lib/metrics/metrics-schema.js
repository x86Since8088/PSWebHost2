/**
 * Metrics Schema - Table definitions and SQL injection prevention
 *
 * Centralizes all table schemas for metrics storage and provides
 * validation functions to prevent SQL injection attacks.
 *
 * Tables:
 * - cpu_metrics: CPU usage over time
 * - memory_metrics: Memory usage over time
 * - disk_metrics: Disk usage per drive over time
 * - network_metrics: Network throughput per interface over time
 */

// Table schema definitions
const SCHEMAS = {
    cpu_metrics: `
        CREATE TABLE IF NOT EXISTS cpu_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            cpu_total DOUBLE,
            PRIMARY KEY (timestamp, hostname)
        )
    `,
    memory_metrics: `
        CREATE TABLE IF NOT EXISTS memory_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            used_mb DOUBLE,
            total_mb DOUBLE,
            percent_used DOUBLE,
            PRIMARY KEY (timestamp, hostname)
        )
    `,
    disk_metrics: `
        CREATE TABLE IF NOT EXISTS disk_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            drive VARCHAR,
            used_gb DOUBLE,
            total_gb DOUBLE,
            percent_used DOUBLE,
            PRIMARY KEY (timestamp, hostname, drive)
        )
    `,
    network_metrics: `
        CREATE TABLE IF NOT EXISTS network_metrics (
            timestamp TIMESTAMP NOT NULL,
            hostname VARCHAR DEFAULT 'local',
            interface VARCHAR,
            bytes_per_sec DOUBLE,
            PRIMARY KEY (timestamp, hostname, interface)
        )
    `
};

// Whitelist of allowed table names (for SQL injection prevention)
const ALLOWED_TABLES = Object.keys(SCHEMAS);

// Whitelist of allowed column names for queries
const ALLOWED_COLUMNS = [
    'timestamp',
    'hostname',
    'cpu_total',
    'used_mb',
    'total_mb',
    'percent_used',
    'drive',
    'used_gb',
    'total_gb',
    'interface',
    'bytes_per_sec'
];

// Value columns by table (for chart queries)
const VALUE_COLUMNS = {
    cpu_metrics: ['cpu_total'],
    memory_metrics: ['used_mb', 'total_mb', 'percent_used'],
    disk_metrics: ['used_gb', 'total_gb', 'percent_used'],
    network_metrics: ['bytes_per_sec']
};

/**
 * Validate table name against whitelist
 * @param {string} tableName - Table name to validate
 * @throws {Error} If table name is invalid
 * @returns {string} Validated table name
 */
function validateTable(tableName) {
    if (!tableName || typeof tableName !== 'string') {
        throw new Error('Table name must be a non-empty string');
    }
    const normalized = tableName.toLowerCase().trim();
    if (!ALLOWED_TABLES.includes(normalized)) {
        throw new Error(`Invalid table name: ${tableName}. Allowed: ${ALLOWED_TABLES.join(', ')}`);
    }
    return normalized;
}

/**
 * Validate column name against whitelist
 * @param {string} columnName - Column name to validate
 * @throws {Error} If column name is invalid
 * @returns {string} Validated column name
 */
function validateColumn(columnName) {
    if (!columnName || typeof columnName !== 'string') {
        throw new Error('Column name must be a non-empty string');
    }
    const normalized = columnName.toLowerCase().trim();
    if (!ALLOWED_COLUMNS.includes(normalized)) {
        throw new Error(`Invalid column name: ${columnName}. Allowed: ${ALLOWED_COLUMNS.join(', ')}`);
    }
    return normalized;
}

/**
 * Validate value column for a specific table
 * @param {string} tableName - Table name
 * @param {string} columnName - Column name
 * @throws {Error} If column is not valid for the table
 * @returns {string} Validated column name
 */
function validateValueColumn(tableName, columnName) {
    const table = validateTable(tableName);
    const column = validateColumn(columnName);

    const validColumns = VALUE_COLUMNS[table];
    if (!validColumns || !validColumns.includes(column)) {
        throw new Error(`Column '${column}' is not a value column for table '${table}'. Valid: ${validColumns?.join(', ') || 'none'}`);
    }
    return column;
}

/**
 * Get schema SQL for a table
 * @param {string} tableName - Table name
 * @returns {string} CREATE TABLE SQL
 */
function getSchema(tableName) {
    const table = validateTable(tableName);
    return SCHEMAS[table];
}

/**
 * Create all tables in the database
 * @param {Object} conn - DuckDB connection (or object with exec method)
 * @returns {Promise<void>}
 */
async function createAllTables(conn) {
    console.log('[MetricsSchema] Creating all tables...');

    for (const [tableName, schema] of Object.entries(SCHEMAS)) {
        try {
            if (conn.query) {
                // DuckDB async connection
                await conn.query(schema);
            } else if (conn.exec) {
                // Legacy exec method
                conn.exec(schema);
            } else {
                throw new Error('Connection must have query() or exec() method');
            }
            console.log(`[MetricsSchema] Created table: ${tableName}`);
        } catch (err) {
            console.error(`[MetricsSchema] Failed to create table ${tableName}:`, err);
            throw err;
        }
    }

    console.log('[MetricsSchema] All tables created successfully');
}

/**
 * Get list of all table names
 * @returns {string[]}
 */
function getTableNames() {
    return [...ALLOWED_TABLES];
}

/**
 * Get value columns for a table
 * @param {string} tableName - Table name
 * @returns {string[]} Value column names
 */
function getValueColumns(tableName) {
    const table = validateTable(tableName);
    return [...(VALUE_COLUMNS[table] || [])];
}

// Export for ES modules and global
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        SCHEMAS,
        ALLOWED_TABLES,
        ALLOWED_COLUMNS,
        VALUE_COLUMNS,
        validateTable,
        validateColumn,
        validateValueColumn,
        getSchema,
        createAllTables,
        getTableNames,
        getValueColumns
    };
}
if (typeof window !== 'undefined') {
    window.MetricsSchema = {
        SCHEMAS,
        ALLOWED_TABLES,
        ALLOWED_COLUMNS,
        VALUE_COLUMNS,
        validateTable,
        validateColumn,
        validateValueColumn,
        getSchema,
        createAllTables,
        getTableNames,
        getValueColumns
    };
}
