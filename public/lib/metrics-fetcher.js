// Metrics Data Fetcher
// Intelligent data fetching with caching, gap detection, and merging
// Minimizes backend queries by fetching only missing data

class MetricsFetcher {
    constructor(cacheManager = null) {
        this.cache = cacheManager || new MetricsCache();
        this.pendingRequests = new Map();  // Deduplicate concurrent requests
    }

    /**
     * Fetch metrics data with intelligent caching
     * @param {Object} options - Fetch options
     * @param {string} options.dataset - Dataset name (e.g., 'cpu', 'memory')
     * @param {string|Date} options.startTime - Start time
     * @param {string|Date} options.endTime - End time
     * @param {string} options.granularity - Time granularity (e.g., '5s', '1m')
     * @param {string} options.aggregation - Aggregation type (avg, min, max, etc.)
     * @param {string[]} options.metrics - Specific metrics to fetch
     * @param {boolean} options.forceRefresh - Bypass cache
     * @param {number} options.resolution - Target number of data points
     * @returns {Promise<Array>} Metrics data
     */
    async fetch(options) {
        const {
            dataset = 'metrics',
            startTime,
            endTime,
            granularity = null,
            aggregation = 'avg',
            metrics = null,
            forceRefresh = false,
            resolution = null
        } = options;

        // Validate inputs
        if (!startTime || !endTime) {
            throw new Error('startTime and endTime are required');
        }

        // Create unique request key for deduplication
        const requestKey = JSON.stringify(options);

        // Check if there's already a pending request for this exact query
        if (this.pendingRequests.has(requestKey)) {
            return this.pendingRequests.get(requestKey);
        }

        // Create the fetch promise
        const fetchPromise = this._fetchWithCache(options);

        // Store pending request
        this.pendingRequests.set(requestKey, fetchPromise);

        try {
            const result = await fetchPromise;
            return result;
        } finally {
            // Remove from pending after completion
            this.pendingRequests.delete(requestKey);
        }
    }

    async _fetchWithCache(options) {
        const {
            dataset,
            startTime,
            endTime,
            granularity,
            aggregation,
            metrics,
            forceRefresh,
            resolution
        } = options;

        // If force refresh, bypass cache
        if (forceRefresh) {
            const data = await this._fetchFromBackend(options);
            // Store in cache for future use
            await this.cache.store(dataset, startTime, endTime, granularity, data);
            return this._extractDataArray(data);
        }

        // Try to get from cache first
        const cached = await this.cache.get(dataset, startTime, endTime, granularity);

        if (cached) {
            console.log('[MetricsFetcher] Cache hit:', dataset, startTime, endTime);
            return this._extractDataArray(cached.data);
        }

        // Detect gaps in cached data
        const gaps = await this.cache.detectGaps(dataset, startTime, endTime, granularity);

        console.log('[MetricsFetcher] Detected gaps:', gaps.length);

        if (gaps.length === 0) {
            // We have all the data cached, merge it
            const merged = await this.cache.mergeCachedData(dataset, startTime, endTime, granularity);
            return merged;
        }

        // Fetch missing gaps from backend
        const gapPromises = gaps.map(gap =>
            this._fetchGap(dataset, gap.start, gap.end, granularity, aggregation, metrics, resolution)
        );

        const gapResults = await Promise.all(gapPromises);

        // Merge all data (cached + new)
        const cachedData = await this.cache.mergeCachedData(dataset, startTime, endTime, granularity);
        const newData = gapResults.flat();

        const allData = [...cachedData, ...newData];

        // Sort by timestamp
        allData.sort((a, b) => {
            const aTime = new Date(a.Timestamp || a.timestamp).getTime();
            const bTime = new Date(b.Timestamp || b.timestamp).getTime();
            return aTime - bTime;
        });

        return allData;
    }

    async _fetchGap(dataset, startTime, endTime, granularity, aggregation, metrics, resolution) {
        console.log('[MetricsFetcher] Fetching gap:', dataset, startTime, endTime);

        const data = await this._fetchFromBackend({
            dataset,
            startTime,
            endTime,
            granularity,
            aggregation,
            metrics,
            resolution
        });

        // Store this gap in cache
        await this.cache.store(dataset, startTime, endTime, granularity, data);

        return this._extractDataArray(data);
    }

    async _fetchFromBackend(options) {
        const {
            dataset,
            startTime,
            endTime,
            granularity,
            aggregation,
            metrics,
            resolution
        } = options;

        // Build query parameters
        const params = new URLSearchParams({
            datasetname: dataset,
            starttime: new Date(startTime).toISOString(),
            endtime: new Date(endTime).toISOString(),
            format: 'json'
        });

        if (granularity) params.set('granularity', granularity);
        if (aggregation) params.set('aggregation', aggregation);
        if (metrics) params.set('metrics', Array.isArray(metrics) ? metrics.join(',') : metrics);
        if (resolution) params.set('resolution', resolution.toString());

        const url = `/api/v1/perfhistorylogs?${params.toString()}`;

        console.log('[MetricsFetcher] Backend request:', url);

        const response = await fetch(url);

        if (!response.ok) {
            throw new Error(`Backend request failed: ${response.status} ${response.statusText}`);
        }

        const data = await response.json();

        if (data.status === 'error') {
            throw new Error(data.message || 'Backend returned error');
        }

        return data;
    }

    _extractDataArray(data) {
        if (!data) return [];

        // Handle different response formats
        if (Array.isArray(data)) {
            return data;
        }

        if (data.data && Array.isArray(data.data)) {
            return data.data;
        }

        if (data.format === 'compact') {
            // Convert compact format to array
            return this._expandCompactFormat(data);
        }

        return [];
    }

    _expandCompactFormat(compactData) {
        const { timestamps, metrics } = compactData;

        if (!timestamps || !metrics) return [];

        const result = [];
        const metricKeys = Object.keys(metrics);

        for (let i = 0; i < timestamps.length; i++) {
            const point = { Timestamp: timestamps[i] };

            for (const key of metricKeys) {
                point[key] = metrics[key][i];
            }

            result.push(point);
        }

        return result;
    }

    /**
     * Fetch incremental updates (only data newer than last fetch)
     * @param {string} dataset
     * @param {string|Date} sinceTime
     * @param {Object} options
     * @returns {Promise<Array>}
     */
    async fetchIncremental(dataset, sinceTime, options = {}) {
        const params = new URLSearchParams({
            datasetname: dataset,
            sincetime: new Date(sinceTime).toISOString(),
            format: 'json',
            ...options
        });

        const url = `/api/v1/perfhistorylogs?${params.toString()}`;
        const response = await fetch(url);

        if (!response.ok) {
            throw new Error(`Incremental fetch failed: ${response.status}`);
        }

        const data = await response.json();

        if (data.status === 'error') {
            throw new Error(data.message);
        }

        // Store in cache
        if (data.data && data.data.length > 0) {
            const firstPoint = data.data[0];
            const lastPoint = data.data[data.data.length - 1];

            await this.cache.store(
                dataset,
                firstPoint.Timestamp,
                lastPoint.Timestamp,
                options.granularity || null,
                data
            );
        }

        return this._extractDataArray(data);
    }

    /**
     * Clear cache for a specific dataset
     * @param {string} dataset
     */
    async clearCache(dataset = null) {
        if (dataset) {
            const ranges = await this.cache.getCachedRanges(dataset);
            // TODO: Implement selective deletion
            console.warn('Selective cache clearing not yet implemented, clearing all');
        }

        await this.cache.clear();
    }

    /**
     * Get cache statistics
     */
    async getCacheStats() {
        return this.cache.getStats();
    }

    /**
     * Cleanup old cached data
     * @param {number} olderThanDays
     */
    async cleanup(olderThanDays = 7) {
        return this.cache.clearOldData(olderThanDays);
    }
}

// Export
if (typeof module !== 'undefined' && module.exports) {
    module.exports = MetricsFetcher;
} else {
    window.MetricsFetcher = MetricsFetcher;
}
