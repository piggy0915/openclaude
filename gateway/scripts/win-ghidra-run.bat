@echo off
setlocal
set JAVA_HOME=G:\Env\java\jdk-25
if exist G:\Env\ghidra-proj\hermesproj rmdir /s /q G:\Env\ghidra-proj\hermesproj
if not exist G:\Env\ghidra-proj mkdir G:\Env\ghidra-proj
if exist G:\Env\ghidra.log del /q G:\Env\ghidra.log
echo === analyzeHeadless 开始 ===
call G:\Env\ghidra_12.1.3_PUBLIC\support\analyzeHeadless.bat G:\Env\ghidra-proj hermesproj ^
  -import C:\Windows\System32\hostname.exe ^
  -postScript DecompileSelected.java . 3 ^
  -scriptPath G:\Env\ghidra_scripts ^
  -log G:\Env\ghidra.log ^
  -deleteProject > G:\Env\v.out 2>&1
echo EXIT=%ERRORLEVEL%
echo === hermes 标记行 ===
findstr /c:"[hermes]" G:\Env\ghidra.log
echo === 导入结果 ===
findstr /c:"Import succeeded" /c:"Import failed" G:\Env\ghidra.log
echo BAT_DONE
