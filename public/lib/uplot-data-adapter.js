/**
 * UPlotDataAdapter - Manages incremental chart data updates with automatic time-window pruning
 *
 * Provides intelligent data merging for uPlot charts:
 * - Appends new time-series data to existing chart
 * - Deduplicates timestamps
 * - Prunes data outside time window
 * - Limits total data points for performance
 *
 * Usage:
 *   const adapter = new UPlotDataAdapter(uplotInstance, {
 *     maxDataPoints: 1000,
 *     timeWindow: 3600000  // 1 hour in ms
 *   });
 *   adapter.replaceData(newData, false);
 */

class UPlotDataAdapter {
    constructor(uplotInstance, options = {}) {
        this.chart = uplotInstance;
        this.maxDataPoints = options.maxDataPoints || 1000;
        this.timeWindowMs = options.timeWindow || 3600000; // 1 hour default
    }

    /**
     * Replace or merge chart data
     * @param {Array} newData - uPlot format: [[timestamps], [series1], [series2], ...]
     * @param {boolean} clearExisting - If true, completely replace data; if false, merge
     */
    replaceData(newData, clearExisting = false) {
        // Validate input
        if (!newData || !Array.isArray(newData) || newData.length === 0) {
            console.warn('[UPlotDataAdapter] Invalid newData:', newData);
            return;
        }

        // If clearing existing data, just set it directly
        if (clearExisting) {
            this.chart.setData(newData);
            return;
        }

        // Get current data from chart
        const currentData = this.chart.data;
        if (!currentData || !currentData[0] || currentData[0].length === 0) {
            // No existing data, just set the new data
            this.chart.setData(newData);
            return;
        }

        // Merge: Append new timestamps, deduplicate, prune old data
        const mergedData = this._mergeTimeSeries(currentData, newData);
        const prunedData = this._pruneByTimeWindow(mergedData);
        const limitedData = this._limitDataPoints(prunedData);

        // Update chart with merged data
        this.chart.setData(limitedData);
    }

    /**
     * Merge two time-series datasets, removing duplicates and maintaining chronological order
     * @param {Array} existing - Current chart data
     * @param {Array} incoming - New data to merge
     * @returns {Array} Merged data in uPlot format
     */
    _mergeTimeSeries(existing, incoming) {
        // Both datasets should have same number of series
        const seriesCount = Math.max(existing.length, incoming.length);
        const merged = [];

        // Create timestamp map for deduplication
        const timestampMap = new Map();

        // Add existing data to map
        const existingTimestamps = existing[0] || [];
        for (let i = 0; i < existingTimestamps.length; i++) {
            const timestamp = existingTimestamps[i];
            const dataPoint = [];
            for (let s = 0; s < seriesCount; s++) {
                dataPoint.push(existing[s] ? existing[s][i] : null);
            }
            timestampMap.set(timestamp, dataPoint);
        }

        // Merge incoming data (overwrites duplicates)
        const incomingTimestamps = incoming[0] || [];
        for (let i = 0; i < incomingTimestamps.length; i++) {
            const timestamp = incomingTimestamps[i];
            const dataPoint = [];
            for (let s = 0; s < seriesCount; s++) {
                dataPoint.push(incoming[s] ? incoming[s][i] : null);
            }
            timestampMap.set(timestamp, dataPoint);
        }

        // Sort timestamps chronologically
        const sortedTimestamps = Array.from(timestampMap.keys()).sort((a, b) => a - b);

        // Build merged arrays
        for (let s = 0; s < seriesCount; s++) {
            merged[s] = [];
        }

        sortedTimestamps.forEach(timestamp => {
            const dataPoint = timestampMap.get(timestamp);
            for (let s = 0; s < seriesCount; s++) {
                merged[s].push(dataPoint[s]);
            }
        });

        return merged;
    }

    /**
     * Remove timestamps older than timeWindowMs
     * @param {Array} data - uPlot format data
     * @returns {Array} Pruned data
     */
    _pruneByTimeWindow(data) {
        if (!this.timeWindowMs || this.timeWindowMs <= 0) {
            return data; // No pruning
        }

        const timestamps = data[0] || [];
        if (timestamps.length === 0) {
            return data;
        }

        // Calculate cutoff time (in seconds if timestamps are in seconds)
        const now = Date.now() / 1000; // Assume timestamps are in seconds (uPlot convention)
        const cutoffTime = now - (this.timeWindowMs / 1000);

        // Find first index to keep
        let startIndex = 0;
        for (let i = 0; i < timestamps.length; i++) {
            if (timestamps[i] >= cutoffTime) {
                startIndex = i;
                break;
            }
        }

        // If all data is too old, return empty dataset with proper structure
        if (startIndex === 0 && timestamps[0] < cutoffTime) {
            return data.map(() => []);
        }

        // Slice all series from startIndex
        return data.map(series => series.slice(startIndex));
    }

    /**
     * Limit total data points to maxDataPoints
     * @param {Array} data - uPlot format data
     * @returns {Array} Limited data
     */
    _limitDataPoints(data) {
        const timestamps = data[0] || [];

        if (timestamps.length <= this.maxDataPoints) {
            return data; // No limiting needed
        }

        // Keep only last maxDataPoints entries
        return data.map(series => series.slice(-this.maxDataPoints));
    }

    /**
     * Get current chart data
     * @returns {Array} Current chart data in uPlot format
     */
    getData() {
        return this.chart.data;
    }

    /**
     * Clear all chart data
     */
    clearData() {
        const emptyData = this.chart.data.map(() => []);
        this.chart.setData(emptyData);
    }
}

// Export to global scope
window.UPlotDataAdapter = UPlotDataAdapter;
