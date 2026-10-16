# Kopiert Shared\ForeverHub.lua in jedes Forever-Addon (alle Ordner mit ForeverHub.lua in der .toc).
# Nach jeder Änderung an Shared\ForeverHub.lua ausführen.
$root = Split-Path $PSScriptRoot -Parent
$hub  = Join-Path $root 'Shared\ForeverHub.lua'

Get-ChildItem $root -Directory | ForEach-Object {
    $toc = Join-Path $_.FullName ($_.Name + '.toc')
    if ((Test-Path $toc) -and (Select-String -Path $toc -Pattern '^ForeverHub\.lua' -Quiet)) {
        $dest = Join-Path $_.FullName 'ForeverHub.lua'
        if (!(Test-Path $dest) -or (Get-FileHash $dest).Hash -ne (Get-FileHash $hub).Hash) {
            Copy-Item $hub $dest -Force
            Write-Host "Hub aktualisiert: $($_.Name)"
        }
    }
}
