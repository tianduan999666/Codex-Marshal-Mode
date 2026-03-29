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

    foreach ($fileLine in ($approvedFileBlock -split "`r?`n")) {
        $trimmedLine = $fileLine.Trim()
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
        '.codex/chancellor/create-gate-package.ps1'
        '.codex/chancellor/create-task-package.ps1'
        '.codex/chancellor/install-public-commit-governance-hook.ps1'
        '.codex/chancellor/invoke-public-commit-governance-gate.ps1'
        '.codex/chancellor/record-exception-state.ps1'
        '.codex/chancellor/resolve-gate-package.ps1'
        '.codex/chancellor/tasks/README.md'
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
    $readmeLandedFiles = @(
        Get-OrderedUniqueValues -Values @(
            [regex]::Matches($readmeLandedSection, '(?m)^- `([^`]+)`\r?$') |
                ForEach-Object { $_.Groups[1].Value }
        )
    )
    if ($readmeLandedFiles.Count -eq 0) {
        throw "生产母体 README 未解析到当前已落文件：$readmePath"
    }
    Assert-ExactOrderedValues -SourceValues $readmeLandedFiles -ExpectedValues $manifestIncludedFiles -Label '生产母体 README 当前已落文件'

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

function Get-CanonicalPanelCommandState {
    $agentsPath = 'AGENTS.md'
    $versionPath = 'codex-home-export/VERSION.json'
    $checklistPath = 'codex-home-export/panel-acceptance-checklist.md'
    $expectedPanelCommands = @(
        '丞相帮助'
        '丞相状态'
        '丞相检查'
        '丞相修复'
        '丞相验板'
        '丞相版本'
    )
    $expectedChecklistCommands = @(
        '丞相版本'
        '丞相检查'
        '丞相状态'
    )
    $expectedBoundaryCommands = @(
        '丞相修复'
        '丞相验板'
    )

    $agentsSection = Get-FileSectionContent -FilePath $agentsPath -SectionStartMarker '## 面板丞相命令' -SectionEndMarker '## 仓库卫生纪律'
    if ([string]::IsNullOrWhiteSpace($agentsSection)) {
        throw "AGENTS 未解析到面板丞相命令区块：$agentsPath"
    }

    $agentPanelCommandRows = @(
        [regex]::Matches($agentsSection, '(?m)^\|\s*`([^`]+)`\s*\|\s*([^|]+?)\s*\|\s*$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = $_.Groups[2].Value.Trim()
                }
            }
    )
    $agentPanelCommands = @(
        Get-OrderedUniqueValues -Values @(
            $agentPanelCommandRows | ForEach-Object { $_.Command }
        )
    )
    Assert-ExactOrderedValues -SourceValues $agentPanelCommands -ExpectedValues $expectedPanelCommands -Label 'AGENTS 面板丞相命令真源'

    $expectedAcceptanceRows = @()
    foreach ($expectedAcceptanceCommand in $expectedChecklistCommands) {
        $matchedAgentRow = @(
            $agentPanelCommandRows |
                Where-Object { $_.Command -eq $expectedAcceptanceCommand }
        ) | Select-Object -First 1
        if ($null -eq $matchedAgentRow) {
            throw "AGENTS 面板丞相命令真源缺少命令：$expectedAcceptanceCommand"
        }

        $expectedAcceptanceRows += [pscustomobject]@{
            Command = $matchedAgentRow.Command
            Description = $matchedAgentRow.Description
        }
    }

    $expectedBoundaryRows = @()
    foreach ($expectedBoundaryCommand in $expectedBoundaryCommands) {
        $matchedAgentRow = @(
            $agentPanelCommandRows |
                Where-Object { $_.Command -eq $expectedBoundaryCommand }
        ) | Select-Object -First 1
        if ($null -eq $matchedAgentRow) {
            throw "AGENTS 面板丞相命令真源缺少命令：$expectedBoundaryCommand"
        }

        $expectedBoundaryRows += [pscustomobject]@{
            Command = $matchedAgentRow.Command
            Description = $matchedAgentRow.Description
        }
    }

    $versionInfo = Read-JsonObjectFromFile -Path $versionPath -Label '生产母体版本文件'
    $versionPanelCommands = @(
        Get-OrderedUniqueValues -Values @($versionInfo.panel_commands)
    )
    if ($versionPanelCommands.Count -eq 0) {
        throw "生产母体版本文件缺少 panel_commands：$versionPath"
    }
    Assert-ExactOrderedValues -SourceValues $versionPanelCommands -ExpectedValues $expectedPanelCommands -Label '生产母体 panel_commands'

    $acceptanceDocPath = 'docs/40-执行/03-面板入口验收.md'
    $boundarySection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 两条维护命令边界' -SectionEndMarker '## 固定人工验收步骤'
    if ([string]::IsNullOrWhiteSpace($boundarySection)) {
        throw "面板入口验收未解析到两条维护命令边界：$acceptanceDocPath"
    }

    $boundaryRows = @(
        [regex]::Matches($boundarySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($boundaryRows | ForEach-Object { $_.Command }) -ExpectedValues $expectedBoundaryCommands -Label '面板入口验收维护命令边界序列'
    foreach ($expectedBoundaryRow in $expectedBoundaryRows) {
        $matchedBoundaryRow = @(
            $boundaryRows |
                Where-Object { $_.Command -eq $expectedBoundaryRow.Command }
        ) | Select-Object -First 1
        if ($null -eq $matchedBoundaryRow) {
            throw "面板入口验收缺少维护命令边界：$($expectedBoundaryRow.Command)"
        }

        if ($matchedBoundaryRow.Description -ne $expectedBoundaryRow.Description) {
            throw "面板入口验收维护命令边界漂移：$($expectedBoundaryRow.Command) 期望 $($expectedBoundaryRow.Description)，实际 $($matchedBoundaryRow.Description)"
        }
    }

    $acceptanceSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 三条核心命令验收口径' -SectionEndMarker '## 通过标准'
    if ([string]::IsNullOrWhiteSpace($acceptanceSection)) {
        throw "面板入口验收未解析到三条核心命令验收口径：$acceptanceDocPath"
    }

    $acceptanceRows = @(
        [regex]::Matches($acceptanceSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($acceptanceRows | ForEach-Object { $_.Command }) -ExpectedValues $expectedChecklistCommands -Label '面板入口验收核心命令序列'
    foreach ($expectedAcceptanceRow in $expectedAcceptanceRows) {
        $matchedAcceptanceRow = @(
            $acceptanceRows |
                Where-Object { $_.Command -eq $expectedAcceptanceRow.Command }
        ) | Select-Object -First 1
        if ($null -eq $matchedAcceptanceRow) {
            throw "面板入口验收缺少核心命令口径：$($expectedAcceptanceRow.Command)"
        }

        if ($matchedAcceptanceRow.Description -ne $expectedAcceptanceRow.Description) {
            throw "面板入口验收命令口径漂移：$($expectedAcceptanceRow.Command) 期望 $($expectedAcceptanceRow.Description)，实际 $($matchedAcceptanceRow.Description)"
        }
    }

    if (-not (Test-Path $checklistPath)) {
        throw "缺少面板人工验板清单：$checklistPath"
    }

    $checklistBoundarySection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 相关维护命令边界' -SectionEndMarker '## 验板步骤'
    if ([string]::IsNullOrWhiteSpace($checklistBoundarySection)) {
        throw "面板人工验板清单未解析到相关维护命令边界：$checklistPath"
    }

    $checklistBoundaryRows = @(
        [regex]::Matches($checklistBoundarySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistBoundaryRows | ForEach-Object { $_.Command }) -ExpectedValues $expectedBoundaryCommands -Label '面板人工验板清单维护命令边界序列'
    foreach ($expectedBoundaryRow in $expectedBoundaryRows) {
        $matchedChecklistBoundaryRow = @(
            $checklistBoundaryRows |
                Where-Object { $_.Command -eq $expectedBoundaryRow.Command }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistBoundaryRow) {
            throw "面板人工验板清单缺少维护命令边界：$($expectedBoundaryRow.Command)"
        }

        if ($matchedChecklistBoundaryRow.Description -ne $expectedBoundaryRow.Description) {
            throw "面板人工验板清单维护命令边界漂移：$($expectedBoundaryRow.Command) 期望 $($expectedBoundaryRow.Description)，实际 $($matchedChecklistBoundaryRow.Description)"
        }
    }

    $checklistStepsSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 验板步骤' -SectionEndMarker '## 通过标准'
    if ([string]::IsNullOrWhiteSpace($checklistStepsSection)) {
        throw "面板人工验板清单未解析到验板步骤区块：$checklistPath"
    }

    $checklistCommands = @(
        Get-OrderedUniqueValues -Values @(
            [regex]::Matches($checklistStepsSection, '丞相(?:帮助|状态|检查|修复|验板|版本)') |
                ForEach-Object { $_.Value }
        )
    )
    if ($checklistCommands.Count -eq 0) {
        throw "面板人工验板清单未解析到丞相命令：$checklistPath"
    }
    Assert-ExactOrderedValues -SourceValues $checklistCommands -ExpectedValues $expectedChecklistCommands -Label '面板人工验板清单命令序列'

    $checklistPassSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 通过标准' -SectionEndMarker '## 若不通过'
    if ([string]::IsNullOrWhiteSpace($checklistPassSection)) {
        throw "面板人工验板清单未解析到通过标准区块：$checklistPath"
    }

    $checklistAcceptanceRows = @(
        [regex]::Matches($checklistPassSection, '(?m)^- `([^`]+)` 能(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistAcceptanceRows | ForEach-Object { $_.Command }) -ExpectedValues $expectedChecklistCommands -Label '面板人工验板清单通过标准命令序列'
    foreach ($expectedAcceptanceRow in $expectedAcceptanceRows) {
        $matchedChecklistAcceptanceRow = @(
            $checklistAcceptanceRows |
                Where-Object { $_.Command -eq $expectedAcceptanceRow.Command }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistAcceptanceRow) {
            throw "面板人工验板清单缺少通过标准：$($expectedAcceptanceRow.Command)"
        }

        if ($matchedChecklistAcceptanceRow.Description -ne $expectedAcceptanceRow.Description) {
            throw "面板人工验板清单通过标准漂移：$($expectedAcceptanceRow.Command) 期望 $($expectedAcceptanceRow.Description)，实际 $($matchedChecklistAcceptanceRow.Description)"
        }
    }

    return [pscustomobject]@{
        PanelCommands = $expectedPanelCommands
        ChecklistCommands = $expectedChecklistCommands
        AcceptanceRows = @($expectedAcceptanceRows)
    }
}

function Get-CanonicalMaintenanceCapabilityDocPaths {
    $maintenanceGuidePath = 'docs/40-执行/13-维护层总入口.md'
    $maintenanceCapabilityPaths = Get-OrderedUniqueValues -Values @(
        Get-OrderedNormalizedDocPathsFromSection -FilePath $maintenanceGuidePath -RegexPattern '`(docs/(?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/(?:10|11|14|15|16|17|18|19|20|21)-[^`]+\.md)|(?:90-归档/01-[^`]+\.md)))`' -PathPrefix '' -SectionStartMarker '## 当前维护层能力' -SectionEndMarker '## 维护层主线真源'
    )

    if ($maintenanceCapabilityPaths.Count -eq 0) {
        throw "维护层总入口未解析到维护能力文档：$maintenanceGuidePath"
    }

    $maintenanceCapabilityOrderPaths = @(
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
    Assert-RequiredPathsPresent -SourcePaths $targetLifecycleSlice -RequiredPaths $requiredTargetLifecyclePaths -Label 'Target 主线真源'
    return $targetLifecycleSlice
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
    Assert-RequiredPathsPresent -SourcePaths $startupPhaseSlice -RequiredPaths $requiredStartupPhasePaths -Label '启动阶段真源'
    return $startupPhaseSlice
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
    Assert-RequiredPathsPresent -SourcePaths $restartGuideCanonicalEntryPaths -RequiredPaths $requiredRestartGuideEntryPaths -Label '重启导读核心入口真源'
    return $restartGuideCanonicalEntryPaths
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
try {
    [void](Get-CodexHomeExportConsistencyState)
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
$publicExecOrderEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 执行区现行标准件入口'
        RegexPattern = 'docs/40-执行/([0-9]{2}-[^`]+\.md)'
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 执行区现行标准件入口'
        RegexPattern = '40-执行/([0-9]{2}-[^`]+\.md)'
    },
    @{
        Path = 'docs/00-导航/02-现行标准件总览.md'
        Label = '现行标准件总览执行区现行标准件入口'
        RegexPattern = 'docs/40-执行/([0-9]{2}-[^`]+\.md)'
    }
)
$criticalPublicRuleEntryPaths = @($coreGovernanceRuleSourcePaths)
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
    $criticalMaintenanceLifecycleEntryPaths = Get-CanonicalMaintenanceLifecycleEntryPaths
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
$canonicalMaintenanceCapabilityDocPaths = @()
try {
    $canonicalMaintenanceCapabilityDocPaths = Get-CanonicalMaintenanceCapabilityDocPaths
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
$publicMaintenanceCapabilityEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 维护层补充入口'
        RegexPattern = '`(docs/(?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/(?:10|11|14|15|16|17|18|19|20|21)-[^`]+\.md)|(?:90-归档/01-[^`]+\.md)))`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 维护层补充入口'
        RegexPattern = '`((?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/(?:10|11|14|15|16|17|18|19|20|21)-[^`]+\.md)|(?:90-归档/01-[^`]+\.md)))`'
        PathPrefix = 'docs/'
    }
)
$publicMaintenanceCapabilityOrderEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 维护层补充入口'
        RegexPattern = '`(docs/(?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/21-[^`]+\.md)))`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 维护层补充入口'
        RegexPattern = '`((?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/21-[^`]+\.md)))`'
        PathPrefix = 'docs/'
    }
)
$criticalMaintenanceCapabilityOrderPaths = @(
    'docs/30-方案/08-V4-治理审计候选规范.md'
    'docs/40-执行/21-关键配置来源与漂移复核模板.md'
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
$restartGuideCanonicalEntryPaths = @()
try {
    $restartGuideCanonicalEntryPaths = Get-CanonicalRestartGuideEntryPaths
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
}
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
$criticalStartupPhaseEntryPaths = @()
try {
    $criticalStartupPhaseEntryPaths = Get-CanonicalStartupPhaseEntryPaths
}
catch {
    $precomputedViolationMessages.Add($_.Exception.Message)
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

$canonicalExecStandardDocNames = @()
try {
    $canonicalExecStandardDocNames = Get-CanonicalExecStandardDocNames
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
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $publicRestartGuideEntryChecks -CriticalEntryPaths $restartGuideCanonicalEntryPaths -MissingFileLabel '重启导读核心入口文件' -MissingEntryLabel '重启导读核心入口' -OrderDriftLabel '重启导读核心入口顺序漂移')) {
    $violationMessages.Add($entryViolationMessage)
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
if ($canonicalMaintenanceCapabilityDocPaths.Count -gt 0) {
    foreach ($entryCheck in $publicMaintenanceCapabilityEntryChecks) {
        if (-not (Test-Path $entryCheck.Path)) {
            $violationMessages.Add("缺少维护层补充入口文件：$($entryCheck.Path)")
            continue
        }

        $actualMaintenanceCapabilityPaths = Get-MatchedNormalizedDocPathsFromFile -FilePath $entryCheck.Path -RegexPattern $entryCheck.RegexPattern -PathPrefix $entryCheck.PathPrefix
        $missingMaintenanceCapabilityPaths = @(
            $canonicalMaintenanceCapabilityDocPaths |
                Where-Object { $_ -notin $actualMaintenanceCapabilityPaths }
        )
        $extraMaintenanceCapabilityPaths = @(
            $actualMaintenanceCapabilityPaths |
                Where-Object { $_ -notin $canonicalMaintenanceCapabilityDocPaths }
        )

        if ($missingMaintenanceCapabilityPaths.Count -gt 0) {
            $violationMessages.Add("$($entryCheck.Label) 缺少维护层补充入口：$($missingMaintenanceCapabilityPaths -join '、')")
        }

        if ($extraMaintenanceCapabilityPaths.Count -gt 0) {
            $violationMessages.Add("$($entryCheck.Label) 存在未受控的维护层补充入口：$($extraMaintenanceCapabilityPaths -join '、')")
        }
    }
}
foreach ($entryViolationMessage in (Get-OrderedEntryViolationMessages -EntryChecks $publicMaintenanceCapabilityOrderEntryChecks -CriticalEntryPaths $criticalMaintenanceCapabilityOrderPaths -MissingFileLabel '维护层补充入口文件' -MissingEntryLabel '维护层补充入口' -OrderDriftLabel '维护层补充入口顺序漂移')) {
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
