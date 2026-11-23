param([Parameter(Mandatory)][string]$Adb,[string]$Serial='emulator-5554')
$ErrorActionPreference='Stop'
if($Serial -notmatch '^emulator-\d+$' -or (& $Adb -s $Serial emu avd name | Select-Object -First 1).Trim() -ne 'WispelPhone'){throw 'Requires the WispelPhone test AVD'}
function Tap([string]$label){& "$PSScriptRoot/PhoneScreen.ps1" -Adb $Adb -Serial $Serial -Tap $label;Start-Sleep -Milliseconds 350}
function CheckEvent([string]$kind,[bool]$visible,[bool]$localOnly=$false){
    $eid=(node "$PSScriptRoot/relay-live.mjs" emit $kind).Trim()
    if($LASTEXITCODE){throw 'Could not enqueue the test event'}
    for($i=0;$i -lt 15;$i++){
        $row=(& $env:WISPEL_QA_EXE status --home $env:WISPEL_QA_HOME | ConvertFrom-Json).events | Where-Object eventId -eq $eid
        if($row.status -eq 'ack'){break};Start-Sleep -Milliseconds 500
    }
    if($row.status -ne 'ack'){throw "No acknowledgement for $kind"}
    $tag=[regex]::Escape($row.sourceId+'.'+$kind)
    $matchesFound=@(& $Adb -s $Serial shell dumpsys notification --noredact | Select-String "NotificationRecord.*pkg=app.wispel.phone .*tag=$tag ")
    if($visible -ne ($matchesFound.Count -gt 0)){throw "Unexpected display state for $kind"}
    if($visible -and $localOnly -ne ($matchesFound[0].Line -match 'LOCAL_ONLY')){throw "Wrong watch routing flag for $kind"}
    "PASS $kind visible=$visible localOnly=$localOnly"
}
Tap '기기 설정'
Tap '워치에 표시'
Tap '메일플러그 · 워치'
CheckEvent mail $true $true
CheckEvent kakao $true $false
Tap '메일플러그 · 워치'
Tap '‹ 설정'
Tap '잠시 쉬기'
Tap '1시간 쉬기'
CheckEvent slack $false
Tap '재개'
CheckEvent slack $true
Tap '‹ 설정'
Tap '받을 알림'
Tap '새 문자'
CheckEvent sms $false
Tap '새 문자'
CheckEvent sms $true
Tap '‹ 설정'
Tap '최근 알림'
