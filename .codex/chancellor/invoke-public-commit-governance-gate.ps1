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
    $expectedHelpCommands = @(
        '丞相帮助'
    )
    $expectedHelpTemplateItems = @(
        [pscustomobject]@{ Name = '当前用法'; Description = '先说明当前默认入口与适用场景' }
        [pscustomobject]@{ Name = '面板命令'; Description = '再列出当前面板丞相命令及其含义' }
        [pscustomobject]@{ Name = '注意事项'; Description = '最后提示维护层动作、安全边界与人工验板提醒' }
    )
    $expectedHelpUsageItems = @(
        [pscustomobject]@{ Name = '默认入口'; Description = '当前默认用户入口是官方 Codex 面板' }
        [pscustomobject]@{ Name = '适用场景'; Description = '普通用户日常使用优先在面板内完成，终端仅保留给维护、安装、迁移、排障' }
        [pscustomobject]@{ Name = '维护层说明'; Description = '如必须落到脚本层，要明确说明“这是维护层动作”' }
    )
    $expectedHelpPanelCommandItems = @(
        [pscustomobject]@{ Name = '命令顺序'; Description = '按丞相帮助、丞相状态、丞相检查、丞相修复、丞相验板、丞相版本的顺序展示' }
        [pscustomobject]@{ Name = '命令含义'; Description = '每条命令都要带一句人话含义，不得只列命令名' }
        [pscustomobject]@{ Name = '公开边界'; Description = '普通用户只暴露面板命令，不主动推荐终端丞相别名' }
    )
    $expectedHelpNoticeItems = @(
        [pscustomobject]@{ Name = '安全边界'; Description = '普通用户入口优先留在官方面板，维护层动作不向普通用户外露复杂终端流程' }
        [pscustomobject]@{ Name = '维护层动作'; Description = '如必须落到脚本层，要明确说明“这是维护层动作”' }
        [pscustomobject]@{ Name = '新开会话验板提醒'; Description = '入口相关改动后，建议新开官方面板会话做人眼验板' }
    )
    $expectedVersionCommandSlotItems = @(
        [pscustomobject]@{ Name = '版本号'; Description = '返回当前丞相模式版本号' }
        [pscustomobject]@{ Name = '版本来源'; Description = '明确当前版本来自哪个版本来源' }
        [pscustomobject]@{ Name = '真源路径'; Description = '优先说明当前版本真源路径为 `codex-home-export/VERSION.json`' }
    )
    $expectedCheckCommandSlotItems = @(
        [pscustomobject]@{ Name = '检查范围'; Description = '只做最小必要检查，不扩展成无关大扫除' }
        [pscustomobject]@{ Name = '检查结论'; Description = '用人话汇报当前是否存在明显异常或风险' }
        [pscustomobject]@{ Name = '建议动作'; Description = '如发现问题，给出下一步建议或引导到修复 / 验板' }
    )
    $expectedStatusCommandSlotItems = @(
        [pscustomobject]@{ Name = '当前模式'; Description = '明确当前处于什么模式或入口状态' }
        [pscustomobject]@{ Name = '稳态判断'; Description = '明确当前是否稳态' }
        [pscustomobject]@{ Name = '下一步'; Description = '给出最小下一步建议' }
    )
    $expectedRepairCommandSlotItems = @(
        [pscustomobject]@{ Name = '修复范围'; Description = '只在安全边界内处理当前常见问题' }
        [pscustomobject]@{ Name = '处理方式'; Description = '优先尝试自动修复当前已知常见问题' }
        [pscustomobject]@{ Name = '升级条件'; Description = '超出安全边界或无法自动修复时停止扩展并提示人工处理' }
    )
    $expectedPanelAcceptanceCommandSlotItems = @(
        [pscustomobject]@{ Name = '触发场景'; Description = '入口相关改动后或切换后进入官方面板做人眼验板' }
        [pscustomobject]@{ Name = '验板动作'; Description = '给出进入官方面板人工验收的固定步骤' }
        [pscustomobject]@{ Name = '验板目标'; Description = '确认版本、模式与入口表现是否稳态' }
    )
    $expectedAcceptanceGoalText = '确保主公从官方面板进入时，入口语义稳定、任务包衔接明确、改动后有固定人工验收闭环'
    $expectedAcceptanceExcludedItems = @(
        '真实业务任务是否跑通'
        '安装链与发布链是否稳定'
        '多 Agent、长期记忆、独立 UI'
    )
    $expectedAcceptanceScopeSummaryItems = @(
        '`丞相：` 首句入口风格'
        '面板内置命令的最小响应口径'
        '入口与 `.codex/chancellor/tasks/` 的衔接关系'
        '入口相关改动后的人工复验步骤'
    )
    $expectedAcceptanceScopeItems = @(
        [pscustomobject]@{ Name = '首句入口风格'; Description = '`丞相：` 首句入口风格' }
        [pscustomobject]@{ Name = '最小响应口径'; Description = '面板内置命令的最小响应口径' }
        [pscustomobject]@{ Name = '任务包衔接'; Description = '入口与 `.codex/chancellor/tasks/` 的衔接关系' }
        [pscustomobject]@{ Name = '人工复验步骤'; Description = '入口相关改动后的人工复验步骤' }
    )
    $expectedAcceptanceStepItems = @(
        [pscustomobject]@{ Name = '预处理动作'; Description = '如有入口相关改动，先完成必要安装或同步动作' }
        [pscustomobject]@{ Name = '新开会话'; Description = '新开一个聊天会话，不复用旧会话' }
        [pscustomobject]@{ Name = '首句验板'; Description = '第一条消息输入：`丞相：测试入口是否稳态`' }
        [pscustomobject]@{ Name = '开头校验'; Description = '检查回复是否使用固定开头：`丞相亮启奏：谨呈本次事宜。`' }
        [pscustomobject]@{ Name = '语气校验'; Description = '检查回复语气是否符合丞相模式，不回退为普通口吻' }
        [pscustomobject]@{ Name = '状态校验'; Description = '输入 `丞相状态`，检查是否能给出当前模式、状态与下一步的人话结论' }
        [pscustomobject]@{ Name = '任务一致性'; Description = '若本地存在激活任务，检查回复口径是否与当前任务状态一致' }
    )
    $expectedAcceptancePassSummaryItems = @(
        '`丞相：...` 首句能稳定进入丞相模式'
        '回复开头使用固定文案，且口吻不漂移'
        '`丞相帮助` 能显示当前用法、命令与注意事项'
        '`丞相帮助` 能按“当前用法 → 面板命令 → 注意事项”组织输出'
        '`丞相帮助` 的当前用法能覆盖“默认入口 → 适用场景 → 维护层说明”'
        '`丞相帮助` 的面板命令说明能覆盖“命令顺序 → 命令含义 → 公开边界”'
        '`丞相帮助` 的注意事项能覆盖“安全边界 → 维护层动作 → 新开会话验板提醒”'
        '`固定人工验收步骤` 能覆盖“预处理动作 → 新开会话 → 首句验板 → 开头校验 → 语气校验 → 状态校验 → 任务一致性”'
        '`丞相版本` 能返回当前丞相模式版本与版本来源'
        '`丞相版本` 的输出能覆盖“版本号 → 版本来源 → 真源路径”'
        '`丞相检查` 能做最小必要检查并返回人话结论'
        '`丞相检查` 的输出能覆盖“检查范围 → 检查结论 → 建议动作”'
        '`丞相状态` 能汇报当前模式、是否稳态、下一步'
        '`丞相状态` 的输出能覆盖“当前模式 → 稳态判断 → 下一步”'
        '`丞相修复` 的边界说明能覆盖“修复范围 → 处理方式 → 升级条件”'
        '`丞相验板` 的边界说明能覆盖“触发场景 → 验板动作 → 验板目标”'
        '若存在激活任务，入口口径与本地任务状态不冲突'
        '入口相关改动后，能通过“新开会话 + 首句验板”完成复验'
    )
    $expectedAcceptanceFailSummaryItems = @(
        '首句未进入丞相模式'
        '固定开头丢失或风格回退为普通模式'
        '`丞相帮助` 未显示当前用法、命令与注意事项'
        '`丞相帮助` 未按“当前用法 → 面板命令 → 注意事项”组织输出'
        '`丞相帮助` 的当前用法未覆盖“默认入口 → 适用场景 → 维护层说明”'
        '`丞相帮助` 的面板命令说明未覆盖“命令顺序 → 命令含义 → 公开边界”'
        '`丞相帮助` 的注意事项未覆盖“安全边界 → 维护层动作 → 新开会话验板提醒”'
        '`固定人工验收步骤` 未覆盖“预处理动作 → 新开会话 → 首句验板 → 开头校验 → 语气校验 → 状态校验 → 任务一致性”'
        '`丞相版本` 未返回当前丞相模式版本与版本来源'
        '`丞相版本` 的输出未覆盖“版本号 → 版本来源 → 真源路径”'
        '`丞相检查` 未做最小必要检查或未返回人话结论'
        '`丞相检查` 的输出未覆盖“检查范围 → 检查结论 → 建议动作”'
        '`丞相状态` 未汇报当前模式、是否稳态、下一步'
        '`丞相状态` 的输出未覆盖“当前模式 → 稳态判断 → 下一步”'
        '`丞相修复` 的边界说明未覆盖“修复范围 → 处理方式 → 升级条件”'
        '`丞相验板` 的边界说明未覆盖“触发场景 → 验板动作 → 验板目标”'
        '入口回复与本地激活任务状态明显冲突'
    )
    $expectedChecklistStepItems = @(
        [pscustomobject]@{ Name = '关闭旧会话'; Description = '关闭当前 `Codex` 会话' }
        [pscustomobject]@{ Name = '新开官方面板'; Description = '重新打开官方 `Codex` 面板，新开一个全新会话' }
        [pscustomobject]@{ Name = '版本验证'; Description = '首句输入：`丞相版本`' }
        [pscustomobject]@{ Name = '检查验证'; Description = '继续输入：`丞相检查`' }
        [pscustomobject]@{ Name = '状态验证'; Description = '如需再验一层，继续输入：`丞相状态`' }
    )
    $expectedAcceptancePassItems = @(
        [pscustomobject]@{ Name = '模式稳定'; Description = '首句进入丞相模式，固定开头不丢失，语气不漂移' }
        [pscustomobject]@{ Name = '帮助完整'; Description = '帮助输出覆盖结构与子项模板' }
        [pscustomobject]@{ Name = '命令口径'; Description = '版本、检查、状态与维护边界口径完整' }
        [pscustomobject]@{ Name = '任务一致'; Description = '若存在激活任务，入口口径与本地任务状态不冲突' }
        [pscustomobject]@{ Name = '复验闭环'; Description = '入口相关改动后，可通过新开会话与首句验板完成复验' }
    )
    $expectedAcceptanceFailItems = @(
        [pscustomobject]@{ Name = '模式失稳'; Description = '首句未进入丞相模式，或固定开头丢失、语气回退' }
        [pscustomobject]@{ Name = '帮助缺项'; Description = '帮助输出未覆盖固定结构或固定子项模板' }
        [pscustomobject]@{ Name = '命令漂移'; Description = '版本、检查、状态或维护边界口径出现缺失或漂移' }
        [pscustomobject]@{ Name = '任务冲突'; Description = '入口回复与本地激活任务状态明显冲突' }
        [pscustomobject]@{ Name = '复验失败'; Description = '重新执行必要同步动作后，仍无法通过新开会话与首句验板完成复验' }
    )
    $expectedAcceptanceRecoveryItems = @(
        [pscustomobject]@{ Name = '停止扩展'; Description = '先停止继续扩展任务范围' }
        [pscustomobject]@{ Name = '回看变更'; Description = '回看最近入口相关变更是否涉及 `AGENTS.md`、规则文档或安装同步动作' }
        [pscustomobject]@{ Name = '重新验板'; Description = '重新执行必要同步动作后，新开会话再次验板' }
        [pscustomobject]@{ Name = '缺陷收口'; Description = '若仍失败，记录为入口缺陷，不带着问题进入真实任务试跑' }
    )
    $expectedAcceptanceTrialGateItems = @(
        [pscustomobject]@{ Name = '前置门槛'; Description = '本文档是进入真实任务试跑前的固定门槛' }
        [pscustomobject]@{ Name = '放行条件'; Description = '只有入口验收通过后，才进入后续真实任务闭环验证' }
        [pscustomobject]@{ Name = '公开边界'; Description = '本文档可进入公开仓；真实运行态与日志继续只留本地' }
    )
    $expectedChecklistPassItems = @(
        [pscustomobject]@{ Name = '命令有效'; Description = '版本、检查、状态命令可用且口径完整' }
        [pscustomobject]@{ Name = '边界稳定'; Description = '修复与验板边界说明完整' }
        [pscustomobject]@{ Name = '验板闭环'; Description = '人工验板步骤模板完整' }
        [pscustomobject]@{ Name = '过程稳定'; Description = '整个过程不出现明显崩溃、失焦或命令失效' }
        [pscustomobject]@{ Name = '无需手改'; Description = '整个过程无需再手改本地文件' }
    )
    $expectedChecklistRecoveryItems = @(
        [pscustomobject]@{ Name = '自动复核'; Description = '先执行：`codex-home-export/verify-cutover.ps1`' }
        [pscustomobject]@{ Name = '自动回退'; Description = '若仍异常，再执行：`codex-home-export/rollback-from-backup.ps1`' }
        [pscustomobject]@{ Name = '重新验板'; Description = '回退后重新打开面板，再次验板' }
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

    $expectedHelpRows = @()
    foreach ($expectedHelpCommand in $expectedHelpCommands) {
        $matchedAgentRow = @(
            $agentPanelCommandRows |
                Where-Object { $_.Command -eq $expectedHelpCommand }
        ) | Select-Object -First 1
        if ($null -eq $matchedAgentRow) {
            throw "AGENTS 面板丞相命令真源缺少命令：$expectedHelpCommand"
        }

        $expectedHelpRows += [pscustomobject]@{
            Command = $matchedAgentRow.Command
            Description = $matchedAgentRow.Description
        }
    }

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
    $acceptanceGoalSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 一句话目标' -SectionEndMarker '## 验收范围'
    if ([string]::IsNullOrWhiteSpace($acceptanceGoalSection)) {
        throw "面板入口验收未解析到一句话目标：$acceptanceDocPath"
    }

    $acceptanceGoalText = ($acceptanceGoalSection.Trim() -replace '。$','')
    if ([string]::IsNullOrWhiteSpace($acceptanceGoalText)) {
        throw "面板入口验收未解析到一句话目标正文：$acceptanceDocPath"
    }
    if ($acceptanceGoalText -ne $expectedAcceptanceGoalText) {
        throw "面板入口验收一句话目标漂移：期望 $expectedAcceptanceGoalText，实际 $acceptanceGoalText"
    }

    $acceptanceExcludedSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 本轮不验收' -SectionEndMarker '## 帮助命令公开用法'
    if ([string]::IsNullOrWhiteSpace($acceptanceExcludedSection)) {
        throw "面板入口验收未解析到本轮不验收摘要：$acceptanceDocPath"
    }

    $acceptanceExcludedItems = @(
        [regex]::Matches($acceptanceExcludedSection, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($acceptanceExcludedItems.Count -eq 0) {
        throw "面板入口验收未解析到本轮不验收摘要列点：$acceptanceDocPath"
    }
    Assert-ExactOrderedValues -SourceValues $acceptanceExcludedItems -ExpectedValues $expectedAcceptanceExcludedItems -Label '面板入口验收本轮不验收摘要序列'

    $acceptanceScopeSummarySection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 验收范围' -SectionEndMarker '## 验收范围固定槽位'
    if ([string]::IsNullOrWhiteSpace($acceptanceScopeSummarySection)) {
        throw "面板入口验收未解析到验收范围摘要：$acceptanceDocPath"
    }

    $acceptanceScopeSummaryItems = @(
        [regex]::Matches($acceptanceScopeSummarySection, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($acceptanceScopeSummaryItems.Count -eq 0) {
        throw "面板入口验收未解析到验收范围摘要列点：$acceptanceDocPath"
    }
    Assert-ExactOrderedValues -SourceValues $acceptanceScopeSummaryItems -ExpectedValues $expectedAcceptanceScopeSummaryItems -Label '面板入口验收验收范围摘要序列'

    $acceptanceScopeSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 验收范围固定槽位' -SectionEndMarker '## 本轮不验收'
    if ([string]::IsNullOrWhiteSpace($acceptanceScopeSection)) {
        throw "面板入口验收未解析到验收范围固定槽位：$acceptanceDocPath"
    }

    $acceptanceScopeRows = @(
        [regex]::Matches($acceptanceScopeSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($acceptanceScopeRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedAcceptanceScopeItems | ForEach-Object { $_.Name }) -Label '面板入口验收验收范围固定槽位序列'
    foreach ($expectedAcceptanceScopeItem in $expectedAcceptanceScopeItems) {
        $matchedAcceptanceScopeRow = @(
            $acceptanceScopeRows |
                Where-Object { $_.Name -eq $expectedAcceptanceScopeItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedAcceptanceScopeRow) {
            throw "面板入口验收缺少验收范围固定槽位：$($expectedAcceptanceScopeItem.Name)"
        }

        if ($matchedAcceptanceScopeRow.Description -ne $expectedAcceptanceScopeItem.Description) {
            throw "面板入口验收验收范围固定槽位漂移：$($expectedAcceptanceScopeItem.Name) 期望 $($expectedAcceptanceScopeItem.Description)，实际 $($matchedAcceptanceScopeRow.Description)"
        }
    }

    $helpSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 帮助命令公开用法' -SectionEndMarker '## 帮助命令固定结构'
    if ([string]::IsNullOrWhiteSpace($helpSection)) {
        throw "面板入口验收未解析到帮助命令公开用法：$acceptanceDocPath"
    }

    $helpRows = @(
        [regex]::Matches($helpSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($helpRows | ForEach-Object { $_.Command }) -ExpectedValues $expectedHelpCommands -Label '面板入口验收帮助命令用法序列'
    foreach ($expectedHelpRow in $expectedHelpRows) {
        $matchedHelpRow = @(
            $helpRows |
                Where-Object { $_.Command -eq $expectedHelpRow.Command }
        ) | Select-Object -First 1
        if ($null -eq $matchedHelpRow) {
            throw "面板入口验收缺少帮助命令用法：$($expectedHelpRow.Command)"
        }

        if ($matchedHelpRow.Description -ne $expectedHelpRow.Description) {
            throw "面板入口验收帮助命令用法漂移：$($expectedHelpRow.Command) 期望 $($expectedHelpRow.Description)，实际 $($matchedHelpRow.Description)"
        }
    }

    $helpTemplateSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 帮助命令固定结构' -SectionEndMarker '## 当前用法固定子项'
    if ([string]::IsNullOrWhiteSpace($helpTemplateSection)) {
        throw "面板入口验收未解析到帮助命令固定结构：$acceptanceDocPath"
    }

    $helpTemplateRows = @(
        [regex]::Matches($helpTemplateSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($helpTemplateRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpTemplateItems | ForEach-Object { $_.Name }) -Label '面板入口验收帮助命令固定结构序列'
    foreach ($expectedHelpTemplateItem in $expectedHelpTemplateItems) {
        $matchedHelpTemplateRow = @(
            $helpTemplateRows |
                Where-Object { $_.Name -eq $expectedHelpTemplateItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedHelpTemplateRow) {
            throw "面板入口验收缺少帮助命令固定结构项：$($expectedHelpTemplateItem.Name)"
        }

        if ($matchedHelpTemplateRow.Description -ne $expectedHelpTemplateItem.Description) {
            throw "面板入口验收帮助命令固定结构漂移：$($expectedHelpTemplateItem.Name) 期望 $($expectedHelpTemplateItem.Description)，实际 $($matchedHelpTemplateRow.Description)"
        }
    }

    $helpUsageSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 当前用法固定子项' -SectionEndMarker '## 面板命令固定子项'
    if ([string]::IsNullOrWhiteSpace($helpUsageSection)) {
        throw "面板入口验收未解析到当前用法固定子项：$acceptanceDocPath"
    }

    $helpUsageRows = @(
        [regex]::Matches($helpUsageSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($helpUsageRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpUsageItems | ForEach-Object { $_.Name }) -Label '面板入口验收当前用法固定子项序列'
    foreach ($expectedHelpUsageItem in $expectedHelpUsageItems) {
        $matchedHelpUsageRow = @(
            $helpUsageRows |
                Where-Object { $_.Name -eq $expectedHelpUsageItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedHelpUsageRow) {
            throw "面板入口验收缺少当前用法固定子项：$($expectedHelpUsageItem.Name)"
        }

        if ($matchedHelpUsageRow.Description -ne $expectedHelpUsageItem.Description) {
            throw "面板入口验收当前用法固定子项漂移：$($expectedHelpUsageItem.Name) 期望 $($expectedHelpUsageItem.Description)，实际 $($matchedHelpUsageRow.Description)"
        }
    }

    $helpPanelCommandSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 面板命令固定子项' -SectionEndMarker '## 注意事项固定子项'
    if ([string]::IsNullOrWhiteSpace($helpPanelCommandSection)) {
        throw "面板入口验收未解析到面板命令固定子项：$acceptanceDocPath"
    }

    $helpPanelCommandRows = @(
        [regex]::Matches($helpPanelCommandSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($helpPanelCommandRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpPanelCommandItems | ForEach-Object { $_.Name }) -Label '面板入口验收面板命令固定子项序列'
    foreach ($expectedHelpPanelCommandItem in $expectedHelpPanelCommandItems) {
        $matchedHelpPanelCommandRow = @(
            $helpPanelCommandRows |
                Where-Object { $_.Name -eq $expectedHelpPanelCommandItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedHelpPanelCommandRow) {
            throw "面板入口验收缺少面板命令固定子项：$($expectedHelpPanelCommandItem.Name)"
        }

        if ($matchedHelpPanelCommandRow.Description -ne $expectedHelpPanelCommandItem.Description) {
            throw "面板入口验收面板命令固定子项漂移：$($expectedHelpPanelCommandItem.Name) 期望 $($expectedHelpPanelCommandItem.Description)，实际 $($matchedHelpPanelCommandRow.Description)"
        }
    }

    $helpNoticeSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 注意事项固定子项' -SectionEndMarker '## 两条维护命令边界'
    if ([string]::IsNullOrWhiteSpace($helpNoticeSection)) {
        throw "面板入口验收未解析到注意事项固定子项：$acceptanceDocPath"
    }

    $helpNoticeRows = @(
        [regex]::Matches($helpNoticeSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($helpNoticeRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpNoticeItems | ForEach-Object { $_.Name }) -Label '面板入口验收注意事项固定子项序列'
    foreach ($expectedHelpNoticeItem in $expectedHelpNoticeItems) {
        $matchedHelpNoticeRow = @(
            $helpNoticeRows |
                Where-Object { $_.Name -eq $expectedHelpNoticeItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedHelpNoticeRow) {
            throw "面板入口验收缺少注意事项固定子项：$($expectedHelpNoticeItem.Name)"
        }

        if ($matchedHelpNoticeRow.Description -ne $expectedHelpNoticeItem.Description) {
            throw "面板入口验收注意事项固定子项漂移：$($expectedHelpNoticeItem.Name) 期望 $($expectedHelpNoticeItem.Description)，实际 $($matchedHelpNoticeRow.Description)"
        }
    }

    $boundarySection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 两条维护命令边界' -SectionEndMarker '## 丞相修复固定槽位'
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

    $repairCommandSlotSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 丞相修复固定槽位' -SectionEndMarker '## 丞相验板固定槽位'
    if ([string]::IsNullOrWhiteSpace($repairCommandSlotSection)) {
        throw "面板入口验收未解析到丞相修复固定槽位：$acceptanceDocPath"
    }

    $repairCommandSlotRows = @(
        [regex]::Matches($repairCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($repairCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedRepairCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板入口验收丞相修复固定槽位序列'
    foreach ($expectedRepairCommandSlotItem in $expectedRepairCommandSlotItems) {
        $matchedRepairCommandSlotRow = @(
            $repairCommandSlotRows |
                Where-Object { $_.Name -eq $expectedRepairCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedRepairCommandSlotRow) {
            throw "面板入口验收缺少丞相修复固定槽位：$($expectedRepairCommandSlotItem.Name)"
        }

        if ($matchedRepairCommandSlotRow.Description -ne $expectedRepairCommandSlotItem.Description) {
            throw "面板入口验收丞相修复固定槽位漂移：$($expectedRepairCommandSlotItem.Name) 期望 $($expectedRepairCommandSlotItem.Description)，实际 $($matchedRepairCommandSlotRow.Description)"
        }
    }

    $panelAcceptanceCommandSlotSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 丞相验板固定槽位' -SectionEndMarker '## 固定人工验收步骤'
    if ([string]::IsNullOrWhiteSpace($panelAcceptanceCommandSlotSection)) {
        throw "面板入口验收未解析到丞相验板固定槽位：$acceptanceDocPath"
    }

    $panelAcceptanceCommandSlotRows = @(
        [regex]::Matches($panelAcceptanceCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($panelAcceptanceCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedPanelAcceptanceCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板入口验收丞相验板固定槽位序列'
    foreach ($expectedPanelAcceptanceCommandSlotItem in $expectedPanelAcceptanceCommandSlotItems) {
        $matchedPanelAcceptanceCommandSlotRow = @(
            $panelAcceptanceCommandSlotRows |
                Where-Object { $_.Name -eq $expectedPanelAcceptanceCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedPanelAcceptanceCommandSlotRow) {
            throw "面板入口验收缺少丞相验板固定槽位：$($expectedPanelAcceptanceCommandSlotItem.Name)"
        }

        if ($matchedPanelAcceptanceCommandSlotRow.Description -ne $expectedPanelAcceptanceCommandSlotItem.Description) {
            throw "面板入口验收丞相验板固定槽位漂移：$($expectedPanelAcceptanceCommandSlotItem.Name) 期望 $($expectedPanelAcceptanceCommandSlotItem.Description)，实际 $($matchedPanelAcceptanceCommandSlotRow.Description)"
        }
    }

    $acceptanceStepSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 固定人工验收步骤固定子项' -SectionEndMarker '## 三条核心命令验收口径'
    if ([string]::IsNullOrWhiteSpace($acceptanceStepSection)) {
        throw "面板入口验收未解析到固定人工验收步骤固定子项：$acceptanceDocPath"
    }

    $acceptanceStepRows = @(
        [regex]::Matches($acceptanceStepSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($acceptanceStepRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedAcceptanceStepItems | ForEach-Object { $_.Name }) -Label '面板入口验收固定人工验收步骤固定子项序列'
    foreach ($expectedAcceptanceStepItem in $expectedAcceptanceStepItems) {
        $matchedAcceptanceStepRow = @(
            $acceptanceStepRows |
                Where-Object { $_.Name -eq $expectedAcceptanceStepItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedAcceptanceStepRow) {
            throw "面板入口验收缺少固定人工验收步骤固定子项：$($expectedAcceptanceStepItem.Name)"
        }

        if ($matchedAcceptanceStepRow.Description -ne $expectedAcceptanceStepItem.Description) {
            throw "面板入口验收固定人工验收步骤固定子项漂移：$($expectedAcceptanceStepItem.Name) 期望 $($expectedAcceptanceStepItem.Description)，实际 $($matchedAcceptanceStepRow.Description)"
        }
    }

    $acceptanceSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 三条核心命令验收口径' -SectionEndMarker '## 丞相版本固定槽位'
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

    $acceptancePassSummarySection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 通过标准' -SectionEndMarker '## 通过标准固定子项'
    if ([string]::IsNullOrWhiteSpace($acceptancePassSummarySection)) {
        throw "面板入口验收未解析到通过标准摘要：$acceptanceDocPath"
    }

    $acceptancePassSummaryItems = @(
        [regex]::Matches($acceptancePassSummarySection, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($acceptancePassSummaryItems.Count -eq 0) {
        throw "面板入口验收未解析到通过标准摘要列点：$acceptanceDocPath"
    }
    Assert-ExactOrderedValues -SourceValues $acceptancePassSummaryItems -ExpectedValues $expectedAcceptancePassSummaryItems -Label '面板入口验收通过标准摘要序列'

    $acceptancePassSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 通过标准固定子项' -SectionEndMarker '## 失败信号'
    if ([string]::IsNullOrWhiteSpace($acceptancePassSection)) {
        throw "面板入口验收未解析到通过标准固定子项：$acceptanceDocPath"
    }

    $acceptancePassRows = @(
        [regex]::Matches($acceptancePassSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($acceptancePassRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedAcceptancePassItems | ForEach-Object { $_.Name }) -Label '面板入口验收通过标准固定子项序列'
    foreach ($expectedAcceptancePassItem in $expectedAcceptancePassItems) {
        $matchedAcceptancePassRow = @(
            $acceptancePassRows |
                Where-Object { $_.Name -eq $expectedAcceptancePassItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedAcceptancePassRow) {
            throw "面板入口验收缺少通过标准固定子项：$($expectedAcceptancePassItem.Name)"
        }

        if ($matchedAcceptancePassRow.Description -ne $expectedAcceptancePassItem.Description) {
            throw "面板入口验收通过标准固定子项漂移：$($expectedAcceptancePassItem.Name) 期望 $($expectedAcceptancePassItem.Description)，实际 $($matchedAcceptancePassRow.Description)"
        }
    }

    $acceptanceFailSummarySection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 失败信号' -SectionEndMarker '## 失败信号固定子项'
    if ([string]::IsNullOrWhiteSpace($acceptanceFailSummarySection)) {
        throw "面板入口验收未解析到失败信号摘要：$acceptanceDocPath"
    }

    $acceptanceFailSummaryItems = @(
        [regex]::Matches($acceptanceFailSummarySection, '(?m)^- (.+?)\r?$') |
            ForEach-Object {
                ($_.Groups[1].Value.Trim() -replace '。$','')
            }
    )
    if ($acceptanceFailSummaryItems.Count -eq 0) {
        throw "面板入口验收未解析到失败信号摘要列点：$acceptanceDocPath"
    }
    Assert-ExactOrderedValues -SourceValues $acceptanceFailSummaryItems -ExpectedValues $expectedAcceptanceFailSummaryItems -Label '面板入口验收失败信号摘要序列'

    $acceptanceFailItemSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 失败信号固定子项' -SectionEndMarker '## 失败后的处置动作'
    if ([string]::IsNullOrWhiteSpace($acceptanceFailItemSection)) {
        throw "面板入口验收未解析到失败信号固定子项：$acceptanceDocPath"
    }

    $acceptanceFailItemRows = @(
        [regex]::Matches($acceptanceFailItemSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($acceptanceFailItemRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedAcceptanceFailItems | ForEach-Object { $_.Name }) -Label '面板入口验收失败信号固定子项序列'
    foreach ($expectedAcceptanceFailItem in $expectedAcceptanceFailItems) {
        $matchedAcceptanceFailItemRow = @(
            $acceptanceFailItemRows |
                Where-Object { $_.Name -eq $expectedAcceptanceFailItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedAcceptanceFailItemRow) {
            throw "面板入口验收缺少失败信号固定子项：$($expectedAcceptanceFailItem.Name)"
        }

        if ($matchedAcceptanceFailItemRow.Description -ne $expectedAcceptanceFailItem.Description) {
            throw "面板入口验收失败信号固定子项漂移：$($expectedAcceptanceFailItem.Name) 期望 $($expectedAcceptanceFailItem.Description)，实际 $($matchedAcceptanceFailItemRow.Description)"
        }
    }

    $acceptanceRecoverySection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 失败后的处置动作固定子项' -SectionEndMarker '## 与试跑阶段的关系'
    if ([string]::IsNullOrWhiteSpace($acceptanceRecoverySection)) {
        throw "面板入口验收未解析到失败后的处置动作固定子项：$acceptanceDocPath"
    }

    $acceptanceRecoveryRows = @(
        [regex]::Matches($acceptanceRecoverySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($acceptanceRecoveryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedAcceptanceRecoveryItems | ForEach-Object { $_.Name }) -Label '面板入口验收失败后的处置动作固定子项序列'
    foreach ($expectedAcceptanceRecoveryItem in $expectedAcceptanceRecoveryItems) {
        $matchedAcceptanceRecoveryRow = @(
            $acceptanceRecoveryRows |
                Where-Object { $_.Name -eq $expectedAcceptanceRecoveryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedAcceptanceRecoveryRow) {
            throw "面板入口验收缺少失败后的处置动作固定子项：$($expectedAcceptanceRecoveryItem.Name)"
        }

        if ($matchedAcceptanceRecoveryRow.Description -ne $expectedAcceptanceRecoveryItem.Description) {
            throw "面板入口验收失败后的处置动作固定子项漂移：$($expectedAcceptanceRecoveryItem.Name) 期望 $($expectedAcceptanceRecoveryItem.Description)，实际 $($matchedAcceptanceRecoveryRow.Description)"
        }
    }

    $acceptanceTrialGateSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 与试跑阶段的关系固定槽位'
    if ([string]::IsNullOrWhiteSpace($acceptanceTrialGateSection)) {
        throw "面板入口验收未解析到与试跑阶段的关系固定槽位：$acceptanceDocPath"
    }

    $acceptanceTrialGateRows = @(
        [regex]::Matches($acceptanceTrialGateSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($acceptanceTrialGateRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedAcceptanceTrialGateItems | ForEach-Object { $_.Name }) -Label '面板入口验收与试跑阶段的关系固定槽位序列'
    foreach ($expectedAcceptanceTrialGateItem in $expectedAcceptanceTrialGateItems) {
        $matchedAcceptanceTrialGateRow = @(
            $acceptanceTrialGateRows |
                Where-Object { $_.Name -eq $expectedAcceptanceTrialGateItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedAcceptanceTrialGateRow) {
            throw "面板入口验收缺少与试跑阶段的关系固定槽位：$($expectedAcceptanceTrialGateItem.Name)"
        }

        if ($matchedAcceptanceTrialGateRow.Description -ne $expectedAcceptanceTrialGateItem.Description) {
            throw "面板入口验收与试跑阶段的关系固定槽位漂移：$($expectedAcceptanceTrialGateItem.Name) 期望 $($expectedAcceptanceTrialGateItem.Description)，实际 $($matchedAcceptanceTrialGateRow.Description)"
        }
    }

    $versionCommandSlotSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 丞相版本固定槽位' -SectionEndMarker '## 丞相检查固定槽位'
    if ([string]::IsNullOrWhiteSpace($versionCommandSlotSection)) {
        throw "面板入口验收未解析到丞相版本固定槽位：$acceptanceDocPath"
    }

    $versionCommandSlotRows = @(
        [regex]::Matches($versionCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($versionCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedVersionCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板入口验收丞相版本固定槽位序列'
    foreach ($expectedVersionCommandSlotItem in $expectedVersionCommandSlotItems) {
        $matchedVersionCommandSlotRow = @(
            $versionCommandSlotRows |
                Where-Object { $_.Name -eq $expectedVersionCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedVersionCommandSlotRow) {
            throw "面板入口验收缺少丞相版本固定槽位：$($expectedVersionCommandSlotItem.Name)"
        }

        if ($matchedVersionCommandSlotRow.Description -ne $expectedVersionCommandSlotItem.Description) {
            throw "面板入口验收丞相版本固定槽位漂移：$($expectedVersionCommandSlotItem.Name) 期望 $($expectedVersionCommandSlotItem.Description)，实际 $($matchedVersionCommandSlotRow.Description)"
        }
    }

    $checkCommandSlotSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 丞相检查固定槽位' -SectionEndMarker '## 丞相状态固定槽位'
    if ([string]::IsNullOrWhiteSpace($checkCommandSlotSection)) {
        throw "面板入口验收未解析到丞相检查固定槽位：$acceptanceDocPath"
    }

    $checkCommandSlotRows = @(
        [regex]::Matches($checkCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checkCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedCheckCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板入口验收丞相检查固定槽位序列'
    foreach ($expectedCheckCommandSlotItem in $expectedCheckCommandSlotItems) {
        $matchedCheckCommandSlotRow = @(
            $checkCommandSlotRows |
                Where-Object { $_.Name -eq $expectedCheckCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedCheckCommandSlotRow) {
            throw "面板入口验收缺少丞相检查固定槽位：$($expectedCheckCommandSlotItem.Name)"
        }

        if ($matchedCheckCommandSlotRow.Description -ne $expectedCheckCommandSlotItem.Description) {
            throw "面板入口验收丞相检查固定槽位漂移：$($expectedCheckCommandSlotItem.Name) 期望 $($expectedCheckCommandSlotItem.Description)，实际 $($matchedCheckCommandSlotRow.Description)"
        }
    }

    $statusCommandSlotSection = Get-FileSectionContent -FilePath $acceptanceDocPath -SectionStartMarker '## 丞相状态固定槽位' -SectionEndMarker '## 通过标准'
    if ([string]::IsNullOrWhiteSpace($statusCommandSlotSection)) {
        throw "面板入口验收未解析到丞相状态固定槽位：$acceptanceDocPath"
    }

    $statusCommandSlotRows = @(
        [regex]::Matches($statusCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($statusCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedStatusCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板入口验收丞相状态固定槽位序列'
    foreach ($expectedStatusCommandSlotItem in $expectedStatusCommandSlotItems) {
        $matchedStatusCommandSlotRow = @(
            $statusCommandSlotRows |
                Where-Object { $_.Name -eq $expectedStatusCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedStatusCommandSlotRow) {
            throw "面板入口验收缺少丞相状态固定槽位：$($expectedStatusCommandSlotItem.Name)"
        }

        if ($matchedStatusCommandSlotRow.Description -ne $expectedStatusCommandSlotItem.Description) {
            throw "面板入口验收丞相状态固定槽位漂移：$($expectedStatusCommandSlotItem.Name) 期望 $($expectedStatusCommandSlotItem.Description)，实际 $($matchedStatusCommandSlotRow.Description)"
        }
    }

    if (-not (Test-Path $checklistPath)) {
        throw "缺少面板人工验板清单：$checklistPath"
    }

    $checklistHelpSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 帮助命令公开用法' -SectionEndMarker '## 帮助命令固定结构'
    if ([string]::IsNullOrWhiteSpace($checklistHelpSection)) {
        throw "面板人工验板清单未解析到帮助命令公开用法：$checklistPath"
    }

    $checklistHelpRows = @(
        [regex]::Matches($checklistHelpSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Command = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistHelpRows | ForEach-Object { $_.Command }) -ExpectedValues $expectedHelpCommands -Label '面板人工验板清单帮助命令用法序列'
    foreach ($expectedHelpRow in $expectedHelpRows) {
        $matchedChecklistHelpRow = @(
            $checklistHelpRows |
                Where-Object { $_.Command -eq $expectedHelpRow.Command }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistHelpRow) {
            throw "面板人工验板清单缺少帮助命令用法：$($expectedHelpRow.Command)"
        }

        if ($matchedChecklistHelpRow.Description -ne $expectedHelpRow.Description) {
            throw "面板人工验板清单帮助命令用法漂移：$($expectedHelpRow.Command) 期望 $($expectedHelpRow.Description)，实际 $($matchedChecklistHelpRow.Description)"
        }
    }

    $checklistHelpTemplateSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 帮助命令固定结构' -SectionEndMarker '## 当前用法固定子项'
    if ([string]::IsNullOrWhiteSpace($checklistHelpTemplateSection)) {
        throw "面板人工验板清单未解析到帮助命令固定结构：$checklistPath"
    }

    $checklistHelpTemplateRows = @(
        [regex]::Matches($checklistHelpTemplateSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistHelpTemplateRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpTemplateItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单帮助命令固定结构序列'
    foreach ($expectedHelpTemplateItem in $expectedHelpTemplateItems) {
        $matchedChecklistHelpTemplateRow = @(
            $checklistHelpTemplateRows |
                Where-Object { $_.Name -eq $expectedHelpTemplateItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistHelpTemplateRow) {
            throw "面板人工验板清单缺少帮助命令固定结构项：$($expectedHelpTemplateItem.Name)"
        }

        if ($matchedChecklistHelpTemplateRow.Description -ne $expectedHelpTemplateItem.Description) {
            throw "面板人工验板清单帮助命令固定结构漂移：$($expectedHelpTemplateItem.Name) 期望 $($expectedHelpTemplateItem.Description)，实际 $($matchedChecklistHelpTemplateRow.Description)"
        }
    }

    $checklistHelpUsageSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 当前用法固定子项' -SectionEndMarker '## 面板命令固定子项'
    if ([string]::IsNullOrWhiteSpace($checklistHelpUsageSection)) {
        throw "面板人工验板清单未解析到当前用法固定子项：$checklistPath"
    }

    $checklistHelpUsageRows = @(
        [regex]::Matches($checklistHelpUsageSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistHelpUsageRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpUsageItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单当前用法固定子项序列'
    foreach ($expectedHelpUsageItem in $expectedHelpUsageItems) {
        $matchedChecklistHelpUsageRow = @(
            $checklistHelpUsageRows |
                Where-Object { $_.Name -eq $expectedHelpUsageItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistHelpUsageRow) {
            throw "面板人工验板清单缺少当前用法固定子项：$($expectedHelpUsageItem.Name)"
        }

        if ($matchedChecklistHelpUsageRow.Description -ne $expectedHelpUsageItem.Description) {
            throw "面板人工验板清单当前用法固定子项漂移：$($expectedHelpUsageItem.Name) 期望 $($expectedHelpUsageItem.Description)，实际 $($matchedChecklistHelpUsageRow.Description)"
        }
    }

    $checklistHelpPanelCommandSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 面板命令固定子项' -SectionEndMarker '## 注意事项固定子项'
    if ([string]::IsNullOrWhiteSpace($checklistHelpPanelCommandSection)) {
        throw "面板人工验板清单未解析到面板命令固定子项：$checklistPath"
    }

    $checklistHelpPanelCommandRows = @(
        [regex]::Matches($checklistHelpPanelCommandSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistHelpPanelCommandRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpPanelCommandItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单面板命令固定子项序列'
    foreach ($expectedHelpPanelCommandItem in $expectedHelpPanelCommandItems) {
        $matchedChecklistHelpPanelCommandRow = @(
            $checklistHelpPanelCommandRows |
                Where-Object { $_.Name -eq $expectedHelpPanelCommandItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistHelpPanelCommandRow) {
            throw "面板人工验板清单缺少面板命令固定子项：$($expectedHelpPanelCommandItem.Name)"
        }

        if ($matchedChecklistHelpPanelCommandRow.Description -ne $expectedHelpPanelCommandItem.Description) {
            throw "面板人工验板清单面板命令固定子项漂移：$($expectedHelpPanelCommandItem.Name) 期望 $($expectedHelpPanelCommandItem.Description)，实际 $($matchedChecklistHelpPanelCommandRow.Description)"
        }
    }

    $checklistHelpNoticeSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 注意事项固定子项' -SectionEndMarker '## 相关维护命令边界'
    if ([string]::IsNullOrWhiteSpace($checklistHelpNoticeSection)) {
        throw "面板人工验板清单未解析到注意事项固定子项：$checklistPath"
    }

    $checklistHelpNoticeRows = @(
        [regex]::Matches($checklistHelpNoticeSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistHelpNoticeRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedHelpNoticeItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单注意事项固定子项序列'
    foreach ($expectedHelpNoticeItem in $expectedHelpNoticeItems) {
        $matchedChecklistHelpNoticeRow = @(
            $checklistHelpNoticeRows |
                Where-Object { $_.Name -eq $expectedHelpNoticeItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistHelpNoticeRow) {
            throw "面板人工验板清单缺少注意事项固定子项：$($expectedHelpNoticeItem.Name)"
        }

        if ($matchedChecklistHelpNoticeRow.Description -ne $expectedHelpNoticeItem.Description) {
            throw "面板人工验板清单注意事项固定子项漂移：$($expectedHelpNoticeItem.Name) 期望 $($expectedHelpNoticeItem.Description)，实际 $($matchedChecklistHelpNoticeRow.Description)"
        }
    }

    $checklistBoundarySection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 相关维护命令边界' -SectionEndMarker '## 丞相修复固定槽位'
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

    $checklistRepairCommandSlotSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 丞相修复固定槽位' -SectionEndMarker '## 丞相验板固定槽位'
    if ([string]::IsNullOrWhiteSpace($checklistRepairCommandSlotSection)) {
        throw "面板人工验板清单未解析到丞相修复固定槽位：$checklistPath"
    }

    $checklistRepairCommandSlotRows = @(
        [regex]::Matches($checklistRepairCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistRepairCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedRepairCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单丞相修复固定槽位序列'
    foreach ($expectedRepairCommandSlotItem in $expectedRepairCommandSlotItems) {
        $matchedChecklistRepairCommandSlotRow = @(
            $checklistRepairCommandSlotRows |
                Where-Object { $_.Name -eq $expectedRepairCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistRepairCommandSlotRow) {
            throw "面板人工验板清单缺少丞相修复固定槽位：$($expectedRepairCommandSlotItem.Name)"
        }

        if ($matchedChecklistRepairCommandSlotRow.Description -ne $expectedRepairCommandSlotItem.Description) {
            throw "面板人工验板清单丞相修复固定槽位漂移：$($expectedRepairCommandSlotItem.Name) 期望 $($expectedRepairCommandSlotItem.Description)，实际 $($matchedChecklistRepairCommandSlotRow.Description)"
        }
    }

    $checklistPanelAcceptanceCommandSlotSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 丞相验板固定槽位' -SectionEndMarker '## 验板步骤'
    if ([string]::IsNullOrWhiteSpace($checklistPanelAcceptanceCommandSlotSection)) {
        throw "面板人工验板清单未解析到丞相验板固定槽位：$checklistPath"
    }

    $checklistPanelAcceptanceCommandSlotRows = @(
        [regex]::Matches($checklistPanelAcceptanceCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistPanelAcceptanceCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedPanelAcceptanceCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单丞相验板固定槽位序列'
    foreach ($expectedPanelAcceptanceCommandSlotItem in $expectedPanelAcceptanceCommandSlotItems) {
        $matchedChecklistPanelAcceptanceCommandSlotRow = @(
            $checklistPanelAcceptanceCommandSlotRows |
                Where-Object { $_.Name -eq $expectedPanelAcceptanceCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistPanelAcceptanceCommandSlotRow) {
            throw "面板人工验板清单缺少丞相验板固定槽位：$($expectedPanelAcceptanceCommandSlotItem.Name)"
        }

        if ($matchedChecklistPanelAcceptanceCommandSlotRow.Description -ne $expectedPanelAcceptanceCommandSlotItem.Description) {
            throw "面板人工验板清单丞相验板固定槽位漂移：$($expectedPanelAcceptanceCommandSlotItem.Name) 期望 $($expectedPanelAcceptanceCommandSlotItem.Description)，实际 $($matchedChecklistPanelAcceptanceCommandSlotRow.Description)"
        }
    }

    $checklistStepsSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 验板步骤' -SectionEndMarker '## 验板步骤固定子项'
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

    $checklistStepSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 验板步骤固定子项' -SectionEndMarker '## 丞相版本固定槽位'
    if ([string]::IsNullOrWhiteSpace($checklistStepSection)) {
        throw "面板人工验板清单未解析到验板步骤固定子项：$checklistPath"
    }

    $checklistStepRows = @(
        [regex]::Matches($checklistStepSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistStepRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedChecklistStepItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单验板步骤固定子项序列'
    foreach ($expectedChecklistStepItem in $expectedChecklistStepItems) {
        $matchedChecklistStepRow = @(
            $checklistStepRows |
                Where-Object { $_.Name -eq $expectedChecklistStepItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistStepRow) {
            throw "面板人工验板清单缺少验板步骤固定子项：$($expectedChecklistStepItem.Name)"
        }

        if ($matchedChecklistStepRow.Description -ne $expectedChecklistStepItem.Description) {
            throw "面板人工验板清单验板步骤固定子项漂移：$($expectedChecklistStepItem.Name) 期望 $($expectedChecklistStepItem.Description)，实际 $($matchedChecklistStepRow.Description)"
        }
    }

    $checklistVersionCommandSlotSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 丞相版本固定槽位' -SectionEndMarker '## 丞相检查固定槽位'
    if ([string]::IsNullOrWhiteSpace($checklistVersionCommandSlotSection)) {
        throw "面板人工验板清单未解析到丞相版本固定槽位：$checklistPath"
    }

    $checklistVersionCommandSlotRows = @(
        [regex]::Matches($checklistVersionCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistVersionCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedVersionCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单丞相版本固定槽位序列'
    foreach ($expectedVersionCommandSlotItem in $expectedVersionCommandSlotItems) {
        $matchedChecklistVersionCommandSlotRow = @(
            $checklistVersionCommandSlotRows |
                Where-Object { $_.Name -eq $expectedVersionCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistVersionCommandSlotRow) {
            throw "面板人工验板清单缺少丞相版本固定槽位：$($expectedVersionCommandSlotItem.Name)"
        }

        if ($matchedChecklistVersionCommandSlotRow.Description -ne $expectedVersionCommandSlotItem.Description) {
            throw "面板人工验板清单丞相版本固定槽位漂移：$($expectedVersionCommandSlotItem.Name) 期望 $($expectedVersionCommandSlotItem.Description)，实际 $($matchedChecklistVersionCommandSlotRow.Description)"
        }
    }

    $checklistCheckCommandSlotSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 丞相检查固定槽位' -SectionEndMarker '## 丞相状态固定槽位'
    if ([string]::IsNullOrWhiteSpace($checklistCheckCommandSlotSection)) {
        throw "面板人工验板清单未解析到丞相检查固定槽位：$checklistPath"
    }

    $checklistCheckCommandSlotRows = @(
        [regex]::Matches($checklistCheckCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistCheckCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedCheckCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单丞相检查固定槽位序列'
    foreach ($expectedCheckCommandSlotItem in $expectedCheckCommandSlotItems) {
        $matchedChecklistCheckCommandSlotRow = @(
            $checklistCheckCommandSlotRows |
                Where-Object { $_.Name -eq $expectedCheckCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistCheckCommandSlotRow) {
            throw "面板人工验板清单缺少丞相检查固定槽位：$($expectedCheckCommandSlotItem.Name)"
        }

        if ($matchedChecklistCheckCommandSlotRow.Description -ne $expectedCheckCommandSlotItem.Description) {
            throw "面板人工验板清单丞相检查固定槽位漂移：$($expectedCheckCommandSlotItem.Name) 期望 $($expectedCheckCommandSlotItem.Description)，实际 $($matchedChecklistCheckCommandSlotRow.Description)"
        }
    }

    $checklistStatusCommandSlotSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 丞相状态固定槽位' -SectionEndMarker '## 通过标准'
    if ([string]::IsNullOrWhiteSpace($checklistStatusCommandSlotSection)) {
        throw "面板人工验板清单未解析到丞相状态固定槽位：$checklistPath"
    }

    $checklistStatusCommandSlotRows = @(
        [regex]::Matches($checklistStatusCommandSlotSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistStatusCommandSlotRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedStatusCommandSlotItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单丞相状态固定槽位序列'
    foreach ($expectedStatusCommandSlotItem in $expectedStatusCommandSlotItems) {
        $matchedChecklistStatusCommandSlotRow = @(
            $checklistStatusCommandSlotRows |
                Where-Object { $_.Name -eq $expectedStatusCommandSlotItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistStatusCommandSlotRow) {
            throw "面板人工验板清单缺少丞相状态固定槽位：$($expectedStatusCommandSlotItem.Name)"
        }

        if ($matchedChecklistStatusCommandSlotRow.Description -ne $expectedStatusCommandSlotItem.Description) {
            throw "面板人工验板清单丞相状态固定槽位漂移：$($expectedStatusCommandSlotItem.Name) 期望 $($expectedStatusCommandSlotItem.Description)，实际 $($matchedChecklistStatusCommandSlotRow.Description)"
        }
    }

    $checklistPassSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 通过标准' -SectionEndMarker '## 通过标准固定子项'
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

    $checklistPassItemSection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 通过标准固定子项' -SectionEndMarker '## 若不通过'
    if ([string]::IsNullOrWhiteSpace($checklistPassItemSection)) {
        throw "面板人工验板清单未解析到通过标准固定子项：$checklistPath"
    }

    $checklistPassItemRows = @(
        [regex]::Matches($checklistPassItemSection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistPassItemRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedChecklistPassItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单通过标准固定子项序列'
    foreach ($expectedChecklistPassItem in $expectedChecklistPassItems) {
        $matchedChecklistPassItemRow = @(
            $checklistPassItemRows |
                Where-Object { $_.Name -eq $expectedChecklistPassItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistPassItemRow) {
            throw "面板人工验板清单缺少通过标准固定子项：$($expectedChecklistPassItem.Name)"
        }

        if ($matchedChecklistPassItemRow.Description -ne $expectedChecklistPassItem.Description) {
            throw "面板人工验板清单通过标准固定子项漂移：$($expectedChecklistPassItem.Name) 期望 $($expectedChecklistPassItem.Description)，实际 $($matchedChecklistPassItemRow.Description)"
        }
    }

    $checklistRecoverySection = Get-FileSectionContent -FilePath $checklistPath -SectionStartMarker '## 若不通过固定子项'
    if ([string]::IsNullOrWhiteSpace($checklistRecoverySection)) {
        throw "面板人工验板清单未解析到若不通过固定子项：$checklistPath"
    }

    $checklistRecoveryRows = @(
        [regex]::Matches($checklistRecoverySection, '(?m)^- `([^`]+)`：(.+?)。?\r?$') |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.Groups[1].Value
                    Description = ($_.Groups[2].Value.Trim() -replace '。$','')
                }
            }
    )
    Assert-ExactOrderedValues -SourceValues @($checklistRecoveryRows | ForEach-Object { $_.Name }) -ExpectedValues @($expectedChecklistRecoveryItems | ForEach-Object { $_.Name }) -Label '面板人工验板清单若不通过固定子项序列'
    foreach ($expectedChecklistRecoveryItem in $expectedChecklistRecoveryItems) {
        $matchedChecklistRecoveryRow = @(
            $checklistRecoveryRows |
                Where-Object { $_.Name -eq $expectedChecklistRecoveryItem.Name }
        ) | Select-Object -First 1
        if ($null -eq $matchedChecklistRecoveryRow) {
            throw "面板人工验板清单缺少若不通过固定子项：$($expectedChecklistRecoveryItem.Name)"
        }

        if ($matchedChecklistRecoveryRow.Description -ne $expectedChecklistRecoveryItem.Description) {
            throw "面板人工验板清单若不通过固定子项漂移：$($expectedChecklistRecoveryItem.Name) 期望 $($expectedChecklistRecoveryItem.Description)，实际 $($matchedChecklistRecoveryRow.Description)"
        }
    }

    return [pscustomobject]@{
        PanelCommands = $expectedPanelCommands
        ChecklistCommands = $expectedChecklistCommands
        AcceptanceRows = @($expectedAcceptanceRows)
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
        RegexPattern = '`(docs/(?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/(?:03|10|11|14|15|16|17|18|19|20|21)-[^`]+\.md)|(?:90-归档/01-[^`]+\.md)))`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 维护层补充入口'
        RegexPattern = '`((?:(?:30-方案/08-[^`]+\.md)|(?:40-执行/(?:03|10|11|14|15|16|17|18|19|20|21)-[^`]+\.md)|(?:90-归档/01-[^`]+\.md)))`'
        PathPrefix = 'docs/'
    }
)
$publicMaintenanceCapabilityOrderEntryChecks = @(
    @{
        Path = 'README.md'
        Label = 'README 维护层补充入口'
        RegexPattern = '`(docs/(?:(?:40-执行/03-[^`]+\.md)|(?:30-方案/08-[^`]+\.md)|(?:40-执行/21-[^`]+\.md)))`'
        PathPrefix = ''
    },
    @{
        Path = 'docs/README.md'
        Label = 'docs/README 维护层补充入口'
        RegexPattern = '`((?:(?:40-执行/03-[^`]+\.md)|(?:30-方案/08-[^`]+\.md)|(?:40-执行/21-[^`]+\.md)))`'
        PathPrefix = 'docs/'
    }
)
$criticalMaintenanceCapabilityOrderPaths = @(
    'docs/40-执行/03-面板入口验收.md'
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
