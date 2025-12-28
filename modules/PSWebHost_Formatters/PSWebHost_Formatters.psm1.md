# PSWebHost_Formatters.psm1

This PowerShell module provides a set of functions for formatting, inspecting, and safely serializing complex PowerShell objects. These are primarily used for debugging and preparing objects for API responses.

## Functions

### Inspect-Object

This is the main function of the module. It recursively walks a PowerShell object (like a hashtable, array, or custom object) and creates a detailed, structured hashtable that describes the original object. This is particularly useful for converting live, complex objects into a format that can be safely serialized to JSON.

**Key Features**:
- **Recursive Traversal**: It walks through nested objects and collections.
- **Type Information**: It records the data type of each property.
- **Safety Limits**: To prevent errors and infinite recursion, it includes several safety mechanisms:
  - A `-Depth` parameter to limit how deep it will traverse an object.
  - A `-MaxEnumerable` parameter to limit the number of items it processes in an array.
  - An internal blacklist of complex or problematic types to avoid (e.g., `System.IO.Stream`, `PSCredential`).

### Get-ObjectSafeWalk

A simplified version of `Inspect-Object`, also designed to safely convert an object into a serializable hashtable with similar safety features like depth limits, blacklisting, and enumerable/property limits.

### Test-Walkable

A helper function used by the other functions in this module to determine if an object is "walkable." It returns `$false` for simple types (like strings or integers) and for types on a blacklist, signaling that the inspection should not recurse any deeper into that object.

### Convert-ObjectToYaml

A basic, custom implementation that converts a PowerShell object into a YAML-like string. It recursively walks the object to build the string representation.
