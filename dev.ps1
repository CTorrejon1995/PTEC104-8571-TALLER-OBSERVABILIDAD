[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('up', 'down', 'restart', 'status', 'logs', 'validate', 'test', 'clean')]
    [string]$Command = 'status',

    [string]$Service,

    [switch]$Build,

    [switch]$Integration,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ComposeFile = Join-Path $ProjectRoot 'docker-compose.yml'

function Invoke-DockerCompose {
    param([string[]]$Arguments)

    Push-Location $ProjectRoot
    try {
        & docker compose --project-directory $ProjectRoot -f $ComposeFile @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Docker Compose finalizó con código $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Get-ComposeServices {
    Push-Location $ProjectRoot
    try {
        $result = & docker compose --project-directory $ProjectRoot -f $ComposeFile config --services
        if ($LASTEXITCODE -ne 0) {
            throw 'No fue posible obtener los servicios definidos en Compose.'
        }
        return @($result | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    finally {
        Pop-Location
    }
}

function Assert-DockerCompose {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'No se encontró Docker CLI. Instala Docker Desktop y habilita Docker Compose.'
    }

    & docker compose version
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose no está disponible.'
    }
}

function Test-ProjectConfiguration {
    Write-Host 'Validando sintaxis y modelo de Docker Compose...'
    Invoke-DockerCompose -Arguments @('config', '--quiet')

    Write-Host 'Validando configuración de Prometheus mediante promtool...'
    Invoke-DockerCompose -Arguments @(
        'run', '--rm', '--no-deps', '--entrypoint', '/bin/promtool', 'prometheus',
        'check', 'config', '/etc/prometheus/prometheus.yml'
    )

    Write-Host 'Validación estática de PR #2 correcta.' -ForegroundColor Green
}

try {
    Assert-DockerCompose

    switch ($Command) {
        'validate' {
            Test-ProjectConfiguration
        }

        'up' {
            Invoke-DockerCompose -Arguments @('config', '--quiet')
            $composeArgs = @('up', '-d')
            if ($Build) { $composeArgs += '--build' }
            Invoke-DockerCompose -Arguments $composeArgs
        }

        'down' {
            Invoke-DockerCompose -Arguments @('down', '--remove-orphans')
        }

        'restart' {
            Invoke-DockerCompose -Arguments @('restart')
        }

        'status' {
            Invoke-DockerCompose -Arguments @('ps', '-a')
        }

        'logs' {
            if ($Service) {
                Invoke-DockerCompose -Arguments @('logs', '--follow', '--tail', '100', $Service)
            }
            else {
                Invoke-DockerCompose -Arguments @('logs', '--follow', '--tail', '100')
            }
        }

        'test' {
            Test-ProjectConfiguration
            if ($Integration) {
                $testScript = Join-Path $ProjectRoot 'tests/validation/test-metrics.ps1'
                if (-not (Test-Path $testScript)) {
                    throw "No se encontró el script de integración: $testScript"
                }
                try {
                    & $testScript
                }
                catch {
                    throw "Las pruebas de integración fallaron: $($_.Exception.Message)"
                }
            }
            else {
                Write-Host 'Pruebas estáticas de PR #2 aprobadas.' -ForegroundColor Green
                Write-Host 'Para comprobar los servicios desplegados, ejecuta: .\dev.ps1 test -Integration'
            }
        }

        'clean' {
            $confirmation = $false
            if ($Force) {
                $confirmation = $true
            }
            else {
                $answer = Read-Host 'Esta operación eliminará contenedores, redes y VOLÚMENES del proyecto. Escriba CLEAN para continuar'
                $confirmation = ($answer -ceq 'CLEAN')
            }

            if (-not $confirmation) {
                Write-Host 'Operación cancelada. No se modificó el entorno.'
                break
            }

            Invoke-DockerCompose -Arguments @('down', '--volumes', '--remove-orphans')
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
