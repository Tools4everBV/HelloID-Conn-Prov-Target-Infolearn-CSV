# HelloID-Conn-Prov-Target-Infolearn-CSV

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!WARNING]
> This connector only creates and manages the CSV file. Currently, an additional scheduled task is still required to upload this file to the Infolearn SFTP server.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV/refs/heads/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Infolearn-CSV](#helloid-conn-prov-target-infolearn-csv)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Rows are replaced, not merged](#rows-are-replaced-not-merged)
    - [Additional task to upload the CSV to Infolearn](#additional-task-to-upload-the-csv-to-infolearn)
    - [CSV layout may differ per customer](#csv-layout-may-differ-per-customer)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Infolearn-CSV_ is a _target_ connector that creates, updates and removes the rows of a person in a CSV file. The CSV file is used for the CSV synchronisation with Infolearn. A person has one row for every contract that is in the conditions.

| Action     | Action(s) performed                                               | Comment                                                                    |
| ---------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| create.ps1 | Add one row per contract in the conditions; existing rows of the person are replaced | As in V1. A person whose rows already exist is reported as correlated |
| update.ps1 | Add, update or remove the rows of the person                      | Only writes the file when the rows differ from what HelloID expects        |
| delete.ps1 | Remove the rows of the person                                     | **All** rows found for the account reference are removed                   |

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                 | Remarks                  |
| ----------------------------------------- | --------- | ----------------------- | ------------------------ |
| **Account Lifecycle**                     | ✅         | Create, Update, Delete  | One row per contract     |
| **Permissions**                           | ❌         | -                       |                          |
| **Resources**                             | ❌         | -                       |                          |
| **Entitlement Import: Accounts**          | ❌         | -                       |                          |
| **Entitlement Import: Permissions**       | ❌         | -                       |                          |
| **Governance Reconciliation Resolutions** | ❌         | -                       |                          |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning target system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-Infolearn-CSV/refs/heads/main/Icon.png
```

### Requirements

- **On-premises**:<br>
  The connector must run on-premises, using the HelloID Provisioning agent, as it reads and writes a local file.
- **Concurrent sessions**:<br>
  Concurrent sessions in HelloID must be set to a **maximum of 1**. A higher value may cause errors due to file locking.
- **Existing CSV file**:<br>
  The CSV file must exist before the connector is used. Create, update and delete fail when the file cannot be read. The file may be empty or only contain the header.

### Connection settings

The following settings are required to connect to the CSV file.

| Setting       | Description                                                                                   | Mandatory |
| ------------- | --------------------------------------------------------------------------------------------- | --------- |
| CSV File Path | The path to the CSV file to export the data to                                                | Yes       |
| Delimiter     | The delimiter that separates the property values in the CSV file. The default is a comma (,)  | Yes       |
| Encoding      | The encoding of the CSV file. The default value is utf8                                       | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match existing rows within the CSV file to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `Medewerker`                      |

> [!IMPORTANT]
> Update and delete look up the rows with `$actionContext.References.Account` in the `Medewerker` column, so the account correlation field in HelloID must be `Medewerker`. Change the column name in _update.ps1_ and _delete.ps1_ when another column is used.

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file. The field names are the column headers of the CSV file and the order of the fields is the column order.

The columns _Opdrachtgevernaam_, _Opdrachtgever_, _OE_code_, _OE_, _Functie_code_ and _Functie_ are mapped from the primary contract, but the scripts fill them for every contract that is in the conditions. The mapping only defines the columns. The header of the existing CSV file must contain all mapped columns: `Export-Csv` takes the columns from the first row, so a column that is not in the header is left out of the file.

### Account Reference

The account reference is populated with the value of the `Medewerker` column (the external ID of the person).

## Remarks

### Rows are replaced, not merged

- To make sure only the HelloID data remains in the CSV file, all rows of the person are removed and the rows that should exist according to HelloID are added again.
  > Because of this, it is not possible to manually add or delete rows of a person that is managed by HelloID.
- The CSV is written to a temporary file (`<CSV file path>.tmp`) next to the CSV and then moved over it, so a failed write does not leave a cut-off file. The account that runs the agent needs create and delete rights on that folder. When the last row is removed, the header line stays in the file.

### Additional task to upload the CSV to Infolearn

- The connector does not upload the CSV file to the Infolearn SFTP server, as that may introduce security risks and timeouts (HelloID Provisioning supports 30 seconds at most per action). An additional task has to be created to upload the file.
- The option to sync a CSV with Infolearn has to be requested at Infolearn. Please contact your Infolearn contact for more information.

### CSV layout may differ per customer

- The connector works out-of-the-box, but the CSV synchronisation has to be requested at Infolearn, so the required CSV may differ from the layout used here.

## Development resources

### API endpoints

This connector does not use an API. It reads and writes the configured CSV file.

### API documentation

Not applicable.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
