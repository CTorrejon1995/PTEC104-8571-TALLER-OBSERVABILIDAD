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
            throw "No fue posible obtener los servicios definidos en Compose."
        }
        return @($result | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    finally {
        Pop-Location
    }
}

function Assert-DockerCompose {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'No se encontró Docker CLI. Instala Docker Desktop y habilita Docker Compose v2.'
    }

    & docker compose version
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Compose v2 no está disponible.'
    }
}

try {
    Assert-DockerCompose

    switch ($Command) {
        'validate' {
            Write-Host 'Validando sintaxis y modelo de Docker Compose...'
            Invoke-DockerCompose -Arguments @('config', '--quiet')
            Write-Host 'Validación de Docker Compose correcta.'
        }

        'up' {
            Invoke-DockerCompose -Arguments @('config', '--quiet')
            $services = Get-ComposeServices
            if ($services.Count -eq 0) {
                Write-Host 'La fundación del PR #1 no define contenedores todavía.'
                Write-Host 'Las redes y los volúmenes se utilizarán al incorporar servicios en los siguientes PR.'
                break
            }

            $composeArgs = @('up', '-d')
            if ($Build) { $composeArgs += '--build' }
            Invoke-DockerCompose -Arguments $composeArgs
        }

        'down' {
            # No elimina volúmenes: preserva la persistencia del entorno.
            Invoke-DockerCompose -Arguments @('down', '--remove-orphans')
        }

        'restart' {
            $services = Get-ComposeServices
            if ($services.Count -eq 0) {
                Write-Host 'No hay servicios definidos para reiniciar.'
                break
            }
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
            if ($Integration) {
                throw 'Las pruebas de integración se incorporarán cuando existan servicios. En PR #1 solo corresponde la validación estática.'
            }
            Invoke-DockerCompose -Arguments @('config', '--quiet')
            Write-Host 'Prueba estática de PR #1 aprobada: Docker Compose es válido.'
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
