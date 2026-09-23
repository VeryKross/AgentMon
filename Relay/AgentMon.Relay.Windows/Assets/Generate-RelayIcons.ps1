[CmdletBinding()]
param(
    [string]$OutputDirectory = $PSScriptRoot,
    [string]$PreviewPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$script:Ink = [System.Drawing.Color]::FromArgb(255, 11, 13, 11)
$script:Paper = [System.Drawing.Color]::FromArgb(255, 232, 230, 214)
$script:Desktop = [System.Drawing.Color]::FromArgb(255, 171, 171, 156)
$script:Sizes = @(16, 20, 24, 32, 48, 64, 256)

function Get-ScaledCoordinate {
    param([int]$Value, [int]$Size)

    return [Math]::Floor(($Value * $Size) / 32.0)
}

function Get-ScaledLength {
    param([int]$Value, [int]$Size)

    return [Math]::Max(1, [Math]::Round(($Value * $Size) / 32.0))
}

function New-ScaledRectangle {
    param(
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [int]$Size
    )

    return [System.Drawing.Rectangle]::new(
        (Get-ScaledCoordinate $X $Size),
        (Get-ScaledCoordinate $Y $Size),
        (Get-ScaledLength $Width $Size),
        (Get-ScaledLength $Height $Size))
}

function New-ScaledPoint {
    param([int]$X, [int]$Y, [int]$Size)

    return [System.Drawing.Point]::new(
        (Get-ScaledCoordinate $X $Size),
        (Get-ScaledCoordinate $Y $Size))
}

function Fill-ScaledRectangle {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Brush]$Brush,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [int]$Size
    )

    $Graphics.FillRectangle(
        $Brush,
        (New-ScaledRectangle $X $Y $Width $Height $Size))
}

function Draw-ConnectionMotif {
    param(
        [System.Drawing.Graphics]$Graphics,
        [System.Drawing.Brush]$InkBrush,
        [System.Drawing.Brush]$PaperBrush,
        [string]$State,
        [int]$Size
    )

    Fill-ScaledRectangle $Graphics $InkBrush 11 12 3 3 $Size
    Fill-ScaledRectangle $Graphics $InkBrush 19 12 3 3 $Size

    if ($State -eq 'Stopped') {
        Fill-ScaledRectangle $Graphics $PaperBrush 12 13 1 1 $Size
        Fill-ScaledRectangle $Graphics $PaperBrush 20 13 1 1 $Size
        return
    }

    if (($State -eq 'Base') -or ($State -eq 'Running')) {
        Fill-ScaledRectangle $Graphics $InkBrush 14 13 5 1 $Size
        Fill-ScaledRectangle $Graphics $InkBrush 16 12 1 3 $Size
        return
    }

    if ($State -eq 'Waiting') {
        Fill-ScaledRectangle $Graphics $InkBrush 14 13 1 1 $Size
        Fill-ScaledRectangle $Graphics $InkBrush 16 13 1 1 $Size
        Fill-ScaledRectangle $Graphics $InkBrush 18 13 1 1 $Size
        return
    }

    Fill-ScaledRectangle $Graphics $InkBrush 14 13 2 1 $Size
    Fill-ScaledRectangle $Graphics $InkBrush 18 13 1 1 $Size
    Fill-ScaledRectangle $Graphics $InkBrush 16 11 1 2 $Size
    Fill-ScaledRectangle $Graphics $InkBrush 16 14 1 2 $Size
}

function New-RelayBitmap {
    param([int]$Size, [string]$State)

    $bitmap = [System.Drawing.Bitmap]::new(
        $Size,
        $Size,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $inkBrush = [System.Drawing.SolidBrush]::new($script:Ink)
    $paperBrush = [System.Drawing.SolidBrush]::new($script:Paper)
    $desktopBrush = [System.Drawing.SolidBrush]::new($script:Desktop)

    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

        if ($Size -ge 32) {
            $tilePoints = [System.Drawing.Point[]]@(
                (New-ScaledPoint 3 0 $Size),
                (New-ScaledPoint 29 0 $Size),
                (New-ScaledPoint 32 3 $Size),
                (New-ScaledPoint 32 29 $Size),
                (New-ScaledPoint 29 32 $Size),
                (New-ScaledPoint 3 32 $Size),
                (New-ScaledPoint 0 29 $Size),
                (New-ScaledPoint 0 3 $Size))
            $graphics.FillPolygon($inkBrush, $tilePoints)

            $innerTilePoints = [System.Drawing.Point[]]@(
                (New-ScaledPoint 3 2 $Size),
                (New-ScaledPoint 28 2 $Size),
                (New-ScaledPoint 30 4 $Size),
                (New-ScaledPoint 30 28 $Size),
                (New-ScaledPoint 28 30 $Size),
                (New-ScaledPoint 4 30 $Size),
                (New-ScaledPoint 2 28 $Size),
                (New-ScaledPoint 2 4 $Size))
            $graphics.FillPolygon($desktopBrush, $innerTilePoints)

            for ($x = 3; $x -lt 29; $x += 4) {
                for ($y = 3; $y -lt 29; $y += 4) {
                    if ((($x + $y) % 8) -eq 0) {
                        Fill-ScaledRectangle $graphics $inkBrush $x $y 1 1 $Size
                    }
                }
            }
        }

        $bodyPoints = [System.Drawing.Point[]]@(
            (New-ScaledPoint 7 4 $Size),
            (New-ScaledPoint 25 4 $Size),
            (New-ScaledPoint 28 7 $Size),
            (New-ScaledPoint 28 27 $Size),
            (New-ScaledPoint 25 30 $Size),
            (New-ScaledPoint 7 30 $Size),
            (New-ScaledPoint 4 27 $Size),
            (New-ScaledPoint 4 7 $Size))
        if ($Size -ge 32) {
            $shadowPoints = [System.Drawing.Point[]]@(
                (New-ScaledPoint 8 5 $Size),
                (New-ScaledPoint 26 5 $Size),
                (New-ScaledPoint 29 8 $Size),
                (New-ScaledPoint 29 28 $Size),
                (New-ScaledPoint 26 31 $Size),
                (New-ScaledPoint 8 31 $Size),
                (New-ScaledPoint 5 28 $Size),
                (New-ScaledPoint 5 8 $Size))
            $graphics.FillPolygon($inkBrush, $shadowPoints)
        }
        $graphics.FillPolygon($inkBrush, $bodyPoints)

        $bodyInterior = [System.Drawing.Point[]]@(
            (New-ScaledPoint 8 6 $Size),
            (New-ScaledPoint 24 6 $Size),
            (New-ScaledPoint 26 8 $Size),
            (New-ScaledPoint 26 26 $Size),
            (New-ScaledPoint 24 28 $Size),
            (New-ScaledPoint 8 28 $Size),
            (New-ScaledPoint 6 26 $Size),
            (New-ScaledPoint 6 8 $Size))
        $graphics.FillPolygon($paperBrush, $bodyInterior)

        Fill-ScaledRectangle $graphics $inkBrush 8 8 16 10 $Size
        Fill-ScaledRectangle $graphics $paperBrush 9 9 14 8 $Size
        Draw-ConnectionMotif $graphics $inkBrush $paperBrush $State $Size
        Fill-ScaledRectangle $graphics $inkBrush 8 22 11 2 $Size
        Fill-ScaledRectangle $graphics $inkBrush 21 24 3 2 $Size

        return $bitmap
    }
    finally {
        $desktopBrush.Dispose()
        $paperBrush.Dispose()
        $inkBrush.Dispose()
        $graphics.Dispose()
    }
}

function Write-MultiResolutionIcon {
    param([string]$Path, [string]$State)

    $images = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($size in $script:Sizes) {
            $bitmap = New-RelayBitmap $size $State
            $stream = [System.IO.MemoryStream]::new()
            try {
                $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
                $images.Add([pscustomobject]@{
                    Size = $size
                    Bytes = $stream.ToArray()
                })
            }
            finally {
                $stream.Dispose()
                $bitmap.Dispose()
            }
        }

        $fileStream = [System.IO.File]::Create($Path)
        $writer = [System.IO.BinaryWriter]::new($fileStream)
        try {
            $writer.Write([uint16]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]$images.Count)

            $offset = 6 + (16 * $images.Count)
            foreach ($image in $images) {
                $dimension = if ($image.Size -eq 256) { 0 } else { $image.Size }
                $writer.Write([byte]$dimension)
                $writer.Write([byte]$dimension)
                $writer.Write([byte]0)
                $writer.Write([byte]0)
                $writer.Write([uint16]1)
                $writer.Write([uint16]32)
                $writer.Write([uint32]$image.Bytes.Length)
                $writer.Write([uint32]$offset)
                $offset += $image.Bytes.Length
            }

            foreach ($image in $images) {
                $writer.Write([byte[]]$image.Bytes)
            }
        }
        finally {
            $writer.Dispose()
            $fileStream.Dispose()
        }
    }
    finally {
        $images.Clear()
    }
}

function Write-Preview {
    param([string]$Path)

    $states = @('Stopped', 'Running', 'Waiting', 'Error')
    $sampleSizes = @(16, 32, 256)
    $canvas = [System.Drawing.Bitmap]::new(1500, 560)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $background = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 242, 241, 233))
    $inkBrush = [System.Drawing.SolidBrush]::new($script:Ink)
    $font = [System.Drawing.Font]::new('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
    $smallFont = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)

    try {
        $graphics.FillRectangle($background, 0, 0, $canvas.Width, $canvas.Height)
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
        for ($column = 0; $column -lt $states.Count; $column++) {
            $state = $states[$column]
            $left = 28 + ($column * 368)
            $graphics.DrawString($state, $font, $inkBrush, $left, 22)

            $x = $left
            foreach ($sampleSize in $sampleSizes[0..1]) {
                $bitmap = New-RelayBitmap $sampleSize $state
                try {
                    $graphics.DrawImageUnscaled($bitmap, $x, 66)
                    $graphics.DrawString(
                        "$($sampleSize) px",
                        $smallFont,
                        $inkBrush,
                        $x,
                        (78 + $sampleSize))
                    $x += $sampleSize + 24
                }
                finally {
                    $bitmap.Dispose()
                }
            }

            $largeBitmap = New-RelayBitmap $sampleSizes[2] $state
            try {
                $graphics.DrawImageUnscaled($largeBitmap, $left, 132)
                $graphics.DrawString('256 px', $smallFont, $inkBrush, $left, 398)
            }
            finally {
                $largeBitmap.Dispose()
            }
        }

        $canvas.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $smallFont.Dispose()
        $font.Dispose()
        $inkBrush.Dispose()
        $background.Dispose()
        $graphics.Dispose()
        $canvas.Dispose()
    }
}

[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
Write-MultiResolutionIcon (Join-Path $OutputDirectory 'AgentMonRelay.ico') 'Base'
Write-MultiResolutionIcon (Join-Path $OutputDirectory 'AgentMonRelay.Stopped.ico') 'Stopped'
Write-MultiResolutionIcon (Join-Path $OutputDirectory 'AgentMonRelay.Running.ico') 'Running'
Write-MultiResolutionIcon (Join-Path $OutputDirectory 'AgentMonRelay.Waiting.ico') 'Waiting'
Write-MultiResolutionIcon (Join-Path $OutputDirectory 'AgentMonRelay.Error.ico') 'Error'

if ($PreviewPath) {
    $previewDirectory = Split-Path -Parent $PreviewPath
    if ($previewDirectory) {
        [System.IO.Directory]::CreateDirectory($previewDirectory) | Out-Null
    }
    Write-Preview $PreviewPath
}
