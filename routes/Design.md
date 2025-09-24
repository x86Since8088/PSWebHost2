# PsWebHost Routing Design

This document outlines the design of the routing system for the PsWebHost project.

## Core Concepts

The routing system is designed to be simple, intuitive, and based on the file system. The core idea is that the URL path and HTTP method of a request map directly to a PowerShell script file in the `routes` directory.

## Request Flow

1.  **Entry Point**: All requests are initially handled by `WebHost.ps1`.
2.  **Request Processing**: The `Process-HttpRequest` function in the `PSWebHost_Support` module is responsible for processing each request.
3.  **Route Resolution**: `Process-HttpRequest` calls the `Resolve-RouteScriptPath` function to determine which script to execute.
4.  **Script Execution**: The located script is then executed.

## Directory Structure and Naming Convention

-   The `routes` directory is the root for all route definitions.
-   Subdirectories within `routes` represent segments of the URL path.
-   The final part of the path is a PowerShell script named after the HTTP method it handles (e.g., `get.ps1`, `post.ps1`).

### Examples

-   A `GET` request to `/spa` will execute the script at `e:\sc\git\PsWebHost\routes\spa\get.ps1`.
-   A `POST` request to `/api/v1/users` would execute `e:\sc\git\PsWebHost\routes\api\v1\users\post.ps1`.
-   A `GET` request to `/api/auth/getaccesstoken` will execute `e:\sc\git\PsWebHost\routes\api\auth\getaccesstoken\get.ps1`.

## Route Script Parameters

Each route script is passed the following parameters:

-   `[System.Net.HttpListenerContext]$Context`: The main context object, which contains both the request and response objects.
-   `[System.Net.HttpListenerRequest]$Request`: The request object, providing access to headers, query parameters, etc.
-   `[System.Net.HttpListenerResponse]$Response`: The response object, used to set the status code, headers, and send the response body.

It is recommended that route scripts define their parameters like this:

```powershell
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)
```

## Special Routes

-   **Static Files**: Requests starting with `/public` are treated as requests for static files and are served directly from the `public` directory. This is handled by `Process-HttpRequest` before the dynamic route resolution.
-   **Root Redirect**: A `GET` request to `/` is automatically redirected to `/spa`.

## Asynchronous vs. Synchronous Execution

The `WebHost.ps1` script can be started with an `-Async` switch.

-   **Asynchronous (Default)**: When running asynchronously, each route script is executed in a separate runspace, allowing the server to handle multiple requests concurrently. This is managed by the `Invoke-ContextRunspace` function.
-   **Synchronous**: If the `-Async` switch is not present, scripts are executed in the main listener thread. This is simpler for debugging but not suitable for production.

---

## SPA (Single Page Application) Design

The SPA is designed as a highly configurable and dynamic layout system. The entire structure and the components within it are defined by a single JSON file, `layout.json`.

### Layout Structure

The layout is divided into five main sections:

-   `titlePane`: A single pane at the top of the page.
-   `leftPane`: A pane on the left side.
-   `rightPane`: A pane on the right side.
-   `middlePanes`: A stack of panes in the center, which build from the top down.
-   `footerPanes`: A stack of panes at the bottom, which build from the bottom up.

Each pane can contain one or more "Elements," which are the individual UI components.

### `layout.json` Schema

The `layout.json` file has a root object that contains keys for each of the layout panes. Each pane's value is an array of Element objects.

```json
{
  "titlePane": [
    {
      "Element_Id": "main-menu",
      "Type": "Menu",
      "Title": "Main Menu",
      "Load": "/api/v1/menu-config",
      "Subscription": "ws://localhost:8080/menu-updates"
    }
  ],
  "leftPane": [
    {
      "Element_Id": "file-explorer",
      "Type": "Menu",
      "Title": "Files",
      "Pinned": true,
      "Load": "/api/v1/files"
    }
  ],
  "rightPane": [
    {
      "Element_Id": "system-status",
      "Type": "Log",
      "Title": "System Log",
      "Subscription": "ws://localhost:8080/system-log"
    }
  ],
  "middlePanes": [
    {
      "Element_Id": "world-map",
      "Type": "Map",
      "Title": "World Map",
      "Load": {
        "map": "/maps/world.svg",
        "coordinates": "/maps/world-coords.json"
      },
      "Subscription": "ws://localhost:8080/map-updates"
    },
    {
      "Element_Id": "server-heatmap",
      "Type": "Heatmap",
      "Title": "Server Load",
      "Subscription": "ws://localhost:8080/server-load"
    }
  ],
  "footerPanes": [
    {
      "Element_Id": "event-stream",
      "Type": "Events",
      "Title": "Real-time Events",
      "Subscription": "ws://localhost:8080/events"
    }
  ]
}
```

### Element Types

#### `Menu`

-   **Description**: A hierarchical menu. Sub-trees can expand on hover or be pinned open.
-   **Properties**:
    -   `Title`: The displayed title of the menu.
    -   `Pinned`: (Optional) boolean, if true, the menu starts in a pinned state.
    -   `Load`: URL to a JSON file defining the menu structure.
-   **Example `Load` JSON**:
    ```json
    [
      { "name": "File", "children": [{ "name": "Open" }, { "name": "Save" }] },
      { "name": "Edit", "children": [{ "name": "Cut" }, { "name": "Copy" }] }
    ]
    ```

#### `Calendar`

-   **Description**: A standard monthly calendar view.
-   **Properties**:
    -   `Load`: URL to a JSON file with a list of events to display.
-   **Example `Load` JSON**:
    ```json
    [
      { "date": "2025-12-25", "title": "Holiday" },
      { "date": "2026-01-01", "title": "New Year" }
    ]
    ```

#### `Heatmap`

-   **Description**: A graphical representation of data where values are depicted by color.
-   **Properties**:
    -   `Subscription`: A WebSocket endpoint that streams data for the heatmap.

#### `Log`

-   **Description**: A real-time log viewer that tails a log file.
-   **Properties**:
    -   `Subscription`: A WebSocket endpoint that streams log lines.

#### `Events`

-   **Description**: A real-time event stream viewer.
-   **Properties**:
    -   `Subscription`: A WebSocket endpoint that streams events.

#### `Map`

-   **Description**: Displays a map graphic (e.g., an SVG) and overlays data on it. Can be updated in real-time.
-   **Properties**:
    -   `Load`: An object containing URLs for the map graphic and coordinate metadata.
    -   `Subscription`: A WebSocket endpoint for real-time data updates. Can also accept KML data.

```
