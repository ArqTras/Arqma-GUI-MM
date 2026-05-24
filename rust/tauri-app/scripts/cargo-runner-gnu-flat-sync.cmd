@echo off
setlocal
node "%~dp0cargo-runner-gnu-flat-sync.mjs" %*
exit /b %ERRORLEVEL%
