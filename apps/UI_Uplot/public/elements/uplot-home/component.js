/**
 * uPlot Chart Builder - Home Component
 * Displays chart type cards with data source selection
 */

class UPlotHomeComponent extends HTMLElement {
    constructor() {
        super();
        this.appConfig = null;
        this.logger = null;
    }

    async connectedCallback() {
        // Initialize console logger from app config
        await this.loadAppConfig();
        this.initializeLogger();

        this.logger.info('UPlot Home Component initialized');

        this.render();
        this.attachEventListeners();
    }

    async loadAppConfig() {
        try {
            const response = await fetch('/apps/uplot/api/v1/config');
            if (response.ok) {
                this.appConfig = await response.json();
            } else {
                console.warn('Failed to load app config, using defaults');
                this.appConfig = { settings: { ConsoleToAPILoggingLevel: 'info' } };
            }
        } catch (error) {
            console.error('Error loading app config:', error);
            this.appConfig = { settings: { ConsoleToAPILoggingLevel: 'info' } };
        }
    }

    initializeLogger() {
        const loggingLevel = this.appConfig?.settings?.ConsoleToAPILoggingLevel || 'info';

        // Check if ConsoleAPILogger is available
        if (typeof ConsoleAPILogger !== 'undefined') {
            this.logger = new ConsoleAPILogger('uplot', loggingLevel);
            this.logger.info(`Logging initialized at level: ${loggingLevel}`);
        } else {
            // Fallback to console with compatible interface
            this.logger = {
                info: (...args) => console.log('[uplot:info]', ...args),
                warn: (...args) => console.warn('[uplot:warn]', ...args),
                error: (...args) => console.error('[uplot:error]', ...args),
                debug: (...args) => console.debug('[uplot:debug]', ...args),
                verbose: (...args) => console.log('[uplot:verbose]', ...args)
            };
            console.log('[uplot:info] Logging initialized (fallback mode)');
        }
    }

    render() {
        this.innerHTML = `
            <div class="uplot-home-container">
                <header class="uplot-header">
                    <h1><i class="fas fa-chart-line"></i> uPlot Chart Builder</h1>
                    <p class="subtitle">High-performance interactive charts with multiple data source options</p>
                </header>

                <div class="chart-types-grid">
                    ${this.renderChartTypeCard('time-series', {
                        name: 'Time Series',
                        icon: 'chart-line',
                        description: 'Line charts for time-based data with real-time updates',
                        dataSources: ['rest-json', 'rest-csv', 'sql-js', 'metrics-db', 'static-json'],
                        useCases: ['Performance metrics', 'Server monitoring', 'Time-based trends'],
                        color: '#3b82f6'
                    })}

                    ${this.renderChartTypeCard('area-chart', {
                        name: 'Area Chart',
                        icon: 'chart-area',
                        description: 'Filled area charts for cumulative data visualization',
                        dataSources: ['rest-json', 'rest-csv', 'sql-js', 'metrics-db', 'static-json'],
                        useCases: ['Cumulative totals', 'Stacked metrics', 'Volume over time'],
                        color: '#10b981'
                    })}

                    ${this.renderChartTypeCard('bar-chart', {
                        name: 'Bar Chart',
                        icon: 'chart-bar',
                        description: 'Vertical or horizontal bars for categorical data comparison',
                        dataSources: ['rest-json', 'rest-csv', 'sql-js', 'static-json'],
                        useCases: ['Category comparison', 'Distribution analysis', 'Ranking data'],
                        color: '#8b5cf6'
                    })}

                    ${this.renderChartTypeCard('scatter-plot', {
                        name: 'Scatter Plot',
                        icon: 'circle',
                        description: 'Point-based plots for correlation and distribution analysis',
                        dataSources: ['rest-json', 'rest-csv', 'sql-js', 'static-json'],
                        useCases: ['Correlation analysis', 'Outlier detection', 'Data distribution'],
                        color: '#f59e0b'
                    })}

                    ${this.renderChartTypeCard('multi-axis', {
                        name: 'Multi-Axis Chart',
                        icon: 'chart-gantt',
                        description: 'Charts with multiple Y-axes for different value scales',
                        dataSources: ['rest-json', 'sql-js', 'metrics-db', 'static-json'],
                        useCases: ['Different unit types', 'Multi-metric comparison', 'Complex datasets'],
                        color: '#ef4444'
                    })}

                    ${this.renderChartTypeCard('heatmap', {
                        name: 'Heatmap',
                        icon: 'th',
                        description: 'Color-coded matrix visualization for density data',
                        dataSources: ['sql-js', 'static-json'],
                        useCases: ['Density maps', 'Matrix data', 'Pattern detection'],
                        color: '#ec4899'
                    })}
                </div>

                <!-- Chart Builder Modal -->
                <div id="chartBuilderModal" class="modal">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h2 id="modalTitle">Create Chart</h2>
                            <button class="close-button" onclick="this.closest('.modal').style.display='none'">
                                <i class="fas fa-times"></i>
                            </button>
                        </div>
                        <div class="modal-body">
                            ${this.renderChartBuilderForm()}
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderChartTypeCard(chartId, config) {
        const dataSourcesHtml = this.getDataSourcesList(config.dataSources);
        const useCasesHtml = config.useCases.map(useCase =>
            `<li><i class="fas fa-check-circle"></i> ${useCase}</li>`
        ).join('');

        return `
            <div class="chart-type-card" data-chart-type="${chartId}" style="border-top-color: ${config.color}">
                <div class="card-icon" style="color: ${config.color}">
                    <i class="fas fa-${config.icon}"></i>
                </div>
                <h3>${config.name}</h3>
                <p class="card-description">${config.description}</p>

                <div class="card-section">
                    <h4><i class="fas fa-database"></i> Supported Data Sources:</h4>
                    <div class="data-sources">
                        ${dataSourcesHtml}
                    </div>
                </div>

                <div class="card-section">
                    <h4><i class="fas fa-lightbulb"></i> Common Use Cases:</h4>
                    <ul class="use-cases">
                        ${useCasesHtml}
                    </ul>
                </div>

                <button class="create-chart-btn" data-chart-type="${chartId}" style="background-color: ${config.color}">
                    <i class="fas fa-plus-circle"></i> Create ${config.name}
                </button>
            </div>
        `;
    }

    getDataSourcesList(sources) {
        const sourceInfo = {
            'rest-json': { icon: 'cloud', label: 'REST API (JSON)', tooltip: 'Fetch JSON from HTTP endpoint' },
            'rest-csv': { icon: 'cloud', label: 'REST API (CSV)', tooltip: 'Fetch CSV from HTTP endpoint' },
            'sql-js': { icon: 'database', label: 'SQL.js Query', tooltip: 'Query in-browser SQLite database' },
            'metrics-db': { icon: 'chart-line', label: 'Metrics DB', tooltip: 'PSWebHost metrics database' },
            'static-json': { icon: 'file-code', label: 'Static JSON', tooltip: 'Paste or upload JSON data' },
            'upload-csv': { icon: 'file-upload', label: 'Upload CSV', tooltip: 'Upload CSV file' }
        };

        return sources.map(sourceId => {
            const info = sourceInfo[sourceId];
            return `
                <span class="data-source-badge" title="${info.tooltip}">
                    <i class="fas fa-${info.icon}"></i> ${info.label}
                </span>
            `;
        }).join('');
    }

    renderChartBuilderForm() {
        return `
            <form id="chartBuilderForm">
                <input type="hidden" id="selectedChartType" name="chartType">

                <div class="form-section">
                    <h3><i class="fas fa-cog"></i> Chart Configuration</h3>

                    <div class="form-group">
                        <label for="chartTitle">
                            <i class="fas fa-heading"></i> Chart Title:
                            <span class="help-text">Descriptive title for your chart</span>
                        </label>
                        <input type="text" id="chartTitle" name="title" placeholder="e.g., Server CPU Usage Over Time" required>
                    </div>

                    <div class="form-row">
                        <div class="form-group">
                            <label for="chartWidth">
                                <i class="fas fa-arrows-alt-h"></i> Width (px):
                            </label>
                            <input type="number" id="chartWidth" name="width" value="800" min="400" max="2000">
                        </div>
                        <div class="form-group">
                            <label for="chartHeight">
                                <i class="fas fa-arrows-alt-v"></i> Height (px):
                            </label>
                            <input type="number" id="chartHeight" name="height" value="400" min="200" max="1000">
                        </div>
                    </div>
                </div>

                <div class="form-section">
                    <h3><i class="fas fa-database"></i> Data Source Configuration</h3>

                    <div class="form-group">
                        <label for="dataSourceType">
                            <i class="fas fa-plug"></i> Select Data Source:
                            <span class="help-text">Choose how to provide data to the chart</span>
                        </label>
                        <select id="dataSourceType" name="dataSourceType" required>
                            <option value="">-- Select Data Source --</option>
                            <option value="rest-json">REST API (JSON) - Fetch data from HTTP endpoint</option>
                            <option value="rest-csv">REST API (CSV) - Fetch CSV from HTTP endpoint</option>
                            <option value="sql-js">SQL.js Query - Query in-browser SQLite database</option>
                            <option value="metrics-db">Metrics Database - PSWebHost metrics</option>
                            <option value="static-json">Static JSON - Paste JSON data directly</option>
                            <option value="upload-csv">Upload CSV - Upload CSV file</option>
                        </select>
                    </div>

                    <!-- Dynamic input areas for each data source type -->
                    <div id="dataSourceInputs"></div>
                </div>

                <div class="form-section">
                    <h3><i class="fas fa-sync"></i> Update Options</h3>

                    <div class="form-group">
                        <label class="checkbox-label">
                            <input type="checkbox" id="enableRealTime" name="enableRealTime">
                            <i class="fas fa-broadcast-tower"></i> Enable Real-Time Updates
                            <span class="help-text">Automatically refresh data at specified interval</span>
                        </label>
                    </div>

                    <div class="form-group" id="refreshIntervalGroup" style="display: none;">
                        <label for="refreshInterval">
                            <i class="fas fa-clock"></i> Refresh Interval (seconds):
                        </label>
                        <input type="number" id="refreshInterval" name="refreshInterval" value="5" min="1" max="300">
                    </div>
                </div>

                <div class="form-actions">
                    <button type="button" class="btn-secondary" onclick="this.closest('.modal').style.display='none'">
                        <i class="fas fa-times"></i> Cancel
                    </button>
                    <button type="submit" class="btn-primary">
                        <i class="fas fa-chart-line"></i> Create Chart
                    </button>
                </div>
            </form>
        `;
    }

    attachEventListeners() {
        // Create chart buttons
        this.querySelectorAll('.create-chart-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const chartType = e.currentTarget.dataset.chartType;
                this.openChartBuilder(chartType);
            });
        });

        // Data source type change
        const dataSourceSelect = this.querySelector('#dataSourceType');
        if (dataSourceSelect) {
            dataSourceSelect.addEventListener('change', (e) => {
                this.renderDataSourceInputs(e.target.value);
            });
        }

        // Real-time updates toggle
        const realTimeCheckbox = this.querySelector('#enableRealTime');
        if (realTimeCheckbox) {
            realTimeCheckbox.addEventListener('change', (e) => {
                const intervalGroup = this.querySelector('#refreshIntervalGroup');
                intervalGroup.style.display = e.target.checked ? 'block' : 'none';
            });
        }

        // Form submission
        const form = this.querySelector('#chartBuilderForm');
        if (form) {
            form.addEventListener('submit', (e) => {
                e.preventDefault();
                this.createChart();
            });
        }
    }

    openChartBuilder(chartType) {
        this.logger.info(`Opening chart builder for type: ${chartType}`);

        const modal = this.querySelector('#chartBuilderModal');
        const modalTitle = this.querySelector('#modalTitle');
        const chartTypeInput = this.querySelector('#selectedChartType');

        const chartNames = {
            'time-series': 'Time Series Chart',
            'area-chart': 'Area Chart',
            'bar-chart': 'Bar Chart',
            'scatter-plot': 'Scatter Plot',
            'multi-axis': 'Multi-Axis Chart',
            'heatmap': 'Heatmap'
        };

        modalTitle.textContent = `Create ${chartNames[chartType]}`;
        chartTypeInput.value = chartType;
        modal.style.display = 'flex';
    }

    renderDataSourceInputs(sourceType) {
        const container = this.querySelector('#dataSourceInputs');
        if (!container) return;

        this.logger.verbose(`Rendering data source inputs for: ${sourceType}`);

        const inputTemplates = {
            'rest-json': `
                <div class="data-source-inputs">
                    <div class="form-group">
                        <label for="restJsonUrl">
                            <i class="fas fa-link"></i> API Endpoint URL:
                            <span class="help-text">Full URL to JSON endpoint (must return array of objects)</span>
                        </label>
                        <input type="url" id="restJsonUrl" name="sourceUrl" placeholder="https://api.example.com/data" required>
                        <small class="input-hint">
                            Expected format: <code>[{"timestamp": 1234567890, "value1": 10, "value2": 20}, ...]</code>
                        </small>
                    </div>
                    <div class="form-group">
                        <label for="jsonHeaders">
                            <i class="fas fa-key"></i> Custom Headers (Optional):
                            <span class="help-text">JSON object with HTTP headers, e.g., {"Authorization": "Bearer token"}</span>
                        </label>
                        <textarea id="jsonHeaders" name="headers" placeholder='{"Authorization": "Bearer YOUR_TOKEN"}' rows="3"></textarea>
                    </div>
                </div>
            `,
            'rest-csv': `
                <div class="data-source-inputs">
                    <div class="form-group">
                        <label for="restCsvUrl">
                            <i class="fas fa-link"></i> CSV Endpoint URL:
                            <span class="help-text">URL to CSV file or endpoint returning CSV data</span>
                        </label>
                        <input type="url" id="restCsvUrl" name="sourceUrl" placeholder="https://example.com/data.csv" required>
                        <small class="input-hint">
                            Expected format: CSV with headers. First column should be timestamp or x-axis values.
                        </small>
                    </div>
                    <div class="form-group">
                        <label class="checkbox-label">
                            <input type="checkbox" id="csvHasHeaders" name="hasHeaders" checked>
                            CSV file has header row
                        </label>
                    </div>
                </div>
            `,
            'sql-js': `
                <div class="data-source-inputs">
                    <div class="form-group">
                        <label for="sqlQuery">
                            <i class="fas fa-database"></i> SQL Query:
                            <span class="help-text">SELECT query to fetch data from in-browser SQLite database</span>
                        </label>
                        <textarea id="sqlQuery" name="query" placeholder="SELECT timestamp, cpu_usage, memory_usage FROM metrics WHERE timestamp > ?" rows="5" required></textarea>
                        <small class="input-hint">
                            Query should return columns: timestamp (first column), followed by value columns.
                            Example: <code>SELECT time, value1, value2 FROM data ORDER BY time</code>
                        </small>
                    </div>
                    <div class="form-group">
                        <label for="sqlParams">
                            <i class="fas fa-sliders-h"></i> Query Parameters (Optional):
                            <span class="help-text">JSON array of parameters for prepared statement, e.g., [1234567890]</span>
                        </label>
                        <input type="text" id="sqlParams" name="params" placeholder='[1609459200]'>
                    </div>
                </div>
            `,
            'metrics-db': `
                <div class="data-source-inputs">
                    <div class="form-group">
                        <label for="metricName">
                            <i class="fas fa-chart-line"></i> Metric Name:
                            <span class="help-text">Name of metric to retrieve from PSWebHost metrics database</span>
                        </label>
                        <select id="metricName" name="metricName" required>
                            <option value="">-- Select Metric --</option>
                            <option value="cpu_usage">CPU Usage</option>
                            <option value="memory_usage">Memory Usage</option>
                            <option value="request_count">Request Count</option>
                            <option value="response_time">Response Time</option>
                            <option value="error_rate">Error Rate</option>
                        </select>
                    </div>
                    <div class="form-row">
                        <div class="form-group">
                            <label for="metricsTimeRange">
                                <i class="fas fa-calendar"></i> Time Range:
                            </label>
                            <select id="metricsTimeRange" name="timeRange">
                                <option value="1h">Last Hour</option>
                                <option value="6h">Last 6 Hours</option>
                                <option value="24h" selected>Last 24 Hours</option>
                                <option value="7d">Last 7 Days</option>
                                <option value="30d">Last 30 Days</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label for="metricsAggregation">
                                <i class="fas fa-compress"></i> Aggregation:
                            </label>
                            <select id="metricsAggregation" name="aggregation">
                                <option value="raw">Raw Data</option>
                                <option value="avg">Average</option>
                                <option value="sum">Sum</option>
                                <option value="min">Minimum</option>
                                <option value="max">Maximum</option>
                            </select>
                        </div>
                    </div>
                </div>
            `,
            'static-json': `
                <div class="data-source-inputs">
                    <div class="form-group">
                        <label for="staticJsonData">
                            <i class="fas fa-file-code"></i> JSON Data:
                            <span class="help-text">Paste JSON array of data objects</span>
                        </label>
                        <textarea id="staticJsonData" name="jsonData" placeholder='[{"timestamp": 1234567890, "value": 42}, ...]' rows="10" required></textarea>
                        <small class="input-hint">
                            Expected format: Array of objects with timestamp/x-value and data fields.<br>
                            Example: <code>[{"time": 1609459200, "cpu": 45.2, "mem": 60.1}, ...]</code>
                        </small>
                    </div>
                    <button type="button" class="btn-secondary" onclick="this.previousElementSibling.querySelector('textarea').value = JSON.stringify(JSON.parse(this.previousElementSibling.querySelector('textarea').value), null, 2)">
                        <i class="fas fa-align-left"></i> Format JSON
                    </button>
                </div>
            `,
            'upload-csv': `
                <div class="data-source-inputs">
                    <div class="form-group">
                        <label for="csvFileUpload">
                            <i class="fas fa-file-upload"></i> Upload CSV File:
                            <span class="help-text">Select CSV file from your computer (max 10MB)</span>
                        </label>
                        <input type="file" id="csvFileUpload" name="csvFile" accept=".csv,text/csv" required>
                        <small class="input-hint">
                            CSV should have headers. First column should be timestamp or x-axis values.
                        </small>
                    </div>
                    <div class="form-group">
                        <label class="checkbox-label">
                            <input type="checkbox" id="uploadCsvHasHeaders" name="hasHeaders" checked>
                            CSV file has header row
                        </label>
                    </div>
                    <div id="csvPreview" style="display: none;">
                        <h4>Preview:</h4>
                        <pre id="csvPreviewContent"></pre>
                    </div>
                </div>
            `
        };

        container.innerHTML = inputTemplates[sourceType] || '<p class="no-selection">Please select a data source type.</p>';

        // Attach file upload preview
        if (sourceType === 'upload-csv') {
            const fileInput = this.querySelector('#csvFileUpload');
            if (fileInput) {
                fileInput.addEventListener('change', (e) => this.previewCsvFile(e.target.files[0]));
            }
        }
    }

    async previewCsvFile(file) {
        if (!file) return;

        this.logger.verbose(`Previewing CSV file: ${file.name} (${file.size} bytes)`);

        const reader = new FileReader();
        reader.onload = (e) => {
            const text = e.target.result;
            const lines = text.split('\n').slice(0, 5); // First 5 lines
            const preview = this.querySelector('#csvPreviewContent');
            const previewContainer = this.querySelector('#csvPreview');

            if (preview && previewContainer) {
                preview.textContent = lines.join('\n') + '\n...';
                previewContainer.style.display = 'block';
            }
        };
        reader.readAsText(file);
    }

    async createChart() {
        const form = this.querySelector('#chartBuilderForm');
        const formData = new FormData(form);
        const chartConfig = Object.fromEntries(formData.entries());

        this.logger.info('Creating chart with config:', chartConfig);

        try {
            // Validate and prepare chart configuration
            const chartType = chartConfig.chartType;
            const dataSourceType = chartConfig.dataSourceType;

            // Build chart creation request
            const requestBody = {
                chartType: chartType,
                title: chartConfig.title,
                width: parseInt(chartConfig.width),
                height: parseInt(chartConfig.height),
                dataSource: {
                    type: dataSourceType,
                    config: this.buildDataSourceConfig(dataSourceType, chartConfig)
                },
                realTime: chartConfig.enableRealTime === 'on',
                refreshInterval: parseInt(chartConfig.refreshInterval) || 5
            };

            this.logger.verbose('Chart request body:', requestBody);

            // Send creation request to backend
            const response = await fetch('/apps/uplot/api/v1/charts/create', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestBody)
            });

            if (response.ok) {
                const result = await response.json();
                this.logger.info('Chart created successfully:', result);

                // Close modal
                this.querySelector('#chartBuilderModal').style.display = 'none';

                // Redirect to chart view
                window.location.href = `/apps/uplot/api/v1/ui/elements/${chartType}?chartId=${result.chartId}`;
            } else {
                const error = await response.text();
                this.logger.error('Failed to create chart:', error);
                alert(`Failed to create chart: ${error}`);
            }
        } catch (error) {
            this.logger.error('Error creating chart:', error);
            alert(`Error creating chart: ${error.message}`);
        }
    }

    buildDataSourceConfig(sourceType, formData) {
        const configs = {
            'rest-json': {
                url: formData.sourceUrl,
                headers: formData.headers ? JSON.parse(formData.headers) : {}
            },
            'rest-csv': {
                url: formData.sourceUrl,
                hasHeaders: formData.hasHeaders === 'on'
            },
            'sql-js': {
                query: formData.query,
                params: formData.params ? JSON.parse(formData.params) : []
            },
            'metrics-db': {
                metricName: formData.metricName,
                timeRange: formData.timeRange,
                aggregation: formData.aggregation
            },
            'static-json': {
                data: JSON.parse(formData.jsonData)
            },
            'upload-csv': {
                file: formData.csvFile,
                hasHeaders: formData.hasHeaders === 'on'
            }
        };

        return configs[sourceType] || {};
    }
}

// Register custom element
customElements.define('uplot-home-component', UPlotHomeComponent);

// Also register as a React component for SPA compatibility
if (typeof window.cardComponents !== 'undefined') {
    window.cardComponents['uplot-home'] = ({ element, url }) => {
        const React = window.React;
        const ref = React.useRef(null);

        React.useEffect(() => {
            if (ref.current && !ref.current.querySelector('uplot-home-component')) {
                const component = document.createElement('uplot-home-component');
                ref.current.appendChild(component);
            }
        }, []);

        return React.createElement('div', {
            ref: ref,
            style: { width: '100%', height: '100%', overflow: 'auto' }
        });
    };
}
