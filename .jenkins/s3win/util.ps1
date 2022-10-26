# When logging, Pipes, ampersands and some other symbols have to be escaped

$global:ScriptLog = ""
function log {
    $Command = "$args"
    $e = [char]27

    Write-Host "$e[1m" # bold text
    Write-Host "$Command"
    Write-Host "$e[0m" # reset text

    $global:ScriptLog += "`n`n$Command"

    $global:LASTEXITCODE = 0
    $Time = Measure-Command {
        Invoke-Expression -Command "$Command" | Out-Default
    }
    if($LASTEXITCODE -ne 0) {
        Write-Host "$e[1m$e[31m" # bold red
        Write-Host "Expression above failed with error $LASTEXITCODE"
        Write-Host "$e[1m$e[31m" # reset
        throw
    } else {
        Write-Host "$e[3m" # italic
        Write-Host "Finished expression in $Time"
        Write-Host "$e[0m" # reset
    }
}


function UploadArchive( [String]$Token, [String]$Filename )
{

    $Url='https://s3.cern.ch/swift/v1/ROOT-build-artifacts'
    $Headers = @{ 'X-Auth-Token' = "$Token" }

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest             `
        -Uri     "$Url/$Filename" `
        -Method  'PUT'            `
        -Infile  "$Filename"      `
        -Headers $Headers
}


function SearchArchive( [String]$Token, [String]$Prefix )
{

    $Url="https://s3.cern.ch/swift/v1/ROOT-build-artifacts?prefix=$Prefix"
    $Headers = @{ 'X-Auth-Token' = "$Token" }

    $ProgressPreference = 'SilentlyContinue'
    $Results = Invoke-WebRequest `
        -Uri     "$Url" `
        -Method  'GET' `
        -Headers $Headers
    
    return $Results
}


function DownloadArchive( [String]$Token, [String]$Filename )
{

    $Url='https://s3.cern.ch/swift/v1/ROOT-build-artifacts'
    $Headers = @{ 'X-Auth-Token' = "$Token" }

    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest  `
        -Uri     "$Url/$Filename" `
        -Method  'GET'            `
        -OutFile "$Filename"      `
        -Headers $Headers
}



function GetArchiveNamePrefix( [string[]]$CMakeParams = @("") ) {
    # Hashing as a Service (HaaS)
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.StreamWriter]::new($stream)
    foreach ($value in $CMakeParams) {
        $writer.write($value)
    }
    $writer.write("Hello World")
    $writer.flush()
    $stream.Position = 0
    $Hash = (Get-FileHash -Algorithm SHA1 -InputStream $Stream).Hash.ToLower()


    return "$env:PLATFORM/$BRANCH/$env:CONFIG/$Hash/"
}