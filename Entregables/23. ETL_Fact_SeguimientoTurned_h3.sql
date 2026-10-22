-- NexoSalud H3 / Alexis Vigo. Extension TURNED: una fila por id_seguimiento.
-- Se ejecuta en el mart despues de 22.Staging y 23.ETL CUSTOMER.
SET NOCOUNT ON;
IF OBJECT_ID('staging.stg_SeguimientosTurned','V') IS NULL THROW 51110, 'Falta staging TURNED.', 1;
IF OBJECT_ID('dbo.Fact_AtencionCustomer','U') IS NULL THROW 51111, 'Falta hecho CUSTOMER H3.', 1;
IF OBJECT_ID('dbo.Log_Ejecucion_ETL','U') IS NULL THROW 51112, 'Falta bitacora ETL.', 1;
IF OBJECT_ID('dbo.Dim_Persona','U') IS NULL THROW 51113, 'Falta Dim_Persona.', 1;
IF NOT EXISTS(SELECT 1 FROM dbo.Dim_Tiempo WHERE KeyTiempo=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Sede WHERE KeySede=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Servicio WHERE KeyServicio=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Profesional WHERE KeyProfesional=0)
 OR NOT EXISTS(SELECT 1 FROM dbo.Dim_Persona WHERE KeyPersona=0)
 THROW 51114, 'Dimension TURNED sin miembro desconocido Key=0.', 1;
GO

IF OBJECT_ID('dbo.Rechazos_ETL_Turned','U') IS NULL
 CREATE TABLE dbo.Rechazos_ETL_Turned (
  RechazoId BIGINT IDENTITY(1,1) PRIMARY KEY,
  EntidadOrigenId INT NOT NULL,
  MotivoRechazo VARCHAR(100) NOT NULL,
  BatchId VARCHAR(50) NOT NULL,
  FechaRechazo DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
  CONSTRAINT UQ_RechazosTurned_Lote UNIQUE(EntidadOrigenId,BatchId)
 );
GO

IF OBJECT_ID('dbo.Fact_SeguimientoTurned','U') IS NULL
 CREATE TABLE dbo.Fact_SeguimientoTurned (
  KeyFactTurned BIGINT IDENTITY(1,1) PRIMARY KEY,
  id_seguimiento_origen INT NOT NULL,
  id_atencion_origen INT NOT NULL,
  id_persona_origen INT NOT NULL,
  KeyTiempoSeguimiento INT NOT NULL,
  KeySede INT NOT NULL,
  KeyServicio INT NOT NULL,
  KeyProfesional INT NOT NULL,
  KeyPersona INT NOT NULL,
  FechaHoraSeguimiento DATETIME2(7) NOT NULL,
  Canal VARCHAR(50) NULL,
  TipoSeguimiento VARCHAR(50) NOT NULL,
  Satisfaccion TINYINT NULL,
  Incidencia INT NOT NULL,
  SeguimientosRegistrados INT NOT NULL,
  Cohorte90DiasEvaluable INT NOT NULL,
  Retorno90Dias INT NOT NULL,
  DiasHastaRetorno INT NULL,
  BatchId VARCHAR(50) NOT NULL,
  FechaCarga DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
  FechaModificacion DATETIME2(7) NULL,
  UsuarioCarga VARCHAR(50) NOT NULL DEFAULT SYSTEM_USER,
  CONSTRAINT UQ_FactTurned_Origen UNIQUE(id_seguimiento_origen),
  CONSTRAINT FK_Turned_Tiempo FOREIGN KEY(KeyTiempoSeguimiento) REFERENCES dbo.Dim_Tiempo(KeyTiempo),
  CONSTRAINT FK_Turned_Sede FOREIGN KEY(KeySede) REFERENCES dbo.Dim_Sede(KeySede),
  CONSTRAINT FK_Turned_Servicio FOREIGN KEY(KeyServicio) REFERENCES dbo.Dim_Servicio(KeyServicio),
  CONSTRAINT FK_Turned_Profesional FOREIGN KEY(KeyProfesional) REFERENCES dbo.Dim_Profesional(KeyProfesional),
  CONSTRAINT FK_Turned_Persona FOREIGN KEY(KeyPersona) REFERENCES dbo.Dim_Persona(KeyPersona),
  CONSTRAINT CK_Turned_Flags CHECK (
   SeguimientosRegistrados BETWEEN 0 AND 1 AND Cohorte90DiasEvaluable BETWEEN 0 AND 1
   AND Retorno90Dias BETWEEN 0 AND Cohorte90DiasEvaluable AND Incidencia BETWEEN 0 AND 1
   AND (DiasHastaRetorno IS NULL OR DiasHastaRetorno>=0))
 );
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID('dbo.Fact_SeguimientoTurned') AND name='IX_Turned_FechaPersona')
 CREATE INDEX IX_Turned_FechaPersona ON dbo.Fact_SeguimientoTurned(KeyTiempoSeguimiento,KeyPersona)
 INCLUDE(Cohorte90DiasEvaluable,Retorno90Dias);
GO

CREATE OR ALTER PROCEDURE dbo.usp_Cargar_Fact_SeguimientoTurned
 @FechaCorte DATE, @BatchId VARCHAR(50),
 @Insertados INT=0 OUTPUT, @Actualizados INT=0 OUTPUT, @SinCambio INT=0 OUTPUT,
 @Rechazados INT=0 OUTPUT, @Pendientes INT=0 OUTPUT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @Insertados=0; SET @Actualizados=0; SET @SinCambio=0; SET @Rechazados=0; SET @Pendientes=0;
 IF @FechaCorte IS NULL OR @FechaCorte='99991231' OR NULLIF(LTRIM(RTRIM(@BatchId)),'') IS NULL
  THROW 51120, 'FechaCorte valida y BatchId no vacio son obligatorios.', 1;
 IF OBJECT_ID('staging.stg_SeguimientosTurned','V') IS NULL THROW 51121, 'Falta staging TURNED.', 1;
 DECLARE @Limite DATETIME2(7)=DATEADD(DAY,1,CAST(@FechaCorte AS DATETIME2(7)));
 DECLARE @Lock INT;
 BEGIN TRY
  BEGIN TRANSACTION;
  EXEC @Lock=sys.sp_getapplock @Resource='ETL_Lock_Fact_SeguimientoTurned', @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=30000;
  IF @Lock<0 THROW 51122, 'No se obtuvo bloqueo ETL TURNED.', 1;
  INSERT dbo.Log_Ejecucion_ETL(Procedimiento,BatchId,TipoEvento,Mensaje)
   VALUES('dbo.usp_Cargar_Fact_SeguimientoTurned',@BatchId,'INICIO','Inicio de carga TURNED');
  SELECT s.*,
   CASE WHEN s.id_persona_atencion IS NULL THEN 'AtencionInexistente'
    WHEN s.id_persona_atencion<>s.id_persona THEN 'PersonaSeguimientoInconsistente'
    WHEN s.asistencia<>'Asistió' OR s.estado_servicio<>'Realizado' OR s.fecha_inicio_atencion IS NULL
      THEN 'AtencionNoFinalizada'
    WHEN s.fecha_hora<s.fecha_inicio_atencion THEN 'SeguimientoAnteriorAAtencion'
    ELSE NULL END AS MotivoRechazo
  INTO #Seguimientos
  FROM staging.stg_SeguimientosTurned AS s WHERE s.fecha_hora<@Limite;
  DELETE dbo.Rechazos_ETL_Turned WHERE BatchId=@BatchId;
  INSERT dbo.Rechazos_ETL_Turned(EntidadOrigenId,MotivoRechazo,BatchId)
   SELECT id_seguimiento,MotivoRechazo,@BatchId FROM #Seguimientos WHERE MotivoRechazo IS NOT NULL;
  SET @Rechazados=@@ROWCOUNT;
  UPDATE f SET SeguimientosRegistrados=0,Incidencia=0,Cohorte90DiasEvaluable=0,Retorno90Dias=0,
   DiasHastaRetorno=NULL,BatchId=@BatchId,FechaModificacion=SYSDATETIME()
  FROM dbo.Fact_SeguimientoTurned AS f
  JOIN #Seguimientos AS s ON s.id_seguimiento=f.id_seguimiento_origen
  WHERE s.MotivoRechazo IS NOT NULL AND f.SeguimientosRegistrados<>0;
  DECLARE @InvalidosActualizados INT=@@ROWCOUNT;
  IF EXISTS(SELECT id_fecha FROM dbo.Dim_Tiempo WHERE id_fecha IS NOT NULL GROUP BY id_fecha HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_sede FROM dbo.Dim_Sede WHERE id_sede IS NOT NULL GROUP BY id_sede HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_servicio FROM dbo.Dim_Servicio WHERE id_servicio IS NOT NULL GROUP BY id_servicio HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_profesional FROM dbo.Dim_Profesional WHERE id_profesional IS NOT NULL GROUP BY id_profesional HAVING COUNT(*)>1)
   OR EXISTS(SELECT id_persona FROM dbo.Dim_Persona WHERE id_persona IS NOT NULL GROUP BY id_persona HAVING COUNT(*)>1)
   THROW 51123, 'Claves naturales duplicadas en dimensiones TURNED.', 1;
  SELECT s.id_seguimiento,s.id_atencion,s.id_persona,
   COALESCE(dt.KeyTiempo,0) AS KeyTiempoSeguimiento,
   COALESCE(ds.KeySede,0) AS KeySede,COALESCE(dsv.KeyServicio,0) AS KeyServicio,
   COALESCE(dp.KeyProfesional,0) AS KeyProfesional,COALESCE(dper.KeyPersona,0) AS KeyPersona,
   s.fecha_hora AS FechaHoraSeguimiento,s.canal AS Canal,s.tipo AS TipoSeguimiento,
   s.satisfaccion AS Satisfaccion,CAST(s.incidencia AS INT) AS Incidencia,
   CAST(1 AS INT) AS SeguimientosRegistrados,
   CASE WHEN DATEADD(DAY,90,s.fecha_hora)<@Limite THEN 1 ELSE 0 END AS Cohorte90DiasEvaluable,
   CASE WHEN DATEADD(DAY,90,s.fecha_hora)<@Limite
     AND s.fecha_inicio_retorno>=s.fecha_hora AND s.fecha_inicio_retorno<DATEADD(DAY,90,s.fecha_hora)
     THEN 1 ELSE 0 END AS Retorno90Dias,
   CASE WHEN s.fecha_inicio_retorno<@Limite THEN DATEDIFF(DAY,s.fecha_hora,s.fecha_inicio_retorno) END AS DiasHastaRetorno
  INTO #Fuente
  FROM #Seguimientos AS s
  LEFT JOIN dbo.Dim_Tiempo AS dt ON dt.id_fecha=CAST(s.fecha_hora AS DATE)
  LEFT JOIN dbo.Dim_Sede AS ds ON ds.id_sede=s.id_sede
  LEFT JOIN dbo.Dim_Servicio AS dsv ON dsv.id_servicio=s.id_servicio
  LEFT JOIN dbo.Dim_Profesional AS dp ON dp.id_profesional=s.id_profesional
  LEFT JOIN dbo.Dim_Persona AS dper ON dper.id_persona=s.id_persona
  WHERE s.MotivoRechazo IS NULL;
  UPDATE f SET
   id_atencion_origen=s.id_atencion,id_persona_origen=s.id_persona,
   KeyTiempoSeguimiento=s.KeyTiempoSeguimiento,KeySede=s.KeySede,KeyServicio=s.KeyServicio,
   KeyProfesional=s.KeyProfesional,KeyPersona=s.KeyPersona,
   FechaHoraSeguimiento=s.FechaHoraSeguimiento,Canal=s.Canal,TipoSeguimiento=s.TipoSeguimiento,
   Satisfaccion=s.Satisfaccion,Incidencia=s.Incidencia,SeguimientosRegistrados=s.SeguimientosRegistrados,
   Cohorte90DiasEvaluable=s.Cohorte90DiasEvaluable,Retorno90Dias=s.Retorno90Dias,
   DiasHastaRetorno=s.DiasHastaRetorno,BatchId=@BatchId,
   FechaModificacion=SYSDATETIME(),UsuarioCarga=SYSTEM_USER
  FROM dbo.Fact_SeguimientoTurned AS f JOIN #Fuente AS s ON s.id_seguimiento=f.id_seguimiento_origen
  WHERE EXISTS(
   SELECT f.id_atencion_origen,f.id_persona_origen,f.KeyTiempoSeguimiento,f.KeySede,f.KeyServicio,
    f.KeyProfesional,f.KeyPersona,f.FechaHoraSeguimiento,f.Canal,f.TipoSeguimiento,
    f.Satisfaccion,f.Incidencia,f.SeguimientosRegistrados,f.Cohorte90DiasEvaluable,f.Retorno90Dias,f.DiasHastaRetorno
   EXCEPT
   SELECT s.id_atencion,s.id_persona,s.KeyTiempoSeguimiento,s.KeySede,s.KeyServicio,
    s.KeyProfesional,s.KeyPersona,s.FechaHoraSeguimiento,s.Canal,s.TipoSeguimiento,
    s.Satisfaccion,s.Incidencia,s.SeguimientosRegistrados,s.Cohorte90DiasEvaluable,s.Retorno90Dias,s.DiasHastaRetorno);
  DECLARE @ValidosActualizados INT=@@ROWCOUNT;
  SET @Actualizados=@ValidosActualizados+@InvalidosActualizados;
  INSERT dbo.Fact_SeguimientoTurned(
   id_seguimiento_origen,id_atencion_origen,id_persona_origen,KeyTiempoSeguimiento,KeySede,
   KeyServicio,KeyProfesional,KeyPersona,FechaHoraSeguimiento,Canal,TipoSeguimiento,
   Satisfaccion,Incidencia,SeguimientosRegistrados,Cohorte90DiasEvaluable,Retorno90Dias,
   DiasHastaRetorno,BatchId)
  SELECT s.id_seguimiento,s.id_atencion,s.id_persona,s.KeyTiempoSeguimiento,s.KeySede,
   s.KeyServicio,s.KeyProfesional,s.KeyPersona,s.FechaHoraSeguimiento,s.Canal,s.TipoSeguimiento,
   s.Satisfaccion,s.Incidencia,s.SeguimientosRegistrados,s.Cohorte90DiasEvaluable,s.Retorno90Dias,
   s.DiasHastaRetorno,@BatchId
  FROM #Fuente AS s WHERE NOT EXISTS(SELECT 1 FROM dbo.Fact_SeguimientoTurned AS f WITH(UPDLOCK,HOLDLOCK)
   WHERE f.id_seguimiento_origen=s.id_seguimiento);
  SET @Insertados=@@ROWCOUNT;
  SELECT @SinCambio=COUNT(*) FROM #Fuente;
  SET @SinCambio=@SinCambio-@Insertados-@ValidosActualizados;
  SELECT @Pendientes=COUNT(*) FROM #Fuente WHERE Cohorte90DiasEvaluable=0;
  INSERT dbo.Log_Ejecucion_ETL(Procedimiento,BatchId,TipoEvento,Mensaje)
   VALUES('dbo.usp_Cargar_Fact_SeguimientoTurned',@BatchId,'EXITO',
    CONCAT('Insertados=',@Insertados,'; Actualizados=',@Actualizados,'; SinCambio=',@SinCambio,
           '; Rechazados=',@Rechazados,'; CohortesInmaduras=',@Pendientes));
  COMMIT TRANSACTION;
  RETURN 0;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
  DECLARE @Error VARCHAR(2048)=ERROR_MESSAGE();
  INSERT dbo.Log_Ejecucion_ETL(Procedimiento,BatchId,TipoEvento,Mensaje,LineaError)
   VALUES('dbo.usp_Cargar_Fact_SeguimientoTurned',COALESCE(@BatchId,'SIN_BATCH'),'ERROR',@Error,ERROR_LINE());
  THROW;
 END CATCH
END;
GO
