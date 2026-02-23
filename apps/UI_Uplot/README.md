# uPlot Chart Builder

High-performance charting application using the uPlot library for data visualization.

## Category
**Data Visualization** > **Charts**

## Overview
UI_Uplot is a comprehensive charting platform built on the uPlot library (4x faster than Chart.js). It provides multiple chart types with flexible data source options including REST APIs, CSV files, JSON data, SQL.js queries, and PSWebHost metrics database integration.

## Features
- 6 chart types: Time Series, Area, Bar, Scatter, Multi-Axis, Heatmap
- Multiple data sources: REST APIs (JSON/CSV), SQL.js, Metrics DB, Static JSON, CSV Upload
- Real-time chart updates with configurable refresh intervals
- Chart export functionality (CSV/PNG)
- Browser console logging with API integration
- High-performance rendering with uPlot library

## Installation
This app is automatically loaded by PSWebHost when placed in the `apps/` directory.

## Configuration
- **Route Prefix:** `/apps/uplot`
- **Required Roles:** authenticated
- **Author:** PSWebHost
- **Version:** 1.0.0

## File Structure
```
UI_Uplot/
├── app.yaml                 # App manifest and settings
├── app_init.ps1             # Initialization script
├── menu.yaml                # Menu entries (8 items)
├── README.md                # This file
├── Architecture.md          # Detailed architecture documentation
├── data/                    # App data storage (centralized)
├── modules/                 # App-specific modules
├── public/elements/         # UI components (7 chart types)
├── routes/                  # API endpoints and routes
│   ├── api/v1/              # REST API endpoints
│   ├── cards/               # Card-based chart views
│   └── public/              # Public assets
└── tests/                   # Test suite
    └── twin/                # Twin test framework
```

## Usage

### Creating Charts
1. Navigate to the Chart Builder: `/apps/uplot/api/v1/ui/elements/uplot-home`
2. Select a chart type from the available cards
3. Choose a data source (REST API, CSV, SQL.js, or Metrics)
4. Configure chart options (title, refresh interval, etc.)
5. Click "Create Chart" to generate your visualization

### Available Chart Types
- **Time Series**: Line charts for time-based data
- **Area Chart**: Filled area charts for cumulative data
- **Bar Chart**: Vertical/horizontal bars for categorical data
- **Scatter Plot**: Point-based plots for correlation analysis
- **Multi-Axis**: Charts with multiple Y-axes for different scales
- **Heatmap**: Color-coded matrix visualization
- **Metrics Chart**: High-performance metrics with sql.js storage

## API Endpoints

### Configuration
- `GET /apps/uplot/api/v1/config` - App configuration and settings

### Chart Management
- `POST /apps/uplot/api/v1/charts/create` - Create new chart

### Data Sources
- `POST /apps/uplot/api/v1/data/csv` - Fetch/parse CSV data
- `POST /apps/uplot/api/v1/data/json` - Fetch/parse JSON data
- `POST /apps/uplot/api/v1/data/sql` - Execute SQL.js queries
- `POST /apps/uplot/api/v1/data/metrics` - Query metrics database

### Logging
- `POST /apps/uplot/api/v1/logs` - Browser console log collection

## Development

### Adding New Chart Types
1. Create component in `public/elements/[chart-type]/`
2. Add route in `routes/api/v1/ui/elements/[chart-type]/`
3. Update `app.yaml` chartTypes section
4. Add menu entry in `menu.yaml`

### Running Tests
```powershell
# PowerShell/CLI tests
.\tests\twin\UI_Uplot.Tests.ps1 -TestMode All

# Browser tests
# Navigate to: http://localhost:8888/apps/unittests/api/v1/ui/elements/unit-test-runner
# Select "UI_Uplot Browser Tests" and click "Run Tests"
```

## Data Sources

### REST API (JSON)
Fetch JSON data from external REST endpoints with custom headers support.

### REST API (CSV)
Fetch CSV data from external endpoints with automatic header detection.

### SQL.js
Execute SQL queries on in-browser SQLite databases with security validation.

### Metrics Database
Query the PSWebHost metrics database with time range and aggregation options.

### Static JSON
Paste or upload JSON data directly into the chart builder.

### CSV Upload
Upload CSV files from your local filesystem (up to 10MB).

## Configuration Settings

Key settings in `app.yaml`:
```yaml
settings:
  ConsoleToAPILoggingLevel: info    # verbose, info, warning, error, none
  defaultChartHeight: 400            # pixels
  defaultChartWidth: 800             # pixels
  defaultRefreshInterval: 5          # seconds
  maxDataPoints: 1000                # per series
  enableRealTimeUpdates: true
  maxCsvFileSize: 10485760          # 10MB
  maxJsonResponseSize: 52428800     # 50MB
  queryTimeout: 30000                # 30 seconds
```

## Security
- Authentication required for all endpoints
- SQL injection protection with query validation
- File size limits on uploads
- Input validation on all API endpoints
- User-scoped data isolation

## Performance
- uPlot library: 4x faster than Chart.js
- Incremental data updates with automatic trimming
- Log buffering (max 100 entries, 5-second flush)
- Thread-safe synchronized hashtables
- Data caching for frequently accessed queries

## Documentation
- **Architecture.md**: Comprehensive architecture and implementation details
- **tests/twin/README.md**: Testing guide and framework documentation
- See inline code documentation for API details

## Version History
- **1.0.0** (2026-01-11) - Initial release with 6 chart types
  - All core chart components implemented
  - Data source handlers complete
  - Browser console logging system
  - Twin test framework integration

## Support
For issues or questions, refer to the Architecture.md document or consult the PSWebHost documentation.
