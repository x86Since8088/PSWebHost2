const { useState, useEffect } = React;

const EventStreamCard = ({ onError }) => {
    const [events, setEvents] = useState([]);

    useEffect(() => {
        let isMounted = true;

        const fetchData = () => {
            psweb_fetchWithAuthHandling('/api/v1/ui/elements/event-stream')
                .then(res => {
                    if (!res.ok) {
                        if (isMounted) {
                            onError({ message: "Failed to fetch event stream", status: res.status, statusText: res.statusText });
                        }
                        throw new Error(`HTTP error! status: ${res.status}`);
                    }
                    return res.text();
                })
                .then(text => {
                    const data = text ? JSON.parse(text) : [];
                    if (isMounted) {
                        const eventsArray = (Array.isArray(data) ? data : [data]).map(event => ({
                            ...event,
                            Date: new Date(event.Date).toLocaleString(),
                            Data: event.Data ? JSON.stringify(event.Data) : ''
                        }));
                        setEvents(eventsArray);
                    }
                })
                .catch(err => {
                    if (err.name !== 'Unauthorized' && isMounted) {
                        console.error("EventStreamCard fetch error:", err);
                        onError({ message: err.message, name: err.name });
                    }
                });
        };

        fetchData();

        return () => {
            isMounted = false;
        };
    }, []); // Intentionally empty to run only once

    const columns = [
        { key: 'Date', label: 'Date' },
        { key: 'state', label: 'State' },
        { key: 'UserID', label: 'User ID' },
        { key: 'Provider', label: 'Provider' },
        { key: 'Data', label: 'Details' },
    ];

    return (
        <div className="event-stream-container">
            {events.length > 0 ? (
                <SortableTable data={events} columns={columns} />
            ) : (
                <p>Loading events...</p>
            )}
        </div>
    );
};

window.cardComponents['event-stream'] = EventStreamCard;
