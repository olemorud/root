
# This program returns an s3 token
# It is dependent on OpenStack application credentials saved as rc.ps1

. "$PSScriptRoot/rc.ps1"

$Headers = @{
    'Content-Type' = 'application/json'
}


$Body = @"
    {
        "auth": {
            "identity": {
                "methods": ["application_credential"],
                "application_credential": {
                    "id": "$OS_APPLICATION_CREDENTIAL_ID",
                    "secret": "$OS_APPLICATION_CREDENTIAL_SECRET"
                }
            }
        }
    }
"@

$Response = Invoke-WebRequest `
     -Method 'POST' `
     -Body $Body `
     -Headers $Headers `
     -Uri "$OS_AUTH_URL/auth/tokens?nocatalog"
 
return $Response.Headers['X-Subject-Token']
