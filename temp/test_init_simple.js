(async function() {
    var results = [];

    // Log helper
    function log(msg) {
        results.push(msg);
        console.log('[TestInit]', msg);
        if (window.logToServer) {
            window.logToServer(msg, 'BrowserTest', 'Info', {});
        }
    }

    log('Starting MetricsDatabase test');

    // Check if class exists
    if (typeof window.MetricsDatabase === 'undefined') {
        log('ERROR: MetricsDatabase class not found');
        return { error: 'MetricsDatabase not found', results: results };
    }
    log('MetricsDatabase class exists');

    // Create instance
    var db = new MetricsDatabase({
        dbName: 'TestDB',
        retentionHours: 1,
        maxRecords: 100
    });
    log('Created MetricsDatabase instance');

    // Initialize with 90 second timeout
    try {
        log('Calling db.initialize()...');
        await db.initialize();
        log('db.initialize() succeeded!');
        log('workerReady: ' + db.workerReady);
        log('sqlLoaded: ' + db.sqlLoaded);
    } catch (e) {
        log('ERROR in initialize: ' + e.message);
        return { error: e.message, results: results };
    }

    // Cleanup
    try {
        await db.destroy();
        log('Cleanup successful');
    } catch (e) {
        log('Cleanup error: ' + e.message);
    }

    return { success: true, results: results };
})();
