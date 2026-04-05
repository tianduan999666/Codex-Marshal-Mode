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
    $execReadmePath = 'docs/40-执行/README.md'
    $sectionContent = Get-FileSectionContent -FilePath $execReadmePath -SectionStartMarker '当前现行标准件：' -SectionEndMarker '带时间戳的文件默认视为过程稿或证据稿，不自动等同于现行标准件。'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区 README 现行标准件区块缺失：$execReadmePath"
    }

    $execDocNames = Get-OrderedUniqueValues -Values @(
        [regex]::Matches($sectionContent, '`([0-9]{2}-[^`]+\.md)`') |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -ne '' }
    )

    if ($execDocNames.Count -eq 0) {
        throw "执行区 README 现行标准件区块未解析到标准件：$execReadmePath"
    }

    $execStandardOrderDocNames = @(
        '11-任务包半自动起包.md'
        '12-V4-Target-实施计划.md'
    )
    $execStandardOrderSlice = @(
        $execDocNames |
            Where-Object { $_ -in $execStandardOrderDocNames }
    )
    if ($execStandardOrderSlice.Count -eq $execStandardOrderDocNames.Count) {
        Assert-ExactOrderedValues -SourceValues $execStandardOrderSlice -ExpectedValues $execStandardOrderDocNames -Label '执行区现行标准件真源'
    }
    return $execDocNames
}

function Get-CanonicalExecReadmeTitleLine {
    $execReadmePath = 'docs/40-执行/README.md'
    $expectedExecReadmeTitleLine = '# 40-执行 目录说明'

    if (-not (Test-Path $execReadmePath)) {
        throw "缺少执行区 README：$execReadmePath"
    }

    $nonEmptyLines = @(
        Get-Content $execReadmePath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($nonEmptyLines.Count -eq 0) {
        throw "执行区 README 为空：$execReadmePath"
    }

    $actualExecReadmeTitleLine = $nonEmptyLines[0]
    Assert-ExactOrderedValues -SourceValues @($actualExecReadmeTitleLine) -ExpectedValues @($expectedExecReadmeTitleLine) -Label '执行区 README 标题'
    return $expectedExecReadmeTitleLine
}

function Get-CanonicalExecReadmeTopSummaryItems {
    $execReadmePath = 'docs/40-执行/README.md'
    $expectedExecReadmeTopSummaryItems = @(
        '试运行计划'
        '任务清单'
        '执行记录'
        '验收单'
    )

    $sectionContent = Get-FileSectionContent -FilePath $execReadmePath -SectionStartMarker '这里放：' -SectionEndMarker '当前现行标准件：'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区 README 顶部用途摘要区块缺失：$execReadmePath"
    }

    $topSummaryItems = Get-OrderedUniqueValues -Values @(
        [regex]::Matches($sectionContent, '(?m)^- (.+?)\r?$') |
            ForEach-Object { $_.Groups[1].Value.Trim() } |
            Where-Object { $_ -ne '' }
    )
    Assert-ExactOrderedValues -SourceValues $topSummaryItems -ExpectedValues $expectedExecReadmeTopSummaryItems -Label '执行区 README 顶部用途摘要序列'
    return $expectedExecReadmeTopSummaryItems
}

function Get-CanonicalExecReadmeFooterNoteItems {
    $execReadmePath = 'docs/40-执行/README.md'
    $expectedExecReadmeFooterNoteItems = @(
        '本区块是执行区现行标准件真源；公开入口同步与提交门禁均以此为准。'
        '带时间戳的文件默认视为过程稿或证据稿，不自动等同于现行标准件。'
        '具体区分与使用顺序见：`04-执行区现行件与证据稿说明.md`'
        '已完成归档规则见：`docs/90-归档/01-执行区证据稿归档规则.md`'
    )

    $sectionContent = Get-FileSectionContent -FilePath $execReadmePath -SectionStartMarker '本区块是执行区现行标准件真源；公开入口同步与提交门禁均以此为准。'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区 README 底部真源说明区块缺失：$execReadmePath"
    }

    $footerNoteItems = @(
        '本区块是执行区现行标准件真源；公开入口同步与提交门禁均以此为准。'
        ($sectionContent -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    Assert-ExactOrderedValues -SourceValues $footerNoteItems -ExpectedValues $expectedExecReadmeFooterNoteItems -Label '执行区 README 底部真源说明序列'
    return $expectedExecReadmeFooterNoteItems
}

function Get-CanonicalExecStandardGuideConclusionLine {
    $execStandardGuidePath = 'docs/40-执行/04-执行区现行件与证据稿说明.md'
    $expectedExecStandardGuideConclusionLine = '在 `docs/40-执行/` 下，固定编号文件是现行标准件，带时间戳的文件默认是证据稿或过程稿。'

    $sectionContent = Get-FileSectionContent -FilePath $execStandardGuidePath -SectionStartMarker '## 一句话结论' -SectionEndMarker '## 现行标准件'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区现行件说明一句话结论区块缺失：$execStandardGuidePath"
    }

    $summaryLines = @(
        ($sectionContent -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($summaryLines.Count -eq 0) {
        throw "执行区现行件说明一句话结论为空：$execStandardGuidePath"
    }

    $actualExecStandardGuideConclusionLine = $summaryLines[0]
    Assert-ExactOrderedValues -SourceValues @($actualExecStandardGuideConclusionLine) -ExpectedValues @($expectedExecStandardGuideConclusionLine) -Label '执行区现行件说明一句话结论'
    return $expectedExecStandardGuideConclusionLine
}

function Get-CanonicalExecStandardGuideEvidenceDraftItems {
    $execStandardGuidePath = 'docs/40-执行/04-执行区现行件与证据稿说明.md'
    $expectedExecStandardGuideEvidenceDraftItems = @(
        '带时间戳的执行文档'
        '某轮推进中的提炼稿、冻结稿、过程说明稿'
        '仅用于还原当时判断过程的阶段性文档'
    )

    $sectionContent = Get-FileSectionContent -FilePath $execStandardGuidePath -SectionStartMarker '## 证据稿与过程稿' -SectionEndMarker '## 使用顺序'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区现行件说明未解析到证据稿与过程稿：$execStandardGuidePath"
    }

    $evidenceDraftItems = @(
        [regex]::Matches($sectionContent, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($evidenceDraftItems.Count -eq 0) {
        throw "执行区现行件说明未解析到证据稿与过程稿列点：$execStandardGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $evidenceDraftItems -ExpectedValues $expectedExecStandardGuideEvidenceDraftItems -Label '执行区现行件说明证据稿与过程稿摘要序列'
    return $expectedExecStandardGuideEvidenceDraftItems
}

function Get-CanonicalExecStandardGuideUsageOrderItems {
    $execStandardGuidePath = 'docs/40-执行/04-执行区现行件与证据稿说明.md'
    $expectedExecStandardGuideUsageOrderItems = @(
        '先读 `01-任务包规范.md`'
        '再读 `02-任务包模板.md`'
        '进入试跑前读 `03-面板入口验收.md`'
        '需要追溯历史判断时，再看时间戳证据稿'
    )

    $sectionContent = Get-FileSectionContent -FilePath $execStandardGuidePath -SectionStartMarker '## 使用顺序' -SectionEndMarker '## 命名与维护规则'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区现行件说明未解析到使用顺序：$execStandardGuidePath"
    }

    $usageOrderItems = @(
        [regex]::Matches($sectionContent, '(?m)^\d+\. (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($usageOrderItems.Count -eq 0) {
        throw "执行区现行件说明未解析到使用顺序列点：$execStandardGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $usageOrderItems -ExpectedValues $expectedExecStandardGuideUsageOrderItems -Label '执行区现行件说明使用顺序摘要序列'
    return $expectedExecStandardGuideUsageOrderItems
}

function Get-CanonicalExecStandardGuideNamingRuleItems {
    $execStandardGuidePath = 'docs/40-执行/04-执行区现行件与证据稿说明.md'
    $expectedExecStandardGuideNamingRuleItems = @(
        '新增现行标准件时，优先使用固定编号文件名，再补本文件中的列表'
        '新增带时间戳的过程稿时，不得默认视为现行标准件'
        '若固定编号文件与时间戳稿出现差异，以固定编号文件为准'
        '若某份时间戳稿已失去参考价值，应转入 `docs/90-归档/` 而不是继续留在执行区长期混放'
    )

    $sectionContent = Get-FileSectionContent -FilePath $execStandardGuidePath -SectionStartMarker '## 命名与维护规则' -SectionEndMarker '## 已迁入归档区的证据稿'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区现行件说明未解析到命名与维护规则：$execStandardGuidePath"
    }

    $namingRuleItems = @(
        [regex]::Matches($sectionContent, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($namingRuleItems.Count -eq 0) {
        throw "执行区现行件说明未解析到命名与维护规则列点：$execStandardGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $namingRuleItems -ExpectedValues $expectedExecStandardGuideNamingRuleItems -Label '执行区现行件说明命名与维护规则摘要序列'
    return $expectedExecStandardGuideNamingRuleItems
}

function Get-CanonicalExecStandardGuideArchivedEvidenceItems {
    $execStandardGuidePath = 'docs/40-执行/04-执行区现行件与证据稿说明.md'
    $expectedExecStandardGuideArchivedEvidenceItems = @(
        'docs/90-归档/20260328-232458-v4-mvp-boundary-and-first-task-package.md'
        'docs/90-归档/20260328-233811-v4-trial-001-mvp-boundary-freeze.md'
    )

    $sectionContent = Get-FileSectionContent -FilePath $execStandardGuidePath -SectionStartMarker '## 已迁入归档区的证据稿' -SectionEndMarker '## 本文件的价值'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区现行件说明未解析到已迁入归档区的证据稿：$execStandardGuidePath"
    }

    $archivedEvidenceItems = @(
        [regex]::Matches($sectionContent, '(?m)^- `([^`]+)`\r?$') |
            ForEach-Object {
                $_.Groups[1].Value.Trim()
            }
    )
    if ($archivedEvidenceItems.Count -eq 0) {
        throw "执行区现行件说明未解析到已迁入归档区的证据稿列点：$execStandardGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $archivedEvidenceItems -ExpectedValues $expectedExecStandardGuideArchivedEvidenceItems -Label '执行区现行件说明已迁入归档区的证据稿序列'
    return $expectedExecStandardGuideArchivedEvidenceItems
}

function Get-CanonicalExecStandardGuideValueItems {
    $execStandardGuidePath = 'docs/40-执行/04-执行区现行件与证据稿说明.md'
    $expectedExecStandardGuideValueItems = @(
        '降低后续 Trial 留痕越来越多时的检索成本'
        '避免把过程稿误当成现行标准件继续扩写'
        '让执行区保持“现行件少而稳，证据稿可追溯”的长期结构'
    )

    $sectionContent = Get-FileSectionContent -FilePath $execStandardGuidePath -SectionStartMarker '## 本文件的价值' -SectionEndMarker ''
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "执行区现行件说明未解析到本文件的价值：$execStandardGuidePath"
    }

    $valueItems = @(
        [regex]::Matches($sectionContent, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($valueItems.Count -eq 0) {
        throw "执行区现行件说明未解析到本文件的价值列点：$execStandardGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $valueItems -ExpectedValues $expectedExecStandardGuideValueItems -Label '执行区现行件说明本文件的价值摘要序列'
    return $expectedExecStandardGuideValueItems
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
    return Get-OrderedUniqueValues -Values @(
        [regex]::Matches($fileContent, $RegexPattern) |
            ForEach-Object { $_.Groups[1].Value }
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

function Get-CodeBlockContentFromSection {
    param(
        [string]$FilePath,
        [string]$SectionStartMarker,
        [string]$SectionEndMarker = ''
    )

    $sectionContent = Get-FileSectionContent -FilePath $FilePath -SectionStartMarker $SectionStartMarker -SectionEndMarker $SectionEndMarker
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        return ''
    }

    $codeBlockMatch = [regex]::Match($sectionContent, '```(?:text)?\s*(?<body>[\s\S]*?)```')
    if (-not $codeBlockMatch.Success) {
        return ''
    }

    return $codeBlockMatch.Groups['body'].Value
}

function ConvertFrom-MarkdownTableLine {
    param(
        [string]$LineText,
        [string]$Label = 'Markdown 表格行'
    )

    $normalizedLineText = $LineText.Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedLineText)) {
        throw "$Label 为空。"
    }

    if ((-not $normalizedLineText.StartsWith('|')) -or (-not $normalizedLineText.EndsWith('|'))) {
        throw "$Label 不是合法的 Markdown 表格行：$normalizedLineText"
    }

    return @(
        ($normalizedLineText.Substring(1, $normalizedLineText.Length - 2) -split '\|') |
            ForEach-Object { $_.Trim() }
    )
}

function Get-ApprovedTopLevelEntriesFromLockList {
    $lockListPath = 'docs/30-方案/02-V4-目录锁定清单.md'
    $approvedDirectoryBlock = Get-CodeBlockContentFromSection -FilePath $lockListPath -SectionStartMarker '## 顶层批准目录' -SectionEndMarker '## 顶层批准文件'
    $approvedFileBlock = Get-CodeBlockContentFromSection -FilePath $lockListPath -SectionStartMarker '## 顶层批准文件' -SectionEndMarker '## docs 批准子目录'

    if ([string]::IsNullOrWhiteSpace($approvedDirectoryBlock)) {
        throw "目录锁定清单缺少顶层批准目录区块：$lockListPath"
    }

    if ([string]::IsNullOrWhiteSpace($approvedFileBlock)) {
        throw "目录锁定清单缺少顶层批准文件区块：$lockListPath"
    }

    $approvedEntries = New-Object System.Collections.Generic.List[string]
    foreach ($directoryMatch in ([regex]::Matches($approvedDirectoryBlock, '(?m)^[├└]─\s+([^/\r\n]+?)/\s*$'))) {
        $approvedEntries.Add($directoryMatch.Groups[1].Value)
    }

    foreach ($fileMatch in ([regex]::Matches($approvedFileBlock, '(?m)^([^\r\n]+?)\s*$'))) {
        $trimmedLine = $fileMatch.Groups[1].Value.Trim()
        if ($trimmedLine -eq '') {
            continue
        }

        $approvedEntries.Add($trimmedLine)
    }

    $orderedApprovedEntries = Get-OrderedUniqueValues -Values @($approvedEntries)
    $expectedApprovedEntries = @(
        'docs'
        '.codex'
        'logs'
        'temp'
        'codex-home-export'
        'README.md'
        'AGENTS.md'
        '.gitignore'
        'install.cmd'
    )
    Assert-ExactOrderedValues -SourceValues $orderedApprovedEntries -ExpectedValues $expectedApprovedEntries -Label '目录锁定清单顶层批准项'
    return $orderedApprovedEntries
}

function Get-ApprovedTrackedCodexFilesFromLockList {
    $lockListPath = 'docs/30-方案/02-V4-目录锁定清单.md'
    $approvedCodexFileBlock = Get-CodeBlockContentFromSection -FilePath $lockListPath -SectionStartMarker '## 公开仓允许跟踪的运行态文件' -SectionEndMarker '## temp 批准结构'
    if ([string]::IsNullOrWhiteSpace($approvedCodexFileBlock)) {
        throw "目录锁定清单缺少公开仓允许跟踪的运行态文件区块：$lockListPath"
    }

    $approvedCodexFiles = New-Object System.Collections.Generic.List[string]
    foreach ($fileLine in ($approvedCodexFileBlock -split "`r?`n")) {
        $trimmedLine = ConvertTo-NormalizedPath $fileLine
        if ($trimmedLine -eq '') {
            continue
        }

        $approvedCodexFiles.Add($trimmedLine)
    }

    $orderedApprovedCodexFiles = Get-OrderedUniqueValues -Values @($approvedCodexFiles)
    $expectedApprovedCodexFiles = @(
        '.codex/chancellor/README.md'
        '.codex/chancellor/audit-local-task-status.ps1'
        '.codex/chancellor/check-task-package-tech-spec.ps1'
        '.codex/chancellor/check-task-state-machine.ps1'
        '.codex/chancellor/finalize-panel-acceptance-closeout.ps1'
        '.codex/chancellor/create-gate-package.ps1'
        '.codex/chancellor/create-task-package.ps1'
        '.codex/chancellor/install-public-commit-governance-hook.ps1'
        '.codex/chancellor/invoke-public-commit-governance-gate.ps1'
        '.codex/chancellor/Invoke-RateLimitedRequest.ps1'
        '.codex/chancellor/Invoke-SafeFileAppend.ps1'
        '.codex/chancellor/record-exception-state.ps1'
        '.codex/chancellor/resolve-gate-package.ps1'
        '.codex/chancellor/resolve-panel-acceptance-closeout.ps1'
        '.codex/chancellor/review-panel-acceptance-closeout.ps1'
        '.codex/chancellor/test-panel-acceptance-closeout-review.ps1'
        '.codex/chancellor/tasks/README.md'
        '.codex/chancellor/Test-Phase2Prerequisites.ps1'
        '.codex/chancellor/test-public-commit-governance-gate.ps1'
        '.codex/chancellor/write-concurrent-status-report.ps1'
        '.codex/chancellor/write-governance-config-review.ps1'
    )
    Assert-ExactOrderedValues -SourceValues $orderedApprovedCodexFiles -ExpectedValues $expectedApprovedCodexFiles -Label '目录锁定清单运行态白名单'
    return $orderedApprovedCodexFiles
}

function Read-JsonObjectFromFile {
    param(
        [string]$Path,
        [string]$Label = 'JSON 文件'
    )

    if (-not (Test-Path $Path)) {
        throw "缺少$Label：$Path"
    }

    try {
        return (Get-Content $Path -Raw | ConvertFrom-Json)
    }
    catch {
        throw "$Label 解析失败：$Path"
    }
}

function Get-CodexHomeExportConsistencyState {
    $readmePath = 'codex-home-export/README.md'
    $versionPath = 'codex-home-export/VERSION.json'
    $manifestPath = 'codex-home-export/manifest.json'

    $versionInfo = Read-JsonObjectFromFile -Path $versionPath -Label '生产母体版本文件'
    $manifestInfo = Read-JsonObjectFromFile -Path $manifestPath -Label '生产母体 manifest'

    if ([string]::IsNullOrWhiteSpace($versionInfo.cx_version)) {
        throw "生产母体版本文件缺少 cx_version：$versionPath"
    }

    if ([string]::IsNullOrWhiteSpace($versionInfo.source_of_truth)) {
        throw "生产母体版本文件缺少 source_of_truth：$versionPath"
    }

    if ($versionInfo.source_of_truth -ne 'codex-home-export') {
        throw "生产母体版本文件 source_of_truth 不匹配：期望 codex-home-export，实际 $($versionInfo.source_of_truth)"
    }

    if ([string]::IsNullOrWhiteSpace($manifestInfo.version)) {
        throw "生产母体 manifest 缺少 version：$manifestPath"
    }

    if ([string]::IsNullOrWhiteSpace($manifestInfo.stage)) {
        throw "生产母体 manifest 缺少 stage：$manifestPath"
    }

    if ($manifestInfo.version -ne $versionInfo.cx_version) {
        throw "生产母体 manifest.version 与 VERSION.json.cx_version 不一致：期望 $($versionInfo.cx_version)，实际 $($manifestInfo.version)"
    }

    $manifestIncludedFiles = @(
        Get-OrderedUniqueValues -Values @($manifestInfo.included)
    )
    if ($manifestIncludedFiles.Count -eq 0) {
        throw "生产母体 manifest.included 为空：$manifestPath"
    }

    $trackedExportFiles = @(
        Get-OrderedUniqueValues -Values @(
            @(git -c core.quotepath=false ls-files -- 'codex-home-export') |
                ForEach-Object { ConvertTo-NormalizedPath $_ } |
                Where-Object { $_.StartsWith('codex-home-export/') } |
                ForEach-Object { $_.Substring('codex-home-export/'.Length) }
        )
    )
    if ($trackedExportFiles.Count -eq 0) {
        throw '生产母体当前没有任何受 git 跟踪的文件。'
    }
    Assert-RequiredPathsPresent -SourcePaths $trackedExportFiles -RequiredPaths $manifestIncludedFiles -Label '生产母体 manifest included 跟踪面'
    $unexpectedTrackedExportFiles = @(
        $trackedExportFiles |
            Where-Object { $_ -notin $manifestIncludedFiles }
    )
    if ($unexpectedTrackedExportFiles.Count -gt 0) {
        throw "生产母体 git 跟踪文件存在未列入 manifest.included 的路径：$($unexpectedTrackedExportFiles -join '、')"
    }

    $actualExportFiles = @(
        Get-OrderedUniqueValues -Values @(
            @(Get-ChildItem 'codex-home-export' -File | Sort-Object Name | ForEach-Object { $_.Name })
        )
    )
    Assert-RequiredPathsPresent -SourcePaths $manifestIncludedFiles -RequiredPaths $actualExportFiles -Label '生产母体 manifest included'

    $unexpectedManifestIncludedFiles = @(
        $manifestIncludedFiles |
            Where-Object { $_ -notin $actualExportFiles }
    )
    if ($unexpectedManifestIncludedFiles.Count -gt 0) {
        throw "生产母体 manifest included 存在未落文件：$($unexpectedManifestIncludedFiles -join '、')"
    }

    $readmeLandedSection = Get-FileSectionContent -FilePath $readmePath -SectionStartMarker '## 当前已落文件' -SectionEndMarker '## 当前未落文件'
    $readmeLandedSummaryLines = @(
        Get-OrderedUniqueValues -Values @(
            [regex]::Matches($readmeLandedSection, '(?m)^- (.+?)\r?$') |
                ForEach-Object { $_.Groups[1].Value.Trim() } |
                Where-Object { $_ -ne '' }
        )
    )
    if ($readmeLandedSummaryLines.Count -eq 0) {
        throw "生产母体 README 未解析到当前已落文件真源说明：$readmePath"
    }
    $expectedReadmeLandedSummaryLines = @(
        '`manifest.json` 的 `included` 是当前生产母体受管文件清单唯一真源。'
        'README 这里只保留阶段、入口与使用说明，不再重复抄整份落文件列表。'
        '如需核对具体受管文件，请直接查看 `manifest.json`。'
    )
    Assert-ExactOrderedValues -SourceValues $readmeLandedSummaryLines -ExpectedValues $expectedReadmeLandedSummaryLines -Label '生产母体 README 当前已落文件真源说明'

    $readmeStageSection = Get-FileSectionContent -FilePath $readmePath -SectionStartMarker '## 当前阶段' -SectionEndMarker '## 当前已落文件'
    $readmeStageValues = @(
        Get-OrderedUniqueValues -Values @(
            [regex]::Matches($readmeStageSection, '(?m)^- `stage`：`([^`]+)`\r?$') |
                ForEach-Object { $_.Groups[1].Value }
        )
    )
    if ($readmeStageValues.Count -ne 1) {
        throw "生产母体 README 当前阶段未解析到唯一 stage：$readmePath"
    }

    if ($readmeStageValues[0] -ne $manifestInfo.stage) {
        throw "生产母体 README stage 与 manifest.stage 不一致：期望 $($manifestInfo.stage)，实际 $($readmeStageValues[0])"
    }

    return [pscustomobject]@{
        Version = $versionInfo.cx_version
        Stage = $manifestInfo.stage
        IncludedFiles = $manifestIncludedFiles
    }
}

function Get-CodexHomeManagedVersionDisciplineViolation {
    param(
        [string[]]$ChangedPaths,
        [string[]]$IncludedFiles
    )

    if (($null -eq $IncludedFiles) -or ($IncludedFiles.Count -eq 0)) {
        return ''
    }

    $managedChangedPaths = @(
        $ChangedPaths |
            Where-Object {
                $_.StartsWith('codex-home-export/') -and
                ($_.Substring('codex-home-export/'.Length) -in $IncludedFiles)
            } |
            Sort-Object -Unique
    )
    if ($managedChangedPaths.Count -eq 0) {
        return ''
    }

    if ($managedChangedPaths -contains 'codex-home-export/VERSION.json') {
        return ''
    }

    return "生产母体受管文件已改动但未同步版本真源：$($managedChangedPaths -join '、')；请同时更新 codex-home-export/VERSION.json，或先重新安装/同步后再提交。"
}

function Get-CanonicalPanelCommandState {
    $agentsPath = 'AGENTS.md'
    $codexHomeAgentsPath = 'codex-home-export/AGENTS.md'
    $versionPath = 'codex-home-export/VERSION.json'
    $acceptanceDocPath = 'docs/40-执行/03-面板入口验收.md'
    $checklistPath = 'codex-home-export/panel-acceptance-checklist.md'
    $expectedAgentRows = @(
        [pscustomobject]@{ Command = '传令：XXXX'; Description = '唯一做事入口；`XXXX` 直接写自然语言需求' }
        [pscustomobject]@{ Command = '传令：状态'; Description = '查看当前丞相状态' }
        [pscustomobject]@{ Command = '传令：版本'; Description = '查看当前版本与真源' }
        [pscustomobject]@{ Command = '传令：升级'; Description = '仅在用户主动要求时，再处理升级动作' }
        [pscustomobject]@{ Command = '传令：交班'; Description = '为当前激活任务生成交班单与进度快照' }
        [pscustomobject]@{ Command = '传令：接班'; Description = '读取当前激活任务交班单并续上当前任务' }
    )
    $expectedTaskEntryFlow = @(
        '先确认丞相能正常接到传令'
        '再确认丞相自身状态良好'
        '接着把丞相调整到最佳工作状态'
        '丞相记录这次要做的任务'
        '丞相开始执行任务'
    )
    $expectedStatusBarSlots = @(
        '版本'
        '上次检查'
        '自动修复'
        '关键文件一致性'
        '当前模式'
        '当前任务'
    )
    $expectedBoundaryPrompt = '提示：丞相在检查阶段只检查自己，不会查看你的项目；执行阶段只按你的传令办事，不会擅自审查项目。'
    $expectedQuoteSystemVersion = '2.0'
    $expectedTaskEntryTemplate = @(
        '🪶 军令入帐。亮，即刻接管全局。'
        '军令已明，亮先接手。'
    )
    $expectedTaskEntryWithCheckTemplate = @(
        '🪶 军令入帐。亮，即刻接管全局。'
        $expectedBoundaryPrompt
        '军令已明，亮先接手。'
    )
    $expectedVersionTemplate = @(
        '版本号：<cx_version>'
        '版本来源：codex-home-export'
        '真源路径：codex-home-export/VERSION.json'
    )
    $expectedStatusTemplate = @(
        '版本：<cx_version>'
        '上次检查：<last_check>'
        '自动修复：<auto_repair>'
        '关键文件一致性：<key_file_consistency>'
        '当前模式：<current_mode>'
        '当前任务：<current_task>'
    )
    $expectedCloseoutSections = @(
        '已完成'
        '结果'
        '下一步'
    )
    $expectedProcessQuotes = [ordered]@{
        task_entry = '军令已明，亮先接手。'
        analysis = '亮先看清症结，再动手。'
        breakdown = '此事可拆，亮按最短路径推进。'
        dispatch = '所需动作已排定，开始推进。'
        wrap_up = '主干已稳，亮正在收束余项。'
        closeout = '此事已交卷，现呈结果。'
    }
    $expectedReplySkeletonLines = @(
        '## 标准回复骨架'
        '- 开工默认骨架固定为：`开场白 → 接令句`'
        '- 只有实际执行自检前才固定补 1 行边界提示：`开场白 → 固定边界提示 → 接令句`'
        '- `传令：版本` 固定按 3 行回复：`版本号 / 版本来源 / 真源路径`'
        '- `传令：状态` 固定按 6 行回复：`版本 / 上次检查 / 自动修复 / 关键文件一致性 / 当前模式 / 当前任务`'
        '- 收口默认固定为 3 段：`已完成 / 结果 / 下一步`'
        '- `接令`：`军令已明，亮先接手。`'
        '- `研判`：`亮先看清症结，再动手。`'
        '- `拆解`：`此事可拆，亮按最短路径推进。`'
        '- `调度`：`所需动作已排定，开始推进。`'
        '- `收束`：`主干已稳，亮正在收束余项。`'
        '- `收口`：`此事已交卷，现呈结果。`'
        '- `显示规则`：过程提示一次只显示 1 句，不随机刷屏。'
    )
    $expectedAcceptanceLines = @(
        '确保主公新开对话时，一眼就懂怎么用；入口不歧义，开场白固定，查看口径稳定，任务入口可以直接开工。'
        '- 唯一做事入口：`传令：XXXX`'
        '- 3 个可查命令：`传令：状态 / 传令：版本 / 传令：升级`'
        '- 2 个跨聊天命令：`传令：交班 / 传令：接班`'
        '- 新对话自动提示：`例如：传令：计算1+1=?`'
        '- 默认开场白：`🪶 军令入帐。亮，即刻接管全局。`'
        '- 固定开工骨架：`开场白 → 接令句`'
        '- 实际执行自检前：`开场白 → 固定边界提示 → 接令句`'
        ('- 对外流程：`' + ($expectedTaskEntryFlow -join ' → ') + '`')
        ('- 固定边界提示：`' + $expectedBoundaryPrompt + '`')
        '- 固定收口格式：`已完成 / 结果 / 下一步`'
        '- `传令：版本`：返回当前版本与真源。'
        '- `传令：状态`：汇报当前状态与下一步。'
        '- `传令：升级`：只在用户主动提出时，再处理升级动作。'
        '- `传令：交班`：为当前激活任务生成交班单与任务快照。'
        '- `传令：接班`：优先读取当前激活任务交班单并续上当前任务。'
        '- `版本`：当前版本号。'
        '- `上次检查`：最近一次检查时间或结论。'
        '- `自动修复`：是否触发过自动修复。'
        '- `关键文件一致性`：关键文件是否一致。'
        '- `当前模式`：当前处于丞相还是维护。'
        '- `当前任务`：当前是否存在激活任务。'
        '- `接令`：`军令已明，亮先接手。`'
        '- `研判`：`亮先看清症结，再动手。`'
        '- `拆解`：`此事可拆，亮按最短路径推进。`'
        '- `调度`：`所需动作已排定，开始推进。`'
        '- `收束`：`主干已稳，亮正在收束余项。`'
        '- `收口`：`此事已交卷，现呈结果。`'
        '- `显示规则`：过程提示一次只显示 1 句，不随机刷屏。'
        '- `触发方式`：只在用户主动输入 `传令：升级` 时触发。'
        '3. 先看系统是否给出示例：`例如：传令：计算1+1=?`'
        '5. 检查回复是否使用固定开场白：`🪶 军令入帐。亮，即刻接管全局。`'
        '6. 检查回复是否只在实际执行自检前带出固定边界提示；若本轮未实际执行自检，不重复显示，也不把检查对象误说成你的项目。'
        '7. 输入 `传令：版本`，检查版本号、版本来源、真源路径是否清楚。'
        '8. 输入 `传令：状态`，检查是否能按固定 6 行说清当前状态。'
        '9. 如需确认升级口径，再输入 `传令：升级`，检查是否明确“默认不自动升级，需用户主动提出”。'
        '10. 若本地存在激活任务，可再输入 `传令：交班`，检查是否生成交班单与任务快照。'
        '11. 若刚完成交班，可再输入 `传令：接班`，检查是否能直接接上当前任务。'
        '- 开工默认骨架稳定，不回退为散乱长段落。'
        '- 仅在实际执行自检前显示固定边界提示；本轮不自检时不重复显示。'
        '- `传令：版本` 能说清版本号、版本来源、真源路径。'
        '- `传令：状态` 能按固定 6 行说清当前状态。'
        '- 过程提示一次只显示 1 句，不刷屏。'
        '- 若触发收口，能按 `已完成 / 结果 / 下一步` 收束。'
        '- `传令：升级` 能明确“用户主动提出才处理，不自动升级”。'
        '- `传令：交班` 能明确保存位置，并生成任务级进度快照与交班单。'
        '- `传令：接班` 能在新聊天直接读到当前任务背景、做法与下一步。'
    )
    $expectedChecklistLines = @(
        '适用场景：完成 `install-to-home.ps1` 与 `verify-cutover.ps1` 后，人工确认本机生产切换是否丝滑。'
        '当前验板命令口径以 `codex-home-export/VERSION.json` 为准。'
        '自然语言任务入口统一使用：`传令：`'
        '- 唯一做事入口：`传令：XXXX`'
        '- 3 个可查命令：`传令：状态 / 传令：版本 / 传令：升级`'
        '- 2 个跨聊天命令：`传令：交班 / 传令：接班`'
        '- 默认开场白：`🪶 军令入帐。亮，即刻接管全局。`'
        '- 固定开工骨架：`开场白 → 接令句`'
        '- 实际执行自检前骨架：`开场白 → 固定边界提示 → 接令句`'
        '- 新对话自动提示：`例如：传令：计算1+1=?`'
        ('- 固定边界提示：`' + $expectedBoundaryPrompt + '`')
        '- 固定收口格式：`已完成 / 结果 / 下一步`'
        '3. 确认是否先看到示例：`例如：传令：计算1+1=?`'
        '4. 首句输入：`传令：测试入口是否稳态`'
        '5. 继续输入：`传令：版本`'
        '6. 再输入：`传令：状态`'
        '7. 如需确认升级口径，再输入：`传令：升级`'
        '8. 若本地已有激活任务，可补测：`传令：交班`'
        '9. 若刚完成交班，可补测：`传令：接班`'
        '- `开场白对不对`：是否固定为 `🪶 军令入帐。亮，即刻接管全局。`'
        '- `开工骨架顺不顺`：是否先开场白，再接令句；若进入检查阶段，再在中间插入边界提示'
        '- `提示清不清楚`：是否给出示例 `例如：传令：计算1+1=?`'
        '- `边界稳不稳`：是否只在需要检查时显示，且明确只检查丞相自己，不检查你的项目'
        '- `版本对不对`：能否说清版本号、版本来源、真源路径'
        '- `状态稳不稳`：能否按固定 6 行说清当前状态'
        '- `过程句多不多`：是否一次只显示 1 句，不乱刷'
        '- `收口顺不顺`：如触发收口，能否按 `已完成 / 结果 / 下一步`'
        '- `升级边界清不清楚`：能否明确“默认不自动升级，用户主动提出才处理”'
        '- `交班能不能落盘`：能否生成 `progress-snapshot.md` 与 `handoff.md`'
        '- `接班能不能续上`：能否直接说清当前任务背景、做法与下一步'
        '- 命令能正常响应。'
        '- 入口口径没有回退为旧的多命令体系。'
        '1. 先执行：`codex-home-export/verify-cutover.ps1`'
        '2. 若仍异常，再执行：`codex-home-export/rollback-from-backup.ps1`'
        '3. 回退后重新打开面板，再次验板。'
    )
    $legacyMarkers = @(
        '传令 帮助'
        '传令 检查'
        '传令 修复'
        '传令 验板'
        '传令 版本'
        '传令 状态'
        '`开始：XXXX`'
        '`执行：XXXX`'
        '`任务：XXXX`'
    )

    function Assert-LineSetContains {
        param(
            [string[]]$Lines,
            [string]$ExpectedLine,
            [string]$Label
        )

        if ($Lines -notcontains $ExpectedLine) {
            throw "$Label 缺少固定行：$ExpectedLine"
        }
    }

    function Assert-ContentHasNoLegacyMarker {
        param(
            [string]$Content,
            [string]$Label,
            [string[]]$Markers
        )

        foreach ($marker in $Markers) {
            if ($Content.Contains($marker)) {
                throw "$Label 仍残留旧口径：$marker"
            }
        }
    }

    $agentsLines = @(Get-Content $agentsPath)
    foreach ($expectedReplySkeletonLine in $expectedReplySkeletonLines) {
        Assert-LineSetContains -Lines $agentsLines -ExpectedLine $expectedReplySkeletonLine -Label 'AGENTS 标准回复骨架'
    }

    $codexHomeAgentsLines = @(Get-Content $codexHomeAgentsPath)
    foreach ($expectedReplySkeletonLine in $expectedReplySkeletonLines) {
        Assert-LineSetContains -Lines $codexHomeAgentsLines -ExpectedLine $expectedReplySkeletonLine -Label 'codex-home-export AGENTS 标准回复骨架'
    }

    $agentsSection = Get-FileSectionContent -FilePath $agentsPath -SectionStartMarker '## 面板传令格式' -SectionEndMarker '## 仓库卫生纪律'
    if ([string]::IsNullOrWhiteSpace($agentsSection)) {
        throw "AGENTS 未解析到面板传令格式区块：$agentsPath"
    }

    $agentRows = @(
        [regex]::Matches($agentsSection, '(?m)^\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|\s*$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = $_.Groups[2].Value.Trim()
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($agentRows | ForEach-Object { $_.Command }) -ExpectedValues @($expectedAgentRows | ForEach-Object { $_.Command }) -Label 'AGENTS 面板传令格式序列'
    foreach ($expectedAgentRow in $expectedAgentRows) {
        $matchedAgentRow = @(
            $agentRows |
                Where-Object { $_.Command -eq $expectedAgentRow.Command }
        ) | Select-Object -First 1
        if ($null -eq $matchedAgentRow) {
            throw "AGENTS 面板传令格式缺少命令：$($expectedAgentRow.Command)"
        }

        if ($matchedAgentRow.Description -ne $expectedAgentRow.Description) {
            throw "AGENTS 面板传令格式漂移：$($expectedAgentRow.Command) 期望 $($expectedAgentRow.Description)，实际 $($matchedAgentRow.Description)"
        }
    }
    Assert-ContentHasNoLegacyMarker -Content $agentsSection -Label 'AGENTS 面板传令格式' -Markers $legacyMarkers

    $versionInfo = Read-JsonObjectFromFile -Path $versionPath -Label '生产母体版本文件'
    if ($versionInfo.task_entry_prefix -ne '传令：') {
        throw "生产母体版本文件 task_entry_prefix 漂移：期望 传令：，实际 $($versionInfo.task_entry_prefix)"
    }
    if ($versionInfo.opening_line -ne '🪶 军令入帐。亮，即刻接管全局。') {
        throw "生产母体版本文件 opening_line 漂移：期望 🪶 军令入帐。亮，即刻接管全局。，实际 $($versionInfo.opening_line)"
    }
    if ($versionInfo.new_chat_hint -ne '例如：传令：计算1+1=?') {
        throw "生产母体版本文件 new_chat_hint 漂移：期望 例如：传令：计算1+1=?，实际 $($versionInfo.new_chat_hint)"
    }
    if ($versionInfo.quote_system_version -ne $expectedQuoteSystemVersion) {
        throw "生产母体版本文件 quote_system_version 漂移：期望 $expectedQuoteSystemVersion，实际 $($versionInfo.quote_system_version)"
    }
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.panel_commands)) -ExpectedValues @($expectedAgentRows | Where-Object { $_.Command -ne '传令：XXXX' } | ForEach-Object { $_.Command }) -Label '生产母体 panel_commands'
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.task_entry_flow)) -ExpectedValues $expectedTaskEntryFlow -Label '生产母体 task_entry_flow'
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.status_bar_slots)) -ExpectedValues $expectedStatusBarSlots -Label '生产母体 status_bar_slots'
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.standard_response_templates.task_entry)) -ExpectedValues $expectedTaskEntryTemplate -Label '生产母体 standard_response_templates.task_entry'
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.standard_response_templates.task_entry_with_check)) -ExpectedValues $expectedTaskEntryWithCheckTemplate -Label '生产母体 standard_response_templates.task_entry_with_check'
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.standard_response_templates.version)) -ExpectedValues $expectedVersionTemplate -Label '生产母体 standard_response_templates.version'
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.standard_response_templates.status)) -ExpectedValues $expectedStatusTemplate -Label '生产母体 standard_response_templates.status'
    Assert-ExactOrderedValues -SourceValues @(Get-OrderedUniqueValues -Values @($versionInfo.standard_response_templates.closeout_sections)) -ExpectedValues $expectedCloseoutSections -Label '生产母体 standard_response_templates.closeout_sections'
    if ($versionInfo.boundary_prompt -ne $expectedBoundaryPrompt) {
        throw "生产母体版本文件 boundary_prompt 漂移：期望 $expectedBoundaryPrompt，实际 $($versionInfo.boundary_prompt)"
    }
    foreach ($quoteKey in $expectedProcessQuotes.Keys) {
        if ($versionInfo.process_quotes_minimal.$quoteKey -ne $expectedProcessQuotes[$quoteKey]) {
            throw "生产母体版本文件 process_quotes_minimal.$quoteKey 漂移：期望 $($expectedProcessQuotes[$quoteKey])，实际 $($versionInfo.process_quotes_minimal.$quoteKey)"
        }
    }

    $acceptanceLines = @(Get-Content $acceptanceDocPath)
    $acceptanceContent = [System.IO.File]::ReadAllText($acceptanceDocPath)
    foreach ($expectedAcceptanceLine in $expectedAcceptanceLines) {
        Assert-LineSetContains -Lines $acceptanceLines -ExpectedLine $expectedAcceptanceLine -Label '面板入口验收'
    }
    Assert-ContentHasNoLegacyMarker -Content $acceptanceContent -Label '面板入口验收' -Markers $legacyMarkers

    $checklistLines = @(Get-Content $checklistPath)
    $checklistContent = [System.IO.File]::ReadAllText($checklistPath)
    foreach ($expectedChecklistLine in $expectedChecklistLines) {
        Assert-LineSetContains -Lines $checklistLines -ExpectedLine $expectedChecklistLine -Label '面板人工验板清单'
    }
    Assert-ContentHasNoLegacyMarker -Content $checklistContent -Label '面板人工验板清单' -Markers $legacyMarkers

    return [pscustomobject]@{
        PanelCommands = @($expectedAgentRows | ForEach-Object { $_.Command })
        TaskEntryFlow = $expectedTaskEntryFlow
        StatusBarSlots = $expectedStatusBarSlots
    }
}
function Get-CanonicalMaintenanceMatrixConclusionLine {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenanceMatrixConclusionLine = '先用动作矩阵判断该走哪条维护路径，再按收口检查表完成留痕、导航同步、提交与推送。'

    $sectionContent = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '## 一句话结论' -SectionEndMarker '## 维护层动作矩阵'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "维护层动作矩阵未解析到一句话结论：$maintenanceMatrixPath"
    }

    $summaryLines = @(
        ($sectionContent -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($summaryLines.Count -eq 0) {
        throw "维护层动作矩阵一句话结论为空：$maintenanceMatrixPath"
    }

    $actualMaintenanceMatrixConclusionLine = $summaryLines[0]
    Assert-ExactOrderedValues -SourceValues @($actualMaintenanceMatrixConclusionLine) -ExpectedValues @($expectedMaintenanceMatrixConclusionLine) -Label '维护层动作矩阵一句话结论'
    return $expectedMaintenanceMatrixConclusionLine
}

function Get-CanonicalMaintenanceMatrixRows {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenanceMatrixHeaders = @(
        '动作类型'
        '什么时候用'
        '主入口'
        '最低产出'
        '公开仓边界'
        '风险级别'
    )
    $expectedMaintenanceMatrixRows = @(
        [pscustomobject]@{ ActionType = '本地安全提交'; WhenToUse = '有公开安全改动需要进入远端时'; PrimaryEntry = '`docs/40-执行/10-本地安全提交流程.md`'; MinimumOutput = '一次串行 `add`/`commit`/`pull --rebase`/`push`'; PublicBoundary = '只提交公开安全文件；禁止带上 `.codex/`、`logs/`'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '任务包半自动起包'; WhenToUse = '需要开始一条新任务并保留本地运行态时'; PrimaryEntry = '`docs/40-执行/11-任务包半自动起包.md`'; MinimumOutput = '任务包 5 件套骨架 + 收口提示'; PublicBoundary = '任务包运行态留在本地；不进入公开仓'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '执行区证据稿归档'; WhenToUse = '执行区出现失去现行职责的时间戳稿时'; PrimaryEntry = '`docs/90-归档/01-执行区证据稿归档规则.md`'; MinimumOutput = '归档结果 + 入口同步'; PublicBoundary = '归档文档可公开；过程运行态仍不公开'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '维护入口同步'; WhenToUse = '新增或变更维护标准件，可能影响入口口径时'; PrimaryEntry = '`docs/40-执行/13-维护层总入口.md`'; MinimumOutput = '首页、总览、执行区索引同步'; PublicBoundary = '只公开标准件与导航；不公开本地日志'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '人工拍板包准备'; WhenToUse = '需要主公判断边界、风险或方案取舍时'; PrimaryEntry = '`docs/40-执行/15-拍板包准备与收口规范.md`'; MinimumOutput = '结论、选项、影响、建议'; PublicBoundary = '拍板材料可公开；敏感运行态不公开'; RiskLevel = '中' }
        [pscustomobject]@{ ActionType = '拍板包半自动模板'; WhenToUse = '需要从空的 `gates.yaml` 快速生成首个待拍板事项时'; PrimaryEntry = '`docs/40-执行/16-拍板包半自动模板.md`'; MinimumOutput = '首个 gate 项 + 状态同步 + 结果留痕'; PublicBoundary = '真实任务运行态继续只留本地；公开仓只放脚本与说明'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '拍板结果回写模板'; WhenToUse = '主公已拍板，需要把结果回写并恢复推进时'; PrimaryEntry = '`docs/40-执行/17-拍板结果回写模板.md`'; MinimumOutput = 'gate 回写 + 状态恢复 + 决策留痕'; PublicBoundary = '真实任务运行态继续只留本地；公开仓只放脚本与说明'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '异常路径与回退模板'; WhenToUse = '当前链路失败、阻塞或需要回退时'; PrimaryEntry = '`docs/40-执行/18-异常路径与回退模板.md`'; MinimumOutput = '异常状态切换 + 回退说明 + 恢复提示'; PublicBoundary = '真实任务运行态继续只留本地；公开仓只放脚本与说明'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '多 gate 与多异常并存处理规则'; WhenToUse = '需要在多个待处理事项之间裁决主状态时'; PrimaryEntry = '`docs/40-执行/19-多 gate 与多异常并存处理规则.md`'; MinimumOutput = '主阻塞裁决 + 次要事项保留 + 汇报顺序'; PublicBoundary = '真实任务运行态继续只留本地；公开仓只放规则与说明'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '复杂并存汇报骨架模板'; WhenToUse = '已选主状态，需要把复杂裁决结果快速落进任务包时'; PrimaryEntry = '`docs/40-执行/20-复杂并存汇报骨架模板.md`'; MinimumOutput = '`result.md` / `decision-log.md` 骨架 + 可选状态同步'; PublicBoundary = '真实任务运行态继续只留本地；公开仓只放脚本与说明'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '治理审计复核'; WhenToUse = '当前轮变更现行标准件、公开口径、拍板/异常/复杂裁决，或准备推送公开改动时'; PrimaryEntry = '`docs/30-方案/08-V4-治理审计候选规范.md`'; MinimumOutput = '来源说明 + 决策依据 + 漂移检查 + 公开边界复核'; PublicBoundary = '只公开规则与结果；不公开本地运行态与隐私文件'; RiskLevel = '低' }
        [pscustomobject]@{ ActionType = '关键配置来源与漂移复核'; WhenToUse = '需要把当前关键配置来源、版本依据与漂移检查写入任务包时'; PrimaryEntry = '`docs/40-执行/21-关键配置来源与漂移复核模板.md`'; MinimumOutput = '`result.md` / `decision-log.md` 复核骨架'; PublicBoundary = '真实任务运行态继续只留本地；公开仓只放脚本与说明'; RiskLevel = '低' }
    )

    $maintenanceMatrixSection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '## 维护层动作矩阵' -SectionEndMarker '## 维护入口同步固定槽位'
    if ([string]::IsNullOrWhiteSpace($maintenanceMatrixSection)) {
        throw "维护层动作矩阵未解析到动作矩阵表格：$maintenanceMatrixPath"
    }

    $maintenanceMatrixTableLines = @(
        ($maintenanceMatrixSection -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -like '|*|' }
    )
    if ($maintenanceMatrixTableLines.Count -lt 3) {
        throw "维护层动作矩阵表格行数不足：$maintenanceMatrixPath"
    }

    $actualMaintenanceMatrixHeaders = ConvertFrom-MarkdownTableLine -LineText $maintenanceMatrixTableLines[0] -Label '维护层动作矩阵表头'
    if ($actualMaintenanceMatrixHeaders.Count -ne $expectedMaintenanceMatrixHeaders.Count) {
        throw "维护层动作矩阵表头列数漂移：期望 $($expectedMaintenanceMatrixHeaders.Count) 列，实际 $($actualMaintenanceMatrixHeaders.Count) 列"
    }
    Assert-ExactOrderedValues -SourceValues $actualMaintenanceMatrixHeaders -ExpectedValues $expectedMaintenanceMatrixHeaders -Label '维护层动作矩阵表头'

    $expectedSeparatorCells = @('---', '---', '---', '---', '---', '---')
    $actualSeparatorCells = ConvertFrom-MarkdownTableLine -LineText $maintenanceMatrixTableLines[1] -Label '维护层动作矩阵分隔行'
    if ($actualSeparatorCells.Count -ne $expectedSeparatorCells.Count) {
        throw "维护层动作矩阵分隔行列数漂移：期望 $($expectedSeparatorCells.Count) 列，实际 $($actualSeparatorCells.Count) 列"
    }

    for ($separatorIndex = 0; $separatorIndex -lt $expectedSeparatorCells.Count; $separatorIndex++) {
        if ($actualSeparatorCells[$separatorIndex] -ne $expectedSeparatorCells[$separatorIndex]) {
            throw "维护层动作矩阵分隔行漂移：第 $($separatorIndex + 1) 列期望 $($expectedSeparatorCells[$separatorIndex])，实际 $($actualSeparatorCells[$separatorIndex])"
        }
    }

    $actualMaintenanceMatrixRows = @(
        $maintenanceMatrixTableLines |
            Select-Object -Skip 2 |
            ForEach-Object {
                $actualRowCells = ConvertFrom-MarkdownTableLine -LineText $_ -Label '维护层动作矩阵数据行'
                if ($actualRowCells.Count -ne 6) {
                    throw "维护层动作矩阵数据行列数漂移：$_"
                }

                [pscustomobject]@{
                    ActionType = $actualRowCells[0]
                    WhenToUse = $actualRowCells[1]
                    PrimaryEntry = $actualRowCells[2]
                    MinimumOutput = $actualRowCells[3]
                    PublicBoundary = $actualRowCells[4]
                    RiskLevel = $actualRowCells[5]
                }
            }
    )
    if ($actualMaintenanceMatrixRows.Count -ne $expectedMaintenanceMatrixRows.Count) {
        throw "维护层动作矩阵数据行数量漂移：期望 $($expectedMaintenanceMatrixRows.Count) 行，实际 $($actualMaintenanceMatrixRows.Count) 行"
    }

    Assert-ExactOrderedValues -SourceValues @($actualMaintenanceMatrixRows | ForEach-Object { $_.ActionType }) -ExpectedValues @($expectedMaintenanceMatrixRows | ForEach-Object { $_.ActionType }) -Label '维护层动作矩阵动作类型序列'

    $maintenanceMatrixColumnLabels = @{
        WhenToUse = '什么时候用'
        PrimaryEntry = '主入口'
        MinimumOutput = '最低产出'
        PublicBoundary = '公开仓边界'
        RiskLevel = '风险级别'
    }

    foreach ($expectedMaintenanceMatrixRow in $expectedMaintenanceMatrixRows) {
        $matchedMaintenanceMatrixRow = @(
            $actualMaintenanceMatrixRows |
                Where-Object { $_.ActionType -eq $expectedMaintenanceMatrixRow.ActionType }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenanceMatrixRow) {
            throw "维护层动作矩阵缺少动作类型：$($expectedMaintenanceMatrixRow.ActionType)"
        }

        foreach ($maintenanceMatrixColumnName in $maintenanceMatrixColumnLabels.Keys) {
            if ($matchedMaintenanceMatrixRow.$maintenanceMatrixColumnName -ne $expectedMaintenanceMatrixRow.$maintenanceMatrixColumnName) {
                throw "维护层动作矩阵行漂移：$($expectedMaintenanceMatrixRow.ActionType) 的 $($maintenanceMatrixColumnLabels[$maintenanceMatrixColumnName]) 期望 $($expectedMaintenanceMatrixRow.$maintenanceMatrixColumnName)，实际 $($matchedMaintenanceMatrixRow.$maintenanceMatrixColumnName)"
            }
        }
    }

    return [pscustomobject]@{
        MaintenanceMatrixHeaders = @($expectedMaintenanceMatrixHeaders)
        MaintenanceMatrixRows = @($expectedMaintenanceMatrixRows)
    }
}

function Get-CanonicalGatePackageConclusionLine {
    $gatePackageDocPath = 'docs/40-执行/15-拍板包准备与收口规范.md'
    $expectedGatePackageConclusionLine = '当任务进入 `waiting_gate` 或存在 `must_gate` 事项时，应先形成标准拍板包，再向主公汇报，不直接把半成品判断抛给主公。'

    $sectionContent = Get-FileSectionContent -FilePath $gatePackageDocPath -SectionStartMarker '## 一句话结论' -SectionEndMarker '## 什么时候必须准备拍板包'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "拍板包准备与收口规范未解析到一句话结论：$gatePackageDocPath"
    }

    $summaryLines = @(
        ($sectionContent -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($summaryLines.Count -eq 0) {
        throw "拍板包准备与收口规范一句话结论为空：$gatePackageDocPath"
    }

    $actualGatePackageConclusionLine = $summaryLines[0]
    Assert-ExactOrderedValues -SourceValues @($actualGatePackageConclusionLine) -ExpectedValues @($expectedGatePackageConclusionLine) -Label '拍板包准备与收口规范一句话结论'
    return $expectedGatePackageConclusionLine
}

function Get-CanonicalGatePackageTriggerItems {
    $gatePackageDocPath = 'docs/40-执行/15-拍板包准备与收口规范.md'
    $expectedGatePackageTriggerItems = @(
        '`contract.yaml` 中 `must_gate` 不为空'
        '`gates.yaml` 中存在待处理事项'
        '任务已进入 `waiting_gate`'
        '当前动作会突破边界、改变风险等级、改动现行口径或需要方案取舍'
    )

    $triggerSection = Get-FileSectionContent -FilePath $gatePackageDocPath -SectionStartMarker '## 什么时候必须准备拍板包' -SectionEndMarker '## 拍板包最低组成'
    if ([string]::IsNullOrWhiteSpace($triggerSection)) {
        throw "拍板包准备与收口规范未解析到必须准备拍板包区块：$gatePackageDocPath"
    }

    $actualGatePackageTriggerItems = @(
        [regex]::Matches($triggerSection, '(?m)^- (.+?)。?\r?$') |
            ForEach-Object { ($_.Groups[1].Value.Trim() -replace '。$','') }
    )
    Assert-ExactOrderedValues -SourceValues $actualGatePackageTriggerItems -ExpectedValues $expectedGatePackageTriggerItems -Label '拍板包准备与收口规范必须准备条件'
    return $expectedGatePackageTriggerItems
}

function Get-CanonicalGatePackageMinimumCompositionState {
    $gatePackageDocPath = 'docs/40-执行/15-拍板包准备与收口规范.md'
    $expectedGatePackageMinimumCompositionItems = @(
        [pscustomobject]@{ Name = '结论'; Description = '一句话说明这次要拍什么' }
        [pscustomobject]@{ Name = '选项'; Description = '给出可执行选项，数量控制在 2 到 3 个' }
        [pscustomobject]@{ Name = '影响'; Description = '分别说明每个选项的收益、成本、风险与后续影响' }
        [pscustomobject]@{ Name = '建议'; Description = '明确推荐项，并说明推荐理由' }
    )

    $minimumCompositionSection = Get-FileSectionContent -FilePath $gatePackageDocPath -SectionStartMarker '## 拍板包最低组成' -SectionEndMarker '## `gates.yaml` 推荐结构'
    if ([string]::IsNullOrWhiteSpace($minimumCompositionSection)) {
        throw "拍板包准备与收口规范未解析到拍板包最低组成：$gatePackageDocPath"
    }

    $minimumCompositionRows = @(
        [regex]::Matches($minimumCompositionSection, '(?m)^\d+\. ([^：]+)：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value.Trim()
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($minimumCompositionRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedGatePackageMinimumCompositionItems | ForEach-Object { $_.Name }) -Label '拍板包准备与收口规范最低组成序列'
    foreach ($expectedGatePackageMinimumCompositionItem in $expectedGatePackageMinimumCompositionItems) {
        $matchedMinimumCompositionRow = @(
            $minimumCompositionRows |
                Where-Object { $_.Name -eq $expectedGatePackageMinimumCompositionItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMinimumCompositionRow) {
            throw "拍板包准备与收口规范缺少最低组成项：$($expectedGatePackageMinimumCompositionItem.Name)"
        }

        if ($matchedMinimumCompositionRow.Description -ne $expectedGatePackageMinimumCompositionItem.Description) {
            throw "拍板包准备与收口规范最低组成漂移：$($expectedGatePackageMinimumCompositionItem.Name) 期望 $($expectedGatePackageMinimumCompositionItem.Description)，实际 $($matchedMinimumCompositionRow.Description)"
        }
    }

    return [pscustomobject]@{
        GatePackageMinimumCompositionItems = @($expectedGatePackageMinimumCompositionItems)
    }
}
function Get-CanonicalGatePackageTemplateConclusionLine {
    $gatePackageTemplateDocPath = 'docs/40-执行/16-拍板包半自动模板.md'
    $expectedGatePackageTemplateConclusionLine = '当任务已具备待拍板问题、且 `gates.yaml` 仍为空时，优先使用当前仓内的拍板包半自动模板，而不是手工分别改四个文件。'

    $sectionContent = Get-FileSectionContent -FilePath $gatePackageTemplateDocPath -SectionStartMarker '## 一句话结论' -SectionEndMarker '## 脚本位置'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "拍板包半自动模板未解析到一句话结论：$gatePackageTemplateDocPath"
    }

    $summaryLines = @(
        ($sectionContent -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($summaryLines.Count -eq 0) {
        throw "拍板包半自动模板一句话结论为空：$gatePackageTemplateDocPath"
    }

    $actualGatePackageTemplateConclusionLine = $summaryLines[0]
    Assert-ExactOrderedValues -SourceValues @($actualGatePackageTemplateConclusionLine) -ExpectedValues @($expectedGatePackageTemplateConclusionLine) -Label '拍板包半自动模板一句话结论'
    return $expectedGatePackageTemplateConclusionLine
}

function Get-CanonicalGatePackageTemplateScenarioItems {
    $gatePackageTemplateDocPath = 'docs/40-执行/16-拍板包半自动模板.md'
    $expectedGatePackageTemplateScenarioItems = @(
        '已存在标准任务包 5 件套'
        '当前需要准备首个待拍板事项'
        '`gates.yaml` 仍为 `items: []`'
        '需要把任务状态切到 `waiting_gate`，并补齐拍板留痕'
    )

    $scenarioSection = Get-FileSectionContent -FilePath $gatePackageTemplateDocPath -SectionStartMarker '## 适用场景' -SectionEndMarker '## 输入项'
    if ([string]::IsNullOrWhiteSpace($scenarioSection)) {
        throw "拍板包半自动模板未解析到适用场景：$gatePackageTemplateDocPath"
    }

    $actualGatePackageTemplateScenarioItems = @(
        [regex]::Matches($scenarioSection, '(?m)^- (.+?)。?\r?$') |
            ForEach-Object { ($_.Groups[1].Value.Trim() -replace '。$','') }
    )
    Assert-ExactOrderedValues -SourceValues $actualGatePackageTemplateScenarioItems -ExpectedValues $expectedGatePackageTemplateScenarioItems -Label '拍板包半自动模板适用场景'
    return $expectedGatePackageTemplateScenarioItems
}

function Get-CanonicalGatePackageTemplateOutputState {
    $gatePackageTemplateDocPath = 'docs/40-执行/16-拍板包半自动模板.md'
    $expectedGatePackageTemplateOutputItems = @(
        [pscustomobject]@{ Name = 'gates.yaml'; Description = '生成首个待拍板事项' }
        [pscustomobject]@{ Name = 'state.yaml'; Description = '切为 `waiting_gate`' }
        [pscustomobject]@{ Name = 'decision-log.md'; Description = '追加进入拍板的决策记录与治理提示' }
        [pscustomobject]@{ Name = 'result.md'; Description = '追加待拍板事项摘要与治理复核骨架' }
    )

    $outputSection = Get-FileSectionContent -FilePath $gatePackageTemplateDocPath -SectionStartMarker '## 输出结果' -SectionEndMarker '## 使用方式'
    if ([string]::IsNullOrWhiteSpace($outputSection)) {
        throw "拍板包半自动模板未解析到输出结果：$gatePackageTemplateDocPath"
    }

    $outputRows = @(
        [regex]::Matches($outputSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value.Trim()
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($outputRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedGatePackageTemplateOutputItems | ForEach-Object { $_.Name }) -Label '拍板包半自动模板输出结果序列'
    foreach ($expectedGatePackageTemplateOutputItem in $expectedGatePackageTemplateOutputItems) {
        $matchedOutputRow = @(
            $outputRows |
                Where-Object { $_.Name -eq $expectedGatePackageTemplateOutputItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedOutputRow) {
            throw "拍板包半自动模板缺少输出结果项：$($expectedGatePackageTemplateOutputItem.Name)"
        }

        if ($matchedOutputRow.Description -ne $expectedGatePackageTemplateOutputItem.Description) {
            throw "拍板包半自动模板输出结果漂移：$($expectedGatePackageTemplateOutputItem.Name) 期望 $($expectedGatePackageTemplateOutputItem.Description)，实际 $($matchedOutputRow.Description)"
        }
    }

    return [pscustomobject]@{
        GatePackageTemplateOutputItems = @($expectedGatePackageTemplateOutputItems)
    }
}

function Get-CanonicalGatePackageResolveConclusionLine {
    $gatePackageResolveDocPath = 'docs/40-执行/17-拍板结果回写模板.md'
    $expectedGatePackageResolveConclusionLine = '当主公已经拍板，且任务需要从 `waiting_gate` 恢复推进时，优先使用当前仓内的拍板结果回写模板，而不是手工分别改四个文件。'

    $sectionContent = Get-FileSectionContent -FilePath $gatePackageResolveDocPath -SectionStartMarker '## 一句话结论' -SectionEndMarker '## 脚本位置'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "拍板结果回写模板未解析到一句话结论：$gatePackageResolveDocPath"
    }

    $summaryLines = @(
        ($sectionContent -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($summaryLines.Count -eq 0) {
        throw "拍板结果回写模板一句话结论为空：$gatePackageResolveDocPath"
    }

    $actualGatePackageResolveConclusionLine = $summaryLines[0]
    Assert-ExactOrderedValues -SourceValues @($actualGatePackageResolveConclusionLine) -ExpectedValues @($expectedGatePackageResolveConclusionLine) -Label '拍板结果回写模板一句话结论'
    return $expectedGatePackageResolveConclusionLine
}

function Get-CanonicalGatePackageResolveScenarioItems {
    $gatePackageResolveDocPath = 'docs/40-执行/17-拍板结果回写模板.md'
    $expectedGatePackageResolveScenarioItems = @(
        '`gates.yaml` 中已存在 `pending` 状态的待拍板事项'
        '主公已给出明确结论'
        '需要把任务状态从 `waiting_gate` 恢复到 `running`、`ready`、`paused` 或其他真实状态'
        '需要把拍板结果沉淀进任务包运行态'
    )

    $scenarioSection = Get-FileSectionContent -FilePath $gatePackageResolveDocPath -SectionStartMarker '## 适用场景' -SectionEndMarker '## 输入项'
    if ([string]::IsNullOrWhiteSpace($scenarioSection)) {
        throw "拍板结果回写模板未解析到适用场景：$gatePackageResolveDocPath"
    }

    $actualGatePackageResolveScenarioItems = @(
        [regex]::Matches($scenarioSection, '(?m)^- (.+?)。?\r?$') |
            ForEach-Object { ($_.Groups[1].Value.Trim() -replace '。$','') }
    )
    Assert-ExactOrderedValues -SourceValues $actualGatePackageResolveScenarioItems -ExpectedValues $expectedGatePackageResolveScenarioItems -Label '拍板结果回写模板适用场景'
    return $expectedGatePackageResolveScenarioItems
}

function Get-CanonicalGatePackageResolveOutputState {
    $gatePackageResolveDocPath = 'docs/40-执行/17-拍板结果回写模板.md'
    $expectedGatePackageResolveOutputItems = @(
        [pscustomobject]@{ Name = 'gates.yaml'; Description = '把目标 gate 从 `pending` 回写为 `decided` 或 `dropped`' }
        [pscustomobject]@{ Name = 'state.yaml'; Description = '恢复为新的真实状态，并更新 `next_action`' }
        [pscustomobject]@{ Name = 'decision-log.md'; Description = '追加回写记录与治理提示' }
        [pscustomobject]@{ Name = 'result.md'; Description = '追加拍板结果摘要与治理复核骨架' }
    )

    $outputSection = Get-FileSectionContent -FilePath $gatePackageResolveDocPath -SectionStartMarker '## 输出结果' -SectionEndMarker '## 使用方式'
    if ([string]::IsNullOrWhiteSpace($outputSection)) {
        throw "拍板结果回写模板未解析到输出结果：$gatePackageResolveDocPath"
    }

    $outputRows = @(
        [regex]::Matches($outputSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value.Trim()
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($outputRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedGatePackageResolveOutputItems | ForEach-Object { $_.Name }) -Label '拍板结果回写模板输出结果序列'
    foreach ($expectedGatePackageResolveOutputItem in $expectedGatePackageResolveOutputItems) {
        $matchedOutputRow = @(
            $outputRows |
                Where-Object { $_.Name -eq $expectedGatePackageResolveOutputItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedOutputRow) {
            throw "拍板结果回写模板缺少输出结果项：$($expectedGatePackageResolveOutputItem.Name)"
        }

        if ($matchedOutputRow.Description -ne $expectedGatePackageResolveOutputItem.Description) {
            throw "拍板结果回写模板输出结果漂移：$($expectedGatePackageResolveOutputItem.Name) 期望 $($expectedGatePackageResolveOutputItem.Description)，实际 $($matchedOutputRow.Description)"
        }
    }

    return [pscustomobject]@{
        GatePackageResolveOutputItems = @($expectedGatePackageResolveOutputItems)
    }
}

function Get-CanonicalExceptionTemplateConclusionLine {
    $exceptionTemplateDocPath = 'docs/40-执行/18-异常路径与回退模板.md'
    $expectedExceptionTemplateConclusionLine = '当任务不能继续按正常链路推进时，优先使用当前仓内的异常路径与回退模板，而不是只在聊天里说明“先停一下”。'

    $sectionContent = Get-FileSectionContent -FilePath $exceptionTemplateDocPath -SectionStartMarker '## 一句话结论' -SectionEndMarker '## 脚本位置'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "异常路径与回退模板未解析到一句话结论：$exceptionTemplateDocPath"
    }

    $summaryLines = @(
        ($sectionContent -split "`r?`n") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($summaryLines.Count -eq 0) {
        throw "异常路径与回退模板一句话结论为空：$exceptionTemplateDocPath"
    }

    $actualExceptionTemplateConclusionLine = $summaryLines[0]
    Assert-ExactOrderedValues -SourceValues @($actualExceptionTemplateConclusionLine) -ExpectedValues @($expectedExceptionTemplateConclusionLine) -Label '异常路径与回退模板一句话结论'
    return $expectedExceptionTemplateConclusionLine
}

function Get-CanonicalExceptionTemplateScenarioItems {
    $exceptionTemplateDocPath = 'docs/40-执行/18-异常路径与回退模板.md'
    $expectedExceptionTemplateScenarioItems = @(
        '当前动作失败，需暂停并保留恢复点'
        '当前改动需要回退到上一稳定状态'
        '当前任务需等待外部协助或额外信息'
        '需要把异常原因、回退范围、恢复提示写入运行态'
    )

    $scenarioSection = Get-FileSectionContent -FilePath $exceptionTemplateDocPath -SectionStartMarker '## 适用场景' -SectionEndMarker '## 输入项'
    if ([string]::IsNullOrWhiteSpace($scenarioSection)) {
        throw "异常路径与回退模板未解析到适用场景：$exceptionTemplateDocPath"
    }

    $actualExceptionTemplateScenarioItems = @(
        [regex]::Matches($scenarioSection, '(?m)^- (.+?)。?\r?$') |
            ForEach-Object { ($_.Groups[1].Value.Trim() -replace '。$','') }
    )
    Assert-ExactOrderedValues -SourceValues $actualExceptionTemplateScenarioItems -ExpectedValues $expectedExceptionTemplateScenarioItems -Label '异常路径与回退模板适用场景'
    return $expectedExceptionTemplateScenarioItems
}

function Get-CanonicalExceptionTemplateOutputState {
    $exceptionTemplateDocPath = 'docs/40-执行/18-异常路径与回退模板.md'
    $expectedExceptionTemplateOutputItems = @(
        [pscustomobject]@{ Name = 'state.yaml'; Description = '切换到异常后的真实状态，并更新 `next_action`' }
        [pscustomobject]@{ Name = 'decision-log.md'; Description = '追加异常或回退记录与治理提示' }
        [pscustomobject]@{ Name = 'result.md'; Description = '追加异常路径摘要与治理复核骨架' }
    )

    $outputSection = Get-FileSectionContent -FilePath $exceptionTemplateDocPath -SectionStartMarker '## 输出结果' -SectionEndMarker '## 使用方式'
    if ([string]::IsNullOrWhiteSpace($outputSection)) {
        throw "异常路径与回退模板未解析到输出结果：$exceptionTemplateDocPath"
    }

    $outputRows = @(
        [regex]::Matches($outputSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value.Trim()
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($outputRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedExceptionTemplateOutputItems | ForEach-Object { $_.Name }) -Label '异常路径与回退模板输出结果序列'
    foreach ($expectedExceptionTemplateOutputItem in $expectedExceptionTemplateOutputItems) {
        $matchedOutputRow = @(
            $outputRows |
                Where-Object { $_.Name -eq $expectedExceptionTemplateOutputItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedOutputRow) {
            throw "异常路径与回退模板缺少输出结果项：$($expectedExceptionTemplateOutputItem.Name)"
        }

        if ($matchedOutputRow.Description -ne $expectedExceptionTemplateOutputItem.Description) {
            throw "异常路径与回退模板输出结果漂移：$($expectedExceptionTemplateOutputItem.Name) 期望 $($expectedExceptionTemplateOutputItem.Description)，实际 $($matchedOutputRow.Description)"
        }
    }

    return [pscustomobject]@{
        ExceptionTemplateOutputItems = @($expectedExceptionTemplateOutputItems)
    }
}

function Get-CanonicalMaintenanceEntrySyncState {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenanceEntrySyncItems = @(
        [pscustomobject]@{ Name = '适用边界'; Description = '当面板入口口径、验板闭环或试跑前置门槛变化时，维护入口同步必须覆盖 `docs/40-执行/03-面板入口验收.md`' }
        [pscustomobject]@{ Name = '主入口真源'; Description = '维护入口同步主入口保持为 `docs/40-执行/13-维护层总入口.md`' }
        [pscustomobject]@{ Name = '同步范围'; Description = '同步 `README.md`、`docs/README.md`、`docs/00-导航/02-现行标准件总览.md`、`docs/40-执行/README.md`' }
        [pscustomobject]@{ Name = '收口要求'; Description = '完成同步后，确认 `03-面板入口验收.md` 与 `13-维护层总入口.md` 口径一致，并通过公开提交治理门禁' }
    )

    $maintenanceEntrySyncSection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '## 维护入口同步固定槽位' -SectionEndMarker '## 默认决策顺序'
    if ([string]::IsNullOrWhiteSpace($maintenanceEntrySyncSection)) {
        throw "维护层动作矩阵未解析到维护入口同步固定槽位：$maintenanceMatrixPath"
    }

    $maintenanceEntrySyncRows = @(
        [regex]::Matches($maintenanceEntrySyncSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($maintenanceEntrySyncRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedMaintenanceEntrySyncItems | ForEach-Object { $_.Name }) -Label '维护层动作矩阵维护入口同步固定槽位序列'
    foreach ($expectedMaintenanceEntrySyncItem in $expectedMaintenanceEntrySyncItems) {
        $matchedMaintenanceEntrySyncRow = @(
            $maintenanceEntrySyncRows |
                Where-Object { $_.Name -eq $expectedMaintenanceEntrySyncItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenanceEntrySyncRow) {
            throw "维护层动作矩阵缺少维护入口同步固定槽位：$($expectedMaintenanceEntrySyncItem.Name)"
        }

        if ($matchedMaintenanceEntrySyncRow.Description -ne $expectedMaintenanceEntrySyncItem.Description) {
            throw "维护层动作矩阵维护入口同步固定槽位漂移：$($expectedMaintenanceEntrySyncItem.Name) 期望 $($expectedMaintenanceEntrySyncItem.Description)，实际 $($matchedMaintenanceEntrySyncRow.Description)"
        }
    }

    return [pscustomobject]@{
        MaintenanceEntrySyncItems = @($expectedMaintenanceEntrySyncItems)
    }
}

function Get-CanonicalMaintenanceDecisionOrderState {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenanceDecisionOrderItems = @(
        [pscustomobject]@{ Name = '动作判类'; Description = '先判断动作属于“提交、起包、归档、入口同步、拍板准备、治理复核”哪一类' }
        [pscustomobject]@{ Name = '进入主入口'; Description = '再进入对应主入口文档，不跨文档来回跳' }
        [pscustomobject]@{ Name = '追加治理复核'; Description = '当前轮若影响公开口径或现行标准件，收口前追加一次治理审计复核' }
        [pscustomobject]@{ Name = '执行统一收口'; Description = '动作完成后，统一执行收口检查表' }
        [pscustomobject]@{ Name = '结束条件'; Description = '只有通过收口检查，才算本轮维护层动作结束' }
    )

    $maintenanceDecisionOrderSection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '## 默认决策顺序固定槽位' -SectionEndMarker '## 收口检查表'
    if ([string]::IsNullOrWhiteSpace($maintenanceDecisionOrderSection)) {
        throw "维护层动作矩阵未解析到默认决策顺序固定槽位：$maintenanceMatrixPath"
    }

    $maintenanceDecisionOrderRows = @(
        [regex]::Matches($maintenanceDecisionOrderSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($maintenanceDecisionOrderRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedMaintenanceDecisionOrderItems | ForEach-Object { $_.Name }) -Label '维护层动作矩阵默认决策顺序固定槽位序列'
    foreach ($expectedMaintenanceDecisionOrderItem in $expectedMaintenanceDecisionOrderItems) {
        $matchedMaintenanceDecisionOrderRow = @(
            $maintenanceDecisionOrderRows |
                Where-Object { $_.Name -eq $expectedMaintenanceDecisionOrderItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenanceDecisionOrderRow) {
            throw "维护层动作矩阵缺少默认决策顺序固定槽位：$($expectedMaintenanceDecisionOrderItem.Name)"
        }

        if ($matchedMaintenanceDecisionOrderRow.Description -ne $expectedMaintenanceDecisionOrderItem.Description) {
            throw "维护层动作矩阵默认决策顺序固定槽位漂移：$($expectedMaintenanceDecisionOrderItem.Name) 期望 $($expectedMaintenanceDecisionOrderItem.Description)，实际 $($matchedMaintenanceDecisionOrderRow.Description)"
        }
    }

    return [pscustomobject]@{
        MaintenanceDecisionOrderItems = @($expectedMaintenanceDecisionOrderItems)
    }
}

function Get-CanonicalMaintenanceBasicCloseoutState {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenanceBasicCloseoutItems = @(
        [pscustomobject]@{ Name = '动作归类'; Description = '已经明确本轮动作属于哪一种维护类型' }
        [pscustomobject]@{ Name = '文档沉淀'; Description = '已经把结果沉淀到当前目录内的现行文档或归档文档' }
        [pscustomobject]@{ Name = '本地留痕'; Description = '已经生成带时间戳的本地日志，写清动作、结果、理由、下一步' }
        [pscustomobject]@{ Name = '导航同步'; Description = '若新增或变更现行标准件，已经同步 `README.md`、`docs/README.md`、`docs/00-导航/02-现行标准件总览.md`、`docs/40-执行/README.md`' }
        [pscustomobject]@{ Name = '提交串行'; Description = '已经按串行流程完成 `commit`、`pull --rebase`、`push`' }
        [pscustomobject]@{ Name = '门禁通过'; Description = '若当前轮涉及公开推送，已经安装并通过本地 `pre-push` 治理门禁' }
        [pscustomobject]@{ Name = '下一步说明'; Description = '已经给出下一步建议，并说明是否需要主公拍板' }
    )

    $maintenanceBasicCloseoutSection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '### 基础收口固定槽位' -SectionEndMarker '### 治理审计补充检查'
    if ([string]::IsNullOrWhiteSpace($maintenanceBasicCloseoutSection)) {
        throw "维护层动作矩阵未解析到基础收口固定槽位：$maintenanceMatrixPath"
    }

    $maintenanceBasicCloseoutRows = @(
        [regex]::Matches($maintenanceBasicCloseoutSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($maintenanceBasicCloseoutRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedMaintenanceBasicCloseoutItems | ForEach-Object { $_.Name }) -Label '维护层动作矩阵基础收口固定槽位序列'
    foreach ($expectedMaintenanceBasicCloseoutItem in $expectedMaintenanceBasicCloseoutItems) {
        $matchedMaintenanceBasicCloseoutRow = @(
            $maintenanceBasicCloseoutRows |
                Where-Object { $_.Name -eq $expectedMaintenanceBasicCloseoutItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenanceBasicCloseoutRow) {
            throw "维护层动作矩阵缺少基础收口固定槽位：$($expectedMaintenanceBasicCloseoutItem.Name)"
        }

        if ($matchedMaintenanceBasicCloseoutRow.Description -ne $expectedMaintenanceBasicCloseoutItem.Description) {
            throw "维护层动作矩阵基础收口固定槽位漂移：$($expectedMaintenanceBasicCloseoutItem.Name) 期望 $($expectedMaintenanceBasicCloseoutItem.Description)，实际 $($matchedMaintenanceBasicCloseoutRow.Description)"
        }
    }

    return [pscustomobject]@{
        MaintenanceBasicCloseoutItems = @($expectedMaintenanceBasicCloseoutItems)
    }
}

function Get-CanonicalMaintenanceGovernanceAuditState {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenanceGovernanceAuditItems = @(
        [pscustomobject]@{ Name = '来源依据'; Description = '当前轮关键配置或关键口径，已经说明来源、版本或现行依据' }
        [pscustomobject]@{ Name = '决策留痕'; Description = '当前轮关键决策，已经在 `decision-log.md` 或现行文档中写明原因、依据与影响' }
        [pscustomobject]@{ Name = '输出追溯'; Description = '当前轮关键输出，已经能追溯到现行件、验证结果、拍板链路或异常链路' }
        [pscustomobject]@{ Name = '入口修平'; Description = '`README.md`、`docs/README.md`、`docs/00-导航/02-现行标准件总览.md`、`docs/40-执行/12-V4-Target-实施计划.md` 之间不存在口径漂移；若有，已经修平' }
        [pscustomobject]@{ Name = '边界复核'; Description = '已经复核公开仓边界，确保 `.codex/`、`logs/`、`temp/generated/`、`.vscode/`、`.serena/` 等运行态与本地工具状态不进入公开仓' }
    )

    $maintenanceGovernanceAuditSection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '### 治理审计补充检查固定槽位' -SectionEndMarker '## 公开仓边界提醒'
    if ([string]::IsNullOrWhiteSpace($maintenanceGovernanceAuditSection)) {
        throw "维护层动作矩阵未解析到治理审计补充检查固定槽位：$maintenanceMatrixPath"
    }

    $maintenanceGovernanceAuditRows = @(
        [regex]::Matches($maintenanceGovernanceAuditSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($maintenanceGovernanceAuditRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedMaintenanceGovernanceAuditItems | ForEach-Object { $_.Name }) -Label '维护层动作矩阵治理审计补充检查固定槽位序列'
    foreach ($expectedMaintenanceGovernanceAuditItem in $expectedMaintenanceGovernanceAuditItems) {
        $matchedMaintenanceGovernanceAuditRow = @(
            $maintenanceGovernanceAuditRows |
                Where-Object { $_.Name -eq $expectedMaintenanceGovernanceAuditItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenanceGovernanceAuditRow) {
            throw "维护层动作矩阵缺少治理审计补充检查固定槽位：$($expectedMaintenanceGovernanceAuditItem.Name)"
        }

        if ($matchedMaintenanceGovernanceAuditRow.Description -ne $expectedMaintenanceGovernanceAuditItem.Description) {
            throw "维护层动作矩阵治理审计补充检查固定槽位漂移：$($expectedMaintenanceGovernanceAuditItem.Name) 期望 $($expectedMaintenanceGovernanceAuditItem.Description)，实际 $($matchedMaintenanceGovernanceAuditRow.Description)"
        }
    }

    return [pscustomobject]@{
        MaintenanceGovernanceAuditItems = @($expectedMaintenanceGovernanceAuditItems)
    }
}

function Get-CanonicalMaintenancePublicBoundaryState {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenancePublicBoundaryItems = @(
        [pscustomobject]@{ Name = '公开范围'; Description = '公开仓只放正式文档、现行标准件、必要脚本与安全配置' }
        [pscustomobject]@{ Name = '本地运行态'; Description = '`.codex/chancellor/tasks/`、`.codex/chancellor/active-task.txt`、`logs/` 继续作为本地运行态与留痕区，不进入公开仓' }
        [pscustomobject]@{ Name = '依赖约束'; Description = '如未来新增维护层脚本，应优先复用当前仓目录，不引入仓外依赖' }
    )

    $maintenancePublicBoundarySection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '## 公开仓边界提醒固定槽位' -SectionEndMarker '## 推荐搭配关系'
    if ([string]::IsNullOrWhiteSpace($maintenancePublicBoundarySection)) {
        throw "维护层动作矩阵未解析到公开仓边界提醒固定槽位：$maintenanceMatrixPath"
    }

    $maintenancePublicBoundaryRows = @(
        [regex]::Matches($maintenancePublicBoundarySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($maintenancePublicBoundaryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedMaintenancePublicBoundaryItems | ForEach-Object { $_.Name }) -Label '维护层动作矩阵公开仓边界提醒固定槽位序列'
    foreach ($expectedMaintenancePublicBoundaryItem in $expectedMaintenancePublicBoundaryItems) {
        $matchedMaintenancePublicBoundaryRow = @(
            $maintenancePublicBoundaryRows |
                Where-Object { $_.Name -eq $expectedMaintenancePublicBoundaryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenancePublicBoundaryRow) {
            throw "维护层动作矩阵缺少公开仓边界提醒固定槽位：$($expectedMaintenancePublicBoundaryItem.Name)"
        }

        if ($matchedMaintenancePublicBoundaryRow.Description -ne $expectedMaintenancePublicBoundaryItem.Description) {
            throw "维护层动作矩阵公开仓边界提醒固定槽位漂移：$($expectedMaintenancePublicBoundaryItem.Name) 期望 $($expectedMaintenancePublicBoundaryItem.Description)，实际 $($matchedMaintenancePublicBoundaryRow.Description)"
        }
    }

    return [pscustomobject]@{
        MaintenancePublicBoundaryItems = @($expectedMaintenancePublicBoundaryItems)
    }
}

function Get-CanonicalMaintenancePairingState {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenancePairingItems = @(
        [pscustomobject]@{ Name = '提交动作'; Description = '先看 `10`，若影响公开口径则先补 `08 + 21`，并确认本地 `pre-push` 治理门禁已安装，做完后按本文收口' }
        [pscustomobject]@{ Name = '起包动作'; Description = '先看 `11`，脚手架会写入收口提示，做完后仍按本文逐项收口' }
        [pscustomobject]@{ Name = '归档动作'; Description = '先看 `01-执行区证据稿归档规则.md`，做完后按本文收口' }
        [pscustomobject]@{ Name = '入口变更'; Description = '先看 `13`，再按本文核对是否同步完全' }
        [pscustomobject]@{ Name = '拍板包准备'; Description = '先看 `15`，拍板完成后再按本文统一收口' }
        [pscustomobject]@{ Name = '拍板包半自动起手'; Description = '先看 `16`，生成后仍回到 `15` 与本文完成闭环' }
        [pscustomobject]@{ Name = '拍板结果回写'; Description = '先看 `17`，回写后按本文完成统一收口' }
        [pscustomobject]@{ Name = '异常路径或回退记录'; Description = '先看 `18`，记录后按本文完成统一收口' }
        [pscustomobject]@{ Name = '多 gate / 多异常裁决'; Description = '先看 `19`，先定主状态，再选单项模板落盘' }
        [pscustomobject]@{ Name = '复杂并存汇报落盘'; Description = '先看 `20`，统一写入 `result.md` 与 `decision-log.md`，必要时同步 `state.yaml`' }
        [pscustomobject]@{ Name = '关键配置来源与漂移检查落盘'; Description = '先看 `21`，再回到本文完成统一收口' }
        [pscustomobject]@{ Name = '公开口径变更前'; Description = '追加一次 `08-V4-治理审计候选规范.md` 对应的治理审计复核' }
    )

    $maintenancePairingSection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '## 推荐搭配关系固定槽位' -SectionEndMarker '## 本文档的价值'
    if ([string]::IsNullOrWhiteSpace($maintenancePairingSection)) {
        throw "维护层动作矩阵未解析到推荐搭配关系固定槽位：$maintenanceMatrixPath"
    }

    $maintenancePairingRows = @(
        [regex]::Matches($maintenancePairingSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($maintenancePairingRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedMaintenancePairingItems | ForEach-Object { $_.Name }) -Label '维护层动作矩阵推荐搭配关系固定槽位序列'
    foreach ($expectedMaintenancePairingItem in $expectedMaintenancePairingItems) {
        $matchedMaintenancePairingRow = @(
            $maintenancePairingRows |
                Where-Object { $_.Name -eq $expectedMaintenancePairingItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenancePairingRow) {
            throw "维护层动作矩阵缺少推荐搭配关系固定槽位：$($expectedMaintenancePairingItem.Name)"
        }

        if ($matchedMaintenancePairingRow.Description -ne $expectedMaintenancePairingItem.Description) {
            throw "维护层动作矩阵推荐搭配关系固定槽位漂移：$($expectedMaintenancePairingItem.Name) 期望 $($expectedMaintenancePairingItem.Description)，实际 $($matchedMaintenancePairingRow.Description)"
        }
    }

    return [pscustomobject]@{
        MaintenancePairingItems = @($expectedMaintenancePairingItems)
    }
}

function Get-CanonicalMaintenanceValueState {
    $maintenanceMatrixPath = 'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    $expectedMaintenanceValueItems = @(
        [pscustomobject]@{ Name = '固定套路'; Description = '把维护层“怎么选动作、怎么收口”写成固定套路' }
        [pscustomobject]@{ Name = '降低经验依赖'; Description = '降低维护动作对执行者个人经验的依赖' }
        [pscustomobject]@{ Name = '保留控制平面'; Description = '为后续更强自动化保留稳定的人类控制平面' }
    )

    $maintenanceValueSection = Get-FileSectionContent -FilePath $maintenanceMatrixPath -SectionStartMarker '## 本文档的价值固定槽位'
    if ([string]::IsNullOrWhiteSpace($maintenanceValueSection)) {
        throw "维护层动作矩阵未解析到本文档的价值固定槽位：$maintenanceMatrixPath"
    }

    $maintenanceValueRows = @(
        [regex]::Matches($maintenanceValueSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($maintenanceValueRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedMaintenanceValueItems | ForEach-Object { $_.Name }) -Label '维护层动作矩阵本文档的价值固定槽位序列'
    foreach ($expectedMaintenanceValueItem in $expectedMaintenanceValueItems) {
        $matchedMaintenanceValueRow = @(
            $maintenanceValueRows |
                Where-Object { $_.Name -eq $expectedMaintenanceValueItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedMaintenanceValueRow) {
            throw "维护层动作矩阵缺少本文档的价值固定槽位：$($expectedMaintenanceValueItem.Name)"
        }

        if ($matchedMaintenanceValueRow.Description -ne $expectedMaintenanceValueItem.Description) {
            throw "维护层动作矩阵本文档的价值固定槽位漂移：$($expectedMaintenanceValueItem.Name) 期望 $($expectedMaintenanceValueItem.Description)，实际 $($matchedMaintenanceValueRow.Description)"
        }
    }

    return [pscustomobject]@{
        MaintenanceValueItems = @($expectedMaintenanceValueItems)
    }
}

function Get-CanonicalConcurrentGateRuleSinglePrimaryState {
    $concurrentRuleDocPath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
    $expectedConcurrentRuleSinglePrimaryItems = @(
        [pscustomobject]@{ Name = 'state.yaml 单主状态'; Description = '`state.yaml` 永远只表达一个当前主状态' }
        [pscustomobject]@{ Name = '次要事项留档'; Description = '其他未解决事项继续分别留在 `gates.yaml`、`result.md`、`decision-log.md`，而不是争抢 `state.yaml`' }
        [pscustomobject]@{ Name = '主阻塞唯一'; Description = '若同时存在多个阻塞，必须选出“当前最先阻断推进”的主阻塞' }
    )

    $concurrentRuleSinglePrimarySection = Get-FileSectionContent -FilePath $concurrentRuleDocPath -SectionStartMarker '## 第一原则：单任务单主状态固定槽位' -SectionEndMarker '## 第二原则：按下一行动主体决定优先级'
    if ([string]::IsNullOrWhiteSpace($concurrentRuleSinglePrimarySection)) {
        throw "多 gate 与多异常并存处理规则未解析到单任务单主状态固定槽位：$concurrentRuleDocPath"
    }

    $concurrentRuleSinglePrimaryRows = @(
        [regex]::Matches($concurrentRuleSinglePrimarySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentRuleSinglePrimaryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentRuleSinglePrimaryItems | ForEach-Object { $_.Name }) -Label '多 gate 与多异常并存处理规则单任务单主状态固定槽位序列'
    foreach ($expectedConcurrentRuleSinglePrimaryItem in $expectedConcurrentRuleSinglePrimaryItems) {
        $matchedConcurrentRuleSinglePrimaryRow = @(
            $concurrentRuleSinglePrimaryRows |
                Where-Object { $_.Name -eq $expectedConcurrentRuleSinglePrimaryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentRuleSinglePrimaryRow) {
            throw "多 gate 与多异常并存处理规则缺少单任务单主状态固定槽位：$($expectedConcurrentRuleSinglePrimaryItem.Name)"
        }

        if ($matchedConcurrentRuleSinglePrimaryRow.Description -ne $expectedConcurrentRuleSinglePrimaryItem.Description) {
            throw "多 gate 与多异常并存处理规则单任务单主状态固定槽位漂移：$($expectedConcurrentRuleSinglePrimaryItem.Name) 期望 $($expectedConcurrentRuleSinglePrimaryItem.Description)，实际 $($matchedConcurrentRuleSinglePrimaryRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentRuleSinglePrimaryItems = @($expectedConcurrentRuleSinglePrimaryItems)
    }
}

function Get-CanonicalConcurrentGateRuleNextActorPriorityState {
    $concurrentRuleDocPath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
    $expectedConcurrentRuleNextActorPriorityItems = @(
        [pscustomobject]@{ Name = 'waiting_assist'; Description = '下一步必须由外部协助、额外信息或环境修复先发生' }
        [pscustomobject]@{ Name = 'waiting_gate'; Description = '下一步必须由主公拍板先发生' }
        [pscustomobject]@{ Name = 'paused'; Description = '当前执行者必须先手动停住，不允许继续推进' }
        [pscustomobject]@{ Name = 'ready_to_resume'; Description = '已具备恢复条件，只差按既定恢复点继续' }
        [pscustomobject]@{ Name = 'running / ready / verifying / done'; Description = '无主阻塞，进入正常推进态' }
    )

    $concurrentRuleNextActorPrioritySection = Get-FileSectionContent -FilePath $concurrentRuleDocPath -SectionStartMarker '## 第二原则：按下一行动主体决定优先级固定槽位' -SectionEndMarker '## 第三原则：多个 gate 并存时的主次划分'
    if ([string]::IsNullOrWhiteSpace($concurrentRuleNextActorPrioritySection)) {
        throw "多 gate 与多异常并存处理规则未解析到按下一行动主体决定优先级固定槽位：$concurrentRuleDocPath"
    }

    $concurrentRuleNextActorPriorityRows = @(
        [regex]::Matches($concurrentRuleNextActorPrioritySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentRuleNextActorPriorityRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentRuleNextActorPriorityItems | ForEach-Object { $_.Name }) -Label '多 gate 与多异常并存处理规则按下一行动主体决定优先级固定槽位序列'
    foreach ($expectedConcurrentRuleNextActorPriorityItem in $expectedConcurrentRuleNextActorPriorityItems) {
        $matchedConcurrentRuleNextActorPriorityRow = @(
            $concurrentRuleNextActorPriorityRows |
                Where-Object { $_.Name -eq $expectedConcurrentRuleNextActorPriorityItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentRuleNextActorPriorityRow) {
            throw "多 gate 与多异常并存处理规则缺少按下一行动主体决定优先级固定槽位：$($expectedConcurrentRuleNextActorPriorityItem.Name)"
        }

        if ($matchedConcurrentRuleNextActorPriorityRow.Description -ne $expectedConcurrentRuleNextActorPriorityItem.Description) {
            throw "多 gate 与多异常并存处理规则按下一行动主体决定优先级固定槽位漂移：$($expectedConcurrentRuleNextActorPriorityItem.Name) 期望 $($expectedConcurrentRuleNextActorPriorityItem.Description)，实际 $($matchedConcurrentRuleNextActorPriorityRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentRuleNextActorPriorityItems = @($expectedConcurrentRuleNextActorPriorityItems)
    }
}

function Get-CanonicalConcurrentGateRuleGatePriorityState {
    $concurrentRuleDocPath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
    $expectedConcurrentRuleGatePriorityItems = @(
        [pscustomobject]@{ Name = '主 gate 唯一'; Description = '只选一个“主 gate”进入当前汇报口径' }
        [pscustomobject]@{ Name = '直接阻断优先'; Description = '主 gate 优先选直接阻断当前下一步的 gate' }
        [pscustomobject]@{ Name = '影响范围次级'; Description = '若都能阻断当前下一步，优先选影响范围最大的 gate' }
        [pscustomobject]@{ Name = '截止时间兜底'; Description = '若影响范围仍难区分，优先选截止时间最早的 gate' }
        [pscustomobject]@{ Name = '次要待处理项留档'; Description = '未被选为主 gate 的事项继续保留在 `gates.yaml`，并在 `result.md` 中列为“次要待处理项”' }
    )

    $concurrentRuleGatePrioritySection = Get-FileSectionContent -FilePath $concurrentRuleDocPath -SectionStartMarker '## 第三原则：多个 gate 并存时的主次划分固定槽位' -SectionEndMarker '## 第四原则：gate 与异常并存时的裁决'
    if ([string]::IsNullOrWhiteSpace($concurrentRuleGatePrioritySection)) {
        throw "多 gate 与多异常并存处理规则未解析到多个 gate 并存时的主次划分固定槽位：$concurrentRuleDocPath"
    }

    $concurrentRuleGatePriorityRows = @(
        [regex]::Matches($concurrentRuleGatePrioritySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentRuleGatePriorityRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentRuleGatePriorityItems | ForEach-Object { $_.Name }) -Label '多 gate 与多异常并存处理规则多个 gate 并存时的主次划分固定槽位序列'
    foreach ($expectedConcurrentRuleGatePriorityItem in $expectedConcurrentRuleGatePriorityItems) {
        $matchedConcurrentRuleGatePriorityRow = @(
            $concurrentRuleGatePriorityRows |
                Where-Object { $_.Name -eq $expectedConcurrentRuleGatePriorityItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentRuleGatePriorityRow) {
            throw "多 gate 与多异常并存处理规则缺少多个 gate 并存时的主次划分固定槽位：$($expectedConcurrentRuleGatePriorityItem.Name)"
        }

        if ($matchedConcurrentRuleGatePriorityRow.Description -ne $expectedConcurrentRuleGatePriorityItem.Description) {
            throw "多 gate 与多异常并存处理规则多个 gate 并存时的主次划分固定槽位漂移：$($expectedConcurrentRuleGatePriorityItem.Name) 期望 $($expectedConcurrentRuleGatePriorityItem.Description)，实际 $($matchedConcurrentRuleGatePriorityRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentRuleGatePriorityItems = @($expectedConcurrentRuleGatePriorityItems)
    }
}

function Get-CanonicalConcurrentGateRuleGateExceptionDecisionState {
    $concurrentRuleDocPath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
    $expectedConcurrentRuleGateExceptionDecisionItems = @(
        [pscustomobject]@{ Name = '讨论条件未满足'; Description = '若异常导致当前连拍板包都不具备讨论条件，主状态优先用 `waiting_assist` 或 `paused`，gate 保留但不主导当前状态' }
        [pscustomobject]@{ Name = '异常收口后待拍板'; Description = '若异常已收口，当前仍需主公拍板才能继续，主状态用 `waiting_gate`' }
        [pscustomobject]@{ Name = '已拍板待恢复'; Description = '若主公已拍板，但恢复动作尚未准备好，主状态按异常结果切到 `paused` 或 `ready_to_resume`' }
        [pscustomobject]@{ Name = '拍板回退先回写'; Description = '若拍板结果本身要求回退，先完成 `decided/dropped` 回写，再按异常模板切换到新的异常态' }
    )

    $concurrentRuleGateExceptionDecisionSection = Get-FileSectionContent -FilePath $concurrentRuleDocPath -SectionStartMarker '## 第四原则：gate 与异常并存时的裁决固定槽位' -SectionEndMarker '## 第五原则：文档落盘分工'
    if ([string]::IsNullOrWhiteSpace($concurrentRuleGateExceptionDecisionSection)) {
        throw "多 gate 与多异常并存处理规则未解析到 gate 与异常并存时的裁决固定槽位：$concurrentRuleDocPath"
    }

    $concurrentRuleGateExceptionDecisionRows = @(
        [regex]::Matches($concurrentRuleGateExceptionDecisionSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentRuleGateExceptionDecisionRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentRuleGateExceptionDecisionItems | ForEach-Object { $_.Name }) -Label '多 gate 与多异常并存处理规则 gate 与异常并存时的裁决固定槽位序列'
    foreach ($expectedConcurrentRuleGateExceptionDecisionItem in $expectedConcurrentRuleGateExceptionDecisionItems) {
        $matchedConcurrentRuleGateExceptionDecisionRow = @(
            $concurrentRuleGateExceptionDecisionRows |
                Where-Object { $_.Name -eq $expectedConcurrentRuleGateExceptionDecisionItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentRuleGateExceptionDecisionRow) {
            throw "多 gate 与多异常并存处理规则缺少 gate 与异常并存时的裁决固定槽位：$($expectedConcurrentRuleGateExceptionDecisionItem.Name)"
        }

        if ($matchedConcurrentRuleGateExceptionDecisionRow.Description -ne $expectedConcurrentRuleGateExceptionDecisionItem.Description) {
            throw "多 gate 与多异常并存处理规则 gate 与异常并存时的裁决固定槽位漂移：$($expectedConcurrentRuleGateExceptionDecisionItem.Name) 期望 $($expectedConcurrentRuleGateExceptionDecisionItem.Description)，实际 $($matchedConcurrentRuleGateExceptionDecisionRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentRuleGateExceptionDecisionItems = @($expectedConcurrentRuleGateExceptionDecisionItems)
    }
}

function Get-CanonicalConcurrentGateRuleCloseoutCheckState {
    $concurrentRuleDocPath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
    $expectedConcurrentRuleCloseoutCheckItems = @(
        [pscustomobject]@{ Name = '主状态排他性'; Description = '是否已明确主状态为何不是其他候选状态' }
        [pscustomobject]@{ Name = '次要事项保留'; Description = '是否已把次要 gate 或异常留在对应文件中，没有被抹掉' }
        [pscustomobject]@{ Name = 'result.md 完整性'; Description = '是否已在 `result.md` 中写明主阻塞与次要待处理项' }
        [pscustomobject]@{ Name = 'decision-log.md 留痕'; Description = '是否已在 `decision-log.md` 中记录本轮裁决依据' }
        [pscustomobject]@{ Name = '恢复后重评'; Description = '是否已在恢复后重新评估主状态，而不是沿用旧状态' }
    )

    $concurrentRuleCloseoutCheckSection = Get-FileSectionContent -FilePath $concurrentRuleDocPath -SectionStartMarker '## 收口检查固定槽位' -SectionEndMarker '## 与现有模板的关系'
    if ([string]::IsNullOrWhiteSpace($concurrentRuleCloseoutCheckSection)) {
        throw "多 gate 与多异常并存处理规则未解析到收口检查固定槽位：$concurrentRuleDocPath"
    }

    $concurrentRuleCloseoutCheckRows = @(
        [regex]::Matches($concurrentRuleCloseoutCheckSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentRuleCloseoutCheckRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentRuleCloseoutCheckItems | ForEach-Object { $_.Name }) -Label '多 gate 与多异常并存处理规则收口检查固定槽位序列'
    foreach ($expectedConcurrentRuleCloseoutCheckItem in $expectedConcurrentRuleCloseoutCheckItems) {
        $matchedConcurrentRuleCloseoutCheckRow = @(
            $concurrentRuleCloseoutCheckRows |
                Where-Object { $_.Name -eq $expectedConcurrentRuleCloseoutCheckItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentRuleCloseoutCheckRow) {
            throw "多 gate 与多异常并存处理规则缺少收口检查固定槽位：$($expectedConcurrentRuleCloseoutCheckItem.Name)"
        }

        if ($matchedConcurrentRuleCloseoutCheckRow.Description -ne $expectedConcurrentRuleCloseoutCheckItem.Description) {
            throw "多 gate 与多异常并存处理规则收口检查固定槽位漂移：$($expectedConcurrentRuleCloseoutCheckItem.Name) 期望 $($expectedConcurrentRuleCloseoutCheckItem.Description)，实际 $($matchedConcurrentRuleCloseoutCheckRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentRuleCloseoutCheckItems = @($expectedConcurrentRuleCloseoutCheckItems)
    }
}

function Get-CanonicalConcurrentGateRuleDocumentSplitState {
    $concurrentRuleDocPath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
    $expectedConcurrentRuleDocumentSplitItems = @(
        [pscustomobject]@{ Name = 'state.yaml'; Description = '只写主状态、主下一步' }
        [pscustomobject]@{ Name = 'gates.yaml'; Description = '保留全部 gate 项及其状态' }
        [pscustomobject]@{ Name = 'decision-log.md'; Description = '记录为什么本轮选择该主状态，而不是其他状态' }
        [pscustomobject]@{ Name = 'result.md'; Description = '写清“主阻塞”“次要待处理项”“恢复顺序”' }
    )

    $concurrentRuleDocumentSplitSection = Get-FileSectionContent -FilePath $concurrentRuleDocPath -SectionStartMarker '## 第五原则：文档落盘分工固定槽位' -SectionEndMarker '## 推荐汇报顺序'
    if ([string]::IsNullOrWhiteSpace($concurrentRuleDocumentSplitSection)) {
        throw "多 gate 与多异常并存处理规则未解析到文档落盘分工固定槽位：$concurrentRuleDocPath"
    }

    $concurrentRuleDocumentSplitRows = @(
        [regex]::Matches($concurrentRuleDocumentSplitSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentRuleDocumentSplitRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentRuleDocumentSplitItems | ForEach-Object { $_.Name }) -Label '多 gate 与多异常并存处理规则文档落盘分工固定槽位序列'
    foreach ($expectedConcurrentRuleDocumentSplitItem in $expectedConcurrentRuleDocumentSplitItems) {
        $matchedConcurrentRuleDocumentSplitRow = @(
            $concurrentRuleDocumentSplitRows |
                Where-Object { $_.Name -eq $expectedConcurrentRuleDocumentSplitItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentRuleDocumentSplitRow) {
            throw "多 gate 与多异常并存处理规则缺少文档落盘分工固定槽位：$($expectedConcurrentRuleDocumentSplitItem.Name)"
        }

        if ($matchedConcurrentRuleDocumentSplitRow.Description -ne $expectedConcurrentRuleDocumentSplitItem.Description) {
            throw "多 gate 与多异常并存处理规则文档落盘分工固定槽位漂移：$($expectedConcurrentRuleDocumentSplitItem.Name) 期望 $($expectedConcurrentRuleDocumentSplitItem.Description)，实际 $($matchedConcurrentRuleDocumentSplitRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentRuleDocumentSplitItems = @($expectedConcurrentRuleDocumentSplitItems)
    }
}

function Get-CanonicalConcurrentGateRuleReportOrderState {
    $concurrentRuleDocPath = 'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
    $expectedConcurrentRuleReportOrderItems = @(
        [pscustomobject]@{ Name = '主状态结论'; Description = '先给主状态结论' }
        [pscustomobject]@{ Name = '主阻塞理由'; Description = '再说明主阻塞是谁、为什么它优先' }
        [pscustomobject]@{ Name = '次要待处理项'; Description = '再列次要待处理项' }
        [pscustomobject]@{ Name = '恢复顺序'; Description = '最后说明一旦主阻塞解除，恢复顺序是什么' }
    )

    $concurrentRuleReportOrderSection = Get-FileSectionContent -FilePath $concurrentRuleDocPath -SectionStartMarker '## 推荐汇报顺序固定槽位' -SectionEndMarker '## 收口检查'
    if ([string]::IsNullOrWhiteSpace($concurrentRuleReportOrderSection)) {
        throw "多 gate 与多异常并存处理规则未解析到推荐汇报顺序固定槽位：$concurrentRuleDocPath"
    }

    $concurrentRuleReportOrderRows = @(
        [regex]::Matches($concurrentRuleReportOrderSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentRuleReportOrderRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentRuleReportOrderItems | ForEach-Object { $_.Name }) -Label '多 gate 与多异常并存处理规则推荐汇报顺序固定槽位序列'
    foreach ($expectedConcurrentRuleReportOrderItem in $expectedConcurrentRuleReportOrderItems) {
        $matchedConcurrentRuleReportOrderRow = @(
            $concurrentRuleReportOrderRows |
                Where-Object { $_.Name -eq $expectedConcurrentRuleReportOrderItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentRuleReportOrderRow) {
            throw "多 gate 与多异常并存处理规则缺少推荐汇报顺序固定槽位：$($expectedConcurrentRuleReportOrderItem.Name)"
        }

        if ($matchedConcurrentRuleReportOrderRow.Description -ne $expectedConcurrentRuleReportOrderItem.Description) {
            throw "多 gate 与多异常并存处理规则推荐汇报顺序固定槽位漂移：$($expectedConcurrentRuleReportOrderItem.Name) 期望 $($expectedConcurrentRuleReportOrderItem.Description)，实际 $($matchedConcurrentRuleReportOrderRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentRuleReportOrderItems = @($expectedConcurrentRuleReportOrderItems)
    }
}

function Get-CanonicalConcurrentStatusReportSummaryState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportSummaryItems = @(
        [pscustomobject]@{ Name = '先选主状态'; Description = '当一个任务同时存在多个 gate、多个异常，或 gate 与异常并存时，先按 `19` 选主状态' }
        [pscustomobject]@{ Name = '一次性落盘'; Description = '再用本模板把 `result.md` 与 `decision-log.md` 一次性落盘' }
    )

    $concurrentReportSummarySection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## 一句话结论固定槽位' -SectionEndMarker '## 什么时候用'
    if ([string]::IsNullOrWhiteSpace($concurrentReportSummarySection)) {
        throw "复杂并存汇报骨架模板未解析到一句话结论固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportSummaryRows = @(
        [regex]::Matches($concurrentReportSummarySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportSummaryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportSummaryItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板一句话结论固定槽位序列'
    foreach ($expectedConcurrentReportSummaryItem in $expectedConcurrentReportSummaryItems) {
        $matchedConcurrentReportSummaryRow = @(
            $concurrentReportSummaryRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportSummaryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportSummaryRow) {
            throw "复杂并存汇报骨架模板缺少一句话结论固定槽位：$($expectedConcurrentReportSummaryItem.Name)"
        }

        if ($matchedConcurrentReportSummaryRow.Description -ne $expectedConcurrentReportSummaryItem.Description) {
            throw "复杂并存汇报骨架模板一句话结论固定槽位漂移：$($expectedConcurrentReportSummaryItem.Name) 期望 $($expectedConcurrentReportSummaryItem.Description)，实际 $($matchedConcurrentReportSummaryRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportSummaryItems = @($expectedConcurrentReportSummaryItems)
    }
}

function Get-CanonicalConcurrentStatusReportTriggerState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportTriggerItems = @(
        [pscustomobject]@{ Name = '已选主状态'; Description = '已按 `docs/40-执行/19-多 gate 与多异常并存处理规则.md` 选出主状态' }
        [pscustomobject]@{ Name = '同步复杂裁决'; Description = '当前需要把复杂裁决结果同步进任务包' }
        [pscustomobject]@{ Name = '超出单一模板'; Description = '任务已经不适合只靠单一 gate 或单一异常模板表达' }
    )

    $concurrentReportTriggerSection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## 什么时候用固定槽位' -SectionEndMarker '## 最低产出'
    if ([string]::IsNullOrWhiteSpace($concurrentReportTriggerSection)) {
        throw "复杂并存汇报骨架模板未解析到什么时候用固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportTriggerRows = @(
        [regex]::Matches($concurrentReportTriggerSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportTriggerRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportTriggerItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板什么时候用固定槽位序列'
    foreach ($expectedConcurrentReportTriggerItem in $expectedConcurrentReportTriggerItems) {
        $matchedConcurrentReportTriggerRow = @(
            $concurrentReportTriggerRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportTriggerItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportTriggerRow) {
            throw "复杂并存汇报骨架模板缺少什么时候用固定槽位：$($expectedConcurrentReportTriggerItem.Name)"
        }

        if ($matchedConcurrentReportTriggerRow.Description -ne $expectedConcurrentReportTriggerItem.Description) {
            throw "复杂并存汇报骨架模板什么时候用固定槽位漂移：$($expectedConcurrentReportTriggerItem.Name) 期望 $($expectedConcurrentReportTriggerItem.Description)，实际 $($matchedConcurrentReportTriggerRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportTriggerItems = @($expectedConcurrentReportTriggerItems)
    }
}

function Get-CanonicalConcurrentStatusReportOutputState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportOutputItems = @(
        [pscustomobject]@{ Name = '主状态落盘'; Description = '`result.md` 写清主状态、主阻塞、主阻塞原因' }
        [pscustomobject]@{ Name = '次要事项与恢复顺序'; Description = '`result.md` 列出次要待处理项、恢复顺序与治理复核' }
        [pscustomobject]@{ Name = '裁决留痕'; Description = '`decision-log.md` 记录为何选当前主状态，而不是其他候选状态' }
        [pscustomobject]@{ Name = '治理复核'; Description = '提交前按 `docs/30-方案/08-V4-治理审计候选规范.md` 追加治理审计复核' }
        [pscustomobject]@{ Name = '状态同步'; Description = '如已确定当前主推进口径，可同步更新 `state.yaml`' }
    )

    $concurrentReportOutputSection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## 最低产出固定槽位' -SectionEndMarker '## 推荐脚本入口'
    if ([string]::IsNullOrWhiteSpace($concurrentReportOutputSection)) {
        throw "复杂并存汇报骨架模板未解析到最低产出固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportOutputRows = @(
        [regex]::Matches($concurrentReportOutputSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportOutputRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportOutputItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板最低产出固定槽位序列'
    foreach ($expectedConcurrentReportOutputItem in $expectedConcurrentReportOutputItems) {
        $matchedConcurrentReportOutputRow = @(
            $concurrentReportOutputRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportOutputItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportOutputRow) {
            throw "复杂并存汇报骨架模板缺少最低产出固定槽位：$($expectedConcurrentReportOutputItem.Name)"
        }

        if ($matchedConcurrentReportOutputRow.Description -ne $expectedConcurrentReportOutputItem.Description) {
            throw "复杂并存汇报骨架模板最低产出固定槽位漂移：$($expectedConcurrentReportOutputItem.Name) 期望 $($expectedConcurrentReportOutputItem.Description)，实际 $($matchedConcurrentReportOutputRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportOutputItems = @($expectedConcurrentReportOutputItems)
    }
}

function Get-CanonicalConcurrentStatusReportScriptEntryState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportScriptEntryItems = @(
        [pscustomobject]@{ Name = '脚本'; Description = '`.codex/chancellor/write-concurrent-status-report.ps1`' }
        [pscustomobject]@{ Name = '规则'; Description = '`docs/40-执行/19-多 gate 与多异常并存处理规则.md`' }
        [pscustomobject]@{ Name = '治理'; Description = '`docs/30-方案/08-V4-治理审计候选规范.md`' }
        [pscustomobject]@{ Name = '收口'; Description = '`docs/40-执行/14-维护层动作矩阵与收口检查表.md`' }
    )

    $concurrentReportScriptEntrySection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## 推荐脚本入口固定槽位' -SectionEndMarker '## `result.md` 推荐骨架'
    if ([string]::IsNullOrWhiteSpace($concurrentReportScriptEntrySection)) {
        throw "复杂并存汇报骨架模板未解析到推荐脚本入口固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportScriptEntryRows = @(
        [regex]::Matches($concurrentReportScriptEntrySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportScriptEntryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportScriptEntryItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板推荐脚本入口固定槽位序列'
    foreach ($expectedConcurrentReportScriptEntryItem in $expectedConcurrentReportScriptEntryItems) {
        $matchedConcurrentReportScriptEntryRow = @(
            $concurrentReportScriptEntryRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportScriptEntryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportScriptEntryRow) {
            throw "复杂并存汇报骨架模板缺少推荐脚本入口固定槽位：$($expectedConcurrentReportScriptEntryItem.Name)"
        }

        if ($matchedConcurrentReportScriptEntryRow.Description -ne $expectedConcurrentReportScriptEntryItem.Description) {
            throw "复杂并存汇报骨架模板推荐脚本入口固定槽位漂移：$($expectedConcurrentReportScriptEntryItem.Name) 期望 $($expectedConcurrentReportScriptEntryItem.Description)，实际 $($matchedConcurrentReportScriptEntryRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportScriptEntryItems = @($expectedConcurrentReportScriptEntryItems)
    }
}

function Get-CanonicalConcurrentStatusReportSemiAutoWriteState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportSemiAutoWriteItems = @(
        [pscustomobject]@{ Name = 'TaskId'; Description = '目标任务包 ID' }
        [pscustomobject]@{ Name = 'PrimaryStatus'; Description = '当前唯一主状态' }
        [pscustomobject]@{ Name = 'PrimaryBlocker'; Description = '当前最先阻断推进的事项' }
        [pscustomobject]@{ Name = 'PrimaryReason'; Description = '为什么它比其他事项更优先' }
        [pscustomobject]@{ Name = 'SecondaryItems'; Description = '次要待处理项列表' }
        [pscustomobject]@{ Name = 'RecoverySteps'; Description = '主阻塞解除后的恢复顺序' }
        [pscustomobject]@{ Name = 'NextAction'; Description = '本轮最小下一步' }
        [pscustomobject]@{ Name = 'DecisionBasis'; Description = '本轮裁决依据' }
        [pscustomobject]@{ Name = 'RejectedCandidates'; Description = '本轮未选状态及原因' }
        [pscustomobject]@{ Name = 'SyncState'; Description = '如当前主状态已确定，允许同步更新 `state.yaml`' }
    )

    $concurrentReportSemiAutoWriteSection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## 半自动写入建议固定槽位' -SectionEndMarker '## 维护层价值'
    if ([string]::IsNullOrWhiteSpace($concurrentReportSemiAutoWriteSection)) {
        throw "复杂并存汇报骨架模板未解析到半自动写入建议固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportSemiAutoWriteRows = @(
        [regex]::Matches($concurrentReportSemiAutoWriteSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportSemiAutoWriteRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportSemiAutoWriteItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板半自动写入建议固定槽位序列'
    foreach ($expectedConcurrentReportSemiAutoWriteItem in $expectedConcurrentReportSemiAutoWriteItems) {
        $matchedConcurrentReportSemiAutoWriteRow = @(
            $concurrentReportSemiAutoWriteRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportSemiAutoWriteItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportSemiAutoWriteRow) {
            throw "复杂并存汇报骨架模板缺少半自动写入建议固定槽位：$($expectedConcurrentReportSemiAutoWriteItem.Name)"
        }

        if ($matchedConcurrentReportSemiAutoWriteRow.Description -ne $expectedConcurrentReportSemiAutoWriteItem.Description) {
            throw "复杂并存汇报骨架模板半自动写入建议固定槽位漂移：$($expectedConcurrentReportSemiAutoWriteItem.Name) 期望 $($expectedConcurrentReportSemiAutoWriteItem.Description)，实际 $($matchedConcurrentReportSemiAutoWriteRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportSemiAutoWriteItems = @($expectedConcurrentReportSemiAutoWriteItems)
    }
}

function Get-CanonicalConcurrentStatusReportResultSkeletonState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportResultSkeletonItems = @(
        [pscustomobject]@{ Name = '主状态'; Description = '写清当前唯一主状态' }
        [pscustomobject]@{ Name = '主阻塞'; Description = '写清当前最先阻断推进的事项' }
        [pscustomobject]@{ Name = '主阻塞原因'; Description = '写清为什么当前主阻塞比其他事项更优先' }
        [pscustomobject]@{ Name = '主规则'; Description = '写明 `docs/40-执行/19-多 gate 与多异常并存处理规则.md`' }
        [pscustomobject]@{ Name = '骨架模板'; Description = '写明 `docs/40-执行/20-复杂并存汇报骨架模板.md`' }
        [pscustomobject]@{ Name = '治理复核入口'; Description = '写明 `docs/30-方案/08-V4-治理审计候选规范.md`' }
        [pscustomobject]@{ Name = '次要待处理项'; Description = '列出仍需保留的次要待处理项' }
        [pscustomobject]@{ Name = '恢复顺序'; Description = '列出主阻塞解除后的恢复顺序' }
        [pscustomobject]@{ Name = '下一步'; Description = '写清本轮最小下一步' }
        [pscustomobject]@{ Name = '治理复核结果'; Description = '写清主状态依据、次要待处理项、口径漂移与治理审计复核状态' }
    )

    $concurrentReportResultSkeletonSection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## `result.md` 推荐骨架固定槽位' -SectionEndMarker '## `decision-log.md` 推荐骨架'
    if ([string]::IsNullOrWhiteSpace($concurrentReportResultSkeletonSection)) {
        throw "复杂并存汇报骨架模板未解析到 result.md 推荐骨架固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportResultSkeletonRows = @(
        [regex]::Matches($concurrentReportResultSkeletonSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportResultSkeletonRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportResultSkeletonItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板 result.md 推荐骨架固定槽位序列'
    foreach ($expectedConcurrentReportResultSkeletonItem in $expectedConcurrentReportResultSkeletonItems) {
        $matchedConcurrentReportResultSkeletonRow = @(
            $concurrentReportResultSkeletonRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportResultSkeletonItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportResultSkeletonRow) {
            throw "复杂并存汇报骨架模板缺少 result.md 推荐骨架固定槽位：$($expectedConcurrentReportResultSkeletonItem.Name)"
        }

        if ($matchedConcurrentReportResultSkeletonRow.Description -ne $expectedConcurrentReportResultSkeletonItem.Description) {
            throw "复杂并存汇报骨架模板 result.md 推荐骨架固定槽位漂移：$($expectedConcurrentReportResultSkeletonItem.Name) 期望 $($expectedConcurrentReportResultSkeletonItem.Description)，实际 $($matchedConcurrentReportResultSkeletonRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportResultSkeletonItems = @($expectedConcurrentReportResultSkeletonItems)
    }
}

function Get-CanonicalConcurrentStatusReportDecisionLogSkeletonState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportDecisionLogSkeletonItems = @(
        [pscustomobject]@{ Name = '决策'; Description = '写明记录复杂并存场景当前主状态' }
        [pscustomobject]@{ Name = '主阻塞'; Description = '写清当前主阻塞事项' }
        [pscustomobject]@{ Name = '原因'; Description = '写清为什么当前异常或 gate 先阻断推进' }
        [pscustomobject]@{ Name = '证据'; Description = '写明依据 `docs/40-执行/19-多 gate 与多异常并存处理规则.md`、`docs/40-执行/20-复杂并存汇报骨架模板.md` 与 `docs/30-方案/08-V4-治理审计候选规范.md` 形成统一汇报骨架' }
        [pscustomobject]@{ Name = '未选状态'; Description = '列出本轮未选状态及原因' }
        [pscustomobject]@{ Name = '裁决依据'; Description = '写清先按下一行动主体判断主状态，再按影响范围与阻断顺序确定主阻塞' }
        [pscustomobject]@{ Name = '治理提示'; Description = '写清复杂裁决结果与提交前应确认主状态依据、次要待处理项与公开边界已完成治理审计复核' }
        [pscustomobject]@{ Name = '影响'; Description = '写清 `result.md` 与 `decision-log.md` 是否已统一口径' }
    )

    $concurrentReportDecisionLogSkeletonSection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## `decision-log.md` 推荐骨架固定槽位' -SectionEndMarker '## 半自动写入建议'
    if ([string]::IsNullOrWhiteSpace($concurrentReportDecisionLogSkeletonSection)) {
        throw "复杂并存汇报骨架模板未解析到 decision-log.md 推荐骨架固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportDecisionLogSkeletonRows = @(
        [regex]::Matches($concurrentReportDecisionLogSkeletonSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportDecisionLogSkeletonRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportDecisionLogSkeletonItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板 decision-log.md 推荐骨架固定槽位序列'
    foreach ($expectedConcurrentReportDecisionLogSkeletonItem in $expectedConcurrentReportDecisionLogSkeletonItems) {
        $matchedConcurrentReportDecisionLogSkeletonRow = @(
            $concurrentReportDecisionLogSkeletonRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportDecisionLogSkeletonItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportDecisionLogSkeletonRow) {
            throw "复杂并存汇报骨架模板缺少 decision-log.md 推荐骨架固定槽位：$($expectedConcurrentReportDecisionLogSkeletonItem.Name)"
        }

        if ($matchedConcurrentReportDecisionLogSkeletonRow.Description -ne $expectedConcurrentReportDecisionLogSkeletonItem.Description) {
            throw "复杂并存汇报骨架模板 decision-log.md 推荐骨架固定槽位漂移：$($expectedConcurrentReportDecisionLogSkeletonItem.Name) 期望 $($expectedConcurrentReportDecisionLogSkeletonItem.Description)，实际 $($matchedConcurrentReportDecisionLogSkeletonRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportDecisionLogSkeletonItems = @($expectedConcurrentReportDecisionLogSkeletonItems)
    }
}

function Get-CanonicalConcurrentStatusReportValueState {
    $concurrentReportDocPath = 'docs/40-执行/20-复杂并存汇报骨架模板.md'
    $expectedConcurrentReportValueItems = @(
        [pscustomobject]@{ Name = '固定骨架'; Description = '把复杂并存场景从口头汇报变成固定骨架' }
        [pscustomobject]@{ Name = '口径稳定'; Description = '让 `state.yaml`、`result.md`、`decision-log.md` 的口径更稳定' }
        [pscustomobject]@{ Name = '最小治理复核'; Description = '让复杂裁决结果在提交前也能挂上最小治理复核' }
        [pscustomobject]@{ Name = '自动化入口'; Description = '为后续更强的复杂裁决自动化保留轻量入口' }
    )

    $concurrentReportValueSection = Get-FileSectionContent -FilePath $concurrentReportDocPath -SectionStartMarker '## 维护层价值固定槽位'
    if ([string]::IsNullOrWhiteSpace($concurrentReportValueSection)) {
        throw "复杂并存汇报骨架模板未解析到维护层价值固定槽位：$concurrentReportDocPath"
    }

    $concurrentReportValueRows = @(
        [regex]::Matches($concurrentReportValueSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($concurrentReportValueRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConcurrentReportValueItems | ForEach-Object { $_.Name }) -Label '复杂并存汇报骨架模板维护层价值固定槽位序列'
    foreach ($expectedConcurrentReportValueItem in $expectedConcurrentReportValueItems) {
        $matchedConcurrentReportValueRow = @(
            $concurrentReportValueRows |
                Where-Object { $_.Name -eq $expectedConcurrentReportValueItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConcurrentReportValueRow) {
            throw "复杂并存汇报骨架模板缺少维护层价值固定槽位：$($expectedConcurrentReportValueItem.Name)"
        }

        if ($matchedConcurrentReportValueRow.Description -ne $expectedConcurrentReportValueItem.Description) {
            throw "复杂并存汇报骨架模板维护层价值固定槽位漂移：$($expectedConcurrentReportValueItem.Name) 期望 $($expectedConcurrentReportValueItem.Description)，实际 $($matchedConcurrentReportValueRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConcurrentReportValueItems = @($expectedConcurrentReportValueItems)
    }
}

function Get-CanonicalGovernanceConfigReviewSummaryState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewSummaryItems = @(
        [pscustomobject]@{ Name = '先回看来源'; Description = '当本轮涉及现行标准件、公开口径、关键边界或提交推送时，先回看来源' }
        [pscustomobject]@{ Name = '统一落盘复核'; Description = '再用本模板把配置来源、版本依据与漂移检查统一落进任务包' }
    )

    $configReviewSummarySection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## 一句话结论固定槽位' -SectionEndMarker '## 什么时候用'
    if ([string]::IsNullOrWhiteSpace($configReviewSummarySection)) {
        throw "关键配置来源与漂移复核模板未解析到一句话结论固定槽位：$configReviewDocPath"
    }

    $configReviewSummaryRows = @(
        [regex]::Matches($configReviewSummarySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewSummaryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewSummaryItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板一句话结论固定槽位序列'
    foreach ($expectedConfigReviewSummaryItem in $expectedConfigReviewSummaryItems) {
        $matchedConfigReviewSummaryRow = @(
            $configReviewSummaryRows |
                Where-Object { $_.Name -eq $expectedConfigReviewSummaryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewSummaryRow) {
            throw "关键配置来源与漂移复核模板缺少一句话结论固定槽位：$($expectedConfigReviewSummaryItem.Name)"
        }

        if ($matchedConfigReviewSummaryRow.Description -ne $expectedConfigReviewSummaryItem.Description) {
            throw "关键配置来源与漂移复核模板一句话结论固定槽位漂移：$($expectedConfigReviewSummaryItem.Name) 期望 $($expectedConfigReviewSummaryItem.Description)，实际 $($matchedConfigReviewSummaryRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewSummaryItems = @($expectedConfigReviewSummaryItems)
    }
}

function Get-CanonicalGovernanceConfigReviewTriggerState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewTriggerItems = @(
        [pscustomobject]@{ Name = '现行标准件变更'; Description = '当前轮新增或修改了现行标准件' }
        [pscustomobject]@{ Name = '公开改动提交前'; Description = '当前轮准备提交并推送公开改动' }
        [pscustomobject]@{ Name = '解释现行依据'; Description = '当前轮需要解释“现在为什么以这份口径为准”' }
        [pscustomobject]@{ Name = '怀疑存在漂移'; Description = '当前轮怀疑入口文档、实施计划、冻结边界之间存在漂移' }
        [pscustomobject]@{ Name = '提交前预检落盘'; Description = '当前轮正在执行 `docs/40-执行/10-本地安全提交流程.md`，需要把提交前预检结果落盘' }
    )

    $configReviewTriggerSection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## 什么时候用固定槽位' -SectionEndMarker '## 最低产出'
    if ([string]::IsNullOrWhiteSpace($configReviewTriggerSection)) {
        throw "关键配置来源与漂移复核模板未解析到什么时候用固定槽位：$configReviewDocPath"
    }

    $configReviewTriggerRows = @(
        [regex]::Matches($configReviewTriggerSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewTriggerRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewTriggerItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板什么时候用固定槽位序列'
    foreach ($expectedConfigReviewTriggerItem in $expectedConfigReviewTriggerItems) {
        $matchedConfigReviewTriggerRow = @(
            $configReviewTriggerRows |
                Where-Object { $_.Name -eq $expectedConfigReviewTriggerItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewTriggerRow) {
            throw "关键配置来源与漂移复核模板缺少什么时候用固定槽位：$($expectedConfigReviewTriggerItem.Name)"
        }

        if ($matchedConfigReviewTriggerRow.Description -ne $expectedConfigReviewTriggerItem.Description) {
            throw "关键配置来源与漂移复核模板什么时候用固定槽位漂移：$($expectedConfigReviewTriggerItem.Name) 期望 $($expectedConfigReviewTriggerItem.Description)，实际 $($matchedConfigReviewTriggerRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewTriggerItems = @($expectedConfigReviewTriggerItems)
    }
}

function Get-CanonicalGovernanceConfigReviewResultSkeletonState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewResultSkeletonItems = @(
        [pscustomobject]@{ Name = '复核模板'; Description = '写明 `docs/40-执行/21-关键配置来源与漂移复核模板.md`' }
        [pscustomobject]@{ Name = '治理规范'; Description = '写明 `docs/30-方案/08-V4-治理审计候选规范.md`' }
        [pscustomobject]@{ Name = '配置来源'; Description = '写清当前公开入口与现行件导航入口' }
        [pscustomobject]@{ Name = '版本与现行依据'; Description = '写清当前推进顺序依据与冻结边界依据' }
        [pscustomobject]@{ Name = '漂移检查'; Description = '写清公开入口与现行件导航是否一致，以及实施计划与冻结边界是否冲突' }
        [pscustomobject]@{ Name = '复核结论'; Description = '写清当前是否存在需先修平的公开漂移' }
        [pscustomobject]@{ Name = '下一步'; Description = '写清是否继续提交前收口' }
    )

    $configReviewResultSkeletonSection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## `result.md` 推荐骨架固定槽位' -SectionEndMarker '## `decision-log.md` 推荐骨架'
    if ([string]::IsNullOrWhiteSpace($configReviewResultSkeletonSection)) {
        throw "关键配置来源与漂移复核模板未解析到 result.md 推荐骨架固定槽位：$configReviewDocPath"
    }

    $configReviewResultSkeletonRows = @(
        [regex]::Matches($configReviewResultSkeletonSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewResultSkeletonRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewResultSkeletonItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板 result.md 推荐骨架固定槽位序列'
    foreach ($expectedConfigReviewResultSkeletonItem in $expectedConfigReviewResultSkeletonItems) {
        $matchedConfigReviewResultSkeletonRow = @(
            $configReviewResultSkeletonRows |
                Where-Object { $_.Name -eq $expectedConfigReviewResultSkeletonItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewResultSkeletonRow) {
            throw "关键配置来源与漂移复核模板缺少 result.md 推荐骨架固定槽位：$($expectedConfigReviewResultSkeletonItem.Name)"
        }

        if ($matchedConfigReviewResultSkeletonRow.Description -ne $expectedConfigReviewResultSkeletonItem.Description) {
            throw "关键配置来源与漂移复核模板 result.md 推荐骨架固定槽位漂移：$($expectedConfigReviewResultSkeletonItem.Name) 期望 $($expectedConfigReviewResultSkeletonItem.Description)，实际 $($matchedConfigReviewResultSkeletonRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewResultSkeletonItems = @($expectedConfigReviewResultSkeletonItems)
    }
}

function Get-CanonicalGovernanceConfigReviewDecisionLogSkeletonState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewDecisionLogSkeletonItems = @(
        [pscustomobject]@{ Name = '决策'; Description = '写明记录关键配置来源与漂移复核' }
        [pscustomobject]@{ Name = '证据'; Description = '写明依据 `docs/40-执行/21-关键配置来源与漂移复核模板.md` 与 `docs/30-方案/08-V4-治理审计候选规范.md` 形成统一复核口径' }
        [pscustomobject]@{ Name = '结论'; Description = '写清当前是否存在需先修平的公开漂移' }
        [pscustomobject]@{ Name = '影响'; Description = '写清是否可以继续进入提交前收口' }
    )

    $configReviewDecisionLogSkeletonSection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## `decision-log.md` 推荐骨架固定槽位' -SectionEndMarker '## 长期价值'
    if ([string]::IsNullOrWhiteSpace($configReviewDecisionLogSkeletonSection)) {
        throw "关键配置来源与漂移复核模板未解析到 decision-log.md 推荐骨架固定槽位：$configReviewDocPath"
    }

    $configReviewDecisionLogSkeletonRows = @(
        [regex]::Matches($configReviewDecisionLogSkeletonSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewDecisionLogSkeletonRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewDecisionLogSkeletonItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板 decision-log.md 推荐骨架固定槽位序列'
    foreach ($expectedConfigReviewDecisionLogSkeletonItem in $expectedConfigReviewDecisionLogSkeletonItems) {
        $matchedConfigReviewDecisionLogSkeletonRow = @(
            $configReviewDecisionLogSkeletonRows |
                Where-Object { $_.Name -eq $expectedConfigReviewDecisionLogSkeletonItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewDecisionLogSkeletonRow) {
            throw "关键配置来源与漂移复核模板缺少 decision-log.md 推荐骨架固定槽位：$($expectedConfigReviewDecisionLogSkeletonItem.Name)"
        }

        if ($matchedConfigReviewDecisionLogSkeletonRow.Description -ne $expectedConfigReviewDecisionLogSkeletonItem.Description) {
            throw "关键配置来源与漂移复核模板 decision-log.md 推荐骨架固定槽位漂移：$($expectedConfigReviewDecisionLogSkeletonItem.Name) 期望 $($expectedConfigReviewDecisionLogSkeletonItem.Description)，实际 $($matchedConfigReviewDecisionLogSkeletonRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewDecisionLogSkeletonItems = @($expectedConfigReviewDecisionLogSkeletonItems)
    }
}

function Get-CanonicalGovernanceConfigReviewLongTermValueState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewLongTermValueItems = @(
        [pscustomobject]@{ Name = '可重复落盘'; Description = '把治理审计从原则推进到可重复落盘' }
        [pscustomobject]@{ Name = '提前暴露漂移'; Description = '提前暴露入口口径漂移，而不是提交后再补洞' }
        [pscustomobject]@{ Name = '目录内自含'; Description = '保持当前目录内自含，不引入额外系统或依赖' }
    )

    $configReviewLongTermValueSection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## 长期价值固定槽位'
    if ([string]::IsNullOrWhiteSpace($configReviewLongTermValueSection)) {
        throw "关键配置来源与漂移复核模板未解析到长期价值固定槽位：$configReviewDocPath"
    }

    $configReviewLongTermValueRows = @(
        [regex]::Matches($configReviewLongTermValueSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewLongTermValueRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewLongTermValueItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板长期价值固定槽位序列'
    foreach ($expectedConfigReviewLongTermValueItem in $expectedConfigReviewLongTermValueItems) {
        $matchedConfigReviewLongTermValueRow = @(
            $configReviewLongTermValueRows |
                Where-Object { $_.Name -eq $expectedConfigReviewLongTermValueItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewLongTermValueRow) {
            throw "关键配置来源与漂移复核模板缺少长期价值固定槽位：$($expectedConfigReviewLongTermValueItem.Name)"
        }

        if ($matchedConfigReviewLongTermValueRow.Description -ne $expectedConfigReviewLongTermValueItem.Description) {
            throw "关键配置来源与漂移复核模板长期价值固定槽位漂移：$($expectedConfigReviewLongTermValueItem.Name) 期望 $($expectedConfigReviewLongTermValueItem.Description)，实际 $($matchedConfigReviewLongTermValueRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewLongTermValueItems = @($expectedConfigReviewLongTermValueItems)
    }
}

function Get-CanonicalGovernanceConfigReviewOutputState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewOutputItems = @(
        [pscustomobject]@{ Name = '结果落盘'; Description = '`result.md` 写清配置来源、版本与现行依据、漂移检查、复核结论' }
        [pscustomobject]@{ Name = '决策留痕'; Description = '`decision-log.md` 记录本轮复核依据与影响' }
        [pscustomobject]@{ Name = '先修平再提交'; Description = '复核后如发现漂移，优先修平口径，再继续提交' }
    )

    $configReviewOutputSection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## 最低产出固定槽位' -SectionEndMarker '## 推荐脚本入口'
    if ([string]::IsNullOrWhiteSpace($configReviewOutputSection)) {
        throw "关键配置来源与漂移复核模板未解析到最低产出固定槽位：$configReviewDocPath"
    }

    $configReviewOutputRows = @(
        [regex]::Matches($configReviewOutputSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewOutputRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewOutputItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板最低产出固定槽位序列'
    foreach ($expectedConfigReviewOutputItem in $expectedConfigReviewOutputItems) {
        $matchedConfigReviewOutputRow = @(
            $configReviewOutputRows |
                Where-Object { $_.Name -eq $expectedConfigReviewOutputItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewOutputRow) {
            throw "关键配置来源与漂移复核模板缺少最低产出固定槽位：$($expectedConfigReviewOutputItem.Name)"
        }

        if ($matchedConfigReviewOutputRow.Description -ne $expectedConfigReviewOutputItem.Description) {
            throw "关键配置来源与漂移复核模板最低产出固定槽位漂移：$($expectedConfigReviewOutputItem.Name) 期望 $($expectedConfigReviewOutputItem.Description)，实际 $($matchedConfigReviewOutputRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewOutputItems = @($expectedConfigReviewOutputItems)
    }
}

function Get-CanonicalGovernanceConfigReviewScriptEntryState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewScriptEntryItems = @(
        [pscustomobject]@{ Name = '脚本入口'; Description = '`.codex/chancellor/write-governance-config-review.ps1`' }
        [pscustomobject]@{ Name = '治理依据'; Description = '`docs/30-方案/08-V4-治理审计候选规范.md`' }
        [pscustomobject]@{ Name = '收口入口'; Description = '`docs/40-执行/14-维护层动作矩阵与收口检查表.md`' }
    )

    $configReviewScriptEntrySection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## 推荐脚本入口固定槽位' -SectionEndMarker '## 推荐复核来源'
    if ([string]::IsNullOrWhiteSpace($configReviewScriptEntrySection)) {
        throw "关键配置来源与漂移复核模板未解析到推荐脚本入口固定槽位：$configReviewDocPath"
    }

    $configReviewScriptEntryRows = @(
        [regex]::Matches($configReviewScriptEntrySection, '(?m)^- `([^`]+)`：(.+?)\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = $_.Groups[2].Value.Trim()
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewScriptEntryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewScriptEntryItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板推荐脚本入口固定槽位序列'
    foreach ($expectedConfigReviewScriptEntryItem in $expectedConfigReviewScriptEntryItems) {
        $matchedConfigReviewScriptEntryRow = @(
            $configReviewScriptEntryRows |
                Where-Object { $_.Name -eq $expectedConfigReviewScriptEntryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewScriptEntryRow) {
            throw "关键配置来源与漂移复核模板缺少推荐脚本入口固定槽位：$($expectedConfigReviewScriptEntryItem.Name)"
        }

        if ($matchedConfigReviewScriptEntryRow.Description -ne $expectedConfigReviewScriptEntryItem.Description) {
            throw "关键配置来源与漂移复核模板推荐脚本入口固定槽位漂移：$($expectedConfigReviewScriptEntryItem.Name) 期望 $($expectedConfigReviewScriptEntryItem.Description)，实际 $($matchedConfigReviewScriptEntryRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewScriptEntryItems = @($expectedConfigReviewScriptEntryItems)
    }
}

function Get-CanonicalGovernanceConfigReviewSourceState {
    $configReviewDocPath = 'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    $expectedConfigReviewSourceItems = @(
        [pscustomobject]@{ Name = '公开入口'; Description = '`README.md`' }
        [pscustomobject]@{ Name = '文档总览入口'; Description = '`docs/README.md`' }
        [pscustomobject]@{ Name = '现行件导航'; Description = '`docs/00-导航/02-现行标准件总览.md`' }
        [pscustomobject]@{ Name = '推进顺序依据'; Description = '`docs/40-执行/12-V4-Target-实施计划.md`' }
        [pscustomobject]@{ Name = '冻结边界依据'; Description = '`docs/30-方案/05-V4-Target-冻结清单.md`' }
    )

    $configReviewSourceSection = Get-FileSectionContent -FilePath $configReviewDocPath -SectionStartMarker '## 推荐复核来源固定槽位' -SectionEndMarker '## `result.md` 推荐骨架'
    if ([string]::IsNullOrWhiteSpace($configReviewSourceSection)) {
        throw "关键配置来源与漂移复核模板未解析到推荐复核来源固定槽位：$configReviewDocPath"
    }

    $configReviewSourceRows = @(
        [regex]::Matches($configReviewSourceSection, '(?m)^- `([^`]+)`：(.+?)\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = $_.Groups[2].Value.Trim()
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($configReviewSourceRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedConfigReviewSourceItems | ForEach-Object { $_.Name }) -Label '关键配置来源与漂移复核模板推荐复核来源固定槽位序列'
    foreach ($expectedConfigReviewSourceItem in $expectedConfigReviewSourceItems) {
        $matchedConfigReviewSourceRow = @(
            $configReviewSourceRows |
                Where-Object { $_.Name -eq $expectedConfigReviewSourceItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedConfigReviewSourceRow) {
            throw "关键配置来源与漂移复核模板缺少推荐复核来源固定槽位：$($expectedConfigReviewSourceItem.Name)"
        }

        if ($matchedConfigReviewSourceRow.Description -ne $expectedConfigReviewSourceItem.Description) {
            throw "关键配置来源与漂移复核模板推荐复核来源固定槽位漂移：$($expectedConfigReviewSourceItem.Name) 期望 $($expectedConfigReviewSourceItem.Description)，实际 $($matchedConfigReviewSourceRow.Description)"
        }
    }

    return [pscustomobject]@{
        ConfigReviewSourceItems = @($expectedConfigReviewSourceItems)
    }
}

function Get-CanonicalMaintenanceCapabilityDocPaths {
    $maintenanceGuidePath = 'docs/40-执行/13-维护层总入口.md'
    $maintenanceCapabilityPaths = Get-OrderedUniqueValues -Values @(
        Get-OrderedNormalizedDocPathsFromSection -FilePath $maintenanceGuidePath -RegexPattern '`(docs/(?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/(?:03|10|11|14|15|16|17|18|19|20|21)-[^`]+\.md)|(?:90-归档/01-[^`]+\.md)))`' -PathPrefix '' -SectionStartMarker '## 当前维护层能力' -SectionEndMarker '## 维护层主线真源'
    )

    if ($maintenanceCapabilityPaths.Count -eq 0) {
        throw "维护层总入口未解析到维护能力文档：$maintenanceGuidePath"
    }

    $expectedMaintenanceCapabilityPaths = @(
        'docs/40-执行/10-本地安全提交流程.md'
        'docs/40-执行/11-任务包半自动起包.md'
        'docs/90-归档/01-执行区证据稿归档规则.md'
        'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
        'docs/40-执行/15-拍板包准备与收口规范.md'
        'docs/40-执行/16-拍板包半自动模板.md'
        'docs/40-执行/17-拍板结果回写模板.md'
        'docs/40-执行/18-异常路径与回退模板.md'
        'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
        'docs/40-执行/20-复杂并存汇报骨架模板.md'
        'docs/40-执行/03-面板入口验收.md'
        'docs/30-方案/08-V4-治理审计候选规范.md'
        'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    )
    Assert-ExactOrderedValues -SourceValues $maintenanceCapabilityPaths -ExpectedValues $expectedMaintenanceCapabilityPaths -Label '维护层补充能力真源'

    $maintenanceCapabilityOrderPaths = @(
        'docs/40-执行/03-面板入口验收.md'
        'docs/30-方案/08-V4-治理审计候选规范.md'
        'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    )
    $maintenanceCapabilityOrderSlice = @(
        $maintenanceCapabilityPaths |
            Where-Object { $_ -in $maintenanceCapabilityOrderPaths }
    )
    Assert-ExactOrderedValues -SourceValues $maintenanceCapabilityOrderSlice -ExpectedValues $maintenanceCapabilityOrderPaths -Label '维护层补充能力真源'
    return $maintenanceCapabilityPaths
}

function Get-CanonicalMaintenanceLifecycleEntryPaths {
    $maintenanceGuidePath = 'docs/40-执行/13-维护层总入口.md'
    $maintenanceLifecyclePaths = Get-OrderedUniqueValues -Values @(
        Get-OrderedNormalizedDocPathsFromSection -FilePath $maintenanceGuidePath -RegexPattern '(?m)^(docs/40-执行/[0-9]{2}-[^\r\n]+\.md)\s*$' -PathPrefix '' -SectionStartMarker '## 维护层主线真源' -SectionEndMarker '## 推荐使用顺序'
    )

    if ($maintenanceLifecyclePaths.Count -eq 0) {
        throw "维护层总入口未解析到维护层主线真源：$maintenanceGuidePath"
    }

    $requiredMaintenanceLifecyclePaths = @(
        'docs/40-执行/13-维护层总入口.md'
        'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
        'docs/40-执行/15-拍板包准备与收口规范.md'
        'docs/40-执行/16-拍板包半自动模板.md'
        'docs/40-执行/17-拍板结果回写模板.md'
        'docs/40-执行/18-异常路径与回退模板.md'
        'docs/40-执行/19-多 gate 与多异常并存处理规则.md'
        'docs/40-执行/20-复杂并存汇报骨架模板.md'
        'docs/40-执行/21-关键配置来源与漂移复核模板.md'
    )
    Assert-RequiredPathsPresent -SourcePaths $maintenanceLifecyclePaths -RequiredPaths $requiredMaintenanceLifecyclePaths -Label '维护层主线真源'
    return $maintenanceLifecyclePaths
}

function Get-CanonicalDocsReadmeMaintenanceSourceSummaryLines {
    $docsReadmePath = 'docs/README.md'
    $expectedDocsReadmeMaintenanceSourceSummaryLines = @(
        '`40-执行/13-维护层总入口.md` 是维护层唯一对外总入口。'
        '维护层主线顺序以 `40-执行/13-维护层总入口.md` 的 `维护层主线真源` 为准，`docs/README.md` 不再重复抄整套主线清单。'
        '维护层补充能力以 `40-执行/13-维护层总入口.md` 的 `当前维护层能力` 为准；需要细项时直接查看该文档。'
    )

    $sectionContent = Get-FileSectionContent -FilePath $docsReadmePath -SectionStartMarker '## 维护层入口' -SectionEndMarker '## 当前分层'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "docs/README 未解析到维护层入口真源说明：$docsReadmePath"
    }

    $maintenanceSourceSummaryLines = @(
        [regex]::Matches($sectionContent, '(?m)^- (.+?)\r?$') |
            ForEach-Object { $_.Groups[1].Value.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($maintenanceSourceSummaryLines.Count -eq 0) {
        throw "docs/README 未解析到维护层入口真源说明列点：$docsReadmePath"
    }

    Assert-ExactOrderedValues -SourceValues $maintenanceSourceSummaryLines -ExpectedValues $expectedDocsReadmeMaintenanceSourceSummaryLines -Label 'docs/README 维护层入口真源说明'
    return $expectedDocsReadmeMaintenanceSourceSummaryLines
}

function Get-CanonicalMaintenanceGuideRecommendedOrderItems {
    $maintenanceGuidePath = 'docs/40-执行/13-维护层总入口.md'
    $expectedMaintenanceGuideRecommendedOrderItems = @(
        '先判断自己是在“提交”“起包”“归档”“入口同步”“拍板准备”还是“治理复核”'
        '再进入对应的单项规则文档、动作矩阵或拍板规范'
        '当前轮若影响公开口径或现行标准件，收口前追加一次治理审计复核'
        '若当前轮还需要说明配置来源、版本依据或漂移检查，继续使用 `21` 追加落盘'
        '若当前轮准备推送公开改动，确认 `pre-push` 治理门禁已安装并可自动触发'
        '完成动作后，按收口检查表确认本轮已闭环'
        '最后再回到现行标准件总览确认入口是否需要同步'
    )

    $maintenanceGuideRecommendedOrderSection = Get-FileSectionContent -FilePath $maintenanceGuidePath -SectionStartMarker '## 推荐使用顺序' -SectionEndMarker '## 当前默认原则'
    if ([string]::IsNullOrWhiteSpace($maintenanceGuideRecommendedOrderSection)) {
        throw "维护层总入口未解析到推荐使用顺序：$maintenanceGuidePath"
    }

    $maintenanceGuideRecommendedOrderItems = @(
        [regex]::Matches($maintenanceGuideRecommendedOrderSection, '(?m)^\d+\. (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($maintenanceGuideRecommendedOrderItems.Count -eq 0) {
        throw "维护层总入口未解析到推荐使用顺序列点：$maintenanceGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $maintenanceGuideRecommendedOrderItems -ExpectedValues $expectedMaintenanceGuideRecommendedOrderItems -Label '维护层总入口推荐使用顺序摘要序列'
    return $expectedMaintenanceGuideRecommendedOrderItems
}

function Get-CanonicalMaintenanceGuideDefaultPrinciplesItems {
    $maintenanceGuidePath = 'docs/40-执行/13-维护层总入口.md'
    $expectedMaintenanceGuideDefaultPrinciplesItems = @(
        '维护层动作继续视为维护层，不对普通面板使用者外露复杂终端流程'
        '维护层动作优先复用当前仓已有规则与脚本，不另起外部依赖'
        '维护层动作完成后，如影响入口口径，应同步更新总览、首页或 docs 入口'
    )

    $maintenanceGuideDefaultPrinciplesSection = Get-FileSectionContent -FilePath $maintenanceGuidePath -SectionStartMarker '## 当前默认原则' -SectionEndMarker '## 什么时候优先看这份入口'
    if ([string]::IsNullOrWhiteSpace($maintenanceGuideDefaultPrinciplesSection)) {
        throw "维护层总入口未解析到当前默认原则：$maintenanceGuidePath"
    }

    $maintenanceGuideDefaultPrinciplesItems = @(
        [regex]::Matches($maintenanceGuideDefaultPrinciplesSection, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($maintenanceGuideDefaultPrinciplesItems.Count -eq 0) {
        throw "维护层总入口未解析到当前默认原则列点：$maintenanceGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $maintenanceGuideDefaultPrinciplesItems -ExpectedValues $expectedMaintenanceGuideDefaultPrinciplesItems -Label '维护层总入口当前默认原则摘要序列'
    return $expectedMaintenanceGuideDefaultPrinciplesItems
}

function Get-CanonicalMaintenanceGuideTriggerItems {
    $maintenanceGuidePath = 'docs/40-执行/13-维护层总入口.md'
    $expectedMaintenanceGuideTriggerItems = @(
        '不确定该先看哪份维护文档时'
        '准备开始维护层动作前'
        '需要交接维护动作给下一位执行者时'
    )

    $maintenanceGuideTriggerSection = Get-FileSectionContent -FilePath $maintenanceGuidePath -SectionStartMarker '## 什么时候优先看这份入口' -SectionEndMarker '## 本文档的价值'
    if ([string]::IsNullOrWhiteSpace($maintenanceGuideTriggerSection)) {
        throw "维护层总入口未解析到什么时候优先看这份入口：$maintenanceGuidePath"
    }

    $maintenanceGuideTriggerItems = @(
        [regex]::Matches($maintenanceGuideTriggerSection, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($maintenanceGuideTriggerItems.Count -eq 0) {
        throw "维护层总入口未解析到什么时候优先看这份入口列点：$maintenanceGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $maintenanceGuideTriggerItems -ExpectedValues $expectedMaintenanceGuideTriggerItems -Label '维护层总入口什么时候优先看这份入口摘要序列'
    return $expectedMaintenanceGuideTriggerItems
}

function Get-CanonicalMaintenanceGuideValueItems {
    $maintenanceGuidePath = 'docs/40-执行/13-维护层总入口.md'
    $expectedMaintenanceGuideValueItems = @(
        '把零散维护规则收成单一入口'
        '缩短维护层上手路径'
        '降低因找错入口而导致的误操作概率'
    )

    $maintenanceGuideValueSection = Get-FileSectionContent -FilePath $maintenanceGuidePath -SectionStartMarker '## 本文档的价值'
    if ([string]::IsNullOrWhiteSpace($maintenanceGuideValueSection)) {
        throw "维护层总入口未解析到本文档的价值：$maintenanceGuidePath"
    }

    $maintenanceGuideValueItems = @(
        [regex]::Matches($maintenanceGuideValueSection, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($maintenanceGuideValueItems.Count -eq 0) {
        throw "维护层总入口未解析到本文档的价值列点：$maintenanceGuidePath"
    }

    Assert-ExactOrderedValues -SourceValues $maintenanceGuideValueItems -ExpectedValues $expectedMaintenanceGuideValueItems -Label '维护层总入口本文档的价值摘要序列'
    return $expectedMaintenanceGuideValueItems
}

function Get-CanonicalTargetLifecycleEntryPaths {
    $targetPlanPath = 'docs/40-执行/12-V4-Target-实施计划.md'
    $targetLifecyclePaths = Get-OrderedUniqueValues -Values @(
        Get-OrderedNormalizedDocPathsFromSection -FilePath $targetPlanPath -RegexPattern '(?m)^(docs/(?:20-决策|30-方案|40-执行)/[^\r\n]+\.md)\s*$' -PathPrefix '' -SectionStartMarker '## Target 主线真源' -SectionEndMarker '## 推荐推进顺序'
    )

    if ($targetLifecyclePaths.Count -eq 0) {
        throw "Target 实施计划未解析到 Target 主线真源：$targetPlanPath"
    }

    $targetLifecycleSlice = Get-OrderedPathSlice -SourcePaths $targetLifecyclePaths -StartPath 'docs/20-决策/02-V4-Target-进入决议.md' -EndPath 'docs/40-执行/12-V4-Target-实施计划.md' -SliceLabel 'Target 主线真源'
    $requiredTargetLifecyclePaths = @(
        'docs/20-决策/02-V4-Target-进入决议.md'
        'docs/30-方案/04-V4-Target-蓝图.md'
        'docs/30-方案/05-V4-Target-冻结清单.md'
        'docs/30-方案/06-V4-OS-参考技术采纳评估.md'
        'docs/30-方案/07-V4-规划策略候选规范.md'
        'docs/30-方案/08-V4-治理审计候选规范.md'
        'docs/40-执行/12-V4-Target-实施计划.md'
    )
    Assert-ExactOrderedValues -SourceValues $targetLifecycleSlice -ExpectedValues $requiredTargetLifecyclePaths -Label 'Target 主线真源'
    return $requiredTargetLifecyclePaths
}

function Get-CanonicalDocsReadmeTargetSourceSummaryLines {
    $docsReadmePath = 'docs/README.md'
    $expectedDocsReadmeTargetSourceSummaryLines = @(
        '`40-执行/12-V4-Target-实施计划.md` 是 Target 主线唯一对外总入口。'
        'Target 主线入口以 `40-执行/12-V4-Target-实施计划.md` 的 `Target 主线真源` 为准，`docs/README.md` 不再重复抄整套主线清单。'
        'Target 推进顺序以 `40-执行/12-V4-Target-实施计划.md` 的 `推荐推进顺序` 为准；需要细项时直接查看该文档。'
    )

    $sectionContent = Get-FileSectionContent -FilePath $docsReadmePath -SectionStartMarker '## Target 主线入口' -SectionEndMarker '## 维护层入口'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "docs/README 未解析到 Target 主线入口真源说明：$docsReadmePath"
    }

    $targetSourceSummaryLines = @(
        [regex]::Matches($sectionContent, '(?m)^- (.+?)\r?$') |
            ForEach-Object { $_.Groups[1].Value.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($targetSourceSummaryLines.Count -eq 0) {
        throw "docs/README 未解析到 Target 主线入口真源说明列点：$docsReadmePath"
    }

    Assert-ExactOrderedValues -SourceValues $targetSourceSummaryLines -ExpectedValues $expectedDocsReadmeTargetSourceSummaryLines -Label 'docs/README Target 主线入口真源说明'
    return $expectedDocsReadmeTargetSourceSummaryLines
}

function Get-CanonicalStartupPhaseEntryPaths {
    $restartGuidePath = 'docs/00-导航/01-V4-重启导读.md'
    $startupPhasePaths = Get-OrderedUniqueValues -Values @(
        Get-OrderedNormalizedDocPathsFromSection -FilePath $restartGuidePath -RegexPattern '(?m)^(docs/(?:00-导航|10-输入材料|20-决策|30-方案)/[^\r\n]+\.md)\s*$' -PathPrefix '' -SectionStartMarker '## 启动阶段真源' -SectionEndMarker '## '
    )

    if ($startupPhasePaths.Count -eq 0) {
        throw "重启导读未解析到启动阶段真源：$restartGuidePath"
    }

    $startupPhaseSlice = Get-OrderedPathSlice -SourcePaths $startupPhasePaths -StartPath 'docs/00-导航/02-现行标准件总览.md' -EndPath 'docs/30-方案/03-V4-MVP边界清单.md' -SliceLabel '启动阶段真源'
    $requiredStartupPhasePaths = @(
        'docs/00-导航/02-现行标准件总览.md'
        'docs/00-导航/01-V4-重启导读.md'
        'docs/20-决策/01-V4-重启ADR.md'
        'docs/10-输入材料/01-旧仓必需资产清单.md'
        'docs/30-方案/01-V4-最小目录蓝图.md'
        'docs/30-方案/02-V4-目录锁定清单.md'
        'docs/30-方案/03-V4-MVP边界清单.md'
    )
    Assert-ExactOrderedValues -SourceValues $startupPhaseSlice -ExpectedValues $requiredStartupPhasePaths -Label '启动阶段真源'
    return $requiredStartupPhasePaths
}

function Get-CanonicalRestartGuideEntryPaths {
    $restartGuidePath = 'docs/00-导航/01-V4-重启导读.md'
    $restartGuideCanonicalEntryPaths = Get-OrderedUniqueValues -Values @(
        Get-OrderedNormalizedDocPathsFromSection -FilePath $restartGuidePath -RegexPattern '`(docs/[^`]+\.md)`' -PathPrefix '' -SectionStartMarker '## 先看什么' -SectionEndMarker '## '
    )

    if ($restartGuideCanonicalEntryPaths.Count -eq 0) {
        throw "重启导读未解析到核心入口真源：$restartGuidePath"
    }

    $requiredRestartGuideEntryPaths = @(
        'docs/00-导航/02-现行标准件总览.md'
        'docs/20-决策/01-V4-重启ADR.md'
        'docs/10-输入材料/01-旧仓必需资产清单.md'
        'docs/30-方案/01-V4-最小目录蓝图.md'
        'docs/30-方案/02-V4-目录锁定清单.md'
        'docs/30-方案/03-V4-MVP边界清单.md'
        'docs/40-执行/01-任务包规范.md'
        'docs/40-执行/02-任务包模板.md'
        'docs/40-执行/03-面板入口验收.md'
        'docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md'
        'docs/reference/02-仓库卫生与命名规范.md'
    )
    Assert-ExactOrderedValues -SourceValues $restartGuideCanonicalEntryPaths -ExpectedValues $requiredRestartGuideEntryPaths -Label '重启导读核心入口真源'
    return $requiredRestartGuideEntryPaths
}

function Get-CanonicalDocsReadmeStartupSourceSummaryLines {
    $docsReadmePath = 'docs/README.md'
    $expectedDocsReadmeStartupSourceSummaryLines = @(
        '`00-导航/01-V4-重启导读.md` 是启动阶段唯一对外总入口。'
        '启动阶段核心入口以 `00-导航/01-V4-重启导读.md` 的 `先看什么` 为准，`docs/README.md` 不再重复抄整套入口清单。'
        '启动阶段顺序以 `00-导航/01-V4-重启导读.md` 的 `启动阶段真源` 为准；需要细项时直接查看该文档。'
    )

    $sectionContent = Get-FileSectionContent -FilePath $docsReadmePath -SectionStartMarker '## 启动阶段入口' -SectionEndMarker '## 继续深读'
    if ([string]::IsNullOrWhiteSpace($sectionContent)) {
        throw "docs/README 未解析到启动阶段入口真源说明：$docsReadmePath"
    }

    $startupSourceSummaryLines = @(
        [regex]::Matches($sectionContent, '(?m)^- (.+?)\r?$') |
            ForEach-Object { $_.Groups[1].Value.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($startupSourceSummaryLines.Count -eq 0) {
        throw "docs/README 未解析到启动阶段入口真源说明列点：$docsReadmePath"
    }

    Assert-ExactOrderedValues -SourceValues $startupSourceSummaryLines -ExpectedValues $expectedDocsReadmeStartupSourceSummaryLines -Label 'docs/README 启动阶段入口真源说明'
    return $expectedDocsReadmeStartupSourceSummaryLines
}

function Get-CanonicalCoreGovernanceRuleSourcePaths {
    $localSafeFlowPath = 'docs/40-执行/10-本地安全提交流程.md'
    $coreGovernanceRuleSourcePaths = Get-OrderedUniqueValues -Values @(
        Get-OrderedNormalizedDocPathsFromSection -FilePath $localSafeFlowPath -RegexPattern '`(docs/(?:reference|30-方案|40-执行)/[^`]+\.md)`' -PathPrefix '' -SectionStartMarker '## 核心治理规则入口真源' -SectionEndMarker '## 公开提交硬门禁'
    )

    if ($coreGovernanceRuleSourcePaths.Count -eq 0) {
        throw "核心治理规则入口真源区块未解析到规则文档：$localSafeFlowPath"
    }

    $requiredCoreGovernanceRuleSourcePaths = @(
        'docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md'
        'docs/reference/02-仓库卫生与命名规范.md'
        'docs/30-方案/02-V4-目录锁定清单.md'
        'docs/30-方案/08-V4-治理审计候选规范.md'
        'docs/40-执行/10-本地安全提交流程.md'
        'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
    )
    Assert-RequiredPathsPresent -SourcePaths $coreGovernanceRuleSourcePaths -RequiredPaths $requiredCoreGovernanceRuleSourcePaths -Label '核心治理规则入口真源'
    return $coreGovernanceRuleSourcePaths
}

function Get-BlockedPathRulesFromLocalSafeFlow {
    $localSafeFlowPath = 'docs/40-执行/10-本地安全提交流程.md'
    $blockedPathBlock = Get-CodeBlockContentFromSection -FilePath $localSafeFlowPath -SectionStartMarker '## 公开提交禁止路径真源' -SectionEndMarker '## 公开提交硬门禁'
    if ([string]::IsNullOrWhiteSpace($blockedPathBlock)) {
        throw "本地安全提交流程缺少公开提交禁止路径真源区块：$localSafeFlowPath"
    }

    $blockedExactPaths = New-Object System.Collections.Generic.List[string]
    $blockedPrefixes = New-Object System.Collections.Generic.List[string]
    $blockedPrefixExceptions = New-Object System.Collections.Generic.List[string]
    foreach ($ruleLine in ($blockedPathBlock -split "`r?`n")) {
        $trimmedRuleLine = $ruleLine.Trim()
        if ($trimmedRuleLine -eq '') {
            continue
        }

        if ($trimmedRuleLine.StartsWith('exact:')) {
            $blockedExactPaths.Add((ConvertTo-NormalizedPath $trimmedRuleLine.Substring(6)))
            continue
        }

        if ($trimmedRuleLine.StartsWith('prefix:')) {
            $blockedPrefixes.Add((ConvertTo-NormalizedPath $trimmedRuleLine.Substring(7)))
            continue
        }

        if ($trimmedRuleLine.StartsWith('except:')) {
            $blockedPrefixExceptions.Add((ConvertTo-NormalizedPath $trimmedRuleLine.Substring(7)))
            continue
        }

        throw "公开提交禁止路径真源存在无法解析的规则：$trimmedRuleLine"
    }

    if (($blockedExactPaths.Count + $blockedPrefixes.Count) -eq 0) {
        throw "公开提交禁止路径真源未解析到阻断规则：$localSafeFlowPath"
    }

    $orderedBlockedExactPaths = Get-OrderedUniqueValues -Values @($blockedExactPaths)
    $orderedBlockedPrefixes = Get-OrderedUniqueValues -Values @($blockedPrefixes)
    $orderedBlockedPrefixExceptions = Get-OrderedUniqueValues -Values @($blockedPrefixExceptions)

    $blockedPrefixOrderPaths = @(
        'logs/'
        'temp/generated/'
    )
    $blockedPrefixOrderSlice = @(
        $orderedBlockedPrefixes |
            Where-Object { $_ -in $blockedPrefixOrderPaths }
    )
    if ($blockedPrefixOrderSlice.Count -eq $blockedPrefixOrderPaths.Count) {
        Assert-ExactOrderedValues -SourceValues $blockedPrefixOrderSlice -ExpectedValues $blockedPrefixOrderPaths -Label '公开提交禁止路径前缀真源'
    }

    $blockedExceptionOrderPaths = @(
        '.codex/chancellor/tasks/README.md'
        'logs/README.md'
        'temp/generated/README.md'
    )
    $blockedExceptionOrderSlice = @(
        $orderedBlockedPrefixExceptions |
            Where-Object { $_ -in $blockedExceptionOrderPaths }
    )
    if ($blockedExceptionOrderSlice.Count -eq $blockedExceptionOrderPaths.Count) {
        Assert-ExactOrderedValues -SourceValues $blockedExceptionOrderSlice -ExpectedValues $blockedExceptionOrderPaths -Label '公开提交禁止路径例外真源'
    }

    return [pscustomobject]@{
        BlockedExactPaths = $orderedBlockedExactPaths
        BlockedPrefixes = $orderedBlockedPrefixes
        BlockedPrefixExceptions = $orderedBlockedPrefixExceptions
    }
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

function Assert-RequiredPathsPresent {
    param(
        [string[]]$SourcePaths,
        [string[]]$RequiredPaths,
        [string]$Label = '关键路径集合'
    )

    $orderedSourcePaths = Get-OrderedUniqueValues -Values @($SourcePaths)
    $orderedRequiredPaths = Get-OrderedUniqueValues -Values @($RequiredPaths)
    $missingRequiredPaths = @(
        $orderedRequiredPaths |
            Where-Object { $_ -notin $orderedSourcePaths }
    )

    if ($missingRequiredPaths.Count -gt 0) {
        throw "$Label 缺少必需路径：$($missingRequiredPaths -join '、')"
    }
}

function Assert-ExactOrderedValues {
    param(
        [string[]]$SourceValues,
        [string[]]$ExpectedValues,
        [string]$Label = '有序值集合'
    )

    $orderedSourceValues = Get-OrderedUniqueValues -Values @($SourceValues)
    $orderedExpectedValues = Get-OrderedUniqueValues -Values @($ExpectedValues)
    $missingExpectedValues = @(
        $orderedExpectedValues |
            Where-Object { $_ -notin $orderedSourceValues }
    )
    if ($missingExpectedValues.Count -gt 0) {
        throw "$Label 缺少必需项：$($missingExpectedValues -join '、')"
    }

    $unexpectedSourceValues = @(
        $orderedSourceValues |
            Where-Object { $_ -notin $orderedExpectedValues }
    )
    if ($unexpectedSourceValues.Count -gt 0) {
        throw "$Label 存在未批准项：$($unexpectedSourceValues -join '、')"
    }

    for ($index = 0; $index -lt $orderedExpectedValues.Count; $index++) {
        if ($orderedSourceValues[$index] -ne $orderedExpectedValues[$index]) {
            $expectedOrderText = $orderedExpectedValues -join ' → '
            $actualOrderText = $orderedSourceValues -join ' → '
            throw "$Label 顺序漂移：期望 $expectedOrderText；实际 $actualOrderText"
        }
    }
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

$precomputedViolationMessages = New-Object System.Collections.Generic.List[string]
$coreGovernanceRuleSourcePaths = @()
try {
    $coreGovernanceRuleSourcePaths = Get-CanonicalCoreGovernanceRuleSourcePaths
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$requiredPolicyFiles = @($coreGovernanceRuleSourcePaths)
$allowedTrackedRootEntries = @()
try {
    $allowedTrackedRootEntries = Get-ApprovedTopLevelEntriesFromLockList
    if ($allowedTrackedRootEntries.Count -eq 0) {
        throw '目录锁定清单未解析到批准顶层项。'
    }
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$allowedTrackedCodexFiles = @()
try {
    $allowedTrackedCodexFiles = Get-ApprovedTrackedCodexFilesFromLockList
    if ($allowedTrackedCodexFiles.Count -eq 0) {
        throw '目录锁定清单未解析到允许跟踪的运行态文件。'
    }
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$codexHomeExportConsistencyState = $null
try {
    $codexHomeExportConsistencyState = Get-CodexHomeExportConsistencyState
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalPanelCommandState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceMatrixConclusionLine)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceMatrixRows)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceEntrySyncState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceDecisionOrderState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceBasicCloseoutState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceGovernanceAuditState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenancePublicBoundaryState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenancePairingState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceValueState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageConclusionLine)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageTriggerItems)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageMinimumCompositionState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageTemplateConclusionLine)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageTemplateScenarioItems)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageTemplateOutputState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageResolveConclusionLine)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageResolveScenarioItems)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGatePackageResolveOutputState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalExceptionTemplateConclusionLine)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalExceptionTemplateScenarioItems)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalExceptionTemplateOutputState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentGateRuleSinglePrimaryState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentGateRuleNextActorPriorityState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentGateRuleGatePriorityState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentGateRuleGateExceptionDecisionState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentGateRuleCloseoutCheckState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentGateRuleDocumentSplitState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentGateRuleReportOrderState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportSummaryState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportTriggerState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportOutputState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportScriptEntryState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportSemiAutoWriteState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportResultSkeletonState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportDecisionLogSkeletonState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalConcurrentStatusReportValueState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewSummaryState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewTriggerState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewResultSkeletonState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewDecisionLogSkeletonState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewLongTermValueState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewOutputState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewScriptEntryState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalGovernanceConfigReviewSourceState)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$blockedExactPaths = @()
$blockedPrefixes = @()
$blockedPrefixExceptions = @()
try {
    $blockedPathRules = Get-BlockedPathRulesFromLocalSafeFlow
    $blockedExactPaths = @($blockedPathRules.BlockedExactPaths)
    $blockedPrefixes = @($blockedPathRules.BlockedPrefixes)
    $blockedPrefixExceptions = @($blockedPathRules.BlockedPrefixExceptions)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$publicExecEntryChecks = @(
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
$publicExecOrderEntryChecks = @(
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览执行区现行标准件入口'
        RegexPattern = 'docs/40-执行/([0-9]{2}-[^`]+\.md)'
    }
)
$criticalPublicRuleEntryPaths = @($coreGovernanceRuleSourcePaths)
$publicRuleEntryChecks = @(
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
$navOverviewReadingOrderPaths = Get-OrderedUniqueValues -Values @(
    Get-OrderedNormalizedDocPathsFromSection -FilePath 'docs/00-导航/02-现行标准件总览.md' -RegexPattern '`(docs/(?:20-决策|30-方案|40-执行)/[^`]+\.md)`' -PathPrefix '' -SectionStartMarker '## 阅读顺序建议' -SectionEndMarker '## 什么不是现行标准件'
)
$ruleOrderEntryChecks = @(
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览规则入口'
        RegexPattern = '`(docs/reference/[^`]+\.md)`'
        PathPrefix = ''
        SectionStartMarker = '### 入口与背景'
        SectionEndMarker = '## 阅读顺序建议'
    }
)
$criticalRuleOrderPaths = @(
    'docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md'
    'docs/reference/02-仓库卫生与命名规范.md'
)
$criticalCoreGovernanceRuleSourceOrderPaths = @(
    'docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md'
    'docs/reference/02-仓库卫生与命名规范.md'
    'docs/30-方案/02-V4-目录锁定清单.md'
    'docs/30-方案/08-V4-治理审计候选规范.md'
    'docs/40-执行/10-本地安全提交流程.md'
    'docs/40-执行/14-维护层动作矩阵与收口检查表.md'
)
$coreGovernanceRuleSourceEntryChecks = @(
    @{
        Path = 'docs/40-执行/10-本地安全提交流程.md'
        Label = '核心治理规则入口真源'
        RegexPattern = '`(docs/(?:reference|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = ''
        SectionStartMarker = '## 核心治理规则入口真源'
        SectionEndMarker = '## 公开提交禁止路径真源'
    }
)
$agentConstraintEntryChecks = @(
    @{
        Path = 'AGENTS.md'
        Label = 'AGENTS 核心约束入口'
        RegexPattern = '`((?:docs/reference|docs/30-方案)/[^`]+\.md)`'
        PathPrefix = ''
    }
)
$criticalAgentConstraintPaths = @(
    'docs/reference/01-反屎山AI研发执行总纲（Codex专用浓缩对照版）.md'
    'docs/30-方案/02-V4-目录锁定清单.md'
)
$criticalTargetLifecycleEntryPaths = @()
try {
    $criticalTargetLifecycleEntryPaths = Get-CanonicalTargetLifecycleEntryPaths
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalDocsReadmeTargetSourceSummaryLines)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$publicTargetEntryChecks = @(
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览 Target 主线入口'
        RegexPattern = '`(docs/(?:20-决策|30-方案|40-执行)/[^`]+\.md)`'
        PathPrefix = ''
    }
)
$criticalMaintenanceLifecycleEntryPaths = @()
try {
    $criticalMaintenanceLifecycleEntryPaths = Get-CanonicalMaintenanceLifecycleEntryPaths
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalMaintenanceCapabilityDocPaths)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalDocsReadmeMaintenanceSourceSummaryLines)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$canonicalMaintenanceGuideRecommendedOrderItems = @()
try {
    $canonicalMaintenanceGuideRecommendedOrderItems = Get-CanonicalMaintenanceGuideRecommendedOrderItems
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$canonicalMaintenanceGuideDefaultPrinciplesItems = @()
try {
    $canonicalMaintenanceGuideDefaultPrinciplesItems = Get-CanonicalMaintenanceGuideDefaultPrinciplesItems
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$canonicalMaintenanceGuideTriggerItems = @()
try {
    $canonicalMaintenanceGuideTriggerItems = Get-CanonicalMaintenanceGuideTriggerItems
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$canonicalMaintenanceGuideValueItems = @()
try {
    $canonicalMaintenanceGuideValueItems = Get-CanonicalMaintenanceGuideValueItems
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$publicMaintenanceEntryChecks = @(
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
try {
    [void](Get-CanonicalRestartGuideEntryPaths)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalStartupPhaseEntryPaths)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
try {
    [void](Get-CanonicalDocsReadmeStartupSourceSummaryLines)
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}

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

if ($null -ne $codexHomeExportConsistencyState) {
    $codexHomeManagedVersionViolation = Get-CodexHomeManagedVersionDisciplineViolation -ChangedPaths $changedPathList -IncludedFiles $codexHomeExportConsistencyState.IncludedFiles
    if (-not [string]::IsNullOrWhiteSpace($codexHomeManagedVersionViolation)) {
        $violationMessages.Add($codexHomeManagedVersionViolation)
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

$canonicalExecStandardDocNames = @()
try {
    $canonicalExecStandardDocNames = Get-CanonicalExecStandardDocNames
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecReadmeTitleLine = ''
try {
    $canonicalExecReadmeTitleLine = Get-CanonicalExecReadmeTitleLine
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecReadmeTopSummaryItems = @()
try {
    $canonicalExecReadmeTopSummaryItems = Get-CanonicalExecReadmeTopSummaryItems
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecReadmeFooterNoteItems = @()
try {
    $canonicalExecReadmeFooterNoteItems = Get-CanonicalExecReadmeFooterNoteItems
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecStandardGuideConclusionLine = ''
try {
    $canonicalExecStandardGuideConclusionLine = Get-CanonicalExecStandardGuideConclusionLine
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecStandardGuideEvidenceDraftItems = @()
try {
    $canonicalExecStandardGuideEvidenceDraftItems = Get-CanonicalExecStandardGuideEvidenceDraftItems
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecStandardGuideUsageOrderItems = @()
try {
    $canonicalExecStandardGuideUsageOrderItems = Get-CanonicalExecStandardGuideUsageOrderItems
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecStandardGuideNamingRuleItems = @()
try {
    $canonicalExecStandardGuideNamingRuleItems = Get-CanonicalExecStandardGuideNamingRuleItems
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecStandardGuideArchivedEvidenceItems = @()
try {
    $canonicalExecStandardGuideArchivedEvidenceItems = Get-CanonicalExecStandardGuideArchivedEvidenceItems
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
$canonicalExecStandardGuideValueItems = @()
try {
    $canonicalExecStandardGuideValueItems = Get-CanonicalExecStandardGuideValueItems
}
catch {
    $violationMessages.Add($_.Exception.Message)
}
if ($canonicalExecStandardDocNames.Count -gt 0) {
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
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $publicExecOrderEntryChecks -CriticalEntryPaths $canonicalExecStandardDocNames -MissingFileLabel '执行区现行标准件入口文件' -MissingEntryLabel '执行区现行标准件入口' -OrderDriftLabel '执行区现行标准件入口顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
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
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $ruleOrderEntryChecks -CriticalEntryPaths $criticalRuleOrderPaths -MissingFileLabel '规则入口文件' -MissingEntryLabel '关键规则入口' -OrderDriftLabel '关键规则入口顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $coreGovernanceRuleSourceEntryChecks -CriticalEntryPaths $criticalCoreGovernanceRuleSourceOrderPaths -MissingFileLabel '核心治理规则真源文件' -MissingEntryLabel '核心治理规则入口' -OrderDriftLabel '核心治理规则入口顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $agentConstraintEntryChecks -CriticalEntryPaths $criticalAgentConstraintPaths -MissingFileLabel 'AGENTS 文件' -MissingEntryLabel '核心约束入口' -OrderDriftLabel '核心约束入口顺序漂移')) {
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

# 检查任务包 tech-spec.md（如果存在任务包修改）
$taskPackagePaths = @(
    $changedPathList |
        Where-Object { $_ -match '^\.codex/chancellor/tasks/([^/]+)/' }
)

if ($taskPackagePaths.Count -gt 0) {
    $taskDirs = @(
        $taskPackagePaths |
            ForEach-Object {
                if ($_ -match '^\.codex/chancellor/tasks/([^/]+)/') {
                    $matches[1]
                }
            } |
            Sort-Object -Unique
    )

    foreach ($taskId in $taskDirs) {
        $taskDir = ".codex/chancellor/tasks/$taskId"

        if (Test-Path $taskDir) {
            try {
                # 检查 tech-spec.md
                $checkScriptPath = '.codex/chancellor/check-task-package-tech-spec.ps1'
                if (Test-Path $checkScriptPath) {
                    & $checkScriptPath -TaskDir $taskDir
                }

                # 检查状态机门禁
                $stateMachineCheckPath = '.codex/chancellor/check-task-state-machine.ps1'
                if (Test-Path $stateMachineCheckPath) {
                    $taskChangedFiles = @(
                        $changedPathList |
                            Where-Object { $_ -match "^\.codex/chancellor/tasks/$taskId/" -or $_ -notmatch '^\.codex/chancellor/tasks/' }
                    )
                    & $stateMachineCheckPath -TaskDir $taskDir -ChangedFiles $taskChangedFiles
                }
            }
            catch {
                $violationMessages.Add("任务包 $taskId 检查失败：$($_.Exception.Message)")
            }
        }
    }
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
