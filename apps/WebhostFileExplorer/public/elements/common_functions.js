/**
 * Common Functions Library for FileExplorer and Editor Components
 *
 * Shared utility functions used across FileExplorer, TextEditor, and HexEditor components.
 * Export as ES6 modules for clean imports.
 */

/**
 * Format bytes to human-readable size (B, KB, MB, GB, TB)
 * @param {number} bytes - Number of bytes
 * @param {number} decimals - Number of decimal places (default: 2)
 * @returns {string} Formatted size string
 */
export function formatFileSize(bytes, decimals = 2) {
    if (!bytes || bytes === 0) return '0 B';

    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));

    return (bytes / Math.pow(k, i)).toFixed(decimals) + ' ' + sizes[i];
}

/**
 * Format duration in milliseconds to human-readable string
 * @param {number} milliseconds - Duration in milliseconds
 * @returns {string} Formatted duration (e.g., "2h 15m", "45s")
 */
export function formatDuration(milliseconds) {
    if (!milliseconds || milliseconds < 0) return '0s';

    const seconds = Math.floor(milliseconds / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) {
        return `${days}d ${hours % 24}h`;
    }
    if (hours > 0) {
        return `${hours}h ${minutes % 60}m`;
    }
    if (minutes > 0) {
        return `${minutes}m ${seconds % 60}s`;
    }
    return `${seconds}s`;
}

/**
 * Format date to localized string
 * @param {Date|string|number} date - Date object, ISO string, or timestamp
 * @param {boolean} includeTime - Whether to include time (default: true)
 * @returns {string} Formatted date string
 */
export function formatDate(date, includeTime = true) {
    if (!date) return 'Unknown';

    try {
        const d = date instanceof Date ? date : new Date(date);

        if (isNaN(d.getTime())) return 'Invalid date';

        if (includeTime) {
            return d.toLocaleString();
        } else {
            return d.toLocaleDateString();
        }
    } catch (error) {
        return 'Invalid date';
    }
}

/**
 * Generate a unique upload/session ID
 * @param {string} prefix - Optional prefix (default: 'id')
 * @returns {string} Unique ID (e.g., "id-1706385620123-a1b2c3")
 */
export function generateUploadId(prefix = 'id') {
    const timestamp = Date.now();
    const random = Math.random().toString(36).substr(2, 9);
    return `${prefix}-${timestamp}-${random}`;
}

/**
 * Determine file type category from filename
 * @param {string} fileName - File name with extension
 * @returns {string} File type: 'text', 'image', 'video', 'audio', 'archive', 'binary', 'folder'
 */
export function getFileType(fileName) {
    if (!fileName) return 'binary';

    const ext = fileName.split('.').pop().toLowerCase();

    // Text files
    const textExts = ['txt', 'md', 'markdown', 'json', 'xml', 'html', 'htm', 'css', 'js', 'ts', 'jsx', 'tsx',
                      'py', 'java', 'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'php', 'rb', 'pl', 'sh', 'bat',
                      'ps1', 'psm1', 'psd1', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'log', 'csv', 'sql'];
    if (textExts.includes(ext)) return 'text';

    // Images
    const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico', 'tiff', 'tif', 'psd'];
    if (imageExts.includes(ext)) return 'image';

    // Videos
    const videoExts = ['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg'];
    if (videoExts.includes(ext)) return 'video';

    // Audio
    const audioExts = ['mp3', 'wav', 'ogg', 'flac', 'aac', 'm4a', 'wma', 'opus'];
    if (audioExts.includes(ext)) return 'audio';

    // Archives
    const archiveExts = ['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso', 'dmg'];
    if (archiveExts.includes(ext)) return 'archive';

    // Documents
    const docExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp'];
    if (docExts.includes(ext)) return 'document';

    return 'binary';
}

/**
 * Check if file is text-editable based on filename
 * @param {string} fileName - File name with extension
 * @returns {boolean} True if file can be edited as text
 */
export function isTextEditable(fileName) {
    const fileType = getFileType(fileName);
    return fileType === 'text';
}

/**
 * Read a chunk of file data
 * @param {File} file - File object
 * @param {number} start - Start byte position
 * @param {number} length - Number of bytes to read
 * @returns {Promise<ArrayBuffer>} Chunk data as ArrayBuffer
 */
export function readFileChunk(file, start, length) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();

        reader.onload = (e) => {
            resolve(e.target.result);
        };

        reader.onerror = (e) => {
            reject(new Error('Failed to read file chunk: ' + e.target.error));
        };

        const slice = file.slice(start, start + length);
        reader.readAsArrayBuffer(slice);
    });
}

/**
 * Parse tree path into components
 * @param {string} path - Tree path (e.g., "local|localhost|User:me/Documents")
 * @returns {Object} Parsed path: { location, host, logicalPath }
 */
export function parseTreePath(path) {
    if (!path) return { location: null, host: null, logicalPath: null };

    const parts = path.split('|');

    return {
        location: parts[0] || null,       // "local" or "remote"
        host: parts[1] || null,            // "localhost" or remote hostname
        logicalPath: parts[2] || null      // "User:me/Documents"
    };
}

/**
 * Build tree path from components
 * @param {string} bucket - Bucket name (e.g., "User:me")
 * @param {string} relativePath - Relative path within bucket
 * @returns {string} Combined logical path
 */
export function buildTreePath(bucket, relativePath) {
    if (!bucket) return relativePath || '';
    if (!relativePath || relativePath === '/') return bucket;

    // Remove leading slash from relative path
    const cleanPath = relativePath.startsWith('/') ? relativePath.substring(1) : relativePath;

    return `${bucket}/${cleanPath}`;
}

/**
 * Extract logical path from full tree path (removes location and host)
 * @param {string} fullPath - Full tree path (e.g., "local|localhost|User:me/Documents")
 * @returns {string} Logical path (e.g., "User:me/Documents")
 */
export function extractLogicalPath(fullPath) {
    if (!fullPath) return '';

    const parts = fullPath.split('|');
    return parts[2] || parts[0] || '';
}

/**
 * Debounce function - delays execution until after wait time of inactivity
 * @param {Function} func - Function to debounce
 * @param {number} wait - Wait time in milliseconds
 * @returns {Function} Debounced function
 */
export function debounce(func, wait) {
    let timeout;

    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };

        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * Throttle function - limits execution to once per time period
 * @param {Function} func - Function to throttle
 * @param {number} limit - Minimum time between executions in milliseconds
 * @returns {Function} Throttled function
 */
export function throttle(func, limit) {
    let inThrottle;

    return function executedFunction(...args) {
        if (!inThrottle) {
            func(...args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    };
}

/**
 * Log message to server via batched logging endpoint
 * @param {string} message - Log message
 * @param {string} level - Log level: 'Info', 'Warning', 'Error', 'Debug'
 * @param {Object} data - Additional data to log
 */
export function logToServer(message, level = 'Info', data = {}) {
    // Use global logToServer if available (from psweb_spa.js)
    if (window.logToServer && typeof window.logToServer === 'function') {
        window.logToServer(message, level, data);
    } else {
        // Fallback: log to console
        console.log(`[${level}] ${message}`, data);
    }
}

/**
 * Show toast notification (if showToast is available globally)
 * @param {string} message - Toast message
 * @param {string} type - Toast type: 'info', 'success', 'warning', 'error'
 */
export function showToast(message, type = 'info') {
    // Use global showToast if available
    if (window.showToast && typeof window.showToast === 'function') {
        window.showToast(message, type);
    } else {
        // Fallback: alert
        alert(`[${type.toUpperCase()}] ${message}`);
    }
}

/**
 * Validate filename for invalid characters
 * @param {string} fileName - File name to validate
 * @returns {Object} { valid: boolean, error: string|null }
 */
export function validateFileName(fileName) {
    if (!fileName || fileName.trim() === '') {
        return { valid: false, error: 'File name cannot be empty' };
    }

    // Check for invalid characters (Windows + Linux)
    const invalidChars = /[<>:"|?*\x00-\x1f]/;
    if (invalidChars.test(fileName)) {
        return { valid: false, error: 'File name contains invalid characters: < > : " | ? *' };
    }

    // Check for reserved Windows names
    const reservedNames = /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/i;
    const nameWithoutExt = fileName.split('.')[0];
    if (reservedNames.test(nameWithoutExt)) {
        return { valid: false, error: `File name "${nameWithoutExt}" is reserved by the system` };
    }

    // Check for trailing dots or spaces (Windows)
    if (fileName.endsWith('.') || fileName.endsWith(' ')) {
        return { valid: false, error: 'File name cannot end with a dot or space' };
    }

    // Check length (most filesystems support 255 characters)
    if (fileName.length > 255) {
        return { valid: false, error: 'File name is too long (maximum 255 characters)' };
    }

    return { valid: true, error: null };
}

/**
 * Sanitize filename by removing/replacing invalid characters
 * @param {string} fileName - File name to sanitize
 * @param {string} replacement - Replacement character for invalid chars (default: '_')
 * @returns {string} Sanitized file name
 */
export function sanitizeFileName(fileName, replacement = '_') {
    if (!fileName) return '';

    // Replace invalid characters
    let sanitized = fileName.replace(/[<>:"|?*\x00-\x1f]/g, replacement);

    // Remove trailing dots and spaces
    sanitized = sanitized.replace(/[\s.]+$/, '');

    // Handle reserved names by appending underscore
    const nameWithoutExt = sanitized.split('.')[0];
    const reservedNames = /^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/i;
    if (reservedNames.test(nameWithoutExt)) {
        sanitized = replacement + sanitized;
    }

    // Truncate if too long
    if (sanitized.length > 255) {
        sanitized = sanitized.substring(0, 255);
    }

    return sanitized || 'unnamed';
}

/**
 * Calculate MD5 hash of file (for integrity checking)
 * @param {File} file - File object
 * @param {Function} onProgress - Progress callback (percent)
 * @returns {Promise<string>} MD5 hash as hex string
 * Note: Requires crypto-js library or SubtleCrypto API
 */
export async function calculateFileMD5(file, onProgress = null) {
    // This would require crypto-js or SubtleCrypto
    // Placeholder implementation - would need actual crypto library
    throw new Error('calculateFileMD5 requires crypto library implementation');
}

/**
 * Copy text to clipboard
 * @param {string} text - Text to copy
 * @returns {Promise<boolean>} True if successful
 */
export async function copyToClipboard(text) {
    try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            await navigator.clipboard.writeText(text);
            return true;
        } else {
            // Fallback for older browsers
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            document.body.removeChild(textarea);
            return true;
        }
    } catch (error) {
        console.error('Failed to copy to clipboard:', error);
        return false;
    }
}

/**
 * Check if browser supports a feature
 * @param {string} feature - Feature name: 'websocket', 'serviceworker', 'webworker', 'indexeddb'
 * @returns {boolean} True if supported
 */
export function supportsFeature(feature) {
    switch (feature.toLowerCase()) {
        case 'websocket':
            return typeof WebSocket !== 'undefined';
        case 'serviceworker':
            return 'serviceWorker' in navigator;
        case 'webworker':
            return typeof Worker !== 'undefined';
        case 'indexeddb':
            return typeof indexedDB !== 'undefined';
        case 'filereader':
            return typeof FileReader !== 'undefined';
        case 'blob':
            return typeof Blob !== 'undefined';
        default:
            return false;
    }
}

/**
 * Parse query string to object
 * @param {string} queryString - Query string (with or without leading '?')
 * @returns {Object} Parsed query parameters
 */
export function parseQueryString(queryString) {
    if (!queryString) return {};

    const params = {};
    const cleanQuery = queryString.startsWith('?') ? queryString.substring(1) : queryString;

    cleanQuery.split('&').forEach(pair => {
        const [key, value] = pair.split('=');
        if (key) {
            params[decodeURIComponent(key)] = value ? decodeURIComponent(value) : '';
        }
    });

    return params;
}

/**
 * Build query string from object
 * @param {Object} params - Query parameters
 * @returns {string} Query string (without leading '?')
 */
export function buildQueryString(params) {
    if (!params || Object.keys(params).length === 0) return '';

    return Object.entries(params)
        .filter(([_, value]) => value !== null && value !== undefined)
        .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`)
        .join('&');
}

// Export all functions as default object as well
export default {
    formatFileSize,
    formatDuration,
    formatDate,
    generateUploadId,
    getFileType,
    isTextEditable,
    readFileChunk,
    parseTreePath,
    buildTreePath,
    extractLogicalPath,
    debounce,
    throttle,
    logToServer,
    showToast,
    validateFileName,
    sanitizeFileName,
    copyToClipboard,
    supportsFeature,
    parseQueryString,
    buildQueryString
};
