/**
 * uPlot Scatter Plot Component
 * Scatter plots for correlation and distribution visualization
 */

class ScatterPlotComponent extends HTMLElement {
    constructor() {
        super();
        this.chart = null;
        this.adapter = null;
        this.logger = null;
        this.chartId = null;
        this.chartConfig = null;
        this.refreshTimer = null;
    }

    async connectedCallback() {
        // Get chartId from URL params
        const params = new URLSearchParams(window.location.search);
        this.chartId = params.get('chartId');

        if (!this.chartId) {
            this.renderError('No chart ID provided');
            return;
        }

        // Initialize logger
        await this.loadAppConfig();
        this.initializeLogger();

        this.logger.info(`Scatter Plot Component loaded for chart: ${this.chartId}`);

        // Load chart configuration
        await this.loadChartConfig();

        // Load required libraries
        await this.loadLibraries();

        // Initialize chart
        this.initializeChart();
    }

    async loadAppConfig() {
        try {
            const response = await fetch('/apps/uplot/api/v1/config');
            if (response.ok) {
                this.appConfig = await response.json();
            } else {
                this.appConfig = { settings: { ConsoleToAPILoggingLevel: 'info' } };
            }
        } catch (error) {
            console.error('Error loading app config:', error);
            this.appConfig = { settings: { ConsoleToAPILoggingLevel: 'info' } };
        }
    }

    initializeLogger() {
        const loggingLevel = this.appConfig?.settings?.ConsoleToAPILoggingLevel || 'info';
        if (typeof ConsoleAPILogger !== 'undefined') {
            this.logger = new ConsoleAPILogger('uplot', loggingLevel);
        } else {
            this.logger = { info: (...args) => console.log('[scatter-plot:info]', ...args), warn: (...args) => console.warn('[scatter-plot:warn]', ...args), error: (...args) => console.error('[scatter-plot:error]', ...args), debug: (...args) => console.debug('[scatter-plot:debug]', ...args), verbose: (...args) => console.log('[scatter-plot:verbose]', ...args) };
        }
    }

    async loadChartConfig() {
        try {
            const params = new URLSearchParams(window.location.search);

            this.chartConfig = {
                chartId: this.chartId,
                chartType: 'scatter-plot',
                title: params.get('title') || 'Scatter Plot',
                width: parseInt(params.get('width')) || 800,
                height: parseInt(params.get('height')) || 400,
                pointSize: parseInt(params.get('pointSize')) || 6,
                showTrendLine: params.get('trendLine') === 'true',
                dataSource: {
                    type: params.get('source') || 'metrics-db',
                    config: this.parseDataSourceConfig(params)
                },
                realTime: params.get('realtime') === 'true',
                refreshInterval: parseInt(params.get('delay')) || 5
            };

            this.logger.verbose('Chart configuration loaded:', this.chartConfig);

        } catch (error) {
            this.logger.error('Failed to load chart configuration:', error);
            this.renderError('Failed to load chart configuration: ' + error.message);
        }
    }

    parseDataSourceConfig(params) {
        const sourceType = params.get('source') || 'metrics-db';

        switch (sourceType) {
            case 'rest-json':
                return {
                    url: params.get('url'),
                    headers: params.get('headers') ? JSON.parse(params.get('headers')) : {}
                };

            case 'rest-csv':
                return {
                    url: params.get('url'),
                    hasHeaders: params.get('hasHeaders') !== 'false'
                };

            case 'metrics-db':
                return {
                    metricName: params.get('metric') || 'correlation_data',
                    timeRange: params.get('timeRange') || '24h',
                    aggregation: params.get('aggregation') || 'raw'
                };

            case 'sql-js':
                return {
                    query: params.get('query'),
                    params: params.get('queryParams') ? JSON.parse(params.get('queryParams')) : []
                };

            default:
                return {};
        }
    }

    async loadLibraries() {
        // Load uPlot library
        if (typeof uPlot === 'undefined') {
            await this.loadScript('/public/lib/uPlot.iife.min.js');
            await this.loadStylesheet('/public/lib/uPlot.min.css');
        }

        // Load uPlot data adapter
        if (typeof UPlotDataAdapter === 'undefined') {
            await this.loadScript('/public/lib/uplot-data-adapter.js');
        }

        this.logger.verbose('Libraries loaded successfully');
    }

    loadScript(src) {
        return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = src;
            script.onload = resolve;
            script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
            document.head.appendChild(script);
        });
    }

    loadStylesheet(href) {
        return new Promise((resolve, reject) => {
            const link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = href;
            link.onload = resolve;
            link.onerror = () => reject(new Error(`Failed to load stylesheet: ${href}`));
            document.head.appendChild(link);
        });
    }

    async initializeChart() {
        this.logger.info('Initializing scatter plot');

        // Render chart container
        this.renderChartContainer();

        // Fetch initial data
        const initialData = await this.fetchData();

        if (!initialData) {
            this.renderError('Failed to fetch chart data');
            return;
        }

        // Create uPlot instance
        const container = this.querySelector('#chartContainer');

        const opts = {
            title: this.chartConfig.title,
            width: this.chartConfig.width,
            height: this.chartConfig.height,
            series: this.buildSeriesConfig(initialData.metadata),
            axes: [
                {
                    // X-axis
                    space: 80,
                    values: (u, vals) => vals.map(v => v.toFixed(2))
                },
                {
                    // Y-axis
                    space: 50,
                    values: (u, vals) => vals.map(v => v.toFixed(2))
                }
            ],
            scales: {
                x: {
                    time: false
                }
            },
            legend: {
                show: true
            },
            cursor: {
                drag: {
                    x: true,
                    y: true
                },
                points: {
                    size: (u, seriesIdx) => this.chartConfig.pointSize * 1.5,
                    width: (u, seriesIdx, size) => size / 4,
                    stroke: (u, seriesIdx) => u.series[seriesIdx].stroke + '80',
                    fill: (u, seriesIdx) => '#fff'
                }
            }
        };

        this.chart = new uPlot(opts, initialData.data, container);
        this.logger.info('Scatter plot created successfully');

        // Add trend line if enabled
        if (this.chartConfig.showTrendLine) {
            this.addTrendLine(initialData.data);
        }

        // Create data adapter for real-time updates
        if (this.chartConfig.realTime) {
            this.adapter = new UPlotDataAdapter(
                this.chart,
                this.chartConfig.width,
                this.chartConfig.refreshInterval * 1000
            );

            this.startRealTimeUpdates();
        }
    }

    buildSeriesConfig(metadata) {
        const series = [
            {
                // X-axis series
                label: metadata?.xAxisLabel || 'X Values'
            }
        ];

        // Add scatter series with visible points and no lines
        const seriesLabels = metadata?.seriesLabels || ['Points'];
        const colors = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899'];

        seriesLabels.forEach((label, index) => {
            const color = colors[index % colors.length];

            series.push({
                label: label,
                stroke: color,
                width: 0, // No line connecting points
                fill: color,

                // Show points prominently
                points: {
                    show: true,
                    size: this.chartConfig.pointSize,
                    width: 1,
                    stroke: color,
                    fill: color + 'cc' // Add transparency
                }
            });
        });

        // Add trend line series if enabled
        if (this.chartConfig.showTrendLine) {
            series.push({
                label: 'Trend Line',
                stroke: '#9ca3af',
                width: 2,
                dash: [10, 5],
                points: {
                    show: false
                }
            });
        }

        return series;
    }

    addTrendLine(data) {
        if (!data || data.length < 2) return;

        const xData = data[0];
        const yData = data[1];

        // Calculate linear regression
        const n = xData.length;
        let sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;

        for (let i = 0; i < n; i++) {
            sumX += xData[i];
            sumY += yData[i];
            sumXY += xData[i] * yData[i];
            sumXX += xData[i] * xData[i];
        }

        const slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
        const intercept = (sumY - slope * sumX) / n;

        // Generate trend line points
        const trendLineY = xData.map(x => slope * x + intercept);

        // Append trend line data
        data.push(trendLineY);

        this.logger.verbose(`Trend line added: y = ${slope.toFixed(4)}x + ${intercept.toFixed(4)}`);
    }

    async fetchData() {
        try {
            const dataSource = this.chartConfig.dataSource;
            const endpoint = this.getDataEndpoint(dataSource.type);

            this.logger.verbose(`Fetching data from: ${endpoint}`);

            const response = await fetch(endpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(dataSource.config)
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const result = await response.json();

            if (!result.success) {
                throw new Error(result.error || 'Data fetch failed');
            }

            this.logger.verbose(`Fetched ${result.metadata?.dataPoints || 0} data points`);

            return result;

        } catch (error) {
            this.logger.error('Data fetch error:', error);
            return null;
        }
    }

    getDataEndpoint(sourceType) {
        const endpoints = {
            'rest-json': '/apps/uplot/api/v1/data/json',
            'rest-csv': '/apps/uplot/api/v1/data/csv',
            'sql-js': '/apps/uplot/api/v1/data/sql',
            'metrics-db': '/apps/uplot/api/v1/data/metrics'
        };

        return endpoints[sourceType] || endpoints['metrics-db'];
    }

    startRealTimeUpdates() {
        this.logger.info(`Starting real-time updates (interval: ${this.chartConfig.refreshInterval}s)`);

        this.refreshTimer = setInterval(async () => {
            const newData = await this.fetchData();

            if (newData && this.chart) {
                if (this.chartConfig.showTrendLine) {
                    this.addTrendLine(newData.data);
                }
                this.chart.setData(newData.data);
                this.logger.verbose('Chart data updated');
            }
        }, this.chartConfig.refreshInterval * 1000);
    }

    stopRealTimeUpdates() {
        if (this.refreshTimer) {
            clearInterval(this.refreshTimer);
            this.refreshTimer = null;
            this.logger.info('Real-time updates stopped');
        }
    }

    renderChartContainer() {
        this.innerHTML = `
            <div class="scatter-plot-container">
                <div class="chart-header">
                    <h2>${this.chartConfig.title}</h2>
                    <div class="chart-controls">
                        ${this.chartConfig.realTime ? `
                            <button id="pauseBtn" class="control-btn">
                                <i class="fas fa-pause"></i> Pause
                            </button>
                        ` : ''}
                        <button id="refreshBtn" class="control-btn">
                            <i class="fas fa-sync"></i> Refresh
                        </button>
                        <button id="exportBtn" class="control-btn">
                            <i class="fas fa-download"></i> Export
                        </button>
                    </div>
                </div>
                <div id="chartContainer"></div>
                <div class="chart-footer">
                    <span class="data-source-info">
                        <i class="fas fa-database"></i> Source: ${this.chartConfig.dataSource.type}
                    </span>
                    <span class="chart-type-info">
                        <i class="fas fa-braille"></i> Point size: ${this.chartConfig.pointSize}px
                        ${this.chartConfig.showTrendLine ? '<i class="fas fa-chart-line"></i> with trend line' : ''}
                    </span>
                    ${this.chartConfig.realTime ? `
                        <span class="realtime-indicator">
                            <i class="fas fa-circle pulse"></i> Live
                        </span>
                    ` : ''}
                </div>
            </div>
        `;

        // Attach event listeners
        this.attachControlListeners();
    }

    attachControlListeners() {
        const pauseBtn = this.querySelector('#pauseBtn');
        if (pauseBtn) {
            pauseBtn.addEventListener('click', () => this.togglePause());
        }

        const refreshBtn = this.querySelector('#refreshBtn');
        if (refreshBtn) {
            refreshBtn.addEventListener('click', () => this.refreshData());
        }

        const exportBtn = this.querySelector('#exportBtn');
        if (exportBtn) {
            exportBtn.addEventListener('click', () => this.exportData());
        }
    }

    togglePause() {
        const pauseBtn = this.querySelector('#pauseBtn');

        if (this.refreshTimer) {
            this.stopRealTimeUpdates();
            pauseBtn.innerHTML = '<i class="fas fa-play"></i> Resume';
        } else {
            this.startRealTimeUpdates();
            pauseBtn.innerHTML = '<i class="fas fa-pause"></i> Pause';
        }
    }

    async refreshData() {
        this.logger.info('Manual refresh triggered');

        const newData = await this.fetchData();

        if (newData && this.chart) {
            if (this.chartConfig.showTrendLine) {
                this.addTrendLine(newData.data);
            }
            this.chart.setData(newData.data);
            this.logger.info('Chart refreshed successfully');
        }
    }

    exportData() {
        this.logger.info('Exporting chart data');

        if (!this.chart) return;

        const data = this.chart.data;
        const csv = this.convertToCSV(data);

        // Download CSV
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `${this.chartConfig.title.replace(/\s+/g, '_')}_${Date.now()}.csv`;
        a.click();
        URL.revokeObjectURL(url);

        this.logger.info('Data exported successfully');
    }

    convertToCSV(data) {
        if (!data || data.length === 0) return '';

        const xValues = data[0];
        const series = data.slice(1);

        // Header row
        let csv = 'X,' + series.map((_, i) => `Series${i + 1}`).join(',') + '\n';

        // Data rows
        for (let i = 0; i < xValues.length; i++) {
            const row = [xValues[i], ...series.map(s => s[i] || '')];
            csv += row.join(',') + '\n';
        }

        return csv;
    }

    renderError(message) {
        this.innerHTML = `
            <div class="error-container">
                <i class="fas fa-exclamation-triangle"></i>
                <h3>Error Loading Chart</h3>
                <p>${message}</p>
                <a href="/apps/uplot/api/v1/ui/elements/uplot-home" class="back-link">
                    <i class="fas fa-arrow-left"></i> Back to Chart Builder
                </a>
            </div>
        `;
    }

    disconnectedCallback() {
        this.stopRealTimeUpdates();

        if (this.chart) {
            this.chart.destroy();
        }

        this.logger?.info('Scatter Plot Component destroyed');
    }
}

// Register custom element
customElements.define('scatter-plot', ScatterPlotComponent);


// Also register as a React component for SPA compatibility
if (typeof window.cardComponents !== 'undefined') {
    window.cardComponents['scatter-plot'] = ({ element, url }) => {
        const React = window.React;
        const ref = React.useRef(null);

        React.useEffect(() => {
            if (ref.current && !ref.current.querySelector('scatter-plot')) {
                const component = document.createElement('scatter-plot');
                ref.current.appendChild(component);
            }
        }, []);

        return React.createElement('div', {
            ref: ref,
            style: { width: '100%', height: '100%', overflow: 'auto' }
        });
    };
}
