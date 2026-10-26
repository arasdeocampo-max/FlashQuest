# Run from PowerShell: .\tool\generate_launcher_icons.ps1
# Requires the existing Flutter SDK and Windows System.Drawing, plus the
# project's flutter_launcher_icons dev dependency. The source PNG is never edited.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets/icon/flash-card.png'
$legacyPath = Join-Path $projectRoot 'assets/icon/flash-card-launcher.png'
$sourceImage = [System.Drawing.Bitmap]::new($sourcePath)
$legacyImage = $null
try {
    # Copy at original resolution, with equal transparent margins. No recoloring,
    # stretching or cropping occurs before flutter_launcher_icons resizes it.
    $canvasSize = [int][Math]::Ceiling([Math]::Max($sourceImage.Width, $sourceImage.Height) * 1.25)
    $legacyImage = [System.Drawing.Bitmap]::new(
        $canvasSize, $canvasSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $left = [int][Math]::Floor(($canvasSize - $sourceImage.Width) / 2)
    $top = [int][Math]::Floor(($canvasSize - $sourceImage.Height) / 2)
    # Copy straight ARGB values instead of drawing through GDI+, which can
    # round partially transparent edge colors during premultiplication.
    for ($y = 0; $y -lt $sourceImage.Height; $y++) {
        for ($x = 0; $x -lt $sourceImage.Width; $x++) {
            $legacyImage.SetPixel($left + $x, $top + $y, $sourceImage.GetPixel($x, $y))
        }
    }
    $legacyImage.Save($legacyPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    if ($null -ne $legacyImage) { $legacyImage.Dispose() }
    $sourceImage.Dispose()
}

Push-Location -LiteralPath $projectRoot
try {
    # Launcher assets only; native startup uses its own small vector resource.
    & dart run flutter_launcher_icons
    if ($LASTEXITCODE -ne 0) { throw 'Android launcher icon generation failed.' }
} finally {
    Pop-Location
}
