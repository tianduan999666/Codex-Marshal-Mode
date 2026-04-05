param(
    [string]$RepoRootPath = '.',
    [string]$DocPath = '',
    [string]$TargetCodexHome = '',
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Read-JsonFile {
    param([string]$Path)

    return Get-Content -Raw -Encoding UTF8 -Path $Path | ConvertFrom-Json
}

function Get-YamlScalarValue {
    param(
        [string[]]$Lines,
        [string]$Key
    )

    $pattern = '^{0}:\s*(.+)$' -f [regex]::Escape($Key)
    $match = $Lines | Select-String -Pattern $pattern | Select-Object -First 1
    if (-not $match) {
        return $null
    }

    $value = $match.Matches[0].Groups[1].Value.Trim()
    if ($value -match "^'(.*)'$") {
        return $Matches[1]
    }

    if ($value -match '^"(.*)"$') {
        return $Matches[1]
    }

    return $value
}

function Get-TaskStateSummary {
    param(
        [string]$TasksRootPath,
        [string]$Prefix
    )

    $taskDirectories = @(
        Get-ChildItem -Path $TasksRootPath -Directory |
            Where-Object { $_.Name -like ($Prefix + '*') } |
            Sort-Object Name
    )

    $doneCount = 0
    foreach ($taskDirectory in $taskDirectories) {
        $stateFilePath = Join-Path $taskDirectory.FullName 'state.yaml'
        if (-not (Test-Path $stateFilePath)) {
            continue
        }

        $status = Get-YamlScalarValue -Lines (Get-Content $stateFilePath) -Key 'status'
        if ($status -eq 'done') {
            $doneCount++
        }
    }

    return [pscustomobject]@{
        TotalCount = $taskDirectories.Count
        DoneCount = $doneCount
    }
}

function Get-ActiveTaskSummary {
    param(
        [string]$RepoRootPath,
        [string]$ActiveTaskFilePath,
        [string]$TasksRootPath
    )

    if (-not (Test-Path $ActiveTaskFilePath)) {
        return '未发现 `active-task.txt`。'
    }

    $activeTaskId = @(
        Get-Content $ActiveTaskFilePath |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    ) | Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($activeTaskId)) {
        return '无激活任务；`active-task.txt` 为空'
    }

    $taskRootPath = Join-Path $TasksRootPath $activeTaskId
    if (-not (Test-Path $taskRootPath -PathType Container)) {
        return ('`active-task.txt` 指向 `{0}`，但对应任务目录不存在' -f $activeTaskId)
    }

    $stateFilePath = Join-Path $taskRootPath 'state.yaml'
    $contractFilePath = Join-Path $taskRootPath 'contract.yaml'
    $status = if (Test-Path $stateFilePath) {
        Get-YamlScalarValue -Lines (Get-Content $stateFilePath) -Key 'status'
    }
    else {
        '<missing-state>'
    }
    $title = if (Test-Path $contractFilePath) {
        Get-YamlScalarValue -Lines (Get-Content $contractFilePath) -Key 'title'
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($title)) {
        return ('当前激活任务：`{0}`；状态=`{1}`' -f $activeTaskId, $status)
    }

    return ('当前激活任务：`{0}`（{1}）；状态=`{2}`' -f $activeTaskId, $title, $status)
}

function Get-VersionCredibilitySummary {
    param(
        [string]$SourceVersion,
        [string]$ManifestVersion,
        [string]$InstallRecordVersion,
        [string]$RuntimeVersion
    )

    $uniqueVersions = @(
        @($SourceVersion, $ManifestVersion, $InstallRecordVersion, $RuntimeVersion) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    if ($uniqueVersions.Count -eq 1) {
        return ('`manifest.version = VERSION.json.cx_version = install-record.cx_version = runtime_version = {0}`' -f $uniqueVersions[0])
    }

    return ('发现版本不一致：`manifest={0}`；`VERSION.json={1}`；`install-record={2}`；`runtime={3}`' -f $ManifestVersion, $SourceVersion, $InstallRecordVersion, $RuntimeVersion)
}

function Get-RuntimeSyncSummary {
    param(
        [pscustomobject]$InstallRecord,
        [pscustomobject]$TaskStartState
    )

    $syncedFileCount = @($InstallRecord.synced_files).Count
    $verifiedAt = [string]$TaskStartState.verified_at
    $verifyStatus = [string]$TaskStartState.verify_status
    $lightCheckItems = @($TaskStartState.light_check_hashes)
    $lightCheckMatched = @(
        $lightCheckItems |
            Where-Object { $_.source_sha256 -eq $_.runtime_sha256 }
    ).Count

    return ('已同步 `{0}` 个受管文件；`verify_status={1}`；上次检查时间为 `{2}`；轻检 `{3}/{4}` 哈希一致' -f $syncedFileCount, $verifyStatus, $verifiedAt, $lightCheckMatched, $lightCheckItems.Count)
}

function Set-ExactLineValue {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Replacement
    )

    if (-not [regex]::IsMatch($Content, $Pattern)) {
        throw "未找到需要替换的内容：$Pattern"
    }

    $updatedContent = [regex]::Replace($Content, $Pattern, $Replacement)
    return $updatedContent
}

$resolvedRepoRootPath = [System.IO.Path]::GetFullPath($RepoRootPath)
if ([string]::IsNullOrWhiteSpace($DocPath)) {
    $DocPath = Join-Path $resolvedRepoRootPath 'docs\40-执行\35-V4-当前真实状态总表.md'
}
if ([string]::IsNullOrWhiteSpace($TargetCodexHome)) {
    $TargetCodexHome = Join-Path $env:USERPROFILE '.codex'
}

$resolvedDocPath = [System.IO.Path]::GetFullPath($DocPath)
$resolvedTargetCodexHome = [System.IO.Path]::GetFullPath($TargetCodexHome)
$tasksRootPath = Join-Path $resolvedRepoRootPath '.codex\chancellor\tasks'
$activeTaskFilePath = Join-Path $resolvedRepoRootPath '.codex\chancellor\active-task.txt'
$sourceVersionPath = Join-Path $resolvedRepoRootPath 'codex-home-export\VERSION.json'
$sourceManifestPath = Join-Path $resolvedRepoRootPath 'codex-home-export\manifest.json'
$runtimeInstallRecordPath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode\install-record.json'
$runtimeTaskStartStatePath = Join-Path $resolvedTargetCodexHome 'config\chancellor-mode\task-start-state.json'
$runtimeVersionPath = Join-Path $resolvedTargetCodexHome 'config\cx-version.json'

foreach ($requiredPath in @($resolvedDocPath, $tasksRootPath, $sourceVersionPath, $sourceManifestPath, $runtimeInstallRecordPath, $runtimeTaskStartStatePath, $runtimeVersionPath)) {
    if (-not (Test-Path $requiredPath)) {
        throw "缺少必要输入：$requiredPath"
    }
}

$sourceVersion = Read-JsonFile -Path $sourceVersionPath
$sourceManifest = Read-JsonFile -Path $sourceManifestPath
$runtimeInstallRecord = Read-JsonFile -Path $runtimeInstallRecordPath
$runtimeTaskStartState = Read-JsonFile -Path $runtimeTaskStartStatePath
$runtimeVersion = Read-JsonFile -Path $runtimeVersionPath
$trialSummary = Get-TaskStateSummary -TasksRootPath $tasksRootPath -Prefix 'v4-trial-'
$targetSummary = Get-TaskStateSummary -TasksRootPath $tasksRootPath -Prefix 'v4-target-'

$trialSummaryText = if ($trialSummary.TotalCount -gt 0) {
    if ($trialSummary.DoneCount -eq $trialSummary.TotalCount) {
        ('`{0}/{1} done`；Trial 验收结论为“通过，但带缺陷进入下一阶段准备”' -f $trialSummary.DoneCount, $trialSummary.TotalCount)
    }
    else {
        ('`{0}/{1} done`；仍有 Trial 任务未收口' -f $trialSummary.DoneCount, $trialSummary.TotalCount)
    }
}
else {
    '未发现 Trial 任务目录'
}

$targetSummaryText = if ($targetSummary.TotalCount -gt 0) {
    if ($targetSummary.DoneCount -eq $targetSummary.TotalCount) {
        ('`{0}/{1} done`；现行推进顺序仍以 `T1 → T2 → T3 → T4 → T5` 为准' -f $targetSummary.DoneCount, $targetSummary.TotalCount)
    }
    else {
        ('`{0}/{1} done`；现行推进顺序仍以 `T1 → T2 → T3 → T4 → T5` 为准' -f $targetSummary.DoneCount, $targetSummary.TotalCount)
    }
}
else {
    '未发现 Target 任务目录'
}

$runtimeSyncSummaryText = Get-RuntimeSyncSummary -InstallRecord $runtimeInstallRecord -TaskStartState $runtimeTaskStartState
$sourceVersionText = [string]$sourceVersion.cx_version
$manifestVersionText = [string]$sourceManifest.version
$installRecordVersionText = [string]$runtimeInstallRecord.cx_version
$runtimeVersionText = [string]$runtimeVersion.cx_version
$currentVersionSummaryText = if (
    ($sourceVersionText -eq $manifestVersionText) -and
    ($sourceVersionText -eq $installRecordVersionText) -and
    ($sourceVersionText -eq $runtimeVersionText)
) {
    ('源仓 / 运行态 / 安装记录统一为 `{0}`' -f $sourceVersionText)
}
else {
    ('源仓=`{0}`；运行态=`{1}`；安装记录=`{2}`' -f $sourceVersionText, $runtimeVersionText, $installRecordVersionText)
}
$versionCredibilitySummaryText = Get-VersionCredibilitySummary `
    -SourceVersion $sourceVersionText `
    -ManifestVersion $manifestVersionText `
    -InstallRecordVersion $installRecordVersionText `
    -RuntimeVersion $runtimeVersionText
$activeTaskSummaryText = Get-ActiveTaskSummary -RepoRootPath $resolvedRepoRootPath -ActiveTaskFilePath $activeTaskFilePath -TasksRootPath $tasksRootPath

$syncState = [pscustomobject]@{
    synced_at = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    doc_path = $resolvedDocPath
    trial_summary = $trialSummaryText
    target_summary = $targetSummaryText
    runtime_sync_summary = $runtimeSyncSummaryText
    current_version_summary = $currentVersionSummaryText
    version_credibility_summary = $versionCredibilitySummaryText
    active_task_summary = $activeTaskSummaryText
}

if ($AsJson) {
    $syncState | ConvertTo-Json -Depth 4
    return
}

$tableContent = Get-Content -Raw -Encoding UTF8 -Path $resolvedDocPath
$tableContent = Set-ExactLineValue -Content $tableContent -Pattern '(?m)^最后更新：.+$' -Replacement ('最后更新：{0}' -f (Get-Date -Format 'yyyy-MM-dd'))
$tableContent = Set-ExactLineValue -Content $tableContent -Pattern '(?m)^\| Trial 完成度 \| .+$' -Replacement ('| Trial 完成度 | {0} | `.codex/chancellor/tasks/*/state.yaml`、`docs/40-执行/07-V4-Trial-验收报告.md` |' -f $trialSummaryText)
$tableContent = Set-ExactLineValue -Content $tableContent -Pattern '(?m)^\| Target 完成度 \| .+$' -Replacement ('| Target 完成度 | {0} | `.codex/chancellor/tasks/*/state.yaml`、`docs/40-执行/12-V4-Target-实施计划.md` |' -f $targetSummaryText)
$tableContent = Set-ExactLineValue -Content $tableContent -Pattern '(?m)^\| 本机运行态同步情况 \| .+$' -Replacement ('| 本机运行态同步情况 | {0} | `C:\Users\tianduan999\.codex\config\chancellor-mode\install-record.json`、`C:\Users\tianduan999\.codex\config\chancellor-mode\task-start-state.json` |' -f $runtimeSyncSummaryText)
$tableContent = Set-ExactLineValue -Content $tableContent -Pattern '(?m)^\| 当前版本 \| .+$' -Replacement ('| 当前版本 | {0} | `codex-home-export/VERSION.json`、`codex-home-export/manifest.json`、`C:\Users\tianduan999\.codex\config\cx-version.json`、`C:\Users\tianduan999\.codex\config\chancellor-mode\install-record.json` |' -f $currentVersionSummaryText)
$tableContent = Set-ExactLineValue -Content $tableContent -Pattern '(?m)^\| 版本可信性 \| .+$' -Replacement ('| 版本可信性 | {0} | 同上 |' -f $versionCredibilitySummaryText)
$tableContent = Set-ExactLineValue -Content $tableContent -Pattern '(?m)^\| 当前任务 \| .+$' -Replacement ('| 当前任务 | {0} | `.codex/chancellor/active-task.txt` |' -f $activeTaskSummaryText)

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($resolvedDocPath, $tableContent, $utf8Bom)

Write-Output ('已追平：{0}' -f $resolvedDocPath)
Write-Output ('- Trial：{0}' -f $trialSummaryText)
Write-Output ('- Target：{0}' -f $targetSummaryText)
Write-Output ('- 运行态：{0}' -f $runtimeSyncSummaryText)
Write-Output ('- 版本：{0}' -f $currentVersionSummaryText)
Write-Output ('- 当前任务：{0}' -f $activeTaskSummaryText)
