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
$RuntimeDirectory = Join-Path $ProjectRoot 'tests/.runtime'
$ValidationCacheFile = Join-Path $RuntimeDirectory 'dev-validation-cache.json'
$BuildCacheFile = Join-Path $RuntimeDirectory 'dev-build-cache.json'
$script:VerboseOutput = ($VerbosePreference -eq 'Continue')

function Assert-DockerCompose {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'No se encontro Docker CLI. Instala Docker Desktop y habilita Docker Compose.'
    }
    $version = & docker compose version --short 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Docker Compose no esta disponible: ' + ($version -join ' ')) }
    Write-Verbose ('Docker Compose ' + ($version -join ' '))
}

function Get-InputFingerprint {
    param([ValidateSet('validation', 'build')][string]$Kind)
    $files = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $dirs = if ($Kind -eq 'build') {
        @('app', 'simulators/snmp-agent', 'simulators/cloud-logs', 'tools/webhook-receiver')
    } else {
        @('app', 'configs', 'dashboards', 'simulators', 'tools', 'tests/validation')
    }
    foreach ($dir in $dirs) {
        $path = Join-Path $ProjectRoot $dir
        if (Test-Path -LiteralPath $path) {
            foreach ($file in (Get-ChildItem -LiteralPath $path -File -Recurse | Where-Object {
                $_.FullName -notmatch '[\\/](\.runtime|__pycache__|\.git)[\\/]'
            })) { $files.Add($file) }
        }
    }
    if ($Kind -eq 'validation') {
        foreach ($relative in @('docker-compose.yml', '.env')) {
            $path = Join-Path $ProjectRoot $relative
            if (Test-Path -LiteralPath $path) { $files.Add((Get-Item -LiteralPath $path)) }
        }
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $items = New-Object 'System.Collections.Generic.List[string]'
        foreach ($file in ($files | Sort-Object FullName -Unique)) {
            $relative = $file.FullName.Substring($ProjectRoot.Length).Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $items.Add($relative + '=' + $hash)
        }
        if ($Kind -eq 'validation') {
            foreach ($name in @('COMPOSE_PROJECT_NAME', 'GRAFANA_ALERTING_DIR', 'GRAFANA_ADMIN_USER', 'GRAFANA_ADMIN_PASSWORD')) {
                $items.Add($name + '=' + [string][Environment]::GetEnvironmentVariable($name, 'Process'))
            }
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes(($items -join "`n"))
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Read-CacheFingerprint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try { return [string]((Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json).fingerprint) }
    catch { return '' }
}

function Write-CacheFingerprint {
    param([string]$Path, [string]$Fingerprint)
    if (-not (Test-Path -LiteralPath $RuntimeDirectory)) {
        $null = New-Item -ItemType Directory -Path $RuntimeDirectory -Force
    }
    $json = @{ fingerprint = $Fingerprint; updated_utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function New-OutputFile {
    # Use the host temporary directory, not a OneDrive-synced project folder.
    return Join-Path ([IO.Path]::GetTempPath()) ('obs-dev-' + [guid]::NewGuid().ToString('N') + '.log')
}

function Save-FailureLog {
    param([string]$SourceFile)
    if (-not (Test-Path -LiteralPath $RuntimeDirectory)) {
        $null = New-Item -ItemType Directory -Path $RuntimeDirectory -Force
    }
    $target = Join-Path $RuntimeDirectory ([IO.Path]::GetFileName($SourceFile))
    Copy-Item -LiteralPath $SourceFile -Destination $target -Force
    return $target
}

function Show-CommandFailure {
    param([string]$Activity, [string]$LogFile, [int]$ExitCode)
    Write-Host "[ERROR] $Activity (codigo $ExitCode)" -ForegroundColor Red
    if (Test-Path -LiteralPath $LogFile) {
        Get-Content -LiteralPath $LogFile -Tail 35 | ForEach-Object { Write-Host $_ }
        $savedLog = Save-FailureLog -SourceFile $LogFile
        Write-Host "Registro completo: $savedLog" -ForegroundColor Yellow
    }
}

function ConvertTo-ProcessArgument {
    param([string]$Value)
    # Windows CommandLineToArgvW quoting; handles spaces and embedded quotes.
    if ($Value -notmatch '[\s"]' -and $Value.Length -gt 0) { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-CommandQuiet {
    param(
        [Parameter(Mandatory)][string]$Activity,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$ShowOutput
    )
    $log = New-OutputFile
    $stderr = $log + '.err'
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $process = $null
    $succeeded = $false
    try {
        $quoted = @($Arguments | ForEach-Object { ConvertTo-ProcessArgument -Value ([string]$_) }) -join ' '
        Write-Verbose ('docker ' + $quoted)
        $process = Start-Process -FilePath (Get-Command docker).Source -ArgumentList $quoted `
            -WorkingDirectory $ProjectRoot -NoNewWindow -PassThru `
            -RedirectStandardOutput $log -RedirectStandardError $stderr
        # Windows PowerShell 5.1 can return a null ExitCode if the process
        # handle has not been acquired before the process exits.
        $null = $process.Handle
        while (-not $process.WaitForExit(650)) {
            Write-Progress -Id 1 -Activity $Activity -Status ('En ejecucion ({0:n0} s)' -f $stopwatch.Elapsed.TotalSeconds)
        }
        $process.WaitForExit()
        $process.Refresh()
        $exitCode = $process.ExitCode
        Write-Progress -Id 1 -Activity $Activity -Completed
        # Combine streams only after completion: no repeated Docker pull frames in terminal.
        if (Test-Path -LiteralPath $stderr) {
            Get-Content -LiteralPath $stderr | Add-Content -LiteralPath $log -Encoding UTF8
        }
        if ($null -eq $exitCode) {
            throw "No fue posible leer el codigo de salida de Docker para: $Activity"
        }
        if ([int]$exitCode -ne 0) {
            Show-CommandFailure -Activity $Activity -LogFile $log -ExitCode ([int]$exitCode)
            throw "$Activity fallo."
        }
        if ($ShowOutput -or $script:VerboseOutput) {
            if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ } }
        }
        $succeeded = $true
        Write-Host ('[OK] ' + $Activity + ' (' + [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1) + ' s)') -ForegroundColor Green
    }
    finally {
        Write-Progress -Id 1 -Activity $Activity -Completed
        if ($null -ne $process) { $process.Dispose() }
        if (Test-Path -LiteralPath $stderr) { Remove-Item -LiteralPath $stderr -Force -ErrorAction SilentlyContinue }
        # Successful commands have no need for permanent stdout logs.
        if (Test-Path -LiteralPath $log) {
            Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-DockerCompose {
    param([string[]]$Arguments, [string]$Activity = 'Docker Compose', [switch]$ShowOutput)
    $allArgs = @('compose', '--progress', 'quiet', '--project-directory', $ProjectRoot, '-f', $ComposeFile) + $Arguments
    Invoke-CommandQuiet -Activity $Activity -Arguments $allArgs -ShowOutput:$ShowOutput
}

function Invoke-DockerComposeInteractive {
    param([string[]]$Arguments)
    Push-Location $ProjectRoot
    try {
        & docker compose --project-directory $ProjectRoot -f $ComposeFile @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Docker Compose finalizo con codigo $LASTEXITCODE." }
    }
    finally { Pop-Location }
}

function Get-ComposeServices {
    Push-Location $ProjectRoot
    try {
        $result = & docker compose --project-directory $ProjectRoot -f $ComposeFile config --services 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'No fue posible obtener los servicios definidos en Compose.' }
        return @($result | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    finally { Pop-Location }
}

function Test-ProjectConfiguration {
    param([switch]$ForceRevalidate)
    Invoke-DockerCompose -Arguments @('config', '--quiet') -Activity 'Validar modelo Docker Compose'
    $fingerprint = Get-InputFingerprint -Kind 'validation'
    if (-not $ForceRevalidate -and (Read-CacheFingerprint -Path $ValidationCacheFile) -eq $fingerprint) {
        Write-Host '[OK] Validacion de configuraciones reutilizada (archivos sin cambios).' -ForegroundColor Green
        return
    }
    # Validate the same source that will run, not an outdated local image.
    # Build once before validations, so the following up -Build can reuse the result.
    $buildFingerprint = Get-InputFingerprint -Kind 'build'
    if ((Read-CacheFingerprint -Path $BuildCacheFile) -ne $buildFingerprint -or -not (Test-BuildImagesPresent)) {
        Invoke-DockerCompose -Arguments @('build','--quiet') -Activity 'Preparar imagenes de validacion'
        Write-CacheFingerprint -Path $BuildCacheFile -Fingerprint $buildFingerprint
    }
    $checks = @(
        @{ Name = 'Prometheus (promtool)'; Args = @('run','--rm','--no-deps','--quiet-pull','--entrypoint','/bin/promtool','prometheus','check','config','/etc/prometheus/prometheus.yml') },
        @{ Name = 'Loki'; Args = @('run','--rm','--no-deps','--quiet-pull','loki','-config.file=/etc/loki/loki.yml','-verify-config=true') },
        @{ Name = 'Promtail'; Args = @('run','--rm','--no-deps','--quiet-pull','promtail','-config.file=/etc/promtail/promtail.yml','-check-syntax') },
        @{ Name = 'Grafana (JSON y referencias)'; Args = @('run','--rm','--no-deps','--quiet-pull','--quiet-build','--entrypoint','python','webhook-receiver','/app/validate_grafana.py','/project-dashboards') },
        @{ Name = 'OpenTelemetry Collector'; Args = @('run','--rm','--no-deps','--quiet-pull','otel-collector','validate','--config','/etc/otelcol/otel-collector.yml') },
        @{ Name = 'Jaeger'; Args = @('run','--rm','--no-deps','--quiet-pull','jaeger','validate','--config','/etc/jaeger/jaeger.yml') },
        @{ Name = 'Microservicios (sintaxis Python)'; Args = @('run','--rm','--no-deps','--quiet-pull','--quiet-build','--entrypoint','python','service-a','-c',"import ast, pathlib; [ast.parse(p.read_text(encoding='utf-8')) for p in pathlib.Path('/app').rglob('*.py')]; print('Microservices syntax: OK')") }
    )
    $services = @(Get-ComposeServices)
    foreach ($check in $checks) {
        $name = $check.Name
        if (($name -eq 'Loki' -and $services -notcontains 'loki') -or
            ($name -eq 'Promtail' -and $services -notcontains 'promtail') -or
            ($name -like 'Grafana*' -and $services -notcontains 'grafana') -or
            ($name -in @('OpenTelemetry Collector', 'Jaeger', 'Microservicios (sintaxis Python)') -and $services -notcontains 'otel-collector')) {
            continue
        }
        Invoke-DockerCompose -Arguments $check.Args -Activity ('Validar ' + $name)
    }
    Write-CacheFingerprint -Path $ValidationCacheFile -Fingerprint $fingerprint
    Write-Host '[OK] Validacion estatica completa.' -ForegroundColor Green
}

function Test-BuildImagesPresent {
    $required = @('observability-demo-app:1.0.0', 'observability-snmp-agent:1.0.0',
        'observability-cloud-logs:1.0.0', 'observability-webhook-receiver:1.0.0')
    $images = & docker image ls --format '{{.Repository}}:{{.Tag}}' 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($name in $required) { if ($images -notcontains $name) { return $false } }
    return $true
}

function Start-Environment {
    Invoke-DockerCompose -Arguments @('config','--quiet') -Activity 'Validar modelo Docker Compose'
    $composeArgs = @('up','-d','--pull','missing','--quiet-pull','--quiet-build')
    if ($Build) {
        $fingerprint = Get-InputFingerprint -Kind 'build'
        $same = ((Read-CacheFingerprint -Path $BuildCacheFile) -eq $fingerprint)
        if ($Force -or -not $same -or -not (Test-BuildImagesPresent)) {
            Write-Host 'Compilacion necesaria: fuentes modificadas, imagen ausente o -Force.'
            Invoke-DockerCompose -Arguments @('build','--quiet') -Activity 'Construir imagenes locales'
            $composeArgs += '--no-build'
        } else {
            Write-Host 'Imagenes locales reutilizadas: el contexto de build no cambio.'
            $composeArgs += '--no-build'
        }
    }
    Invoke-DockerCompose -Arguments $composeArgs -Activity 'Levantar stack de observabilidad'
    if ($Build) { Write-CacheFingerprint -Path $BuildCacheFile -Fingerprint $fingerprint }
}

function Invoke-IntegrationTests {
    $services = @(Get-ComposeServices)
    $scripts = @('tests/validation/test-metrics.ps1')
    if ($services -contains 'loki') { $scripts += 'tests/validation/test-logs.ps1' }
    if ($services -contains 'grafana') { $scripts += 'tests/validation/test-grafana.ps1' }
    if ($services -contains 'otel-collector') { $scripts += 'tests/validation/test-traces.ps1' }
    for ($i = 0; $i -lt $scripts.Count; $i++) {
        $relative = $scripts[$i]
        $scriptPath = Join-Path $ProjectRoot $relative
        if (-not (Test-Path -LiteralPath $scriptPath)) { throw "No se encontro el script: $scriptPath" }
        $activity = 'Integracion ' + $relative
        $percent = [int](100 * $i / $scripts.Count)
        Write-Progress -Id 2 -Activity 'Pruebas de integracion' -Status $activity -PercentComplete $percent
        $log = New-OutputFile
        $timer = [Diagnostics.Stopwatch]::StartNew()
        try {
            # Keep original test logic and error propagation. Redirect noisy output only.
            & $scriptPath *> $log
            if (-not $?) { throw "La prueba $relative devolvio error." }
            if ($script:VerboseOutput) { Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ } }
            Write-Host ('[OK] ' + $relative + ' (' + [Math]::Round($timer.Elapsed.TotalSeconds, 1) + ' s)') -ForegroundColor Green
            Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "[ERROR] $relative" -ForegroundColor Red
            if (Test-Path -LiteralPath $log) {
                Get-Content -LiteralPath $log -Tail 35 | ForEach-Object { Write-Host $_ }
                $savedLog = Save-FailureLog -SourceFile $log
                Write-Host "Registro completo: $savedLog" -ForegroundColor Yellow
                Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
            }
            throw ('Fallo en ' + $relative + ': ' + $_.Exception.Message)
        }
    }
    Write-Progress -Id 2 -Activity 'Pruebas de integracion' -Completed
    Write-Host '[OK] Pruebas de integracion del stack aprobadas.' -ForegroundColor Green
}

try {
    Assert-DockerCompose
    switch ($Command) {
        'validate' { Test-ProjectConfiguration -ForceRevalidate:$Force }
        'up' { Start-Environment }
        'down' { Invoke-DockerCompose -Arguments @('down','--remove-orphans') -Activity 'Detener stack (volumenes conservados)' }
        'restart' { Invoke-DockerCompose -Arguments @('restart') -Activity 'Reiniciar stack' }
        'status' { Invoke-DockerComposeInteractive -Arguments @('ps','-a') }
        'logs' {
            if ($Service) { Invoke-DockerComposeInteractive -Arguments @('logs','--follow','--tail','100',$Service) }
            else { Invoke-DockerComposeInteractive -Arguments @('logs','--follow','--tail','100') }
        }
        'test' {
            Test-ProjectConfiguration -ForceRevalidate:$Force
            if ($Integration) { Invoke-IntegrationTests }
            else { Write-Host '[OK] Pruebas estaticas aprobadas. Usa test -Integration para probar servicios desplegados.' -ForegroundColor Green }
        }
        'clean' {
            $confirmed = [bool]$Force
            if (-not $confirmed) {
                $answer = Read-Host 'Esta operacion elimina contenedores, redes y VOLUMENES. Escriba CLEAN para continuar'
                $confirmed = ($answer -ceq 'CLEAN')
            }
            if ($confirmed) {
                Invoke-DockerCompose -Arguments @('down','--volumes','--remove-orphans') -Activity 'Eliminar entorno y volumenes'
                foreach ($path in @($ValidationCacheFile, $BuildCacheFile)) {
                    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
                }
            } else { Write-Host 'Operacion cancelada. No se modifico el entorno.' }
        }
    }
}
catch {
    Write-Progress -Id 1 -Activity 'Docker Compose' -Completed
    Write-Progress -Id 2 -Activity 'Pruebas de integracion' -Completed
    Write-Error $_
    exit 1
}
