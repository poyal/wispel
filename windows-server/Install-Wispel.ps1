#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PublishDirectory,
    [Parameter(Mandatory)][ipaddress]$Address,
    [ipaddress]$AdvertisedAddress=$Address,
    [ValidateRange(1024,65535)][int]$Port=7443,
    [ValidatePattern('^Wispel(?:QA)?$')][string]$ServiceName='Wispel'
)
$ErrorActionPreference='Stop'
$binaryRoot=Join-Path $env:ProgramFiles $ServiceName
$dataRoot=Join-Path $env:ProgramData $ServiceName
if ((Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) -or (Test-Path $binaryRoot) -or (Test-Path $dataRoot)) { throw "Service or installation directory already exists: $ServiceName" }
$source=(Resolve-Path -LiteralPath $PublishDirectory).Path
if (!(Test-Path -LiteralPath (Join-Path $source 'Wispel.exe'))) { throw 'Missing published Wispel.exe' }
New-Item -ItemType Directory -Path $binaryRoot,$dataRoot | Out-Null
$ownerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $dataRoot /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' ('*'+$ownerSid+':(OI)(CI)F')
if ($LASTEXITCODE) { throw 'Could not protect the data directory' }
Get-ChildItem -LiteralPath $source | Copy-Item -Destination $binaryRoot -Recurse
$exe=Join-Path $binaryRoot 'Wispel.exe'
& $exe init $Address.ToString() $Port $AdvertisedAddress.ToString() --home $dataRoot
if ($LASTEXITCODE) {throw 'Initialization failed'}
$binaryCommand='"'+$exe+'" serve --home "'+$dataRoot+'"'
& sc.exe create $ServiceName binPath= $binaryCommand start= auto obj= 'NT AUTHORITY\LocalService'
if ($LASTEXITCODE) {throw 'Service registration failed'}
& sc.exe sidtype $ServiceName unrestricted
if ($LASTEXITCODE) {throw 'Service SID setup failed'}
& icacls.exe $dataRoot /grant ("NT SERVICE\"+$ServiceName+':(OI)(CI)M')
if ($LASTEXITCODE) {throw 'Service data ACL setup failed'}
Start-Service $ServiceName
Get-Service $ServiceName
