$ErrorActionPreference = 'Stop'

$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetScriptPath = Join-Path $scriptRootPath 'sync-current-state-table.ps1'

if (-not (Test-Path $targetScriptPath)) {
    throw "缺少待测脚本：$targetScriptPath"
}

function Assert-ContentContains {
    param(
        [string]$Content,
        [string]$ExpectedText,
        [string]$Message
    )

    if (-not $Content.Contains($ExpectedText)) {
        throw "$Message`n期望包含：$ExpectedText`n实际内容：`n$Content"
    }
}

$testRootPath = Join-Path $env:TEMP ('cx-sync-state-table-' + [guid]::NewGuid().ToString('N'))
$repoRootPath = Join-Path $testRootPath 'repo'
$targetHomePath = Join-Path $testRootPath 'home'
$docPath = Join-Path $repoRootPath 'docs\40-执行\35-V4-当前真实状态总表.md'

try {
    foreach ($path in @(
        (Join-Path $repoRootPath '.codex\chancellor\tasks\v4-trial-001-demo'),
        (Join-Path $repoRootPath '.codex\chancellor\tasks\v4-trial-002-demo'),
        (Join-Path $repoRootPath '.codex\chancellor\tasks\v4-target-001-demo'),
        (Join-Path $repoRootPath 'codex-home-export'),
        (Join-Path $repoRootPath 'docs\40-执行'),
        (Join-Path $targetHomePath 'config\chancellor-mode'),
        (Join-Path $targetHomePath 'config')
    )) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    Set-Content -Path (Join-Path $repoRootPath '.codex\chancellor\active-task.txt') -Value '' -Encoding UTF8
    Set-Content -Path (Join-Path $repoRootPath '.codex\chancellor\tasks\v4-trial-001-demo\state.yaml') -Value "status: done`n" -Encoding UTF8
    Set-Content -Path (Join-Path $repoRootPath '.codex\chancellor\tasks\v4-trial-002-demo\state.yaml') -Value "status: ready`n" -Encoding UTF8
    Set-Content -Path (Join-Path $repoRootPath '.codex\chancellor\tasks\v4-target-001-demo\state.yaml') -Value "status: done`n" -Encoding UTF8

    Set-Content -Path (Join-Path $repoRootPath 'codex-home-export\VERSION.json') -Value @'
{
  "cx_version": "CX-TEST-001"
}
'@ -Encoding UTF8
    Set-Content -Path (Join-Path $repoRootPath 'codex-home-export\manifest.json') -Value @'
{
  "version": "CX-TEST-001"
}
'@ -Encoding UTF8
    Set-Content -Path (Join-Path $targetHomePath 'config\chancellor-mode\install-record.json') -Value @'
{
  "cx_version": "CX-TEST-001",
  "synced_files": [
    "a",
    "b",
    "c"
  ]
}
'@ -Encoding UTF8
    Set-Content -Path (Join-Path $targetHomePath 'config\chancellor-mode\task-start-state.json') -Value @'
{
  "verified_at": "2026-04-05 20:00:00",
  "verify_status": "passed",
  "light_check_hashes": [
    {
      "source_sha256": "1",
      "runtime_sha256": "1"
    },
    {
      "source_sha256": "2",
      "runtime_sha256": "3"
    }
  ]
}
'@ -Encoding UTF8
    Set-Content -Path (Join-Path $targetHomePath 'config\cx-version.json') -Value @'
{
  "cx_version": "CX-TEST-001"
}
'@ -Encoding UTF8

    Set-Content -Path $docPath -Value @'
# V4 当前真实状态总表

最后更新：2026-01-01
状态：现行标准件

## 当前真实状态总表

| 维度 | 当前真实状态 | 证据 |
| --- | --- | --- |
| Trial 完成度 | old | x |
| Target 完成度 | old | x |
| 本机运行态同步情况 | old | x |
| 当前版本 | old | x |
| 版本可信性 | old | x |
| 当前任务 | old | x |
'@ -Encoding UTF8

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $targetScriptPath -RepoRootPath $repoRootPath -TargetCodexHome $targetHomePath | Out-Null

    $updatedDocContent = Get-Content -Raw -Encoding UTF8 -Path $docPath
    Assert-ContentContains -Content $updatedDocContent -ExpectedText '| Trial 完成度 | `1/2 done`；仍有 Trial 任务未收口 | `.codex/chancellor/tasks/*/state.yaml`、`docs/40-执行/07-V4-Trial-验收报告.md` |' -Message 'Trial 汇总未正确回写'
    Assert-ContentContains -Content $updatedDocContent -ExpectedText '| Target 完成度 | `1/1 done`；现行推进顺序仍以 `T1 → T2 → T3 → T4 → T5` 为准 | `.codex/chancellor/tasks/*/state.yaml`、`docs/40-执行/12-V4-Target-实施计划.md` |' -Message 'Target 汇总未正确回写'
    Assert-ContentContains -Content $updatedDocContent -ExpectedText '| 本机运行态同步情况 | 已同步 `3` 个受管文件；`verify_status=passed`；上次检查时间为 `2026-04-05 20:00:00`；轻检 `1/2` 哈希一致 | `C:\Users\tianduan999\.codex\config\chancellor-mode\install-record.json`、`C:\Users\tianduan999\.codex\config\chancellor-mode\task-start-state.json` |' -Message '运行态汇总未正确回写'
    Assert-ContentContains -Content $updatedDocContent -ExpectedText '| 当前版本 | 源仓 / 运行态 / 安装记录统一为 `CX-TEST-001` | `codex-home-export/VERSION.json`、`codex-home-export/manifest.json`、`C:\Users\tianduan999\.codex\config\cx-version.json`、`C:\Users\tianduan999\.codex\config\chancellor-mode\install-record.json` |' -Message '版本汇总未正确回写'
    Assert-ContentContains -Content $updatedDocContent -ExpectedText '| 版本可信性 | `manifest.version = VERSION.json.cx_version = install-record.cx_version = runtime_version = CX-TEST-001` | 同上 |' -Message '版本可信性未正确回写'
    Assert-ContentContains -Content $updatedDocContent -ExpectedText '| 当前任务 | 无激活任务；`active-task.txt` 为空 | `.codex/chancellor/active-task.txt` |' -Message '当前任务未正确回写'

    Write-Host 'PASS: sync-current-state-table.test.ps1' -ForegroundColor Green
}
finally {
    if (Test-Path $testRootPath) {
        Remove-Item -LiteralPath $testRootPath -Recurse -Force
    }
}
