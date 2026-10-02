@echo off
rem Windows entry point: runs harness.sh with Git Bash. From PowerShell or
rem cmd, "./harness.sh" only opens the file in its associated editor, and a
rem bare "bash" usually resolves to WSL, which has no oc login.
rem Usage: harness\harness.cmd <command> [args...]
setlocal
set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH_EXE%" (
  echo Git Bash not found at "%BASH_EXE%". Install Git for Windows or run harness.sh from a Git Bash terminal. 1>&2
  exit /b 1
)
rem Forward slashes: harness.sh finds its own directory with dirname, which
rem does not treat backslashes as separators.
set "SCRIPT=%~dp0harness.sh"
set "SCRIPT=%SCRIPT:\=/%"
"%BASH_EXE%" "%SCRIPT%" %*
exit /b %ERRORLEVEL%
