-- NexoSalud H3: staging de Alexis. Ejecutar con sqlcmd -v OLTP_DB=NexoSaludDB
-- La variable OLTP_DB permite pruebas contra una base aislada sin tocar producción.
-- Se ejecuta conectado al mart. No modifica el OLTP.
IF DB_NAME() IS NULL THROW 51001, 'Seleccione la base mart con sqlcmd -d.', 1;
GO
IF SCHEMA_ID('staging') IS NULL EXEC('CREATE SCHEMA staging');
GO

CREATE OR ALTER VIEW staging.stg_CitasCustomer
AS
SELECT
    r.id_reserva,
    r.id_persona,
    r.id_solicitud,
    r.id_opcion,
    o.id_solicitud AS id_solicitud_opcion,
    sol.id_persona AS id_persona_solicitud,
    r.estado AS estado_reserva,
    r.confirmacion_explicita,
    r.fecha_reserva,
    o.id_disponibilidad,
    d.fecha AS fecha_turno,
    d.hora_inicio,
    d.hora_fin,
    CASE WHEN d.fecha IS NOT NULL AND d.hora_inicio IS NOT NULL
         THEN DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00:00' AS time), d.hora_inicio), CAST(d.fecha AS datetime2(7)))
         ELSE NULL END AS fecha_hora_turno,
    COALESCE(a.id_sede, d.id_sede) AS id_sede,
    COALESCE(a.id_servicio, sol.id_servicio) AS id_servicio,
    COALESCE(a.id_profesional, d.id_profesional) AS id_profesional,
    ac.total_atenciones,
    a.id_atencion,
    a.id_persona AS id_persona_atencion,
    a.fecha_atencion,
    a.fecha_inicio,
    a.fecha_fin,
    a.asistencia,
    a.estado_servicio,
    CASE WHEN NULLIF(LTRIM(RTRIM(a.diagnostico_basico)), '') IS NOT NULL
              AND LEN(LTRIM(RTRIM(a.diagnostico_basico))) >= 5 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS tiene_diagnostico,
    CASE WHEN NULLIF(LTRIM(RTRIM(a.procedimiento_realizado)), '') IS NOT NULL
              AND LEN(LTRIM(RTRIM(a.procedimiento_realizado))) >= 5 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS tiene_procedimiento,
    CASE WHEN NULLIF(LTRIM(RTRIM(a.indicaciones_finales)), '') IS NOT NULL
              AND LEN(LTRIM(RTRIM(a.indicaciones_finales))) >= 5 THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS tiene_indicaciones
FROM [$(OLTP_DB)].dbo.Reservas AS r
LEFT JOIN [$(OLTP_DB)].dbo.Opciones AS o ON o.id_opcion = r.id_opcion
LEFT JOIN [$(OLTP_DB)].dbo.Disponibilidad AS d ON d.id_disponibilidad = o.id_disponibilidad
LEFT JOIN [$(OLTP_DB)].dbo.Solicitudes AS sol ON sol.id_solicitud = r.id_solicitud
OUTER APPLY (
    SELECT COUNT(*) AS total_atenciones
    FROM [$(OLTP_DB)].dbo.Atenciones AS ax
    WHERE ax.id_reserva = r.id_reserva
) AS ac
LEFT JOIN [$(OLTP_DB)].dbo.Atenciones AS a
    ON a.id_reserva = r.id_reserva AND ac.total_atenciones = 1;
GO

CREATE OR ALTER VIEW staging.stg_SeguimientosTurned
AS
SELECT
    s.id_seguimiento,
    s.id_persona,
    s.id_atencion,
    s.fecha_hora,
    s.canal,
    s.tipo,
    s.satisfaccion,
    s.incidencia,
    a.id_persona AS id_persona_atencion,
    a.id_reserva,
    a.id_sede,
    a.id_servicio,
    a.id_profesional,
    a.asistencia,
    a.estado_servicio,
    a.fecha_inicio AS fecha_inicio_atencion,
    retorno.id_atencion AS id_atencion_retorno,
    retorno.fecha_inicio AS fecha_inicio_retorno
FROM [$(OLTP_DB)].dbo.Seguimientos AS s
LEFT JOIN [$(OLTP_DB)].dbo.Atenciones AS a ON a.id_atencion = s.id_atencion
OUTER APPLY (
    SELECT TOP (1) ax.id_atencion, ax.fecha_inicio
    FROM [$(OLTP_DB)].dbo.Atenciones AS ax
    WHERE ax.id_persona = s.id_persona
      AND ax.id_atencion <> s.id_atencion
      AND ax.fecha_inicio > s.fecha_hora
      AND ax.asistencia = 'Asistió'
    ORDER BY ax.fecha_inicio, ax.id_atencion
) AS retorno;
GO
