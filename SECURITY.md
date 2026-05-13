# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in AIMacCleaner, please report it by:

1. **Do not** open a public GitHub issue
2. Email your findings to the maintainers through GitHub
3. Include detailed steps to reproduce the vulnerability

## Security Considerations

- AIMacCleaner requires **Full Disk Access** to scan all directories on your Mac
- The app **never** sends your files or personal data to external servers
- AI scanning only sends directory names and sizes (not file contents) to the configured LLM API
- API keys are stored locally in `~/.aimaccleaner_ai.json`
- All deletion operations require explicit user confirmation
