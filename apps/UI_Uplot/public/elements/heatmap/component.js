/**
 * uPlot Heatmap Component
 * Heatmap visualization for matrix data with color scales
 */

class HeatmapComponent extends HTMLElement {
    constructor() {
        super();
        this.chart = null;
        this.logger = null;
        this.chartId = null;
        this.chartConfig = null;
        this.refreshTimer = null;
        this.colorScale = null;
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

        this.logger.info(`Heatmap Component loaded for chart: ${this.chartId}`);

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
            this.logger = { info: (...args) => console.log('[heatmap:info]', ...args), warn: (...args) => console.warn('[heatmap:warn]', ...args), error: (...args) => console.error('[heatmap:error]', ...args), debug: (...args) => console.debug('[heatmap:debug]', ...args), verbose: (...args) => console.log('[heatmap:verbose]', ...args) };
        }
    }

    async loadChartConfig() {
        try {
            const params = new URLSearchParams(window.location.search);

            this.chartConfig = {
                chartId: this.chartId,
                chartType: 'heatmap',
                title: params.get('title') || 'Heatmap',
                width: parseInt(params.get('width')) || 800,
                height: parseInt(params.get('height')) || 600,
                colorScale: params.get('colorScale') || 'heat', // heat, cool, viridis, plasma
                showValues: params.get('showValues') !== 'false',
                cellSize: parseInt(params.get('cellSize')) || 30,
                dataSource: {
                    type: params.get('source') || 'metrics-db',
                    config: this.parseDataSourceConfig(params)
                },
                realTime: params.get('realtime') === 'true',
                refreshInterval: parseInt(params.get('delay')) || 10
            };

            // Initialize color scale
            this.initializeColorScale();

            this.logger.verbose('Chart configuration loaded:', this.chartConfig);

        } catch (error) {
            this.logger.error('Failed to load chart configuration:', error);
            this.renderError('Failed to load chart configuration: ' + error.message);
        }
    }

    initializeColorScale() {
        const scales = {
            heat: [
                { stop: 0.0, color: '#ffffcc' },
                { stop: 0.25, color: '#ffeda0' },
                { stop: 0.5, color: '#feb24c' },
                { stop: 0.75, color: '#f03b20' },
                { stop: 1.0, color: '#bd0026' }
            ],
            cool: [
                { stop: 0.0, color: '#f7fbff' },
                { stop: 0.25, color: '#c6dbef' },
                { stop: 0.5, color: '#6baed6' },
                { stop: 0.75, color: '#2171b5' },
                { stop: 1.0, color: '#08306b' }
            ],
            viridis: [
                { stop: 0.0, color: '#440154' },
                { stop: 0.25, color: '#31688e' },
                { stop: 0.5, color: '#35b779' },
                { stop: 0.75, color: '#fde724' },
                { stop: 1.0, color: '#fde724' }
            ],
            plasma: [
                { stop: 0.0, color: '#0d0887' },
                { stop: 0.25, color: '#7e03a8' },
                { stop: 0.5, color: '#cc4778' },
                { stop: 0.75, color: '#f89540' },
                { stop: 1.0, color: '#f0f921' }
            ]
        };

        this.colorScale = scales[this.chartConfig.colorScale] || scales.heat;
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
                    metricName: params.get('metric') || 'heatmap_data',
                    timeRange: params.get('timeRange') || '24h',
                    aggregation: params.get('aggregation') || 'avg'
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
        // Load uPlot library (for canvas utilities)
        if (typeof uPlot === 'undefined') {
            await this.loadScript('/public/lib/uPlot.iife.min.js');
            await this.loadStylesheet('/public/lib/uPlot.min.css');
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
        this.logger.info('Initializing heatmap');

        // Render chart container
        this.renderChartContainer();

        // Fetch initial data
        const initialData = await this.fetchData();

        if (!initialData) {
            this.renderError('Failed to fetch chart data');
            return;
        }

        // Render heatmap
        this.renderHeatmap(initialData);

        // Start real-time updates if enabled
        if (this.chartConfig.realTime) {
            this.startRealTimeUpdates();
        }
    }

    renderHeatmap(data) {
        const container = this.querySelector('#heatmapCanvas');
        const canvas = document.createElement('canvas');

        const matrixData = data.matrix;
        const xLabels = data.metadata?.xLabels || [];
        const yLabels = data.metadata?.yLabels || [];

        const rows = matrixData.length;
        const cols = matrixData[0]?.length || 0;

        const cellSize = this.chartConfig.cellSize;
        const labelWidth = 100;
        const labelHeight = 30;

        canvas.width = cols * cellSize + labelWidth;
        canvas.height = rows * cellSize + labelHeight;

        const ctx = canvas.getContext('2d');

        // Find min/max for normalization
        let min = Infinity, max = -Infinity;
        matrixData.forEach(row => {
            row.forEach(val => {
                if (val < min) min = val;
                if (val > max) max = val;
            });
        });

        // Draw cells
        matrixData.forEach((row, y) => {
            row.forEach((value, x) => {
                const normalized = (value - min) / (max - min);
                const color = this.getColorForValue(normalized);

                ctx.fillStyle = color;
                ctx.fillRect(
                    labelWidth + x * cellSize,
                    labelHeight + y * cellSize,
                    cellSize,
                    cellSize
                );

                // Draw cell border
                ctx.strokeStyle = '#e5e7eb';
                ctx.strokeRect(
                    labelWidth + x * cellSize,
                    labelHeight + y * cellSize,
                    cellSize,
                    cellSize
                );

                // Draw value if enabled and cell is large enough
                if (this.chartConfig.showValues && cellSize >= 25) {
                    ctx.fillStyle = this.getContrastColor(color);
                    ctx.font = `${Math.min(cellSize / 3, 12)}px Arial`;
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillText(
                        value.toFixed(1),
                        labelWidth + x * cellSize + cellSize / 2,
                        labelHeight + y * cellSize + cellSize / 2
                    );
                }
            });
        });

        // Draw X labels
        ctx.fillStyle = '#374151';
        ctx.font = '11px Arial';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        xLabels.forEach((label, i) => {
            ctx.save();
            ctx.translate(
                labelWidth + i * cellSize + cellSize / 2,
                labelHeight / 2
            );
            ctx.rotate(-Math.PI / 4);
            ctx.fillText(label, 0, 0);
            ctx.restore();
        });

        // Draw Y labels
        ctx.textAlign = 'right';
        ctx.textBaseline = 'middle';
        yLabels.forEach((label, i) => {
            ctx.fillText(
                label,
                labelWidth - 10,
                labelHeight + i * cellSize + cellSize / 2
            );
        });

        // Add canvas to container
        container.innerHTML = '';
        container.appendChild(canvas);

        // Add color legend
        this.renderColorLegend(min, max);

        // Add tooltip
        this.addTooltip(canvas, matrixData, xLabels, yLabels, labelWidth, labelHeight, cellSize);

        this.logger.info('Heatmap rendered successfully');
    }

    getColorForValue(normalized) {
        // Clamp normalized value between 0 and 1
        normalized = Math.max(0, Math.min(1, normalized));

        // Find color stops
        for (let i = 0; i < this.colorScale.length - 1; i++) {
            const current = this.colorScale[i];
            const next = this.colorScale[i + 1];

            if (normalized >= current.stop && normalized <= next.stop) {
                const t = (normalized - current.stop) / (next.stop - current.stop);
                return this.interpolateColor(current.color, next.color, t);
            }
        }

        return this.colorScale[this.colorScale.length - 1].color;
    }

    interpolateColor(color1, color2, t) {
        const r1 = parseInt(color1.substr(1, 2), 16);
        const g1 = parseInt(color1.substr(3, 2), 16);
        const b1 = parseInt(color1.substr(5, 2), 16);

        const r2 = parseInt(color2.substr(1, 2), 16);
        const g2 = parseInt(color2.substr(3, 2), 16);
        const b2 = parseInt(color2.substr(5, 2), 16);

        const r = Math.round(r1 + (r2 - r1) * t);
        const g = Math.round(g1 + (g2 - g1) * t);
        const b = Math.round(b1 + (b2 - b1) * t);

        return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;
    }

    getContrastColor(hexColor) {
        const r = parseInt(hexColor.substr(1, 2), 16);
        const g = parseInt(hexColor.substr(3, 2), 16);
        const b = parseInt(hexColor.substr(5, 2), 16);
        const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
        return luminance > 0.5 ? '#000000' : '#ffffff';
    }

    renderColorLegend(min, max) {
        const legend = this.querySelector('#colorLegend');
        const canvas = document.createElement('canvas');
        canvas.width = 300;
        canvas.height = 40;

        const ctx = canvas.getContext('2d');

        // Draw gradient
        for (let i = 0; i < 300; i++) {
            const normalized = i / 300;
            const color = this.getColorForValue(normalized);
            ctx.fillStyle = color;
            ctx.fillRect(i, 0, 1, 20);
        }

        // Draw labels
        ctx.fillStyle = '#374151';
        ctx.font = '11px Arial';
        ctx.textAlign = 'left';
        ctx.fillText(min.toFixed(2), 0, 35);
        ctx.textAlign = 'right';
        ctx.fillText(max.toFixed(2), 300, 35);

        legend.innerHTML = '';
        legend.appendChild(canvas);
    }

    addTooltip(canvas, matrixData, xLabels, yLabels, labelWidth, labelHeight, cellSize) {
        const tooltip = this.querySelector('#tooltip');

        canvas.addEventListener('mousemove', (e) => {
            const rect = canvas.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;

            const col = Math.floor((x - labelWidth) / cellSize);
            const row = Math.floor((y - labelHeight) / cellSize);

            if (row >= 0 && row < matrixData.length && col >= 0 && col < matrixData[0].length) {
                const value = matrixData[row][col];
                const xLabel = xLabels[col] || col;
                const yLabel = yLabels[row] || row;

                tooltip.style.display = 'block';
                tooltip.style.left = `${e.clientX + 10}px`;
                tooltip.style.top = `${e.clientY + 10}px`;
                tooltip.innerHTML = `
                    <strong>${xLabel} × ${yLabel}</strong><br>
                    Value: ${value.toFixed(2)}
                `;
            } else {
                tooltip.style.display = 'none';
            }
        });

        canvas.addEventListener('mouseleave', () => {
            tooltip.style.display = 'none';
        });
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

            this.logger.verbose(`Fetched matrix data: ${result.matrix?.length || 0} rows`);

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

            if (newData) {
                this.renderHeatmap(newData);
                this.logger.verbose('Heatmap data updated');
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
            <div class="heatmap-container">
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
                <div class="heatmap-content">
                    <div id="heatmapCanvas"></div>
                    <div class="legend-container">
                        <label>Color Scale (${this.chartConfig.colorScale}):</label>
                        <div id="colorLegend"></div>
                    </div>
                </div>
                <div class="chart-footer">
                    <span class="data-source-info">
                        <i class="fas fa-database"></i> Source: ${this.chartConfig.dataSource.type}
                    </span>
                    <span class="chart-type-info">
                        <i class="fas fa-th"></i> Cell size: ${this.chartConfig.cellSize}px
                    </span>
                    ${this.chartConfig.realTime ? `
                        <span class="realtime-indicator">
                            <i class="fas fa-circle pulse"></i> Live
                        </span>
                    ` : ''}
                </div>
            </div>
            <div id="tooltip" class="heatmap-tooltip"></div>
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

        if (newData) {
            this.renderHeatmap(newData);
            this.logger.info('Heatmap refreshed successfully');
        }
    }

    exportData() {
        this.logger.info('Exporting heatmap data');

        const canvas = this.querySelector('#heatmapCanvas canvas');
        if (!canvas) return;

        // Export as PNG
        canvas.toBlob((blob) => {
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `${this.chartConfig.title.replace(/\s+/g, '_')}_${Date.now()}.png`;
            a.click();
            URL.revokeObjectURL(url);
        });

        this.logger.info('Heatmap exported successfully');
    }

    renderError(message) {
        this.innerHTML = `
            <div class="error-container">
                <i class="fas fa-exclamation-triangle"></i>
                <h3>Error Loading Heatmap</h3>
                <p>${message}</p>
                <a href="/apps/uplot/api/v1/ui/elements/uplot-home" class="back-link">
                    <i class="fas fa-arrow-left"></i> Back to Chart Builder
                </a>
            </div>
        `;
    }

    disconnectedCallback() {
        this.stopRealTimeUpdates();
        this.logger?.info('Heatmap Component destroyed');
    }
}

// Register custom element
customElements.define('heat-map', HeatmapComponent);


// Also register as a React component for SPA compatibility
if (typeof window.cardComponents !== 'undefined') {
    window.cardComponents['heatmap'] = ({ element, url }) => {
        const React = window.React;
        const ref = React.useRef(null);

        React.useEffect(() => {
            if (ref.current && !ref.current.querySelector('heat-map')) {
                const component = document.createElement('heat-map');
                ref.current.appendChild(component);
            }
        }, []);

        return React.createElement('div', {
            ref: ref,
            style: { width: '100%', height: '100%', overflow: 'auto' }
        });
    };
}
