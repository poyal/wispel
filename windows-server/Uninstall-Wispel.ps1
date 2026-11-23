#Requires -RunAsAdministrator
[CmdletBinding()]
param([ValidatePattern('^Wispel(?:QA)?$')][string]$ServiceName='Wispel',[switch]$RemoveTestData)
$ErrorActionPreference='Stop'
if ($RemoveTestData -and $ServiceName -ne 'WispelQA') {throw 'Only QA data may be removed by this script'}
$service=Get-Service $ServiceName -ErrorAction SilentlyContinue
if($service){
    Stop-Service $ServiceName
    & sc.exe delete $ServiceName
    if($LASTEXITCODE){throw 'Service removal failed'}
}
foreach($root in @($env:ProgramFiles,$env:ProgramData)){
    if($root -eq $env:ProgramData -and !$RemoveTestData){continue}
    $expected=[IO.Path]::GetFullPath((Join-Path $root $ServiceName))
    if(Test-Path -LiteralPath $expected){
        $entry=Get-Item -LiteralPath $expected
        if($entry.FullName -ne $expected -or $entry.Parent.FullName -ne $root -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unexpected installation path'}
        # The service can report Stopped before Windows releases its mapped runtime DLLs.
        for ($attempt=1; $attempt -le 12; $attempt++) {
            try {
                Remove-Item -LiteralPath $expected -Recurse -Force -ErrorAction Stop
                break
            } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
                if ($attempt -eq 12) { throw }
                Start-Sleep -Seconds 1
            }
        }
    }
}
