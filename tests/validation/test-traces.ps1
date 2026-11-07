[CmdletBinding()]
param(
    [string]$ApplicationBaseUrl = 'http://127.0.0.1:8082',
    [string]$JaegerBaseUrl = 'http://127.0.0.1:16686',
    [string]$CollectorHealthUrl = 'http://127.0.0.1:13133',
    [ValidateRange(15, 300)]
    [int]$TimeoutSeconds = 90,
    [string]$EnvironmentLabel = 'windows-docker-compose',
    [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $EvidencePath) { $EvidencePath = Join-Path $ProjectRoot 'docs/evidence/pr-05/results/pr05-windows-validation.json' }
$EvidenceDirectory = Split-Path -Parent $EvidencePath
$prefix = [IO.Path]::GetFileNameWithoutExtension($EvidencePath).Replace('-validation', '')
$report = [ordered]@{
    status = 'running'
    started_at = [DateTime]::UtcNow.ToString('o')
    environment = $EnvironmentLabel
    platform = [Environment]::OSVersion.ToString()
    checks = @()
    simulation = 'Worker lookup deliberately waits 40ms or 600ms; HTTP requests, SDK spans, export and Jaeger storage are real.'
}

function Save-Json {
    param([string]$Path, [object]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [IO.File]::WriteAllText($Path, ((ConvertTo-Json -InputObject $Value -Depth 80) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Wait-Ready {
    param([string]$Url, [string]$Name)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = ''
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $null = Invoke-RestMethod -Uri $Url -TimeoutSec 3
            Write-Host ($Name + ': READY') -ForegroundColor Green
            return
        }
        catch { $lastError = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
    }
    throw ($Name + ' no quedo listo: ' + $lastError)
}

function Get-TagValue {
    param([object]$Span, [string]$Key)
    $found = @($Span.tags | Where-Object { $_.key -eq $Key })
    if ($found.Count -eq 0) { return $null }
    return $found[0].value
}

function Get-ServiceName {
    param([object]$Trace, [object]$Span)
    $process = $Trace.processes.PSObject.Properties[[string]$Span.processID]
    if ($null -eq $process) { throw 'Un span no tiene proceso asociado en Jaeger.' }
    return [string]$process.Value.serviceName
}

function Get-OneSpan {
    param([object]$Trace, [string]$Operation, [string]$Service)
    $found = @($Trace.spans | Where-Object { $_.operationName -eq $Operation -and (Get-ServiceName -Trace $Trace -Span $_) -eq $Service })
    if ($found.Count -ne 1) { throw "Se esperaba un span $Service / $Operation; aparecieron $($found.Count)." }
    return $found[0]
}

function Assert-Parent {
    param([object]$Child, [object]$Parent, [string]$TraceId)
    $references = @($Child.references | Where-Object { $_.refType -eq 'CHILD_OF' -and $_.spanID -eq $Parent.spanID -and $_.traceID -eq $TraceId })
    if ($references.Count -ne 1) { throw "No se conservo el enlace padre-hijo de $($Child.operationName)." }
}

function Wait-CompleteTrace {
    param([string]$TraceId)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = 'Aun no aparecen todos los spans.'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-RestMethod -Uri "$JaegerBaseUrl/api/traces/$TraceId" -TimeoutSec 5
            if (@($response.data).Count -eq 1) {
                $candidate = $response.data[0]
                if ($candidate.traceID -eq $TraceId -and @($candidate.spans).Count -ge 6) {
                    $null = Get-OneSpan -Trace $candidate -Operation 'GET /checkout' -Service 'service-a'
                    $null = Get-OneSpan -Trace $candidate -Operation 'GET /work' -Service 'service-b'
                    $null = Get-OneSpan -Trace $candidate -Operation 'simulated-db-query' -Service 'service-b'
                    return $candidate
                }
            }
        }
        catch { $lastError = $_.Exception.Message }
        Start-Sleep -Milliseconds 500
    }
    throw "La traza nueva $TraceId no llego completa a Jaeger: $lastError"
}

function Test-Scenario {
    param([string]$Scenario, [int]$ExpectedDelayMs)
    $testRun = 'pr5-' + [guid]::NewGuid().ToString('N')
    $result = Invoke-RestMethod -Uri "$ApplicationBaseUrl/checkout?scenario=$Scenario&test_run=$testRun" -TimeoutSec 15
    if ($result.test_run -ne $testRun -or $result.service -ne 'service-a' -or $result.worker.service -ne 'service-b') {
        throw 'La respuesta no corresponde al recorrido nuevo entre los dos servicios.'
    }
    $traceId = [string]$result.trace_id
    if ($traceId -notmatch '^[a-f0-9]{32}$' -or $traceId -eq ('0' * 32) -or $result.worker.trace_id -ne $traceId) {
        throw 'Los servicios no devolvieron el mismo trace_id valido.'
    }
    $trace = Wait-CompleteTrace -TraceId $traceId
    $rootSpan = Get-OneSpan -Trace $trace -Operation 'GET /checkout' -Service 'service-a'
    $clientSpan = Get-OneSpan -Trace $trace -Operation 'HTTP GET service-b/work' -Service 'service-a'
    $workerSpan = Get-OneSpan -Trace $trace -Operation 'GET /work' -Service 'service-b'
    $querySpan = Get-OneSpan -Trace $trace -Operation 'simulated-db-query' -Service 'service-b'
    Assert-Parent -Child $clientSpan -Parent $rootSpan -TraceId $traceId
    Assert-Parent -Child $workerSpan -Parent $clientSpan -TraceId $traceId
    Assert-Parent -Child $querySpan -Parent $workerSpan -TraceId $traceId
    foreach ($span in @($rootSpan, $workerSpan)) {
        if ((Get-TagValue -Span $span -Key 'lab.test_run') -ne $testRun) { throw 'Falta el identificador de esta solicitud en un servicio.' }
        if ((Get-TagValue -Span $span -Key 'lab.scenario') -ne $Scenario) { throw 'La traza no pertenece al escenario solicitado.' }
    }
    if ((Get-TagValue -Span $querySpan -Key 'lab.delay_ms') -ne $ExpectedDelayMs -or (Get-TagValue -Span $querySpan -Key 'lab.simulated') -ne $true) {
        throw 'La operacion no identifica su demora simulada real.'
    }
    $queryMs = [double]$querySpan.duration / 1000
    $rootMs = [double]$rootSpan.duration / 1000
    if ($queryMs -lt ($ExpectedDelayMs * 0.9) -or $rootMs -lt $queryMs) { throw 'Las duraciones de Jaeger no son coherentes con la operacion ejecutada.' }
    $parentIds = @($trace.spans | ForEach-Object { @($_.references) } | ForEach-Object { $_.spanID })
    $leaves = @($trace.spans | Where-Object { $_.spanID -notin $parentIds } | Sort-Object duration -Descending)
    if ($leaves.Count -eq 0) { throw 'No se identificaron spans hoja para analizar latencia.' }
    $largest = $leaves[0]
    $tracePath = Join-Path $EvidenceDirectory ($prefix + '-' + $Scenario + '-trace.json')
    Save-Json -Path $tracePath -Value $trace
    Write-Host "Traza nueva ${Scenario}: $traceId; servicios enlazados service-a -> service-b." -ForegroundColor Green
    return [ordered]@{
        scenario = $Scenario
        test_run = $testRun
        trace_id = $traceId
        jaeger_url = $JaegerBaseUrl + '/trace/' + $traceId
        spans = @($trace.spans).Count
        services = @('service-a', 'service-b')
        cross_service_parent_reference = $true
        root_duration_ms = [Math]::Round($rootMs, 3)
        simulated_query_duration_ms = [Math]::Round($queryMs, 3)
        configured_delay_ms = $ExpectedDelayMs
        longest_leaf = [ordered]@{
            operation = $largest.operationName
            service = Get-ServiceName -Trace $trace -Span $largest
            duration_ms = [Math]::Round(([double]$largest.duration / 1000), 3)
            root_percent = [Math]::Round(([double]$largest.duration / [double]$rootSpan.duration * 100), 2)
        }
        trace_file = [IO.Path]::GetFileName($tracePath)
    }
}

Save-Json -Path $EvidencePath -Value $report
try {
    Wait-Ready -Url $CollectorHealthUrl -Name 'OpenTelemetry Collector'
    Wait-Ready -Url "$JaegerBaseUrl/api/v3/services" -Name 'Jaeger'
    Wait-Ready -Url "$ApplicationBaseUrl/health" -Name 'service-a'
    $report.checks += 'collector-jaeger-application-ready'
    $fast = Test-Scenario -Scenario 'fast' -ExpectedDelayMs 40
    $slow = Test-Scenario -Scenario 'slow' -ExpectedDelayMs 600
    if ($fast.trace_id -eq $slow.trace_id) { throw 'Dos solicitudes nuevas no deben reutilizar el trace_id.' }
    $report.fast = $fast
    $report.slow = $slow
    $report.slow_minus_fast_root_ms = [Math]::Round(($slow.root_duration_ms - $fast.root_duration_ms), 3)
    $report.checks += 'fresh-sdk-traces-stored-in-jaeger'
    $report.checks += 'same-trace-id-and-real-parent-reference-across-http-services'
    $report.checks += 'configured-simulated-delay-and-measured-span-durations'
    $report.checks += 'longest-leaf-span-identified-without-summing-overlapping-spans'
    Write-Host ("Mayor span hoja de la solicitud lenta: " + $slow.longest_leaf.service + ' / ' + $slow.longest_leaf.operation + ', ' + $slow.longest_leaf.duration_ms + ' ms.') -ForegroundColor Green
    $analysisPath = Join-Path $EvidenceDirectory ($prefix + '-analysis.md')
    $analysis = @"
# Analisis de latencia observado

Entorno: $EnvironmentLabel. Estos valores proceden de trazas reales consultadas en Jaeger, no de una imagen simulada.

| Escenario | Demora configurada (ms) | Transaccion medida (ms) | Span de consulta medido (ms) |
|---|---|---|---|
| fast | 40 | $($fast.root_duration_ms) | $($fast.simulated_query_duration_ms) |
| slow | 600 | $($slow.root_duration_ms) | $($slow.simulated_query_duration_ms) |

La solicitud lenta tiene trace_id $($slow.trace_id) y enlaza service-a con service-b mediante una referencia padre-hijo entre el cliente HTTP y el servidor remoto.

El span hoja de mayor duracion fue $($slow.longest_leaf.service) / $($slow.longest_leaf.operation): $($slow.longest_leaf.duration_ms) ms, aproximadamente $($slow.longest_leaf.root_percent) % de la duracion de la transaccion. Los spans de cliente y servidor incluyen tiempo de sus hijos; no se suman todas sus duraciones como si fueran operaciones independientes.

La demora de 600 ms es deliberada y esta etiquetada lab.simulated=true. No corresponde a una base de datos real. La peticion HTTP, el contexto W3C, los spans SDK, el Collector y la consulta de Jaeger funcionan realmente.

Abrir la transaccion: $($slow.jaeger_url)

Los JSON $($fast.trace_file) y $($slow.trace_file) conservan las trazas observadas. Jaeger usa memoria en este laboratorio: un reinicio elimina su almacenamiento, pero los JSON guardados permanecen en el clon.
"@
    [IO.File]::WriteAllText($analysisPath, $analysis + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
    $report.analysis_file = [IO.Path]::GetFileName($analysisPath)
    $report.status = 'passed'
}
catch {
    $report.status = 'failed'
    $report.error = $_.Exception.Message
    throw
}
finally {
    $report.finished_at = [DateTime]::UtcNow.ToString('o')
    Save-Json -Path $EvidencePath -Value $report
}
Write-Host "Traza lenta para capturar en Jaeger: $($slow.jaeger_url)"
Write-Host "Evidencia y analisis guardados en $EvidenceDirectory"
Write-Host 'Pruebas de trazas distribuidas aprobadas.' -ForegroundColor Green
