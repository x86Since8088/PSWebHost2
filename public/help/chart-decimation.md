# Client-Side Chart Decimation

Chart.js handles data downsampling on the client side, eliminating the need for server-side aggregation.

## How It Works

### Raw Data Collection

**Metrics are collected at two granularities**:
- **5-second samples** (raw): Last 1 hour (720 points)
- **1-minute averages** (aggregated): Last 24 hours (1,440 points)

### Time Range Mapping

| Time Range | Data Source | Points | Granularity |
|------------|-------------|--------|-------------|
| 5 minutes  | 5s samples  | 60     | 5s          |
| 15 minutes | 5s samples  | 180    | 5s          |
| 30 minutes | 5s samples  | 360    | 5s          |
| 1 hour     | 5s samples  | 720    | 5s          |
| 3 hours    | 1m averages | 180    | 1m          |
| 6 hours    | 1m averages | 360    | 1m          |
| 12 hours   | 1m averages | 720    | 1m          |
| 24 hours   | 1m averages | 1,440  | 1m          |

### Chart.js Decimation

**Instead of reducing data on the server**, we:

1. **Send all raw data** to the browser (once)
2. **Cache it** in IndexedDB
3. **Let Chart.js decimate** for display

**Chart.js Decimation Plugin** (LTTB Algorithm):
```javascript
decimation: {
  enabled: true,
  algorithm: 'lttb',  // Largest-Triangle-Three-Buckets
  samples: 500         // Target display points
}
```

## Benefits

### 1. No Server-Side Processing
```
❌ Old Way:
User changes view → Server aggregates data → Send to browser

✅ New Way:
User changes view → Chart.js decimates cached data → Instant update
```

### 2. Smooth Zooming
```
5 min view (60 points)    → Cached, decimated to 500 points
  ↓ Zoom out
1 hour view (720 points)  → Fetch missing data, decimate to 500 points
  ↓ Zoom back in
5 min view (60 points)    → Use cached data, NO backend request
```

### 3. Performance Comparison

| Operation | Without Decimation | With Decimation |
|-----------|-------------------|-----------------|
| Initial 1h load | 500ms | 500ms |
| Render 720 points | Slow (janky) | Fast (smooth) |
| Zoom to 24h | 500ms + slow render | 200ms (gap fetch) + fast render |
| Zoom back to 1h | 500ms + slow render | 0ms (cached) + instant |

## LTTB Algorithm

**Largest-Triangle-Three-Buckets** preserves data shape while reducing points:

```
Original: ●●●●●●●●●●●●●●●●●●●●●●●● (1000 points)
                     ↓
Decimated: ●     ●    ●     ●    ●      (100 points)
           |_____|    |_____|
           Preserves peaks and valleys
```

**Algorithm**:
1. Divide data into buckets
2. Keep first and last points
3. For each bucket, find point that creates largest triangle with neighbors
4. This preserves visual shape

## Configuration

### Server-Heatmap CPU Chart

```javascript
// Enable decimation for CPU histogram
<ChartJsComponent
  element={{
    url: `/api/v1/ui/elements/chartjs?source=/api/v1/metrics/history
         &metric=cpu&timerange=${timeRange}
         &delay=5&charttype=line
         &decimation=true`  // ← Enable decimation
  }}
/>
```

### Chart.js Options

```javascript
options: {
  animation: false,  // Disable for performance
  parsing: false,    // Data pre-parsed
  plugins: {
    decimation: {
      enabled: true,
      algorithm: 'lttb',
      samples: 500    // Adjust for more/less detail
    }
  },
  elements: {
    point: {
      radius: 0  // Don't render individual points
    },
    line: {
      borderWidth: 2
    }
  }
}
```

## Data Format

**For Chart.js time scale**, data must be in `{x, y}` format:

```json
{
  "datasets": [
    {
      "label": "CPU 0",
      "data": [
        { "x": "2026-01-05T10:00:00Z", "y": 45.2 },
        { "x": "2026-01-05T10:00:05Z", "y": 46.1 },
        { "x": "2026-01-05T10:00:10Z", "y": 44.8 }
      ],
      "borderColor": "#3b82f6"
    },
    {
      "label": "CPU 1",
      "data": [
        { "x": "2026-01-05T10:00:00Z", "y": 42.1 },
        { "x": "2026-01-05T10:00:05Z", "y": 43.5 },
        { "x": "2026-01-05T10:00:10Z", "y": 41.9 }
      ],
      "borderColor": "#ef4444"
    }
  ]
}
```

## Best Practices

### 1. Send Raw Data
```
✅ DO: Send all collected data at native granularity
❌ DON'T: Pre-aggregate on server (unless caching)
```

### 2. Cache Everything
```
✅ DO: Store raw data in IndexedDB
✅ DO: Let Chart.js decimate for display
❌ DON'T: Fetch pre-aggregated versions
```

### 3. Adjust Sample Target
```javascript
// High detail (slower)
samples: 1000

// Medium (recommended)
samples: 500

// Low detail (fastest)
samples: 200
```

### 4. Disable Animations
```javascript
// For large datasets
animation: false  // Much faster rendering
```

## When Server-Side Aggregation IS Needed

Server-side aggregation is still valuable for:

1. **Historical data** (older than 24h, not in real-time cache)
2. **Long time ranges** (weeks, months, years)
3. **Statistical queries** (p95, p99 calculations)
4. **CSV exports** (pre-aggregated for download)
5. **API efficiency** (reduce initial load size)

But for **real-time monitoring dashboards**, client-side decimation is superior.

## Memory Usage

| Time Range | Data Points | Memory | With Decimation |
|------------|-------------|--------|-----------------|
| 5 min      | 60          | ~5 KB  | ~5 KB |
| 1 hour     | 720         | ~60 KB | ~40 KB |
| 24 hours   | 1,440       | ~120 KB| ~40 KB |

**Decimation saves memory** by reducing rendered elements, but keeps raw data cached for precision when needed.

## Future Enhancements

- [ ] **Progressive rendering**: Load low-res first, fill in details
- [ ] **Zoom-based detail**: Higher sample count when zoomed in
- [ ] **WebGL rendering**: Handle millions of points
- [ ] **Worker threads**: Decimate in background
- [ ] **Adaptive sampling**: Adjust based on device performance
