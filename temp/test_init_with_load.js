(async function() {
    var messages = [];
    function log(msg) {
        messages.push(msg);
        console.log('[TestDB]', msg);
    }

    log('Starting test');

    // First, manually load the metrics-database.js
    log('Loading metrics-database.js...');
    await new Promise(function(resolve, reject) {
        var script = document.createElement('script');
        script.src = '/public/lib/metrics-database.js';
        script.onload = function() {
            log('Script loaded');
            resolve();
        };
        script.onerror = function(e) {
            log('Script load error: ' + e);
            reject(new Error('Script load failed'));
        };
        document.head.appendChild(script);
    });

    log('Checking MetricsDatabase: ' + (typeof window.MetricsDatabase));

    if (typeof window.MetricsDatabase === 'undefined') {
        log('MetricsDatabase not defined after load!');
        return { success: false, error: 'MetricsDatabase not defined', messages: messages };
    }

    log('Creating MetricsDatabase instance...');
    var db = new window.MetricsDatabase({
        dbName: 'TestMetrics',
        retentionHours: 1,
        maxRecords: 100
    });

    log('Calling initialize()...');
    try {
        await db.initialize();
        log('Initialize succeeded! workerReady=' + db.workerReady);
    } catch (e) {
        log('Initialize failed: ' + e.message);
        return { success: false, error: e.message, messages: messages };
    }

    log('Destroying db...');
    await db.destroy();
    log('Test complete');

    return { success: true, messages: messages };
})();
