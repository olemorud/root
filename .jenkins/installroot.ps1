<#
POWERSHELL SCRIPT TO INSTALL ROOT ON WINDOWS

maintainer: Ole Morud ole.kristian.morud@cern.ch

Usage:
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
    [string]$TargetArch = "Win32",     # ARM, ARM64, Win32, x64
    [string]$ToolchainVersion = "x64", # Version of host tools to use, e.g. x64 or Win32.
    [string]$Workdir = "$HOME/ROOT",   # Where to download, setup and install ROOT
    [bool]$StubCMake = 0
)
$CMakeParams = @(
    "-DCMAKE_INSTALL_PREFIX=`"$Workdir/install`"",
    "-A`"$TargetArch`"",
    "-Thost=`"$ToolchainVersion`""
    "-Dalien=Off",
    "-Darrow=Off",
    "-Dasimage=On",
    "-Dasserts=Off",
    "-Dbuiltin_afterimage=On",
    "-Dbuiltin_cfitsio=On",
    "-Dbuiltin_cppzmq=Off",
    "-Dbuiltin_davix=Off",
    "-Dbuiltin_fftw3=Off",
    "-Dbuiltin_freetype=On",
    "-Dbuiltin_ftgl=On",
    "-Dbuiltin_gl2ps=On",
    "-Dbuiltin_glew=On",
    "-Dbuiltin_gsl=Off",
    "-Dbuiltin_lz4=On",
    "-Dbuiltin_lzma=On",
    "-Dbuiltin_nlohmannjson=On",
    "-Dbuiltin_openssl=Off",
    "-Dbuiltin_openui5=On",
    "-Dbuiltin_pcre=On",
    "-Dbuiltin_tbb=On",
    "-Dbuiltin_unuran=On",
    "-Dbuiltin_vc=Off",
    "-Dbuiltin_vdt=Off",
    "-Dbuiltin_veccore=Off",
    "-Dbuiltin_xrootd=Off",
    "-Dbuiltin_xxhash=On",
    "-Dbuiltin_zeromq=Off",
    "-Dbuiltin_zlib=On",
    "-Dbuiltin_zstd=On",
    "-Dcefweb=Off",
    "-Dclad=On",
    "-Dcocoa=Off",
    "-Dcuda=Off",
    "-Dcudnn=Off",
    "-Ddaos=Off",
    "-Ddataframe=On",
    "-Ddavix=Off",
    "-Ddcache=Off",
    "-Ddev=Off",
    "-Ddistcc=Off",
    "-Dfcgi=Off",
    "-Dfftw3=On",
    "-Dfitsio=Off",
    "-Dfortran=Off",
    "-Dgdml=On",
    "-Dgfal=Off",
    "-Dgsl_shared=Off",
    "-Dgviz=Off",
    "-Dhttp=On",
    "-Dimt=On",
    "-Dlibcxx=Off",
    "-Dmathmore=Off",
    "-Dminuit2=On",
    "-Dmlp=On",
    "-Dmonalisa=Off",
    "-Dmpi=Off",
    "-Dmysql=Off",
    "-Dodbc=Off",
    "-Dopengl=On",
    "-Doracle=Off",
    "-Dpgsql=Off",
    "-Dpyroot2=Off",
    "-Dpyroot3=On",
    "-Dpyroot=On",
    "-Dpyroot_legacy=Off",
    "-Dpythia6=Off",
    "-Dpythia6_nolink=Off",
    "-Dpythia8=Off",
    "-Dqt5web=Off",
    "-Dqt6web=Off",
    "-Dr=Off",
    "-Droofit=On",
    "-Droofit_hs3_ryml=Off",
    "-Droofit_multiprocess=Off",
    "-Dshadowpw=Off",
    "-Dspectrum=On",
    "-Dsqlite=Off",
    "-Dssl=Off",
    "-Dtest_distrdf_dask=Off",
    "-Dtest_distrdf_pyspark=Off",
    "-Dtmva-cpu=On",
    "-Dtmva-gpu=Off",
    "-Dtmva-pymva=On",
    "-Dtmva-rmva=Off",
    "-Dtmva-sofie=Off",
    "-Dtmva=On",
    "-Dunuran=On",
    "-During=Off",
    "-Dvc=Off",
    "-Dvdt=Off",
    "-Dveccore=Off",
    "-Dvecgeom=Off",
    "-Dwin_broken_tests=Off",
    "-Dx11=Off",
    "-Dxml=Off",
    "-Dxproofd=Off",
    "-Dxrootd=Off"
)
if ($Generator) {
    $CMakeParams += "-G`"$Generator`""
}


Push-Location

$global:ScriptLog = ""



# When logging, Pipes, ampersands and some other symbols have to be escaped
# Variables do not expand when using single quotes.
function log {
    $Command = "$args"
    $e = [char]27

    Write-Host "$e[1m" # bold text
    Write-Host "$Command"
    Write-Host "$e[0m" # reset text

    $global:ScriptLog += "`n$Command"

    $global:LASTEXITCODE = 0
    $Time = Measure-Command {
        Invoke-Expression -Command "$Command" | Out-Default
    }
    if($LASTEXITCODE -ne 0) {
        Write-Host "$e[1m$e[31m" # bold red
        Write-Host "Expression above failed"
        Write-Host "$e[1m$e[31m" # reset
        Exit $LASTEXITCODE
    } else {
        Write-Host "$e[3m" # italic
        Write-Host "Finished expression in $Time"
        Write-Host "$e[0m" # reset
    }
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
if("$env:INCREMENTAL" -eq "true"){
    try {
        log @"
& "$PSScriptRoot/s3win/download.ps1" "$ArchiveName"
"@
        log tar xvf "$ArchiveName" -C '/'
        log Set-Location "$Workdir/source"
        log git pull
    } catch {
        $env:INCREMENTAL="false"
    }
}

if("$env:INCREMENTAL" -eq "false") {
    log git clone --branch $Branch --depth=1 "https://github.com/root-project/root.git" "$Workdir/source"
    log New-Item -ItemType Directory -Force -Path "$Workdir/build"
    log New-Item -ItemType Directory -Force -Path "$Workdir/install"
}



# Generate, build and install
if(-Not ($StubCMake)){
    #$NCores = (Get-CimInstance –ClassName Win32_Processor).NumberOfLogicalProcessors
    log Set-Location "$Workdir/build"
    log cmake  @CMakeParams "$Workdir/source/"
    log cmake --build . --config "$Config" --parallel "$env:NUMBER_OF_PROCESSORS" --target install
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
    log "`& `"$PSScriptRoot/s3win/upload.ps1`" `"$ArchiveName`""
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
