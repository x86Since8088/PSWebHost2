const { useState, useEffect, useRef } = React;

const WorldMapCard = ({ onError }) => {
    const containerRef = useRef(null);
    const [pins, setPins] = useState([]);
    const [mapDef, setMapDef] = useState(null);
    const [imageLoaded, setImageLoaded] = useState(false);

    // Load map definition
    useEffect(() => {
        let isMounted = true;

        fetch('/public/elements/world-map/map-definition.json')
            .then(res => {
                if (!res.ok) {
                    throw new Error(`Failed to load map definition: ${res.status}`);
                }
                return res.json();
            })
            .then(data => {
                if (isMounted) {
                    setMapDef(data);
                }
            })
            .catch(err => {
                if (isMounted) {
                    console.error("Error loading map definition:", err);
                    onError({ message: "Map definition could not be loaded.", status: "Error", statusText: err.message });
                }
            });

        return () => {
            isMounted = false;
        };
    }, [onError]);

    // Fetch pin data
    useEffect(() => {
        let isMounted = true;

        const fetchData = () => {
            psweb_fetchWithAuthHandling('/api/v1/ui/elements/world-map')
                .then(res => {
                    if (!res.ok) {
                        if (isMounted) {
                            onError({ message: "Failed to fetch world map data", status: res.status, statusText: res.statusText });
                        }
                        throw new Error(`HTTP error! status: ${res.status}`);
                    }
                    return res.text();
                })
                .then(text => {
                    const data = text ? JSON.parse(text) : [];
                    if (isMounted) {
                        setPins(data);
                    }
                })
                .catch(err => {
                    if (err.name !== 'Unauthorized' && isMounted) {
                        console.error("WorldMapCard fetch error:", err);
                    }
                });
        };

        fetchData();

        return () => {
            isMounted = false;
        };
    }, [onError]);

    // Convert lat/lng to pixel coordinates
    const latLngToPixel = (lat, lng) => {
        if (!mapDef) return { x: 0, y: 0 };

        const { topLeft, bottomRight, imageWidth, imageHeight, euclideanCurvature } = mapDef;

        // Calculate normalized position (0 to 1)
        const normalizedX = (lng - topLeft.lng) / (bottomRight.lng - topLeft.lng);
        const normalizedY = (lat - topLeft.lat) / (bottomRight.lat - topLeft.lat);

        // Apply curvature adjustment if specified
        // For euclideanCurvature = 0, this is a simple linear mapping
        // For non-zero values, apply spherical adjustment
        let adjustedY = normalizedY;
        if (euclideanCurvature !== 0) {
            // Apply curvature correction (simplified spherical adjustment)
            const latRadians = (lat * Math.PI) / 180;
            const topLatRadians = (topLeft.lat * Math.PI) / 180;
            const bottomLatRadians = (bottomRight.lat * Math.PI) / 180;
            adjustedY = (Math.sin(latRadians) - Math.sin(topLatRadians)) /
                       (Math.sin(bottomLatRadians) - Math.sin(topLatRadians));
        }

        return {
            x: normalizedX * imageWidth,
            y: adjustedY * imageHeight
        };
    };

    // Render the map and pins
    useEffect(() => {
        if (!containerRef.current || !mapDef || !imageLoaded) return;

        const container = containerRef.current;
        const svg = container.querySelector('svg');
        if (!svg) return;

        // Clear existing pins
        const existingPins = svg.querySelectorAll('.map-pin');
        existingPins.forEach(pin => pin.remove());

        // Render pins
        const statusColors = {
            Operational: '#4CAF50',
            Degraded: '#FF9800',
            Outage: '#F44336'
        };

        pins.forEach(pin => {
            const pos = latLngToPixel(pin.lat, pin.lng);
            const color = statusColors[pin.status] || '#999999';

            // Create pin marker
            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circle.setAttribute('class', 'map-pin');
            circle.setAttribute('cx', pos.x);
            circle.setAttribute('cy', pos.y);
            circle.setAttribute('r', '8');
            circle.setAttribute('fill', color);
            circle.setAttribute('stroke', 'white');
            circle.setAttribute('stroke-width', '2');
            circle.setAttribute('style', 'cursor: pointer;');
            circle.setAttribute('data-title', pin.title);
            circle.setAttribute('data-status', pin.status);

            // Add click handler for tooltip
            circle.addEventListener('click', (e) => {
                alert(`${pin.title}\nStatus: ${pin.status}`);
            });

            svg.appendChild(circle);
        });
    }, [pins, mapDef, imageLoaded]);

    if (!mapDef) {
        return <div style={{ padding: '20px', textAlign: 'center' }}>Loading map...</div>;
    }

    return (
        <div
            ref={containerRef}
            style={{
                width: '100%',
                height: '100%',
                position: 'relative',
                overflow: 'hidden',
                backgroundColor: '#e0e0e0'
            }}
        >
            <svg
                width="100%"
                height="100%"
                viewBox={`0 0 ${mapDef.imageWidth} ${mapDef.imageHeight}`}
                preserveAspectRatio="xMidYMid meet"
            >
                <image
                    href={`/public/elements/world-map/${mapDef.imageFile}`}
                    width={mapDef.imageWidth}
                    height={mapDef.imageHeight}
                    onLoad={() => setImageLoaded(true)}
                    onError={(e) => {
                        console.error("Failed to load map image");
                        onError({
                            message: "Map image could not be loaded. Please ensure world-map.png exists in /public/elements/world-map/",
                            status: "Image Error",
                            statusText: "File not found"
                        });
                    }}
                />
            </svg>
        </div>
    );
};

window.cardComponents['world-map'] = WorldMapCard;
