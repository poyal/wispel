param([Parameter(Mandatory)][string]$Adb,[string]$Serial='emulator-5554')
$ErrorActionPreference='Stop'
if ($Serial -notmatch '^emulator-\d+$') { throw 'Choose a QA phone emulator' }
if (!$env:WISPEL_QA_HOME -or !$env:WISPEL_QA_EXE) { throw 'Configure the isolated QA server first' }
function Read-Status {
    $json = & $env:WISPEL_QA_EXE status --home $env:WISPEL_QA_HOME
    if ($LASTEXITCODE) { throw 'Could not read QA relay status' }
    $json | ConvertFrom-Json
}
$status = Read-Status
$senders = @($status.devices | Where-Object { $_.platform -eq 'android' -and $_.role -eq 'send' })
if ($senders.Count -ne 1) { throw 'Register the emulator as the only Android sender on the QA relay' }
$known = @($status.events.eventId)
& $Adb -s $Serial shell input keyevent KEYCODE_HOME
foreach ($index in 1..2) {
    & $Adb -s $Serial emu sms send 5557538 wispel-same
    if ($LASTEXITCODE) { throw 'Could not inject the test SMS' }
    Start-Sleep -Seconds 3
}
$until = (Get-Date).AddSeconds(35)
do {
    $new = @((Read-Status).events | Where-Object {
        $_.sourceId -eq $senders[0].id -and $_.kind -eq 'sms' -and $_.eventId -notin $known
    })
    if ($new.Count -ge 2) {break}
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $until)
Start-Sleep -Seconds 5
$new = @((Read-Status).events | Where-Object {
    $_.sourceId -eq $senders[0].id -and $_.kind -eq 'sms' -and $_.eventId -notin $known
})
if ($new.Count -ne 2) { throw "Expected two distinct incoming SMS events, received $($new.Count)" }
'PASS two identical SMS inputs, two events after conversation updates'
