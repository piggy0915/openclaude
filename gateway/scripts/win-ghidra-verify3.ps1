$ErrorActionPreference = 'Continue'
$gh  = 'G:\Env\ghidra_12.1.3_PUBLIC'
$jdk = 'G:\Env\java\jdk-25'
$proj = 'G:\Env\ghidra-proj'
$target = Join-Path $env:SystemRoot 'System32\hostname.exe'
$log = 'G:\Env\ghidra-verify3.log'

New-Item -ItemType Directory -Force -Path $proj | Out-Null
$env:JAVA_HOME = $jdk
$hs = Join-Path $gh 'support\analyzeHeadless.bat'

# 用参数数组 splat，避免反引号续行在 .bat 调用上失效
$cmdArgs = @(
  $proj, 'hermesproj',
  '-import', $target,
  '-postScript', 'DecompileSelected.java', '.', '3',
  '-scriptPath', 'G:\Env',
  '-log', (Join-Path $proj 'ghidra.log'),
  '-deleteProject'
)
Write-Output ('CMD ' + $hs + ' ' + ($cmdArgs -join ' '))
& $hs @cmdArgs *> $log

$txt = @(Get-Content $log -ErrorAction SilentlyContinue)
Write-Output ('LOG_LINES ' + $txt.Count)
Write-Output '--- 关键行 ---'
$txt | Select-String -Pattern 'hermes\]|matched_functions|Import succeeded|Import failed' |
  Select-Object -First 12 | ForEach-Object { Write-Output $_.Line.Trim() }
Write-Output '--- C 伪码（前 28 行）---'
$hit = $txt | Select-String -Pattern 'hermes\] FUNC' | Select-Object -First 1
if ($hit) {
  $idx = $hit.LineNumber
  $end = [math]::Min($idx + 27, $txt.Count - 1)
  $txt[$idx..$end] | ForEach-Object { Write-Output $_ }
} else {
  Write-Output '(no FUNC line; tail 15)'
  $txt | Select-Object -Last 15 | ForEach-Object { Write-Output $_ }
}
Write-Output 'VERIFY3_DONE'
