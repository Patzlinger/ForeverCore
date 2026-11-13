# Erzeugt die kleinen Sprach-Flaggen fuer die Gruppensuche (ForeverHelpers\Languages.lua):
#   ForeverHelpers\Media\Flags\<Sprache>.tga  (deDE, enUS, frFR, esES, ruRU, ptBR)
# Je 64x32, 32 bit mit Alpha; die Flagge selbst fuellt links 48x32 (Seitenverhaeltnis 3:2), rechts transparent.
# Im Spiel wird nur dieser Teil gezeigt (TexCoord 0..0.75). Nach Aenderungen: Spiel komplett neu starten.
#   .\tools\make-flag-art.ps1                 (optional: $env:FLAG_PREVIEW = Ordner fuer PNG-Vorschau)
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$dir = Join-Path $root 'ForeverHelpers\Media\Flags'
New-Item -ItemType Directory -Force $dir | Out-Null
$W, $H, $FW = 64, 32, 48

function C($r, $g, $b) { [System.Drawing.Color]::FromArgb(255, $r, $g, $b) }
function Fill($g, $col, $x, $y, $w, $h) { $br = New-Object System.Drawing.SolidBrush $col; $g.FillRectangle($br, $x, $y, $w, $h); $br.Dispose() }
# (PowerShell unterscheidet keine Gross-/Kleinschreibung: Streifenmasse heissen darum $stripeH/$stripeW, nicht $h/$w)
function HStripes($g, $cols, $weights) {
    $sum = ($weights | Measure-Object -Sum).Sum; $top = 0.0
    for ($i = 0; $i -lt $cols.Count; $i++) {
        $stripeH = $H * $weights[$i] / $sum
        Fill $g $cols[$i] 0 $top $FW ($stripeH + 0.5)
        $top += $stripeH
    }
}
function VStripes($g, $cols) {
    $stripeW = $FW / $cols.Count
    for ($i = 0; $i -lt $cols.Count; $i++) { Fill $g $cols[$i] ($i * $stripeW) 0 ($stripeW + 0.5) $H }
}

$flags = [ordered]@{
    deDE = { param($g) HStripes $g @((C 0 0 0), (C 221 0 0), (C 255 206 0)) @(1, 1, 1) }
    frFR = { param($g) VStripes $g @((C 0 85 164), (C 255 255 255), (C 239 65 53)) }
    esES = { param($g) HStripes $g @((C 170 21 27), (C 241 191 0), (C 170 21 27)) @(1, 2, 1) }
    ruRU = { param($g) HStripes $g @((C 255 255 255), (C 0 57 166), (C 213 43 30)) @(1, 1, 1) }
    enUS = {
        param($g)
        $cols = for ($i = 0; $i -lt 13; $i++) { if ($i % 2 -eq 0) { C 178 34 52 } else { C 255 255 255 } }
        HStripes $g @($cols) @(1..13 | ForEach-Object { 1 })
        $cw, $ch = 21, [Math]::Round($H * 7 / 13)
        Fill $g (C 60 59 110) 0 0 $cw $ch
        $br = New-Object System.Drawing.SolidBrush (C 255 255 255)
        for ($row = 0; $row -lt 4; $row++) { for ($col = 0; $col -lt 5; $col++) {
            $g.FillRectangle($br, 2 + $col * 4 + ($row % 2) * 2, 2 + $row * 4, 1.4, 1.4) } }
        $br.Dispose()
    }
    ptBR = {
        param($g)
        Fill $g (C 0 156 59) 0 0 $FW $H
        $br = New-Object System.Drawing.SolidBrush (C 255 223 0)
        $pts = @((New-Object System.Drawing.PointF 4, 16), (New-Object System.Drawing.PointF 24, 3),
                 (New-Object System.Drawing.PointF 44, 16), (New-Object System.Drawing.PointF 24, 29))
        $g.FillPolygon($br, [System.Drawing.PointF[]]$pts); $br.Dispose()
        $br = New-Object System.Drawing.SolidBrush (C 0 39 118)
        $g.FillEllipse($br, 16.5, 8.5, 15, 15); $br.Dispose()
        $p = New-Object System.Drawing.Pen (C 255 255 255), 1.4
        $g.DrawArc($p, 14, 12, 21, 14, 200, 140); $p.Dispose()
    }
}

foreach ($name in $flags.Keys) {
    $bmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    & $flags[$name] $g
    # feiner dunkler Rand, damit helle Flaggen (Russland) auf dunklem Grund nicht ausfransen
    $p = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 0, 0, 0)), 1
    $g.SmoothingMode = 'None'
    $g.DrawRectangle($p, 0, 0, $FW - 1, $H - 1); $p.Dispose()
    $g.Dispose()
    # TGA: unkomprimiert, 32 bit, Ursprung oben links
    $out = Join-Path $dir "$name.tga"
    $fs = [System.IO.File]::Create($out)
    $hdr = New-Object byte[] 18
    $hdr[2] = 2; $hdr[12] = $W -band 255; $hdr[13] = $W -shr 8; $hdr[14] = $H -band 255; $hdr[15] = $H -shr 8; $hdr[16] = 32; $hdr[17] = 0x28
    $fs.Write($hdr, 0, 18)
    $buf = New-Object byte[] ($W * 4)
    for ($y = 0; $y -lt $H; $y++) {
        for ($x = 0; $x -lt $W; $x++) {
            $px = $bmp.GetPixel($x, $y); $i = $x * 4
            $buf[$i] = $px.B; $buf[$i + 1] = $px.G; $buf[$i + 2] = $px.R; $buf[$i + 3] = $px.A
        }
        $fs.Write($buf, 0, $buf.Length)
    }
    $fs.Close()
    if ($env:FLAG_PREVIEW) {
        $big = New-Object System.Drawing.Bitmap ($W * 4), ($H * 4)
        $g2 = [System.Drawing.Graphics]::FromImage($big); $g2.Clear((C 20 20 26))
        $g2.InterpolationMode = 'NearestNeighbor'; $g2.DrawImage($bmp, 0, 0, $W * 4, $H * 4); $g2.Dispose()
        $big.Save((Join-Path $env:FLAG_PREVIEW "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png); $big.Dispose()
    }
    $bmp.Dispose()
    Write-Host "geschrieben: $out"
}
