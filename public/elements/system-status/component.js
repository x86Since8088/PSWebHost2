const { useState, useEffect } = React;

const SystemStatusCard = ({ onError }) => {
    const [logData, setLogData] = useState([]);

    useEffect(() => {
        let isMounted = true;

        psweb_fetchWithAuthHandling('/api/v1/ui/elements/system-status')
            .then(res => {
                if (!res.ok) {
                    if (isMounted) {
                        onError({ message: "Failed to fetch system status", status: res.status, statusText: res.statusText });
                    }
                    throw new Error(`HTTP error! status: ${res.status}`);
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
        .log-entry { border-bottom: 1px solid #eee; padding: 4px 0; font-family: monospace; font-size: 0.9em; }
        .log-entry .level-INFO { color: #333; }
        .log-entry .level-WARN { color: #ffa500; }
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
