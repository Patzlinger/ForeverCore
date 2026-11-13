# Erzeugt die Grafik fuer das Runen-Design (Prototyp): ForeverCoreUI\Media\ThemeRunes.tga
# 512x512, 32 bit mit Alpha, goldene Linien auf transparentem Grund (Deckkraft stellt Theme.lua ein).
#   .\tools\make-theme-art.ps1
# Zum Entfernen des Prototyps diese Datei mit loeschen.
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$out = Join-Path $root 'ForeverCoreUI\Media\ThemeRunes.tga'
$S = 512
$bmp = New-Object System.Drawing.Bitmap $S, $S, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)
$gold = [System.Drawing.Color]::FromArgb(255, 222, 176, 70)
function Pen($w, $a = 255) { New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($a, 222, 176, 70)), $w }
$c = $S / 2

function Ring($r, $w, $a = 255) { $p = Pen $w $a; $g.DrawEllipse($p, $c - $r, $c - $r, 2 * $r, 2 * $r); $p.Dispose() }
Ring 252 2.5
Ring 240 1.2
Ring 206 1.2 200
Ring 160 1.5
Ring 112 1.2 220
Ring 64 2

# Strichmarken zwischen den beiden aeusseren Ringen
$p = Pen 1.2
for ($d = 0; $d -lt 360; $d += 5) {
    $long = ($d % 30 -eq 0)
    $r1 = 240; $r2 = if ($long) { 226 } else { 233 }
    $a = [Math]::PI * $d / 180
    $g.DrawLine($p, $c + $r1 * [Math]::Cos($a), $c + $r1 * [Math]::Sin($a), $c + $r2 * [Math]::Cos($a), $c + $r2 * [Math]::Sin($a))
}
$p.Dispose()

# Rauten (Runenzeichen) auf dem mittleren Ring, alle 30 Grad
$fill = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 222, 176, 70))
for ($d = 15; $d -lt 360; $d += 30) {
    $a = [Math]::PI * $d / 180
    $cx = $c + 183 * [Math]::Cos($a); $cy = $c + 183 * [Math]::Sin($a)
    $pts = @(
        (New-Object System.Drawing.PointF ($cx + 9 * [Math]::Cos($a)), ($cy + 9 * [Math]::Sin($a))),
        (New-Object System.Drawing.PointF ($cx - 5 * [Math]::Sin($a)), ($cy + 5 * [Math]::Cos($a))),
        (New-Object System.Drawing.PointF ($cx - 9 * [Math]::Cos($a)), ($cy - 9 * [Math]::Sin($a))),
        (New-Object System.Drawing.PointF ($cx + 5 * [Math]::Sin($a)), ($cy - 5 * [Math]::Cos($a)))
    )
    $g.FillPolygon($fill, $pts)
}
$fill.Dispose()

# Sechsstern aus zwei Dreiecken (Radius 150) und ein Quadrat im Inneren
$p = Pen 1.5 230
foreach ($rot in 0, 60) {
    $pts = foreach ($k in 0..2) { $a = [Math]::PI * ($rot - 90 + 120 * $k) / 180; New-Object System.Drawing.PointF ($c + 160 * [Math]::Cos($a)), ($c + 160 * [Math]::Sin($a)) }
    $g.DrawPolygon($p, [System.Drawing.PointF[]]$pts)
}
$pts = foreach ($k in 0..3) { $a = [Math]::PI * (45 + 90 * $k) / 180; New-Object System.Drawing.PointF ($c + 112 * [Math]::Cos($a)), ($c + 112 * [Math]::Sin($a)) }
$g.DrawPolygon($p, [System.Drawing.PointF[]]$pts)
$p.Dispose()

# kleine Kreise an den Zacken des Sterns
$p = Pen 1.2
for ($d = 0; $d -lt 360; $d += 60) {
    $a = [Math]::PI * ($d - 90) / 180
    $g.DrawEllipse($p, $c + 160 * [Math]::Cos($a) - 7, $c + 160 * [Math]::Sin($a) - 7, 14, 14)
}
$p.Dispose()
$g.Dispose()

# TGA schreiben: unkomprimiert, 32 bit, Ursprung oben links
$fs = [System.IO.File]::Create($out)
$hdr = New-Object byte[] 18
$hdr[2] = 2; $hdr[12] = $S -band 255; $hdr[13] = $S -shr 8; $hdr[14] = $S -band 255; $hdr[15] = $S -shr 8; $hdr[16] = 32; $hdr[17] = 0x28
$fs.Write($hdr, 0, 18)
$buf = New-Object byte[] ($S * 4)
for ($y = 0; $y -lt $S; $y++) {
    for ($x = 0; $x -lt $S; $x++) {
        $px = $bmp.GetPixel($x, $y)
        $i = $x * 4
        $buf[$i] = $px.B; $buf[$i + 1] = $px.G; $buf[$i + 2] = $px.R; $buf[$i + 3] = $px.A
    }
    $fs.Write($buf, 0, $buf.Length)
}
$fs.Close()
if ($env:THEME_PREVIEW) { $bk = New-Object System.Drawing.Bitmap $S, $S; $g2 = [System.Drawing.Graphics]::FromImage($bk); $g2.Clear([System.Drawing.Color]::FromArgb(255, 14, 22, 44)); $g2.DrawImage($bmp, 0, 0); $bk.Save($env:THEME_PREVIEW, [System.Drawing.Imaging.ImageFormat]::Png) }
$bmp.Dispose()
Write-Host "geschrieben: $out"
