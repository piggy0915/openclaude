$ErrorActionPreference = 'Continue'
$zip = 'G:\Env\ghidra_12.1.3_PUBLIC.zip'
$dst = 'G:\Env'
$gh  = 'G:\Env\ghidra_12.1.3_PUBLIC'
$jdk = 'G:\Env\java\jdk-25'

Write-Output ('FREE_G_GB ' + [math]::Round((Get-PSDrive G).Free / 1GB, 1))
if (-not (Test-Path $zip)) { Write-Output 'ZIP_MISSING'; exit 1 }

if (Test-Path (Join-Path $gh 'support\analyzeHeadless.bat')) {
  Write-Output 'ALREADY_EXTRACTED'
} else {
  Write-Output 'EXTRACTING with tar...'
  Push-Location $dst
  & tar -xf $zip
  Pop-Location
}
$hasHS = Test-Path (Join-Path $gh 'support\analyzeHeadless.bat')
Write-Output ('HAS_ANALYZEHEADLESS ' + $hasHS)
if (-not $hasHS) { Write-Output 'EXTRACT_FAILED'; exit 1 }

# JAVA_HOME_OVERRIDE → JDK 25
$lp = Join-Path $gh 'support\launch.properties'
$txt = Get-Content $lp -Raw
if ($txt -match '(?m)^\s*#?\s*JAVA_HOME_OVERRIDE=') {
  $txt = [regex]::Replace($txt, '(?m)^\s*#?\s*JAVA_HOME_OVERRIDE=.*$', ('JAVA_HOME_OVERRIDE=' + $jdk))
} else {
  $txt = $txt.TrimEnd() + "`r`nJAVA_HOME_OVERRIDE=$jdk`r`n"
}
Set-Content -Path $lp -Value $txt -Encoding ASCII
Write-Output ('LAUNCH_PROP ' + ((Select-String -Path $lp -Pattern '^JAVA_HOME_OVERRIDE=' | Select-Object -First 1).Line))

Write-Output ('JDK25 ' + (& "$jdk\bin\java" -version 2>&1 | Select-Object -First 1))

# Ghidra 版本自检（headless -help 等价：直接看 version 文件）
$verFile = Join-Path $gh 'Ghidra\application.properties'
if (Test-Path $verFile) {
  (Select-String -Path $verFile -Pattern '^application.version=' | Select-Object -First 1).Line | ForEach-Object { Write-Output ('GHIDRA_' + $_) }
}
Write-Output 'SETUP_DONE'
