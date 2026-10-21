-- ====================================================================================================
-- SCRIPT DE PREPARACIÓN DE ENTORNO PARA PRUEBA DE CONCURRENCIA LEAD (H3)
-- Bases: Test_NexoSalud_OLTP_Lead_Conc y Test_NexoSalud_Mart_Lead_Conc
-- ====================================================================================================

-- 1. Verificación previa de no existencia
IF EXISTS (SELECT 1 FROM sys.databases WHERE name IN ('Test_NexoSalud_OLTP_Lead_Conc', 'Test_NexoSalud_Mart_Lead_Conc'))
BEGIN
    RAISERROR('Error: Las bases temporales de concurrencia ya existen. Limpie antes de continuar.', 16, 1);
    RETURN;
END;
GO

-- 2. Creación de Bases Aisladas
CREATE DATABASE Test_NexoSalud_OLTP_Lead_Conc;
CREATE DATABASE Test_NexoSalud_Mart_Lead_Conc;
GO

PRINT '>> Bases de concurrencia creadas exitosamente.';
GO

-- ====================================================================================================
-- 3. MODELO TRANSACCIONAL OLTP Y DATOS SINTÉTICOS
-- ====================================================================================================
USE Test_NexoSalud_OLTP_Lead_Conc;
GO

CREATE TABLE dbo.Personas (
    id_persona INT PRIMARY KEY,
    nombres VARCHAR(100),
    apellidos VARCHAR(100),
    dni VARCHAR(20),
    email VARCHAR(100),
    numero VARCHAR(50),
    fecha_registro DATETIME2 NOT NULL
);

CREATE TABLE dbo.Solicitudes (
    id_solicitud INT PRIMARY KEY,
    id_persona INT NOT NULL,
    id_servicio INT NULL,
    estado VARCHAR(50) NOT NULL,
    tipo_consulta VARCHAR(50) NULL,
    prioridad VARCHAR(50) NULL,
    motivo VARCHAR(200) NULL,
    fecha_solicitud DATETIME2 NOT NULL,
    fecha_primera_respuesta DATETIME2 NULL,
    fecha_cierre DATETIME2 NULL
);

CREATE TABLE dbo.Disponibilidad (
    id_disponibilidad INT PRIMARY KEY,
    id_sede INT NULL,
    id_profesional INT NULL
);

CREATE TABLE dbo.Opciones (
    id_opcion INT PRIMARY KEY,
    id_solicitud INT NOT NULL,
    id_disponibilidad INT NULL,
    precio_ofrecido DECIMAL(10,2) NULL,
    fecha_ofrecida DATETIME2 NOT NULL,
    seleccionada BIT NOT NULL
);

CREATE TABLE dbo.Reservas (
    id_reserva INT PRIMARY KEY,
    id_solicitud INT NOT NULL,
    fecha_reserva DATETIME2 NOT NULL,
    estado VARCHAR(50) NOT NULL,
    confirmacion_explicita BIT NOT NULL,
    fecha_confirmacion DATETIME2 NULL
);

CREATE TABLE dbo.Interacciones (
    id_interaccion INT PRIMARY KEY,
    id_persona INT NOT NULL,
    id_canal INT NULL,
    id_fuente INT NULL,
    id_usuario INT NULL,
    fecha_hora DATETIME2 NOT NULL,
    es_respuesta_util BIT NOT NULL,
    resultado VARCHAR(100) NULL,
    tipo VARCHAR(50) NULL
);
GO

-- 3 personas y 3 solicitudes para contención concurrente
INSERT INTO dbo.Personas VALUES
(101, 'Mateo', 'Bravo', '71234567', 'mateo.b@email.com', '981234567', '2026-09-01 10:00:00'),
(102, 'Carla', 'Salas', '72345678', 'carla.s@email.com', '972345678', '2026-09-01 11:00:00'),
(103, 'Lucia', 'Ramos', '73456789', 'lucia.r@email.com', '963456789', '2026-09-01 12:00:00');

INSERT INTO dbo.Solicitudes VALUES
(301, 101, 1, 'Confirmada', 'Ortodoncia', 'Media', 'Consulta M', '2026-09-05 10:00:00', '2026-09-05 10:05:00', NULL),
(302, 102, 2, 'Confirmada', 'Endodoncia', 'Media', 'Consulta C', '2026-09-05 11:00:00', '2026-09-05 11:05:00', NULL),
(303, 103, 3, 'Perdida',    'Periodoncia', 'Alta', 'Consulta L', '2026-09-05 12:00:00', '2026-09-05 12:05:00', '2026-09-06 18:00:00');

INSERT INTO dbo.Disponibilidad VALUES (1, 1, 1), (2, 2, 2), (3, 3, 3);

INSERT INTO dbo.Opciones VALUES
(1, 301, 1, 250.00, '2026-09-05 10:02:00', 1),
(2, 302, 2, 350.00, '2026-09-05 11:02:00', 1),
(3, 303, 3, 150.00, '2026-09-05 12:02:00', 0);

INSERT INTO dbo.Reservas VALUES
(1, 301, '2026-09-07 10:00:00', 'Confirmada', 1, '2026-09-07 11:00:00'),
(2, 302, '2026-09-08 11:00:00', 'Confirmada', 1, '2026-09-08 12:00:00');

INSERT INTO dbo.Interacciones VALUES
(1, 101, 1, 1, 1, '2026-09-05 10:05:00', 1, 'Atendido', 'Mensaje'),
(2, 102, 1, 1, 1, '2026-09-05 11:05:00', 1, 'Atendido', 'Mensaje'),
(3, 103, 1, 1, 1, '2026-09-05 12:05:00', 1, 'Atendido', 'Mensaje');
GO

-- ====================================================================================================
-- 4. CONFIGURACIÓN DEL DATA MART Y VISTAS REALES DE STAGING
-- ====================================================================================================
USE Test_NexoSalud_Mart_Lead_Conc;
GO

CREATE SCHEMA staging;
GO

CREATE OR ALTER VIEW staging.stg_Solicitudes
AS
SELECT 
    s.id_solicitud,
    s.id_persona,
    s.id_servicio AS id_servicio_solicitado,
    s.fecha_solicitud,
    CAST(CONVERT(VARCHAR(8), s.fecha_solicitud, 112) AS INT) AS KeyTiempoSolicitud,
    CAST(REPLACE(SUBSTRING(CONVERT(VARCHAR(8), s.fecha_solicitud, 108), 1, 5), ':', '') AS INT) AS KeyHoraSolicitud,
    s.fecha_primera_respuesta,
    CASE WHEN s.fecha_primera_respuesta IS NOT NULL THEN 1 ELSE 0 END AS tiene_fecha_primera_respuesta,
    s.fecha_cierre,
    CASE WHEN s.fecha_cierre IS NOT NULL THEN 1 ELSE 0 END AS tiene_fecha_cierre,
    s.estado AS estado_original,
    st_norm.estado_solicitud_norm,
    s.tipo_consulta AS tipo_consulta_original,
    ISNULL(s.tipo_consulta, 'Desconocido') AS tipo_consulta_norm,
    ISNULL(s.prioridad, 'Media') AS prioridad_norm,
    CASE WHEN s.motivo IS NOT NULL AND LEN(LTRIM(RTRIM(s.motivo))) > 0 THEN 1 ELSE 0 END AS tiene_motivo_registrado,
    opc.primer_precio_ofrecido,
    opc.fecha_primer_precio_ofrecido,
    opc.id_primera_opcion,
    ISNULL(opc.cantidad_opciones_ofrecidas, 0) AS cantidad_opciones_ofrecidas,
    ISNULL(opc.cantidad_opciones_seleccionadas, 0) AS cantidad_opciones_seleccionadas,
    opc.precio_cotizado_seleccionado,
    CASE WHEN ISNULL(opc.cantidad_opciones_seleccionadas, 0) > 1 THEN 1 ELSE 0 END AS tiene_multiple_opcion_seleccionada,
    res.id_primera_reserva,
    res.primera_fecha_reserva,
    res.estado_primera_reserva,
    ISNULL(res.confirmacion_explicita_primera_reserva, 0) AS confirmacion_explicita_primera_reserva,
    res.fecha_confirmacion_primera_reserva,
    ISNULL(res.cantidad_reservas_asociadas, 0) AS cantidad_reservas_asociadas,
    ISNULL(res.tiene_alguna_reserva_confirmada, 0) AS tiene_alguna_reserva_confirmada,
    CASE WHEN res.id_primera_reserva IS NOT NULL THEN 1 ELSE 0 END AS tiene_reserva_registrada
FROM [Test_NexoSalud_OLTP_Lead_Conc].dbo.[Solicitudes] s
CROSS APPLY (
    SELECT 
        CASE 
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('abierta', 'pendiente', 'iniciada', 'en negociacion', 'en negociación') THEN 'Abierta'
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('reserva', 'reservada') THEN 'Reserva'
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('confirmada', 'cita confirmada') THEN 'Confirmada'
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('convertida', 'ganada', 'pagada') THEN 'Convertida'
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('abandonada') THEN 'Abandonada'
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('cancelada') THEN 'Cancelada'
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('descartada') THEN 'Descartada'
            WHEN LOWER(LTRIM(RTRIM(s.estado))) IN ('perdida', 'no asistio', 'no asistió') THEN 'Perdida'
            ELSE 'Desconocido'
        END AS estado_solicitud_norm
) st_norm
OUTER APPLY (
    SELECT 
        COUNT(*) AS cantidad_opciones_ofrecidas,
        SUM(CASE WHEN o.seleccionada = 1 THEN 1 ELSE 0 END) AS cantidad_opciones_seleccionadas,
        MIN(CASE WHEN o.seleccionada = 1 THEN o.precio_ofrecido END) AS precio_cotizado_seleccionado,
        MIN(o.precio_ofrecido) AS primer_precio_ofrecido,
        MIN(o.fecha_ofrecida) AS fecha_primer_precio_ofrecido,
        MIN(o.id_opcion) AS id_primera_opcion
    FROM [Test_NexoSalud_OLTP_Lead_Conc].dbo.[Opciones] o
    WHERE o.id_solicitud = s.id_solicitud
) opc
OUTER APPLY (
    SELECT 
        COUNT(*) AS cantidad_reservas_asociadas,
        MAX(CASE WHEN r.estado = 'Confirmada' OR r.confirmacion_explicita = 1 THEN 1 ELSE 0 END) AS tiene_alguna_reserva_confirmada,
        MIN(r.id_reserva) AS id_primera_reserva,
        MIN(r.fecha_reserva) AS primera_fecha_reserva,
        MIN(r.estado) AS estado_primera_reserva,
        MAX(CAST(r.confirmacion_explicita AS INT)) AS confirmacion_explicita_primera_reserva,
        MIN(r.fecha_confirmacion) AS fecha_confirmacion_primera_reserva
    FROM [Test_NexoSalud_OLTP_Lead_Conc].dbo.[Reservas] r
    WHERE r.id_solicitud = s.id_solicitud
) res;
GO

CREATE OR ALTER VIEW staging.stg_Interacciones
AS
SELECT 
    i.id_interaccion,
    i.id_persona,
    i.id_canal,
    i.id_fuente,
    i.id_usuario AS id_usuario_operador,
    i.fecha_hora AS fecha_hora_interaccion,
    CAST(CONVERT(VARCHAR(8), i.fecha_hora, 112) AS INT) AS KeyTiempoInteraccion,
    CAST(REPLACE(SUBSTRING(CONVERT(VARCHAR(8), i.fecha_hora, 108), 1, 5), ':', '') AS INT) AS KeyHoraInteraccion,
    CASE WHEN i.es_respuesta_util = 1 THEN 1 ELSE 0 END AS es_respuesta_util,
    i.resultado AS resultado_original,
    i.tipo AS tipo_interaccion_original
FROM [Test_NexoSalud_OLTP_Lead_Conc].dbo.[Interacciones] i;
GO

-- 5. Creación de Dimensiones
CREATE TABLE dbo.Dim_Tiempo (
    KeyTiempo   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_fecha    DATE NOT NULL
);

CREATE TABLE dbo.Dim_Sede (
    KeySede     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_sede     INT NULL,
    NombreSede  VARCHAR(100) NOT NULL
);

CREATE TABLE dbo.Dim_Servicio (
    KeyServicio    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_servicio    INT NULL,
    NombreServicio VARCHAR(100) NOT NULL
);

CREATE TABLE dbo.Dim_Profesional (
    KeyProfesional  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_profesional  INT NULL,
    NombreCompleto  VARCHAR(150) NOT NULL
);

CREATE TABLE dbo.Dim_Negociador (
    KeyNegociador   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_usuario      INT NULL,
    NombreCompleto  VARCHAR(150) NOT NULL
);

CREATE TABLE dbo.Dim_Persona (
    KeyPersona      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_persona      INT NULL,
    NombreCompleto  VARCHAR(150) NOT NULL
);

CREATE TABLE dbo.Config_CalendarioAtencion_ETL (
    IdIntervalo INT PRIMARY KEY,
    DiaSemana   INT NOT NULL,
    HoraInicio  TIME(0) NOT NULL,
    HoraFin     TIME(0) NOT NULL,
    EsLaborable BIT NOT NULL,
    Activo      BIT NOT NULL
);
GO

-- Inserción de Miembros 0 y registros de prueba
SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha) VALUES (0, '1900-01-01');
SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;

DECLARE @f DATE = '2026-08-01';
WHILE @f <= '2026-12-31'
BEGIN
    INSERT INTO dbo.Dim_Tiempo (id_fecha) VALUES (@f);
    SET @f = DATEADD(day, 1, @f);
END;

SET IDENTITY_INSERT dbo.Dim_Sede ON;
INSERT INTO dbo.Dim_Sede (KeySede, id_sede, NombreSede) VALUES (0, NULL, 'Sin Sede'), (1, 1, 'Sede Central');
SET IDENTITY_INSERT dbo.Dim_Sede OFF;

SET IDENTITY_INSERT dbo.Dim_Servicio ON;
INSERT INTO dbo.Dim_Servicio (KeyServicio, id_servicio, NombreServicio) VALUES 
(0, NULL, 'Desconocido'),
(1, 1, 'Ortodoncia Invisible'),
(2, 2, 'Endodoncia Rotatoria'),
(3, 3, 'Periodoncia Avanzada');
SET IDENTITY_INSERT dbo.Dim_Servicio OFF;

SET IDENTITY_INSERT dbo.Dim_Profesional ON;
INSERT INTO dbo.Dim_Profesional (KeyProfesional, id_profesional, NombreCompleto) VALUES (0, NULL, 'Sin Profesional');
SET IDENTITY_INSERT dbo.Dim_Profesional OFF;

SET IDENTITY_INSERT dbo.Dim_Negociador ON;
INSERT INTO dbo.Dim_Negociador (KeyNegociador, id_usuario, NombreCompleto) VALUES 
(0, 0, 'Negociador No Identificado'), 
(1, 1, 'Asesor Comercial 1');
SET IDENTITY_INSERT dbo.Dim_Negociador OFF;

SET IDENTITY_INSERT dbo.Dim_Persona ON;
INSERT INTO dbo.Dim_Persona (KeyPersona, id_persona, NombreCompleto) VALUES 
(0, NULL, 'No Conformada'),
(101, 101, 'Mateo Bravo'),
(102, 102, 'Carla Salas'),
(103, 103, 'Lucia Ramos');
SET IDENTITY_INSERT dbo.Dim_Persona OFF;

INSERT INTO dbo.Config_CalendarioAtencion_ETL VALUES
(1, 1, '08:00:00', '18:00:00', 1, 1),
(2, 2, '08:00:00', '18:00:00', 1, 1),
(3, 3, '08:00:00', '18:00:00', 1, 1),
(4, 4, '08:00:00', '18:00:00', 1, 1),
(5, 5, '08:00:00', '18:00:00', 1, 1),
(6, 6, '08:00:00', '13:00:00', 1, 1),
(7, 7, '00:00:00', '00:00:00', 0, 1);
GO

-- 6. Despliegue de la implementación real de LEAD mediante inclusión
:r "Entregables\16. ETL_Fact_NegociacionLead_h3.sql"
GO

PRINT '>> Entorno para prueba de concurrencia LEAD preparado y desplegado exitosamente.';
GO
