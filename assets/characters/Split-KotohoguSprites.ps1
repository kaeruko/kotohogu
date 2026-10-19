#requires -Version 5.1
<#
.SYNOPSIS
  コトホグの4x4スプライトシート(PNG)を個別PNG/GIFに変換します。
.EXAMPLE
  .\Split-KotohoguSprites.ps1 -InputPng 'C:\Users\mail\Downloads\cat.png' -Name '004_neko'
.NOTES
  ImageMagick 7 の magick コマンドが必要です。
  レイアウト: 1行目=前歩行×4、2行目=後歩行×4、3行目=右歩行×4、
  4行目=待機×1・拍手×2・空欄×1。
  ノイズ除去や他のマスにはみ出したキャラの自動修復はしません。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $InputPng,
    [Parameter()]
    [string] $Name,
    [Parameter()]
    [string] $OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Magick {
    param([Parameter(Mandatory = $true)][string[]] $Arguments)
    & $script:MagickExe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick failed (exit=$LASTEXITCODE): magick $($Arguments -join ' ')"
    }
}

# 依存コマンド・入力を事前検証
$magickCommand = Get-Command 'magick' -ErrorAction Stop
$script:MagickExe = $magickCommand.Source
$inputFile = Get-Item -LiteralPath $InputPng -ErrorAction Stop
if ($inputFile.PSIsContainer -or $inputFile.Extension -ine '.png') {
    throw "入力はPNGファイルで指定してください: $InputPng"
}
$source = $inputFile.FullName

if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $inputFile.BaseName }
if ($Name -match '[\\/:*?"<>|]' -or $Name -eq '.' -or $Name -eq '..') {
    throw "出力名に使用できない文字が含まれています: $Name"
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = $inputFile.DirectoryName }
$outputBase = [System.IO.Path]::GetFullPath($OutputRoot)
if (-not (Test-Path -LiteralPath $outputBase -PathType Container)) {
    throw "出力先フォルダがありません: $outputBase"
}
$outDir = Join-Path $outputBase "${Name}"
if (Test-Path -LiteralPath $outDir) {
    throw "同名の出力フォルダが既にあります。上書きせず停止します: $outDir"
}

# アルファチャンネルとサイズを確認（1254pxなど4で割れない寸法も対応）
$meta = & $script:MagickExe identify -format '%m|%w|%h|%[channels]|%[opaque]' $source
if ($LASTEXITCODE -ne 0) { throw "ImageMagick identify failed (exit=$LASTEXITCODE): $source" }
$parts = ($meta -join '').Trim() -split '\|'
if ($parts.Count -ne 5 -or $parts[0] -cne 'PNG') {
    throw "PNGのメタデータ取得に失敗しました: $meta"
}
$width = [int]::Parse($parts[1], [System.Globalization.CultureInfo]::InvariantCulture)
$height = [int]::Parse($parts[2], [System.Globalization.CultureInfo]::InvariantCulture)
if ($width -ne $height -or $width -lt 400) {
    throw "4x4の正方形スプライトシートを指定してください。実際: ${width}x${height}"
}
if ($parts[3] -notmatch 'a' -or $parts[4] -ne 'False') {
    throw "透過PNGではありません (channels=$($parts[3]), opaque=$($parts[4]))。背景を透過させてから実行してください。"
}

New-Item -ItemType Directory -Path $outDir -ErrorAction Stop | Out-Null

# 行優先（左から右、上から下）の名前付け
$names = @(
    'walk_front_01', 'walk_front_02', 'walk_front_03', 'walk_front_04',
    'walk_back_01', 'walk_back_02', 'walk_back_03', 'walk_back_04',
    'walk_right_01', 'walk_right_02', 'walk_right_03', 'walk_right_04',
    'idle_front_01', 'clap_front_01', 'clap_front_02'
)

# 端数を含む4x4をピクセル境界で16分割。隙間・重複を作らない。
for ($index = 0; $index -lt 15; $index++) {
    $row = [int][math]::Floor($index / 4)
    $col = $index % 4
    $x1 = [int][math]::Floor($width * $col / 4)
    $x2 = [int][math]::Floor($width * ($col + 1) / 4)
    $y1 = [int][math]::Floor($height * $row / 4)
    $y2 = [int][math]::Floor($height * ($row + 1) / 4)
    $tileW = $x2 - $x1
    $tileH = $y2 - $y1
    $geometry = "${tileW}x${tileH}+${x1}+${y1}"
    $path = Join-Path $outDir ($names[$index] + '.png')

    Invoke-Magick -Arguments @(
        $source, '-crop', $geometry, '+repage',
        '-resize', '288x288', '-background', 'none',
        '-gravity', 'center', '-extent', '288x288', $path
    )
}

# 左向きは右向きから左右反転
for ($i = 1; $i -le 4; $i++) {
    $number = '{0:D2}' -f $i
    $right = Join-Path $outDir "walk_right_${number}.png"
    $left  = Join-Path $outDir "walk_left_${number}.png"
    Invoke-Magick -Arguments @($right, '-flop', $left)
}

# PNG 15コマを4x4のシートに再配置（最後は透明セル）
$blank = Join-Path $outDir '__blank_for_sheet.png'
Invoke-Magick -Arguments @('-size', '288x288', 'xc:none', $blank)
$sheetInputs = @()
foreach ($n in $names) { $sheetInputs += (Join-Path $outDir ($n + '.png')) }
$sheetInputs += $blank
$sheet = Join-Path $outDir "${Name}_sheet_4x4.png"
Invoke-Magick -Arguments (@('montage') + $sheetInputs + @(
    '-tile', '4x4', '-geometry', '288x288+0+0', '-background', 'none', $sheet
))
Remove-Item -LiteralPath $blank -ErrorAction Stop

# GIF（歩行=0.18秒/コマ、拍手=0.25秒/コマ）
$animations = @(
    @{ Prefix = 'walk_front'; Count = 4; Delay = '18' },
    @{ Prefix = 'walk_back';  Count = 4; Delay = '18' },
    @{ Prefix = 'walk_right'; Count = 4; Delay = '18' },
    @{ Prefix = 'clap_front'; Count = 2; Delay = '25' }
)
foreach ($animation in $animations) {
    $framePaths = @()
    for ($i = 1; $i -le $animation.Count; $i++) {
        $number = '{0:D2}' -f $i
        $framePaths += (Join-Path $outDir "$($animation.Prefix)_${number}.png")
    }
    $gifBase = if ($animation.Prefix -eq 'clap_front') { 'preview_clap.gif' } else { "preview_$($animation.Prefix).gif" }
    $gif = Join-Path $outDir $gifBase
    Invoke-Magick -Arguments (@('-delay', $animation.Delay, '-dispose', 'background') + $framePaths + @('-loop', '0', $gif))
}

@"
Kotohogu sprite package: $Name
Source: $($inputFile.Name)
Source size: ${width}x${height}
Output PNG: 288x288 pixels, transparent

walk_front_01..04: front walk
walk_back_01..04: back walk
walk_right_01..04: right walk
walk_left_01..04: horizontal flips of right walk
idle_front_01: idle
clap_front_01..02: clap
${Name}_sheet_4x4.png: 4x4 sprite sheet
preview_*.gif: animation previews

IMPORTANT:
Pure equal-grid crop/resizing only. This script does not remove noise or
reconstruct characters overlapping another grid cell.
Inspect the preview before adding assets to the app.
"@ | Set-Content -LiteralPath (Join-Path $outDir 'README.txt') -Encoding UTF8

# 期待するPNGの個数・寸法を検証
$pngs = @(Get-ChildItem -LiteralPath $outDir -Filter '*.png' -File)
if ($pngs.Count -ne 20) {
    throw "PNGファイル数が想定外です。expected=20, actual=$($pngs.Count), output=$outDir"
}
foreach ($png in $pngs) {
    $dimension = (& $script:MagickExe identify -format '%wx%h' $png.FullName) -join ''
    if ($LASTEXITCODE -ne 0 -or $dimension -ne $(if ($png.Name -eq "${Name}_sheet_4x4.png") { '1152x1152' } else { '288x288' })) {
        throw "画像サイズ検証失敗: $($png.FullName) (actual=$dimension, exit=$LASTEXITCODE)"
    }
}

Write-Host "完了（個別PNG/GIF）: $outDir"
Write-Host "注意: キャラのはみ出しとノイズは自動修正しません。必ずプレビューを確認してください。"
