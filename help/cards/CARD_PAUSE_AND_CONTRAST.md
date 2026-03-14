# Card Pause and High Contrast Features

**Date:** 2026-01-17
**Status:** ✅ Implemented

---

## Overview

All cards now include two new control buttons in the card header:
1. **Pause/Resume Button** (⏸/▶) - Stops/resumes component updates
2. **High Contrast Toggle** (◐) - Applies high contrast mode to the card

---

## Features

### 1. Pause/Resume Button

**Icon:** ⏸ (Pause) / ▶ (Resume)
**Location:** Card header actions (leftmost button)
**Purpose:** Allows users to freeze component updates for easier reading or interaction

**Visual Indicators:**
- Button shows ⏸ when running, ▶ when paused
- When paused, button turns amber/yellow color
- "PAUSED" badge appears next to card title
- Console log message when toggled

**Use Cases:**
- Freeze scrolling logs to read specific entries
- Pause auto-refreshing charts to examine data
- Stop background polling while interacting with data
- Reduce CPU usage by pausing non-critical cards

### 2. High Contrast Toggle

**Icon:** ◐ (Half-circle)
**Location:** Card header actions (second from left)
**Purpose:** Applies high contrast mode for better visibility

**Visual Effects:**
- Increases contrast by 1.5x
- Increases brightness by 1.1x
- Adds solid black 2px border
- Ensures white background (if not already set)
- Button highlights with yellow background when active

**Use Cases:**
- Improve readability for vision impairment
- Better visibility in bright environments
- Enhanced text contrast on complex backgrounds
- Presentation mode with clearer visuals

---

## For Component Developers

### Accessing Pause State

Components receive pause state through props:

```javascript
window.cardComponents['my-component'] = function MyComponent(props) {
    const { isPaused, pauseStateRef } = props;

    // Method 1: Use isPaused prop (triggers re-render)
    React.useEffect(() => {
        if (!isPaused) {
            // Component is running - start updates
            const interval = setInterval(() => {
                // Update logic here
            }, 1000);

            return () => clearInterval(interval);
        }
        // Component is paused - cleanup happens automatically
    }, [isPaused]);

    // Method 2: Use pauseStateRef (no re-render, for intervals/loops)
    React.useEffect(() => {
        const interval = setInterval(() => {
            // Check pause state before updating
            if (!pauseStateRef.current.paused) {
                // Update logic here
            }
        }, 1000);

        return () => clearInterval(interval);
    }, []);

    return <div>My Component</div>;
};
```

### Example: Auto-Refreshing Component

```javascript
window.cardComponents['auto-refresh-data'] = function AutoRefreshData(props) {
    const { isPaused, pauseStateRef } = props;
    const [data, setData] = React.useState([]);
    const [lastUpdate, setLastUpdate] = React.useState(null);

    const fetchData = async () => {
        const response = await fetch('/api/v1/data');
        const result = await response.json();
        setData(result.data);
        setLastUpdate(new Date().toLocaleTimeString());
    };

    React.useEffect(() => {
        // Initial fetch
        fetchData();

        // Set up interval that respects pause state
        const interval = setInterval(() => {
            // Only fetch if not paused
            if (!pauseStateRef.current.paused) {
                fetchData();
            }
        }, 5000);

        return () => clearInterval(interval);
    }, []);

    return (
        <div>
            <h3>Auto-Refreshing Data {isPaused && '(Paused)'}</h3>
            <p>Last Update: {lastUpdate}</p>
            <ul>
                {data.map((item, i) => (
                    <li key={i}>{item.name}</li>
                ))}
            </ul>
        </div>
    );
};
```

### Example: Web Component with Pause Support

```javascript
class MyComponentClass extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.paused = false;
        this.updateInterval = null;
    }

    connectedCallback() {
        this.render();
        this.startUpdates();
    }

    disconnectedCallback() {
        this.stopUpdates();
    }

    setPaused(paused) {
        this.paused = paused;
        if (paused) {
            this.stopUpdates();
        } else {
            this.startUpdates();
        }
    }

    startUpdates() {
        if (this.updateInterval) return;

        this.updateInterval = setInterval(() => {
            if (!this.paused) {
                this.updateData();
            }
        }, 1000);
    }

    stopUpdates() {
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }
    }

    updateData() {
        // Update logic here
        this.render();
    }

    render() {
        this.shadowRoot.innerHTML = `
            <style>
                :host { display: block; padding: 10px; }
            </style>
            <div>My Component Content</div>
        `;
    }
}

if (!customElements.get('my-component')) {
    customElements.define('my-component', MyComponentClass);
}

// React wrapper with pause support
window.cardComponents['my-component'] = function(props) {
    const { isPaused, pauseStateRef } = props;
    const containerRef = React.useRef(null);
    const elementRef = React.useRef(null);

    React.useEffect(() => {
        if (containerRef.current && !elementRef.current) {
            const element = document.createElement('my-component');
            containerRef.current.appendChild(element);
            elementRef.current = element;

            return () => {
                if (containerRef.current && containerRef.current.contains(element)) {
                    containerRef.current.removeChild(element);
                }
            };
        }
    }, []);

    // Update web component when pause state changes
    React.useEffect(() => {
        if (elementRef.current && elementRef.current.setPaused) {
            elementRef.current.setPaused(isPaused);
        }
    }, [isPaused]);

    return React.createElement('div', {
        ref: containerRef,
        style: { width: '100%', height: '100%' }
    });
};
```

### Example: Component with Manual Pause Check

```javascript
window.cardComponents['streaming-logs'] = function StreamingLogs(props) {
    const { pauseStateRef } = props;
    const [logs, setLogs] = React.useState([]);
    const logsRef = React.useRef([]);

    React.useEffect(() => {
        const eventSource = new EventSource('/api/v1/logs/stream');

        eventSource.onmessage = (event) => {
            // Only add log if not paused
            if (!pauseStateRef.current.paused) {
                const newLog = JSON.parse(event.data);
                logsRef.current = [...logsRef.current, newLog];
                setLogs(logsRef.current);
            }
            // When paused, logs are buffered by EventSource but not displayed
        };

        return () => eventSource.close();
    }, []);

    return (
        <div style={{ fontFamily: 'monospace', fontSize: '12px' }}>
            {logs.map((log, i) => (
                <div key={i}>{log.timestamp} {log.message}</div>
            ))}
        </div>
    );
};
```

---

## High Contrast Mode

### How It Works

When the high contrast button is clicked:
1. Card applies CSS filter: `contrast(1.5) brightness(1.1)`
2. Card adds a solid 2px black border
3. Background becomes white (if not already set)
4. Card gets `high-contrast` CSS class

### Custom High Contrast Styles

Components can add custom high contrast styles:

```javascript
window.cardComponents['my-component'] = function MyComponent(props) {
    return (
        <div>
            <style>
                {`
                    .high-contrast .my-text {
                        color: #000;
                        font-weight: bold;
                    }
                    .high-contrast .my-background {
                        background-color: #fff;
                    }
                `}
            </style>
            <div className="my-text">High contrast text</div>
            <div className="my-background">High contrast background</div>
        </div>
    );
};
```

### Detecting High Contrast Mode

Components don't currently receive high contrast state as a prop (CSS handles it), but you can detect it:

```javascript
// Check if parent card has high-contrast class
const isHighContrast = containerRef.current?.closest('.high-contrast') !== null;
```

---

## User Interface

### Card Header Layout

```
┌────────────────────────────────────────────────────────┐
│ [Icon] Card Title [PAUSED]    [⏸][◐][?][⛶][🗖][⚙][×] │
└────────────────────────────────────────────────────────┘
  ↑      ↑         ↑              ↑  ↑  ↑  ↑  ↑  ↑  ↑
  │      │         │              │  │  │  │  │  │  └─ Close
  │      │         │              │  │  │  │  │  └──── Settings
  │      │         │              │  │  │  │  └─────── Maximize
  │      │         │              │  │  │  └────────── Fullscreen
  │      │         │              │  │  └───────────── Help
  │      │         │              │  └──────────────── High Contrast
  │      │         │              └─────────────────── Pause/Resume
  │      │         └────────────────────────────────── Pause Badge
  │      └──────────────────────────────────────────── Title
  └─────────────────────────────────────────────────── Icon
```

### Button States

**Pause Button:**
- Not paused: ⏸ (normal color)
- Paused: ▶ (amber/yellow color)

**High Contrast Button:**
- Normal: ◐ (normal color, transparent background)
- Active: ◐ (black color, yellow background, bold)

### PAUSED Badge

When a card is paused, a badge appears next to the title:
- Background: Amber (#ffc107)
- Text: Black, bold
- Content: "PAUSED"

---

## Best Practices

### For Component Developers

1. **Always Respect Pause State**
   - Check `pauseStateRef.current.paused` before updates
   - Don't poll APIs when paused
   - Don't update state when paused

2. **Use the Right Method**
   - Use `isPaused` prop when you need re-render on pause
   - Use `pauseStateRef` for interval checks (no re-render)

3. **Clean Up Properly**
   - Clear intervals in `useEffect` cleanup
   - Close connections when paused or unmounted

4. **Provide Visual Feedback**
   - Show "(Paused)" indicator in component if helpful
   - Display last update timestamp

5. **Test Pause Behavior**
   - Verify updates stop when paused
   - Verify updates resume when unpaused
   - Check for memory leaks

### For Users

1. **Pause When Needed**
   - Pause scrolling content to read details
   - Pause charts to examine specific data points
   - Pause to reduce CPU usage

2. **High Contrast Usage**
   - Use for better readability
   - Helpful in bright environments
   - Good for screenshots/presentations

---

## Migration Guide

### Existing Components

Existing components will work without changes:
- Pause functionality is optional
- Components that ignore pause state continue updating
- High contrast applies automatically via CSS

### Recommended Update

Add pause support to auto-updating components:

```javascript
// Before
window.cardComponents['my-component'] = function(props) {
    React.useEffect(() => {
        const interval = setInterval(() => {
            updateData();
        }, 1000);
        return () => clearInterval(interval);
    }, []);
    // ...
};

// After
window.cardComponents['my-component'] = function(props) {
    const { pauseStateRef } = props;

    React.useEffect(() => {
        const interval = setInterval(() => {
            if (!pauseStateRef.current.paused) {
                updateData();
            }
        }, 1000);
        return () => clearInterval(interval);
    }, []);
    // ...
};
```

---

## Technical Details

### State Management

- **isPaused:** Boolean state, triggers re-renders
- **isHighContrast:** Boolean state, triggers re-renders
- **pauseStateRef:** Ref object for interval checks without re-renders

### Props Passed to Components

```javascript
{
    element: { /* card element data */ },
    onError: function(error) { /* error handler */ },
    isPaused: boolean,           // Pause state (triggers re-render)
    pauseStateRef: { current: { paused: boolean } }  // Ref (no re-render)
}
```

### CSS Classes

- `.high-contrast` - Applied to card when high contrast is active

### Inline Styles Applied

High contrast mode applies:
```javascript
{
    filter: 'contrast(1.5) brightness(1.1)',
    border: '2px solid #000',
    backgroundColor: '#ffffff'
}
```

---

## Examples

### Task Manager with Pause

```javascript
window.cardComponents['task-manager'] = function TaskManager(props) {
    const { isPaused, pauseStateRef } = props;
    const [tasks, setTasks] = React.useState([]);

    const loadTasks = async () => {
        const response = await fetch('/api/v1/tasks');
        const data = await response.json();
        setTasks(data.tasks);
    };

    React.useEffect(() => {
        loadTasks();

        // Auto-refresh every 5 seconds (but only when not paused)
        const interval = setInterval(() => {
            if (!pauseStateRef.current.paused) {
                loadTasks();
            }
        }, 5000);

        return () => clearInterval(interval);
    }, []);

    return (
        <div>
            <h3>Tasks {isPaused && '⏸'}</h3>
            {tasks.map(task => (
                <div key={task.id}>{task.name}</div>
            ))}
        </div>
    );
};
```

### Real-time Events with Pause

```javascript
window.cardComponents['realtime-events'] = function RealtimeEvents(props) {
    const { pauseStateRef } = props;
    const [events, setEvents] = React.useState([]);
    const queueRef = React.useRef([]);

    React.useEffect(() => {
        const ws = new WebSocket('ws://localhost:8080/events');

        ws.onmessage = (msg) => {
            const event = JSON.parse(msg.data);

            if (!pauseStateRef.current.paused) {
                // Show immediately if not paused
                setEvents(prev => [event, ...prev].slice(0, 100));
            } else {
                // Queue for later if paused
                queueRef.current.push(event);
            }
        };

        // Process queued events when unpaused
        const interval = setInterval(() => {
            if (!pauseStateRef.current.paused && queueRef.current.length > 0) {
                setEvents(prev => [...queueRef.current, ...prev].slice(0, 100));
                queueRef.current = [];
            }
        }, 1000);

        return () => {
            ws.close();
            clearInterval(interval);
        };
    }, []);

    return (
        <div>
            {events.map((event, i) => (
                <div key={i}>{event.timestamp}: {event.message}</div>
            ))}
        </div>
    );
};
```

---

## Troubleshooting

### Component Still Updates When Paused

**Problem:** Updates continue even when paused

**Solution:** Ensure you're checking `pauseStateRef.current.paused`:
```javascript
if (!pauseStateRef.current.paused) {
    // Update logic
}
```

### High Contrast Not Working

**Problem:** Custom styles override high contrast

**Solution:** Use `!important` or check for `.high-contrast` class:
```css
.high-contrast .my-element {
    color: #000 !important;
}
```

### Memory Leak When Paused

**Problem:** Intervals not clearing properly

**Solution:** Always clean up in useEffect return:
```javascript
React.useEffect(() => {
    const interval = setInterval(/* ... */, 1000);
    return () => clearInterval(interval);  // ← Must have this
}, []);
```

---

## Summary

✅ **Pause/Resume Button** - Stops component updates for easier reading
✅ **High Contrast Toggle** - Improves visibility with enhanced contrast
✅ **Props-Based API** - Simple `isPaused` and `pauseStateRef` props
✅ **Backwards Compatible** - Existing components work unchanged
✅ **User-Friendly** - Clear visual indicators and tooltips

**Benefits:**
- Better user experience for reading dynamic content
- Improved accessibility with high contrast mode
- Reduced resource usage by pausing non-critical cards
- Professional controls consistent across all cards

---

**Last Updated:** 2026-01-17
**Author:** PSWebHost Development Team
**Status:** ✅ Production Ready
