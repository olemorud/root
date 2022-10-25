

param(
    [Parameter(mandatory=$true)]
    [string[]]$CMakeParams = @("")
)

$Timestamp = Get-Date -Format yyyy-MM-dd

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


return "$env:PLATFORM/$BRANCH/$env:CONFIG/$Hash-$Timestamp"

