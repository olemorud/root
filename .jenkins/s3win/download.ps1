
param(
    [Parameter(Mandatory=$true)]
    [String]$Filename
)

$Url='https://s3.cern.ch/swift/v1/ROOT-build-artifacts'
$Token= & "$PSScriptRoot/auth.ps1"
$Headers = @{ 'X-Auth-Token' = "$Token" }

$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest             `
    -Uri     "$Url/$Filename" `
    -Method  'GET'            `
    -OutFile "$Filename"      `
    -Headers $Headers
