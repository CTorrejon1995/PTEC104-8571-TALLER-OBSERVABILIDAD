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

    $services = @(Get-ComposeServices)
    if ($services -contains 'loki') {
        Write-Host 'Validando configuracion de Loki...'
        Invoke-DockerCompose -Arguments @(
            'run', '--rm', '--no-deps', 'loki',
            '-config.file=/etc/loki/loki.yml', '-verify-config=true'
        )
    }
    if ($services -contains 'promtail') {
        Write-Host 'Validando configuracion de Promtail...'
        Invoke-DockerCompose -Arguments @(
            'run', '--rm', '--no-deps', 'promtail',
            '-config.file=/etc/promtail/promtail.yml', '-check-syntax'
        )
    }
    Write-Host 'Validacion estatica del stack correcta.' -ForegroundColor Green
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
                $scripts = @('tests/validation/test-metrics.ps1')
                if (@(Get-ComposeServices) -contains 'loki') {
                    $scripts += 'tests/validation/test-logs.ps1'
                }
                foreach ($relativeScript in $scripts) {
                    $testScript = Join-Path $ProjectRoot $relativeScript
                    if (-not (Test-Path $testScript)) {
                        throw "No se encontro el script de integracion: $testScript"
                    }
                    try {
                        & $testScript
                    }
                    catch {
                        throw ('Fallo en ' + $relativeScript + ': ' + $_.Exception.Message)
                    }
                }
                Write-Host 'Pruebas de integracion del stack aprobadas.' -ForegroundColor Green
            }
            else {
                Write-Host 'Pruebas estaticas del stack aprobadas.' -ForegroundColor Green
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
