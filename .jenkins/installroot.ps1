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
#>

param(
    [string]$Generator = "Visual Studio 17 2022",       # The Generator used to build ROOT, `cmake --help` lists available generators
    [string]$TargetArch = "x64",                        # ARM, ARM64, Win32, x64
    [string]$Config = "Release",                        # Debug, MinSizeRel, Optimized, Release, RelWithDebInfo
    [string]$CMakeInstallPrefix = "$HOME/ROOT/install", # CMAKE_INSTALL_PREFIX
    [string]$ToolchainVersion = "x64",                  # Version of host tools to use, e.g. x64 or Win32.
    [string]$Workdir = "$HOME/ROOT"                     # Where to download, setup and install ROOT

)
$CMakeParams = @()
if ($Generator)          { $CMakeParams += "-G`"$Generator`"" }
if ($TargetArch)         { $CMakeParams += "-A `"$TargetArch`"" }
if ($ToolchainVersion)   { $CMakeParams += "-Thost=`"$ToolchainVersion`"" }
if ($CMakeInstallPrefix) { $CMakeParams += "-DCMAKE_INSTALL_PREFIX=`"$CMakeInstallPrefix`"" }


Push-Location

if(Test-Path -Path "$Workdir/source") {
    Remove-Item -Recurse -Force "$Workdir/source"
}
git clone --branch latest-stable --depth=1 https://github.com/root-project/root.git $Workdir/source

# -Force does not overwrite directories but supresses warnings
New-Item -ItemType Directory -Force -Path "$Workdir/build"
New-Item -ItemType Directory -Force -Path "$Workdir/install"
Set-Location "$Workdir/build"

Write-Host "cmake $CMakeParams `"$Workdir/source/`""
cmake @CMakeParams "$Workdir/source/"
cmake --build "$Workdir/build" --config "$Config" --target install


Pop-Location
