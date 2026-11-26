#################################################
# HelloID-Conn-Prov-Target-Infolearn-CSV-Delete
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

    # A person has one row per contract, so more than one row is expected
    if (($correlatedAccount | Measure-Object).Count -eq 0) {
        $lifecycleProcess = 'NotFound'
    }
    else {
        $lifecycleProcess = 'DeleteAccount'
    }

    # Process
    switch ($lifecycleProcess) {
        'DeleteAccount' {
            $actionMessage = 'removing rows from CSV'
            $removedRows = @($correlatedAccount)
            $updatedCsvContent = @($csvContent | Where-Object { $_ -notin $removedRows })

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
                Write-Information "Removing [$($removedRows.Count)] row(s) from CSV where [Medewerker] = [$($actionContext.References.Account)]"
                if ($updatedCsvContent.Count -gt 0) {
                    $null = $updatedCsvContent | Export-Csv @splatExportCsvParams
                }
                else {
                    # No rows left: keep the header line, so the CSV keeps its column names
                    $csvHeader = ($removedRows[0] | ConvertTo-Csv -Delimiter $actionContext.Configuration.Delimiter -NoTypeInformation)[0]
                    Set-Content -Path $csvTempPath -Value $csvHeader -Encoding $actionContext.Configuration.Encoding -ErrorAction Stop
                }
                Move-Item -Path $csvTempPath -Destination $actionContext.Configuration.CsvPath -Force -ErrorAction Stop
            }
            else {
                Write-Information "[DryRun] Remove [$($removedRows.Count)] row(s) from CSV where [Medewerker] = [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Delete account: [$($actionContext.References.Account)] was successful. Removed [$($removedRows.Count)] row(s). Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            # A missing row is the desired end state
            Write-Information "Infolearn-CSV rows: [$($actionContext.References.Account)] could not be found, indicating that they may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Infolearn-CSV rows: [$($actionContext.References.Account)] could not be found, indicating that they may have been deleted. Action initiated by: [$($actionContext.Origin)]"
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
    $auditLogMessage = "Error $($actionMessage). Could not delete Infolearn-CSV rows: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
    Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
