param(
    [string[]]$ChangedPaths = @(),
    [string]$BaseRef = '',
    [string]$HeadRef = 'HEAD',
    [string]$PushLocalSha = '',
    [string]$PushRemoteSha = '',
    [switch]$UseStagedFiles
)

$ErrorActionPreference = 'Stop'

function ConvertTo-NormalizedPath {
    param([string]$PathText)

    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return ''
    }

    return (($PathText.Trim().Trim('"')) -replace '\\', '/')
}

function Get-NormalizedChangedPaths {
    if ($ChangedPaths.Count -gt 0) {
        return @(
            $ChangedPaths |
                ForEach-Object { ConvertTo-NormalizedPath $_ } |
                Where-Object { $_ -ne '' } |
                Sort-Object -Unique
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($PushLocalSha)) {
        if ([string]::IsNullOrWhiteSpace($PushRemoteSha) -or $PushRemoteSha -eq ('0' * 40)) {
            $rawPaths = @(git -c core.quotepath=false diff-tree --no-commit-id --name-only -r --root $PushLocalSha)
        }
        else {
            $rawPaths = @(git -c core.quotepath=false diff --name-only $PushRemoteSha $PushLocalSha)
        }

        return @(
            $rawPaths |
                ForEach-Object { ConvertTo-NormalizedPath $_ } |
                Where-Object { $_ -ne '' } |
                Sort-Object -Unique
        )
    }

    if ($UseStagedFiles) {
        return @(
            @(git -c core.quotepath=false diff --cached --name-only) |
                ForEach-Object { ConvertTo-NormalizedPath $_ } |
                Where-Object { $_ -ne '' } |
                Sort-Object -Unique
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($BaseRef)) {
        return @(
            @(git -c core.quotepath=false diff --name-only $BaseRef $HeadRef) |
                ForEach-Object { ConvertTo-NormalizedPath $_ } |
                Where-Object { $_ -ne '' } |
                Sort-Object -Unique
        )
    }

    throw '必须提供 ChangedPaths、PushLocalSha、UseStagedFiles 或 BaseRef 中的一种输入。'
}

function Test-PathStartsWithAnyPrefix {
    param(
        [string]$TargetPath,
        [string[]]$Prefixes
    )

    foreach ($prefixText in $Prefixes) {
        if ($TargetPath.StartsWith($prefixText)) {
            return $true
        }
    }

    return $false
}

function Get-CanonicalExecStandardDocNames {
    $execDocPaths = @(
        @(git -c core.quotepath=false ls-files -- 'docs/40-执行/*.md') |
            ForEach-Object { ConvertTo-NormalizedPath $_ } |
            Where-Object { $_ -match '^docs/40-执行/[0-9]{2}-.+\.md$' }
    )

    return @(
        $execDocPaths |
            ForEach-Object { Split-Path $_ -Leaf } |
            Sort-Object -Unique
    )
}

function Get-MatchedExecStandardDocNamesFromFile {
    param(
        [string]$FilePath,
        [string]$RegexPattern
    )

    if (-not (Test-Path $FilePath)) {
        return @()
    }

    $fileContent = Get-Content $FilePath -Raw
    return @(
        [regex]::Matches($fileContent, $RegexPattern) |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
    )
}

function Get-MatchedNormalizedDocPathsFromFile {
    param(
        [string]$FilePath,
        [string]$RegexPattern,
        [string]$PathPrefix = ''
    )

    if (-not (Test-Path $FilePath)) {
        return @()
    }

    $fileContent = Get-Content $FilePath -Raw
    return @(
        [regex]::Matches($fileContent, $RegexPattern) |
            ForEach-Object {
                $capturedPath = ConvertTo-NormalizedPath $_.Groups[1].Value
                if ($PathPrefix -ne '') {
                    ConvertTo-NormalizedPath ($PathPrefix + $capturedPath)
                }
                else {
                    $capturedPath
                }
            } |
            Sort-Object -Unique
    )
}

function Get-OrderedNormalizedDocPathsFromFile {
    param(
        [string]$FilePath,
        [string]$RegexPattern,
        [string]$PathPrefix = ''
    )

    if (-not (Test-Path $FilePath)) {
        return @()
    }

    $fileContent = Get-Content $FilePath -Raw
    return @(
        [regex]::Matches($fileContent, $RegexPattern) |
            ForEach-Object {
                $capturedPath = ConvertTo-NormalizedPath $_.Groups[1].Value
                if ($PathPrefix -ne '') {
                    ConvertTo-NormalizedPath ($PathPrefix + $capturedPath)
                }
                else {
                    $capturedPath
                }
            } |
            Where-Object { $_ -ne '' }
    )
}

function Get-FileSectionContent {
    param(
        [string]$FilePath,
        [string]$SectionStartMarker,
        [string]$SectionEndMarker = ''
    )

    if (-not (Test-Path $FilePath)) {
        return ''
    }

    $fileContent = Get-Content $FilePath -Raw
    $sectionStartIndex = $fileContent.IndexOf($SectionStartMarker)
    if ($sectionStartIndex -lt 0) {
        return ''
    }

    $sectionContent = $fileContent.Substring($sectionStartIndex + $SectionStartMarker.Length)
    if (-not [string]::IsNullOrWhiteSpace($SectionEndMarker)) {
        $sectionEndIndex = $sectionContent.IndexOf($SectionEndMarker)
        if ($sectionEndIndex -ge 0) {
            $sectionContent = $sectionContent.Substring(0, $sectionEndIndex)
        }
    }

    return $sectionContent
}

function Get-OrderedNormalizedDocPathsFromSection {
    param(
        [string]$FilePath,
        [string]$RegexPattern,
        [string]$PathPrefix = '',
        [string]$SectionStartMarker,
        [string]$SectionEndMarker = ''
    )

    $sectionContent = Get-FileSectionContent -FilePath $FilePath -SectionStartMarker $SectionStartMarker -SectionEndMarker $SectionEndMarker
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        return @()
    }

    return @(
        [regex]::Matches($sectionContent, $RegexPattern) |
            ForEach-Object {
                $capturedPath = ConvertTo-NormalizedPath $_.Groups[1].Value
                if ($PathPrefix -ne '') {
                    ConvertTo-NormalizedPath ($PathPrefix + $capturedPath)
                }
                else {
                    $capturedPath
                }
            } |
            Where-Object { $_ -ne '' }
    )
}

function Get-OrderedUniqueValues {
    param([string[]]$Values)

    $seenValues = New-Object 'System.Collections.Generic.HashSet[string]'
    $orderedUniqueValues = New-Object System.Collections.Generic.List[string]
    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        if ($seenValues.Add($value)) {
            $orderedUniqueValues.Add($value)
        }
    }

    return @($orderedUniqueValues)
}

function Get-OrderedPathSlice {
    param(
        [string[]]$SourcePaths,
        [string]$StartPath,
        [string]$EndPath,
        [string]$SliceLabel = '有序路径片段'
    )

    $orderedSlice = New-Object System.Collections.Generic.List[string]
    $hasStarted = $false
    $hasEnded = $false
    foreach ($sourcePath in $SourcePaths) {
        if (-not $hasStarted) {
            if ($sourcePath -ne $StartPath) {
                continue
            }

            $hasStarted = $true
        }

        $orderedSlice.Add($sourcePath)
        if ($sourcePath -eq $EndPath) {
            $hasEnded = $true
            break
        }
    }

    if (-not $hasStarted) {
        throw "$SliceLabel 缺少起始路径：$StartPath"
    }

    if (-not $hasEnded) {
        throw "$SliceLabel 缺少结束路径或结束路径出现在起始路径之前：$EndPath"
    }

    return @($orderedSlice)
}

function Get-OrderedEntryViolationMessages {
    param(
        [object[]]$EntryChecks,
        [string[]]$CriticalEntryPaths,
        [string]$MissingFileLabel,
        [string]$MissingEntryLabel,
        [string]$OrderDriftLabel
    )

    $entryViolationMessages = New-Object System.Collections.Generic.List[string]
    $expectedOrderText = @(
        $CriticalEntryPaths |
            ForEach-Object { Split-Path $_ -Leaf }
    ) -join ' → '

    foreach ($entryCheck in $EntryChecks) {
        if (-not (Test-Path $entryCheck.Path)) {
            $entryViolationMessages.Add("缺少$MissingFileLabel：$($entryCheck.Path)")
            continue
        }

        if ($entryCheck.ContainsKey('SectionStartMarker')) {
            $orderedMatchedPaths = Get-OrderedNormalizedDocPathsFromSection -FilePath $entryCheck.Path -RegexPattern $entryCheck.RegexPattern -PathPrefix $entryCheck.PathPrefix -SectionStartMarker $entryCheck.SectionStartMarker -SectionEndMarker $entryCheck.SectionEndMarker
        }
        else {
            $orderedMatchedPaths = Get-OrderedNormalizedDocPathsFromFile -FilePath $entryCheck.Path -RegexPattern $entryCheck.RegexPattern -PathPrefix $entryCheck.PathPrefix
        }

        $actualEntryPaths = Get-OrderedUniqueValues -Values @(
            $orderedMatchedPaths |
                Where-Object { $_ -in $CriticalEntryPaths }
        )
        $missingEntryPaths = @(
            $CriticalEntryPaths |
                Where-Object { $_ -notin $actualEntryPaths }
        )

        if ($missingEntryPaths.Count -gt 0) {
            $entryViolationMessages.Add("$($entryCheck.Label) 缺少$MissingEntryLabel：$($missingEntryPaths -join '、')")
            continue
        }

        $hasOrderDrift = $false
        for ($index = 0; $index -lt $CriticalEntryPaths.Count; $index++) {
            if ($actualEntryPaths[$index] -ne $CriticalEntryPaths[$index]) {
                $hasOrderDrift = $true
                break
            }
        }

        if ($hasOrderDrift) {
            $actualOrderText = @(
                $actualEntryPaths |
                    ForEach-Object { Split-Path $_ -Leaf }
            ) -join ' → '
            $entryViolationMessages.Add("$($entryCheck.Label) $OrderDriftLabel：期望 $expectedOrderText；实际 $actualOrderText")
        }
    }

    return @($entryViolationMessages)
}

$requiredPolicyFiles = @(
    'docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md',
    'docs/reference/02-仓库卫生与命名规范.md',
    'docs/30-方案/02-V4-目录锁定清单.md',
    'docs/30-方案/08-V4-治理审计候选规范.md',
    'docs/40-执行/10-本地安全提交流程.md',
    'docs/40-执行/14-维护层动作矩阵与收口检查表.md',
    'docs/40-执行/21-关键配置来源与漂移复核模板.md'
)
$allowedTrackedRootEntries = @(
    '.codex',
    'docs',
    'logs',
    'temp',
    'README.md',
    'AGENTS.md',
    '.gitignore'
)
$allowedTrackedCodexFiles = @(
    '.codex/chancellor/README.md',
    '.codex/chancellor/create-gate-package.ps1',
    '.codex/chancellor/create-task-package.ps1',
    '.codex/chancellor/install-public-commit-governance-hook.ps1',
    '.codex/chancellor/invoke-public-commit-governance-gate.ps1',
    '.codex/chancellor/record-exception-state.ps1',
    '.codex/chancellor/resolve-gate-package.ps1',
    '.codex/chancellor/tasks/README.md',
    '.codex/chancellor/test-public-commit-governance-gate.ps1',
    '.codex/chancellor/write-concurrent-status-report.ps1',
    '.codex/chancellor/write-governance-config-review.ps1'
)
$blockedExactPaths = @(
    '.codex/chancellor/active-task.txt'
)
$blockedPrefixes = @(
    '.codex/chancellor/tasks/',
    'logs/',
    'temp/generated/',
    '.vscode/',
    '.serena/'
)
$blockedPrefixExceptions = @(
    'logs/README.md',
    'temp/generated/README.md'
)
$publicExecEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 公开入口'
        RegexPattern = 'docs/40-执行/([0-9]{2}-[^`]+\.md)'
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 公开入口'
        RegexPattern = '40-执行/([0-9]{2}-[^`]+\.md)'
    },
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览'
        RegexPattern = 'docs/40-执行/([0-9]{2}-[^`]+\.md)'
    },
    @{
        Path = 'docs/40-执行/README.md'
        Label = '执行区 README'
        RegexPattern = '(?m)^- `([0-9]{2}-[^`]+\.md)`\r?$'
    }
)
$criticalPublicRuleEntryPaths = @(
    'docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md',
    'docs/reference/02-仓库卫生与命名规范.md',
    'docs/30-方案/02-V4-目录锁定清单.md',
    'docs/30-方案/08-V4-治理审计候选规范.md',
    'docs/40-执行/10-本地安全提交流程.md',
    'docs/40-执行/14-维护层动作矩阵与收口检查表.md',
    'docs/40-执行/21-关键配置来源与漂移复核模板.md'
)
$publicRuleEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 规则入口'
        RegexPattern = '`(docs/(?:reference|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 规则入口'
        RegexPattern = '`((?:reference|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = 'docs/'
    },
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览规则入口'
        RegexPattern = '`(docs/(?:reference|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = ''
    }
)
$precomputedViolationMessages = New-Object System.Collections.Generic.List[string]
$navOverviewReadingOrderPaths = Get-OrderedUniqueValues -Values @(
    Get-OrderedNormalizedDocPathsFromSection -FilePath 'docs/00-导航/02-现行标准件总览.md' -RegexPattern '`(docs/(?:20-决策|30-方案|40-执行)/[^`]+\.md)`' -PathPrefix '' -SectionStartMarker '## 阅读顺序建议' -SectionEndMarker '## 什么不是现行标准件'
)
$criticalTargetLifecycleEntryPaths = @()
try {
    $criticalTargetLifecycleEntryPaths = Get-OrderedPathSlice -SourcePaths $navOverviewReadingOrderPaths -StartPath 'docs/20-决策/02-V4-Target-进入决议.md' -EndPath 'docs/40-执行/12-V4-Target-实施计划.md' -SliceLabel '现行总览阅读顺序 Target 主线'
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$publicTargetEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README Target 主线入口'
        RegexPattern = '`(docs/(?:20-决策|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README Target 主线入口'
        RegexPattern = '`((?:20-决策|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = 'docs/'
    },
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览 Target 主线入口'
        RegexPattern = '`(docs/(?:20-决策|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = ''
    }
)
$criticalMaintenanceLifecycleEntryPaths = @()
try {
    $criticalMaintenanceLifecycleEntryPaths = Get-OrderedPathSlice -SourcePaths $navOverviewReadingOrderPaths -StartPath 'docs/40-执行/13-维护层总入口.md' -EndPath 'docs/40-执行/21-关键配置来源与漂移复核模板.md' -SliceLabel '现行总览阅读顺序维护层主线'
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$publicMaintenanceEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 维护层主线入口'
        RegexPattern = '`(docs/40-执行/[^`]+\.md)`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 维护层主线入口'
        RegexPattern = '`(40-执行/[^`]+\.md)`'
        PathPrefix = 'docs/'
    },
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览维护层主线入口'
        RegexPattern = '`(docs/40-执行/[^`]+\.md)`'
        PathPrefix = ''
    }
)
$readingOrderTargetEntryChecks = @(
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行总览阅读顺序 Target 主线'
        RegexPattern = '`(docs/(?:20-决策|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = ''
        SectionStartMarker = '## 阅读顺序建议'
        SectionEndMarker = '## 什么不是现行标准件'
    }
)
$readingOrderMaintenanceEntryChecks = @(
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行总览阅读顺序维护层主线'
        RegexPattern = '`(docs/40-执行/[^`]+\.md)`'
        PathPrefix = ''
        SectionStartMarker = '## 阅读顺序建议'
        SectionEndMarker = '## 什么不是现行标准件'
    }
)
$restartGuideCanonicalEntryPaths = Get-OrderedUniqueValues -Values @(
    Get-OrderedNormalizedDocPathsFromSection -FilePath 'docs/00-导航/01-V4-重启导读.md' -RegexPattern '`(docs/[^`]+\.md)`' -PathPrefix '' -SectionStartMarker '## 先看什么' -SectionEndMarker '## '
)
$publicRestartGuideEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 重启导读核心入口'
        RegexPattern = '`(docs/(?:00-导航|10-输入材料|20-决策|30-方案|40-执行|reference)/[^`]+\.md)`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 重启导读核心入口'
        RegexPattern = '`((?:00-导航|10-输入材料|20-决策|30-方案|40-执行|reference)/[^`]+\.md)`'
        PathPrefix = 'docs/'
    }
)
$startupPhaseBoundaryPath = 'docs/30-方案/03-V4-MVP边界清单.md'
$criticalStartupPhaseEntryPaths = New-Object System.Collections.Generic.List[string]
$criticalStartupPhaseEntryPaths.Add('docs/00-导航/02-现行标准件总览.md')
$criticalStartupPhaseEntryPaths.Add('docs/00-导航/01-V4-重启导读.md')
foreach ($restartGuideEntryPath in $restartGuideCanonicalEntryPaths) {
    if ($restartGuideEntryPath -eq 'docs/00-导航/02-现行标准件总览.md') {
        continue
    }

    if ($restartGuideEntryPath -notin $criticalStartupPhaseEntryPaths) {
        $criticalStartupPhaseEntryPaths.Add($restartGuideEntryPath)
    }

    if ($restartGuideEntryPath -eq $startupPhaseBoundaryPath) {
        break
    }
}
$publicStartupPhaseEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 启动阶段入口'
        RegexPattern = '`(docs/(?:00-导航|10-输入材料|20-决策|30-方案)/[^`]+\.md)`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 启动阶段入口'
        RegexPattern = '`((?:00-导航|10-输入材料|20-决策|30-方案)/[^`]+\.md)`'
        PathPrefix = 'docs/'
    }
)

$changedPathList = Get-NormalizedChangedPaths
if ($changedPathList.Count -eq 0) {
    Write-Host 'PASS: 未检测到需要校验的改动路径。'
    exit 0
}

$violationMessages = New-Object System.Collections.Generic.List[string]
foreach ($precomputedViolationMessage in $precomputedViolationMessages) {
    $violationMessages.Add($precomputedViolationMessage)
}
foreach ($policyFilePath in $requiredPolicyFiles) {
    if (-not (Test-Path $policyFilePath)) {
        $violationMessages.Add("缺少必需规则文件：$policyFilePath")
    }
}

foreach ($changedPath in $changedPathList) {
    if ($changedPath -in $blockedExactPaths) {
        $violationMessages.Add("禁止把本地运行态文件带入公开提交：$changedPath")
        continue
    }

    if ((Test-PathStartsWithAnyPrefix -TargetPath $changedPath -Prefixes $blockedPrefixes) -and ($changedPath -notin $blockedPrefixExceptions)) {
        $violationMessages.Add("禁止把运行态或本地工具状态带入公开提交：$changedPath")
    }
}

$trackedPathList = @(
    @(git -c core.quotepath=false ls-files) |
        ForEach-Object { ConvertTo-NormalizedPath $_ } |
        Where-Object { $_ -ne '' }
)
$trackedRootEntries = @(
    $trackedPathList |
        ForEach-Object {
            if ($_.Contains('/')) {
                $_.Split('/')[0]
            }
            else {
                $_
            }
        } |
        Sort-Object -Unique
)
$unexpectedTrackedRootEntries = @(
    $trackedRootEntries |
        Where-Object { $_ -notin $allowedTrackedRootEntries }
)
foreach ($unexpectedTrackedRootEntry in $unexpectedTrackedRootEntries) {
    $violationMessages.Add("发现未批准的跟踪顶层项：$unexpectedTrackedRootEntry")
}

$trackedCodexFiles = @(
    $trackedPathList |
        Where-Object { $_.StartsWith('.codex/') }
)
$unexpectedTrackedCodexFiles = @(
    $trackedCodexFiles |
        Where-Object { $_ -notin $allowedTrackedCodexFiles }
)
foreach ($unexpectedTrackedCodexFile in $unexpectedTrackedCodexFiles) {
    $violationMessages.Add("发现未列入白名单的 .codex 跟踪文件：$unexpectedTrackedCodexFile")
}

$canonicalExecStandardDocNames = Get-CanonicalExecStandardDocNames
foreach ($entryCheck in $publicExecEntryChecks) {
    if (-not (Test-Path $entryCheck.Path)) {
        $violationMessages.Add("缺少公开入口文件：$($entryCheck.Path)")
        continue
    }

    $actualExecDocNames = Get-MatchedExecStandardDocNamesFromFile -FilePath $entryCheck.Path -RegexPattern $entryCheck.RegexPattern
    $missingExecDocNames = @(
        $canonicalExecStandardDocNames |
            Where-Object { $_ -notin $actualExecDocNames }
    )
    $extraExecDocNames = @(
        $actualExecDocNames |
            Where-Object { $_ -notin $canonicalExecStandardDocNames }
    )

    if ($missingExecDocNames.Count -gt 0) {
        $violationMessages.Add("$($entryCheck.Label) 缺少执行区现行标准件入口：$($missingExecDocNames -join '、')")
    }

    if ($extraExecDocNames.Count -gt 0) {
        $violationMessages.Add("$($entryCheck.Label) 存在未受控的执行区入口：$($extraExecDocNames -join '、')")
    }
}

foreach ($ruleEntryCheck in $publicRuleEntryChecks) {
    if (-not (Test-Path $ruleEntryCheck.Path)) {
        $violationMessages.Add("缺少规则入口文件：$($ruleEntryCheck.Path)")
        continue
    }

    $actualRuleEntryPaths = Get-MatchedNormalizedDocPathsFromFile -FilePath $ruleEntryCheck.Path -RegexPattern $ruleEntryCheck.RegexPattern -PathPrefix $ruleEntryCheck.PathPrefix
    $missingRuleEntryPaths = @(
        $criticalPublicRuleEntryPaths |
            Where-Object { $_ -notin $actualRuleEntryPaths }
    )

    if ($missingRuleEntryPaths.Count -gt 0) {
        $violationMessages.Add("$($ruleEntryCheck.Label) 缺少关键规则入口：$($missingRuleEntryPaths -join '、')")
    }
}
foreach ($restartGuideEntryCheck in $publicRestartGuideEntryChecks) {
    if (-not (Test-Path $restartGuideEntryCheck.Path)) {
        $violationMessages.Add("缺少重启导读核心入口文件：$($restartGuideEntryCheck.Path)")
        continue
    }

    $actualRestartGuideEntryPaths = Get-MatchedNormalizedDocPathsFromFile -FilePath $restartGuideEntryCheck.Path -RegexPattern $restartGuideEntryCheck.RegexPattern -PathPrefix $restartGuideEntryCheck.PathPrefix
    $missingRestartGuideEntryPaths = @(
        $restartGuideCanonicalEntryPaths |
            Where-Object { $_ -notin $actualRestartGuideEntryPaths }
    )

    if ($missingRestartGuideEntryPaths.Count -gt 0) {
        $violationMessages.Add("$($restartGuideEntryCheck.Label) 缺少重启导读核心入口：$($missingRestartGuideEntryPaths -join '、')")
    }
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $publicStartupPhaseEntryChecks -CriticalEntryPaths $criticalStartupPhaseEntryPaths -MissingFileLabel '启动阶段入口文件' -MissingEntryLabel '启动阶段关键入口' -OrderDriftLabel '启动阶段入口顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
}

foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $publicTargetEntryChecks -CriticalEntryPaths $criticalTargetLifecycleEntryPaths -MissingFileLabel 'Target 主线入口文件' -MissingEntryLabel '关键主线入口' -OrderDriftLabel '关键主线入口顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $publicMaintenanceEntryChecks -CriticalEntryPaths $criticalMaintenanceLifecycleEntryPaths -MissingFileLabel '维护层主线入口文件' -MissingEntryLabel '维护层关键入口' -OrderDriftLabel '维护层关键入口顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $readingOrderTargetEntryChecks -CriticalEntryPaths $criticalTargetLifecycleEntryPaths -MissingFileLabel '阅读顺序区文件' -MissingEntryLabel '阅读顺序关键入口' -OrderDriftLabel '阅读顺序建议顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $readingOrderMaintenanceEntryChecks -CriticalEntryPaths $criticalMaintenanceLifecycleEntryPaths -MissingFileLabel '阅读顺序区文件' -MissingEntryLabel '阅读顺序关键入口' -OrderDriftLabel '阅读顺序建议顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
}

if ($violationMessages.Count -gt 0) {
    Write-Host 'FAIL: 公开提交治理门禁未通过。'
    foreach ($violationMessage in $violationMessages) {
        Write-Host ('- ' + $violationMessage)
    }

    exit 1
}

Write-Host 'PASS: 公开提交治理门禁通过。'
Write-Host ('- 已校验路径数：' + $changedPathList.Count)
Write-Host ('- 校验路径：' + ($changedPathList -join ', '))
exit 0
