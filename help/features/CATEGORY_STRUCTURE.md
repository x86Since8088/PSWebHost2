# App Category Structure

## Overview

PSWebHost apps now use a hierarchical parent category system that automatically merges duplicate categories across apps. This provides a clean, organized structure for grouping related apps.

---

## Category Structure

### Parent Category Object

Each app's `app.json` now includes a `parentCategory` object:

```json
{
  "parentCategory": {
    "id": "operating-systems",
    "name": "Operating Systems",
    "description": "Operating system administration and management",
    "icon": "desktop",
    "order": 1
  },
  "subCategory": {
    "name": "Windows",
    "order": 1
  }
}
```

### Predefined Parent Categories

| Category | ID | Icon | Order | Description |
|----------|----|----- |-------|-------------|
| Operating Systems | `operating-systems` | desktop | 1 | Operating system administration and management |
| Containers | `containers` | box | 2 | Container orchestration and management |
| Databases | `databases` | database | 3 | Database administration and monitoring |
| Monitoring | `monitoring` | chart | 4 | System monitoring and metrics |
| Administration | `admin` | users | 5 | User and system administration |
| Utilities | `utilities` | tool | 6 | Tools and helpers |

---

## Category Merging

### How It Works

1. **During Initialization** (`system/init.ps1`):
   - Apps are loaded and their manifests are read
   - Parent categories with the same `id` are merged into a single category
   - Subcategories are grouped under their parent
   - Apps are added to their respective subcategories

2. **Merged Structure** (`$Global:PSWebServer.Categories`):
   ```powershell
   @{
       "operating-systems" = @{
           id = "operating-systems"
           name = "Operating Systems"
           description = "..."
           icon = "desktop"
           order = 1
           subCategories = @{
               "Windows" = @{
                   name = "Windows"
                   order = 1
                   apps = @(
                       @{ name = "WindowsAdmin"; displayName = "Windows Administration"; ... }
                   )
               }
               "Linux" = @{
                   name = "Linux"
                   order = 2
                   apps = @(
                       @{ name = "LinuxAdmin"; displayName = "Linux Administration"; ... }
                   )
               }
           }
           apps = @("WindowsAdmin", "LinuxAdmin")
       }
       "containers" = @{ ... }
       "databases" = @{ ... }
   }
   ```

3. **API Exposure** (`/api/v1/categories`):
   - Categories are sorted by `order`
   - Subcategories are sorted by `order`
   - Apps within subcategories maintain their metadata

---

## Current Category Assignments

### Operating Systems (2 apps)
- **Windows** (order: 1)
  - WindowsAdmin: Windows service and task scheduler management
- **Linux** (order: 2)
  - LinuxAdmin: Linux systemd services and cron job management

### Containers (3 apps)
- **WSL** (order: 1)
  - WSLManager: Windows Subsystem for Linux distribution management
- **Docker** (order: 2)
  - DockerManager: Docker container, image, and network management
- **Kubernetes** (order: 3)
  - KubernetesManager: Kubernetes cluster status and resource viewing

### Databases (5 apps)
- **MySQL** (order: 1)
  - MySQLManager: MySQL database administration and monitoring
- **Redis** (order: 2)
  - RedisManager: Redis cache and data structure management
- **SQLite** (order: 3)
  - SQLiteManager: SQLite database file management
- **SQL Server** (order: 4)
  - SQLServerManager: Microsoft SQL Server administration
- **Vault** (order: 5)
  - VaultManager: HashiCorp Vault secrets management

---

## API Endpoint

### GET /api/v1/categories

Returns the merged category structure.

**Response Example:**
```json
{
  "categories": [
    {
      "id": "operating-systems",
      "name": "Operating Systems",
      "description": "Operating system administration and management",
      "icon": "desktop",
      "order": 1,
      "subCategories": [
        {
          "name": "Windows",
          "order": 1,
          "apps": [
            {
              "name": "WindowsAdmin",
              "displayName": "Windows Administration",
              "version": "1.0.0",
              "description": "Windows service and task scheduler management",
              "routePrefix": "/apps/windowsadmin",
              "requiredRoles": ["admin", "system_admin"]
            }
          ]
        },
        {
          "name": "Linux",
          "order": 2,
          "apps": [...]
        }
      ],
      "totalApps": 2
    },
    {
      "id": "containers",
      "name": "Containers",
      ...
    },
    {
      "id": "databases",
      "name": "Databases",
      ...
    }
  ],
  "totalCategories": 3,
  "totalApps": 10,
  "generatedAt": "2026-01-10T22:45:00.0000000Z"
}
```

**Security**: Unauthenticated access allowed (public endpoint)

---

## Creating New Apps with Categories

### Using New-PSWebHostApp.ps1

```powershell
.\system\utility\New-PSWebHostApp.ps1 `
  -AppName "PostgreSQLManager" `
  -DisplayName "PostgreSQL Manager" `
  -Description "PostgreSQL database administration" `
  -Category "Databases" `
  -SubCategory "PostgreSQL" `
  -RequiredRoles @('admin', 'database_admin')
```

The script will:
1. Look up the predefined "Databases" category definition
2. Create the `parentCategory` object in `app.json`
3. Create the `subCategory` object with default order 999
4. Generate proper structure automatically

### Custom Categories

If you use a category name not in the predefined list:

```powershell
-Category "Custom Category Name"
```

The script will create a new parent category with:
- `id`: kebab-case version of the name
- `order`: 99 (appears after predefined categories)
- `icon`: "folder" (generic icon)

---

## Benefits

### 1. Automatic Merging
- Multiple apps can share the same parent category
- No manual merging required
- Single source of truth per category

### 2. Organized Structure
- Three-tier hierarchy: Category > SubCategory > App
- Ordered display (by category order, then subcategory order)
- Consistent metadata across apps

### 3. Discoverability
- API endpoint for dynamic category browsing
- Apps grouped by function and technology
- Clear navigation paths

### 4. Extensibility
- Easy to add new categories
- Custom categories supported
- Forward-compatible structure

---

## Implementation Files

### Modified Files
1. **system/init.ps1** (lines 681-752)
   - Category merging logic
   - Thread-safe synchronized hashtables
   - Verbose logging of category structure

2. **system/utility/New-PSWebHostApp.ps1** (lines 136-228)
   - Predefined category definitions
   - Automatic parent category object creation
   - Support for custom categories

3. **All app.json files** (10 apps)
   - Converted from `category` string to `parentCategory` object
   - Added `subCategory` object with order

### New Files
1. **routes/api/v1/categories/get.ps1**
   - API endpoint for category structure
   - Sorted output by order
   - Metadata aggregation

2. **routes/api/v1/categories/get.security.json**
   - Public access (unauthenticated)

3. **update-app-categories.ps1**
   - Migration script (one-time use)
   - Updated all existing apps

4. **CATEGORY_STRUCTURE.md** (this file)
   - Documentation

---

## Future Enhancements

### Potential Additions
1. **Category Icons in Menu**
   - Use `icon` property for visual indicators
   - Icon library (FontAwesome, Material Icons, etc.)

2. **Category-Level Security**
   - Role requirements at category level
   - Inherited by subcategories and apps

3. **Dynamic Category Registration**
   - Apps can register custom categories
   - Category plugins/extensions

4. **Category Metadata**
   - Tags for cross-category searching
   - Related categories
   - Category-level documentation

5. **UI Components**
   - Category browser component
   - Hierarchical menu rendering
   - Breadcrumb navigation

---

## Migration Notes

### From Old Structure
**Before:**
```json
{
  "category": "Operating Systems",
  "subCategory": "Windows"
}
```

**After:**
```json
{
  "parentCategory": {
    "id": "operating-systems",
    "name": "Operating Systems",
    "description": "Operating system administration and management",
    "icon": "desktop",
    "order": 1
  },
  "subCategory": {
    "name": "Windows",
    "order": 1
  }
}
```

### Migration Script
Run `update-app-categories.ps1` to convert existing apps (already completed for current apps).

---

## Testing

### Verify Category Structure
```powershell
# Start server
.\WebHost.ps1 -Port 8080 -Async

# Query categories
Invoke-RestMethod -Uri "http://localhost:8080/api/v1/categories" | ConvertTo-Json -Depth 10

# Check server global variable
$Global:PSWebServer.Categories
```

### Expected Output
- 3 parent categories (Operating Systems, Containers, Databases)
- 10 subcategories across all categories
- 10 apps distributed across subcategories
- Proper ordering and metadata

---

## Conclusion

The parent category structure provides a scalable, organized system for grouping PSWebHost apps. Duplicate categories are automatically merged during initialization, and the structure is exposed via a public API endpoint for frontend consumption.

**Key Benefits:**
- ✅ Automatic category merging
- ✅ Hierarchical organization
- ✅ Ordered display
- ✅ Extensible design
- ✅ API-driven architecture
- ✅ Backward-compatible scaffolding
