param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("all","0","1","2","3","4","5","6","7","8","9","10")]
  [string]$Phase,

  [string]$EnvFile = "./.env",
  [string]$StateFile = "./workspace/.migration-state.json",
  [string]$WorkspaceRoot = ".",
  [switch]$Resume
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $scriptDir "run-phase.sh"

if (-not (Test-Path $runner)) {
  throw "Runner not found: $runner"
}

$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bashCmd) {
  throw "bash not found on PATH. Install Git Bash and ensure 'bash' is available."
}

$args = @(
  $runner,
  "--phase", $Phase,
  "--env-file", $EnvFile,
  "--state-file", $StateFile,
  "--workspace-root", $WorkspaceRoot
)

if ($Resume.IsPresent) {
  $args += "--resume"
}

& bash @args
$exitCode = $LASTEXITCODE
exit $exitCode
