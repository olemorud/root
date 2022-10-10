# POWERSHELL SCRIPT TO INSTALL ROOT ON WINDOWS
#
# maintainer: Ole Morud ole.kristian.morud@cern.ch
#
<# Usage:
installroot.ps1  -Generator        <Generator> `
                 -TargetArch       [ARM|ARM64|Win32|x64] `
                 -Config           [Debug, MinSizeRel, Optimized, Release, RelWithDebInfo] `
                 -ToolchainVersion [x64|Win32] `
                 -Workdir          <Path>
#>

param(
    [string]$Branch = "latest-stable", # The github branch of ROOT to build
    [string]$Config = "Release",       # Debug, MinSizeRel, Optimized, Release, RelWithDebInfo
    [string]$Generator = "",           # The Generator used to build ROOT, `cmake --help` lists available generators
    [string]$TargetArch = "x64",       # ARM, ARM64, Win32, x64
    [string]$ToolchainVersion = "x64", # Version of host tools to use, e.g. x64 or Win32.
    [string]$Workdir = "$HOME/ROOT",   # Where to download, setup and install ROOT
    [bool]$StubCMake = 0
)
$CMakeParams = @(
    "-DCMAKE_INSTALL_PREFIX=`"$Workdir/install`"",
    "-A`"$TargetArch`"",
    "-Thost=`"$ToolchainVersion`""
)
if ($Generator) {
    $CMakeParams += "-G`"$Generator`""
}


Push-Location

$global:ScriptLog = ""

# Does not work very well with:
# - variable assignments
# - ampersands
# - pipes / redirections
# - control flows / script blocks
function log {
    $Command = "$args"
    $e = [char]27

    Write-Host "$e[1m" # bold text
    Write-Host "$Command"

    $global:ScriptLog += "`n$Command"

    Write-Host "$e[0m" # reset text
    $Time = Measure-Command {
        Invoke-Expression $Command
    }

    if($Time:TotalSeconds -gt 15){
        Write-Host "$e[3m" # italic
        Write-Host "Finished expression in $Time:TotalMinutes minutes"
    }

    Write-Host "$e[0m" # reset
}



# Print useful debug information
Get-ChildItem env:* | Sort-Object name # dump env
Get-Date



# Test S3 connection
try {
    Write-Output "Hello World" > helloworld.txt
    & "$PSScriptRoot/s3win/upload.ps1" "helloworld.txt" | Out-Null
    & "$PSScriptRoot/s3win/download.ps1" "helloworld.txt" | Out-Null
} catch {
    Write-Host $_
    Write-Host @'
===========================================================
                 COULD NOT CONNECT TO S3

             BUILD ARTIFACTS ARE NOT STORED
===========================================================
'@
    $env:INCREMENTAL = false
}



# Clear the workspace
log @"
if(Test-Path $Workdir){
    Remove-Item $Workdir/* -Recurse -Force
} else {
    New-Item -ItemType Directory -Force -Path "$Workdir"
}
"@

log Set-Location $Workdir
$ArchiveName = & "$PSScriptRoot/s3win/getbuildname.ps1"
$ArchiveName += '.tar.gz'



# Download and extract previous build artifacts if incremental
# If not, download entire source from git
log @"
if($env:INCREMENTAL){
    & "$PSScriptRoot/s3win/download.ps1" "$ArchiveName"
    tar xvf "$ArchiveName" -C '/'
    Set-Location "$Workdir/source"
    git pull
} else {
    Set-Location "$Workdir"
    git clone --branch $Branch --depth=1 "https://github.com/root-project/root.git" "$Workdir/source"
    New-Item -ItemType Directory -Force -Path "$Workdir/build"
    New-Item -ItemType Directory -Force -Path "$Workdir/install"
}
@"



# Generate, build and install
log Set-Location "$Workdir/build"

if(-Not ($StubCMake)){
    log cmake @CMakeParams "$Workdir/source/"
    log cmake --build "$Workdir/build" --config "$Config" --target install
} else {
    Write-Host 'Stubbing CMake step, creating files ./build/buildfile and ./install/installedfile'
    Write-Output "this is a generator file"  > "$Workdir/build/buildfile"
    Write-Output "this is an installed file" > "$Workdir/install/installedfile"
}



# Upload build artifacts to S3
log @"
if(Test-Path $ArchiveName){
    Write-Host "Remove-Item $Workdir/$ArchiveName"
    Remove-Item "$Workdir/$ArchiveName"
}
"@

log tar Pczf "$Workdir/$ArchiveName" "$Workdir/source" "$Workdir/build" "$Workdir/install"

try {
    log Set-Location "$Workdir"
    log "& `"$PSScriptRoot/s3win/upload.ps1`" `"$ArchiveName`""
} catch {
    Write-Host $_
    Write-Host @'
===========================================================
                 ERROR UPLOADING FILES

             BUILD ARTIFACTS ARE NOT UPLOADED
===========================================================
'@
}



# Write a log of commands needed to replcate build
Write-Host @"
`n`n`n
************************************
*    Script to replicate build     *
************************************
$global:ScriptLog

************************************
"@

Pop-Location
