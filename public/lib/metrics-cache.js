// Metrics Cache Manager
// Provides intelligent browser-side caching using IndexedDB
// Minimizes backend queries through range-based caching and gap detection

class MetricsCache {
    constructor(dbName = 'PSWebHostMetrics', version = 1) {
        this.dbName = dbName;
        this.version = version;
        this.db = null;
        this.initPromise = this.initDB();
    }

    async initDB() {
        return new Promise((resolve, reject) => {
            const request = indexedDB.open(this.dbName, this.version);

            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                this.db = request.result;
                resolve(this.db);
            };

            request.onupgradeneeded = (event) => {
                const db = event.target.result;

                // Metrics data store
                if (!db.objectStoreNames.contains('metrics')) {
                    const metricsStore = db.createObjectStore('metrics', { keyPath: 'id' });
                    metricsStore.createIndex('dataset', 'dataset', { unique: false });
                    metricsStore.createIndex('startTime', 'startTime', { unique: false });
                    metricsStore.createIndex('endTime', 'endTime', { unique: false });
                    metricsStore.createIndex('granularity', 'granularity', { unique: false });
                }

                // Metadata store (track what ranges we have cached)
                if (!db.objectStoreNames.contains('metadata')) {
                    const metadataStore = db.createObjectStore('metadata', { keyPath: 'key' });
                }
            };
        });
    }

    // Generate unique ID for cache entry
    generateId(dataset, startTime, endTime, granularity) {
        const start = new Date(startTime).getTime();
        const end = new Date(endTime).getTime();
        return `${dataset}_${start}_${end}_${granularity || 'raw'}`;
    }

    // Store metrics data
    async store(dataset, startTime, endTime, granularity, data) {
        await this.initPromise;

        const id = this.generateId(dataset, startTime, endTime, granularity);
        const entry = {
            id,
            dataset,
            startTime: new Date(startTime).toISOString(),
            endTime: new Date(endTime).toISOString(),
            granularity: granularity || 'raw',
            data,
            cachedAt: new Date().toISOString(),
            dataPoints: Array.isArray(data) ? data.length : (data.dataPoints || 0)
        };

        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['metrics'], 'readwrite');
            const store = transaction.objectStore('metrics');
            const request = store.put(entry);

            request.onsuccess = () => resolve(entry);
            request.onerror = () => reject(request.error);
        });
    }

    // Retrieve cached data for a time range
    async get(dataset, startTime, endTime, granularity) {
        await this.initPromise;

        const id = this.generateId(dataset, startTime, endTime, granularity);

        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['metrics'], 'readonly');
            const store = transaction.objectStore('metrics');
            const request = store.get(id);

            request.onsuccess = () => resolve(request.result || null);
            request.onerror = () => reject(request.error);
        });
    }

    // Find all cached ranges for a dataset
    async getCachedRanges(dataset, granularity) {
        await this.initPromise;

        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['metrics'], 'readonly');
            const store = transaction.objectStore('metrics');
            const index = store.index('dataset');
            const request = index.getAll(dataset);

            request.onsuccess = () => {
                const results = request.result.filter(entry =>
                    !granularity || entry.granularity === granularity
                );
                resolve(results);
            };
            request.onerror = () => reject(request.error);
        });
    }

    // Detect gaps in cached data
    async detectGaps(dataset, startTime, endTime, granularity) {
        const cached = await this.getCachedRanges(dataset, granularity);

        if (cached.length === 0) {
            return [{ start: startTime, end: endTime }];
        }

        // Sort by start time
        const sorted = cached.sort((a, b) =>
            new Date(a.startTime).getTime() - new Date(b.startTime).getTime()
        );

        const gaps = [];
        const requestStart = new Date(startTime).getTime();
        const requestEnd = new Date(endTime).getTime();

        let currentStart = requestStart;

        for (const range of sorted) {
            const rangeStart = new Date(range.startTime).getTime();
            const rangeEnd = new Date(range.endTime).getTime();

            // Skip ranges that don't overlap with our request
            if (rangeEnd < requestStart || rangeStart > requestEnd) {
                continue;
            }

            // Gap before this range
            if (currentStart < rangeStart) {
                gaps.push({
                    start: new Date(currentStart).toISOString(),
                    end: new Date(Math.min(rangeStart, requestEnd)).toISOString()
                });
            }

            // Move current start past this range
            currentStart = Math.max(currentStart, rangeEnd);
        }

        // Gap after last range
        if (currentStart < requestEnd) {
            gaps.push({
                start: new Date(currentStart).toISOString(),
                end: new Date(requestEnd).toISOString()
            });
        }

        return gaps;
    }

    // Merge overlapping data ranges
    async mergeCachedData(dataset, startTime, endTime, granularity) {
        await this.initPromise;

        return new Promise(async (resolve, reject) => {
            try {
                const transaction = this.db.transaction(['metrics'], 'readonly');
                const store = transaction.objectStore('metrics');
                const index = store.index('dataset');
                const request = index.getAll(dataset);

                request.onsuccess = () => {
                    const results = request.result.filter(entry => {
                        if (granularity && entry.granularity !== granularity) {
                            return false;
                        }

                        const entryStart = new Date(entry.startTime).getTime();
                        const entryEnd = new Date(entry.endTime).getTime();
                        const reqStart = new Date(startTime).getTime();
                        const reqEnd = new Date(endTime).getTime();

                        // Check if ranges overlap
                        return entryStart <= reqEnd && entryEnd >= reqStart;
                    });

                    // Merge all data points
                    const allData = [];
                    results.forEach(entry => {
                        if (Array.isArray(entry.data)) {
                            allData.push(...entry.data);
                        } else if (entry.data && entry.data.data) {
                            allData.push(...entry.data.data);
                        }
                    });

                    // Sort by timestamp and deduplicate
                    const sorted = allData.sort((a, b) => {
                        const aTime = new Date(a.Timestamp || a.timestamp).getTime();
                        const bTime = new Date(b.Timestamp || b.timestamp).getTime();
                        return aTime - bTime;
                    });

                    // Remove duplicates (same timestamp)
                    const deduped = [];
                    let lastTime = null;
                    for (const point of sorted) {
                        const pointTime = new Date(point.Timestamp || point.timestamp).getTime();
                        if (pointTime !== lastTime) {
                            deduped.push(point);
                            lastTime = pointTime;
                        }
                    }

                    resolve(deduped);
                };

                request.onerror = () => reject(request.error);
            } catch (err) {
                reject(err);
            }
        });
    }

    // Clear old cached data (cleanup)
    async clearOldData(olderThanDays = 7) {
        await this.initPromise;

        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - olderThanDays);
        const cutoffTime = cutoffDate.toISOString();

        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['metrics'], 'readwrite');
            const store = transaction.objectStore('metrics');
            const index = store.index('endTime');
            const range = IDBKeyRange.upperBound(cutoffTime);
            const request = index.openCursor(range);

            let deleteCount = 0;
            request.onsuccess = (event) => {
                const cursor = event.target.result;
                if (cursor) {
                    cursor.delete();
                    deleteCount++;
                    cursor.continue();
                } else {
                    resolve({ deleted: deleteCount });
                }
            };

            request.onerror = () => reject(request.error);
        });
    }

    // Get cache statistics
    async getStats() {
        await this.initPromise;

        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['metrics'], 'readonly');
            const store = transaction.objectStore('metrics');
            const countRequest = store.count();

            countRequest.onsuccess = () => {
                const getAllRequest = store.getAll();

                getAllRequest.onsuccess = () => {
                    const entries = getAllRequest.result;
                    const totalDataPoints = entries.reduce((sum, entry) =>
                        sum + (entry.dataPoints || 0), 0
                    );

                    const datasets = new Set(entries.map(e => e.dataset));

                    resolve({
                        totalEntries: entries.length,
                        totalDataPoints,
                        datasets: Array.from(datasets),
                        oldestEntry: entries.length > 0 ?
                            entries.reduce((oldest, entry) =>
                                new Date(entry.cachedAt) < new Date(oldest.cachedAt) ? entry : oldest
                            ).cachedAt : null,
                        newestEntry: entries.length > 0 ?
                            entries.reduce((newest, entry) =>
                                new Date(entry.cachedAt) > new Date(newest.cachedAt) ? entry : newest
                            ).cachedAt : null
                    });
                };

                getAllRequest.onerror = () => reject(getAllRequest.error);
            };

            countRequest.onerror = () => reject(countRequest.error);
        });
    }

    // Clear all cached data
    async clear() {
        await this.initPromise;

        return new Promise((resolve, reject) => {
            const transaction = this.db.transaction(['metrics'], 'readwrite');
            const store = transaction.objectStore('metrics');
            const request = store.clear();

            request.onsuccess = () => resolve();
            request.onerror = () => reject(request.error);
        });
    }
}

// Export for use in other scripts
if (typeof module !== 'undefined' && module.exports) {
    module.exports = MetricsCache;
} else {
    window.MetricsCache = MetricsCache;
}
