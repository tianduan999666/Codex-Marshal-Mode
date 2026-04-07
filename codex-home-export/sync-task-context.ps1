param(
    [ValidateSet('snapshot', 'write', 'read')]
    [string]$Mode = 'snapshot',
    [string]$RepoRootPath = '',
    [string]$TargetCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$TaskId = '',
    [string]$BackgroundSummary = '',
    [string]$OverallGoal = '',
    [string]$RecommendedApproach = '',
    [string]$NextStepText = '',
    [string[]]$ImportantNotes = @(),
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRootPath)) {
    $RepoRootPath = Join-Path $scriptRootPath '..'
}

$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$versionSourcePath = Join-Path $scriptRootPath 'VERSION.json'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'
$taskStartStatePath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode\task-start-state.json'
$activeTaskPath = Join-Path $resolvedRepoRootPath '.codex\chancellor\active-task.txt'

function Get-TrimmedSingleLine([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ''
    }

    return (($Text -replace '\r?\n+', ' ') -replace '\s{2,}', ' ').Trim()
}

function Get-TaskYamlScalarValue {
    param(
        [string]$Content,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return ''
    }

    $pattern = '(?m)^{0}:\s*(.+?)\s*$' -f [regex]::Escape($Key)
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return ''
    }

    return Get-TrimmedSingleLine -Text $match.Groups[1].Value
}

function Get-TaskYamlBlockValue {
    param(
        [string]$Content,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return ''
    }

    $pattern = '(?ms)^{0}:\s*>-\s*\r?\n(?<body>(?:[ ]{{2}}.*(?:\r?\n|$))+)' -f [regex]::Escape($Key)
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return ''
    }

    $lines = @(
        ($match.Groups['body'].Value -split '\r?\n') |
            ForEach-Object {
                if ($_.StartsWith('  ')) {
                    $_.Substring(2)
                }
                else {
                    $_
                }
            }
    )

    return (($lines -join "`n").Trim())
}

function Get-TaskYamlListValue {
    param(
        [string]$Content,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return @()
    }

    $emptyPattern = '(?m)^{0}:\s*\[\s*\]\s*$' -f [regex]::Escape($Key)
    if ([regex]::IsMatch($Content, $emptyPattern)) {
        return @()
    }

    $pattern = '(?ms)^{0}:\s*\r?\n(?<body>(?:[ ]{{2}}-\s*.*(?:\r?\n|$))+)' -f [regex]::Escape($Key)
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return @()
    }

    return @(
        ($match.Groups['body'].Value -split '\r?\n') |
            ForEach-Object {
                $line = $_.Trim()
                if ($line.StartsWith('-')) {
                    $line.Substring(1).Trim()
                }
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-MarkdownSectionBody {
    param(
        [string]$Content,
        [string]$Heading
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return ''
    }

    $pattern = '(?ms)^##\s*{0}\s*\r?\n(?<body>.*?)(?=^##\s+|\z)' -f [regex]::Escape($Heading)
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return ''
    }

    return $match.Groups['body'].Value.Trim()
}

function Get-MarkdownBulletLines {
    param([string]$SectionBody)

    if ([string]::IsNullOrWhiteSpace($SectionBody)) {
        return @()
    }

    return @(
        ($SectionBody -split '\r?\n') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -like '- *' } |
            ForEach-Object { $_.Substring(1).Trim() }
    )
}

function Get-MarkdownSectionParagraph {
    param([string]$SectionBody)

    if ([string]::IsNullOrWhiteSpace($SectionBody)) {
        return ''
    }

    $lines = @(
        ($SectionBody -split '\r?\n') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    if ($lines.Count -eq 0) {
        return ''
    }

    return Get-TrimmedSingleLine -Text ($lines -join ' ')
}

function Get-LatestDecisionSummary([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return ''
    }

    $matches = [regex]::Matches($Content, '(?ms)^##\s*(?<title>.+?)\s*\r?\n(?<body>.*?)(?=^##\s+|\z)')
    if ($matches.Count -eq 0) {
        return ''
    }

    $lastMatch = $matches[$matches.Count - 1]
    $decisionLines = @(
        ($lastMatch.Groups['body'].Value -split '\r?\n') |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -like '- *' } |
            Select-Object -First 3 |
            ForEach-Object { $_.Substring(1).Trim() }
    )
    if ($decisionLines.Count -eq 0) {
        return Get-TrimmedSingleLine -Text $lastMatch.Groups['title'].Value
    }

    return ($decisionLines -join '；')
}

function Read-JsonFileOrNull([string]$Path) {
    if (-not (Test-Path $Path)) {
        return $null
    }

    return (Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json)
}

function Resolve-RepoRelativePath {
    param(
        [string]$AbsolutePath,
        [string]$RepoRootPath
    )

    $normalizedAbsolute = [System.IO.Path]::GetFullPath($AbsolutePath)
    $normalizedRepoRoot = [System.IO.Path]::GetFullPath($RepoRootPath)
    if (-not $normalizedRepoRoot.EndsWith('\')) {
        $normalizedRepoRoot = $normalizedRepoRoot + '\'
    }

    if ($normalizedAbsolute.StartsWith($normalizedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $normalizedAbsolute.Substring($normalizedRepoRoot.Length).Replace('\', '/')
    }

    return $normalizedAbsolute
}

function Get-ActiveTaskContext {
    param(
        [string]$ResolvedRepoRootPath,
        [string]$PreferredTaskId
    )

    $resolvedTaskId = Get-TrimmedSingleLine -Text $PreferredTaskId
    if ([string]::IsNullOrWhiteSpace($resolvedTaskId)) {
        if (-not (Test-Path $activeTaskPath)) {
            throw '当前没有激活任务，不能同步任务上下文。'
        }

        $resolvedTaskId = Get-TrimmedSingleLine -Text ((Get-Content -Path $activeTaskPath | Select-Object -First 1))
    }

    if ([string]::IsNullOrWhiteSpace($resolvedTaskId)) {
        throw 'active-task.txt 为空，当前没有可同步的任务。'
    }

    $taskRootPath = Join-Path $ResolvedRepoRootPath ('.codex\chancellor\tasks\{0}' -f $resolvedTaskId)
    if (-not (Test-Path $taskRootPath)) {
        throw ("当前激活任务目录不存在：{0}" -f $taskRootPath)
    }

    $contractPath = Join-Path $taskRootPath 'contract.yaml'
    $statePath = Join-Path $taskRootPath 'state.yaml'
    $decisionLogPath = Join-Path $taskRootPath 'decision-log.md'
    $resultPath = Join-Path $taskRootPath 'result.md'
    foreach ($requiredPath in @($contractPath, $statePath, $decisionLogPath, $resultPath)) {
        if (-not (Test-Path $requiredPath)) {
            throw ("任务上下文缺少必要文件：{0}" -f $requiredPath)
        }
    }

    return [pscustomobject]@{
        TaskId = $resolvedTaskId
        TaskRootPath = $taskRootPath
        ContractPath = $contractPath
        StatePath = $statePath
        DecisionLogPath = $decisionLogPath
        ResultPath = $resultPath
        ProgressSnapshotPath = Join-Path $taskRootPath 'progress-snapshot.md'
        HandoffPath = Join-Path $taskRootPath 'handoff.md'
    }
}

function Get-TaskSummaryData([object]$TaskContext) {
    $contractContent = Get-Content -Raw -Encoding UTF8 -Path $TaskContext.ContractPath
    $stateContent = Get-Content -Raw -Encoding UTF8 -Path $TaskContext.StatePath
    $decisionLogContent = Get-Content -Raw -Encoding UTF8 -Path $TaskContext.DecisionLogPath
    $resultContent = Get-Content -Raw -Encoding UTF8 -Path $TaskContext.ResultPath
    $runtimeVersionInfo = Read-JsonFileOrNull -Path $runtimeVersionPath
    $taskStartState = Read-JsonFileOrNull -Path $taskStartStatePath

    $taskTitle = Get-TaskYamlScalarValue -Content $contractContent -Key 'title'
    $goalText = Get-TaskYamlBlockValue -Content $contractContent -Key 'goal'
    $planningHint = Get-TaskYamlBlockValue -Content $contractContent -Key 'planning_hint'
    $status = Get-TaskYamlScalarValue -Content $stateContent -Key 'status'
    $riskLevel = Get-TaskYamlScalarValue -Content $stateContent -Key 'risk_level'
    $nextAction = Get-TaskYamlScalarValue -Content $stateContent -Key 'next_action'
    $updatedAt = Get-TaskYamlScalarValue -Content $stateContent -Key 'updated_at'
    $phaseHint = Get-TaskYamlScalarValue -Content $stateContent -Key 'phase_hint'
    $planStep = Get-TaskYamlScalarValue -Content $stateContent -Key 'plan_step'
    $verifySignal = Get-TaskYamlScalarValue -Content $stateContent -Key 'verify_signal'
    $blockedByItems = Get-TaskYamlListValue -Content $stateContent -Key 'blocked_by'
    $completedItems = Get-MarkdownBulletLines -SectionBody (Get-MarkdownSectionBody -Content $resultContent -Heading '已完成')
    $leftoverItems = Get-MarkdownBulletLines -SectionBody (Get-MarkdownSectionBody -Content $resultContent -Heading '遗留事项')
    $nextSuggestionItems = Get-MarkdownBulletLines -SectionBody (Get-MarkdownSectionBody -Content $resultContent -Heading '下一步建议')
    $latestDecisionSummary = Get-LatestDecisionSummary -Content $decisionLogContent

    if ([string]::IsNullOrWhiteSpace($goalText)) {
        $goalText = ('围绕“{0}”完成当前轮最小闭环推进。' -f $taskTitle)
    }
    if ([string]::IsNullOrWhiteSpace($planStep)) {
        $planStep = $nextAction
    }
    if ([string]::IsNullOrWhiteSpace($planningHint)) {
        $planningHint = $planStep
    }

    $lastCheckValue = ''
    if (($null -ne $taskStartState) -and (-not [string]::IsNullOrWhiteSpace([string]$taskStartState.verified_at))) {
        $lastCheckValue = [string]$taskStartState.verified_at
    }
    elseif (($null -ne $taskStartState) -and (-not [string]::IsNullOrWhiteSpace([string]$taskStartState.verify_status))) {
        $lastCheckValue = [string]$taskStartState.verify_status
    }
    else {
        $lastCheckValue = '未记录'
    }

    $runtimeVersion = if ($null -ne $runtimeVersionInfo) { [string]$runtimeVersionInfo.cx_version } else { '' }
    if ([string]::IsNullOrWhiteSpace($runtimeVersion) -and (Test-Path $versionSourcePath)) {
        $sourceVersionInfo = Read-JsonFileOrNull -Path $versionSourcePath
        if ($null -ne $sourceVersionInfo) {
            $runtimeVersion = [string]$sourceVersionInfo.cx_version
        }
    }

    return [pscustomobject]@{
        TaskId = $TaskContext.TaskId
        TaskTitle = $taskTitle
        TaskDisplay = if ([string]::IsNullOrWhiteSpace($taskTitle)) { $TaskContext.TaskId } else { '{0}（{1}）' -f $TaskContext.TaskId, $taskTitle }
        GoalText = Get-TrimmedSingleLine -Text $goalText
        PlanningHint = Get-TrimmedSingleLine -Text $planningHint
        Status = $status
        RiskLevel = $riskLevel
        NextAction = $nextAction
        UpdatedAt = $updatedAt
        PhaseHint = $phaseHint
        PlanStep = $planStep
        VerifySignal = $verifySignal
        BlockedByItems = @($blockedByItems)
        CompletedItems = @($completedItems)
        LeftoverItems = @($leftoverItems)
        NextSuggestionItems = @($nextSuggestionItems)
        LatestDecisionSummary = $latestDecisionSummary
        RuntimeVersion = $runtimeVersion
        LastCheckValue = $lastCheckValue
        ProgressSnapshotPath = $TaskContext.ProgressSnapshotPath
        HandoffPath = $TaskContext.HandoffPath
    }
}

function New-TaskProgressSnapshotContent([object]$TaskData) {
    $blockedByText = if ($TaskData.BlockedByItems.Count -eq 0) { '无' } else { $TaskData.BlockedByItems -join '；' }
    $completedText = if ($TaskData.CompletedItems.Count -eq 0) { '暂无已完成摘要' } else { ($TaskData.CompletedItems -join '；') }
    $leftoverText = if ($TaskData.LeftoverItems.Count -eq 0) { '暂无明确遗留项' } else { ($TaskData.LeftoverItems -join '；') }
    $nextSuggestionText = if ($TaskData.NextSuggestionItems.Count -eq 0) { $TaskData.NextAction } else { ($TaskData.NextSuggestionItems -join '；') }
    $decisionText = if ([string]::IsNullOrWhiteSpace($TaskData.LatestDecisionSummary)) { '暂无额外关键决策摘要' } else { $TaskData.LatestDecisionSummary }
    $snapshotRelativePath = Resolve-RepoRelativePath -AbsolutePath $TaskData.ProgressSnapshotPath -RepoRootPath $resolvedRepoRootPath
    $taskDirectoryRelativePath = Resolve-RepoRelativePath -AbsolutePath (Split-Path -Parent $TaskData.ProgressSnapshotPath) -RepoRootPath $resolvedRepoRootPath

    return (
        @(
            '# 任务级进度快照'
            ''
            ('- 生成时间：{0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
            ('- 任务编号：{0}' -f $TaskData.TaskId)
            ('- 任务标题：{0}' -f $TaskData.TaskTitle)
            ('- 当前状态：{0}' -f $TaskData.Status)
            ('- 风险等级：{0}' -f $TaskData.RiskLevel)
            ('- 当前版本：{0}' -f $TaskData.RuntimeVersion)
            ('- 上次检查：{0}' -f $TaskData.LastCheckValue)
            ('- 任务目录：{0}' -f $taskDirectoryRelativePath)
            ('- 快照文件：{0}' -f $snapshotRelativePath)
            ''
            '## 当前目标'
            ''
            $TaskData.GoalText
            ''
            '## 当前推进面'
            ''
            ('- 下一步：{0}' -f $TaskData.NextAction)
            ('- 最小推进步：{0}' -f $TaskData.PlanStep)
            ('- 验证信号：{0}' -f $TaskData.VerifySignal)
            ('- 当前阶段：{0}' -f $TaskData.PhaseHint)
            ('- 最近更新时间：{0}' -f $TaskData.UpdatedAt)
            ('- 当前阻塞：{0}' -f $blockedByText)
            ''
            '## 已有结果'
            ''
            ('- 已完成：{0}' -f $completedText)
            ('- 遗留事项：{0}' -f $leftoverText)
            ''
            '## 最新决策'
            ''
            ('- {0}' -f $decisionText)
            ''
            '## 下轮建议'
            ''
            ('- {0}' -f $nextSuggestionText)
            '- 如需跨聊天续做，优先读取同目录下的 `handoff.md`'
        ) -join [Environment]::NewLine
    )
}

function New-HandoffPayload {
    param(
        [object]$TaskData,
        [string]$BackgroundSummaryText,
        [string]$OverallGoalText,
        [string]$RecommendedApproachText,
        [string]$NextStepValue,
        [string[]]$ImportantNoteLines
    )

    $defaultBackgroundSummary = if ($TaskData.CompletedItems.Count -eq 0) {
        ('当前任务处于 {0}，正在围绕“{1}”推进。' -f $TaskData.Status, $TaskData.TaskTitle)
    }
    else {
        ('当前任务处于 {0}，已完成：{1}。' -f $TaskData.Status, ($TaskData.CompletedItems -join '；'))
    }
    $defaultRecommendedApproach = if (-not [string]::IsNullOrWhiteSpace($TaskData.PlanStep)) {
        $TaskData.PlanStep
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TaskData.PlanningHint)) {
        $TaskData.PlanningHint
    }
    else {
        $TaskData.NextAction
    }
    $resolvedBackground = Get-TrimmedSingleLine -Text $BackgroundSummaryText
    $resolvedOverallGoal = Get-TrimmedSingleLine -Text $OverallGoalText
    $resolvedRecommendedApproach = Get-TrimmedSingleLine -Text $RecommendedApproachText
    $resolvedNextStep = Get-TrimmedSingleLine -Text $NextStepValue
    $resolvedImportantNotes = @(
        $ImportantNoteLines |
            ForEach-Object { Get-TrimmedSingleLine -Text $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ([string]::IsNullOrWhiteSpace($resolvedBackground)) {
        $resolvedBackground = Get-TrimmedSingleLine -Text $defaultBackgroundSummary
    }
    if ([string]::IsNullOrWhiteSpace($resolvedOverallGoal)) {
        $resolvedOverallGoal = Get-TrimmedSingleLine -Text $TaskData.GoalText
    }
    if ([string]::IsNullOrWhiteSpace($resolvedRecommendedApproach)) {
        $resolvedRecommendedApproach = Get-TrimmedSingleLine -Text $defaultRecommendedApproach
    }
    if ([string]::IsNullOrWhiteSpace($resolvedNextStep)) {
        $resolvedNextStep = Get-TrimmedSingleLine -Text $TaskData.NextAction
    }
    if ($resolvedImportantNotes.Count -eq 0) {
        $resolvedImportantNotes = @(
            '交班文件与任务快照都挂在当前任务目录。'
            '对外涉及未公开项目时，统一代称写“业务项目”。'
        )
    }

    return [pscustomobject]@{
        BackgroundSummary = $resolvedBackground
        OverallGoal = $resolvedOverallGoal
        RecommendedApproach = $resolvedRecommendedApproach
        NextStepText = $resolvedNextStep
        ImportantNotes = @($resolvedImportantNotes)
    }
}

function Read-HandoffPayload {
    param(
        [object]$TaskData,
        [string]$HandoffPath
    )

    if (-not (Test-Path $HandoffPath)) {
        return $null
    }

    $handoffContent = Get-Content -Raw -Encoding UTF8 -Path $HandoffPath
    return [pscustomobject]@{
        BackgroundSummary = Get-MarkdownSectionParagraph -SectionBody (Get-MarkdownSectionBody -Content $handoffContent -Heading '本轮背景')
        OverallGoal = Get-MarkdownSectionParagraph -SectionBody (Get-MarkdownSectionBody -Content $handoffContent -Heading '整体要做什么')
        RecommendedApproach = Get-MarkdownSectionParagraph -SectionBody (Get-MarkdownSectionBody -Content $handoffContent -Heading '建议怎么做')
        NextStepText = Get-MarkdownSectionParagraph -SectionBody (Get-MarkdownSectionBody -Content $handoffContent -Heading '下一步')
        ImportantNotes = Get-MarkdownBulletLines -SectionBody (Get-MarkdownSectionBody -Content $handoffContent -Heading '必要提醒')
    }
}

function Write-Utf8TextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parentPath = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        New-Item -ItemType Directory -Force -Path $parentPath | Out-Null
    }

    Set-Content -Path $Path -Value $Content -Encoding UTF8
}

$taskContext = Get-ActiveTaskContext -ResolvedRepoRootPath $resolvedRepoRootPath -PreferredTaskId $TaskId
$taskData = Get-TaskSummaryData -TaskContext $taskContext
$snapshotContent = New-TaskProgressSnapshotContent -TaskData $taskData
Write-Utf8TextFile -Path $taskData.ProgressSnapshotPath -Content $snapshotContent

switch ($Mode) {
    'snapshot' {
        if (-not $Quiet) {
            Write-Output '已完成：已刷新当前任务快照。'
            Write-Output ('任务编号：{0}' -f $taskData.TaskDisplay)
            Write-Output ('进度快照：{0}' -f (Resolve-RepoRelativePath -AbsolutePath $taskData.ProgressSnapshotPath -RepoRootPath $resolvedRepoRootPath))
            Write-Output ('当前状态：{0}' -f $taskData.Status)
            Write-Output ('下一步：{0}' -f $taskData.NextAction)
        }
        break
    }
    'write' {
        $handoffPayload = New-HandoffPayload `
            -TaskData $taskData `
            -BackgroundSummaryText $BackgroundSummary `
            -OverallGoalText $OverallGoal `
            -RecommendedApproachText $RecommendedApproach `
            -NextStepValue $NextStepText `
            -ImportantNoteLines $ImportantNotes
        $snapshotRelativePath = Resolve-RepoRelativePath -AbsolutePath $taskData.ProgressSnapshotPath -RepoRootPath $resolvedRepoRootPath
        $handoffRelativePath = Resolve-RepoRelativePath -AbsolutePath $taskData.HandoffPath -RepoRootPath $resolvedRepoRootPath
        $noteLines = @($handoffPayload.ImportantNotes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($noteLines.Count -eq 0) {
            $noteLines = @('无')
        }
        $handoffContent = (
            @(
                '# 交班单'
                ''
                ('- 生成时间：{0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
                ('- 任务编号：{0}' -f $taskData.TaskId)
                ('- 任务标题：{0}' -f $taskData.TaskTitle)
                ('- 当前状态：{0}' -f $taskData.Status)
                ('- 当前版本：{0}' -f $taskData.RuntimeVersion)
                ('- 快照文件：{0}' -f $snapshotRelativePath)
                ('- 交班文件：{0}' -f $handoffRelativePath)
                ''
                '## 本轮背景'
                ''
                $handoffPayload.BackgroundSummary
                ''
                '## 整体要做什么'
                ''
                $handoffPayload.OverallGoal
                ''
                '## 建议怎么做'
                ''
                $handoffPayload.RecommendedApproach
                ''
                '## 下一步'
                ''
                $handoffPayload.NextStepText
                ''
                '## 必要提醒'
                ''
            ) + @(
                $noteLines | ForEach-Object { '- ' + (Get-TrimmedSingleLine -Text $_) }
            )
        ) -join [Environment]::NewLine
        Write-Utf8TextFile -Path $taskData.HandoffPath -Content $handoffContent

        if (-not $Quiet) {
            Write-Output '已完成：已为当前任务生成交班材料。'
            Write-Output ('任务编号：{0}' -f $taskData.TaskDisplay)
            Write-Output ('进度快照：{0}' -f (Resolve-RepoRelativePath -AbsolutePath $taskData.ProgressSnapshotPath -RepoRootPath $resolvedRepoRootPath))
            Write-Output ('交班文件：{0}' -f (Resolve-RepoRelativePath -AbsolutePath $taskData.HandoffPath -RepoRootPath $resolvedRepoRootPath))
            Write-Output ('当前状态：{0}' -f $taskData.Status)
            Write-Output '下一步：新聊天只需输入 `传令：接班`。'
        }
        break
    }
    'read' {
        $handoffPayload = Read-HandoffPayload -TaskData $taskData -HandoffPath $taskData.HandoffPath
        $handoffLocationLine = ''
        if ($null -eq $handoffPayload) {
            $handoffPayload = New-HandoffPayload `
                -TaskData $taskData `
                -BackgroundSummaryText '' `
                -OverallGoalText '' `
                -RecommendedApproachText '' `
                -NextStepValue '' `
                -ImportantNoteLines @()
            $handoffLocationLine = '交班文件：未找到 handoff.md，已按当前任务包临时重建接班摘要。'
        }
        else {
            $handoffLocationLine = ('交班文件：{0}' -f (Resolve-RepoRelativePath -AbsolutePath $taskData.HandoffPath -RepoRootPath $resolvedRepoRootPath))
        }

        if (-not $Quiet) {
            Write-Output ('当前任务：{0}' -f $taskData.TaskDisplay)
            Write-Output $handoffLocationLine
            Write-Output ('背景：{0}' -f $handoffPayload.BackgroundSummary)
            Write-Output ('整体要做：{0}' -f $handoffPayload.OverallGoal)
            Write-Output ('怎么做：{0}' -f $handoffPayload.RecommendedApproach)
            Write-Output ('下一步：{0}' -f $handoffPayload.NextStepText)
        }
        break
    }
}
