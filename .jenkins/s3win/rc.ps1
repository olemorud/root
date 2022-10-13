
$OS_AUTH_TYPE            = 'v3applicationcredential'
$OS_AUTH_URL             = 'https://keystone.cern.ch/v3'
$OS_IDENTITY_API_VERSION = '3'
$OS_REGION_NAME          = 'cern'
$OS_INTERFACE            = 'public'

# Secret must be provided externally
$OS_APPLICATION_CREDENTIAL_ID     = $env:OS_APPLICATION_CREDENTIAL_ID
$OS_APPLICATION_CREDENTIAL_SECRET = $env:OS_APPLICATION_CREDENTIAL_SECRET
