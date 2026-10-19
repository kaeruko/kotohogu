#requires -Version 5.1
<#
.SYNOPSIS
  assets/characters にある複数の4x4スプライトシートを一括分割します。
.DESCRIPTION
  ファイル名が「3桁の番号_英小文字名.png」に一致する直下のPNGを処理します。
  *_source.png と *_sheet_4x4.png は生成物・保存用素材として除外します。
  各画像の分割処理・透過検証は Split-KotohoguSprites.ps1 に委譲します。
  既存の出力は上書きせず、エラー時はその場で停止します。
.EXAMPLE
  .\Split-KotohoguSpritesBatch.ps1 -SkipExisting
.EXAMPLE
  .\Split-KotohoguSpritesBatch.ps1 -SkipExisting -WhatIf
.EXAMPLE
  .\Split-KotohoguSpritesBatch.ps1 -InputDirectory 'C:\sprites' -OutputRoot 'C:\output'
.NOTES
  ImageMagick 7 の magick コマンドが必要です。
  -SkipExisting は完成済みの出力フォルダがある場合にスキップします。
  ファイル一覧を検証し、欠損がある場合は停止します。
  ZIPファイルは生成しません。既存のZIPは変更しません。
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [string] $InputDirectory = $PSScriptRoot,

    [Parameter()]
    [string] $OutputRoot = $PSScriptRoot,

    [Parameter()]
    [switch] $SkipExisting
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$splitter = Join-Path $PSScriptRoot 'Split-KotohoguSprites.ps1'
if (-not (Test-Path -LiteralPath $splitter -PathType Leaf)) {
    throw "分割スクリプトがありません: $splitter"
}

$inputItem = Get-Item -LiteralPath $InputDirectory -ErrorAction Stop
if (-not $inputItem.PSIsContainer) {
    throw "入力先はフォルダで指定してください: $InputDirectory"
}
$outputItem = Get-Item -LiteralPath $OutputRoot -ErrorAction Stop
if (-not $outputItem.PSIsContainer) {
    throw "出力先はフォルダで指定してください: $OutputRoot"
}

$inputs = @(
    Get-ChildItem -LiteralPath $inputItem.FullName -File -Filter '*.png' -ErrorAction Stop |
        Where-Object {
            $_.BaseName -cmatch '^[0-9]{3}_[a-z][a-z0-9_]*$' -and
            $_.BaseName -cnotmatch '(_source|_sheet_4x4)$'
        } |
        Sort-Object Name
)
if ($inputs.Count -eq 0) {
    throw "対象PNGがありません。必要な名前形式: 014_construction_worker.png (入力先: $($inputItem.FullName))"
}

# -SkipExisting でスキップする前に、元スクリプトが生成する成果物がそろっているか検証する。
# 既存フォルダが不完全な場合は暗黙にやり直したり無視したりせず停止する。
function Assert-CompleteSpriteOutput {
    param(
        [Parameter(Mandatory = $true)][string] $Directory,
        [Parameter(Mandatory = $true)][string] $Name
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        throw "既存の出力先がフォルダではありません: $Directory"
    }

    $required = @(
        'README.txt',
        'idle_front_01.png',
        'clap_front_01.png',
        'clap_front_02.png',
        "${Name}_sheet_4x4.png",
        'preview_walk_front.gif',
        'preview_walk_back.gif',
        'preview_walk_right.gif',
        'preview_clap.gif'
    )
    foreach ($direction in @('front', 'back', 'right', 'left')) {
        for ($frame = 1; $frame -le 4; $frame++) {
            $required += ("walk_${direction}_{0:D2}.png" -f $frame)
        }
    }

    foreach ($fileName in $required) {
        $filePath = Join-Path $Directory $fileName
        if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
            throw "既存の出力フォルダに必要なファイルがありません: $filePath"
        }
        $file = Get-Item -LiteralPath $filePath -ErrorAction Stop
        if ($file.Length -eq 0) {
            throw "既存の出力ファイルが空です: $filePath"
        }
    }
    $actualPngs = @(Get-ChildItem -LiteralPath $Directory -Filter '*.png' -File)
    if ($actualPngs.Count -ne 20) {
        throw "既存の出力PNGの数が想定外です: $Directory (expected=20, actual=$($actualPngs.Count))"
    }
}

# 全入力について出力先の衝突を先に調べてから処理を開始する。
$pending = @()
$skipped = 0
foreach ($inputPng in $inputs) {
    $name = $inputPng.BaseName
    $outDir = Join-Path $outputItem.FullName $name
    if (Test-Path -LiteralPath $outDir) {
        if ($SkipExisting) {
            Assert-CompleteSpriteOutput -Directory $outDir -Name $name
            Write-Host "スキップ（出力済み）: $name"
            $skipped++
            continue
        }

        throw "出力先が既に存在します: $outDir。-SkipExisting は完成済みフォルダのみスキップできます。"
    }
    $pending += $inputPng
}

if ($pending.Count -gt 0) {
    Get-Command 'magick' -ErrorAction Stop | Out-Null
}

$completed = 0
foreach ($inputPng in $pending) {
    $name = $inputPng.BaseName
    if ($PSCmdlet.ShouldProcess($inputPng.FullName, "分割・GIF生成 ($name)")) {
        Write-Host "処理中: $($inputPng.Name)"
        & $splitter -InputPng $inputPng.FullName -Name $name -OutputRoot $outputItem.FullName
        $completed++
    }
}
Write-Host "一括処理終了: 対象=$($inputs.Count)、完了=$completed、スキップ=$skipped"
