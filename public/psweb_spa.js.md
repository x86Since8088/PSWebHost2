# psweb_spa.js

This JavaScript file is the core of the single-page application (SPA) for the PSWebHost UI, built using React.

## Key Features

- **React-Based Architecture**: The application is built with React and utilizes React Hooks (`useState`, `useEffect`, `useCallback`, etc.) for state management and side effects.

- **Component-Driven UI**: The user interface is composed of several reusable React components:
  - `App`: The main component that orchestrates the entire application.
  - `Pane`: A container for different sections of the layout (e.g., header, footer, sidebars).
  - `Card`: A generic container for displaying content widgets.
  - `UserCard`: A specific card for displaying user information and handling login/logout.
  - `Modal`: A generic modal dialog.
  - `CardSettingsModal`: A modal for configuring the layout of individual cards.
  - `IFrameComponent`: A component for embedding content from other URLs.

- **Dynamic Layout**: 
  - The application fetches a `layout.json` file to determine the initial arrangement of cards within different panes.
  - It uses the `react-grid-layout` library to provide a draggable and resizable grid for the main content area, allowing users to customize the dashboard.

- **Dynamic Component Loading**: Card components are loaded dynamically at runtime. The application fetches the JavaScript for each component, transpiles it from JSX using Babel, and then registers it for use.

- **Authentication Handling**:
  - A `psweb_fetchWithAuthHandling` function is used to wrap `fetch` calls to handle authentication.
  - The `UserCard` component checks the user's session status and provides a login button if they are not authenticated.

- **Global Functions**: The script exposes several functions on the `window` object for global access:
  - `window.openCard()`: To open new content in an iframe-based card.
  - `window.openComponentInModal()`: To open a registered component within a modal.
  - `window.resetGrid()`: To reset the layout to its default state.
  - `window.openAuthModal()`: To initiate the authentication flow.
