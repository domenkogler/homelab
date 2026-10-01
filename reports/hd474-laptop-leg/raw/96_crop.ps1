# 96_crop.ps1 — cut the untouched 8160x6120 rack photo into tiles, for the SKU question.
#
# WHY THIS EXISTS: the laptop vision leg answered CRS326-24G-2S+RM five times (three sampled, two
# greedy) where docs/network-rack.md U15 records CRS328-24P-4S+ behind a label photo. Open question:
# is that a PERCEPTION floor (the label is tiny inside an 8160x6120 frame, so the model guesses from
# the family) or a resolution artifact (the ViT grid simply never had the pixels)? A crop answers it,
# but a crop chosen by the model that is on trial is circular. So:
#
#   * a fixed 2x3 grid with overlap, chosen WITHOUT looking at the image: the model does not pick
#     where to look;
#   * tiles that do NOT contain the switch are negative controls — a confident CRS answer for a tile
#     with no label is confabulation, which is a stronger result than any reading;
#   * one DOWNSCALED full frame in the opposite direction, so "more pixels per label" is compared
#     against "fewer", not against nothing.
#
# No Pillow on this interpreter, so System.Drawing. ASCII-only source (PS 5.1 misparses BOM-less
# UTF-8), LF endings, JPEG quality pinned so tile bytes are comparable.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$raw = Join-Path $PSScriptRoot ''
$srcPath = Join-Path $raw 'original8160.jpg'
if (-not (Test-Path -LiteralPath $srcPath)) { throw "missing $srcPath" }

$src = [System.Drawing.Image]::FromFile($srcPath)
Write-Output ("source {0}x{1} from {2}" -f $src.Width, $src.Height, $srcPath)

$jpg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
       Where-Object { $_.MimeType -eq 'image/jpeg' }
$enc = New-Object System.Drawing.Imaging.EncoderParameters(1)
$enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
    [System.Drawing.Imaging.Encoder]::Quality, [long]88)

function Save-Crop([string]$name, [int]$x, [int]$y, [int]$w, [int]$h, [double]$scale) {
    $ow = [int][Math]::Round($w * $scale)
    $oh = [int][Math]::Round($h * $scale)
    $bmp = New-Object System.Drawing.Bitmap($ow, $oh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    # HighQualityBicubic: we are testing what the model can read, so do not let the resampler be
    # the weak link. Negative scale values are not used, so no edge-artifact param is needed.
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $dest = New-Object System.Drawing.Rectangle(0, 0, $ow, $oh)
    $srcRect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
    $g.DrawImage($src, $dest, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $out = Join-Path $raw $name
    $bmp.Save($out, $jpg, $enc)
    $bmp.Dispose()
    $len = (Get-Item -LiteralPath $out).Length
    Write-Output ("wrote {0}  crop=({1},{2})+{3}x{4}  out={5}x{6}  {7} bytes" -f `
        $name, $x, $y, $w, $h, $ow, $oh, $len)
}

# 2 rows x 3 cols, 3264x3672 each, stepping 2448 px on both axes (about 25 percent overlap, so a
# label never falls exactly on a cut and gets lost in both neighbours).
$w = 3264; $h = 3672
for ($r = 0; $r -lt 2; $r++) {
    for ($c = 0; $c -lt 3; $c++) {
        $x = [Math]::Min($c * 2448, $src.Width - $w)
        $y = [Math]::Min($r * 2448, $src.Height - $h)
        Save-Crop ("96-tile-r{0}c{1}.jpg" -f $r, $c) $x $y $w $h 1.0
    }
}

# Opposite direction: whole frame at one fifth, as a floor on "fewer pixels".
Save-Crop '96-full-fifth.jpg' 0 0 $src.Width $src.Height 0.2

$src.Dispose()
Write-Output 'DONE'
