

param(
    [Parameter(mandatory=$true)]
    [string[]]$CMakeParams = @(""),

    [Parameter(mandatory=$true)]
    [string]$Config = ""
)

$Timestamp = Get-Date -Format yyyy-MM-dd

# calculate a simple SHA1 of cmake options 🥲
$stream = [System.IO.MemoryStream]::new()
$writer = [System.IO.StreamWriter]::new($stream)
foreach ($value in $CMakeParams) {
    $writer.write($value)
}
$writer.write("Hello World")
$writer.flush()
$stream.Position = 0
$Hash = (Get-FileHash -Algorithm SHA1 -InputStream $Stream).Hash.ToLower()


return "$env:PLATFORM/$BRANCH/$Config/$Hash-$Timestamp"

