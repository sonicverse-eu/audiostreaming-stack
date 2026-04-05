param(
    [switch]$Ci,
    [switch]$PythonUser,
    [switch]$SkipNode,
    [switch]$SkipPython
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-PythonCommand {
    if ($env:PYTHON) {
        $cmd = Get-Command $env:PYTHON -ErrorAction SilentlyContinue
        if ($cmd) {
            return $env:PYTHON
        }
    }

    $candidates = @("py", "python", "python3")
    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) {
            if ($candidate -eq "py") {
                return "py -3"
            }
            return $candidate
        }
    }

    throw "[python] Python not found. Install Python 3.12+ and retry."
}

function Install-NodeDeps {
    $statusDashboard = Join-Path $RootDir "status-dashboard"
    $manager = "npm"

    if (Test-Path (Join-Path $statusDashboard "pnpm-lock.yaml")) {
        $manager = "pnpm"
    } elseif (Test-Path (Join-Path $statusDashboard "yarn.lock")) {
        $manager = "yarn"
    }

    Write-Host "[node] Installing status-dashboard dependencies with $manager"

    Push-Location $statusDashboard
    try {
        if ($manager -eq "npm") {
            if ($Ci -and (Test-Path "package-lock.json")) {
                npm ci
            } else {
                npm install
            }
        } elseif ($manager -eq "yarn") {
            if (-not (Get-Command yarn -ErrorAction SilentlyContinue)) {
                throw "[node] yarn.lock found but yarn is not installed."
            }
            if ($Ci) {
                yarn install --frozen-lockfile
            } else {
                yarn install
            }
        } elseif ($manager -eq "pnpm") {
            if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
                throw "[node] pnpm-lock.yaml found but pnpm is not installed."
            }
            if ($Ci) {
                pnpm install --frozen-lockfile
            } else {
                pnpm install
            }
        }
    }
    finally {
        Pop-Location
    }
}

function Install-PythonDeps {
    $pythonCmd = Get-PythonCommand
    $requirements = @(
        (Join-Path $RootDir "analytics/requirements.txt"),
        (Join-Path $RootDir "status-panel/requirements.txt")
    )

    Write-Host "[python] Installing dependencies with $pythonCmd"

    foreach ($requirementsFile in $requirements) {
        if ($PythonUser) {
            Invoke-Expression "$pythonCmd -m pip install --user -r `"$requirementsFile`""
        } else {
            Invoke-Expression "$pythonCmd -m pip install -r `"$requirementsFile`""
        }
    }
}

if ($SkipNode -and $SkipPython) {
    Write-Host "Nothing to do: both Node and Python installs are skipped."
    exit 0
}

if (-not $SkipNode) {
    Install-NodeDeps
} else {
    Write-Host "[node] Skipped"
}

if (-not $SkipPython) {
    Install-PythonDeps
} else {
    Write-Host "[python] Skipped"
}

Write-Host "All dependency installs completed."
