# Richtet den automatischen Abgleich ein (Windows-Aufgabe "Forever Core Abgleich" für den angemeldeten Benutzer,
# keine Admin-Rechte nötig): alle 5 Minuten tools\auto-sync.ps1, unsichtbar (ohne aufblitzendes Fenster).
#   .\tools\auto-sync-install.ps1            -> einrichten (oder neu einrichten)
#   .\tools\auto-sync-install.ps1 -Remove    -> wieder entfernen
param([switch]$Remove, [int]$Minutes = 5)
$name = 'Forever Core Abgleich'
if ($Remove) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Aufgabe '$name' entfernt"
    exit 0
}
$script = Join-Path $PSScriptRoot 'auto-sync.ps1'
# wscript startet PowerShell ohne Fenster (powershell -WindowStyle Hidden blitzt kurz auf)
$vbs = Join-Path $PSScriptRoot 'auto-sync-hidden.vbs'
Set-Content $vbs ('CreateObject("WScript.Shell").Run "pwsh.exe -NoProfile -ExecutionPolicy Bypass -File ""' + $script + '""", 0, True') -Encoding ASCII
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $vbs + '"')
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger, $logon -Settings $settings `
    -Description 'Holt alle paar Minuten den neuen Stand von Forever Core (GitHub, Zweig development) und verknüpft neue Addons.' -Force | Out-Null
Write-Host "Aufgabe '$name' eingerichtet: alle $Minutes Minuten (Protokoll: .git\forever-auto-sync.log)"
