# CJBravo1/PSScripts

$ErrorActionPreference = "Stop"

$excludedShares = @('C$', 'ADMIN$', 'SYSVOL', 'NETLOGON', 'IPC$', 'PRINT$', 'localsplonly')
$shares = Get-SmbShare | Where-Object { $_.Name -notin $excludedShares }

$excludedUsers = @('BUILTIN\Users', 'BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM', 'CREATOR OWNER')

$totalShares = $shares.Count
$currentShareIndex = 0

$outputPath = "$PSScriptRoot\output_shares.csv"

Set-Location -Path $PSScriptRoot

function Get-MostRestrictivePermission {
    param (
        [System.Security.AccessControl.FileSystemRights[]]$permissions
    )

    # Convert the permissions to numerical values
    $numericPermissions = $permissions | ForEach-Object { [int]$_ }

    # Get the most restrictive permission
    $mostRestrictivePermission = $numericPermissions | ForEach-Object { $_ } | Sort-Object -Descending | Select-Object -First 1

    return [System.Security.AccessControl.FileSystemRights]$mostRestrictivePermission
}

foreach ($share in $shares) {
    $currentShareIndex++
    $shareName = $share.Name
    $sharePath = $share.Path

    Write-Host "Working on Share: $shareName" -ForegroundColor Yellow

    try {
        $directories = Get-ChildItem -Path $sharePath -Directory -ErrorAction Stop

        foreach ($directory in $directories) {
            $directoryPath = $directory.FullName

            Write-Host "Working on Directory: $directoryPath" -ForegroundColor Cyan

            try {
                $acl = Get-Acl -Path $directoryPath

                $permissions = $acl.Access | ForEach-Object {
                    $identity = $_.IdentityReference.Value

                    # Skip inherited permissions, excluded user accounts, and users starting with "S-1"
                    if (!$_.IsInherited -and $excludedUsers -notcontains $identity -and $identity -notlike 'S-1*') {
                        $accessControlType = $_.AccessControlType
                        $permission = $_.FileSystemRights

                        [PSCustomObject]@{
                            "Share Name"          = $shareName
                            "Share Path"          = $sharePath
                            "Directory"           = $directoryPath
                            "Identity"            = $identity
                            "AccessControlType"   = $accessControlType
                            "Permission"          = $permission
                        }
                    }
                } | Where-Object { $_ }

                # Export permissions of the current directory to the CSV file
                $permissions | Select-Object -Property * -Unique | Export-Csv -Path $outputPath -Append -NoTypeInformation
            } catch {
                Write-Host "Error processing directory: $directoryPath. Skipping..." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "Error accessing share: $shareName. Skipping..." -ForegroundColor Red
    }

    # Update the progress bar
    $percentComplete = ($currentShareIndex / $totalShares) * 100
    Write-Progress -Activity "Processing Shares" -Status "Working on Share: $shareName" -PercentComplete $percentComplete
}

Write-Progress -Activity "Processing Shares" -Completed
