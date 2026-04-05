param(
    [switch]$Ci,
    [switch]$PythonUser,
    [switch]$SkipNode,
    [switch]$SkipPython
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $RootDir "install-all.ps1") -Ci:$Ci -PythonUser:$PythonUser -SkipNode:$SkipNode -SkipPython:$SkipPython
