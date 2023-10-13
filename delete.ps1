#####################################################
# HelloID-Conn-Prov-Target-Infolearn-CSV-Delete
#
# Version: 1.0.0
#####################################################
# Initialize default values
$c = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$success = $false # Set to false at start, at the end, only when no error occurs it is set to true
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($c.isDebug)) {
    $true { $VerbosePreference = "Continue" }
    $false { $VerbosePreference = "SilentlyContinue" }
}
$InformationPreference = "Continue"
$WarningPreference = "Continue"

# Correlation values
$correlationProperty = "Medewerker" # Has to match the name of the unique identifier
$correlationValue = $aRef.Medewerker # Has to match the value of the unique identifier

#region Change mapping here
# No account mapping object needed as we delete the rows
$account = [PSCustomObject]@{}
#endregion Change mapping here

#region functions
function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        # Set verbose error message
        $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message

        # Set audit error message
        $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message

        Write-Output $errorMessage
    }
}
#endregion functions

try {
    #region Check if required fields are available for correlation
    $incompleteCorrelationValues = $false
    if ([String]::IsNullOrEmpty($correlationProperty)) {
        $incompleteCorrelationValues = $true
        Write-Warning "Required correlation field [$correlationProperty] has a null or empty value"
    }
    if ([String]::IsNullOrEmpty($correlationValue)) {
        $incompleteCorrelationValues = $true
        Write-Warning "Required correlation field [$correlationValue] has a null or empty value"
    }
    if ($incompleteCorrelationValues -eq $true) {
        throw "Correlation values incomplete, cannot continue. CorrelationProperty = [$correlationProperty], CorrelationValue = [$correlationValue]"
    }
    #endregion Check if required fields are available for correlation

    #region Check if required fields are available in account object
    $incompleteAccount = $false
    foreach ($requiredAccountField in $requiredAccountFields) {
        if ($requiredAccountField -notin $account.PsObject.Properties.Name) {
            $incompleteAccount = $true
            Write-Warning "Required account object field [$requiredAccountField] is missing"
        }
        elseif ([String]::IsNullOrEmpty($account.$requiredAccountField)) {
            $incompleteAccount = $true
            Write-Warning "Required account object field [$requiredAccountField] has a null or empty value"
        }
    }
    if ($incompleteAccount -eq $true) {
        throw "Account object incomplete, cannot continue."
    }
    #endregion Check if required fields are available in account object

    #region Import CSV data
    try {
        Write-Verbose "Querying data from CSV file at path [$($c.CsvPath)]"
    
        $csvContent = $null
        $csvContent = Import-Csv -Path $c.CsvPath -Delimiter $c.Delimiter -Encoding $c.Encoding

        # Group on correlation property to match employee to CSV row(s)
        $csvContentGroupedOnCorrelationProperty = $csvContent | Group-Object -Property $correlationProperty -AsString -AsHashTable
        
        Write-Information "Successfully queried data from CSV file at path [$($c.CsvPath)]. Result count: $(($csvContent | Measure-Object).Count)"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error querying data from CSV file at path [$($c.CsvPath)]. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })

        # Skip further actions, as this is a critical error
        continue
    }
    #endregion Import CSV data

    #region Get current row(s) for person
    try {
        Write-Verbose "Querying row(s) where [$($correlationProperty)] = [$($correlationValue)]"

        $currentRows = $null
        if ($csvContentGroupedOnCorrelationProperty -ne $null -and -not[string]::IsNullOrEmpty($correlationValue)) {
            $currentRows = $csvContentGroupedOnCorrelationProperty["$($correlationValue)"]
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error querying row(s) where [$($correlationProperty)] = [$($correlationValue)]. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })

        # Skip further actions, as this is a critical error
        continue
    }
    #endregion Getcurrent row(s) for person

    #region Create custom object for updated csv without the current row(s) for person (to make sure only HelloID input remains)
    try {
        Write-Verbose "Creating custom object for updated csv without the current rows"

        $updatedCsvContent = $null
        $updatedCsvContent = [System.Collections.ArrayList](, ($csvContent | Where-Object { $_ -notin $currentRows }))

        $removedRows = ($currentRows | Measure-Object).Count
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error creating custom object for updated csv without the current row(s) for person. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })

        # Skip further actions, as this is a critical error
        continue
    }
    #endregion Create custom object for updated csv without the current row(s) for person (to make sure only HelloID input remains)

    #region Export updated CSV object
    try {
        $splatParams = @{
            Path              = $c.CsvPath
            Delimiter         = $c.Delimiter
            Encoding          = $c.Encoding
            NoTypeInformation = $true
            ErrorAction       = "Stop"
            Verbose           = $false
        }

        if (-not($dryRun -eq $true)) {
            Write-Verbose "Removing [$($removedRows)] rows from CSV where [$($correlationProperty)] = [$($correlationValue)]"

            $updatedCsv = $updatedCsvContent | Foreach-Object { $_ } | Export-Csv @splatParams

            # Set aRef object for use in futher actions
            $aRef = [PSCustomObject]@{
                $correlationProperty = $correlationValue
            }

            $auditLogs.Add([PSCustomObject]@{
                    # Action  = "" # Optional
                    Message = "Successfully removed $($removedRows)] rows from CSV where [$($correlationProperty)] = [$($correlationValue)]"
                    IsError = $false
                })
        }
        else {
            Write-Warning "DryRun: Would remove $($removedRows)] rows from CSV where [$($correlationProperty)] = [$($correlationValue)]"
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"

        $auditLogs.Add([PSCustomObject]@{
                # Action  = "" # Optional
                Message = "Error removing $($removedRows)] rows from CSV where [$($correlationProperty)] = [$($correlationValue)]t. Error Message: $($errorMessage.AuditErrorMessage)"
                IsError = $true
            })

        # Skip further actions, as this is a critical error
        continue
    }
    #endregion Export updated CSV object
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if (-NOT($auditLogs.IsError -contains $true)) {
        $success = $true
    }
    
    # Send results
    $result = [PSCustomObject]@{
        Success   = $success
        AuditLogs = $auditLogs
    }
    
    Write-Output ($result | ConvertTo-Json -Depth 10)  
}