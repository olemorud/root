# POWERSHELL SCRIPT TO INSTALL ROOT ON WINDOWS
#
# maintainer: Ole Morud ole.kristian.morud@cern.ch
#
<# Usage (All parameters are optional, see below for default values):
installroot.ps1  -Generator        <Generator> `
                 -TargetArch       [ARM|ARM64|Win32|x64] `
                 -Config           [Debug, MinSizeRel, Optimized, Release, RelWithDebInfo] `
                 -ToolchainVersion [x64|Win32] `
                 -Workdir          <Path>

 WARNING:
   All contents of <Workdir> will be deleted!
#>

param(
    [string]$Branch = "latest-stable", # The github branch of ROOT to build
    [string]$Config = "Release",       # Debug, MinSizeRel, Optimized, Release, RelWithDebInfo
    [string]$Generator = "",           # The Generator used to build ROOT, `cmake --help` lists available generators
    [string]$TargetArch = "x64",       # ARM, ARM64, Win32, x64
    [string]$ToolchainVersion = "x64", # Version of host tools to use, e.g. x64 or Win32.
    [string]$Workdir = "$HOME/ROOT",   # Where to download, setup and install ROOT
    [bool]$StubCMake = 1
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

    Write-Host '************'
    Write-Host $Command
    Write-Host '************'

    $global:ScriptLog += "`n$Command"

    $Time = Measure-Command {
        Invoke-Expression $Command
    }

    if($Time.TotalSeconds -gt 15){
        Write-Host "Finished in $Time.TotalMinutes minutes"
    }
}



# Print useful debug information
Get-ChildItem env:* | Sort-Object name # dump env
Get-Date
#Set-PSDebug -Trace 2 # 1: trace script lines, 2: also trace var-assigns, func. calls and scripts



# Test S3 connection
try {
    Write-Output "Hello World" > helloworld.txt
    & "$PSScriptRoot/s3win/upload.ps1" "helloworld.txt"
    & "$PSScriptRoot/s3win/download.ps1" "helloworld.txt"
} catch {
    Write-Host $_
    Write-Host @'
===========================================================
                 COULD NOT CONNECT TO S3

             BUILD ARTIFACTS ARE NOT STORED
===========================================================
'@
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
if($INCREMENTAL){
    log @"
    & "$PSScriptRoot/s3win/download.ps1" "$ArchiveName"
    Expand-Archive -Path "$ArchiveName" `
                   -DestinationPath "$Workdir" `
                   -Force
    Set-Location "$Workdir/source"
    git pull
"@
} else {
    log @"
    Set-Location "$Workdir"
    git clone --branch $Branch --depth=1 "https://github.com/root-project/root.git" "$Workdir/source"
    New-Item -ItemType Directory -Force -Path "$Workdir/build"
    New-Item -ItemType Directory -Force -Path "$Workdir/install"
"@
}



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

log tar czf "$Workdir/$ArchiveName" "$Workdir/source" "$Workdir/build" "$Workdir/install"

try {
    log Set-Location "$Workdir"
    Write-Host @"
& "$PSScriptRoot/s3win/upload.ps1" "$ArchiveName"
"@
    $global:ScriptLog += @"
& "$PSScriptRoot/s3win/upload.ps1" "$ArchiveName"
"@
    Measure-Command {
        & "$PSScriptRoot/s3win/upload.ps1" "$ArchiveName"
    } | Select-Object TotalMinutes
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
************************************
*    Script to replicate build     *
************************************
"@
Write-Host $global:ScriptLog


Pop-Location
