const { useState, useMemo } = React;

const SortableTable = ({ data, columns }) => {
    const [sortConfig, setSortConfig] = useState({ key: null, direction: 'ascending' });
    const [filter, setFilter] = useState('');

    const sortedData = useMemo(() => {
        let sortableData = [...data];
        if (sortConfig.key !== null) {
            sortableData.sort((a, b) => {
                if (a[sortConfig.key] < b[sortConfig.key]) {
                    return sortConfig.direction === 'ascending' ? -1 : 1;
                }
                if (a[sortConfig.key] > b[sortConfig.key]) {
                    return sortConfig.direction === 'ascending' ? 1 : -1;
                }
                return 0;
            });
        }
        return sortableData;
    }, [data, sortConfig]);

    const filteredData = useMemo(() => {
        const lowerCaseFilter = filter.toLowerCase();
        return sortedData.filter(item => {
            return Object.values(item).some(val =>
                String(val).toLowerCase().includes(lowerCaseFilter)
            );
        });
    }, [sortedData, filter]);

    const requestSort = (key) => {
        let direction = 'ascending';
        if (sortConfig.key === key && sortConfig.direction === 'ascending') {
            direction = 'descending';
        }
        setSortConfig({ key, direction });
    };

    const getClassNamesFor = (name) => {
        if (!sortConfig) {
            return;
        }
        return sortConfig.key === name ? sortConfig.direction : undefined;
    };

    const styles = `
        .generic-table {
            width: 100%;
            border-collapse: collapse;
        }
        .generic-table th, .generic-table td {
            border: 1px solid #ddd;
            padding: 4px;
        }
        .generic-table th {
            padding-top: 2px;
            padding-bottom: 3px;
            text-align: left;
            background-color: #7d7b7bff;
            cursor: pointer;
        }
        .generic-table .ascending::after {
            content: ' ▲';
        }
        .generic-table .descending::after {
            content: ' ▼';
        }
    `;

    return (
        <>
            <style>{styles}</style>
            <div>
                <input
                    type="text"
                    placeholder="Filter..."
                    value={filter}
                    onChange={(e) => setFilter(e.target.value)}
                    style={{ marginBottom: '3px', padding: '2px' }}
                />
                <table className="generic-table">
                    <thead>
                        <tr>
                            {columns.map((col) => (
                                <th
                                    key={col.key}
                                    onClick={() => requestSort(col.key)}
                                    className={getClassNamesFor(col.key)}
                                >
                                    {col.label}
                                </th>
                            ))}
                        </tr>
                    </thead>
                    <tbody>
                        {filteredData.map((item, index) => (
                            <tr key={index}>
                                {columns.map((col) => (
                                    <td key={col.key}>{item[col.key]}</td>
                                ))}
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </>
    );
};
