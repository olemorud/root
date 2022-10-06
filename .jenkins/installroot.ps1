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
    [string]$Workdir = "$HOME/ROOT"    # Where to download, setup and install ROOT
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

if(Test-Path $Workdir){
    Remove-Item $Workdir/* -Recurse -Force
} else {
    New-Item -ItemType Directory -Force -Path "$Workdir"
}

Set-Location $Workdir
$ArchiveName = & "$PSScriptRoot/s3win/getbuildname.ps1"
& "$PSScriptRoot/s3win/download.ps1" "$ArchiveName"

try {
    Expand-Archive -Path "$ArchiveName" `
                   -DestinationPath "$Workdir" `
                   -Force
    Set-Location "$Workdir/source"
    git pull
} catch {
    Set-Location "$Workdir"
    git clone --branch $Branch `
              --depth=1 `
              "https://github.com/root-project/root.git" `
              "$Workdir/source"
    New-Item -ItemType Directory -Force -Path "$Workdir/build"
    New-Item -ItemType Directory -Force -Path "$Workdir/install"
}

Set-Location "$Workdir/build"

Write-Host "cmake $CMakeParams `"$Workdir/source/`""
cmake @CMakeParams "$Workdir/source/"
cmake --build "$Workdir/build" --config "$Config" --target install


Pop-Location
