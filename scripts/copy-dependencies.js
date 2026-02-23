/**
 * Copy DuckDB-WASM and Apache Arrow dependencies from node_modules to public/lib
 */

const fs = require('fs');
const path = require('path');

const copyFile = (src, dest) => {
    try {
        // Ensure destination directory exists
        const destDir = path.dirname(dest);
        if (!fs.existsSync(destDir)) {
            fs.mkdirSync(destDir, { recursive: true });
        }

        // Copy file
        fs.copyFileSync(src, dest);

        // Get file size
        const stats = fs.statSync(dest);
        const sizeKB = (stats.size / 1024).toFixed(2);
        const sizeMB = (stats.size / 1024 / 1024).toFixed(2);
        const sizeDisplay = stats.size > 1024 * 1024 ? `${sizeMB}MB` : `${sizeKB}KB`;

        console.log(`✓ Copied: ${path.basename(dest)} (${sizeDisplay})`);
        return true;
    } catch (err) {
        console.error(`✗ Failed to copy ${path.basename(src)}: ${err.message}`);
        return false;
    }
};

console.log('\n===== Copying DuckDB-WASM Dependencies =====\n');

const rootDir = path.resolve(__dirname, '..');
const nodeModulesDir = path.join(rootDir, 'node_modules');
const publicLibDir = path.join(rootDir, 'public', 'lib');

// Define files to copy (modern DuckDB-WASM doesn't have duckdb-mvp.wasm.js)
const dependencies = [
    {
        src: path.join(nodeModulesDir, '@duckdb/duckdb-wasm/dist/duckdb-mvp.wasm'),
        dest: path.join(publicLibDir, 'duckdb-mvp.wasm')
    },
    {
        src: path.join(nodeModulesDir, '@duckdb/duckdb-wasm/dist/duckdb-browser-mvp.worker.js'),
        dest: path.join(publicLibDir, 'duckdb-browser-mvp.worker.js')
    },
    {
        src: path.join(nodeModulesDir, '@duckdb/duckdb-wasm/dist/duckdb-browser.mjs'),
        dest: path.join(publicLibDir, 'duckdb-browser.mjs')
    },
    {
        src: path.join(nodeModulesDir, 'apache-arrow/Arrow.es2015.min.js'),
        dest: path.join(publicLibDir, 'apache-arrow.es2015.min.js')
    }
];

let successCount = 0;
let failCount = 0;

dependencies.forEach(dep => {
    if (copyFile(dep.src, dep.dest)) {
        successCount++;
    } else {
        failCount++;
    }
});

console.log(`\n===== Copy Summary =====`);
console.log(`✓ Copied: ${successCount}`);
console.log(`✗ Failed: ${failCount}`);

if (failCount === 0) {
    console.log('\n✓ All dependencies copied successfully!');
    process.exit(0);
} else {
    console.log('\n⚠ Some files failed to copy. Check errors above.');
    process.exit(1);
}
