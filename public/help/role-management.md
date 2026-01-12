# Role Management

Configure user roles and permissions for access control.

## Overview

PSWebHost uses role-based access control (RBAC) to manage what users can see and do within the application.

## Built-in Roles

### admin
Full system access with all permissions.

### site_admin
- Manage site settings
- User management
- View all content

### system_admin
- System configuration
- Service management
- Database access

### authenticated
Basic access for logged-in users:
- View profile
- Use standard cards
- Access public features

### debug
Access to debugging tools:
- View debug variables
- Test error handling
- Access diagnostic endpoints

### unauthenticated
Limited access for anonymous users:
- Login page
- Public content only

## Features

### Role List
View all roles with:
- Role name and ID
- Description
- User count
- Assigned permissions

### Role Details
Select a role to view:
- Full permission list
- Users with this role
- Role hierarchy

### Actions
- **Add Role**: Create new custom role
- **Edit Role**: Modify permissions
- **Delete Role**: Remove unused roles
- **Assign Users**: Add/remove users from role

## Access
This component requires `site_admin`, `system_admin`, or `admin` role.
