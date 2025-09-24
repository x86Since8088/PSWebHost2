const { useState, useEffect } = React;

const ServerHeatmapCard = ({ onError }) => {
    const [heatmapData, setHeatmapData] = useState([]);

    useEffect(() => {
        let isMounted = true;

        psweb_fetchWithAuthHandling('/api/v1/ui/elements/server-heatmap')
            .then(res => {
                if (!res.ok) {
                    if (isMounted) {
                        onError({ message: "Failed to fetch heatmap data", status: res.status, statusText: res.statusText });
                    }
                    throw new Error(`HTTP error! status: ${res.status}`);
                }
                return res.json();
            })
            .then(data => {
                if (isMounted) {
                    setHeatmapData(data);
                }
            })
            .catch(err => {
                console.error("ServerHeatmapCard fetch error:", err);
            });

        return () => {
            isMounted = false;
        };
    }, [onError]);

    const styles = `
        .heatmap-grid { display: grid; grid-template-columns: repeat(10, 1fr); gap: 2px; }
        .heatmap-cell { width: 100%; padding-bottom: 100%; /* Aspect ratio 1:1 */ position: relative; }
        .heatmap-cell-inner { position: absolute; inset: 0; display: flex; justify-content: center; align-items: center; font-size: 0.7em; color: white; }
    `;

    return (
        <>
            <style>{styles}</style>
            <div className="heatmap-grid">
                {heatmapData.flat().map((value, index) => {
                    const blue = 255 - Math.round(value * 2.55);
                    const red = Math.round(value * 2.55);
                    const color = `rgb(${red}, 0, ${blue})`;
                    return (
                        <div key={index} className="heatmap-cell">
                            <div className="heatmap-cell-inner" style={{ backgroundColor: color }}>
                                {value}
                            </div>
                        </div>
                    );
                })}
            </div>
        </>
    );
};

window.cardComponents['server-heatmap'] = ServerHeatmapCard;
