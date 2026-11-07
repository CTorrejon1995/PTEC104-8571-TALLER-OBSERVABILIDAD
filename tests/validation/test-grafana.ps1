[CmdletBinding()]
param(
    [string]$GrafanaBaseUrl = 'http://127.0.0.1:3000',
    [string]$WebhookBaseUrl = 'http://127.0.0.1:8081',
    [string]$GrafanaUsername,
    [string]$GrafanaPassword,
    [string]$StorageMountpoint = '/mnt/docker-desktop-disk',
    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 180,
    # Solo para el harness Linux: directorio temporal con provisioning real de Grafana.
    [string]$NativeAlertingDirectory,
    [switch]$SkipSnmp,
    [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ComposeFile = Join-Path $ProjectRoot 'docker-compose.yml'
$nativeMode = -not [string]::IsNullOrWhiteSpace($NativeAlertingDirectory)
$testRun = 'pr4-' + [guid]::NewGuid().ToString('N')
$report = [ordered]@{
    status = 'running'
    started_at = [DateTime]::UtcNow.ToString('o')
    platform = [System.Environment]::OSVersion.ToString()
    mode = 'docker-compose'
    test_run = $testRun
    normal_threshold_percent = 80
    normal_pending_period = '1m'
    temporary_threshold_percent = -1
    temporary_pending_period = '0s'
    checks = @()
    restored_normal_rule = $false
}
if ($nativeMode) { $report.mode = 'native-binaries' }
if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $EvidencePath = Join-Path $ProjectRoot 'docs/evidence/pr-04/results/pr04-windows-validation.json'
}
$temporaryDir = $null
$originalRuleBytes = $null
$changedProvisioning = $false
$oldOverride = [Environment]::GetEnvironmentVariable('GRAFANA_ALERTING_DIR', 'Process')

function Save-Report {
    $directory = Split-Path -Parent $EvidencePath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    $json = ConvertTo-Json -InputObject $report -Depth 40
    [IO.File]::WriteAllText($EvidencePath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

function Invoke-Compose {
    param([string[]]$Arguments)

    # Docker Compose escribe su progreso (Recreate, Started...) en stderr.
    # Windows PowerShell 5.1 puede convertirlo en un error terminante si
    # ErrorActionPreference es Stop. Se comprueba el codigo de salida real.
    $previousPreference = $ErrorActionPreference
    $output = @()
    $exitCode = $null
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& docker compose --project-directory $ProjectRoot -f $ComposeFile @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($null -eq $exitCode -or [int]$exitCode -ne 0) {
        $details = ($output | ForEach-Object { $_.ToString() } | Select-Object -Last 20) -join [Environment]::NewLine
        throw "Docker Compose fallo con codigo $exitCode. $details"
    }
}

function Get-Api {
    param([string]$Path)
    Invoke-RestMethod -Uri ($GrafanaBaseUrl + $Path) -Headers $script:AuthHeaders -TimeoutSec 10
}

function Wait-Grafana {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = 'Grafana aun no responde.'
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $health = Invoke-RestMethod -Uri "$GrafanaBaseUrl/api/health" -TimeoutSec 3
            if ($health.database -eq 'ok') {
                $null = Get-Api -Path '/api/user'
                return
            }
        }
        catch { $lastError = $_.Exception.Message }
        Start-Sleep -Milliseconds 750
    }
    throw "Grafana no quedo listo: $lastError"
}

function Get-PrometheusValue {
    param([string]$Query)
    $encoded = [uri]::EscapeDataString($Query)
    $data = Get-Api -Path "/api/datasources/proxy/uid/prometheus/api/v1/query?query=$encoded"
    if ($data.status -ne 'success' -or @($data.data.result).Count -eq 0) {
        throw "La consulta no devolvio series: $Query"
    }
    $values = @($data.data.result | ForEach-Object {
        $value = [double]::Parse([string]$_.value[1], [Globalization.CultureInfo]::InvariantCulture)
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) {
            throw "Valor de metrica invalido: $value"
        }
        $value
    })
    return $values
}

function Apply-Provisioning {
    if ($nativeMode) {
        $null = Invoke-RestMethod -Method Post -Uri "$GrafanaBaseUrl/api/admin/provisioning/alerting/reload" -Headers $script:AuthHeaders -TimeoutSec 30
    }
    else {
        Invoke-Compose -Arguments @('up', '-d', '--no-deps', '--force-recreate', 'grafana')
    }
    Wait-Grafana
}

function Assert-NormalRule {
    $rule = Get-Api -Path '/api/v1/provisioning/alert-rules/cpu-high'
    $condition = @($rule.data | Where-Object { $_.refId -eq 'C' })[0]
    if ([double]$condition.model.conditions[0].evaluator.params[0] -ne 80 -or $rule.for -notin @('1m', '1m0s', '60s')) {
        throw 'La regla normal debe evaluar CPU > 80 % durante 1 minuto.'
    }
    if ($null -ne $rule.labels.PSObject.Properties['test_run']) { throw 'Quedo una etiqueta temporal en la regla normal.' }
}

Save-Report
try {
    if ($nativeMode) {
        if (-not $GrafanaUsername) { $GrafanaUsername = 'admin' }
        if (-not $GrafanaPassword) { $GrafanaPassword = 'observability-lab' }
    }
    else {
        $configText = & docker compose --project-directory $ProjectRoot -f $ComposeFile config --format json
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo resolver Compose.' }
        $config = ($configText | Out-String) | ConvertFrom-Json
        if (-not $GrafanaUsername) { $GrafanaUsername = $config.services.grafana.environment.GF_SECURITY_ADMIN_USER }
        if (-not $GrafanaPassword) { $GrafanaPassword = $config.services.grafana.environment.GF_SECURITY_ADMIN_PASSWORD }
    }
    $encodedCredentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($GrafanaUsername + ':' + $GrafanaPassword))
    $script:AuthHeaders = @{ Authorization = 'Basic ' + $encodedCredentials }
    Wait-Grafana
    $health = Invoke-RestMethod -Uri "$WebhookBaseUrl/health" -TimeoutSec 5
    if ($health.status -ne 'ok') { throw 'El receptor Webhook no esta listo.' }
    foreach ($uid in @('prometheus', 'loki')) {
        $source = Get-Api -Path "/api/datasources/uid/$uid/health"
        if ($source.status -ne 'OK') { throw "La fuente $uid no esta conectada." }
        Write-Host "Grafana datasource ${uid}: OK" -ForegroundColor Green
    }
    $report.checks += 'datasources-prometheus-loki'
    $dashboard = (Get-Api -Path '/api/dashboards/uid/operativo-observabilidad').dashboard
    if (@($dashboard.panels).Count -lt 4) { throw 'No se cargaron los cuatro paneles del Dashboard Operativo.' }
    $report.checks += 'dashboard-provisioned'
    Assert-NormalRule

    $cpuExpression = [string](@($dashboard.panels | Where-Object { $_.id -eq 1 })[0].targets[0].expr)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $metricsReady = $false
    $lastError = ''
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $cpuValues = @(Get-PrometheusValue -Query $cpuExpression)
            if (@($cpuValues | Where-Object { $_ -gt 100.01 }).Count -gt 0) { throw 'CPU fuera de rango.' }
            $storageExpression = [string](@($dashboard.panels | Where-Object { $_.id -eq 2 })[0].targets[0].expr)
            $storageExpression = $storageExpression.Replace('$disco', $StorageMountpoint)
            $storageValues = @(Get-PrometheusValue -Query $storageExpression)
            if (@($storageValues | Where-Object { $_ -gt 100.01 }).Count -gt 0) { throw 'Storage fuera de rango.' }
            if (-not $SkipSnmp) {
                foreach ($target in @(@($dashboard.panels | Where-Object { $_.id -eq 3 })[0].targets)) {
                    $null = Get-PrometheusValue -Query $target.expr
                }
            }
            $metricsReady = $true
            break
        }
        catch { $lastError = $_.Exception.Message }
        Start-Sleep -Seconds 2
    }
    if (-not $metricsReady) { throw "No hay datos validos para los paneles: $lastError" }
    $report.cpu_percent = $cpuValues
    $report.storage_mountpoint = $StorageMountpoint
    $report.storage_unavailable_percent = $storageValues
    $report.snmp_queries_checked = -not [bool]$SkipSnmp
    $report.checks += 'cpu-storage-queries-through-grafana'
    if (-not $SkipSnmp) { $report.checks += 'snmp-in-out-mbps-through-grafana' }
    $query = [uri]::EscapeDataString('{job="cloud-logs"}')
    $logs = Get-Api -Path "/api/datasources/proxy/uid/loki/loki/api/v1/query_range?query=$query&limit=20"
    if ($logs.status -ne 'success' -or @($logs.data.result).Count -eq 0) { throw 'No aparecen logs de cloud-logs a traves de Grafana.' }
    $report.checks += 'loki-logs-through-grafana'
    Write-Host 'Dashboard y consultas de CPU, storage, red y logs comprobados (red omitida solo con -SkipSnmp).' -ForegroundColor Green

    if ($nativeMode) {
        $temporaryDir = $NativeAlertingDirectory
        $originalRuleBytes = [IO.File]::ReadAllBytes((Join-Path $temporaryDir 'rules.json'))
    }
    else {
        $temporaryDir = Join-Path $ProjectRoot ('tests/.runtime/' + $testRun)
        $null = New-Item -ItemType Directory -Path $temporaryDir -Force
        Copy-Item -Path (Join-Path $ProjectRoot 'dashboards/alerting/*') -Destination $temporaryDir
    }
    $ruleFile = Join-Path $temporaryDir 'rules.json'
    $testProvisioning = Get-Content -LiteralPath $ruleFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $testRule = $testProvisioning.groups[0].rules[0]
    $testRule.for = '0s'
    $testRule.labels | Add-Member -NotePropertyName test_run -NotePropertyValue $testRun -Force
    $testRule.annotations.summary = 'PR4: prueba controlada de CPU; umbral temporal -1 %, sin generar carga.'
    $threshold = @($testRule.data | Where-Object { $_.refId -eq 'C' })[0]
    $threshold.model.conditions[0].evaluator.params = @(-1)
    $json = ConvertTo-Json -InputObject $testProvisioning -Depth 40
    [IO.File]::WriteAllText($ruleFile, $json, [Text.UTF8Encoding]::new($false))
    $changedProvisioning = $true
    if (-not $nativeMode) {
        [Environment]::SetEnvironmentVariable('GRAFANA_ALERTING_DIR', $temporaryDir.Replace('\', '/'), 'Process')
    }
    Write-Host 'Prueba controlada: CPU real > -1 %, sin periodo de espera; se restaurara 80 % / 1m.'
    Apply-Provisioning
    $activeRule = Get-Api -Path '/api/v1/provisioning/alert-rules/cpu-high'
    if ($activeRule.labels.test_run -ne $testRun) { throw 'Grafana no cargo la regla temporal de esta ejecucion.' }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $matchingEvent = $null
    $report.received_event_count = 0
    $report.received_alerts = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        $received = Invoke-RestMethod -Uri "$WebhookBaseUrl/events" -TimeoutSec 5
        $report.received_event_count = @($received.events).Count
        $observed = @()
        foreach ($event in @($received.events)) {
            foreach ($alert in @($event.payload.alerts)) {
                $label = $alert.labels.PSObject.Properties['test_run']
                $ruleId = $alert.PSObject.Properties['ruleUID']
                $seenRun = $null
                $seenRule = $null
                if ($null -ne $label) { $seenRun = $label.Value }
                if ($null -ne $ruleId) { $seenRule = $ruleId.Value }
                $observed += [ordered]@{
                    event_id = $event.id
                    status = $alert.status
                    rule_uid = $seenRule
                    alert_name = $alert.labels.alertname
                    test_run = $seenRun
                }
                # A display name may contain localized Unicode. Match the stable UID.
                if ($seenRun -eq $testRun -and $alert.status -eq 'firing' -and $seenRule -eq 'cpu-high' -and $alert.labels.alertname -notin @('DatasourceError', 'DatasourceNoData')) {
                    if ($null -eq $alert.PSObject.Properties['values'] -or $null -eq $alert.values.PSObject.Properties['B']) {
                        throw 'El aviso no contiene el valor real de CPU de la expresion B.'
                    }
                    $cpuValue = [double]$alert.values.B
                    if ([double]::IsNaN($cpuValue) -or [double]::IsInfinity($cpuValue) -or $cpuValue -lt 0 -or $cpuValue -gt 100.01) {
                        throw 'El aviso recibido no contiene un porcentaje de CPU valido.'
                    }
                    $matchingEvent = $event
                    break
                }
            }
            if ($null -ne $matchingEvent) { break }
        }
        $report.received_alerts = @($observed | Select-Object -First 10)
        if ($null -ne $matchingEvent) { break }
        Start-Sleep -Seconds 2
    }
    if ($null -eq $matchingEvent) {
        try { $report.rule_evaluation = Get-Api -Path '/api/prometheus/grafana/api/v1/rules' }
        catch { $report.rule_evaluation_error = $_.Exception.Message }
        throw "No se encontro el aviso firing de cpu-high para $testRun. El receptor tiene $($report.received_event_count) eventos; ver received_alerts en el informe."
    }
    $report.webhook_event = $matchingEvent
    $report.checks += 'real-cpu-alert-firing-webhook-received'
    Write-Host "Webhook real recibido para $testRun. Evento $($matchingEvent.id)." -ForegroundColor Green
    $report.status = 'passed'
}
catch {
    $report.status = 'failed'
    $report.error = $_.Exception.Message
    throw
}
finally {
    try {
        if ($changedProvisioning) {
            if ($nativeMode) {
                [IO.File]::WriteAllBytes((Join-Path $temporaryDir 'rules.json'), $originalRuleBytes)
            }
            else {
                [Environment]::SetEnvironmentVariable('GRAFANA_ALERTING_DIR', $oldOverride, 'Process')
            }
            Apply-Provisioning
            Assert-NormalRule
            $report.restored_normal_rule = $true
            if (-not $nativeMode) { Remove-Item -LiteralPath $temporaryDir -Recurse -Force }
            Write-Host 'Regla normal restaurada: CPU > 80 % durante 1 minuto.' -ForegroundColor Green
        }
    }
    catch {
        $report.status = 'failed'
        $report.restore_error = $_.Exception.Message
        throw
    }
    finally {
        [Environment]::SetEnvironmentVariable('GRAFANA_ALERTING_DIR', $oldOverride, 'Process')
        $report.finished_at = [DateTime]::UtcNow.ToString('o')
        Save-Report
    }
}
Write-Host "Evidencia guardada: $EvidencePath"
Write-Host 'Pruebas de Grafana, dashboard y alerta Webhook aprobadas.' -ForegroundColor Green
