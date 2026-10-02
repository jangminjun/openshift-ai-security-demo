# Renders a Mermaid (.mmd) file to PNG with headless Edge, so diagrams show
# up in any Markdown viewer (VS Code preview does not render Mermaid).
# Usage: .\harness\render-diagram.ps1 <input.mmd> <output.png> [width] [height]
param(
  [Parameter(Mandatory)] [string] $In,
  [Parameter(Mandatory)] [string] $Out,
  [int] $Width = 1600,
  [int] $Height = 900
)
$ErrorActionPreference = 'Stop'
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$src = [System.Net.WebUtility]::HtmlEncode((Get-Content -Raw -Encoding UTF8 $In))
$html = Join-Path $env:TEMP ("diagram-" + [guid]::NewGuid() + ".html")
@"
<!doctype html><html><head><meta charset="utf-8">
<style>body{margin:0;background:#fff;font-family:'Malgun Gothic',sans-serif}.mermaid{padding:16px}</style>
<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>mermaid.initialize({startOnLoad:true,theme:'default',themeVariables:{fontSize:'22px'},flowchart:{htmlLabels:true,nodeSpacing:40,rankSpacing:70}});</script>
</head><body><pre class="mermaid">$src</pre></body></html>
"@ | Set-Content -Encoding UTF8 $html
# Resolve against the PowerShell location, not the .NET process directory.
$outFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
# msedge.exe returns before the screenshot is written, so wait on the
# process; a separate profile keeps it apart from any open Edge window.
$edgeProfile = Join-Path $env:TEMP ("diagram-edge-" + [guid]::NewGuid())
if (Test-Path $outFull) { Remove-Item $outFull }
$edgeArgs = @('--headless=new', '--disable-gpu', '--hide-scrollbars', "--user-data-dir=`"$edgeProfile`"",
  "--window-size=$Width,$Height", '--virtual-time-budget=10000', "--screenshot=`"$outFull`"",
  "file:///$($html -replace '\\','/')")
Start-Process -FilePath $edge -ArgumentList $edgeArgs -Wait -WindowStyle Hidden
Remove-Item $html
Remove-Item -Recurse -Force $edgeProfile -ErrorAction SilentlyContinue
if (-not (Test-Path $outFull)) { throw "Edge did not write $outFull" }

# Trim the white margin around the drawing.
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile($outFull)
$minX = $bmp.Width; $minY = $bmp.Height; $maxX = 0; $maxY = 0
for ($y = 0; $y -lt $bmp.Height; $y += 2) {
  for ($x = 0; $x -lt $bmp.Width; $x += 2) {
    $p = $bmp.GetPixel($x, $y)
    if ($p.R -lt 245 -or $p.G -lt 245 -or $p.B -lt 245) {
      if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
      if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
    }
  }
}
$pad = 16
$minX = [Math]::Max(0, $minX - $pad); $minY = [Math]::Max(0, $minY - $pad)
$maxX = [Math]::Min($bmp.Width - 1, $maxX + $pad); $maxY = [Math]::Min($bmp.Height - 1, $maxY + $pad)
$crop = $bmp.Clone((New-Object System.Drawing.Rectangle $minX, $minY, ($maxX - $minX + 1), ($maxY - $minY + 1)), $bmp.PixelFormat)
$bmp.Dispose()
$crop.Save($outFull, [System.Drawing.Imaging.ImageFormat]::Png)
$crop.Dispose()
Write-Output "Saved $outFull"
