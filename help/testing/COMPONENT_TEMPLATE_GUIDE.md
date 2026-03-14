# PSWebHost Component Template Guide

**Date:** 2026-01-17

---

## Component.js Template

All PSWebHost components should follow this structure to avoid re-registration errors and work properly with the SPA framework.

### Template Structure

```javascript
/**
 * Your Component Name
 *
 * Description of what this component does
 */

class YourComponentClass extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });

        // Initialize state
        this.state = {
            // Your state properties
        };
    }

    connectedCallback() {
        this.render();
        // Initialize component
    }

    disconnectedCallback() {
        // Cleanup (remove event listeners, intervals, etc.)
    }

    setState(newState) {
        this.state = { ...this.state, ...newState };
        this.render();
    }

    render() {
        this.shadowRoot.innerHTML = `
            <style>
                /* Your styles here */
            </style>

            <div class="container">
                <!-- Your HTML here -->
            </div>
        `;

        this.attachEventListeners();
    }

    attachEventListeners() {
        // Attach event listeners to shadow DOM elements
    }
}

// ⚠️ IMPORTANT: Check before registering to prevent re-definition errors
if (!customElements.get('your-component-name')) {
    customElements.define('your-component-name', YourComponentClass);
}

// Register in window.cardComponents for SPA framework
window.cardComponents = window.cardComponents || {};
window.cardComponents['your-component-name'] = function(props) {
    return `<your-component-name></your-component-name>`;
};
```

---

## Key Points

### 1. Custom Element Registration

**Always check before defining:**
```javascript
if (!customElements.get('your-component-name')) {
    customElements.define('your-component-name', YourComponentClass);
}
```

**Why?**
- Components can be loaded multiple times when cards are opened
- `customElements.define()` throws error if element is already defined
- Checking first prevents: `DOMException: 'your-component' has already been defined`

### 2. SPA Framework Registration

**Register in window.cardComponents:**
```javascript
window.cardComponents = window.cardComponents || {};
window.cardComponents['your-component-name'] = function(props) {
    return `<your-component-name></your-component-name>`;
};
```

**Why?**
- The SPA framework checks `window.cardComponents` to verify component is loaded
- The function returns the HTML tag to insert into the card
- Can accept `props` for future dynamic configuration

### 3. Component Naming

**Use kebab-case:**
- ✅ `'task-manager'`
- ✅ `'user-profile'`
- ✅ `'data-grid'`
- ❌ `'taskManager'` (not valid custom element name)
- ❌ `'TaskManager'` (not valid custom element name)

**Custom element names must:**
- Contain a hyphen `-`
- Start with a lowercase letter
- Not be a reserved name

### 4. Shadow DOM

**Use shadow DOM for encapsulation:**
```javascript
this.attachShadow({ mode: 'open' });
```

**Benefits:**
- Styles don't leak to/from parent page
- Component is self-contained
- Multiple instances don't conflict

### 5. Cleanup

**Always implement disconnectedCallback:**
```javascript
disconnectedCallback() {
    // Clear intervals
    if (this.refreshInterval) {
        clearInterval(this.refreshInterval);
    }

    // Remove event listeners
    // Cleanup resources
}
```

**Why?**
- Cards can be closed and removed from DOM
- Prevents memory leaks
- Stops background tasks when card is closed

---

## Complete Example: Task Manager

```javascript
/**
 * Task Manager Component
 * Manages scheduled tasks, background jobs, and runspaces
 */

class TaskManagerComponent extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });

        this.state = {
            currentView: 'tasks',
            loading: false,
            tasks: [],
            error: null
        };

        this.refreshInterval = null;
    }

    connectedCallback() {
        this.render();
        this.loadData();
        this.startAutoRefresh();
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    startAutoRefresh() {
        this.refreshInterval = setInterval(() => {
            this.loadData();
        }, 5000);
    }

    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
    }

    async loadData() {
        try {
            this.setState({ loading: true });
            const response = await fetch('/apps/WebHostTaskManagement/api/v1/tasks');
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const data = await response.json();
            this.setState({ tasks: data.tasks || [], loading: false, error: null });
        } catch (error) {
            this.setState({ error: error.message, loading: false });
        }
    }

    setState(newState) {
        this.state = { ...this.state, ...newState };
        this.render();
    }

    render() {
        this.shadowRoot.innerHTML = `
            <style>
                .container { padding: 20px; }
                .error { color: red; }
                .loading { opacity: 0.5; }
            </style>

            <div class="container ${this.state.loading ? 'loading' : ''}">
                ${this.state.error ? `
                    <div class="error">Error: ${this.state.error}</div>
                ` : ''}

                <h2>Tasks (${this.state.tasks.length})</h2>
                <ul>
                    ${this.state.tasks.map(task => `
                        <li>${task.name} - ${task.enabled ? 'Enabled' : 'Disabled'}</li>
                    `).join('')}
                </ul>
            </div>
        `;
    }
}

// Check before registering to prevent re-definition errors
if (!customElements.get('task-manager')) {
    customElements.define('task-manager', TaskManagerComponent);
}

// Register in window.cardComponents for SPA framework
window.cardComponents = window.cardComponents || {};
window.cardComponents['task-manager'] = function(props) {
    return `<task-manager></task-manager>`;
};
```

---

## Endpoint Response Format

The endpoint should return JSON with component metadata:

```json
{
  "component": "task-manager",
  "title": "Task Management",
  "description": "Manage scheduled tasks and background jobs",
  "scriptPath": "/apps/WebHostTaskManagement/public/elements/task-manager/component.js",
  "width": 12,
  "height": 800,
  "features": [
    "View and enable/disable scheduled tasks",
    "Monitor background PowerShell jobs",
    "Auto-refresh every 5 seconds"
  ]
}
```

**Required fields:**
- `component` - Element ID (matches custom element name)
- `scriptPath` - Path to component.js file
- `title` - Display title for the card

**Optional fields:**
- `description` - Component description
- `width` - Card width (1-12, default 12)
- `height` - Card height in pixels (default based on layout.json)
- `features` - Array of feature descriptions

---

## File Structure

```
apps/
└── YourApp/
    ├── app.yaml
    ├── menu.yaml
    ├── routes/
    │   └── api/
    │       └── v1/
    │           └── ui/
    │               └── elements/
    │                   └── your-component/
    │                       ├── get.ps1              # Returns scriptPath
    │                       └── get.security.json
    └── public/
        └── elements/
            └── your-component/
                └── component.js                     # Component definition
```

---

## Testing Checklist

- [ ] Component loads without errors on first open
- [ ] Component loads without errors on second open (no re-definition error)
- [ ] Component appears in `window.cardComponents` object
- [ ] Component renders correctly in card
- [ ] Component fetches and displays data
- [ ] Component cleans up when card is closed
- [ ] No memory leaks (check with browser dev tools)
- [ ] No console errors

---

## Common Errors

### Error: 'my-component' has already been defined

**Cause:** Missing check before `customElements.define()`

**Fix:**
```javascript
if (!customElements.get('my-component')) {
    customElements.define('my-component', MyComponent);
}
```

### Error: Component loaded but not registered in window.cardComponents

**Cause:** Missing window.cardComponents registration

**Fix:**
```javascript
window.cardComponents = window.cardComponents || {};
window.cardComponents['my-component'] = function(props) {
    return `<my-component></my-component>`;
};
```

### Error: Failed to construct 'HTMLElement'

**Cause:** Invalid custom element name (no hyphen)

**Fix:** Use kebab-case with hyphen: `'my-component'` not `'mycomponent'`

---

## Migration from Old Components

If you have existing components without the guard:

1. **Add check before registration:**
   ```javascript
   if (!customElements.get('component-name')) {
       customElements.define('component-name', ComponentClass);
   }
   ```

2. **Add window.cardComponents registration:**
   ```javascript
   window.cardComponents['component-name'] = function(props) {
       return `<component-name></component-name>`;
   };
   ```

3. **Test opening component multiple times**

---

## Best Practices

### 1. State Management
- Use `setState()` method to update state
- Trigger re-render on state changes
- Don't mutate state directly

### 2. Event Listeners
- Attach to shadow DOM elements, not document
- Remove listeners in `disconnectedCallback()`
- Use delegation for dynamic elements

### 3. Styling
- Include all styles in shadow DOM `<style>` tag
- Use CSS custom properties for theming
- Avoid global styles

### 4. Data Fetching
- Use async/await for API calls
- Handle errors gracefully
- Show loading states
- Implement auto-refresh if needed

### 5. Performance
- Debounce rapid updates
- Use virtual scrolling for large lists
- Lazy load heavy resources
- Clean up timers and intervals

---

**Last Updated:** 2026-01-17
**Maintainer:** PSWebHost Development Team
