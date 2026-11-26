#################################################
# HelloID-Conn-Prov-Target-Infolearn-CSV-Create
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-InfolearnCSVError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $null
            FriendlyMessage  = $null
        }

        # Set verbose error message
        $errorMessage.ErrorDetails = $ErrorObject.Exception.Message

        # Set audit error message
        $errorMessage.FriendlyMessage = $ErrorObject.Exception.Message

        Write-Output $errorMessage
    }
}

function Write-InfolearnCSVRows {
    # Replaces the existing rows of the person in the CSV by the new rows
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Rows,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $ExistingRows,
        [Parameter(Mandatory)] [AllowNull()] [object[]] $CsvContent
    )
    process {
        if (($Rows.Count -eq 0) -and ($ExistingRows.Count -eq 0)) { return }

        $updatedCsvContent = @($CsvContent | Where-Object { $_ -notin $ExistingRows }) + @($Rows)

        # Export-Csv takes its columns from the first row: use the CSV header plus the new columns, so a column missing in the header (e.g. OE_code) is not dropped
        $columns = [System.Collections.Generic.List[string]]::new()
        foreach ($row in @(@($CsvContent | Select-Object -First 1) + @($Rows | Select-Object -First 1))) {
            foreach ($name in $row.PSObject.Properties.Name) { if ($columns -notcontains $name) { $columns.Add($name) } }
        }

        # Write to a temporary file next to the CSV and move it into place, so a failed write never leaves a cut-off CSV
        $csvTempPath = "$($actionContext.Configuration.CsvPath).tmp"
        if ($updatedCsvContent.Count -gt 0) {
            $null = $updatedCsvContent | Select-Object -Property $columns | Export-Csv -Path $csvTempPath -Delimiter $actionContext.Configuration.Delimiter -Encoding $actionContext.Configuration.Encoding -NoTypeInformation -ErrorAction Stop -Verbose:$false
        }
        else {
            # No rows left: keep the header line, so the CSV keeps its column names
            $csvHeader = ($ExistingRows[0] | ConvertTo-Csv -Delimiter $actionContext.Configuration.Delimiter -NoTypeInformation)[0]
            Set-Content -Path $csvTempPath -Value $csvHeader -Encoding $actionContext.Configuration.Encoding -ErrorAction Stop
        }
        Move-Item -Path $csvTempPath -Destination $actionContext.Configuration.CsvPath -Force -ErrorAction Stop
    }
}
#endregion functions

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'
    $actionMessage = 'validating mapped fields and correlation configuration'

    # Account object = mapped data with the computed values applied
    $account = $actionContext.Data.PSObject.Copy()

    # The fields of the field mapping, so the output context only contains mapped fields
    $mappedFields = $actionContext.Data.PSObject.Properties.Name

    # Convert birthdate to accepted format. The date is taken as written, also with a Z or an offset, and not converted to the time zone of the agent
    if ($account.Geboortedatum -is [DateTime]) {
        $account.Geboortedatum = $account.Geboortedatum.ToString('dd/MM/yyyy')
    }
    elseif (-not [string]::IsNullOrEmpty($account.Geboortedatum)) {
        $birthDateFormats = [string[]]@('dd/MM/yyyy HH:mm:ss', 'dd/MM/yyyy', 'yyyy-MM-ddTHH:mm:ss.fffffffK', 'yyyy-MM-ddTHH:mm:ssK', 'yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd', 'MM/dd/yyyy HH:mm:ss', 'MM/dd/yyyy')
        $parsedBirthDate = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParseExact([string]$account.Geboortedatum, $birthDateFormats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsedBirthDate)) {
            throw 'Unable to convert Geboortedatum to a date. Expected one of the supported formats'
        }
        $account.Geboortedatum = $parsedBirthDate.Date.ToString('dd/MM/yyyy')
    }
    else {
        $account.Geboortedatum = ''
    }

    # Validate mandatory mapped fields
    foreach ($requiredField in @('Username', 'Medewerker')) {
        if ([string]::IsNullOrEmpty($account.$requiredField)) {
            throw "Mandatory attribute [$requiredField] is empty. Please make sure it is correctly mapped"
        }
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [PersonFieldValue] is empty. Please make sure it is correctly mapped'
        }
    }
    else {
        throw 'Correlation is disabled. This connector requires correlation, as the rows of a person are identified by the correlation field'
    }

    # GET account: import the CSV and find the row(s) for the correlation value
    $actionMessage = "querying data from CSV file at path [$($actionContext.Configuration.CsvPath)]"
    $csvContent = Import-Csv -Path $actionContext.Configuration.CsvPath -Delimiter $actionContext.Configuration.Delimiter -Encoding $actionContext.Configuration.Encoding -ErrorAction Stop

    # Group on correlation field to match employee to CSV row(s)
    $csvContentGrouped = $csvContent | Group-Object -Property $correlationField -AsString -AsHashTable
    Write-Information "Successfully queried data from CSV file at path [$($actionContext.Configuration.CsvPath)]. Result count: $(($csvContent | Measure-Object).Count)"

    $actionMessage = "querying row(s) where [$($correlationField)] = [$($correlationValue)]"
    $correlatedAccount = $null
    if ($null -ne $csvContentGrouped) {
        $correlatedAccount = $csvContentGrouped["$($correlationValue)"]
    }

    # A person has one row per contract, so the correlation value is not unique in the CSV: more than one row is expected
    $existingRows = @($correlatedAccount | Where-Object { $_ })
    if ($existingRows.Count -eq 0) {
        $lifecycleProcess = 'CreateAccount'
    }
    else {
        $lifecycleProcess = 'CorrelateAccount'
    }

    # One row per contract in conditions (all contracts on a dry run)
    $actionMessage = 'creating account object for each contract'
    $rows = [System.Collections.ArrayList]::new()
    foreach ($contract in $personContext.Person.Contracts) {
        if ($contract.Context.InConditions -or ($actionContext.DryRun -eq $true)) {
            $csvRowObject = [PSCustomObject]@{}
            $account.PSObject.Properties | ForEach-Object {
                $csvRowObject | Add-Member -MemberType NoteProperty -Name $_.Name -Value $_.Value -Force
            }

            # Contract specific mapping. Add-Member -Force adds the column even when it is not in the field mapping
            $contractColumns = [ordered]@{
                Opdrachtgevernaam = "$($contract.Organization.ExternalId)"
                Opdrachtgever     = "$($contract.Organization.Name)"
                OE_code           = "$($contract.Custom.DepartmentCode)"
                OE                = "$($contract.Department.DisplayName)"
                Functie_code      = "$($contract.Title.Code)"
                Functie           = "$($contract.Title.Name)"
            }
            foreach ($column in $contractColumns.GetEnumerator()) {
                $csvRowObject | Add-Member -MemberType NoteProperty -Name $column.Key -Value $column.Value -Force
            }

            [void]$rows.Add($csvRowObject)
        }
    }

    # Not representable for all CSV rows since the rows differ per contract, this is only the last row
    if ($rows.Count -gt 0) {
        $outputData = $rows[-1] | Select-Object -Property $mappedFields
    }
    elseif ($existingRows.Count -gt 0) {
        $outputData = $existingRows[-1] | Select-Object -Property $mappedFields
    }
    else {
        $outputData = $account | Select-Object -Property $mappedFields
    }

    # Process
    # As in V1, the rows of the person are always replaced by the rows that should exist: the current rows of
    # the person are removed and a row per contract is added, also when the person already has rows
    switch ($lifecycleProcess) {
        'CreateAccount' {
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Creating [$($rows.Count)] row(s) where [$($correlationField)] = [$($correlationValue)]"
                Write-InfolearnCSVRows -Rows $rows -ExistingRows $existingRows -CsvContent $csvContent

                $outputContext.Data = $outputData
                $outputContext.AccountReference = "$($correlationValue)"
            }
            else {
                Write-Information "[DryRun] Create [$($rows.Count)] row(s) where [$($correlationField)] = [$($correlationValue)], will be executed during enforcement"
            }
            $auditLogMessage = "Create account was successful. Created [$($rows.Count)] row(s). AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Infolearn-CSV rows'

            if (-not($actionContext.DryRun -eq $true)) {
                Write-InfolearnCSVRows -Rows $rows -ExistingRows $existingRows -CsvContent $csvContent
            }
            else {
                Write-Information "[DryRun] Replace [$($existingRows.Count)] row(s) with [$($rows.Count)] row(s) where [$($correlationField)] = [$($correlationValue)], will be executed during enforcement"
            }

            $outputContext.Data = $outputData
            $outputContext.AccountReference = "$($correlationValue)"
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]. Found [$($existingRows.Count)] row(s), replaced by [$($rows.Count)] row(s) from HelloID"
            break
        }
    }

    $outputContext.Success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    # File-based: no HTTP exceptions, so always resolve with the error function
    $errorObj = Resolve-InfolearnCSVError -ErrorObject $ex
    $auditLogMessage = "Error $($actionMessage). Could not create or correlate Infolearn-CSV rows. Error: $($errorObj.FriendlyMessage)"
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
