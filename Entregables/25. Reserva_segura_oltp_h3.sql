-- NexoSalud H3 / Alexis Vigo. Ejecutar conectado al OLTP, no al mart.
-- El backend debe usar este procedimiento (o una transaccion equivalente) para que
-- la proteccion concurrente tenga efecto. No modifica reservas existentes.
CREATE OR ALTER PROCEDURE dbo.usp_ReservarTurnoSinColision
 @IdPersona INT, @IdSolicitud INT, @IdOpcion INT, @IdReserva INT OUTPUT
AS
BEGIN
 SET NOCOUNT ON; SET XACT_ABORT ON;
 SET @IdReserva=NULL;
 IF @IdPersona<=0 OR @IdSolicitud<=0 OR @IdOpcion<=0
  THROW 51300, 'Persona, solicitud y opcion validas son obligatorias.', 1;
 DECLARE @IdDisponibilidad INT,@EstadoDisponibilidad VARCHAR(20),@Bloqueo INT,@Recurso VARCHAR(100),
  @HoraInicio TIME,@HoraFin TIME;
 BEGIN TRY
  BEGIN TRANSACTION;
  SELECT @IdDisponibilidad=o.id_disponibilidad
  FROM dbo.Opciones AS o WITH(UPDLOCK,HOLDLOCK)
  WHERE o.id_opcion=@IdOpcion AND o.id_solicitud=@IdSolicitud;
  IF @IdDisponibilidad IS NULL THROW 51301, 'Opcion inexistente.', 1;
  IF NOT EXISTS(SELECT 1 FROM dbo.Solicitudes
    WHERE id_solicitud=@IdSolicitud AND id_persona=@IdPersona)
   THROW 51306, 'Solicitud no pertenece a la persona.', 1;
  SET @Recurso=CONCAT('ReservaDisponibilidad:',@IdDisponibilidad);
  EXEC @Bloqueo=sys.sp_getapplock
   @Resource=@Recurso,
   @LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=15000;
  IF @Bloqueo<0 THROW 51302, 'No se obtuvo bloqueo del turno.', 1;
  SELECT @EstadoDisponibilidad=d.estado,@HoraInicio=d.hora_inicio,@HoraFin=d.hora_fin
  FROM dbo.Disponibilidad AS d WITH(UPDLOCK,HOLDLOCK)
  WHERE d.id_disponibilidad=@IdDisponibilidad;
  IF @EstadoDisponibilidad IS NULL THROW 51303, 'Disponibilidad inexistente.', 1;
  IF @HoraFin<=@HoraInicio THROW 51307, 'Turno con intervalo invalido.', 1;
  IF UPPER(LTRIM(RTRIM(@EstadoDisponibilidad)))<>'DISPONIBLE'
   THROW 51304, 'Turno ocupado o no disponible.', 1;
  IF EXISTS(
   SELECT 1 FROM dbo.Reservas AS r WITH(UPDLOCK,HOLDLOCK)
   JOIN dbo.Opciones AS o ON o.id_opcion=r.id_opcion
   WHERE o.id_disponibilidad=@IdDisponibilidad
     AND UPPER(LTRIM(RTRIM(r.estado))) IN ('PENDIENTE','CONFIRMADA','CONFIRMADO'))
   THROW 51305, 'Ya existe una reserva activa para el turno.', 1;
  INSERT dbo.Reservas(id_persona,id_solicitud,id_opcion,fecha_reserva,estado,confirmacion_explicita)
   VALUES(@IdPersona,@IdSolicitud,@IdOpcion,SYSDATETIME(),'Pendiente',0);
  SET @IdReserva=CONVERT(INT,SCOPE_IDENTITY());
  UPDATE dbo.Disponibilidad SET estado='Ocupado' WHERE id_disponibilidad=@IdDisponibilidad;
  COMMIT TRANSACTION;
 END TRY
 BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
  THROW;
 END CATCH
END;
GO
