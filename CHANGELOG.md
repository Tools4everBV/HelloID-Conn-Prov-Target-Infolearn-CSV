# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [1.0.0] - 2026-10-30

This is the first official release of _HelloID-Conn-Prov-Target-Infolearn-CSV_. This release is based on template version _4.1.2_.

### Added
- Converted the connector from PowerShell V1 to PowerShell V2.
- Added _fieldMapping.json_, _CHANGELOG.md_, _.gitignore_ and the _.github_ workflows.
- Added compare logic in the update lifecycle action.

### Changed
- The account reference is now the plain value of the _Medewerker_ column instead of a JSON object.
- The correlation configuration is now set in HelloID (Correlation tab) instead of in the script.

### Deprecated

### Removed
- Removed the `isDebug` setting from _configuration.json_.
