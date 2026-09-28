$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path $PSScriptRoot -Parent
$iconPath = Join-Path $root 'app/HateVPN.Desktop/Assets/HateVPN.ico'
$previewPath = Join-Path $root 'artifacts/HateVPN-icon-1.0.png'

function New-Point([single]$x, [single]$y) { return [System.Drawing.PointF]::new($x, $y) }
function New-RoundedPath([single]$x, [single]$y, [single]$width, [single]$height, [single]$radius) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = $radius * 2
    $path.AddArc($x, $y, $diameter, $diameter, 180, 90)
    $path.AddArc($x + $width - $diameter, $y, $diameter, $diameter, 270, 90)
    $path.AddArc($x + $width - $diameter, $y + $height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($x, $y + $height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-IconPng([int]$size) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.ScaleTransform($size / 256.0, $size / 256.0)

        $rounded = New-RoundedPath 10 10 236 236 51
        $top = [System.Drawing.Point]::new(0, 10)
        $bottom = [System.Drawing.Point]::new(0, 246)
        $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new($top, $bottom,
            [System.Drawing.ColorTranslator]::FromHtml('#232B32'), [System.Drawing.ColorTranslator]::FromHtml('#080B0E'))
        $outline = [System.Drawing.Pen]::new([System.Drawing.ColorTranslator]::FromHtml('#5C6871'), 3)
        $mark = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#F1F5F7'))
        $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(100, 0, 0, 0))
        try {
            $graphics.FillPath($background, $rounded)
            $graphics.DrawPath($outline, $rounded)
            $left = [System.Drawing.PointF[]]@((New-Point 63 50), (New-Point 103 50), (New-Point 78 206), (New-Point 38 206))
            $right = [System.Drawing.PointF[]]@((New-Point 167 50), (New-Point 207 50), (New-Point 182 206), (New-Point 142 206))
            $bridge = [System.Drawing.PointF[]]@((New-Point 81 111), (New-Point 175 111), (New-Point 168 145), (New-Point 74 145))
            $graphics.TranslateTransform(0, 4)
            $graphics.FillPolygon($shadow, $left); $graphics.FillPolygon($shadow, $right); $graphics.FillPolygon($shadow, $bridge)
            $graphics.TranslateTransform(0, -4)
            $graphics.FillPolygon($mark, $left); $graphics.FillPolygon($mark, $right); $graphics.FillPolygon($mark, $bridge)
        }
        finally { $rounded.Dispose(); $background.Dispose(); $outline.Dispose(); $mark.Dispose(); $shadow.Dispose() }

        $stream = [System.IO.MemoryStream]::new()
        try { $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png); return ,$stream.ToArray() }
        finally { $stream.Dispose() }
    }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = @($sizes | ForEach-Object { New-IconPng $_ })
$output = [System.IO.File]::Create($iconPath)
$writer = [System.IO.BinaryWriter]::new($output)
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($index = 0; $index -lt $sizes.Count; $index++) {
        $size = $sizes[$index]
        $writer.Write([byte]($size % 256)); $writer.Write([byte]($size % 256))
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$images[$index].Length); $writer.Write([uint32]$offset)
        $offset += $images[$index].Length
    }
    foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
}
finally { $writer.Dispose() }
[System.IO.File]::WriteAllBytes($previewPath, [byte[]]$images[-1])
Write-Output "Created $iconPath"
