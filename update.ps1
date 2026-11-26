#################################################
# HelloID-Conn-Prov-Target-Infolearn-CSV-Update
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
#endregion functions

try {
    $actionMessage = 'verifying account reference'

    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Account object = mapped data with the computed values applied (same as create)
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
    $accountPropertiesToCompare = $account.PSObject.Properties.Name

    # GET account: import the CSV and find the row(s) for the account reference
    $actionMessage = "querying data from CSV file at path [$($actionContext.Configuration.CsvPath)]"
    $csvContent = Import-Csv -Path $actionContext.Configuration.CsvPath -Delimiter $actionContext.Configuration.Delimiter -Encoding $actionContext.Configuration.Encoding -ErrorAction Stop

    # Group on correlation field to match employee to CSV row(s)
    $csvContentGrouped = $csvContent | Group-Object -Property 'Medewerker' -AsString -AsHashTable
    Write-Information "Successfully queried data from CSV file at path [$($actionContext.Configuration.CsvPath)]. Result count: $(($csvContent | Measure-Object).Count)"

    $actionMessage = "querying row(s) where [Medewerker] = [$($actionContext.References.Account)]"
    $correlatedAccount = $null
    if ($null -ne $csvContentGrouped) {
        $correlatedAccount = $csvContentGrouped["$($actionContext.References.Account)"]
    }
    # Where-Object drops the $null of a missing person: @($null) would count as one (empty) row
    $currentRows = @($correlatedAccount | Where-Object { $_ })

    # Not representable for all CSV rows since the rows differ per contract, this is only the last row
    if ($currentRows.Count -gt 0) {
        $outputContext.PreviousData = $currentRows[-1] | Select-Object -Property $mappedFields
    }
    else {
        $outputContext.PreviousData = [PSCustomObject]@{}
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

    # Compare the current rows to the rows that should exist. Every row is compared as one string of its values
    $actionMessage = 'comparing current rows to mapped properties'
    $currentRowStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($currentRow in $currentRows) {
        $rowString = foreach ($propertyName in $accountPropertiesToCompare) { "$($propertyName)=$($currentRow.$propertyName -join ',')" }
        $currentRowStrings.Add($rowString -join '|')
    }
    $desiredRowStrings = [System.Collections.Generic.List[string]]::new()
    foreach ($row in $rows) {
        $rowString = foreach ($propertyName in $accountPropertiesToCompare) { "$($propertyName)=$($row.$propertyName -join ',')" }
        $desiredRowStrings.Add($rowString -join '|')
    }
    $rowsToAdd = @($desiredRowStrings | Where-Object { $_ -notin $currentRowStrings })
    $rowsToRemove = @($currentRowStrings | Where-Object { $_ -notin $desiredRowStrings })

    if (($rowsToAdd.Count -gt 0) -or ($rowsToRemove.Count -gt 0) -or ($currentRowStrings.Count -ne $desiredRowStrings.Count)) {
        $lifecycleProcess = 'UpdateAccount'
    }
    else {
        $lifecycleProcess = 'NoChanges'
    }

    # Not representable for all CSV rows since the rows differ per contract, this is only the last row
    if ($rows.Count -gt 0) {
        $outputContext.Data = $rows[-1] | Select-Object -Property $mappedFields
    }
    else {
        $outputContext.Data = $account | Select-Object -Property $mappedFields
    }

    # Process
    switch ($lifecycleProcess) {
        'UpdateAccount' {
            Write-Information "Row(s) to add: [$($rowsToAdd.Count)], row(s) to remove: [$($rowsToRemove.Count)]"

            # Remove the current rows for the person and add the rows that should exist, so only HelloID input remains
            $actionMessage = 'updating rows in CSV'
            $updatedCsvContent = @($csvContent | Where-Object { $_ -notin $currentRows }) + @($rows)

    # Export-Csv takes its columns from the first row: use the CSV header plus the new columns, so a column missing in the header (e.g. OE_code) is not dropped
    $columns = [System.Collections.Generic.List[string]]::new()
    foreach ($row in @(@($csvContent | Select-Object -First 1) + @($rows | Select-Object -First 1))) {
        foreach ($name in $row.PSObject.Properties.Name) { if ($columns -notcontains $name) { $columns.Add($name) } }
    }

            # Write to a temporary file next to the CSV and move it into place, so a failed write never leaves a cut-off CSV
            $csvTempPath = "$($actionContext.Configuration.CsvPath).tmp"
            $splatExportCsvParams = @{
                Path              = $csvTempPath
                Delimiter         = $actionContext.Configuration.Delimiter
                Encoding          = $actionContext.Configuration.Encoding
                NoTypeInformation = $true
                ErrorAction       = 'Stop'
                Verbose           = $false
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Infolearn-CSV [$($rows.Count)] row(s) with accountReference: [$($actionContext.References.Account)]"
                if ($updatedCsvContent.Count -gt 0) {
                    $null = $updatedCsvContent | Select-Object -Property $columns | Export-Csv @splatExportCsvParams
                }
                else {
                    # No rows left: keep the header line, so the CSV keeps its column names
                    $csvHeader = ($currentRows[0] | ConvertTo-Csv -Delimiter $actionContext.Configuration.Delimiter -NoTypeInformation)[0]
                    Set-Content -Path $csvTempPath -Value $csvHeader -Encoding $actionContext.Configuration.Encoding -ErrorAction Stop
                }
                Move-Item -Path $csvTempPath -Destination $actionContext.Configuration.CsvPath -Force -ErrorAction Stop
            }
            else {
                Write-Information "[DryRun] Update Infolearn-CSV [$($rows.Count)] row(s) with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful. Row(s) added: [$($rowsToAdd.Count)], row(s) removed: [$($rowsToRemove.Count)], total row(s): [$($rows.Count)]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Infolearn-CSV rows with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating Infolearn-CSV rows with AccountReference: [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    # File-based: no HTTP exceptions, so always resolve with the error function
    $errorObj = Resolve-InfolearnCSVError -ErrorObject $ex
    $auditLogMessage = "Error $($actionMessage). Could not update Infolearn-CSV rows: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
