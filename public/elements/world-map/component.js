const { useState, useEffect, useRef } = React;

const WorldMapCard = ({ onError }) => {
    const mapRef = useRef(null);
    const [pins, setPins] = useState([]);
    const [map, setMap] = useState(null);

    // Load Google Maps script and initialize map
    useEffect(() => {
        let isMounted = true;

        async function initMap() {
            if (!mapRef.current || !isMounted) return;

            try {
                const { Map } = await google.maps.importLibrary("maps");
                const newMap = new Map(mapRef.current, {
                    zoom: 2,
                    center: { lat: 20, lng: 0 },
                    // You can add other map options here
                });
                if (isMounted) {
                    setMap(newMap);
                }
            } catch (error) {
                console.error("Error loading Google Maps:", error);
                if (isMounted) {
                    onError({ message: "Google Maps could not be loaded.", status: "API Error", statusText: error.message });
                }
            }
        }

        initMap();

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
                        // The onError is likely already called by the response check, but this is a fallback.
                        // onError({ message: err.message, name: err.name });
                    }
                });
        };

        fetchData();

        return () => {
            isMounted = false;
        };
    }, [onError]); // Add onError to dependency array

    // Render pins when map and pin data are ready
    useEffect(() => {
        if (map && pins.length > 0) {
            // We need to make sure the 'marker' library is loaded to create markers
            google.maps.importLibrary("marker").then(({ Marker }) => {
                const statusColors = {
                    Operational: 'green',
                    Degraded: 'orange',
                    Outage: 'red'
                };

                pins.forEach(pin => {
                    const marker = new Marker({
                        position: { lat: pin.lat, lng: pin.lng },
                        map: map,
                        title: pin.title,
                        icon: {
                            path: google.maps.SymbolPath.CIRCLE,
                            fillColor: statusColors[pin.status] || 'gray',
                            fillOpacity: 0.9,
                            scale: 7,
                            strokeColor: 'white',
                            strokeWeight: 1,
                        }
                    });

                    // InfoWindow doesn't need a separate library import
                    const infoWindow = new google.maps.InfoWindow({
                        content: `<h4>${pin.title}</h4><p>Status: ${pin.status}</p>`
                    });

                    marker.addListener("click", () => {
                        infoWindow.open(map, marker);
                    });
                });
            }).catch(e => {
                console.error("Failed to load marker library", e);
                onError({ message: "Could not load map markers.", status: "API Error", statusText: e.message });
            });
        }
    }, [map, pins, onError]);

    return (
        <div ref={mapRef} style={{ width: '100%', height: '400px' }}></div>
    );
};

window.cardComponents['world-map'] = WorldMapCard;
