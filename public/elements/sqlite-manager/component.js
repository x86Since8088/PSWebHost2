/**
 * SQLite Manager Component
 * Database overview, table list, and database information
 *
 * Features:
 * - Database file detection and stats
 * - Table list with row counts
 * - Database metadata display
 * - Quick navigation to query editor
 */

const { useState, useEffect } = React;

const SqliteManagerCard = ({ onError }) => {
    const [dbInfo, setDbInfo] = useState(null);
    const [tables, setTables] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        let isMounted = true;

        const loadDatabaseInfo = async () => {
            try {
                setLoading(true);

                // Get database file info
                const dbFile = 'PsWebHost_Data/pswebhost.db';

                // Query to get all tables
                const tablesQuery = {
                    query: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
                };

                const tablesResponse = await window.psweb_fetchWithAuthHandling('/apps/sqlitemanager/api/v1/sqlite/query', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(tablesQuery)
                });

                if (!tablesResponse.ok) {
                    throw new Error(`Failed to fetch tables: ${tablesResponse.status}`);
                }

                const tablesData = await tablesResponse.json();

                if (tablesData.success && tablesData.rows) {
                    const tableList = tablesData.rows.map(row => row.name);

                    // Get row count for each table
                    const tableDetails = await Promise.all(
                        tableList.map(async (tableName) => {
                            try {
                                const countQuery = {
                                    query: `SELECT COUNT(*) as count FROM "${tableName}"`
                                };

                                const countResponse = await window.psweb_fetchWithAuthHandling('/apps/sqlitemanager/api/v1/sqlite/query', {
                                    method: 'POST',
                                    headers: {
                                        'Content-Type': 'application/json'
                                    },
                                    body: JSON.stringify(countQuery)
                                });

                                if (countResponse.ok) {
                                    const countData = await countResponse.json();
                                    const rowCount = countData.success && countData.rows && countData.rows.length > 0
                                        ? countData.rows[0].count
                                        : 0;

                                    return {
                                        name: tableName,
                                        rowCount: rowCount
                                    };
                                }
                            } catch (err) {
                                console.warn(`Failed to get row count for ${tableName}:`, err);
                            }

                            return {
                                name: tableName,
                                rowCount: 0
                            };
                        })
                    );

                    if (isMounted) {
                        setTables(tableDetails);
                        setDbInfo({
                            file: dbFile,
                            tableCount: tableList.length
                        });
                        setLoading(false);
                    }
                } else {
                    throw new Error(tablesData.error || 'Failed to retrieve tables');
                }

            } catch (err) {
                console.error('SQLite Manager error:', err);
                if (isMounted) {
                    setError(err.message);
                    setLoading(false);
                    if (onError) {
                        onError({ message: err.message });
                    }
                }
            }
        };

        loadDatabaseInfo();

        return () => {
            isMounted = false;
        };
    }, [onError]);

    const handleTableClick = (tableName) => {
        // Navigate to query editor with pre-filled SELECT query
        const query = `SELECT * FROM "${tableName}" LIMIT 100`;
        // Store query in sessionStorage for query editor to pick up
        sessionStorage.setItem('sqlite_query_buffer', query);
        // Navigate to query editor
        window.location.hash = '#/apps/sqlitemanager/cards/sqlite-query-editor';
    };

    const styles = `
        .sqlite-manager {
            padding: 1rem;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }

        .db-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 1.5rem;
            border-radius: 8px;
            margin-bottom: 1.5rem;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }

        .db-header h2 {
            margin: 0 0 0.5rem 0;
            font-size: 1.5rem;
            font-weight: 600;
        }

        .db-path {
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
            opacity: 0.9;
            margin-bottom: 0.5rem;
        }

        .db-stats {
            display: flex;
            gap: 1.5rem;
            margin-top: 1rem;
        }

        .stat-item {
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .stat-icon {
            font-size: 1.2rem;
        }

        .stat-label {
            font-size: 0.85rem;
            opacity: 0.9;
        }

        .stat-value {
            font-size: 1.2rem;
            font-weight: 600;
        }

        .tables-section {
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            overflow: hidden;
        }

        .section-header {
            background: #f8f9fa;
            padding: 1rem 1.5rem;
            border-bottom: 1px solid #e9ecef;
            font-weight: 600;
            font-size: 1.1rem;
            color: #495057;
        }

        .tables-list {
            max-height: 500px;
            overflow-y: auto;
        }

        .table-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 1rem 1.5rem;
            border-bottom: 1px solid #e9ecef;
            cursor: pointer;
            transition: background-color 0.2s;
        }

        .table-item:hover {
            background-color: #f8f9fa;
        }

        .table-item:last-child {
            border-bottom: none;
        }

        .table-name {
            font-family: 'Courier New', monospace;
            font-weight: 500;
            color: #495057;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .table-icon {
            color: #667eea;
        }

        .table-info {
            display: flex;
            align-items: center;
            gap: 1rem;
        }

        .row-count {
            color: #6c757d;
            font-size: 0.9rem;
        }

        .row-count-badge {
            background: #e9ecef;
            padding: 0.25rem 0.75rem;
            border-radius: 12px;
            font-size: 0.85rem;
            font-weight: 500;
        }

        .loading-spinner {
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 3rem;
            color: #6c757d;
        }

        .error-message {
            background: #fee;
            border: 1px solid #fcc;
            color: #c33;
            padding: 1rem;
            border-radius: 4px;
            margin: 1rem 0;
        }

        .empty-state {
            text-align: center;
            padding: 3rem;
            color: #6c757d;
        }

        .actions-bar {
            display: flex;
            gap: 1rem;
            margin-bottom: 1.5rem;
        }

        .btn {
            padding: 0.5rem 1rem;
            border: none;
            border-radius: 6px;
            font-size: 0.9rem;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            text-decoration: none;
            color: inherit;
        }

        .btn-primary {
            background: #667eea;
            color: white;
        }

        .btn-primary:hover {
            background: #5568d3;
            transform: translateY(-1px);
            box-shadow: 0 4px 8px rgba(102, 126, 234, 0.3);
        }

        .btn-secondary {
            background: #f8f9fa;
            color: #495057;
            border: 1px solid #dee2e6;
        }

        .btn-secondary:hover {
            background: #e9ecef;
        }

        @keyframes spin {
            to { transform: rotate(360deg); }
        }

        .spinner {
            display: inline-block;
            width: 2rem;
            height: 2rem;
            border: 3px solid rgba(0,0,0,0.1);
            border-left-color: #667eea;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
    `;

    if (loading) {
        return (
            <>
                <style>{styles}</style>
                <div className="sqlite-manager">
                    <div className="loading-spinner">
                        <div className="spinner"></div>
                        <span style={{marginLeft: '1rem'}}>Loading database information...</span>
                    </div>
                </div>
            </>
        );
    }

    if (error) {
        return (
            <>
                <style>{styles}</style>
                <div className="sqlite-manager">
                    <div className="error-message">
                        <strong>Error:</strong> {error}
                    </div>
                </div>
            </>
        );
    }

    return (
        <>
            <style>{styles}</style>
            <div className="sqlite-manager">
                {dbInfo && (
                    <div className="db-header">
                        <h2>SQLite Database Manager</h2>
                        <div className="db-path">
                            <span role="img" aria-label="database">🗄️</span> {dbInfo.file}
                        </div>
                        <div className="db-stats">
                            <div className="stat-item">
                                <span className="stat-icon">📊</span>
                                <div>
                                    <div className="stat-label">Tables</div>
                                    <div className="stat-value">{dbInfo.tableCount}</div>
                                </div>
                            </div>
                            <div className="stat-item">
                                <span className="stat-icon">📝</span>
                                <div>
                                    <div className="stat-label">Total Rows</div>
                                    <div className="stat-value">
                                        {tables.reduce((sum, t) => sum + t.rowCount, 0).toLocaleString()}
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                )}

                <div className="actions-bar">
                    <a href="#/apps/sqlitemanager/cards/sqlite-query-editor" className="btn btn-primary">
                        <span>⚡</span>
                        Query Editor
                    </a>
                    <button className="btn btn-secondary" onClick={() => window.location.reload()}>
                        <span>🔄</span>
                        Refresh
                    </button>
                </div>

                <div className="tables-section">
                    <div className="section-header">
                        Database Tables
                    </div>
                    <div className="tables-list">
                        {tables.length === 0 ? (
                            <div className="empty-state">
                                No tables found in database
                            </div>
                        ) : (
                            tables.map((table, index) => (
                                <div
                                    key={index}
                                    className="table-item"
                                    onClick={() => handleTableClick(table.name)}
                                    title={`Click to query ${table.name}`}
                                >
                                    <div className="table-name">
                                        <span className="table-icon">📋</span>
                                        {table.name}
                                    </div>
                                    <div className="table-info">
                                        <span className="row-count-badge">
                                            {table.rowCount.toLocaleString()} rows
                                        </span>
                                        <span style={{color: '#667eea'}}>→</span>
                                    </div>
                                </div>
                            ))
                        )}
                    </div>
                </div>
            </div>
        </>
    );
};

// Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['sqlite-manager'] = SqliteManagerCard;
