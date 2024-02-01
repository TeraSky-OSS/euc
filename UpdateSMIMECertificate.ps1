<#
.SYNOPSIS
A powershell script to update the SMIME certificate on Workspace ONE UEM Console

.NOTES
  Version:        1.0
  Author:         Ofir Dalal - ofird@terasky.com
  Creation Date:  27/12/2023
  Purpose/Change: Initial script development
  
#>

#----------------------------------------------------------[Declarations]----------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#-----------------------------------------------------------[Functions]------------------------------------------------------------

#Script parameters
$apikey = 'value'
$username = "value"
$UnsecurePassword = "value"
$TenantURL = "asXXXX.awmdm.com"
$PFXfolder = "C:\Temp\certs"
$doneFolder = "C:\Temp\certs\done"
$CertificatePassword = "value"
$logFilePath = "C:\Temp\cert_upload_log.txt"
$logRotationDays = 180


# Function to rotate log files
function Rotate-Log {
    param (
        [string]$logFilePath
    )

    $currentDate = Get-Date
    $archivePath = $logFilePath -replace '\.txt$', "_$currentDate.txt"

    Move-Item -Path $logFilePath -Destination $archivePath -Force
}

# Initialize success and failure counters
$successCount = 0
$failureCount = 0

# Base64 Encode AW Username and Password
$combined = $Username + ":" + $UnsecurePassword
$encoding = [System.Text.Encoding]::ASCII.GetBytes($combined)
$cred = [Convert]::ToBase64String($encoding)

# Create "done" folder if it doesn't exist
if (-not (Test-Path $doneFolder)) {
    New-Item -Path $doneFolder -ItemType Directory
}

# Import pfx files
$pfxFiles = Get-ChildItem $PFXfolder -Filter *.pfx

foreach ($pfxFile in $pfxFiles) {
    try {
        # Remove the ".pfx" extension and get username
        $user = $pfxFile.BaseName

        # Convert username to user ID
        $headersusername = @{
            "aw-tenant-code" = $apikey
            "Accept"         = "application/json;version=2"
            "Content-Type"   = "application/json"
            "Authorization"  = "Basic $cred"
        }

        $response = Invoke-RestMethod "https://$TenantURL/API/system/users/search?UserName=$user" -Method 'GET' -Headers $headersusername
        $UserId = $response.users.id.Value

        # Convert pfx to base64 format
        $fileContentBytes = Get-Content $pfxFile.FullName -Encoding Byte
        $certificate = [System.Convert]::ToBase64String($fileContentBytes)

        # Update Certificate to the user
        $headerscertuser = @{
            "aw-tenant-code" = $apikey
            "Accept"         = "application/json;version=2"
            "Content-Type"   = "application/json"
            "Authorization"  = "Basic $cred"
        }

        $body = @{
            Encryption = @{
                CertificatePayload = $certificate
                Password           = $CertificatePassword
            }
            Signing    = @{
                CertificatePayload = $certificate
                Password           = $CertificatePassword
            }
        } | ConvertTo-Json

        Invoke-RestMethod "https://$TenantURL/API/system/users/$UserId/uploadsmimecerts" -Method 'POST' -Headers $headerscertuser -Body $body

        # Increment success counter
        $successCount++
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Success: Certificate uploaded for user $user"
        Write-Host $logMessage
        Add-Content -Path $logFilePath -Value $logMessage -Force

        # Move and rename successful PFX files to "done" folder
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $doneFilePath = Join-Path $doneFolder "$user-$timestamp.pfx"
        Move-Item -Path $pfxFile.FullName -Destination $doneFilePath -Force

    } catch {
        # Increment failure counter
        $failureCount++
        $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Error: Failed to upload certificate for user $user. $_"
        Write-Host $logMessage
        Add-Content -Path $logFilePath -Value $logMessage -Force
    }
}

# Rotate log if needed
$currentDate = Get-Date
$lastWriteTime = (Get-Item $logFilePath).LastWriteTime
$daysDifference = ($currentDate - $lastWriteTime).Days

if ($daysDifference -ge $logRotationDays) {
    Rotate-Log -logFilePath $logFilePath
}

# Display summary
Write-Host "Upload summary:"
Write-Host "Success count: $successCount"
Write-Host "Failure count: $failureCount"
