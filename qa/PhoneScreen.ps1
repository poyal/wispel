param([Parameter(Mandatory)][string]$Adb,[string]$Serial='emulator-5554',[string]$Tap,[switch]$List)
$ErrorActionPreference='Stop'
function Read-Nodes {
    & $Adb -s $Serial shell uiautomator dump /sdcard/wispel-qa.xml | Out-Null
    [xml]$ui=(& $Adb -s $Serial shell cat /sdcard/wispel-qa.xml) -join [Environment]::NewLine
    $ui.SelectNodes('//node')
}
$nodes=Read-Nodes
if($List){$nodes | Where-Object {$_.text -or $_.'content-desc'} | ForEach-Object {if($_.text -like 'wispel://*'){'[등록 주소]'}else{$_.text+' '+$_.'content-desc'}};return}
$n=$nodes | Where-Object {$_.text -eq $Tap -or $_.'content-desc' -eq $Tap} | Select-Object -First 1
for($attempt=0;!$n -and $attempt -lt 4;$attempt++){
    $size=(& $Adb -s $Serial shell wm size | Select-Object -Last 1)
    if($size -notmatch '(\d+)x(\d+)'){break}
    $width=[int]$Matches[1];$height=[int]$Matches[2]
    & $Adb -s $Serial shell input swipe ([int]($width/2)) ([int]($height*.76)) ([int]($width/2)) ([int]($height*.35)) 350
    $n=Read-Nodes | Where-Object {$_.text -eq $Tap -or $_.'content-desc' -eq $Tap} | Select-Object -First 1
}
if(!$n -or $n.bounds -notmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$'){throw "UI element missing: $Tap"}
$x=[int](([int]$Matches[1]+[int]$Matches[3])/2)
$y=[int](([int]$Matches[2]+[int]$Matches[4])/2)
& $Adb -s $Serial shell input tap $x $y
