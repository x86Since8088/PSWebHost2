# getauthtoken.html

This HTML file provides the user interface for the first step of the login process, allowing the user to select their preferred authentication method.

## Functionality

- **User Interface**: It presents a clean, centered dialog with buttons for each available authentication method:
  - Sign in with Windows
  - Sign in with Password
  - Sign in with Email OTP

- **Dynamic URL Parameters**: The page includes a client-side JavaScript snippet that plays a crucial role in maintaining the authentication flow's state.
  - On page load, the script reads the `RedirectTo` and `state` parameters from the URL's query string.
  - It then dynamically appends these parameters to the `href` attribute of each authentication link.
  - This ensures that no matter which authentication method the user chooses, the `state` (for security) and the original `RedirectTo` destination are preserved throughout the entire login process.
