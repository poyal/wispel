param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._@-]*$')][string]$Mac,
    [Parameter(Mandatory)][guid]$Simulator,
    [Parameter(Mandatory)][ValidateSet('Burst','WaitForAck','SingleWorkflow')][string]$Mode,
    [ValidatePattern('^[a-zA-Z0-9-]+$')][string]$PhoneWorkflow='Wispel-Call',
    [ValidateRange(0,30)][int]$IntervalSeconds=3
)
$ErrorActionPreference='Stop'
function Read-Relay {
    $json=& $env:WISPEL_QA_EXE status --home $env:WISPEL_QA_HOME
    if ($LASTEXITCODE) {throw 'Could not read the QA relay'}
    $json | ConvertFrom-Json
}
function Invoke-Mac([string]$command) {
    & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes $Mac $command | Out-Null
    if ($LASTEXITCODE) {throw 'Simulator command failed'}
}
$initial=Read-Relay
$senders=@($initial.devices | Where-Object {$_.platform -eq 'ios' -and $_.role -eq 'send'})
$receivers=@($initial.devices | Where-Object {$_.platform -eq 'android' -and $_.role -eq 'receive'})
if ($senders.Count -ne 1 -or $receivers.Count -ne 1) {throw 'Requires an isolated QA relay with one iOS sender and a connected Android receiver'}
$baseline=@($initial.events.eventId)
function Read-NewEvents {
    (Read-Relay).events | Where-Object {$_.sourceId -eq $senders[0].id -and $_.eventId -notin $baseline}
}
$inputs=[ordered]@{
    sms='Wispel-Sms'
    mail='Wispel-Mail'
    slack='Wispel-Slack'
    call="$PhoneWorkflow&input=text&text=QA%20incoming"
    missedCall="$PhoneWorkflow&input=text&text=" + [Uri]::EscapeDataString("QA`n부재중 전화")
    kakao='Wispel-Kakao'
}
$urls=@($inputs.Values | ForEach-Object {"'shortcuts://run-shortcut?name=$_'"})
# All arms use the same device, startup sequence and input order.
Invoke-Mac "set -e; xcrun simctl shutdown $Simulator; xcrun simctl boot $Simulator; xcrun simctl bootstatus $Simulator -b >/dev/null; xcrun simctl install $Simulator ~/Library/Developer/WispelQA/Derived/Build/Products/Debug-iphonesimulator/Wispel.app; xcrun simctl launch $Simulator app.wispel.phone; sleep 3"
$start=[DateTimeOffset]::Now
if ($Mode -eq 'SingleWorkflow') {
    Invoke-Mac "xcrun simctl openurl $Simulator 'shortcuts://run-shortcut?name=Wispel-QA-DirectSix'"
} elseif ($Mode -eq 'Burst') {
    # The timed arm must not insert a Windows/SSH round trip between launches.
    Invoke-Mac ('set -e; for url in '+($urls -join ' ')+'; do xcrun simctl openurl '+$Simulator+' "$url"; sleep '+$IntervalSeconds+'; done')
} else {
    $i=0
    foreach ($kind in $inputs.Keys) {
        Invoke-Mac "xcrun simctl openurl $Simulator $($urls[$i])"
        $i++
        $deadline=(Get-Date).AddSeconds(75)
        do {
            $ack=@(Read-NewEvents | Where-Object {$_.kind -eq $kind -and $_.status -eq 'ack'})
            if ($ack.Count -gt 0) {break}
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $deadline)
        if ($ack.Count -ne 1) {break}
    }
}
if ($Mode -ne 'SingleWorkflow') {Invoke-Mac "xcrun simctl launch $Simulator app.wispel.phone"}
# Include late executions after the final URL and detect unexpected duplicates.
$deadline=(Get-Date).AddSeconds(75)
do {
    $events=@(Read-NewEvents)
    if (@($events | Where-Object status -eq 'ack').Count -ge $inputs.Count) {Start-Sleep -Seconds 3; break}
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $deadline)
$events=@(Read-NewEvents)
$checks=@(foreach ($kind in $inputs.Keys) {
    $rows=@($events | Where-Object kind -eq $kind)
    [pscustomobject]@{Kind=$kind;Accepted=$rows.Count;Acknowledged=@($rows | Where-Object status -eq 'ack').Count}
})
[pscustomobject]@{Mode=$Mode;Started=$start.ToString('o');Kinds=$checks} | ConvertTo-Json -Depth 4
if (@($checks | Where-Object {$_.Accepted -ne 1 -or $_.Acknowledged -ne 1}).Count) {throw 'One or more launches did not produce exactly one acknowledged event'}
