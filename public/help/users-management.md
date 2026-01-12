# User Management

Administer site users and their account settings.

## Overview

The User Management component allows administrators to view, create, edit, and delete user accounts in the PSWebHost system.

## Features

### User List
View all registered users with:
- Username
- Email address
- Phone number
- Profile actions

### User Actions

#### Create User
Add a new user account with:
- Username (required)
- Email address
- Phone number
- Profile picture (optional)

#### Edit User
Modify existing user information:
- Update contact details
- Change profile picture
- Modify account settings

#### Delete User
Remove a user account from the system.

**Warning**: Deleting a user removes their account permanently. Associated data may also be removed.

## User Properties

| Field | Description |
|-------|-------------|
| UserID | Unique identifier (auto-generated) |
| UserName | Display name for the user |
| Email | Contact email address |
| Phone | Contact phone number |
| Profile Image | User avatar/picture |

## Access

This component requires `site_admin` or `admin` role.

## API Endpoints

The component uses these API endpoints:
- `GET /api/v1/users` - List all users
- `PUT /api/v1/users` - Create new user
- `POST /api/v1/users?UserID=...` - Update user
- `DELETE /api/v1/users?UserID=...` - Delete user

## Security Notes

- User passwords are hashed and never displayed
- Only administrators can view and modify user accounts
- All changes are logged for audit purposes
