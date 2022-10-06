
param(
    [Parameter(Mandatory=$true)]
    [String]$Filename
)

$Url='https://s3.cern.ch/swift/v1/ROOT-build-artifacts'
$Token= & "$PSScriptRoot/auth.ps1"
$Headers = @{ 'X-Auth-Token' = "$Token" }

Invoke-WebRequest             `
    -Uri     "$Url/$Filename" `
    -Method  'PUT'            `
    -Infile  "$Filename"      `
    -Headers $Headers
