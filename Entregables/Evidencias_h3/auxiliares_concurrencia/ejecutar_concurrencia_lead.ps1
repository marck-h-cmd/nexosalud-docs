# ====================================================================================================
# ORQUESTADOR DE PRUEBA DE CONCURRENCIA DETERMINISTA CON ESPERA OBSERVADA (H3 - LEAD)
# ====================================================================================================

$ErrorActionPreference = "Stop"
$auxDir = $PSScriptRoot
if (-not $auxDir) { $auxDir = (Get-Location).Path }
# Corrección de resolución: subir tres niveles desde auxiliares_concurrencia conduce a la raíz del repo
$repoRoot = (Resolve-Path "$auxDir\..\..\..").Path
$logFile = "$auxDir\..\salida_concurrencia_lead.txt"
$oltpDb = "Test_NexoSalud_OLTP_Lead_Conc"
$martDb = "Test_NexoSalud_Mart_Lead_Conc"

# 1. Comprobación defensiva previa de existencia de archivos requeridos
$reqFiles = @(
    "$auxDir\01_preparar_concurrencia_lead.sql",
    "$auxDir\02_conn1_lead.sql",
    "$auxDir\03_conn2_lead.sql",
    "$auxDir\04_verificar_y_limpiar_lead.sql",
    "$repoRoot\Entregables\16. ETL_Fact_NegociacionLead_h3.sql"
)
foreach ($f in $reqFiles) {
    if (-not (Test-Path $f)) {
        Write-Error "ABORTANDO: Archivo requerido no encontrado: $f"
        exit 1
    }
}

# 2. Comprobación defensiva de existencia de bases: abortar si ya existen (no eliminar automáticamente)
$chkDbs = sqlcmd -S localhost -E -h -1 -W -b -Q "SELECT COUNT(*) FROM sys.databases WHERE name IN ('$martDb', '$oltpDb');"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ABORTANDO: Error al consultar el catálogo sys.databases en el motor."
    exit 1
}
$existCount = [int]($chkDbs | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
if ($existCount -gt 0) {
    Write-Error "ABORTANDO: Una o ambas bases de concurrencia ya existen en el servidor ($martDb, $oltpDb). Limpie manualmente antes de continuar; no se eliminan bases preexistentes."
    exit 1
}

$basesIniciadas = $false
$job1 = $null
$job2 = $null
$errorEjecucion = $null
$falloLimpieza = $false
$errorLimpieza = $null

try {
    "=================================================================================" | Out-File -FilePath $logFile -Encoding utf8
    "PRUEBA DE CONCURRENCIA DETERMINISTA CON ESPERA OBSERVADA (H3 - FACT_NEGOCIACIONLEAD)" | Out-File -FilePath $logFile -Append -Encoding utf8
    "Fecha y Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $logFile -Append -Encoding utf8
    "Entorno: Motor SQL Server Local (Bases Aisladas: $oltpDb / $martDb)" | Out-File -FilePath $logFile -Append -Encoding utf8
    "=================================================================================" | Out-File -FilePath $logFile -Append -Encoding utf8
    "" | Out-File -FilePath $logFile -Append -Encoding utf8

    Write-Host "Paso 1: Preparando entorno y desplegando modelo real mediante 01_preparar_concurrencia_lead.sql..."
    Push-Location $repoRoot
    $basesIniciadas = $true
    try {
        $prepOut = sqlcmd -S localhost -E -b -i "$auxDir\01_preparar_concurrencia_lead.sql"
        if ($LASTEXITCODE -ne 0) {
            throw "Fallo en la preparación del entorno de concurrencia: $prepOut"
        }
    } finally {
        Pop-Location
    }

    Write-Host "Paso 2: Lanzando Conexión 1 (ejecuta el procedimiento y retiene el bloqueo 6 segundos)..."
    $job1 = Start-Job -ScriptBlock { 
        param($file) 
        $out = & sqlcmd -S localhost -E -b -i $file 2>&1
        $ec = $LASTEXITCODE
        return [PSCustomObject]@{
            ExitCode = $ec
            Output = ($out | Out-String)
        }
    } -ArgumentList "$auxDir\02_conn1_lead.sql"

    # Esperar 800 ms para asegurar que Conexión 1 inició la transacción y adquirió el applock
    Start-Sleep -Milliseconds 800

    Write-Host "Paso 3: Lanzando Conexión 2 (debe solicitar el bloqueo y entrar en espera observada)..."
    $job2 = Start-Job -ScriptBlock { 
        param($file) 
        $out = & sqlcmd -S localhost -E -b -i $file 2>&1
        $ec = $LASTEXITCODE
        return [PSCustomObject]@{
            ExitCode = $ec
            Output = ($out | Out-String)
        }
    } -ArgumentList "$auxDir\03_conn2_lead.sql"

    # Paso 4: Muestreo de DMV
    Write-Host "Paso 4: Muestreando sys.dm_tran_locks y sys.dm_os_waiting_tasks en vivo..."
    $esperaDetectada = $false
    $evidenciaLocks = ""

    for ($i = 0; $i -lt 30; $i++) {
        $chkWait = sqlcmd -S localhost -E -h -1 -W -b -Q "SELECT COUNT(*) FROM sys.dm_tran_locks WHERE resource_description LIKE '%ETL_Lock_Fact_NegociacionLead%' AND request_status = 'WAIT';"
        $waitCount = [int]($chkWait | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
        
        if ($waitCount -gt 0) {
            $esperaDetectada = $true
            $qryDmv = @"
SELECT 
    tl.request_session_id AS SpidSolicitante,
    tl.resource_type AS TipoRecurso,
    tl.resource_description AS RecursoBloqueado,
    tl.request_mode AS ModoBloqueo,
    tl.request_status AS EstadoBloqueo,
    ISNULL(wt.wait_type, 'NINGUNO') AS WaitType,
    ISNULL(wt.blocking_session_id, 0) AS BlockingSpid
FROM sys.dm_tran_locks tl
LEFT JOIN sys.dm_os_waiting_tasks wt ON tl.lock_owner_address = wt.resource_address
WHERE tl.resource_description LIKE '%ETL_Lock_Fact_NegociacionLead%';
"@
            $snap = sqlcmd -S localhost -E -W -b -Q $qryDmv
            $evidenciaLocks = ($snap | Out-String).Trim()
            Write-Host ">> CONTENCION REGISTRADA EN VIVO EN ITERACION $i :"
            Write-Host $evidenciaLocks
            break
        }
        Start-Sleep -Milliseconds 250
    }

    Write-Host "Paso 5: Esperando finalización de Conexión 1 y Conexión 2..."
    $resJob1 = Receive-Job -Job $job1 -Wait
    $resJob2 = Receive-Job -Job $job2 -Wait

    # Verificación explícita de códigos de salida de los trabajos en segundo plano
    if ($null -eq $resJob1 -or $resJob1.ExitCode -ne 0) {
        throw "Fallo en Conexión 1 (ExitCode $($resJob1.ExitCode)): $($resJob1.Output)"
    }
    if ($null -eq $resJob2 -or $resJob2.ExitCode -ne 0) {
        throw "Fallo en Conexión 2 (ExitCode $($resJob2.ExitCode)): $($resJob2.Output)"
    }

    # Verificación estricta de espera observada
    if (-not $esperaDetectada) {
        throw "Fallo de Concurrencia: No se observó la espera requerida (LCK_M_X) en sys.dm_tran_locks."
    }

    # Verificación estricta de expectativas de negocio en la salida de cada conexión
    # Conexión 1 debe haber insertado 3 filas
    if ($resJob1.Output -notmatch "Insertados\s*=\s*3") {
        throw "Fallo en Conexión 1: No se observó la inserción esperada de 3 filas. Salida: $($resJob1.Output)"
    }
    # Conexión 2 debe haber encontrado 0 inserciones y 3 sin cambio (segunda carga sin cambios)
    if ($resJob2.Output -notmatch "Insertados\s*=\s*0" -or $resJob2.Output -notmatch "SinCambio\s*=\s*3") {
        throw "Fallo en Conexión 2: No se observó la segunda carga idéntica sin cambios (Insertados=0, SinCambio=3). Salida: $($resJob2.Output)"
    }

    # Registrar evidencias de conexiones
    "1. EVIDENCIA DE CONTENCION OBSERVADA EN VIVO (SYS.DM_TRAN_LOCKS / SYS.DM_OS_WAITING_TASKS):" | Out-File -FilePath $logFile -Append -Encoding utf8
    $evidenciaLocks | Out-File -FilePath $logFile -Append -Encoding utf8
    "" | Out-File -FilePath $logFile -Append -Encoding utf8

    "2. SALIDA DE CONEXION 1 (ExitCode: $($resJob1.ExitCode)):" | Out-File -FilePath $logFile -Append -Encoding utf8
    $resJob1.Output.Trim() | Out-File -FilePath $logFile -Append -Encoding utf8
    "" | Out-File -FilePath $logFile -Append -Encoding utf8

    "3. SALIDA DE CONEXION 2 (ExitCode: $($resJob2.ExitCode)):" | Out-File -FilePath $logFile -Append -Encoding utf8
    $resJob2.Output.Trim() | Out-File -FilePath $logFile -Append -Encoding utf8
    "" | Out-File -FilePath $logFile -Append -Encoding utf8

    Write-Host "Paso 6: Verificación de invariantes en el Data Mart (0 duplicados)..."
    # Consulta directa de verificación antes de la limpieza
    $countsRaw = sqlcmd -S localhost -E -d $martDb -h -1 -W -b -Q "SELECT CAST(COUNT(*) AS VARCHAR) + '|' + CAST(COUNT(DISTINCT id_solicitud_origen) AS VARCHAR) FROM dbo.Fact_NegociacionLead;"
    if ($LASTEXITCODE -ne 0) {
        throw "Error al consultar invariantes en Fact_NegociacionLead."
    }
    $countsLine = ($countsRaw | Where-Object { $_ -match '^\d+\|\d+$' } | Select-Object -First 1)
    $partes = $countsLine.Split('|')
    $totFilas = [int]$partes[0]
    $totUnicas = [int]$partes[1]

    if ($totFilas -ne 3 -or $totUnicas -ne 3) {
        throw "Fallo de Invariantes: Se esperaban 3 filas y 3 únicas en Fact_NegociacionLead (0 duplicados). Obtenido: TotalFilas=$totFilas, TotalUnicas=$totUnicas."
    }

    $outVerif = sqlcmd -S localhost -E -b -i "$auxDir\04_verificar_y_limpiar_lead.sql"
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo en la verificación/limpieza final: $outVerif"
    }

    "4. VERIFICACION FINAL DE TABLA DE HECHOS Y LOGS (TotalFilas: $totFilas, TotalUnicas: $totUnicas, 0 DUPLICADOS):" | Out-File -FilePath $logFile -Append -Encoding utf8
    ($outVerif | Out-String) | Out-File -FilePath $logFile -Append -Encoding utf8

    Write-Host "Prueba de concurrencia LEAD finalizada exitosamente. Evidencia guardada en $logFile."
} catch {
    $errorEjecucion = $_
    $msgErr = "ERROR CRÍTICO EN CONCURRENCIA: $($_.Exception.Message)"
    Write-Host $msgErr
    $msgErr | Out-File -FilePath $logFile -Append -Encoding utf8
} finally {
    # Manejo seguro de fallos parciales: no referenciar trabajos que todavía no existen
    if ($null -ne $job1) {
        Remove-Job -Job $job1 -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $job2) {
        Remove-Job -Job $job2 -Force -ErrorAction SilentlyContinue
    }

    [System.Data.SqlClient.SqlConnection]::ClearAllPools()

    if ($basesIniciadas) {
        # Limpieza defensiva final únicamente de bases creadas por esta ejecución y si aún siguen existiendo
        # Cierre normal sin desconectar sesiones por la fuerza (sin SINGLE_USER WITH ROLLBACK IMMEDIATE)
        foreach ($db in @($martDb, $oltpDb)) {
            $chkRaw = sqlcmd -S localhost -E -h -1 -W -b -Q "SELECT COUNT(*) FROM sys.databases WHERE name = '$db';"
            $dbExists = [int]($chkRaw | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
            if ($dbExists -gt 0) {
                $dropOut = sqlcmd -S localhost -E -b -Q "USE master; IF DB_ID('$db') IS NOT NULL DROP DATABASE [$db];" 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $falloLimpieza = $true
                    $errorLimpieza = ($dropOut | Out-String).Trim()
                    $msgLimpieza = "ERROR EN LIMPIEZA: No se pudo eliminar la base temporal [$db] de forma normal (posiblemente ocupada o en uso): $errorLimpieza"
                    Write-Host $msgLimpieza
                    $msgLimpieza | Out-File -FilePath $logFile -Append -Encoding utf8
                } else {
                    Write-Host "Base temporal [$db] eliminada limpiamente (cierre normal)."
                }
            }
        }
    }
}

$fallasConc = [System.Collections.Generic.List[string]]::new()

if ($null -ne $errorEjecucion) {
    $fallasConc.Add("Fallo durante la ejecución de concurrencia: $($errorEjecucion.Exception.Message)")
}

if ($falloLimpieza) {
    $fallasConc.Add("Fallo de limpieza en concurrencia: Una o más bases temporales permanecieron ocupadas o no pudieron eliminarse normalmente: $errorLimpieza")
}

if ($fallasConc.Count -gt 0) {
    foreach ($f in $fallasConc) {
        Write-Error $f
    }
    exit 1
}

exit 0
