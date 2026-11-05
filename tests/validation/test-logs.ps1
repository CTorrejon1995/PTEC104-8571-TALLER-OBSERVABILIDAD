[CmdletBinding()]
param(
    [string]$LokiBaseUrl = 'http://127.0.0.1:3100',
    [string]$PromtailBaseUrl = 'http://127.0.0.1:9080',
    [ValidateRange(5, 300)]
    [int]$TimeoutSeconds = 90,
    [string]$ExistingProbeId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ComposeFile = Join-Path $ProjectRoot 'docker-compose.yml'

function Wait-ReadyEndpoint {
    param([string]$Url, [string]$Name)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = 'El endpoint todavia no responde.'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $null = Invoke-RestMethod -Uri $Url -TimeoutSec 3
            Write-Host ($Name + ': READY') -ForegroundColor Green
            return
        }
        catch {
            $lastError = $_.Exception.Message
            Start-Sleep -Milliseconds 500
        }
    }
    throw ($Name + ' no alcanzo estado READY. Detalle: ' + $lastError)
}

function Get-LokiQuery {
    param([string]$Query)
    $encoded = [uri]::EscapeDataString($Query)
    $start = [DateTimeOffset]::UtcNow.AddMinutes(-15).ToUnixTimeMilliseconds().ToString() + '000000'
    $end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString() + '000000'
    $url = "$LokiBaseUrl/loki/api/v1/query_range?query=$encoded&start=$start&end=$end&limit=100"
    $response = Invoke-RestMethod -Uri $url -TimeoutSec 5
    if ($response.status -ne 'success' -or $response.data.resultType -ne 'streams') {
        throw "Loki no devolvio una consulta de logs correcta: $Query"
    }
    return $response
}

Wait-ReadyEndpoint -Url "$LokiBaseUrl/ready" -Name 'Loki'
Wait-ReadyEndpoint -Url "$PromtailBaseUrl/ready" -Name 'Promtail'

if ([string]::IsNullOrWhiteSpace($ExistingProbeId)) {
    $probeId = 'pr3-probe-' + [guid]::NewGuid().ToString('N')
    $probeArgs = @(
        'compose', '--project-directory', $ProjectRoot, '-f', $ComposeFile,
        'exec', '-T', 'cloud-logs', 'python', '/app/generate_logs.py',
        '--once', '--level', 'error', '--message', $probeId
    )
    & docker @probeArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'No se pudo escribir el log de prueba mediante el generador.'
    }
}
else {
    # Permite comprobar un probe producido por un despliegue nativo/CI real.
    $probeId = $ExistingProbeId
    if ($probeId -notmatch '^pr3-probe-[a-f0-9]{32}$') {
        throw 'ExistingProbeId debe tener formato pr3-probe- seguido de 32 digitos hexadecimales.'
    }
}

$query = '{job="cloud-logs",level="error"} |= "' + $probeId + '"'
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$found = $false
$lastError = 'El probe todavia no llego a Loki.'
while ([DateTime]::UtcNow -lt $deadline) {
    try {
        $response = Get-LokiQuery -Query $query
        foreach ($stream in @($response.data.result)) {
            if ($stream.stream.level -ne 'error') {
                throw 'La etiqueta level no contiene la severidad extraida del JSON.'
            }
            foreach ($value in @($stream.values)) {
                $event = ConvertFrom-Json -InputObject ([string]$value[1])
                foreach ($field in @('timestamp', 'level', 'service', 'message', 'simulated')) {
                    if ($null -eq $event.PSObject.Properties[$field]) {
                        throw "Falta el campo $field en el log almacenado."
                    }
                }
                if ($event.message -eq $probeId -and $event.level -eq 'error' -and $event.simulated -eq $true) {
                    $found = $true
                    break
                }
            }
            if ($found) { break }
        }
        if ($found) { break }
    }
    catch {
        $lastError = $_.Exception.Message
    }
    Start-Sleep -Milliseconds 500
}
if (-not $found) {
    throw "El log nuevo no recorrio generador -> Promtail -> Loki. Detalle: $lastError"
}
Write-Host "Probe nuevo recibido en Loki: $probeId" -ForegroundColor Green
Write-Host "Filtro LogQL comprobado: $query" -ForegroundColor Green

$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$levelsFound = $false
while ([DateTime]::UtcNow -lt $deadline) {
    try {
        $response = Get-LokiQuery -Query '{job="cloud-logs"}'
        $levels = @($response.data.result | ForEach-Object { $_.stream.level } | Select-Object -Unique)
        $missingLevels = @(@('info', 'warn', 'error') | Where-Object { $_ -notin $levels })
        if ($missingLevels.Count -eq 0) {
            $levelsFound = $true
            break
        }
    }
    catch {
        $lastError = $_.Exception.Message
    }
    Start-Sleep -Milliseconds 500
}
if (-not $levelsFound) { throw 'No aparecieron las tres etiquetas level: info, warn y error.' }
Write-Host 'Severidades JSON indexadas: info, warn, error.' -ForegroundColor Green
Write-Host 'Pruebas de integracion de logs aprobadas.' -ForegroundColor Green
