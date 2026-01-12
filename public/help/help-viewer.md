# Help Viewer

The Help Viewer displays documentation for PSWebHost components and features.

## Features

- **Markdown Rendering**: Converts markdown files to formatted HTML
- **Code Highlighting**: Displays code blocks with syntax styling
- **Linked Navigation**: Click links to navigate to related help topics

## Usage

Click the help icon (?) on any card to open documentation for that component.

## Supported Markdown

- Headers (# through ######)
- Bold (**text**) and italic (*text*)
- Code blocks (```language)
- Inline code (`code`)
- Links [text](url)
- Images ![alt](src)
- Lists (ordered and unordered)
- Blockquotes (> text)
- Horizontal rules (---)

## Help File Locations

Help files are markdown (.md) files located in:
- `public/help/` - Component documentation
- `docs/` - General documentation

## Creating Help Files

To add help for a new component, create a markdown file at:
```
public/help/{component-name}.md
```

The file name should match the component's element name.
