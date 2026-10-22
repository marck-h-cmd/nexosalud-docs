-- NexoSalud H3 / Alexis Vigo. Conectarse a NexoSalud_Mart con sqlcmd -d.
-- Requiere staging.stg_CitasCustomer, dimensiones H2/H3 y Log_Ejecucion_ETL.
-- No ejecutar 8.DDL ni el bloque CUSTOMER de 9.Poblacion despues de este script.
SET NOCOUNT ON;
IF OBJECT_ID('staging.stg_CitasCustomer', 'V') IS NULL THROW 51010, 'Falta staging.stg_CitasCustomer.', 1;
IF OBJECT_ID('dbo.Log_Ejecucion_ETL', 'U') IS NULL THROW 51011, 'Falta dbo.Log_Ejecucion_ETL del ETL BUYER.', 1;
IF OBJECT_ID('dbo.Dim_Persona', 'U') IS NULL THROW 51012, 'Falta Dim_Persona: resolver brecha H2 antes de desplegar.', 1;
IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NULL OR OBJECT_ID('dbo.Dim_Hora', 'U') IS NULL
 OR OBJECT_ID('dbo.Dim_Sede', 'U') IS NULL OR OBJECT_ID('dbo.Dim_Servicio', 'U') IS NULL
 OR OBJECT_ID('dbo.Dim_Profesional', 'U') IS NULL OR OBJECT_ID('dbo.Dim_EstadoAtencion', 'U') IS NULL
 THROW 51013, 'Faltan dimensiones conformadas CUSTOMER.', 1;
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Tiempo WHERE KeyTiempo=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Hora WHERE KeyHora=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Sede WHERE KeySede=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Servicio WHERE KeyServicio=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Profesional WHERE KeyProfesional=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.Dim_EstadoAtencion WHERE KeyEstadoAtencion=0)
 OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Persona WHERE KeyPersona=0)
 THROW 51014, 'Una dimension CUSTOMER no tiene miembro desconocido Key=0.', 1;
IF OBJECT_ID('dbo.Fact_AtencionCustomer', 'U') IS NOT NULL
 AND COL_LENGTH('dbo.Fact_AtencionCustomer', 'id_reserva_origen') IS NULL
BEGIN
 IF EXISTS (SELECT 1 FROM dbo.Fact_AtencionCustomer)
  THROW 51015, 'Fact_AtencionCustomer H2 contiene filas: requiere migracion revisada, no se borra.', 1;
 DROP TABLE dbo.Fact_AtencionCustomer;
END;
GO

IF OBJECT_ID('dbo.Rechazos_ETL_Customer', 'U') IS NULL
 CREATE TABLE dbo.Rechazos_ETL_Customer (
  RechazoId BIGINT IDENTITY(1,1) PRIMARY KEY,
  EntidadOrigenId INT NOT NULL,
  MotivoRechazo VARCHAR(100) NOT NULL,
  BatchId VARCHAR(50) NOT NULL,
  FechaRechazo DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT UQ_RechazosCustomer_Lote UNIQUE (EntidadOrigenId, BatchId)
 );
GO

IF OBJECT_ID('dbo.Fact_AtencionCustomer', 'U') IS NULL
 CREATE TABLE dbo.Fact_AtencionCustomer (
  KeyFactCustomer BIGINT IDENTITY(1,1) PRIMARY KEY,
  id_reserva_origen INT NOT NULL,
  id_atencion_origen INT NULL,
  id_persona_origen INT NOT NULL,
  KeyTiempoTurno INT NOT NULL,
  KeyTiempoInicio INT NOT NULL CONSTRAINT DF_Customer_TiempoInicio DEFAULT 0,
  KeyHora INT NOT NULL,
  KeySede INT NOT NULL,
  KeyServicio INT NOT NULL,
  KeyProfesional INT NOT NULL,
  KeyEstadoAtencion INT NOT NULL,
  KeyPersona INT NOT NULL,
  FechaHoraTurno DATETIME2(7) NOT NULL,
  FechaEventoCustomer DATETIME2(7) NULL,
  ResultadoCita VARCHAR(25) NOT NULL,
  CitasProgramadas INT NOT NULL,
  CitasEvaluables INT NOT NULL,
  AtencionesRealizadas INT NOT NULL,
  CitasConInasistencia INT NOT NULL,
  CitasCanceladas INT NOT NULL,
  CitasVencidasSinResultado INT NOT NULL,
  TiempoEnSillonDentalMin INT NULL,
  AtencionesIniciadas INT NOT NULL,
  AtencionesFinalizadas INT NOT NULL,
  AtencionesFinalizadasConformes INT NOT NULL,
  EventoCustomerDerivado BIT NOT NULL,
  BatchId VARCHAR(50) NOT NULL,
  FechaCarga DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
  FechaModificacion DATETIME2(7) NULL,
  UsuarioCarga VARCHAR(50) NOT NULL DEFAULT SYSTEM_USER,
  CONSTRAINT UQ_FactCustomer_Reserva UNIQUE (id_reserva_origen),
  CONSTRAINT FK_Customer_TiempoTurno FOREIGN KEY (KeyTiempoTurno) REFERENCES dbo.Dim_Tiempo(KeyTiempo),
  CONSTRAINT FK_Customer_TiempoInicio FOREIGN KEY (KeyTiempoInicio) REFERENCES dbo.Dim_Tiempo(KeyTiempo),
  CONSTRAINT FK_Customer_Hora FOREIGN KEY (KeyHora) REFERENCES dbo.Dim_Hora(KeyHora),
  CONSTRAINT FK_Customer_Sede FOREIGN KEY (KeySede) REFERENCES dbo.Dim_Sede(KeySede),
  CONSTRAINT FK_Customer_Servicio FOREIGN KEY (KeyServicio) REFERENCES dbo.Dim_Servicio(KeyServicio),
  CONSTRAINT FK_Customer_Profesional FOREIGN KEY (KeyProfesional) REFERENCES dbo.Dim_Profesional(KeyProfesional),
  CONSTRAINT FK_Customer_Estado FOREIGN KEY (KeyEstadoAtencion) REFERENCES dbo.Dim_EstadoAtencion(KeyEstadoAtencion),
  CONSTRAINT FK_Customer_Persona FOREIGN KEY (KeyPersona) REFERENCES dbo.Dim_Persona(KeyPersona),
  CONSTRAINT CK_Customer_Flags CHECK (
   CitasProgramadas BETWEEN 0 AND 1 AND CitasEvaluables BETWEEN 0 AND 1
   AND AtencionesRealizadas BETWEEN 0 AND 1 AND CitasConInasistencia BETWEEN 0 AND 1
   AND CitasCanceladas BETWEEN 0 AND 1 AND CitasVencidasSinResultado BETWEEN 0 AND 1
   AND AtencionesIniciadas BETWEEN 0 AND 1 AND AtencionesFinalizadas BETWEEN 0 AND 1
   AND AtencionesFinalizadasConformes BETWEEN 0 AND 1
   AND AtencionesRealizadas+CitasConInasistencia=CitasEvaluables
   AND (TiempoEnSillonDentalMin IS NULL OR TiempoEnSillonDentalMin >= 0)
  )
 );
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Fact_AtencionCustomer') AND name='IX_Customer_Turno')
 CREATE INDEX IX_Customer_Turno ON dbo.Fact_AtencionCustomer(KeyTiempoTurno,KeySede,KeyServicio)
 INCLUDE (CitasEvaluables,AtencionesRealizadas,CitasConInasistencia);
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cargar_Fact_AtencionCustomer
 @FechaCorte DATE, @BatchId VARCHAR(50),
 @Insertados INT=0 OUTPUT, @Actualizados INT=0 OUTPUT, @SinCambio INT=0 OUTPUT,
 @Rechazados INT=0 OUTPUT, @Pendientes INT=0 OUTPUT
AS
BEGIN
 SET NOCOUNT ON;
 SET XACT_ABORT ON;
 SET @Insertados=0; SET @Actualizados=0; SET @SinCambio=0; SET @Rechazados=0; SET @Pendientes=0;
 IF @FechaCorte IS NULL OR @FechaCorte='99991231' OR NULLIF(LTRIM(RTRIM(@BatchId)),'') IS NULL
  THROW 51020, 'FechaCorte valida y BatchId no vacio son obligatorios.', 1;
 IF OBJECT_ID('staging.stg_CitasCustomer','V') IS NULL THROW 51021, 'Falta staging CUSTOMER.', 1;
 DECLARE @Limite DATETIME2(7)=DATEADD(DAY,1,CAST(@FechaCorte AS DATETIME2(7)));
 DECLARE @Lock INT;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC @Lock=sys.sp_getapplock @Resource='ETL_Lock_Fact_AtencionCustomer', @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=30000;
  IF @Lock<0 THROW 51022, 'No se obtuvo bloqueo ETL CUSTOMER.', 1;
  INSERT dbo.Log_Ejecucion_ETL(Procedimiento,BatchId,TipoEvento,Mensaje)
   VALUES('dbo.usp_Cargar_Fact_AtencionCustomer',@BatchId,'INICIO','Inicio de carga CUSTOMER');

  SELECT s.*,
   CASE
    WHEN s.total_atenciones>1 THEN 'MultiplesAtencionesPorReserva'
    WHEN s.fecha_hora_turno IS NULL THEN 'TurnoSinFechaOHora'
    WHEN s.id_solicitud_opcion IS NULL OR s.id_persona_solicitud IS NULL
      OR s.id_solicitud_opcion<>s.id_solicitud OR s.id_persona_solicitud<>s.id_persona
      THEN 'CadenaSolicitudInconsistente'
    WHEN s.id_atencion IS NOT NULL AND s.id_persona_atencion<>s.id_persona THEN 'PersonaAtencionInconsistente'
    WHEN s.hora_fin IS NOT NULL AND s.hora_inicio IS NOT NULL AND s.hora_fin<=s.hora_inicio THEN 'TurnoInvalido'
    WHEN s.fecha_inicio IS NOT NULL AND s.fecha_inicio<s.fecha_reserva THEN 'AtencionAnteriorAReserva'
    WHEN s.fecha_inicio IS NOT NULL AND s.fecha_fin IS NOT NULL AND s.fecha_fin<s.fecha_inicio THEN 'DuracionNegativa'
    WHEN UPPER(LTRIM(RTRIM(s.asistencia))) IN ('NO ASISTIÓ','NO ASISTIO','NO-SHOW')
      AND s.fecha_inicio IS NOT NULL THEN 'NoShowConInicioClinico'
    WHEN s.fecha_reserva>=@Limite THEN 'FueraDeCorte'
    ELSE NULL END AS MotivoRechazo,
   CASE
    WHEN s.fecha_hora_turno>=@Limite THEN 'Futura'
    WHEN UPPER(LTRIM(RTRIM(s.estado_reserva))) IN ('CANCELADA','CANCELADO') THEN 'Cancelada'
    WHEN UPPER(LTRIM(RTRIM(s.estado_reserva))) IN ('REPROGRAMADA','REPROGRAMADO') THEN 'Reprogramada'
    WHEN UPPER(LTRIM(RTRIM(s.asistencia))) IN ('NO ASISTIÓ','NO ASISTIO','NO-SHOW')
      OR UPPER(LTRIM(RTRIM(s.estado_reserva))) IN ('NO ASISTIÓ','NO ASISTIO','NO-SHOW') THEN 'NoShow'
    WHEN UPPER(LTRIM(RTRIM(s.asistencia))) IN ('ASISTIÓ','ASISTIO')
      AND s.fecha_inicio IS NOT NULL AND s.fecha_inicio<@Limite THEN 'Asistio'
    ELSE 'PendienteResultado' END AS ResultadoCalculado
  INTO #Citas FROM staging.stg_CitasCustomer AS s WHERE s.fecha_reserva<@Limite;

  DELETE FROM dbo.Rechazos_ETL_Customer WHERE BatchId=@BatchId;
  INSERT dbo.Rechazos_ETL_Customer(EntidadOrigenId,MotivoRechazo,BatchId)
   SELECT id_reserva,MotivoRechazo,@BatchId FROM #Citas WHERE MotivoRechazo IS NOT NULL;
  SET @Rechazados=@@ROWCOUNT;

  -- Una fila previamente válida que ahora falla calidad no puede seguir sumando KPI.
  UPDATE f SET ResultadoCita='Rechazada',CitasProgramadas=0,CitasEvaluables=0,AtencionesRealizadas=0,
   CitasConInasistencia=0,CitasCanceladas=0,CitasVencidasSinResultado=0,
   TiempoEnSillonDentalMin=NULL,AtencionesIniciadas=0,AtencionesFinalizadas=0,
   AtencionesFinalizadasConformes=0,EventoCustomerDerivado=0,FechaEventoCustomer=NULL,
   BatchId=@BatchId,FechaModificacion=SYSDATETIME()
  FROM dbo.Fact_AtencionCustomer AS f
  JOIN #Citas AS c ON c.id_reserva=f.id_reserva_origen
  WHERE c.MotivoRechazo IS NOT NULL AND f.ResultadoCita<>'Rechazada';
  DECLARE @InvalidosActualizados INT=@@ROWCOUNT;

  -- Los lookups se hacen con una subconsulta por clave natural. Se detiene ante duplicados
  -- para impedir fanout silencioso de dimensiones.
  IF EXISTS(SELECT id_fecha FROM dbo.Dim_Tiempo WHERE id_fecha IS NOT NULL GROUP BY id_fecha HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_hora FROM dbo.Dim_Hora WHERE id_hora IS NOT NULL GROUP BY id_hora HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_sede FROM dbo.Dim_Sede WHERE id_sede IS NOT NULL GROUP BY id_sede HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_servicio FROM dbo.Dim_Servicio WHERE id_servicio IS NOT NULL GROUP BY id_servicio HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_profesional FROM dbo.Dim_Profesional WHERE id_profesional IS NOT NULL GROUP BY id_profesional HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_persona FROM dbo.Dim_Persona WHERE id_persona IS NOT NULL GROUP BY id_persona HAVING COUNT(*)>1)
   OR EXISTS(SELECT EstadoFinal,Asistencia FROM dbo.Dim_EstadoAtencion
     WHERE EstadoFinal IS NOT NULL AND Asistencia IS NOT NULL
     GROUP BY EstadoFinal,Asistencia HAVING COUNT(*)>1)
   THROW 51023, 'Claves naturales duplicadas en dimensiones CUSTOMER.', 1;

  SELECT c.id_reserva, c.id_atencion, c.id_persona,
   COALESCE(dt.KeyTiempo,0) AS KeyTiempoTurno,
   COALESCE(di.KeyTiempo,0) AS KeyTiempoInicio,
   COALESCE(dh.KeyHora,0) AS KeyHora,
   COALESCE(ds.KeySede,0) AS KeySede,
   COALESCE(dsv.KeyServicio,0) AS KeyServicio,
   COALESCE(dp.KeyProfesional,0) AS KeyProfesional,
   COALESCE(de.KeyEstadoAtencion,0) AS KeyEstadoAtencion,
   COALESCE(dper.KeyPersona,0) AS KeyPersona,
   c.fecha_hora_turno AS FechaHoraTurno,
   CASE WHEN c.ResultadoCalculado='Asistio' THEN c.fecha_inicio END AS FechaEventoCustomer,
   c.ResultadoCalculado AS ResultadoCita,
   CAST(1 AS INT) AS CitasProgramadas,
   CASE WHEN c.ResultadoCalculado IN ('Asistio','NoShow') THEN 1 ELSE 0 END AS CitasEvaluables,
   CASE WHEN c.ResultadoCalculado='Asistio' THEN 1 ELSE 0 END AS AtencionesRealizadas,
   CASE WHEN c.ResultadoCalculado='NoShow' THEN 1 ELSE 0 END AS CitasConInasistencia,
   CASE WHEN c.ResultadoCalculado='Cancelada' THEN 1 ELSE 0 END AS CitasCanceladas,
   CASE WHEN c.ResultadoCalculado='PendienteResultado' THEN 1 ELSE 0 END AS CitasVencidasSinResultado,
   CASE WHEN c.estado_servicio='Realizado' AND c.ResultadoCalculado='Asistio'
      AND c.fecha_inicio IS NOT NULL AND c.fecha_fin IS NOT NULL
      THEN DATEDIFF(MINUTE,c.fecha_inicio,c.fecha_fin) END AS TiempoEnSillonDentalMin,
   CASE WHEN c.fecha_inicio IS NOT NULL THEN 1 ELSE 0 END AS AtencionesIniciadas,
   CASE WHEN c.estado_servicio='Realizado' AND c.fecha_fin IS NOT NULL THEN 1 ELSE 0 END AS AtencionesFinalizadas,
   CASE WHEN c.estado_servicio='Realizado' AND c.fecha_fin IS NOT NULL
     AND c.tiene_diagnostico=1 AND c.tiene_procedimiento=1 AND c.tiene_indicaciones=1 THEN 1 ELSE 0 END AS AtencionesFinalizadasConformes,
   CASE WHEN c.ResultadoCalculado='Asistio' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS EventoCustomerDerivado
  INTO #Fuente
  FROM #Citas AS c
  LEFT JOIN dbo.Dim_Tiempo AS dt ON dt.id_fecha=CAST(c.fecha_hora_turno AS DATE)
  LEFT JOIN dbo.Dim_Tiempo AS di ON di.id_fecha=CAST(c.fecha_inicio AS DATE)
  LEFT JOIN dbo.Dim_Hora AS dh ON dh.id_hora=DATEPART(HOUR,c.fecha_hora_turno)*100+DATEPART(MINUTE,c.fecha_hora_turno)
  LEFT JOIN dbo.Dim_Sede AS ds ON ds.id_sede=c.id_sede
  LEFT JOIN dbo.Dim_Servicio AS dsv ON dsv.id_servicio=c.id_servicio
  LEFT JOIN dbo.Dim_Profesional AS dp ON dp.id_profesional=c.id_profesional
  LEFT JOIN dbo.Dim_EstadoAtencion AS de ON de.EstadoFinal=c.estado_servicio AND de.Asistencia=c.asistencia
  LEFT JOIN dbo.Dim_Persona AS dper ON dper.id_persona=c.id_persona
  WHERE c.MotivoRechazo IS NULL;

  UPDATE f SET
   id_atencion_origen=s.id_atencion, id_persona_origen=s.id_persona,
   KeyTiempoTurno=s.KeyTiempoTurno, KeyTiempoInicio=s.KeyTiempoInicio, KeyHora=s.KeyHora,
   KeySede=s.KeySede,KeyServicio=s.KeyServicio,KeyProfesional=s.KeyProfesional,
   KeyEstadoAtencion=s.KeyEstadoAtencion,KeyPersona=s.KeyPersona,
   FechaHoraTurno=s.FechaHoraTurno,FechaEventoCustomer=s.FechaEventoCustomer,
   ResultadoCita=s.ResultadoCita,CitasProgramadas=s.CitasProgramadas,
   CitasEvaluables=s.CitasEvaluables,AtencionesRealizadas=s.AtencionesRealizadas,
   CitasConInasistencia=s.CitasConInasistencia,CitasCanceladas=s.CitasCanceladas,
   CitasVencidasSinResultado=s.CitasVencidasSinResultado,
   TiempoEnSillonDentalMin=s.TiempoEnSillonDentalMin,AtencionesIniciadas=s.AtencionesIniciadas,
   AtencionesFinalizadas=s.AtencionesFinalizadas,
   AtencionesFinalizadasConformes=s.AtencionesFinalizadasConformes,
   EventoCustomerDerivado=s.EventoCustomerDerivado,
   BatchId=@BatchId,FechaModificacion=SYSDATETIME(),UsuarioCarga=SYSTEM_USER
  FROM dbo.Fact_AtencionCustomer AS f JOIN #Fuente AS s ON s.id_reserva=f.id_reserva_origen
  WHERE EXISTS (
   SELECT f.id_atencion_origen,f.id_persona_origen,f.KeyTiempoTurno,f.KeyTiempoInicio,f.KeyHora,
    f.KeySede,f.KeyServicio,f.KeyProfesional,f.KeyEstadoAtencion,f.KeyPersona,
    f.FechaHoraTurno,f.FechaEventoCustomer,f.ResultadoCita,f.CitasEvaluables,
    f.AtencionesRealizadas,f.CitasConInasistencia,f.CitasCanceladas,f.CitasVencidasSinResultado,
    f.TiempoEnSillonDentalMin,f.AtencionesIniciadas,f.AtencionesFinalizadas,
    f.AtencionesFinalizadasConformes,f.EventoCustomerDerivado
   EXCEPT
   SELECT s.id_atencion,s.id_persona,s.KeyTiempoTurno,s.KeyTiempoInicio,s.KeyHora,
    s.KeySede,s.KeyServicio,s.KeyProfesional,s.KeyEstadoAtencion,s.KeyPersona,
    s.FechaHoraTurno,s.FechaEventoCustomer,s.ResultadoCita,s.CitasEvaluables,
    s.AtencionesRealizadas,s.CitasConInasistencia,s.CitasCanceladas,s.CitasVencidasSinResultado,
    s.TiempoEnSillonDentalMin,s.AtencionesIniciadas,s.AtencionesFinalizadas,
    s.AtencionesFinalizadasConformes,s.EventoCustomerDerivado
  );
  DECLARE @ValidosActualizados INT=@@ROWCOUNT;
  SET @Actualizados=@ValidosActualizados+@InvalidosActualizados;

  INSERT dbo.Fact_AtencionCustomer(
   id_reserva_origen,id_atencion_origen,id_persona_origen,KeyTiempoTurno,KeyTiempoInicio,KeyHora,
   KeySede,KeyServicio,KeyProfesional,KeyEstadoAtencion,KeyPersona,FechaHoraTurno,FechaEventoCustomer,
   ResultadoCita,CitasProgramadas,CitasEvaluables,AtencionesRealizadas,CitasConInasistencia,
   CitasCanceladas,CitasVencidasSinResultado,TiempoEnSillonDentalMin,AtencionesIniciadas,
   AtencionesFinalizadas,AtencionesFinalizadasConformes,EventoCustomerDerivado,BatchId)
  SELECT s.id_reserva,s.id_atencion,s.id_persona,s.KeyTiempoTurno,s.KeyTiempoInicio,s.KeyHora,
   s.KeySede,s.KeyServicio,s.KeyProfesional,s.KeyEstadoAtencion,s.KeyPersona,s.FechaHoraTurno,s.FechaEventoCustomer,
   s.ResultadoCita,s.CitasProgramadas,s.CitasEvaluables,s.AtencionesRealizadas,s.CitasConInasistencia,
   s.CitasCanceladas,s.CitasVencidasSinResultado,s.TiempoEnSillonDentalMin,s.AtencionesIniciadas,
   s.AtencionesFinalizadas,s.AtencionesFinalizadasConformes,s.EventoCustomerDerivado,@BatchId
  FROM #Fuente AS s WHERE NOT EXISTS(
   SELECT 1 FROM dbo.Fact_AtencionCustomer AS f WITH(UPDLOCK,HOLDLOCK) WHERE f.id_reserva_origen=s.id_reserva);
  SET @Insertados=@@ROWCOUNT;
  SELECT @SinCambio=COUNT(*) FROM #Fuente AS s JOIN dbo.Fact_AtencionCustomer AS f ON f.id_reserva_origen=s.id_reserva;
  SET @SinCambio=@SinCambio-@Insertados-@ValidosActualizados;
  SELECT @Pendientes=COUNT(*) FROM #Fuente WHERE ResultadoCita='PendienteResultado';
  INSERT dbo.Log_Ejecucion_ETL(Procedimiento,BatchId,TipoEvento,Mensaje)
   VALUES('dbo.usp_Cargar_Fact_AtencionCustomer',@BatchId,'EXITO',
    CONCAT('Insertados=',@Insertados,'; Actualizados=',@Actualizados,'; SinCambio=',@SinCambio,
           '; Rechazados=',@Rechazados,'; Pendientes=',@Pendientes));
  COMMIT TRANSACTION;
  RETURN 0;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
  DECLARE @Error VARCHAR(2048)=ERROR_MESSAGE();
  INSERT dbo.Log_Ejecucion_ETL(Procedimiento,BatchId,TipoEvento,Mensaje,LineaError)
   VALUES('dbo.usp_Cargar_Fact_AtencionCustomer',COALESCE(@BatchId,'SIN_BATCH'),'ERROR',@Error,ERROR_LINE());
  THROW;
 END CATCH
END;
GO
