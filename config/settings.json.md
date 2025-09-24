# `settings.json` Configuration

This document describes the structure and available settings for the `config/settings.json` file.

## Root Object

The JSON file should contain a single root object.

### `WebServer` (Object)

Contains settings related to the core web server.

-   **`Port`** (Number): The TCP port on which the server will listen for incoming HTTP requests. 
    *Example: `8080`*

### `MimeTypes` (Object)

Contains a dictionary of file extensions and their corresponding MIME types. This allows the server to send the correct `Content-Type` header for static files.

-   **Keys**: The file extension as a string, including the leading dot (e.g., `".css"`).
-   **Values**: The full MIME type string (e.g., `"text/css"`).

#### Example `MimeTypes` Configuration

```json
{
  "MimeTypes": {
    ".css": "text/css",
    ".js": "application/javascript",
    ".html": "text/html",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".svg": "image/svg+xml",
    ".json": "application/json",
    ".txt": "text/plain"
  }
}
```
