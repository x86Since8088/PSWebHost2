const { useState, useEffect } = React;

const SystemStatusCard = ({ onError }) => {
    const [logData, setLogData] = useState([]);

    useEffect(() => {
        let isMounted = true;

        window.psweb_fetchWithAuthHandling('/cards/system-status')
            .then(res => {
                if (!res.ok) {
                    if (isMounted) {
                        onError({ message: "Failed to fetch system status", status: res.status, statusText: res.statusText });
                    }
                    const error = new Error(`HTTP error! status: ${res.status}`);
                    error.status = res.status;
                    error.statusText = res.statusText;
                    throw error;
                }
                return res.json();
            })
            .then(data => {
                if (isMounted) {
                    setLogData(data);
                }
            })
            .catch(err => {
                console.error("SystemStatusCard fetch error:", err);
            });

        return () => {
            isMounted = false;
        };
    }, [onError]);

    const styles = `
        #system-status-content { background: #ffffff; padding: 12px; }
        .log-entry { border-bottom: 1px solid #eee; padding: 4px 0; font-family: monospace; font-size: 0.9em; color: #333; background: #fff; }
        .log-entry .level-INFO { color: #333; }
        .log-entry .level-WARN { color: #cc8800; }
        .log-entry .level-ERROR { color: #dc3545; font-weight: bold; }
    `;

    return (
        <>
            <style>{styles}</style>
            <div id="system-status-content">
                {logData.map((entry, index) => (
                    <div key={index} className="log-entry">
                        <span className={`level-${entry.level}`}>[{entry.level}]</span> {entry.message}
                    </div>
                ))}
            </div>
        </>
    );
};

window.cardComponents['system-status'] = SystemStatusCard;
