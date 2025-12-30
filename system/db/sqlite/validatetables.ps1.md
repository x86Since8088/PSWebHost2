# validatetables.ps1

This script is a database schema validator and migrator for the PsWebHost application. It ensures that the structure of the SQLite database matches the schema defined in the `sqliteconfig.json` file.

## Functionality

- **Schema-Driven Validation**: The script takes a database file and a JSON configuration file as input. It reads the table and column definitions from the JSON file and compares them against the live database.

- **Automatic Table Creation**: If a table defined in the configuration file does not exist in the database, the script will automatically generate and execute the appropriate `CREATE TABLE` statement, including all specified columns, data types, constraints, and composite primary keys.

- **Automatic Column Addition**: If a table already exists but is missing a column that is defined in the configuration, the script will automatically execute an `ALTER TABLE ... ADD COLUMN` statement to add the missing column. This provides a simple but effective database migration capability, allowing the schema to be evolved over time by simply updating the configuration file.

- **Environment Integration**: It ensures the main application environment is loaded by running `init.ps1` before it begins, so that it has access to all necessary helper functions for database interaction.
