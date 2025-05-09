<#
.SYNOPSIS
    Generates a full user report from Active Directory and Entra ID with real-time output and Arabic-safe CSV export.

.DESCRIPTION
    This script collects user data from both on-premises Active Directory and Microsoft Entra ID (Azure AD), 
    merges them by username, shows progress and user info as it processes, and exports the result to the desktop.

    It is optimized for large environments and provides detailed user data for auditing and comparison.

.NOTES
    Author  : Mohammad Abdulkader Omar
    Website : momar.tech
    Date: 2025-05-07
#>

# Load required modules
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop

# Connect to Microsoft Graph
Write-Host "🔄 Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All" -NoWelcome
Write-Host "✅ Connected to Microsoft Graph.`n" -ForegroundColor Green

# Prepare export paths
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$desktopPath = [Environment]::GetFolderPath('Desktop')
if (-not (Test-Path $desktopPath)) {
    $desktopPath = "C:\\Temp"
    if (-not (Test-Path $desktopPath)) { New-Item -Path $desktopPath -ItemType Directory | Out-Null }
}
$csvPath = Join-Path $desktopPath "FullUserReport-$timestamp.csv"
$columns = @(
    'Username','DisplayName','Department','Title','Email',
    'InAD','AD_Enabled','AD_Created','AD_LastLogon','AD_WhenChanged','AD_PwdLastSet','AD_Description','AD_DistinguishedName',
    'InEntraID','Entra_Enabled','Entra_Created','Entra_LastInteractiveSignIn','Entra_LastNonInteractiveSignIn'
)

# Create blank CSV file with headers
@() | Select-Object $columns | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# Start logging
$logPath = Join-Path $desktopPath "HybridUserAuditLog-$timestamp.txt"
Start-Transcript -Path $logPath -Append

# Retrieve all Entra ID users and index by username
Write-Host "🔎 Fetching Entra ID users..." -ForegroundColor Yellow
$entraLookup = @{}
$j = 0
try {
    Get-MgUser -All -Property DisplayName, UserPrincipalName, Department, JobTitle, Mail, AccountEnabled, CreatedDateTime, SignInActivity | ForEach-Object {
        $j++
        $username = ($_.UserPrincipalName -split "@")[0].ToLower()
        $entraLookup[$username] = $_
        Write-Host "[EntraID] $j - $username : $($_.DisplayName)" -ForegroundColor DarkYellow
    }
    Write-Host "✅ Finished loading Entra ID users.`n" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to fetch Entra ID users: $($_.Exception.Message)" -ForegroundColor Red
}

# Process AD users alphabetically by SamAccountName to avoid enumeration issues
Write-Host "🔁 Processing AD users and writing merged report..." -ForegroundColor Cyan
$i = 0
$prefixes = @('a','b','c','d','e','f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x','y','z','0','1','2','3','4','5','6','7','8','9')
foreach ($prefix in $prefixes) {
    Write-Host "🔍 Fetching AD users starting with '$prefix'..." -ForegroundColor Yellow
    Get-ADUser -LDAPFilter "(sAMAccountName=$prefix*)" -Properties * | ForEach-Object {
        $i++
        $adUser = $_
        $username = $adUser.SamAccountName.ToLower()
        $entraUser = $entraLookup[$username]

        $record = [PSCustomObject]@{
            Username                        = $username
            InAD                            = "Yes"
            InEntraID                       = if ($entraUser) { "Yes" } else { "No" }
            DisplayName                     = if ($adUser.DisplayName) { $adUser.DisplayName } elseif ($entraUser) { $entraUser.DisplayName } else { "" }
            Department                      = if ($adUser.Department) { $adUser.Department } elseif ($entraUser) { $entraUser.Department } else { "" }
            Title                           = if ($adUser.Title) { $adUser.Title } elseif ($entraUser) { $entraUser.JobTitle } else { "" }
            Email                           = if ($adUser.Mail) { $adUser.Mail } elseif ($entraUser) { $entraUser.Mail } else { "" }
            AD_Enabled                      = if ($adUser.Enabled) { 'Enabled' } else { 'Disabled' }
            Entra_Enabled                   = if ($entraUser.AccountEnabled) { 'Enabled' } else { 'Disabled' }
            AD_Created                      = $adUser.WhenCreated.ToString("yyyy-MM-dd")
            Entra_Created                   = if ($entraUser.CreatedDateTime) { $entraUser.CreatedDateTime.ToString("yyyy-MM-dd") } else { "" }
            AD_LastLogon                    = if ($adUser.LastLogonDate) { $adUser.LastLogonDate.ToString("yyyy-MM-dd") } else { "" }
            Entra_LastInteractiveSignIn     = if ($entraUser.SignInActivity.LastSignInDateTime) { $entraUser.SignInActivity.LastSignInDateTime.ToString("yyyy-MM-dd") } else { "" }
            Entra_LastNonInteractiveSignIn  = if ($entraUser.SignInActivity.LastNonInteractiveSignInDateTime) { $entraUser.SignInActivity.LastNonInteractiveSignInDateTime.ToString("yyyy-MM-dd") } else { "" }
            AD_WhenChanged                  = if ($adUser.whenChanged) { $adUser.whenChanged.ToString("yyyy-MM-dd") } else { "" }
            AD_PwdLastSet                   = if ($adUser.pwdLastSet) { ([datetime]::FromFileTime($adUser.pwdLastSet)).ToString("yyyy-MM-dd") } else { "" }
            AD_Description                  = $adUser.Description
            AD_DistinguishedName            = $adUser.DistinguishedName
        }

        $record | Select-Object $columns | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Append
        Write-Host "[✔] $i - $username : $($record.DisplayName)" -ForegroundColor Magenta
    }
}

Stop-Transcript
Write-Host "`n✅ Report saved to: $csvPath" -ForegroundColor Green
Start-Process "explorer.exe" -ArgumentList (Split-Path $csvPath)
