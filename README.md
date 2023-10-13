# HelloID-Conn-Prov-Target-Infolearn-CSV
Create and manage a CSV file required for synchronization of CSV to Infolearn

<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV/network/members"><img src="https://img.shields.io/github/forks/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV" alt="Forks Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV/pulls"><img src="https://img.shields.io/github/issues-pr/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV" alt="Pull Requests Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV/issues"><img src="https://img.shields.io/github/issues/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV" alt="Issues Badge"/></a>
<a href="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV/graphs/contributors"><img alt="GitHub contributors" src="https://img.shields.io/github/contributors/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV?color=2b9348"></a>

| :warning: Warning                                                                                                                                                     |
| :-------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This is connector only creates and manages the CSV file. Currently, there is still an additional scheduled task required to upload this to the Infolearn SFTP server. |

| :information_source: Information                                                                                                                                                                                                                                                                                                                                                       |
| :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="https://infolearn.nl/infolearn-version-004/wp-content/themes/infolearn/assets/images/logo/default.png">
</p>

## Versioning
| Version | Description     |
| ------- | --------------- |
| 1.0.0   | Initial release |

<!-- TABLE OF CONTENTS -->
## Table of Contents
- [HelloID-Conn-Prov-Target-Infolearn-CSV](#helloid-conn-prov-target-infolearn-csv)
  - [Versioning](#versioning)
  - [Table of Contents](#table-of-contents)
  - [Requirements](#requirements)
  - [Introduction](#introduction)
  - [Getting Started](#getting-started)
    - [Request CSV sync with Infolearn](#request-csv-sync-with-infolearn)
    - [Configuring Task to upload CSV to Infolearn SFTP server](#configuring-task-to-upload-csv-to-infolearn-sftp-server)
    - [Connection settings](#connection-settings)
  - [Remarks](#remarks)
  - [Getting help](#getting-help)
  - [HelloID Docs](#helloid-docs)

## Requirements
- Required to run **On-Premises**.
- **Concurrent sessions** in HelloID set to a **maximum of 1**! If this is any higher than 1, this may cause errors due to file locking.

## Introduction
For this connector we have the option to create, update, and remove rows in the CSV file for a person.

| Action     | Action(s) Performed                                        | Comment                                                                   |
| ---------- | ---------------------------------------------------------- | ------------------------------------------------------------------------- |
| create.ps1 | Create new and Update or Remove existing row(s) for person | Can remove existing rows if they are no longer valid according to HelloID |
| update.ps1 | Create new and Update or Remove existing row(s) for person | Can remove existing rows if they are no longer valid according to HelloID |
| delete.ps1 | Remove existing row(s) for person                          | **All** rows that are found according to correlation will be removed      |

## Getting Started

### Request CSV sync with Infolearn
The first step is to request the option to sync a CSV with Infolearn.
The process for requesting this is currently unclear. Please contact your Infolearn contact for more information.

### Configuring Task to upload CSV to Infolearn SFTP server
This connector creates the CSV file required for the CSV sync to Infolearn. However, this CSV file still needs to be placed on the Infolearn SFTP server.
We cannot and will not upload this directly to the SFTP server as this may introduce security risks and further issues (e.g. timeouts as HelloID Prov only supports 30 seconds max. for an action).
So an additional task has to be created to upload the CSV file to the Infolearn SFTP server.

### Connection settings
| Setting              | Description                                                                                   | Mandatory |
| -------------------- | --------------------------------------------------------------------------------------------- | --------- |
| CSV File Path        | The path to the CSV file to export the data to                                                | Yes       |
| Delimiter            | TThe delimiter that separates the property values in the CSV file. The default is a comma (,) | Yes       |
| Encoding             | The encoding for the imported CSV file. The default value is utf8                             | Yes       |
| Toggle debug logging | When toggled, debug logging will be displayed                                                 | No        |


## Remarks
- To make sure only the HelloID data remains in the CSV file, we remove all rows for the person and then add all rows again that should exist according to HelloID.
    > Because of this, it is not possible to manually add/delete any rows.
- This connector works "out-of-the-box", but as the CSV synchronisation to Infolearn has to be additionally requested to Infolearn, the required CSV may differ from the example in this template.

## Getting help
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012518799-How-to-add-a-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/806-helloid-provisioning-helloid-conn-prov-target-exchangeonline)_

## HelloID Docs
The official HelloID documentation can be found at: https://docs.helloid.com/
