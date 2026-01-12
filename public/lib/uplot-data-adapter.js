/**
 * uPlot Data Adapter - Incremental chart updates without destruction
 *
 * Provides efficient incremental updates for uPlot charts with automatic
 * data trimming and point limit management.
 *
 * Usage:
 *   const adapter = new UPlotDataAdapter(uplotInstance, {
 *     maxDataPoints: 1000,
 *     timeWindow: 3600000  // 1 hour in ms
 *   });
 *
 *   adapter.appendData(newData);
 *   adapter.replaceData(fullData);
 */

class UPlotDataAdapter {
    /**
     * @param {uPlot} uplotInstance - The uPlot instance to manage
     * @param {Object} options - Configuration options
     * @param {number} options.maxDataPoints - Maximum points per dataset (default: 1000)
     * @param {number} options.timeWindow - Time window in milliseconds (null = no trimming)
     */
    constructor(uplotInstance, options = {}) {
        this.uplot = uplotInstance;
        this.maxDataPoints = options.maxDataPoints || 1000;
        this.timeWindow = options.timeWindow || null;
        this.appendCount = 0;
        this.replaceCount = 0;
    }

    /**
     * Append new data points incrementally
     * @param {Array} newData - uPlot data format: [[timestamps], [series1], [series2], ...]
     * @param {boolean} resetScales - Whether to reset axis scales (default: false)
     */
    appendData(newData, resetScales = false) {
        if (!newData || !newData[0] || newData[0].length === 0) {
            return;
        }

        const currentData = this.uplot.data;
        const mergedData = this._mergeData(currentData, newData);
        const trimmedData = this._trimData(mergedData);

        this.uplot.setData(trimmedData, resetScales);
        this.appendCount++;
    }

    /**
     * Replace all data (e.g., on time range change)
     * @param {Array} newData - uPlot data format: [[timestamps], [series1], [series2], ...]
     * @param {boolean} resetScales - Whether to reset axis scales (default: true)
     */
    replaceData(newData, resetScales = true) {
        const trimmedData = this._trimData(newData);
        this.uplot.setData(trimmedData, resetScales);
        this.replaceCount++;
    }

    /**
     * Merge new data with existing data, removing duplicates
     * @private
     */
    _mergeData(currentData, newData) {
        if (!currentData || currentData.length === 0 || !currentData[0]) {
            return newData;
        }

        // Clone current data
        const merged = currentData.map(series => [...series]);

        // Get timestamp arrays
        const currentTimestamps = merged[0];
        const newTimestamps = newData[0];

        if (!newTimestamps || newTimestamps.length === 0) {
            return merged;
        }

        // Find insertion point (first new timestamp > last current timestamp)
        const lastCurrentTime = currentTimestamps[currentTimestamps.length - 1];
        const insertIndex = newTimestamps.findIndex(t => t > lastCurrentTime);

        if (insertIndex === -1) {
            // All new data is older than current data, skip
            return merged;
        }

        // Append new data points
        for (let i = 0; i < merged.length && i < newData.length; i++) {
            const newPoints = newData[i].slice(insertIndex);
            merged[i] = merged[i].concat(newPoints);
        }

        return merged;
    }

    /**
     * Trim data based on maxDataPoints and timeWindow
     * @private
     */
    _trimData(data) {
        if (!data || !data[0] || data[0].length === 0) {
            return data;
        }

        let trimmed = data.map(series => [...series]);
        const timestamps = trimmed[0];

        // Trim by time window
        if (this.timeWindow !== null) {
            const now = Date.now() / 1000;  // uPlot uses seconds
            const cutoff = now - (this.timeWindow / 1000);

            const startIndex = timestamps.findIndex(t => t >= cutoff);
            if (startIndex > 0) {
                trimmed = trimmed.map(series => series.slice(startIndex));
            }
        }

        // Trim by max data points
        if (this.maxDataPoints && trimmed[0].length > this.maxDataPoints) {
            const excess = trimmed[0].length - this.maxDataPoints;
            trimmed = trimmed.map(series => series.slice(excess));
        }

        return trimmed;
    }

    /**
     * Get current data point count
     */
    getDataCount() {
        return this.uplot.data[0] ? this.uplot.data[0].length : 0;
    }

    /**
     * Get adapter statistics
     */
    getStats() {
        return {
            dataPointCount: this.getDataCount(),
            seriesCount: this.uplot.data.length - 1,
            appendOperations: this.appendCount,
            replaceOperations: this.replaceCount,
            maxDataPoints: this.maxDataPoints,
            timeWindow: this.timeWindow
        };
    }

    /**
     * Clear all data
     */
    clear() {
        const emptyData = this.uplot.data.map(() => []);
        this.uplot.setData(emptyData);
    }

    /**
     * Destroy the adapter (cleanup)
     */
    destroy() {
        this.uplot = null;
    }
}

// Export for browser usage
if (typeof window !== 'undefined') {
    window.UPlotDataAdapter = UPlotDataAdapter;
}

// Export for Node.js usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = UPlotDataAdapter;
}
