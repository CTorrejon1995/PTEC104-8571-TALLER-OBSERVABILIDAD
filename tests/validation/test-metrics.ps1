[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PrometheusBaseUrl = 'http://127.0.0.1:9090'

function Assert-TargetUp {
    param([Parameter(Mandatory)][string]$JobName)

    $lastState = 'El target aún no aparece en Prometheus.'
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri "$PrometheusBaseUrl/api/v1/targets?state=active" -TimeoutSec 10
            $targets = @($response.data.activeTargets | Where-Object { $_.labels.job -eq $JobName })
            if ($targets.Count -gt 0) {
                $down = @($targets | Where-Object { $_.health -ne 'up' })
                if ($down.Count -eq 0) {
                    Write-Host "Target '$JobName': UP" -ForegroundColor Green
                    return
                }
                $lastState = ($down | ForEach-Object { "$($_.scrapeUrl): $($_.lastError)" }) -join '; '
            }
        }
        catch {
            $lastState = $_.Exception.Message
        }

        if ($attempt -lt 12) { Start-Sleep -Seconds 5 }
    }

    throw "El job '$JobName' no alcanzó estado UP dentro de 60 segundos. Detalle: $lastState"
}

function Assert-MetricPresent {
    param([Parameter(Mandatory)][string]$MetricName)

    $encoded = [uri]::EscapeDataString("count($MetricName)")
    $response = Invoke-RestMethod -Uri "$PrometheusBaseUrl/api/v1/query?query=$encoded" -TimeoutSec 10
    $results = @($response.data.result)
    if ($response.status -ne 'success' -or $results.Count -eq 0) {
        throw "La métrica '$MetricName' no está disponible en Prometheus."
    }

    Write-Host "Métrica '$MetricName': disponible" -ForegroundColor Green
}

try {
    $null = Invoke-RestMethod -Uri "$PrometheusBaseUrl/-/ready" -TimeoutSec 5
    Write-Host 'Prometheus: READY' -ForegroundColor Green

    Assert-TargetUp -JobName 'prometheus'
    Assert-TargetUp -JobName 'node-exporter'
    Assert-TargetUp -JobName 'snmp-device'

    Assert-MetricPresent -MetricName 'node_cpu_seconds_total'
    Assert-MetricPresent -MetricName 'ifHCInOctets'
    Assert-MetricPresent -MetricName 'ifHCOutOctets'

    Write-Host 'Pruebas de integración de métricas aprobadas.' -ForegroundColor Green
}
catch {
    throw "Pruebas de integración de métricas fallidas: $($_.Exception.Message)"
}
