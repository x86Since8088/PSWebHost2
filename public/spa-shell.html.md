# spa-shell.html

This file is the main HTML shell that hosts the entire Single Page Application (SPA). It sets up the environment, loads all necessary dependencies, and provides the entry point for the React application.

## Key Components

- **React Root**: Contains the essential `<div id="root"></div>`, which serves as the mounting point for the main React application component defined in `psweb_spa.js`.

- **Dependencies**: It loads all the core libraries and stylesheets required for the SPA to function:
  - **React**: `react.development.js` and `react-dom.development.js`.
  - **Babel**: `babel.min.js` is loaded to enable in-browser transpilation of JSX and modern JavaScript, which is used for the React components.
  - **Styling**: `style.css` for general application styles and `react-grid-layout.css` for the grid component.
  - **React Grid Layout**: The JavaScript library for the draggable and resizable grid layout.

- **Application Scripts**: It loads the main application logic from `psweb_spa.js` and other components like `SortableTable.js`. These are loaded with `type="text/babel"` so that the Babel library can transpile them in the browser.

- **Vanilla JS Splitters**: The file includes a self-contained vanilla JavaScript implementation for creating draggable vertical splitters between the layout's panes. 
  - This script waits for the DOM to load and then dynamically injects `<div>` elements to act as the splitters.
  - It handles pointer events to allow the user to drag the splitters and resize the panes, calculating the new dimensions while respecting a minimum width. 
  - It uses `setTimeout` to re-run the initialization, ensuring it can find the panes even if they are rendered asynchronously by React.
