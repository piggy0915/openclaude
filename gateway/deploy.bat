@echo off
chcp 65001 >nul


set "APP_DIR=%~dp0"
set "PROJECT_ROOT=%APP_DIR%.."

rem if exist "%PROJECT_ROOT%\src" (
rem     xcopy "%PROJECT_ROOT%\src" "%APP_DIR%openclaude\src\" /E /I /Y >nul
rem )

if exist "%PROJECT_ROOT%\dist" (
    xcopy "%PROJECT_ROOT%\dist" "%APP_DIR%openclaude\dist\" /E /I /Y >nul
)

if exist "%PROJECT_ROOT%\bin" (
    xcopy "%PROJECT_ROOT%\bin" "%APP_DIR%openclaude\bin\" /E /I /Y >nul
)

if exist "%PROJECT_ROOT%\scripts" (
    xcopy "%PROJECT_ROOT%\scripts" "%APP_DIR%openclaude\scripts\" /E /I /Y >nul
)

if exist "%PROJECT_ROOT%\tsconfig.json" (
    copy "%PROJECT_ROOT%\tsconfig.json" "%APP_DIR%openclaude\tsconfig.json" /Y >nul
)

if exist "%PROJECT_ROOT%\package.json" (
    copy "%PROJECT_ROOT%\package.json" "%APP_DIR%openclaude\package.json" /Y >nul
)

if exist "%PROJECT_ROOT%\bun.lock" (
    copy "%PROJECT_ROOT%\bun.lock" "%APP_DIR%openclaude\bun.lock" /Y >nul
)

if exist "%PROJECT_ROOT%\package-lock.json" (
    copy "%PROJECT_ROOT%\package-lock.json" "%APP_DIR%openclaude\package-lock.json" /Y >nul
)

if exist "%PROJECT_ROOT%\README.md" (
    copy "%PROJECT_ROOT%\README.md" "%APP_DIR%openclaude\README.md" /Y >nul
)

rem if exist "%PROJECT_ROOT%\Dockerfile" (
rem    copy "%PROJECT_ROOT%\Dockerfile" "%APP_DIR%openclaude\Dockerfile" /Y >nul
rem )

