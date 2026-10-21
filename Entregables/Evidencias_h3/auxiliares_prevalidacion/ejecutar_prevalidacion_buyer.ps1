# ====================================================================================================
# AUXILIAR PORTABLE: EJECUTOR DE PREVALIDACIÓN NEGATIVA SOBRE ARCHIVO REAL ETL BUYER H3
# Archivo Evaluado: Entregables\15. ETL_Fact_CaptacionBuyer_h3.sql
# Protocolo: Invocación de procesos sqlcmd independientes con -b, captura de exit code,
# diagnóstico, comprobación de invariancia de estructuras/datos y ausencia de objetos posteriores.
# ====================================================================================================

$ErrorActionPreference = "Stop"
$auxDir = $PSScriptRoot
if (-not $auxDir) { $auxDir = (Get-Location).Path }
$repoRoot = (Resolve-Path "$auxDir\..\..\..").Path
$RealEtlFile = Join-Path $repoRoot "Entregables\15. ETL_Fact_CaptacionBuyer_h3.sql"
$EvidenciaDir = (Resolve-Path "$auxDir\..").Path
$OutputFile = Join-Path $EvidenciaDir "salida_prevalidacion_buyer.txt"

if (-not (Test-Path $RealEtlFile)) {
    Write-Error "ABORTANDO: No se encontró el archivo real de ETL en: $RealEtlFile"
    exit 1
}

if (!(Test-Path $EvidenciaDir)) {
    New-Item -ItemType Directory -Path $EvidenciaDir -Force | Out-Null
}

$LogLines = @()
function LogMsg($msg) {
    Write-Host $msg
    $script:LogLines += $msg
}

function Invoke-SqlCmdScalar($query, $database = "master") {
    $conn = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Database=$database;Integrated Security=True;Pooling=False;")
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        return $cmd.ExecuteScalar()
    } finally {
        $conn.Close()
        $conn.Dispose()
    }
}

function Invoke-SqlCmdNonQuery($query, $database = "master") {
    $conn = New-Object System.Data.SqlClient.SqlConnection("Server=localhost;Database=$database;Integrated Security=True;Pooling=False;")
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        $cmd.ExecuteNonQuery() | Out-Null
    } finally {
        $conn.Close()
        $conn.Dispose()
    }
}

# 1. Comprobación defensiva previa de no existencia para TODAS las bases que utilizará la ejecución
$dbsPlanificadas = @(
    "Test_NexoSalud_Mart_Preval_P01",
    "Test_NexoSalud_Mart_Preval_P02",
    "Test_NexoSalud_Mart_Preval_P03",
    "Test_NexoSalud_Mart_Preval_P04"
)
$dbListStr = ($dbsPlanificadas | ForEach-Object { "'$_'" }) -join ","
$chkExistentes = Invoke-SqlCmdScalar "SELECT COUNT(*) FROM sys.databases WHERE name IN ($dbListStr);" "master"
if ($chkExistentes -gt 0) {
    $existentesStr = Invoke-SqlCmdScalar "SELECT STRING_AGG(name, ', ') FROM sys.databases WHERE name IN ($dbListStr);" "master"
    Write-Error "ABORTANDO: Una o más bases de prueba de prevalidación ya existen en el servidor ($existentesStr). Limpie manualmente antes de continuar; no se eliminan ni modifican bases preexistentes."
    exit 1
}

# Registro estricto de bases creadas por ESTA ejecución
$basesCreadas = [System.Collections.Generic.List[string]]::new()

function Preparar-DimensionesBase($targetDb) {
    $ddl = @"
CREATE TABLE dbo.Dim_Tiempo (KeyTiempo INT IDENTITY(1,1) PRIMARY KEY, id_fecha DATE NOT NULL);
CREATE TABLE dbo.Dim_Canal (KeyCanal INT IDENTITY(1,1) PRIMARY KEY, id_canal INT NULL);
CREATE TABLE dbo.Dim_Fuente (KeyFuente INT IDENTITY(1,1) PRIMARY KEY, id_campana INT NULL);
CREATE TABLE dbo.Dim_Campana (KeyCampana INT IDENTITY(1,1) PRIMARY KEY, id_campana INT NULL);
CREATE TABLE dbo.Dim_Sede (KeySede INT IDENTITY(1,1) PRIMARY KEY);
CREATE TABLE dbo.Dim_Persona (KeyPersona INT IDENTITY(1,1) PRIMARY KEY, id_persona INT NULL);
CREATE TABLE dbo.Dim_EstadoRegistro (
    KeyEstadoRegistro INT IDENTITY(1,1) PRIMARY KEY,
    EstadoCalidad VARCHAR(50) NOT NULL,
    AutorizacionContacto VARCHAR(10) NOT NULL
);
SET IDENTITY_INSERT dbo.Dim_Tiempo ON; INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha) VALUES (0, '1900-01-01'); SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;
SET IDENTITY_INSERT dbo.Dim_Canal ON; INSERT INTO dbo.Dim_Canal (KeyCanal, id_canal) VALUES (0, NULL); SET IDENTITY_INSERT dbo.Dim_Canal OFF;
SET IDENTITY_INSERT dbo.Dim_Fuente ON; INSERT INTO dbo.Dim_Fuente (KeyFuente, id_campana) VALUES (0, NULL); SET IDENTITY_INSERT dbo.Dim_Fuente OFF;
SET IDENTITY_INSERT dbo.Dim_Campana ON; INSERT INTO dbo.Dim_Campana (KeyCampana, id_campana) VALUES (0, NULL); SET IDENTITY_INSERT dbo.Dim_Campana OFF;
SET IDENTITY_INSERT dbo.Dim_Sede ON; INSERT INTO dbo.Dim_Sede (KeySede) VALUES (0); SET IDENTITY_INSERT dbo.Dim_Sede OFF;
SET IDENTITY_INSERT dbo.Dim_Persona ON; INSERT INTO dbo.Dim_Persona (KeyPersona, id_persona) VALUES (0, NULL); SET IDENTITY_INSERT dbo.Dim_Persona OFF;
SET IDENTITY_INSERT dbo.Dim_EstadoRegistro ON; INSERT INTO dbo.Dim_EstadoRegistro (KeyEstadoRegistro, EstadoCalidad, AutorizacionContacto) VALUES (0, 'Desconocido', 'NO'); SET IDENTITY_INSERT dbo.Dim_EstadoRegistro OFF;
"@
    Invoke-SqlCmdNonQuery $ddl $targetDb
}

function Ejecutar-ProcesoSqlcmdReal($targetDb) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "sqlcmd.exe"
    $psi.Arguments = "-S localhost -E -d $targetDb -b -i `"$RealEtlFile`""
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $procPid = $proc.Id
    LogMsg ">> Proceso sqlcmd iniciado [PID: $procPid] sobre base $targetDb..."

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    $proc.Close()

    return @{
        ExitCode = $exitCode
        Pid = $procPid
        Output = ($stdout + "`n" + $stderr).Trim()
    }
}

$Resultados = @()
$DbP01 = "Test_NexoSalud_Mart_Preval_P01"
$DbP02 = "Test_NexoSalud_Mart_Preval_P02"
$DbP03 = "Test_NexoSalud_Mart_Preval_P03"
$DbP04 = "Test_NexoSalud_Mart_Preval_P04"

$errorEjecucion = $null
$falloLimpieza = $false
$errorLimpieza = $null

$sqlAux = @"
CREATE TABLE dbo.Log_Ejecucion_ETL (LogId BIGINT IDENTITY PRIMARY KEY, Procedimiento VARCHAR(100) NOT NULL, BatchId VARCHAR(50) NOT NULL, TipoEvento VARCHAR(30) NOT NULL, Mensaje VARCHAR(MAX) NOT NULL, LineaError INT NULL, FechaRegistro DATETIME2 NOT NULL);
CREATE TABLE dbo.Rechazos_ETL_Buyer (RechazoId BIGINT IDENTITY PRIMARY KEY, EntidadOrigenId INT NOT NULL, MotivoRechazo VARCHAR(150) NOT NULL, DetalleRechazo VARCHAR(MAX) NULL, BatchId VARCHAR(50) NOT NULL, FechaRechazo DATETIME2 NOT NULL);
"@

try {
    LogMsg "================================================================================="
    LogMsg "EVALUACIÓN DE PREVALIDACIÓN NEGATIVA SOBRE ARCHIVO REAL ETL BUYER H3"
    LogMsg "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    LogMsg "Archivo Real Invocado: $RealEtlFile"
    LogMsg "================================================================================="

    # ====================================================================================================
    # ESCENARIO PREVAL-01: Columna Contractual con Longitud y Precisión Insuficiente
    # ====================================================================================================
    LogMsg "`n---------------------------------------------------------------------------------"
    LogMsg "EJECUTANDO ESCENARIO PREVAL-01: Longitud y Precisión Insuficiente en Fact_CaptacionBuyer"
    LogMsg "---------------------------------------------------------------------------------"

    Invoke-SqlCmdNonQuery "CREATE DATABASE [$DbP01];" "master"
    $basesCreadas.Add($DbP01)
    Preparar-DimensionesBase $DbP01
    Invoke-SqlCmdNonQuery $sqlAux $DbP01

    $sqlFactP1 = @"
CREATE TABLE dbo.Fact_CaptacionBuyer (
    KeyFactBuyer BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_persona_origen INT NOT NULL UNIQUE,
    KeyTiempoRegistro INT NOT NULL REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyTiempoConversion INT NOT NULL REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyCanal INT NOT NULL REFERENCES dbo.Dim_Canal(KeyCanal),
    KeyFuente INT NOT NULL REFERENCES dbo.Dim_Fuente(KeyFuente),
    KeyCampana INT NOT NULL REFERENCES dbo.Dim_Campana(KeyCampana),
    KeySede INT NOT NULL REFERENCES dbo.Dim_Sede(KeySede),
    KeyPersona INT NOT NULL REFERENCES dbo.Dim_Persona(KeyPersona),
    KeyEstadoRegistro INT NOT NULL REFERENCES dbo.Dim_EstadoRegistro(KeyEstadoRegistro),
    ContactosRegistrados INT NOT NULL,
    ContactosUtilizables INT NOT NULL,
    ContactosElegiblesB1 INT NOT NULL,
    ConversionesALead14Dias INT NOT NULL,
    ConversionesALead INT NOT NULL,
    SegundosConversion BIGINT NULL,
    TiempoConversionDias INT NULL,
    CostoAtribuidoCaptacion DECIMAL(6,2) NULL,
    EstadoDisponibilidadCosto VARCHAR(30) NOT NULL,
    BatchId VARCHAR(20) NOT NULL,
    FechaCarga DATETIME2 NOT NULL,
    UsuarioCarga VARCHAR(50) NOT NULL
);
INSERT INTO dbo.Fact_CaptacionBuyer (id_persona_origen, KeyTiempoRegistro, KeyTiempoConversion, KeyCanal, KeyFuente, KeyCampana, KeySede, KeyPersona, KeyEstadoRegistro, ContactosRegistrados, ContactosUtilizables, ContactosElegiblesB1, ConversionesALead14Dias, ConversionesALead, CostoAtribuidoCaptacion, EstadoDisponibilidadCosto, BatchId, FechaCarga, UsuarioCarga)
VALUES (9999, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 50.00, 'PendienteConciliacion', 'BATCH_TEST_PREVAL', SYSDATETIME(), 'ETL_USER');
"@
    Invoke-SqlCmdNonQuery $sqlFactP1 $DbP01

    $procPreex = "CREATE PROCEDURE dbo.usp_Cargar_Fact_CaptacionBuyer AS BEGIN SELECT 'PREEXISTENTE' AS res; END;"
    Invoke-SqlCmdNonQuery $procPreex $DbP01

    $res1 = Ejecutar-ProcesoSqlcmdReal $DbP01
    $exitCode1 = $res1.ExitCode
    $procOutput1 = $res1.Output

    $diagCosto = $procOutput1 -like "*Capacidad decimal insuficiente*decimal(6,2)*"
    $diagBatch = $procOutput1 -like "*BatchId*Longitud 20 menor a requerida 50*"
    $colTipoCosto = Invoke-SqlCmdScalar "SELECT t.name + '(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')' FROM sys.columns c JOIN sys.types t ON c.user_type_id = t.user_type_id WHERE c.object_id = OBJECT_ID('dbo.Fact_CaptacionBuyer') AND c.name = 'CostoAtribuidoCaptacion'" $DbP01
    $colTipoBatch = Invoke-SqlCmdScalar "SELECT t.name + '(' + CAST(c.max_length AS VARCHAR) + ')' FROM sys.columns c JOIN sys.types t ON c.user_type_id = t.user_type_id WHERE c.object_id = OBJECT_ID('dbo.Fact_CaptacionBuyer') AND c.name = 'BatchId'" $DbP01
    $filasFact1 = Invoke-SqlCmdScalar "SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 9999" $DbP01
    $estructOk1 = ($colTipoCosto -eq "decimal(6,2)" -and $colTipoBatch -eq "varchar(20)")
    $datosOk1 = ($filasFact1 -eq 1)
    $objPostOk1 = ((Invoke-SqlCmdScalar "SELECT COUNT(*) FROM sys.tables WHERE name IN ('Rechazos_ETL_Buyer_Post', 'Log_Ejecucion_ETL_Post')" $DbP01) -eq 0)
    $procDef1 = Invoke-SqlCmdScalar "SELECT definition FROM sys.sql_modules WHERE object_id = OBJECT_ID('dbo.usp_Cargar_Fact_CaptacionBuyer')" $DbP01
    $procPreexOk1 = ($procDef1 -like "*PREEXISTENTE*")

    $resP01 = ($exitCode1 -ne 0 -and $diagCosto -and $diagBatch -and $estructOk1 -and $datosOk1 -and $objPostOk1 -and $procPreexOk1)
    LogMsg "Resultado PREVAL-01: ExitCode=$exitCode1, DiagCosto=$diagCosto, DiagBatch=$diagBatch, EstructuraOk=$estructOk1, DatosOk=$datosOk1, SinObjPost=$objPostOk1, ProcPreexOk=$procPreexOk1 -> Veredicto: $(if ($resP01) { 'CORRECTO' } else { 'FALLIDO' })"
    $Resultados += [PSCustomObject]@{
        Caso = "PREVAL-01"
        Nombre = "Prevalidación Negativa: Longitud y Precisión Insuficiente en Fact_CaptacionBuyer"
        ArchivoReal = "15. ETL_Fact_CaptacionBuyer_h3.sql"
        Veredicto = if ($resP01) { "CORRECTO" } else { "FALLIDO" }
    }

    # ====================================================================================================
    # ESCENARIO PREVAL-02: Capacidad Entera Decimal Insuficiente (DECIMAL(10,9))
    # ====================================================================================================
    LogMsg "`n---------------------------------------------------------------------------------"
    LogMsg "EJECUTANDO ESCENARIO PREVAL-02: Capacidad Entera Decimal Insuficiente (DECIMAL(10,9))"
    LogMsg "---------------------------------------------------------------------------------"

    Invoke-SqlCmdNonQuery "CREATE DATABASE [$DbP02];" "master"
    $basesCreadas.Add($DbP02)
    Preparar-DimensionesBase $DbP02
    Invoke-SqlCmdNonQuery $sqlAux $DbP02

    $sqlFactP2 = @"
CREATE TABLE dbo.Fact_CaptacionBuyer (
    KeyFactBuyer BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_persona_origen INT NOT NULL UNIQUE,
    KeyTiempoRegistro INT NOT NULL REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyTiempoConversion INT NOT NULL REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyCanal INT NOT NULL REFERENCES dbo.Dim_Canal(KeyCanal),
    KeyFuente INT NOT NULL REFERENCES dbo.Dim_Fuente(KeyFuente),
    KeyCampana INT NOT NULL REFERENCES dbo.Dim_Campana(KeyCampana),
    KeySede INT NOT NULL REFERENCES dbo.Dim_Sede(KeySede),
    KeyPersona INT NOT NULL REFERENCES dbo.Dim_Persona(KeyPersona),
    KeyEstadoRegistro INT NOT NULL REFERENCES dbo.Dim_EstadoRegistro(KeyEstadoRegistro),
    ContactosRegistrados INT NOT NULL,
    ContactosUtilizables INT NOT NULL,
    ContactosElegiblesB1 INT NOT NULL,
    ConversionesALead14Dias INT NOT NULL,
    ConversionesALead INT NOT NULL,
    SegundosConversion BIGINT NULL,
    TiempoConversionDias INT NULL,
    CostoAtribuidoCaptacion DECIMAL(10,9) NULL,
    EstadoDisponibilidadCosto VARCHAR(30) NOT NULL,
    BatchId VARCHAR(50) NOT NULL,
    FechaCarga DATETIME2 NOT NULL,
    UsuarioCarga VARCHAR(50) NOT NULL
);
INSERT INTO dbo.Fact_CaptacionBuyer (id_persona_origen, KeyTiempoRegistro, KeyTiempoConversion, KeyCanal, KeyFuente, KeyCampana, KeySede, KeyPersona, KeyEstadoRegistro, ContactosRegistrados, ContactosUtilizables, ContactosElegiblesB1, ConversionesALead14Dias, ConversionesALead, CostoAtribuidoCaptacion, EstadoDisponibilidadCosto, BatchId, FechaCarga, UsuarioCarga)
VALUES (9998, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0.123456789, 'PendienteConciliacion', 'BATCH_TEST_P02', SYSDATETIME(), 'ETL_USER');
"@
    Invoke-SqlCmdNonQuery $sqlFactP2 $DbP02

    $res2 = Ejecutar-ProcesoSqlcmdReal $DbP02
    $exitCode2 = $res2.ExitCode
    $procOutput2 = $res2.Output

    $diagDecimal = $procOutput2 -like "*Capacidad decimal insuficiente*decimal(10,9)*"
    $colTipoCosto2 = Invoke-SqlCmdScalar "SELECT t.name + '(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')' FROM sys.columns c JOIN sys.types t ON c.user_type_id = t.user_type_id WHERE c.object_id = OBJECT_ID('dbo.Fact_CaptacionBuyer') AND c.name = 'CostoAtribuidoCaptacion'" $DbP02
    $filasFact2 = Invoke-SqlCmdScalar "SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 9998" $DbP02
    $estructOk2 = ($colTipoCosto2 -eq "decimal(10,9)")
    $datosOk2 = ($filasFact2 -eq 1)
    $objPostOk2 = ((Invoke-SqlCmdScalar "SELECT COUNT(*) FROM sys.tables WHERE name IN ('Rechazos_ETL_Buyer_Post')" $DbP02) -eq 0)

    $resP02 = ($exitCode2 -ne 0 -and $diagDecimal -and $estructOk2 -and $datosOk2 -and $objPostOk2)
    LogMsg "Resultado PREVAL-02: ExitCode=$exitCode2, DiagDecimal=$diagDecimal, EstructuraOk=$estructOk2, DatosOk=$datosOk2, SinObjPost=$objPostOk2 -> Veredicto: $(if ($resP02) { 'CORRECTO' } else { 'FALLIDO' })"
    $Resultados += [PSCustomObject]@{
        Caso = "PREVAL-02"
        Nombre = "Prevalidación Negativa: Capacidad Entera Decimal Insuficiente (DECIMAL(10,9))"
        ArchivoReal = "15. ETL_Fact_CaptacionBuyer_h3.sql"
        Veredicto = if ($resP02) { "CORRECTO" } else { "FALLIDO" }
    }

    # ====================================================================================================
    # ESCENARIO PREVAL-03: Tabla Auxiliar con Identidad Correcta pero Columna Ausente (Log_Ejecucion_ETL sin Mensaje)
    # ====================================================================================================
    LogMsg "`n---------------------------------------------------------------------------------"
    LogMsg "EJECUTANDO ESCENARIO PREVAL-03: Tabla Auxiliar sin Columna Obligatoria (Log_Ejecucion_ETL sin Mensaje)"
    LogMsg "---------------------------------------------------------------------------------"

    Invoke-SqlCmdNonQuery "CREATE DATABASE [$DbP03];" "master"
    $basesCreadas.Add($DbP03)
    Preparar-DimensionesBase $DbP03

    $ddlLogP3 = @"
CREATE TABLE dbo.Log_Ejecucion_ETL (
    LogId BIGINT IDENTITY(1,1) PRIMARY KEY,
    Procedimiento VARCHAR(100) NOT NULL,
    FechaRegistro DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    BatchId VARCHAR(50) NOT NULL,
    TipoEvento VARCHAR(30) NOT NULL,
    LineaError INT NULL
);
INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento) VALUES ('PROC_TEST', 'BATCH_01', 'INFO');
"@
    Invoke-SqlCmdNonQuery $ddlLogP3 $DbP03
    Invoke-SqlCmdNonQuery "CREATE TABLE dbo.Rechazos_ETL_Buyer (RechazoId BIGINT IDENTITY PRIMARY KEY, EntidadOrigenId INT NOT NULL, MotivoRechazo VARCHAR(150) NOT NULL, DetalleRechazo VARCHAR(MAX) NULL, BatchId VARCHAR(50) NOT NULL, FechaRechazo DATETIME2 NOT NULL);" $DbP03

    $res3 = Ejecutar-ProcesoSqlcmdReal $DbP03
    $exitCode3 = $res3.ExitCode
    $procOutput3 = $res3.Output

    $diagLog = $procOutput3 -like "*Log_Ejecucion_ETL*Mensaje*"
    $filasLog3 = Invoke-SqlCmdScalar "SELECT COUNT(*) FROM dbo.Log_Ejecucion_ETL WHERE Procedimiento = 'PROC_TEST'" $DbP03
    $colMensajeExiste = Invoke-SqlCmdScalar "SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Log_Ejecucion_ETL') AND name = 'Mensaje'" $DbP03
    $estructOk3 = ($colMensajeExiste -eq 0)
    $datosOk3 = ($filasLog3 -eq 1)
    $objPostOk3 = ((Invoke-SqlCmdScalar "SELECT COUNT(*) FROM sys.tables WHERE name IN ('Fact_CaptacionBuyer')" $DbP03) -eq 0)

    $resP03 = ($exitCode3 -ne 0 -and $diagLog -and $estructOk3 -and $datosOk3 -and $objPostOk3)
    LogMsg "Resultado PREVAL-03: ExitCode=$exitCode3, DiagLog=$diagLog, EstructuraOk=$estructOk3, DatosOk=$datosOk3, SinObjPost=$objPostOk3 -> Veredicto: $(if ($resP03) { 'CORRECTO' } else { 'FALLIDO' })"
    $Resultados += [PSCustomObject]@{
        Caso = "PREVAL-03"
        Nombre = "Prevalidación Negativa: Tabla Auxiliar con Identidad pero Columna Ausente (Log_Ejecucion_ETL sin Mensaje)"
        ArchivoReal = "15. ETL_Fact_CaptacionBuyer_h3.sql"
        Veredicto = if ($resP03) { "CORRECTO" } else { "FALLIDO" }
    }

    # ====================================================================================================
    # ESCENARIO PREVAL-04: Unicidad Compuesta y FK Deshabilitada
    # ====================================================================================================
    LogMsg "`n---------------------------------------------------------------------------------"
    LogMsg "EJECUTANDO ESCENARIO PREVAL-04: Unicidad Compuesta y FK Deshabilitada"
    LogMsg "---------------------------------------------------------------------------------"

    Invoke-SqlCmdNonQuery "CREATE DATABASE [$DbP04];" "master"
    $basesCreadas.Add($DbP04)
    Preparar-DimensionesBase $DbP04
    Invoke-SqlCmdNonQuery $sqlAux $DbP04

    $ddlFactP4 = @"
CREATE TABLE dbo.Fact_CaptacionBuyer (
    KeyFactBuyer BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_persona_origen INT NOT NULL,
    KeyTiempoRegistro INT NOT NULL,
    KeyTiempoConversion INT NOT NULL REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyCanal INT NOT NULL REFERENCES dbo.Dim_Canal(KeyCanal),
    KeyFuente INT NOT NULL REFERENCES dbo.Dim_Fuente(KeyFuente),
    KeyCampana INT NOT NULL REFERENCES dbo.Dim_Campana(KeyCampana),
    KeySede INT NOT NULL REFERENCES dbo.Dim_Sede(KeySede),
    KeyPersona INT NOT NULL REFERENCES dbo.Dim_Persona(KeyPersona),
    KeyEstadoRegistro INT NOT NULL REFERENCES dbo.Dim_EstadoRegistro(KeyEstadoRegistro),
    ContactosRegistrados INT NOT NULL,
    ContactosUtilizables INT NOT NULL,
    ContactosElegiblesB1 INT NOT NULL,
    ConversionesALead14Dias INT NOT NULL,
    ConversionesALead INT NOT NULL,
    SegundosConversion BIGINT NULL,
    TiempoConversionDias INT NULL,
    CostoAtribuidoCaptacion DECIMAL(10,2) NULL,
    EstadoDisponibilidadCosto VARCHAR(30) NOT NULL,
    BatchId VARCHAR(50) NOT NULL,
    FechaCarga DATETIME2 NOT NULL,
    UsuarioCarga VARCHAR(50) NOT NULL,
    CONSTRAINT UQ_FactBuyer_Compuesta UNIQUE (id_persona_origen, KeyTiempoRegistro)
);
ALTER TABLE dbo.Fact_CaptacionBuyer ADD CONSTRAINT FK_FactBuyer_TiempoReg FOREIGN KEY (KeyTiempoRegistro) REFERENCES dbo.Dim_Tiempo(KeyTiempo);
ALTER TABLE dbo.Fact_CaptacionBuyer NOCHECK CONSTRAINT FK_FactBuyer_TiempoReg;
INSERT INTO dbo.Fact_CaptacionBuyer (id_persona_origen, KeyTiempoRegistro, KeyTiempoConversion, KeyCanal, KeyFuente, KeyCampana, KeySede, KeyPersona, KeyEstadoRegistro, ContactosRegistrados, ContactosUtilizables, ContactosElegiblesB1, ConversionesALead14Dias, ConversionesALead, CostoAtribuidoCaptacion, EstadoDisponibilidadCosto, BatchId, FechaCarga, UsuarioCarga)
VALUES (9997, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 50.00, 'PendienteConciliacion', 'BATCH_P04', SYSDATETIME(), 'ETL_USER');
"@
    Invoke-SqlCmdNonQuery $ddlFactP4 $DbP04

    $res4 = Ejecutar-ProcesoSqlcmdReal $DbP04
    $exitCode4 = $res4.ExitCode
    $procOutput4 = $res4.Output

    $diagUq = $procOutput4 -like "*id_persona_origen*compuesto no garantiza la unicidad individual*"
    $diagFk = $procOutput4 -like "*KeyTiempoRegistro*FK deshabilitada*"
    $filasFact4 = Invoke-SqlCmdScalar "SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 9997" $DbP04
    $fkDisabled = Invoke-SqlCmdScalar "SELECT is_disabled FROM sys.foreign_keys WHERE name = 'FK_FactBuyer_TiempoReg'" $DbP04
    $estructOk4 = ($fkDisabled -eq 1)
    $datosOk4 = ($filasFact4 -eq 1)
    $objPostOk4 = ((Invoke-SqlCmdScalar "SELECT COUNT(*) FROM sys.tables WHERE name IN ('Rechazos_ETL_Buyer_Post')" $DbP04) -eq 0)

    $resP04 = ($exitCode4 -ne 0 -and $diagUq -and $diagFk -and $estructOk4 -and $datosOk4 -and $objPostOk4)
    LogMsg "Resultado PREVAL-04: ExitCode=$exitCode4, DiagUq=$diagUq, DiagFk=$diagFk, EstructuraOk=$estructOk4, DatosOk=$datosOk4, SinObjPost=$objPostOk4 -> Veredicto: $(if ($resP04) { 'CORRECTO' } else { 'FALLIDO' })"
    $Resultados += [PSCustomObject]@{
        Caso = "PREVAL-04"
        Nombre = "Prevalidación Negativa: Unicidad Compuesta y FK Deshabilitada"
        ArchivoReal = "15. ETL_Fact_CaptacionBuyer_h3.sql"
        Veredicto = if ($resP04) { "CORRECTO" } else { "FALLIDO" }
    }

} catch {
    $errorEjecucion = $_
    LogMsg "`nERROR CRÍTICO DURANTE EJECUCIÓN: $($_.Exception.Message)"
} finally {
    LogMsg "`n================================================================================="
    LogMsg "RESUMEN CONSOLIDADO DE PREVALIDACIÓN NEGATIVA SOBRE ARCHIVO REAL:"
    LogMsg "================================================================================="
    $totalEval = @($Resultados).Count
    $totalOk = @($Resultados | Where-Object { $_.Veredicto -eq "CORRECTO" }).Count
    $totalFail = @($Resultados | Where-Object { $_.Veredicto -ne "CORRECTO" }).Count

    foreach ($r in $Resultados) {
        LogMsg ("{0,-10} {1,-65} {2}" -f $r.Caso, $r.Nombre, $r.Veredicto)
    }
    LogMsg "---------------------------------------------------------------------------------"
    LogMsg "Total Escenarios Planificados: 4"
    LogMsg "Total Escenarios Evaluados   : $totalEval"
    LogMsg "Escenarios Correctos         : $totalOk"
    LogMsg "Escenarios Fallidos          : $totalFail"
    if ($errorEjecucion) {
        LogMsg "Fallo Crítico de Ejecución   : $($errorEjecucion.Exception.Message)"
    }

    [System.Data.SqlClient.SqlConnection]::ClearAllPools()

    LogMsg "`n>> Procediendo a la limpieza de bases temporales creadas exclusivamente por esta ejecución..."
    foreach ($db in $basesCreadas) {
        try {
            $dropSql = "USE master; IF DB_ID('$db') IS NOT NULL DROP DATABASE [$db];"
            Invoke-SqlCmdNonQuery $dropSql "master"
            LogMsg ">> Base temporal [$db] eliminada limpiamente (cierre normal)."
        } catch {
            $falloLimpieza = $true
            $errorLimpieza = $_
            $errMsg = $_.Exception.Message
            LogMsg "ERROR EN LIMPIEZA: No se pudo eliminar la base temporal [$db] (posiblemente ocupada o en uso): $errMsg"
            LogMsg ">> Se registra el problema sin forzar la desconexión de sesiones."
        }
    }

    $dictamenValido = ($null -eq $errorEjecucion -and $totalEval -eq 4 -and $totalFail -eq 0 -and -not $falloLimpieza)
    LogMsg "Dictamen de Prevalidación    : $(if ($dictamenValido) { 'TODOS LOS CASOS NEGATIVOS APROBADOS FRENTE AL ARCHIVO REAL' } else { 'PREVALIDACIÓN FALLIDA' })"

    try {
        $LogLines | Out-File -FilePath $OutputFile -Encoding utf8
        LogMsg ">> Evidencia completa guardada en: $OutputFile"
    } catch {
        LogMsg "ADVERTENCIA: No se pudo guardar el archivo de evidencia: $($_.Exception.Message)"
    }
}

$erroresPreval = [System.Collections.Generic.List[string]]::new()

if ($null -ne $errorEjecucion) {
    $erroresPreval.Add("Fallo durante la ejecución de la prevalidación: $($errorEjecucion.Exception.Message)")
}

if ($totalEval -ne 4) {
    $erroresPreval.Add("Fallo de cobertura: No se ejecutaron exactamente los 4 escenarios planificados (ejecutados: $totalEval de 4).")
}

if ($totalFail -gt 0) {
    $erroresPreval.Add("Fallo de aserción: Se detectaron $totalFail escenario(s) con aserciones fallidas.")
}

if ($falloLimpieza) {
    $erroresPreval.Add("Fallo de limpieza: Una o más bases temporales permanecieron ocupadas o no pudieron eliminarse normalmente: $($errorLimpieza.Exception.Message)")
}

if ($erroresPreval.Count -gt 0) {
    foreach ($err in $erroresPreval) {
        Write-Error $err
    }
    exit 1
}

exit 0
