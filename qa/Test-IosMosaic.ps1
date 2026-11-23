param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9._@-]+$')][string]$Mac,
    [Parameter(Mandatory)][guid]$Simulator,
    [Parameter(Mandatory)][string]$Adb,
    [ValidatePattern('^emulator-\d+$')][string]$Serial='emulator-5554',
    [ValidatePattern('^[a-zA-Z0-9-]+$')][string]$PhoneWorkflow='Wispel-Call'
)
$ErrorActionPreference='Stop'
function Status { (& $env:WISPEL_QA_EXE status --home $env:WISPEL_QA_HOME) | ConvertFrom-Json }
function Tap([string]$label) { & "$PSScriptRoot/PhoneScreen.ps1" -Adb $Adb -Serial $Serial -Tap $label; Start-Sleep -Milliseconds 650 }
function Labels { (& "$PSScriptRoot/PhoneScreen.ps1" -Adb $Adb -Serial $Serial -List) -join ' ' }
$senders=@((Status).devices | Where-Object {$_.platform -eq 'ios' -and $_.role -eq 'send'})
if ($senders.Count -ne 1) {throw 'Use an isolated server with one paired iOS sender'}
& $Adb -s $Serial shell input keyevent KEYCODE_WAKEUP
& $Adb -s $Serial shell wm dismiss-keyguard
& $Adb -s $Serial shell am force-stop app.wispel.phone
& $Adb -s $Serial shell am start -n app.wispel.phone/.Home | Out-Null
$until=(Get-Date).AddSeconds(20)
while ((Labels) -notmatch '기기 설정') {if((Get-Date) -gt $until){throw 'Android home did not open'}}
Tap '기기 설정'
Tap '기록 보관'
Tap '기록 전체 삭제'
Tap '최근 알림'
$missed="$PhoneWorkflow&input=text&text=" + [Uri]::EscapeDataString("QA`n부재중 전화")
foreach($entry in @('Wispel-Sms|sms','Wispel-Mail|mail','Wispel-Slack|slack','Wispel-Slack|slack',"$missed|missedCall",'Wispel-Kakao|kakao','Wispel-Kakao|kakao','Wispel-Kakao|kakao')) {
    $workflow,$kind=$entry.Split('|')
    $known=@((Status).events.eventId)
    & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes $Mac "xcrun simctl openurl $Simulator 'shortcuts://run-shortcut?name=$workflow'"
    if($LASTEXITCODE){throw "Could not start $kind"}
    $until=(Get-Date).AddSeconds(30)
    do {
        $acked=@((Status).events | Where-Object {$_.sourceId -eq $senders[0].id -and $_.eventId -notin $known -and $_.kind -eq $kind -and $_.status -eq 'ack'})
        if($acked.Count -eq 1){break}
        Start-Sleep -Milliseconds 700
    } while((Get-Date) -lt $until)
    if($acked.Count -ne 1){throw "Expected one new $kind acknowledgement"}
    Start-Sleep -Seconds 1
}
$screen=Labels
foreach($label in '3건','2건','카카오톡','부재중 전화','Slack','메일플러그','새 문자') {if(!$screen.Contains($label)){throw "Missing Android tile: $label"}}
$folder=Join-Path (Get-Location) 'artifacts/screens'
[IO.Directory]::CreateDirectory($folder) | Out-Null
# Use adb pull for binary integrity in both Windows PowerShell and PowerShell 7.
function Screenshot([string]$name) {
    & $Adb -s $Serial shell screencap -p /sdcard/wispel-qa-screen.png
    & $Adb -s $Serial pull /sdcard/wispel-qa-screen.png (Join-Path $folder $name) | Out-Null
    if($LASTEXITCODE){throw 'Could not capture the Android screen'}
}
Screenshot 'android-home.png'
Tap '기기 설정'
if((Labels) -notmatch '받을 알림'){throw 'Settings page did not load'}
Screenshot 'android-settings.png'
'PASS eight signed shortcut runs, Android acknowledgements and Mosaic tile counts'
