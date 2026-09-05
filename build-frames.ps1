<#
  build-frames.ps1 - convierte los videos en las secuencias de frames que usa index.html.
  USO:  .\build-frames.ps1 -Desktop "video-desktop.mp4" -Mobile "video-movil.mp4"
        .\build-frames.ps1 -Desktop "video-desktop.mp4" -RecortarMovil
  Resultado: frames/desktop/, frames/mobile/, poster.jpg
#>
param(
  [Parameter(Mandatory = $true)][string]$Desktop,
  [string]$Mobile,
  [switch]$RecortarMovil,
  [int]$FramesDesktop = 240,
  [int]$FramesMobile  = 120,
  [int]$AltoDesktop   = 1440,
  [int]$AltoMobile    = 1600,
  [int]$Calidad       = 78,
  [switch]$SinLimpiar
)

$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot

function Buscar($nombre) {
  $c = Get-Command $nombre -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $p = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg*" -Recurse -Filter "$nombre.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($p) { return $p.FullName }
  throw "No se encontro $nombre. Instala ffmpeg:  winget install Gyan.FFmpeg"
}
$ffmpeg  = Buscar ffmpeg
$ffprobe = Buscar ffprobe
Write-Host "ffmpeg:  $ffmpeg" -ForegroundColor DarkGray

function Duracion($archivo) {
  [double](& $ffprobe -v error -show_entries format=duration -of "csv=p=0" -- "$archivo")
}

function Generar($video, $carpeta, $nFrames, $alto, $recortar) {
  $video = (Resolve-Path -- $video).Path
  $destino = Join-Path $raiz $carpeta
  New-Item -ItemType Directory -Force -Path $destino | Out-Null
  if (-not $SinLimpiar) {
    Get-ChildItem $destino -Filter "frame_*.webp" -ErrorAction SilentlyContinue | Remove-Item -Force
  }
  $dur = Duracion $video
  if ($dur -le 0) { throw "No pude leer la duracion de $video" }
  $fps = [math]::Round($nFrames / $dur, 4)
  Write-Host ""
  Write-Host "== $carpeta ==" -ForegroundColor Cyan
  Write-Host ("   fuente {0}  |  duracion {1:N2}s  |  fps {2}  |  objetivo {3} frames  |  alto {4}px" -f (Split-Path $video -Leaf), $dur, $fps, $nFrames, $alto)

  # Recorte central a 9:16 cuando se reaprovecha el clip horizontal para movil.
  $crop = ""
  # Sin comas dentro de la expresion: la coma separa filtros en el filtergraph.
  if ($recortar) { $crop = "crop=ih*9/16:ih," }

  $vf = "${crop}hqdn3d=1.5:1.2:3:3,fps=$fps,scale=-2:${alto}:flags=lanczos,unsharp=5:5:0.9:5:5:0.0"
  & $ffmpeg -hide_banner -loglevel error -y -i "$video" `
    -vf $vf -fps_mode passthrough `
    -c:v libwebp -q:v $Calidad -compression_level 6 -preset picture `
    -- (Join-Path $destino "frame_%04d.webp")
  if ($LASTEXITCODE -ne 0) { throw "ffmpeg fallo en $carpeta" }
  $frames = Get-ChildItem $destino -Filter "frame_*.webp" | Sort-Object Name
  if ($frames.Count -gt $nFrames) {
    $frames | Select-Object -Skip $nFrames | Remove-Item -Force
    $frames = Get-ChildItem $destino -Filter "frame_*.webp" | Sort-Object Name
  }
  $peso = ($frames | Measure-Object Length -Sum).Sum / 1MB
  $color = if ($frames.Count -eq $nFrames) { 'Green' } else { 'Yellow' }
  Write-Host ("   -> {0} frames  |  {1:N1} MB" -f $frames.Count, $peso) -ForegroundColor $color
  if ($frames.Count -ne $nFrames) {
    Write-Host ("   AJUSTA index.html: pon el numero real de frames en HERO ({0})." -f $frames.Count) -ForegroundColor Yellow
  }
}

function Poster($video) {
  $video = (Resolve-Path -- $video).Path
  $dur = Duracion $video
  $t = [math]::Round($dur * 0.18, 3)
  & $ffmpeg -hide_banner -loglevel error -y -ss $t -i "$video" `
    -frames:v 1 -vf "scale=-2:1400:flags=lanczos,unsharp=5:5:0.5" -q:v 3 `
    -- (Join-Path $raiz "poster.jpg")
  if ($LASTEXITCODE -eq 0) {
    $kb = (Get-Item (Join-Path $raiz "poster.jpg")).Length / 1KB
    Write-Host ("poster.jpg  |  {0:N0} KB  (segundo {1})" -f $kb, $t) -ForegroundColor Green
  }
}

Generar $Desktop "frames/desktop" $FramesDesktop $AltoDesktop $false
Poster  $Desktop
if ($Mobile) {
  Generar $Mobile "frames/mobile" $FramesMobile $AltoMobile $false
} elseif ($RecortarMovil) {
  Write-Host ""
  Write-Host "Sin clip vertical: se genera la version movil recortando el centro del horizontal a 9:16." -ForegroundColor Yellow
  Generar $Desktop "frames/mobile" $FramesMobile $AltoMobile $true
} else {
  Write-Host ""
  Write-Host "Sin -Mobile: en telefonos se recorta la version desktop. Recomendado pasar el clip 9:16." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Listo. Abre index.html para revisar." -ForegroundColor Green
