-- ====================================================================================================
-- NEXOSALUD — SISTEMA DE BUSINESS INTELLIGENCE ODONTOLÓGICO (CLÍNICA LUXEDENT)
-- PROYECTO BI — HITO H3 / FASE 2: BATERÍA DE PRUEBAS AUTOMATIZADA LEAD
-- SCRIPT DE EVALUACIÓN: Entregables/16. Pruebas_ETL_Lead_h3.sql
-- RESPONSABLE TÉCNICO: Jesús Daniel Ordóñez Ugarte (Integrante 4 — asumiendo LEAD por intercambio acordado)
-- TITULAR DEL ROL: Mario Antonio Martinez Dominguez (Integrante 3 — ETL BUYER y LEAD, Embudo y Calidad)
-- ARCHIVO REAL EVALUADO: Entregables/16. ETL_Fact_NegociacionLead_h3.sql (invocado mediante inclusión :r)
-- REQUISITOS EVALUADOS: 25 Escenarios Procedurales Formales (T01 a T25)
-- ====================================================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ====================================================================================================
-- FASE 1: PREPARACIÓN DEL ENTORNO TEMPORAL AISLADO DE PRUEBAS
-- ====================================================================================================
DECLARE @DbTestOLTP NVARCHAR(128) = N'Test_NexoSalud_OLTP_Lead_Bateria';
DECLARE @DbTestMart NVARCHAR(128) = N'Test_NexoSalud_Mart_Lead_Bateria';

-- Verificación preventiva de existencia (Política estricta no destructiva)
IF DB_ID(@DbTestOLTP) IS NOT NULL
BEGIN
    RAISERROR('ERROR PREVENTIVO: La base de datos [%s] ya existe en el servidor. Abortando para no sobreescribir datos preexistentes.', 16, 1, @DbTestOLTP);
    RETURN;
END;

IF DB_ID(@DbTestMart) IS NOT NULL
BEGIN
    RAISERROR('ERROR PREVENTIVO: La base de datos [%s] ya existe en el servidor. Abortando para no sobreescribir datos preexistentes.', 16, 1, @DbTestMart);
    RETURN;
END;

-- Creación normal de bases de datos aisladas
EXEC(N'CREATE DATABASE ' + @DbTestOLTP + N';');
EXEC(N'CREATE DATABASE ' + @DbTestMart + N';');
GO

USE Test_NexoSalud_OLTP_Lead_Bateria;
GO

-- 1.1 Esquemas y Tablas del OLTP Transaccional Ficticio
CREATE TABLE dbo.Personas (
    id_persona          INT NOT NULL PRIMARY KEY,
    nombres             VARCHAR(100) NOT NULL,
    apellidos           VARCHAR(100) NOT NULL,
    numero              VARCHAR(30) NULL,
    email               VARCHAR(150) NULL,
    estado_calidad      VARCHAR(30) NOT NULL DEFAULT 'Valido',
    autoriza_contacto   BIT NOT NULL DEFAULT 1,
    tipo_persona        VARCHAR(50) NULL DEFAULT 'Natural',
    fecha_nacimiento    DATE NULL,
    fecha_registro      DATETIME2(7) NOT NULL DEFAULT '2026-09-01 10:00:00'
);

CREATE TABLE dbo.Servicios (
    id_servicio         INT NOT NULL PRIMARY KEY,
    nombre_servicio     VARCHAR(100) NOT NULL
);

CREATE TABLE dbo.Sedes (
    id_sede             INT NOT NULL PRIMARY KEY,
    nombre_sede         VARCHAR(100) NOT NULL
);

CREATE TABLE dbo.Profesionales (
    id_profesional      INT NOT NULL PRIMARY KEY,
    nombre_completo     VARCHAR(150) NOT NULL
);

CREATE TABLE dbo.Disponibilidad (
    id_disponibilidad   INT NOT NULL PRIMARY KEY,
    id_sede             INT NOT NULL REFERENCES dbo.Sedes(id_sede),
    id_profesional      INT NOT NULL REFERENCES dbo.Profesionales(id_profesional),
    fecha_disponible    DATE NOT NULL,
    hora_inicio         TIME NOT NULL
);

CREATE TABLE dbo.Solicitudes (
    id_solicitud            INT NOT NULL PRIMARY KEY,
    id_persona              INT NOT NULL REFERENCES dbo.Personas(id_persona),
    id_servicio             INT NULL REFERENCES dbo.Servicios(id_servicio),
    fecha_solicitud         DATETIME2(7) NOT NULL,
    estado                  VARCHAR(30) NOT NULL,
    tipo_consulta           VARCHAR(50) NULL,
    prioridad               VARCHAR(30) NULL,
    motivo                  VARCHAR(255) NULL,
    fecha_primera_respuesta DATETIME2(7) NULL,
    fecha_cierre            DATETIME2(7) NULL
);

CREATE TABLE dbo.Opciones (
    id_opcion           INT NOT NULL PRIMARY KEY,
    id_solicitud        INT NOT NULL REFERENCES dbo.Solicitudes(id_solicitud),
    id_disponibilidad   INT NULL REFERENCES dbo.Disponibilidad(id_disponibilidad),
    precio_ofrecido     DECIMAL(10,2) NULL,
    seleccionada        BIT NOT NULL DEFAULT 0,
    fecha_ofrecida      DATETIME2(7) NOT NULL
);

CREATE TABLE dbo.Reservas (
    id_reserva              INT NOT NULL PRIMARY KEY,
    id_solicitud            INT NOT NULL REFERENCES dbo.Solicitudes(id_solicitud),
    id_opcion               INT NULL REFERENCES dbo.Opciones(id_opcion),
    fecha_reserva           DATETIME2(7) NOT NULL,
    estado                  VARCHAR(30) NOT NULL DEFAULT 'Pendiente',
    confirmacion_explicita  BIT NOT NULL DEFAULT 0,
    fecha_confirmacion      DATETIME2(7) NULL
);

CREATE TABLE dbo.Usuarios (
    id_usuario          INT NOT NULL PRIMARY KEY,
    nombre_completo     VARCHAR(150) NOT NULL,
    rol                 VARCHAR(50) NOT NULL
);

CREATE TABLE dbo.Interacciones (
    id_interaccion      INT NOT NULL PRIMARY KEY,
    id_persona          INT NOT NULL REFERENCES dbo.Personas(id_persona),
    id_usuario          INT NULL REFERENCES dbo.Usuarios(id_usuario),
    id_canal            INT NOT NULL DEFAULT 1,
    id_fuente           INT NOT NULL DEFAULT 1,
    fecha_hora          DATETIME2(7) NOT NULL,
    tipo                VARCHAR(50) NOT NULL,
    es_respuesta_util   BIT NOT NULL DEFAULT 1,
    resultado           VARCHAR(100) NULL,
    mensaje             VARCHAR(MAX) NULL
);

-- Siembra de Catálogos Maestros de Prueba
INSERT INTO dbo.Servicios (id_servicio, nombre_servicio) VALUES (1, 'Ortodoncia Invisible'), (2, 'Implantes Dentales'), (3, 'Diseno de Sonrisa');
INSERT INTO dbo.Sedes (id_sede, nombre_sede) VALUES (1, 'Sede Central Trujillo'), (2, 'Sede Larco'), (3, 'Sede California');
INSERT INTO dbo.Profesionales (id_profesional, nombre_completo) VALUES (1, 'Dra. Patricia Gomez'), (2, 'Dr. Roberto Mendoza'), (3, 'Dr. Javier Vargas');
INSERT INTO dbo.Usuarios (id_usuario, nombre_completo, rol) VALUES (1, 'Asesor Comercial 1', 'Operador'), (2, 'Asesor Comercial 2', 'Operador');

INSERT INTO dbo.Disponibilidad (id_disponibilidad, id_sede, id_profesional, fecha_disponible, hora_inicio) VALUES
(101, 1, 1, '2026-09-05', '09:00:00'),
(102, 2, 2, '2026-09-06', '10:00:00'),
(103, 3, 3, '2026-09-07', '11:00:00');
GO

-- ====================================================================================================
-- FASE 2: PREPARACIÓN DE LA BASE DE DESTINO (MART) CON DIMENSIONES Y VISTAS REALES DE STAGING
-- ====================================================================================================
USE Test_NexoSalud_Mart_Lead_Bateria;
GO

EXEC(N'CREATE SCHEMA staging;');
GO

-- 2.1 Copias Exactas de las Vistas Reales de Staging (Entregable 13) Vinculadas a la Base OLTP Aislada
CREATE OR ALTER VIEW staging.stg_Solicitudes
AS
SELECT 
    -- 1. Identificadores Naturales
    s.id_solicitud,
    s.id_persona,
    s.id_servicio AS id_servicio_solicitado,

    -- 2. Marcas Temporales y Claves de Fecha/Hora
    s.fecha_solicitud,
    CAST(CONVERT(VARCHAR(8), s.fecha_solicitud, 112) AS INT) AS KeyTiempoSolicitud,
    CAST(REPLACE(SUBSTRING(CONVERT(VARCHAR(8), s.fecha_solicitud, 108), 1, 5), ':', '') AS INT) AS KeyHoraSolicitud,
    s.fecha_primera_respuesta,
    CASE WHEN s.fecha_primera_respuesta IS NOT NULL THEN 1 ELSE 0 END AS tiene_fecha_primera_respuesta,
    s.fecha_cierre,
    CASE WHEN s.fecha_cierre IS NOT NULL THEN 1 ELSE 0 END AS tiene_fecha_cierre,

    -- 3. Consistencia Cronológica Transaccional
    CASE 
        WHEN s.fecha_primera_respuesta IS NULL OR s.fecha_primera_respuesta >= s.fecha_solicitud THEN 1 
        ELSE 0 
    END AS es_cronologia_respuesta_valida,
    CASE 
        WHEN s.fecha_cierre IS NULL OR s.fecha_cierre >= s.fecha_solicitud THEN 1 
        ELSE 0 
    END AS es_cronologia_cierre_valida,

    -- 4. Normalización de Estados Comerciales (Comparación Explícita de Mayúsculas y Espacios)
    s.estado AS estado_original,
    st_norm.estado_solicitud_norm,

    -- 5. Banderas Comerciales Derivadas de un ÚNICO Estado Normalizado
    CASE WHEN st_norm.estado_solicitud_norm IN ('Abierta', 'En Negociacion') THEN 1 ELSE 0 END AS es_solicitud_abierta,
    CASE WHEN st_norm.estado_solicitud_norm = 'Reserva' THEN 1 ELSE 0 END AS es_solicitud_reserva,
    CASE WHEN st_norm.estado_solicitud_norm = 'Confirmada' THEN 1 ELSE 0 END AS es_solicitud_confirmada,
    CASE WHEN st_norm.estado_solicitud_norm = 'Convertida' THEN 1 ELSE 0 END AS es_solicitud_convertida,
    CASE WHEN st_norm.estado_solicitud_norm = 'Abandonada' THEN 1 ELSE 0 END AS es_solicitud_abandonada,
    CASE WHEN st_norm.estado_solicitud_norm = 'Cancelada' THEN 1 ELSE 0 END AS es_solicitud_cancelada,
    CASE WHEN st_norm.estado_solicitud_norm = 'Descartada' THEN 1 ELSE 0 END AS es_solicitud_descartada,
    CASE WHEN st_norm.estado_solicitud_norm = 'Perdida' THEN 1 ELSE 0 END AS es_solicitud_perdida,
    CASE 
        WHEN st_norm.estado_solicitud_norm IN ('Reserva', 'Confirmada', 'Convertida', 'Abandonada', 'Cancelada', 'Descartada', 'Perdida') 
        THEN 1 
        ELSE 0 
    END AS es_solicitud_cerrada_comercial,
    CASE WHEN st_norm.estado_solicitud_norm = 'Desconocido' THEN 1 ELSE 0 END AS es_solicitud_estado_desconocido,

    -- 6. Detección Separada de Contradicciones entre Estado y Fechas
    CASE 
        WHEN s.fecha_cierre IS NOT NULL AND st_norm.estado_solicitud_norm IN ('Abierta', 'En Negociacion') THEN 1 
        ELSE 0 
    END AS tiene_cierre_sin_estado_resolutivo,
    CASE 
        WHEN s.fecha_cierre IS NULL AND st_norm.estado_solicitud_norm IN ('Confirmada', 'Convertida', 'Abandonada', 'Cancelada', 'Descartada', 'Perdida') THEN 1 
        ELSE 0 
    END AS tiene_estado_resolutivo_sin_fecha_cierre,

    -- 7. Clasificación de la Demanda (Sin Textos Libres Clínicos)
    s.tipo_consulta AS tipo_consulta_original,
    COALESCE(NULLIF(LTRIM(RTRIM(s.tipo_consulta)), ''), 'No Especificado') AS tipo_consulta_norm,
    s.prioridad AS prioridad_original,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(s.prioridad))) IN ('ALTA', 'HIGH', 'URGENTE') THEN 'Alta'
        WHEN UPPER(LTRIM(RTRIM(s.prioridad))) IN ('MEDIA', 'MEDIUM', 'NORMAL') THEN 'Media'
        WHEN UPPER(LTRIM(RTRIM(s.prioridad))) IN ('BAJA', 'LOW') THEN 'Baja'
        ELSE 'No Especificada'
    END AS prioridad_norm,
    CASE WHEN NULLIF(LTRIM(RTRIM(s.motivo)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_motivo_registrado,

    -- 8. Enriquecimiento Escalar de Opciones (Preserva Grano 1:1, Manejo de Ceros en Agregados y NULL en Precios)
    opc_prim.primer_precio_ofrecido,
    opc_prim.fecha_primer_precio_ofrecido,
    opc_prim.id_primera_opcion,
    opc_agg.cantidad_opciones_ofrecidas,
    opc_agg.cantidad_opciones_seleccionadas,
    opc_agg.precio_cotizado_seleccionado,
    opc_agg.tiene_multiple_opcion_seleccionada,

    -- 9. Enriquecimiento Escalar de Reservas (Coherencia de la Misma Primera Reserva)
    res_prim.id_primera_reserva,
    res_prim.primera_fecha_reserva,
    res_prim.estado_primera_reserva,
    res_prim.confirmacion_explicita_primera_reserva,
    res_prim.fecha_confirmacion_primera_reserva,
    res_agg.cantidad_reservas_asociadas,
    res_agg.tiene_alguna_reserva_confirmada,
    CASE WHEN res_agg.cantidad_reservas_asociadas > 0 THEN 1 ELSE 0 END AS tiene_reserva_registrada

FROM [Test_NexoSalud_OLTP_Lead_Bateria].dbo.[Solicitudes] s
CROSS APPLY (
    SELECT 
        CASE 
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('ABIERTA', 'ABIERTO', 'NUEVA', 'NUEVO') THEN 'Abierta'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('EN NEGOCIACION', 'EN NEGOCIACIÓN', 'NEGOCIACION', 'NEGOCIANDO') THEN 'En Negociacion'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('RESERVA', 'RESERVADA', 'PRE-RESERVA', 'PRE RESERVA') THEN 'Reserva'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('CONFIRMADA', 'CONFIRMADO') THEN 'Confirmada'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('CONVERTIDA', 'CONVERTIDO') THEN 'Convertida'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('CANCELADA', 'CANCELADO') THEN 'Cancelada'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('DESCARTADA', 'DESCARTADO') THEN 'Descartada'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('ABANDONADA', 'ABANDONADO') THEN 'Abandonada'
            WHEN UPPER(LTRIM(RTRIM(s.estado))) IN ('PERDIDA', 'PERDIDO') THEN 'Perdida'
            ELSE 'Desconocido'
        END AS estado_solicitud_norm
) st_norm
OUTER APPLY (
    SELECT TOP 1 
        o_prim.id_opcion AS id_primera_opcion,
        o_prim.precio_ofrecido AS primer_precio_ofrecido,
        o_prim.fecha_ofrecida AS fecha_primer_precio_ofrecido
    FROM [Test_NexoSalud_OLTP_Lead_Bateria].dbo.[Opciones] o_prim
    WHERE o_prim.id_solicitud = s.id_solicitud
    ORDER BY o_prim.fecha_ofrecida ASC, o_prim.id_opcion ASC
) opc_prim
OUTER APPLY (
    SELECT 
        COALESCE(COUNT(o_agg.id_opcion), 0) AS cantidad_opciones_ofrecidas,
        COALESCE(SUM(CASE WHEN o_agg.seleccionada = 1 THEN 1 ELSE 0 END), 0) AS cantidad_opciones_seleccionadas,
        CASE 
            WHEN COALESCE(SUM(CASE WHEN o_agg.seleccionada = 1 THEN 1 ELSE 0 END), 0) = 1 
            THEN MAX(CASE WHEN o_agg.seleccionada = 1 THEN o_agg.precio_ofrecido ELSE NULL END)
            ELSE NULL 
        END AS precio_cotizado_seleccionado,
        CASE 
            WHEN COALESCE(SUM(CASE WHEN o_agg.seleccionada = 1 THEN 1 ELSE 0 END), 0) > 1 THEN 1 
            ELSE 0 
        END AS tiene_multiple_opcion_seleccionada
    FROM [Test_NexoSalud_OLTP_Lead_Bateria].dbo.[Opciones] o_agg
    WHERE o_agg.id_solicitud = s.id_solicitud
) opc_agg
OUTER APPLY (
    SELECT TOP 1
        r_prim.id_reserva AS id_primera_reserva,
        r_prim.fecha_reserva AS primera_fecha_reserva,
        r_prim.estado AS estado_primera_reserva,
        r_prim.confirmacion_explicita AS confirmacion_explicita_primera_reserva,
        r_prim.fecha_confirmacion AS fecha_confirmacion_primera_reserva
    FROM [Test_NexoSalud_OLTP_Lead_Bateria].dbo.[Reservas] r_prim
    WHERE r_prim.id_solicitud = s.id_solicitud
    ORDER BY r_prim.fecha_reserva ASC, r_prim.id_reserva ASC
) res_prim
OUTER APPLY (
    SELECT 
        COALESCE(COUNT(r_agg.id_reserva), 0) AS cantidad_reservas_asociadas,
        COALESCE(MAX(CASE WHEN r_agg.confirmacion_explicita = 1 THEN 1 ELSE 0 END), 0) AS tiene_alguna_reserva_confirmada
    FROM [Test_NexoSalud_OLTP_Lead_Bateria].dbo.[Reservas] r_agg
    WHERE r_agg.id_solicitud = s.id_solicitud
) res_agg;
GO

PRINT '>> Vista [staging].[stg_Solicitudes] desplegada con definición real del Entregable 13.';
GO

CREATE OR ALTER VIEW staging.stg_Interacciones
AS
SELECT 
    -- 1. Identificador Natural de Origen
    i.id_interaccion,

    -- 2. Entidades Relacionadas Transaccionalmente (Directas de Origen)
    i.id_persona,
    i.id_canal,
    i.id_fuente,
    i.id_usuario AS id_usuario_operador,

    -- 3. Marcas Temporales y Claves de Fecha/Hora
    i.fecha_hora AS fecha_hora_interaccion,
    CAST(CONVERT(VARCHAR(8), i.fecha_hora, 112) AS INT) AS KeyTiempoInteraccion,
    CAST(REPLACE(SUBSTRING(CONVERT(VARCHAR(8), i.fecha_hora, 108), 1, 5), ':', '') AS INT) AS KeyHoraInteraccion,

    -- 4. Normalización de Tipos de Interacción
    i.tipo AS tipo_interaccion_original,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%WHATSAPP%' THEN 'WhatsApp'
        WHEN UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%LLAMADA%' OR UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%CALL%' THEN 'Llamada'
        WHEN UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%CORREO%' OR UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%EMAIL%' THEN 'Email'
        WHEN UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%FORMULARIO%' OR UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%WEB%' THEN 'Formulario Web'
        WHEN UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%PRESENCIAL%' OR UPPER(LTRIM(RTRIM(i.tipo))) LIKE '%SEDE%' THEN 'Presencial'
        WHEN i.tipo IS NULL OR LTRIM(RTRIM(i.tipo)) = '' THEN 'Desconocido'
        ELSE 'Otro'
    END AS tipo_interaccion_norm,

    -- 5. Calificación de Utilidad y Categorización Segura de Resultados
    CASE WHEN i.es_respuesta_util = 1 THEN 1 ELSE 0 END AS es_respuesta_util,
    CASE WHEN NULLIF(LTRIM(RTRIM(i.resultado)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_resultado_registrado,
    
    -- Categorización Explícita por Equivalencias Completas (No expone textos libres clínicos)
    CASE 
        WHEN i.resultado IS NULL OR LTRIM(RTRIM(i.resultado)) = '' 
            THEN 'Sin Resultado'
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN (
            'CITA AGENDADA', 'AGENDADO', 'AGENDADA', 'RESERVA AGENDADA', 'CITA CONFIRMADA', 'TURNO ASIGNADO'
        ) THEN 'Cita Agendada'
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN (
            'INTERESADO', 'INTERESADA', 'SOLICITA COTIZACION', 'SOLICITA INFORMACION', 'EN EVALUACION'
        ) THEN 'Interesado'
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN (
            'NO INTERESADO', 'NO INTERESADA', 'NO DESEA', 'RECHAZADO', 'RECHAZADA', 'DESCARTADO'
        ) THEN 'No Interesado'
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN (
            'NO CONTACTADO', 'NO CONTESTA', 'NO RESPONDE', 'BUZON DE VOZ', 'BUZÓN DE VOZ', 'NUMERO EQUIVOCADO', 'NÚMERO EQUIVOCADO'
        ) THEN 'No Contactado'
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN (
            'RESERVA CANCELADA', 'CITA CANCELADA', 'CANCELADO', 'CANCELADA', 'CITA ANULADA'
        ) THEN 'Reserva Cancelada'
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN (
            'EN SEGUIMIENTO', 'PENDIENTE DE RESPUESTA', 'RELLAMAR', 'VOLVER A LLAMAR'
        ) THEN 'En Seguimiento'
        ELSE 'Otro / No Tipificado'
    END AS resultado_categoria_norm,

    -- Banderas Específicas Derivadas de Categorías Seguras
    CASE 
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN ('CITA AGENDADA', 'AGENDADO', 'AGENDADA', 'RESERVA AGENDADA', 'CITA CONFIRMADA', 'TURNO ASIGNADO') 
        THEN 1 ELSE 0 
    END AS es_resultado_agendado,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN ('NO CONTACTADO', 'NO CONTESTA', 'NO RESPONDE', 'BUZON DE VOZ', 'BUZÓN DE VOZ', 'NUMERO EQUIVOCADO', 'NÚMERO EQUIVOCADO') 
        THEN 1 ELSE 0 
    END AS es_resultado_no_contactado,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN ('NO INTERESADO', 'NO INTERESADA', 'NO DESEA', 'RECHAZADO', 'RECHAZADA', 'DESCARTADO') 
        THEN 1 ELSE 0 
    END AS es_resultado_no_interesado,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(i.resultado))) IN ('RESERVA CANCELADA', 'CITA CANCELADA', 'CANCELADO', 'CANCELADA', 'CITA ANULADA') 
        THEN 1 ELSE 0 
    END AS es_resultado_reserva_cancelada,

    -- 6. Protección de Datos Personales (Exclusión de Mensajes de Conversación)
    CASE WHEN NULLIF(LTRIM(RTRIM(i.mensaje)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_mensaje_texto,
    LEN(ISNULL(i.mensaje, '')) AS longitud_mensaje_caracteres,

    -- 7. Acreditación de Desconexión Física en OLTP
    CAST(0 AS BIT) AS tiene_vinculo_solicitud_oltp

FROM [Test_NexoSalud_OLTP_Lead_Bateria].dbo.[Interacciones] i;
GO

PRINT '>> Vista [staging].[stg_Interacciones] desplegada con definición real del Entregable 13.';
GO

-- 2.2 Despliegue de Dimensiones Conformadas Requeridas
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
    KeyServicio INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_servicio INT NULL,
    NombreServicio VARCHAR(100) NOT NULL
);

CREATE TABLE dbo.Dim_Profesional (
    KeyProfesional INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_profesional INT NULL,
    NombreCompleto VARCHAR(150) NOT NULL
);

CREATE TABLE dbo.Dim_Negociador (
    KeyNegociador INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_usuario  INT NULL,
    NombreCompleto VARCHAR(150) NOT NULL
);

CREATE TABLE dbo.Dim_Persona (
    KeyPersona  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_persona  INT NULL,
    NombreCompleto VARCHAR(150) NOT NULL
);

-- Población de Miembros Desconocidos (Key = 0)
SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha) VALUES (0, '1900-01-01');
SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;

SET IDENTITY_INSERT dbo.Dim_Sede ON;
INSERT INTO dbo.Dim_Sede (KeySede, id_sede, NombreSede) VALUES (0, 0, 'Sede No Especificada');
SET IDENTITY_INSERT dbo.Dim_Sede OFF;

SET IDENTITY_INSERT dbo.Dim_Servicio ON;
INSERT INTO dbo.Dim_Servicio (KeyServicio, id_servicio, NombreServicio) VALUES (0, 0, 'Servicio No Especificado');
SET IDENTITY_INSERT dbo.Dim_Servicio OFF;

SET IDENTITY_INSERT dbo.Dim_Profesional ON;
INSERT INTO dbo.Dim_Profesional (KeyProfesional, id_profesional, NombreCompleto) VALUES (0, 0, 'Profesional No Asignado');
SET IDENTITY_INSERT dbo.Dim_Profesional OFF;

SET IDENTITY_INSERT dbo.Dim_Negociador ON;
INSERT INTO dbo.Dim_Negociador (KeyNegociador, id_usuario, NombreCompleto) VALUES (0, 0, 'Negociador No Identificado');
SET IDENTITY_INSERT dbo.Dim_Negociador OFF;

SET IDENTITY_INSERT dbo.Dim_Persona ON;
INSERT INTO dbo.Dim_Persona (KeyPersona, id_persona, NombreCompleto) VALUES (0, 0, 'Persona No Conformada');
SET IDENTITY_INSERT dbo.Dim_Persona OFF;

-- Población de Dimensiones Maestras de Prueba
INSERT INTO dbo.Dim_Sede (id_sede, NombreSede) VALUES (1, 'Sede Central Trujillo'), (2, 'Sede Larco'), (3, 'Sede California');
INSERT INTO dbo.Dim_Servicio (id_servicio, NombreServicio) VALUES (1, 'Ortodoncia Invisible'), (2, 'Implantes Dentales'), (3, 'Diseno de Sonrisa');
INSERT INTO dbo.Dim_Profesional (id_profesional, NombreCompleto) VALUES (1, 'Dra. Patricia Gomez'), (2, 'Dr. Roberto Mendoza'), (3, 'Dr. Javier Vargas');
INSERT INTO dbo.Dim_Negociador (id_usuario, NombreCompleto) VALUES (1, 'Asesor Comercial 1'), (2, 'Asesor Comercial 2');

-- Generación de Calendario en Dim_Tiempo con claves inteligentes (YYYYMMDD) para comprobaciones explícitas
SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
DECLARE @f DATE = '2024-01-01';
WHILE @f <= '2026-11-30'
BEGIN
    INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha) 
    VALUES (CAST(CONVERT(VARCHAR(8), @f, 112) AS INT), @f);
    SET @f = DATEADD(DAY, 1, @f);
END;
SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;

-- Población de Dim_Persona de Prueba (P1 a P500)
DECLARE @p INT = 1;
WHILE @p <= 500
BEGIN
    INSERT INTO dbo.Dim_Persona (id_persona, NombreCompleto) VALUES (@p, CONCAT('Persona de Prueba ', @p));
    SET @p = @p + 1;
END;
GO

-- ====================================================================================================
-- FASE 3: INCLUSIÓN DEL ARCHIVO REAL DEL ENTREGABLE 16 MEDIANTE SQLCMD (:r)
-- ====================================================================================================
:r "Entregables\16. ETL_Fact_NegociacionLead_h3.sql"
GO

-- Población del Calendario Hábil en dbo.Config_CalendarioAtencion_ETL (creada en Lote 2 del ETL real)
INSERT INTO dbo.Config_CalendarioAtencion_ETL (IdIntervalo, DiaSemana, HoraInicio, HoraFin, EsLaborable, Activo, DescripcionHorario)
VALUES 
(1, 1, '08:00:00', '18:00:00', 1, 1, 'Lunes 08:00 a 18:00'),
(2, 2, '08:00:00', '18:00:00', 1, 1, 'Martes 08:00 a 18:00'),
(3, 3, '08:00:00', '18:00:00', 1, 1, 'Miercoles 08:00 a 18:00'),
(4, 4, '08:00:00', '18:00:00', 1, 1, 'Jueves 08:00 a 18:00'),
(5, 5, '08:00:00', '18:00:00', 1, 1, 'Viernes 08:00 a 18:00'),
(6, 6, '08:00:00', '13:00:00', 1, 1, 'Sabado 08:00 a 13:00');
GO

-- ====================================================================================================
-- FASE 4: DEFINICIÓN DE TABLA DE RESULTADOS DE PRUEBA
-- ====================================================================================================
IF OBJECT_ID('tempdb..#ResultadosPruebaLead') IS NOT NULL DROP TABLE #ResultadosPruebaLead;
CREATE TABLE #ResultadosPruebaLead (
    CasoId              VARCHAR(10) NOT NULL,
    NombreCaso          VARCHAR(120) NOT NULL,
    ResultadoEsperado   VARCHAR(255) NOT NULL,
    ResultadoObtenido   VARCHAR(255) NOT NULL,
    Estado              VARCHAR(15) NOT NULL
);
GO

-- ====================================================================================================
-- FASE 5: EJECUCIÓN DE LA BATERÍA DE CASOS DE PRUEBA FORMALES (T01 A T25)
-- ====================================================================================================

-- ----------------------------------------------------------------------------------------------------
-- CASO T01: Carga Inicial de Solicitudes Base (10 Solicitudes de 10 Personas)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, estado_calidad, autoriza_contacto, fecha_registro)
VALUES 
(1, 'Carlos', 'Gomez', '944111222', 'carlos@test.pe', 'Valido', 1, '2026-09-01 09:00:00'),
(2, 'Maria', 'Lopez', '955222333', 'maria@test.pe', 'Valido', 1, '2026-09-02 09:00:00'),
(3, 'Juan', 'Perez', '966333444', 'juan@test.pe', 'Valido', 1, '2026-09-03 09:00:00'),
(4, 'Ana', 'Torres', '977444555', 'ana@test.pe', 'Valido', 1, '2026-09-04 09:00:00'),
(5, 'Luis', 'Castro', '988555666', 'luis@test.pe', 'Valido', 1, '2026-09-05 09:00:00'),
(6, 'Elena', 'Ruiz', '999666777', 'elena@test.pe', 'Valido', 1, '2026-09-06 09:00:00'),
(7, 'David', 'Moran', '911777888', 'david@test.pe', 'Valido', 1, '2026-09-07 09:00:00'),
(8, 'Sofia', 'Vega', '922888999', 'sofia@test.pe', 'Valido', 1, '2026-09-08 09:00:00'),
(9, 'Diego', 'Rios', '933999000', 'diego@test.pe', 'Valido', 1, '2026-09-09 09:00:00'),
(10, 'Lucia', 'Silva', '944000111', 'lucia@test.pe', 'Valido', 1, '2026-09-10 09:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES
(1, 1, 1, '2026-09-01 10:00:00', 'En Negociacion'),
(2, 2, 2, '2026-09-02 10:00:00', 'En Negociacion'),
(3, 3, 1, '2026-09-03 10:00:00', 'En Negociacion'),
(4, 4, 3, '2026-09-04 10:00:00', 'En Negociacion'),
(5, 5, 2, '2026-09-05 10:00:00', 'En Negociacion'),
(6, 6, 1, '2026-09-06 10:00:00', 'En Negociacion'),
(7, 7, 3, '2026-09-07 10:00:00', 'En Negociacion'),
(8, 8, 2, '2026-09-08 10:00:00', 'En Negociacion'),
(9, 9, 1, '2026-09-09 10:00:00', 'En Negociacion'),
(10, 10, 3, '2026-09-10 10:00:00', 'En Negociacion');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES
(1, 1, 101, 150.00, 1, '2026-09-01 10:30:00'),
(2, 2, 102, 350.00, 1, '2026-09-02 10:30:00'),
(3, 3, 101, 150.00, 1, '2026-09-03 10:30:00'),
(4, 4, 103, 500.00, 1, '2026-09-04 10:30:00'),
(5, 5, 102, 350.00, 1, '2026-09-05 10:30:00'),
(6, 6, 101, 150.00, 1, '2026-09-06 10:30:00'),
(7, 7, 103, 500.00, 1, '2026-09-07 10:30:00'),
(8, 8, 102, 350.00, 1, '2026-09-08 10:30:00'),
(9, 9, 101, 150.00, 1, '2026-09-09 10:30:00'),
(10, 10, 103, 500.00, 1, '2026-09-10 10:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

DECLARE @Ins INT, @Act INT, @Sin INT, @Rech INT, @Pend INT;
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T01',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rech OUTPUT,
    @Pendientes = @Pend OUTPUT;

DECLARE @TotalHechos_T01 INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T01', 'Carga Inicial de Solicitudes Base (10 Filas)',
    'Ins: 10, Act: 0, Sin: 0, Rech: 0, Total: 10',
    CONCAT('Ins: ', @Ins, ', Act: ', @Act, ', Sin: ', @Sin, ', Rech: ', @Rech, ', Total: ', @TotalHechos_T01),
    CASE WHEN @Ins = 10 AND @Act = 0 AND @Sin = 0 AND @Rech = 0 AND @TotalHechos_T01 = 10 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T02: Idempotencia Operativa Absoluta (Segunda Ejecución sin Cambios)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_Mart_Lead_Bateria;

DECLARE @Ins INT, @Act INT, @Sin INT, @Rech INT, @Pend INT;
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T02',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rech OUTPUT,
    @Pendientes = @Pend OUTPUT;

DECLARE @TotalHechos_T02 INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T02', 'Idempotencia Operativa Absoluta (0 Ins, 0 Act, 10 Sin)',
    'Ins: 0, Act: 0, Sin: 10, Rech: 0, Total: 10',
    CONCAT('Ins: ', @Ins, ', Act: ', @Act, ', Sin: ', @Sin, ', Rech: ', @Rech, ', Total: ', @TotalHechos_T02),
    CASE WHEN @Ins = 0 AND @Act = 0 AND @Sin = 10 AND @Rech = 0 AND @TotalHechos_T02 = 10 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T03: Actualización In-Place de Diferencias (Cambio de Estado a Confirmada)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
UPDATE dbo.Solicitudes SET estado = 'Confirmada' WHERE id_solicitud = 1;

USE Test_NexoSalud_Mart_Lead_Bateria;

DECLARE @Ins INT, @Act INT, @Sin INT, @Rech INT, @Pend INT;
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T03',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rech OUTPUT,
    @Pendientes = @Pend OUTPUT;

DECLARE @ResFinal_S1 INT = (SELECT LeadsResultadoFinal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 1);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T03', 'Actualización In-Place de Diferencias (S1 Confirmada)',
    'Ins: 0, Act: 1, Sin: 9, LeadsResultadoFinal S1 = 1',
    CONCAT('Ins: ', @Ins, ', Act: ', @Act, ', Sin: ', @Sin, ', ResFinal: ', @ResFinal_S1),
    CASE WHEN @Ins = 0 AND @Act = 1 AND @Sin = 9 AND @ResFinal_S1 = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T04: 1 Persona con Múltiples Solicitudes Distintas (Grano Atómico Solicitud)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (11, 1, 1, '2026-09-15 11:00:00', 'En Negociacion');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (11, 11, 101, 200.00, 1, '2026-09-15 11:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

DECLARE @Ins INT, @Act INT, @Sin INT, @Rech INT, @Pend INT;
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T04',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rech OUTPUT,
    @Pendientes = @Pend OUTPUT;

DECLARE @CantFilas_P1 INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_persona_origen = 1);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T04', '1 Persona con Múltiples Solicitudes Distintas (P1 con S1 y S11)',
    'Ins: 1, Act: 0, Filas P1 en Hechos: 2',
    CONCAT('Ins: ', @Ins, ', Act: ', @Act, ', Filas P1: ', @CantFilas_P1),
    CASE WHEN @Ins = 1 AND @Act = 0 AND @CantFilas_P1 = 2 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T05: Maduración Temporal de Cohortes L1 (Inmadura vs Evaluable)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES 
(12, 'Pedro', 'Navarro', '944123456', 'pedro@test.pe', '2026-09-12 08:00:00'),
(13, 'Clara', 'Mendez', '955654321', 'clara@test.pe', '2026-09-27 08:00:00');

-- S12: 18 días de antigüedad al corte 2026-09-30 (Evaluable = 1, Inmadura = 0)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (12, 12, 1, '2026-09-12 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (12, 12, 101, 150.00, 1, '2026-09-12 10:30:00');

-- S13: 3 días de antigüedad al corte 2026-09-30 (Evaluable = 0, Inmadura = 1)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (13, 13, 2, '2026-09-27 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (13, 13, 102, 350.00, 1, '2026-09-27 10:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T05',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Eval_S12 INT, @Inmad_S12 INT, @Eval_S13 INT, @Inmad_S13 INT;
SELECT @Eval_S12 = LeadsCohorteEvaluable, @Inmad_S12 = CohorteInmadura FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 12;
SELECT @Eval_S13 = LeadsCohorteEvaluable, @Inmad_S13 = CohorteInmadura FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 13;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T05', 'Maduración Temporal de Cohortes L1 (S12 Evaluable, S13 Inmadura)',
    'S12: Eval=1 Inmad=0 | S13: Eval=0 Inmad=1',
    CONCAT('S12: Eval=', @Eval_S12, ' Inmad=', @Inmad_S12, ' | S13: Eval=', @Eval_S13, ' Inmad=', @Inmad_S13),
    CASE WHEN @Eval_S12 = 1 AND @Inmad_S12 = 0 AND @Eval_S13 = 0 AND @Inmad_S13 = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T06: Intervalo Semiabierto y Exclusión Posterior al Corte
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (14, 'Hugo', 'Paredes', '966112233', 'hugo@test.pe', '2026-10-01 07:00:00');

-- Solicitud posterior al corte 2026-09-30 (debe ser ignorada)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (14, 14, 1, '2026-10-01 08:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (14, 14, 101, 150.00, 1, '2026-10-01 08:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T06',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Existe_S14 INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 14);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T06', 'Intervalo Semiabierto (Exclusión Estricta de S14 Posterior al Corte)',
    'Filas S14 en Hechos = 0',
    CONCAT('Filas S14: ', @Existe_S14),
    CASE WHEN @Existe_S14 = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T07: Verificación Explícita de Claves de Fecha (KeyTiempoSolicitud y KeyTiempoReserva)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (15, 'Raul', 'Salas', '977889900', 'raul@test.pe', '2026-09-05 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (15, 15, 1, '2026-09-05 14:30:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (15, 15, 101, 150.00, 1, '2026-09-05 15:00:00');

INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita)
VALUES (15, 15, 15, '2026-09-07 10:00:00', 'Pendiente', 0);

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T07',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @KeySol_S15 INT, @KeyRes_S15 INT, @KeyRes_S3 INT;
SELECT @KeySol_S15 = KeyTiempoSolicitud, @KeyRes_S15 = KeyTiempoReserva FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 15;
SELECT @KeyRes_S3 = KeyTiempoReserva FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 3;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T07', 'Verificación Explícita de Claves de Fecha (Valores Exactos, no solo > 0)',
    'KeyTiempoSol S15 = 20260905, KeyTiempoRes S15 = 20260907, KeyTiempoRes S3 = 0',
    CONCAT('KeySol S15: ', @KeySol_S15, ', KeyRes S15: ', @KeyRes_S15, ', KeyRes S3: ', @KeyRes_S3),
    CASE WHEN @KeySol_S15 = 20260905 AND @KeyRes_S15 = 20260907 AND @KeyRes_S3 = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T08: Conversión Previa a Abandono y Resultado Final L3
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (16, 'Valeria', 'Montes', '988001122', 'valeria@test.pe', '2026-09-02 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (16, 16, 1, '2026-09-02 09:00:00', 'Abandonada');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (16, 16, 101, 150.00, 1, '2026-09-02 09:30:00');

-- Reserva creada en 2 días (dentro de 14 días), luego abandonó
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita)
VALUES (16, 16, 16, '2026-09-04 11:00:00', 'Pendiente', 0);

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T08',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Conv14D_S16 INT, @ConvTot_S16 INT, @Aband_S16 INT, @ResFin_S16 INT, @EnNeg_S16 INT;
SELECT 
    @Conv14D_S16 = LeadsConvertidosPayer14Dias,
    @ConvTot_S16 = LeadsConvertidosPayerTotal,
    @Aband_S16   = LeadsAbandonados,
    @ResFin_S16  = LeadsResultadoFinal,
    @EnNeg_S16   = LeadsEnNegociacion
FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 16;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T08', 'Conversión Previa a Abandono y Resultado Final L3',
    'Conv14D=1, ConvTot=1, Abandonada=1, ResFinal=1, EnNeg=0',
    CONCAT('Conv14D=', @Conv14D_S16, ', ConvTot=', @ConvTot_S16, ', Aband=', @Aband_S16, ', ResFin=', @ResFin_S16, ', EnNeg=', @EnNeg_S16),
    CASE WHEN @Conv14D_S16 = 1 AND @ConvTot_S16 = 1 AND @Aband_S16 = 1 AND @ResFin_S16 = 1 AND @EnNeg_S16 = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T09: Clasificación Comercial de Solicitud Perdida y Rechazo por Estado Desconocido
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES 
(17, 'Tomas', 'Guerrero', '999112233', 'tomas@test.pe', '2026-09-03 08:00:00'),
(18, 'Gisela', 'Bazan', '911223344', 'gisela@test.pe', '2026-09-03 08:00:00');

-- S17: Estado Perdida (resultado final)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (17, 17, 2, '2026-09-03 10:00:00', 'Perdida');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (17, 17, 102, 350.00, 1, '2026-09-03 10:30:00');

-- S18: Estado Anómalo no catalogado (debe ser rechazada)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (18, 18, 1, '2026-09-03 11:00:00', 'EstadoInexistenteXYZ');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (18, 18, 101, 150.00, 1, '2026-09-03 11:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T09',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @ResFin_S17 INT = (SELECT LeadsResultadoFinal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 17);
DECLARE @Rechazo_S18 INT = (SELECT COUNT(*) FROM dbo.Rechazos_ETL_Lead WHERE id_solicitud_origen = 18 AND MotivoRechazo LIKE '%EstadoComercialDesconocido%');
DECLARE @Existe_S18_Fact INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 18);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T09', 'Clasificación Comercial: Perdida y Rechazo por Estado Desconocido',
    'ResFinal S17 = 1, Rechazo S18 = 1, S18 en Hechos = 0',
    CONCAT('ResFinal S17: ', @ResFin_S17, ', Rechazo S18: ', @Rechazo_S18, ', Fact S18: ', @Existe_S18_Fact),
    CASE WHEN @ResFin_S17 = 1 AND @Rechazo_S18 = 1 AND @Existe_S18_Fact = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T10: Reglas Contractuales de Precio Cotizado (NULL, Seleccionado, Múltiples, Primer Ofrecido)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES 
(19, 'Precio1', 'User', '922001100', 'p1@test.pe', '2026-09-04 08:00:00'),
(20, 'Precio2', 'User', '933001100', 'p2@test.pe', '2026-09-04 08:00:00'),
(21, 'Precio3', 'User', '944001100', 'p3@test.pe', '2026-09-04 08:00:00'),
(22, 'Precio4', 'User', '955001100', 'p4@test.pe', '2026-09-04 08:00:00');

-- S19: 0 opciones -> NULL
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (19, 19, 1, '2026-09-04 10:00:00', 'En Negociacion');

-- S20: 1 seleccionada entre varias -> 280.00
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (20, 20, 2, '2026-09-04 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES 
(201, 20, 102, 150.00, 0, '2026-09-04 10:15:00'),
(202, 20, 102, 280.00, 1, '2026-09-04 10:30:00');

-- S21: Múltiples seleccionadas -> NULL
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (21, 21, 1, '2026-09-04 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES 
(211, 21, 101, 150.00, 1, '2026-09-04 10:15:00'),
(212, 21, 101, 280.00, 1, '2026-09-04 10:30:00');

-- S22: 0 seleccionadas -> primer precio ofrecido (180.00)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (22, 22, 3, '2026-09-04 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES 
(221, 22, 103, 180.00, 0, '2026-09-04 10:15:00'),
(222, 22, 103, 320.00, 0, '2026-09-04 10:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T10',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @P19 DECIMAL(10,2), @P20 DECIMAL(10,2), @P21 DECIMAL(10,2), @P22 DECIMAL(10,2);
SELECT @P19 = PrecioCotizado FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 19;
SELECT @P20 = PrecioCotizado FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 20;
SELECT @P21 = PrecioCotizado FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 21;
SELECT @P22 = PrecioCotizado FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 22;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T10', 'Reglas Contractuales de Precio Cotizado (NULL, Seleccionado, Múltiples, Primer Ofrecido)',
    'P19: NULL, P20: 280.00, P21: NULL, P22: 180.00',
    CONCAT('P19: ', ISNULL(CAST(@P19 AS VARCHAR), 'NULL'), ', P20: ', ISNULL(CAST(@P20 AS VARCHAR), 'NULL'), ', P21: ', ISNULL(CAST(@P21 AS VARCHAR), 'NULL'), ', P22: ', ISNULL(CAST(@P22 AS VARCHAR), 'NULL')),
    CASE WHEN @P19 IS NULL AND @P20 = 280.00 AND @P21 IS NULL AND @P22 = 180.00 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T11: Solicitud con Múltiples Interacciones Útiles (Consumo Cronológico 1:1)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (23, 'Atrib1', 'User', '966001100', 'atrib1@test.pe', '2026-09-04 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (23, 23, 1, '2026-09-04 09:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (23, 23, 101, 150.00, 1, '2026-09-04 09:15:00');

-- Interacción 1: 5 minutos después (300 s), operador 1
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (231, 23, 1, '2026-09-04 09:05:00', 'WhatsApp', 1, 'Interesado');

-- Interacción 2: posterior, operador 2 (no debe sobrescribir)
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (232, 23, 2, '2026-09-04 09:20:00', 'Llamada', 1, 'Cita Agendada');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T11',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Seg_S23 INT, @Min_S23 INT, @SLA_S23 VARCHAR(30), @Resp15M_S23 INT, @Neg_S23 INT;
SELECT 
    @Seg_S23 = SegundosPrimeraRespuesta,
    @Min_S23 = MinutosPrimeraRespuesta,
    @SLA_S23 = EstadoRespuestaSLA,
    @Resp15M_S23 = LeadsRespuestaUtil15Min,
    @Neg_S23 = KeyNegociador
FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 23;

DECLARE @KeyNeg1 INT = (SELECT KeyNegociador FROM dbo.Dim_Negociador WHERE id_usuario = 1);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T11', 'Solicitud con Múltiples Interacciones Útiles (Consumo Cronológico 1:1)',
    CONCAT('Seg=300, Min=5, SLA=Acreditada, Resp15M=1, KeyNeg=', @KeyNeg1),
    CONCAT('Seg=', @Seg_S23, ', Min=', @Min_S23, ', SLA=', @SLA_S23, ', Resp15M=', @Resp15M_S23, ', KeyNeg=', @Neg_S23),
    CASE WHEN @Seg_S23 = 300 AND @Min_S23 = 5 AND @SLA_S23 = 'Acreditada' AND @Resp15M_S23 = 1 AND @Neg_S23 = @KeyNeg1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T12: Preservación Irreversible de Ambigüedad entre Solicitudes Concurrentes
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (24, 'Ambig', 'User', '977001100', 'ambig@test.pe', '2026-09-04 08:00:00');

-- Dos solicitudes concurrentes de la misma persona
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES 
(241, 24, 1, '2026-09-04 09:00:00', 'En Negociacion'),
(242, 24, 2, '2026-09-04 09:10:00', 'En Negociacion');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES 
(241, 241, 101, 150.00, 1, '2026-09-04 09:05:00'),
(242, 242, 102, 350.00, 1, '2026-09-04 09:12:00');

-- Una interacción posterior a ambas: genera ambigüedad irreversible en ambas
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (2401, 24, 1, '2026-09-04 09:15:00', 'WhatsApp', 1, 'Interesado');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T12',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Ambig_241 BIT, @SLA_241 VARCHAR(30), @Resp15M_241 INT, @Seg_241 INT;
DECLARE @Ambig_242 BIT, @SLA_242 VARCHAR(30), @Resp15M_242 INT, @Seg_242 INT;

SELECT @Ambig_241 = AtribucionAmbigua, @SLA_241 = EstadoRespuestaSLA, @Resp15M_241 = LeadsRespuestaUtil15Min, @Seg_241 = SegundosPrimeraRespuesta FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 241;
SELECT @Ambig_242 = AtribucionAmbigua, @SLA_242 = EstadoRespuestaSLA, @Resp15M_242 = LeadsRespuestaUtil15Min, @Seg_242 = SegundosPrimeraRespuesta FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 242;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T12', 'Preservación Irreversible de Ambigüedad entre Solicitudes Concurrentes',
    'Ambas: Ambigua=1, SLA=EvidenciaInsuficiente, Resp15M=0, Seg=NULL',
    CONCAT('S241: Amb=', @Ambig_241, ' SLA=', @SLA_241, ' | S242: Amb=', @Ambig_242, ' SLA=', @SLA_242),
    CASE WHEN @Ambig_241 = 1 AND @SLA_241 = 'EvidenciaInsuficiente' AND @Resp15M_241 = 0 AND @Seg_241 IS NULL
          AND @Ambig_242 = 1 AND @SLA_242 = 'EvidenciaInsuficiente' AND @Resp15M_242 = 0 AND @Seg_242 IS NULL
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T13: Cómputo de SLA Hábil en Umbrales Críticos (899s Acreditada, 900s Acreditada, 901s Incumplida)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES 
(251, 'SLA_899', 'User', '988001101', 'sla899@test.pe', '2026-09-04 08:00:00'),
(252, 'SLA_900', 'User', '988001102', 'sla900@test.pe', '2026-09-04 08:00:00'),
(253, 'SLA_901', 'User', '988001103', 'sla901@test.pe', '2026-09-04 08:00:00');

-- Solicitudes registradas el Viernes 2026-09-04 a las 17:55:00 (restan 300 s para el cierre de las 18:00)
-- Sábado abre a las 08:00:00
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES 
(251, 251, 1, '2026-09-04 17:55:00', 'En Negociacion'),
(252, 252, 1, '2026-09-04 17:55:00', 'En Negociacion'),
(253, 253, 1, '2026-09-04 17:55:00', 'En Negociacion');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES 
(251, 251, 101, 150.00, 1, '2026-09-04 17:56:00'),
(252, 252, 101, 150.00, 1, '2026-09-04 17:56:00'),
(253, 253, 101, 150.00, 1, '2026-09-04 17:56:00');

-- 899 s: Sábado 08:09:59 (300 s del viernes + 599 s del sábado) -> Acreditada, Resp15M = 1
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (2510, 251, 1, '2026-09-05 08:09:59', 'WhatsApp', 1, 'Interesado');

-- 900 s: Sábado 08:10:00 (300 s del viernes + 600 s del sábado) -> Acreditada, Resp15M = 1
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (2520, 252, 1, '2026-09-05 08:10:00', 'WhatsApp', 1, 'Interesado');

-- 901 s: Sábado 08:10:01 (300 s del viernes + 601 s del sábado) -> Incumplida, Resp15M = 0
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (2530, 253, 1, '2026-09-05 08:10:01', 'WhatsApp', 1, 'Interesado');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T13',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Seg_251 INT, @SLA_251 VARCHAR(30), @Resp15M_251 INT;
DECLARE @Seg_252 INT, @SLA_252 VARCHAR(30), @Resp15M_252 INT;
DECLARE @Seg_253 INT, @SLA_253 VARCHAR(30), @Resp15M_253 INT;

SELECT @Seg_251 = SegundosPrimeraRespuesta, @SLA_251 = EstadoRespuestaSLA, @Resp15M_251 = LeadsRespuestaUtil15Min FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 251;
SELECT @Seg_252 = SegundosPrimeraRespuesta, @SLA_252 = EstadoRespuestaSLA, @Resp15M_252 = LeadsRespuestaUtil15Min FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 252;
SELECT @Seg_253 = SegundosPrimeraRespuesta, @SLA_253 = EstadoRespuestaSLA, @Resp15M_253 = LeadsRespuestaUtil15Min FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 253;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T13', 'Cómputo de SLA Hábil en Umbrales Críticos (899s, 900s, 901s)',
    '251: 899s/Acreditada/1 | 252: 900s/Acreditada/1 | 253: 901s/Incumplida/0',
    CONCAT('251: ', @Seg_251, 's/', @SLA_251, '/', @Resp15M_251, ' | 252: ', @Seg_252, 's/', @SLA_252, '/', @Resp15M_252, ' | 253: ', @Seg_253, 's/', @SLA_253, '/', @Resp15M_253),
    CASE WHEN @Seg_251 = 899 AND @SLA_251 = 'Acreditada' AND @Resp15M_251 = 1
          AND @Seg_252 = 900 AND @SLA_252 = 'Acreditada' AND @Resp15M_252 = 1
          AND @Seg_253 = 901 AND @SLA_253 = 'Incumplida' AND @Resp15M_253 = 0
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T14: Solicitud sin Respuesta e Interacciones No Útiles (EvidenciaInsuficiente)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES 
(261, 'SinResp', 'User', '999001101', 'sinresp@test.pe', '2026-09-04 08:00:00'),
(262, 'NoUtil', 'User', '999001102', 'noutil@test.pe', '2026-09-04 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES 
(261, 261, 1, '2026-09-04 09:00:00', 'En Negociacion'),
(262, 262, 1, '2026-09-04 09:00:00', 'En Negociacion');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES 
(261, 261, 101, 150.00, 1, '2026-09-04 09:15:00'),
(262, 262, 101, 150.00, 1, '2026-09-04 09:15:00');

-- Interacción con es_respuesta_util = 0 (no acredita respuesta útil de SLA)
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (2620, 262, 1, '2026-09-04 09:05:00', 'WhatsApp', 0, 'No Contactado');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T14',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @SLA_261 VARCHAR(30), @Seg_261 INT, @SLA_262 VARCHAR(30), @Seg_262 INT;
SELECT @SLA_261 = EstadoRespuestaSLA, @Seg_261 = SegundosPrimeraRespuesta FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 261;
SELECT @SLA_262 = EstadoRespuestaSLA, @Seg_262 = SegundosPrimeraRespuesta FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 262;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T14', 'Solicitud sin Respuesta e Interacciones No Útiles (EvidenciaInsuficiente)',
    '261: EvidenciaInsuficiente/NULL | 262: EvidenciaInsuficiente/NULL',
    CONCAT('261: ', @SLA_261, '/', ISNULL(CAST(@Seg_261 AS VARCHAR), 'NULL'), ' | 262: ', @SLA_262, '/', ISNULL(CAST(@Seg_262 AS VARCHAR), 'NULL')),
    CASE WHEN @SLA_261 = 'EvidenciaInsuficiente' AND @Seg_261 IS NULL
          AND @SLA_262 = 'EvidenciaInsuficiente' AND @Seg_262 IS NULL
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T15: Resolución Dimensional con Multiplicidad (>1 Coincidencias -> ErrorLookupAmbiguo)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_Mart_Lead_Bateria;

-- Inserción forzada de duplicidad en catálogo de Dim_Servicio
INSERT INTO dbo.Dim_Servicio (id_servicio, NombreServicio) VALUES (99, 'Servicio Duplicado A');
INSERT INTO dbo.Dim_Servicio (id_servicio, NombreServicio) VALUES (99, 'Servicio Duplicado B');

USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Servicios (id_servicio, nombre_servicio) VALUES (99, 'Servicio Temporal 99');
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (27, 'DimMult', 'User', '911998877', 'dimmult@test.pe', '2026-09-04 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (27, 27, 99, '2026-09-04 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (27, 27, 101, 150.00, 1, '2026-09-04 10:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T15',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Rechazo_S27 INT = (SELECT COUNT(*) FROM dbo.Rechazos_ETL_Lead WHERE id_solicitud_origen = 27 AND MotivoRechazo LIKE '%ErrorLookupAmbiguo: Dim_Servicio%');
DECLARE @Existe_S27_Fact INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 27);

-- Limpieza de duplicidad para no contaminar casos posteriores
DELETE FROM dbo.Dim_Servicio WHERE id_servicio = 99;
DELETE FROM Test_NexoSalud_OLTP_Lead_Bateria.dbo.Opciones WHERE id_solicitud = 27;
DELETE FROM Test_NexoSalud_OLTP_Lead_Bateria.dbo.Solicitudes WHERE id_solicitud = 27;
DELETE FROM Test_NexoSalud_OLTP_Lead_Bateria.dbo.Servicios WHERE id_servicio = 99;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T15', 'Resolución Dimensional con Multiplicidad (>1 Coincidencias -> ErrorLookupAmbiguo)',
    'Rechazo S27 = 1, S27 en Hechos = 0',
    CONCAT('Rechazo S27: ', @Rechazo_S27, ', Fact S27: ', @Existe_S27_Fact),
    CASE WHEN @Rechazo_S27 = 1 AND @Existe_S27_Fact = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T16: Validación Defensiva de Parámetros (@ConvencionHoraria, @FechaCorte, @FuenteOLTP, Hitos)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_Mart_Lead_Bateria;

DECLARE @ErrConvNullCapturado BIT = 0;
DECLARE @ErrConvVaciaCapturado BIT = 0;
DECLARE @ErrCorteCapturado BIT = 0;
DECLARE @ErrFuenteCapturado BIT = 0;
DECLARE @ErrPagoCapturado BIT = 0;
DECLARE @ErrHitoInvalidoCapturado BIT = 0;

-- Sub-caso 1: @ConvencionHoraria NULL (rechazo obligatorio previo a modificar hechos)
BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_T16_ERR0A',
        @ConfigHitoConversion = 'CreacionReserva',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
        @ConvencionHoraria = NULL;
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%@ConvencionHoraria es obligatorio%' SET @ErrConvNullCapturado = 1;
END CATCH;

-- Sub-caso 2: @ConvencionHoraria vacía (rechazo obligatorio)
BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_T16_ERR0B',
        @ConfigHitoConversion = 'CreacionReserva',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
        @ConvencionHoraria = '   ';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%@ConvencionHoraria es obligatorio%' SET @ErrConvVaciaCapturado = 1;
END CATCH;

-- Sub-caso 3: @FechaCorte NULL
BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = NULL,
        @BatchId = 'BATCH_T16_ERR1',
        @ConfigHitoConversion = 'CreacionReserva',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
        @ConvencionHoraria = 'Local_Clinica_SinOffset';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%@FechaCorte es obligatorio%' SET @ErrCorteCapturado = 1;
END CATCH;

-- Sub-caso 4: @FuenteOLTP inexistente
BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_T16_ERR2',
        @ConfigHitoConversion = 'CreacionReserva',
        @FuenteOLTP = 'BaseDeDatosInexistente_XYZ',
        @ConvencionHoraria = 'Local_Clinica_SinOffset';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%no existe en la instancia%' SET @ErrFuenteCapturado = 1;
END CATCH;

-- Sub-caso 5: PagoValidado bloqueado
BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_T16_ERR3',
        @ConfigHitoConversion = 'PagoValidado',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
        @ConvencionHoraria = 'Local_Clinica_SinOffset';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%PagoValidado%permanece bloqueado%' SET @ErrPagoCapturado = 1;
END CATCH;

-- Sub-caso 6: Hito inexistente
BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_T16_ERR4',
        @ConfigHitoConversion = 'HitoInexistenteXYZ',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
        @ConvencionHoraria = 'Local_Clinica_SinOffset';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%no es reconocido%' SET @ErrHitoInvalidoCapturado = 1;
END CATCH;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T16', 'Validación Defensiva de Parámetros, Convención Horaria y Fuente OLTP',
    'ErrConvNull: 1, ErrConvVac: 1, ErrCorte: 1, ErrFuente: 1, ErrPago: 1, ErrHitoInv: 1',
    CONCAT('ErrConvNull: ', @ErrConvNullCapturado, ', ErrConvVac: ', @ErrConvVaciaCapturado, ', ErrCorte: ', @ErrCorteCapturado, ', ErrFuente: ', @ErrFuenteCapturado, ', ErrPago: ', @ErrPagoCapturado, ', ErrHitoInv: ', @ErrHitoInvalidoCapturado),
    CASE WHEN @ErrConvNullCapturado = 1 AND @ErrConvVaciaCapturado = 1 AND @ErrCorteCapturado = 1 AND @ErrFuenteCapturado = 1 AND @ErrPagoCapturado = 1 AND @ErrHitoInvalidoCapturado = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T17: Reversión Atómica Integral (Rollback) ante Fallo Forzado por Trigger
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (32, 'Trig_User', 'Test', '944999111', 'trig@test.pe', '2026-09-02 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (32, 32, 1, '2026-09-02 10:00:00', 'En Negociacion');
UPDATE dbo.Solicitudes SET estado = 'Confirmada' WHERE id_solicitud = 2;

USE Test_NexoSalud_Mart_Lead_Bateria;

IF OBJECT_ID('tempdb..#Instantanea_Fact_Lead') IS NOT NULL DROP TABLE #Instantanea_Fact_Lead;
SELECT * INTO #Instantanea_Fact_Lead FROM dbo.Fact_NegociacionLead;

EXEC sp_executesql N'
CREATE OR ALTER TRIGGER dbo.trg_TestRollbackLead ON dbo.Fact_NegociacionLead
FOR INSERT
AS
BEGIN
    IF EXISTS (SELECT 1 FROM inserted WHERE id_solicitud_origen = 32)
    BEGIN
        RAISERROR(''Fallo forzado por trigger de prueba para verificar atomicidad de reversión LEAD.'', 16, 1);
        ROLLBACK TRANSACTION;
    END;
END;
';

DECLARE @ErrorCapturado_T17 BIT = 0;
DECLARE @InsFail INT = 0, @ActFail INT = 0;

BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_LEAD_T17_FAIL',
        @ConfigHitoConversion = 'CreacionReserva',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset',
        @Insertados = @InsFail OUTPUT,
        @Actualizados = @ActFail OUTPUT;
END TRY
BEGIN CATCH
    SET @ErrorCapturado_T17 = 1;
END CATCH;

DROP TRIGGER dbo.trg_TestRollbackLead;

DECLARE @Diff1 INT = (SELECT COUNT(*) FROM (SELECT * FROM dbo.Fact_NegociacionLead EXCEPT SELECT * FROM #Instantanea_Fact_Lead) d);
DECLARE @Diff2 INT = (SELECT COUNT(*) FROM (SELECT * FROM #Instantanea_Fact_Lead EXCEPT SELECT * FROM dbo.Fact_NegociacionLead) d);
DECLARE @Existe_S32 INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 32);
DECLARE @LogErr INT = (SELECT COUNT(*) FROM dbo.Log_Ejecucion_ETL WHERE BatchId = 'BATCH_LEAD_T17_FAIL' AND TipoEvento = 'ERROR');

UPDATE Test_NexoSalud_OLTP_Lead_Bateria.dbo.Solicitudes SET estado = 'En Negociacion' WHERE id_solicitud = 2;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T17', 'Reversión Atómica Integral (Rollback) ante Fallo Forzado por Trigger',
    'Error: 1, Diff1: 0, Diff2: 0, S32 en Hechos: 0, Ins: 0, Act: 0, Log ERROR: 1',
    CONCAT('Error: ', @ErrorCapturado_T17, ', Diff1: ', @Diff1, ', Diff2: ', @Diff2, ', S32: ', @Existe_S32, ', Ins: ', @InsFail, ', Act: ', @ActFail, ', Log: ', @LogErr),
    CASE WHEN @ErrorCapturado_T17 = 1 AND @Diff1 = 0 AND @Diff2 = 0 AND @Existe_S32 = 0 AND @InsFail = 0 AND @ActFail = 0 AND @LogErr = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T18: Primera Reserva Pendiente y Segunda Confirmada (Confirmación de la Segunda, KeyTiempo de la Primera)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (28, 'Res2Conf', 'User', '944118822', 'res2conf@test.pe', '2026-09-05 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (28, 28, 1, '2026-09-05 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (28, 28, 101, 150.00, 1, '2026-09-05 10:30:00');

-- Reserva 1: Creada el 2026-09-06 10:00:00, Pendiente, sin confirmación explícita
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (281, 28, 28, '2026-09-06 10:00:00', 'Pendiente', 0, NULL);

-- Reserva 2: Creada el 2026-09-07 10:00:00, Confirmada explícita el 2026-09-08 14:00:00
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (282, 28, 28, '2026-09-07 10:00:00', 'Confirmada', 1, '2026-09-08 14:00:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T18',
    @ConfigHitoConversion = 'ConfirmacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @ConvTot_S28 INT, @Conv14D_S28 INT, @KeyRes_S28 INT;
SELECT 
    @ConvTot_S28 = LeadsConvertidosPayerTotal,
    @Conv14D_S28 = LeadsConvertidosPayer14Dias,
    @KeyRes_S28  = KeyTiempoReserva
FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 28;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T18', 'Primera Reserva Pendiente y Segunda Confirmada (Uso de Segunda Confirmación, KeyTiempo de Primera Creación)',
    'ConvTot=1, Conv14D=1, KeyTiempoReserva=20260906',
    CONCAT('ConvTot=', @ConvTot_S28, ', Conv14D=', @Conv14D_S28, ', KeyTiempoRes=', @KeyRes_S28),
    CASE WHEN @ConvTot_S28 = 1 AND @Conv14D_S28 = 1 AND @KeyRes_S28 = 20260906 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T19: Creación Dentro de 14 Días y Confirmación Fuera (Conversión 14D Distinta según Hito)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (29, 'HitoDiff', 'User', '955228833', 'hitodiff@test.pe', '2026-09-01 08:00:00');

-- Solicitud del 2026-09-01 10:00:00 (Evaluable = 1 al 2026-09-30)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (29, 29, 1, '2026-09-01 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (29, 29, 101, 150.00, 1, '2026-09-01 10:30:00');

-- Reserva creada a los 9 días (2026-09-10 <= 14d) y confirmada a los 21 días (2026-09-22 > 14d)
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (29, 29, 29, '2026-09-10 10:00:00', 'Confirmada', 1, '2026-09-22 10:00:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

-- Sub-caso A: Hito CreacionReserva -> Conv14D debe ser 1 (creación en 9 días <= 14 días)
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T19_CREA',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Conv14D_Crea INT = (SELECT LeadsConvertidosPayer14Dias FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 29);

-- Sub-caso B: Hito ConfirmacionReserva -> Conv14D debe ser 0 (confirmación en 21 días > 14 días)
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T19_CONF',
    @ConfigHitoConversion = 'ConfirmacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Conv14D_Conf INT = (SELECT LeadsConvertidosPayer14Dias FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 29);
DECLARE @ConvTot_Conf INT = (SELECT LeadsConvertidosPayerTotal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 29);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T19', 'Creación Dentro de 14 Días y Confirmación Fuera (Conversión 14D Distinta según Hito)',
    'CreacionReserva Conv14D=1 | ConfirmacionReserva Conv14D=0, ConvTot=1',
    CONCAT('Hito Creacion Conv14D=', @Conv14D_Crea, ' | Hito Conf Conv14D=', @Conv14D_Conf, ', ConvTot=', @ConvTot_Conf),
    CASE WHEN @Conv14D_Crea = 1 AND @Conv14D_Conf = 0 AND @ConvTot_Conf = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T20: Confirmación Posterior al Corte (No Acredita Conversión en ConfirmacionReserva)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (30, 'ConfPostCorte', 'User', '966338844', 'confpost@test.pe', '2026-09-15 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (30, 30, 1, '2026-09-15 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (30, 30, 101, 150.00, 1, '2026-09-15 10:30:00');

-- Reserva creada antes del corte (2026-09-20), pero confirmada el 2026-10-02 (posterior al corte 2026-09-30)
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (30, 30, 30, '2026-09-20 10:00:00', 'Confirmada', 1, '2026-10-02 10:00:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T20',
    @ConfigHitoConversion = 'ConfirmacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @ConvTot_S30 INT, @Conv14D_S30 INT, @KeyRes_S30 INT;
SELECT 
    @ConvTot_S30 = LeadsConvertidosPayerTotal,
    @Conv14D_S30 = LeadsConvertidosPayer14Dias,
    @KeyRes_S30  = KeyTiempoReserva
FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 30;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T20', 'Confirmación Posterior al Corte (No Acredita Conversión en Hito ConfirmacionReserva)',
    'ConvTot=0, Conv14D=0, KeyTiempoReserva=20260920',
    CONCAT('ConvTot=', @ConvTot_S30, ', Conv14D=', @Conv14D_S30, ', KeyTiempoRes=', @KeyRes_S30),
    CASE WHEN @ConvTot_S30 = 0 AND @Conv14D_S30 = 0 AND @KeyRes_S30 = 20260920 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T21: Confirmación Anómala sin Fecha o Anterior a Creación (No Acredita Conversión)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES 
(311, 'ConfSinFecha', 'User', '977448855', 'sinfecha@test.pe', '2026-09-05 08:00:00'),
(312, 'ConfAnterior', 'User', '977448866', 'anterior@test.pe', '2026-09-05 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES 
(311, 311, 1, '2026-09-05 10:00:00', 'En Negociacion'),
(312, 312, 1, '2026-09-05 10:00:00', 'En Negociacion');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES 
(311, 311, 101, 150.00, 1, '2026-09-05 10:30:00'),
(312, 312, 101, 150.00, 1, '2026-09-05 10:30:00');

-- 311: confirmacion_explicita = 1 pero fecha_confirmacion es NULL
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (311, 311, 311, '2026-09-06 10:00:00', 'Confirmada', 1, NULL);

-- 312: fecha_confirmacion anterior a la fecha_reserva (anomalía de confirmación previa a creación)
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_opcion, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (312, 312, 312, '2026-09-10 10:00:00', 'Confirmada', 1, '2026-09-08 10:00:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T21',
    @ConfigHitoConversion = 'ConfirmacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @ConvTot_311 INT = (SELECT LeadsConvertidosPayerTotal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 311);
DECLARE @ConvTot_312 INT = (SELECT LeadsConvertidosPayerTotal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 312);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T21', 'Confirmación Anómala sin Fecha o Anterior a Creación (No Acredita Conversión)',
    'S311 ConvTot=0, S312 ConvTot=0',
    CONCAT('S311: ', @ConvTot_311, ', S312: ', @ConvTot_312),
    CASE WHEN @ConvTot_311 = 0 AND @ConvTot_312 = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T22: Opción Posterior al Corte (No Altera Precio ni Selección de Opciones Elegibles)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (33, 'OpcPostCorte', 'User', '988558877', 'opcpost@test.pe', '2026-09-05 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (33, 33, 1, '2026-09-05 10:00:00', 'En Negociacion');

-- Opción 1: Ofrecida antes del corte (2026-09-06), seleccionada = 1, precio 250.00
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (331, 33, 101, 250.00, 1, '2026-09-06 10:30:00');

-- Opción 2: Ofrecida posterior al corte (2026-10-05), seleccionada = 1, precio 400.00
-- Si no estuviera filtrada por el corte, habría 2 seleccionadas y el precio resultaría NULL.
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (332, 33, 101, 400.00, 1, '2026-10-05 10:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T22',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @Precio_S33 DECIMAL(10,2) = (SELECT PrecioCotizado FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 33);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T22', 'Opción Posterior al Corte (No Altera Precio ni Selección de Opciones Elegibles)',
    'PrecioCotizado = 250.00 (Opción posterior al corte excluida)',
    CONCAT('PrecioCotizado: ', ISNULL(CAST(@Precio_S33 AS VARCHAR), 'NULL')),
    CASE WHEN @Precio_S33 = 250.00 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T23: Sede y Profesional Conocidos (Resolución a Claves Reales desde Disponibilidad)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES (34, 'SedeProfReal', 'User', '999668888', 'sedeprof@test.pe', '2026-09-05 08:00:00');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (34, 34, 3, '2026-09-05 10:00:00', 'En Negociacion');

-- Opción con id_disponibilidad = 103 (Sede 3: California, Profesional 3: Dr. Javier Vargas)
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (34, 34, 103, 500.00, 1, '2026-09-05 10:30:00');

USE Test_NexoSalud_Mart_Lead_Bateria;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T23',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @KeySede_S34 INT, @KeyProf_S34 INT;
SELECT @KeySede_S34 = KeySede, @KeyProf_S34 = KeyProfesional FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 34;

DECLARE @KeySede3_Esp INT = (SELECT KeySede FROM dbo.Dim_Sede WHERE id_sede = 3);
DECLARE @KeyProf3_Esp INT = (SELECT KeyProfesional FROM dbo.Dim_Profesional WHERE id_profesional = 3);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T23', 'Sede y Profesional Conocidos (Resolución a Claves Reales desde Disponibilidad)',
    CONCAT('KeySede = ', @KeySede3_Esp, ', KeyProfesional = ', @KeyProf3_Esp, ' (no 0 ni NULL)'),
    CONCAT('KeySede: ', @KeySede_S34, ', KeyProf: ', @KeyProf_S34),
    CASE WHEN @KeySede_S34 = @KeySede3_Esp AND @KeyProf_S34 = @KeyProf3_Esp AND @KeySede_S34 > 0 AND @KeyProf_S34 > 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO T24: Diagnóstico Controlado de Intervalos que Exceden Capacidad o INT Contractual (Sin Saturación/Truncamiento)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_Mart_Lead_Bateria;

-- Asegurar claves de fecha en Dim_Tiempo para solicitudes con fechas históricas extremas
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Tiempo WHERE KeyTiempo = 19500110)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
    INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha) VALUES (19500110, '1950-01-10');
    SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;
END;
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Tiempo WHERE KeyTiempo = 17500110)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
    INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha) VALUES (17500110, '1750-01-10');
    SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;
END;

USE Test_NexoSalud_OLTP_Lead_Bateria;
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, numero, email, fecha_registro)
VALUES 
(35, 'Antigua366', 'User', '911778899', 'antigua366@test.pe', '2025-01-10 08:00:00'),
(36, 'ExcesoCapacidadSinResp', 'User', '911778800', 'exceso_sinresp@test.pe', '1950-01-10 08:00:00'),
(37, 'ExcesoCapacidadConResp', 'User', '911778811', 'exceso_conresp@test.pe', '1750-01-10 08:00:00');

-- S35: Solicitud de enero 2025 (~628 días de antigüedad al corte 2026-09-30, sin respuestas)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (35, 35, 1, '2025-01-10 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (35, 35, 101, 150.00, 1, '2025-01-10 10:30:00');

-- S36: Solicitud con intervalo temporal extremo SIN respuesta atribuida
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (36, 36, 1, '1950-01-10 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (36, 36, 101, 150.00, 1, '1950-01-10 10:30:00');

-- S37: Solicitud con intervalo temporal extremo CON respuesta útil atribuida (debe dar EvidenciaInsuficiente, no Incumplida)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, fecha_solicitud, estado)
VALUES (37, 37, 1, '1750-01-10 10:00:00', 'En Negociacion');
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, seleccionada, fecha_ofrecida)
VALUES (37, 37, 101, 150.00, 1, '1750-01-10 10:30:00');
INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (37, 37, 1, '2026-09-01 10:00:00', 'LLAMADA_SALIENTE', 1, 'CONTACTADO');

USE Test_NexoSalud_Mart_Lead_Bateria;

-- Verificación directa de la función escalar: intervalos que exceden la capacidad del generador (>65,535 días) devuelven NULL
DECLARE @SegCapacidadExtrema INT = dbo.fn_CalcularSegundosHabiles('1800-01-01 08:00:00', '2100-01-01 18:00:00');

DECLARE @RC_T24 INT = -1;
EXEC @RC_T24 = dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte = '2026-09-30',
    @BatchId = 'BATCH_LEAD_T24',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';

DECLARE @SLA_S35 VARCHAR(30), @Seg_S35 INT, @Min_S35 INT, @Resp15M_S35 INT;
SELECT 
    @SLA_S35 = EstadoRespuestaSLA,
    @Seg_S35 = SegundosPrimeraRespuesta,
    @Min_S35 = MinutosPrimeraRespuesta,
    @Resp15M_S35 = LeadsRespuestaUtil15Min
FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 35;

DECLARE @SLA_S36 VARCHAR(30), @Seg_S36 INT, @Min_S36 INT, @Resp15M_S36 INT;
SELECT 
    @SLA_S36 = EstadoRespuestaSLA,
    @Seg_S36 = SegundosPrimeraRespuesta,
    @Min_S36 = MinutosPrimeraRespuesta,
    @Resp15M_S36 = LeadsRespuestaUtil15Min
FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 36;

DECLARE @SLA_S37 VARCHAR(30), @Seg_S37 INT, @Min_S37 INT, @Resp15M_S37 INT;
SELECT 
    @SLA_S37 = EstadoRespuestaSLA,
    @Seg_S37 = SegundosPrimeraRespuesta,
    @Min_S37 = MinutosPrimeraRespuesta,
    @Resp15M_S37 = LeadsRespuestaUtil15Min
FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 37;

DECLARE @DiagLogExiste INT = (
    SELECT COUNT(*) FROM dbo.Log_Ejecucion_ETL 
    WHERE BatchId = 'BATCH_LEAD_T24' 
      AND TipoEvento = 'ADVERTENCIA' 
      AND Mensaje LIKE '%Diagnóstico Controlado: Se detectaron intervalos temporales que exceden la capacidad%'
);

INSERT INTO #ResultadosPruebaLead VALUES (
    'T24', 'Diagnóstico Controlado de Intervalos Extremos (>Capacidad e INT) sin Saturación Artificial',
    'FnExtrema=NULL, S36_SLA=EvidenciaInsuficiente, S37(ConResp)_SLA=EvidenciaInsuficiente, Seg=NULL, DiagLog>=1',
    CONCAT('FnExtrema=', ISNULL(CAST(@SegCapacidadExtrema AS VARCHAR), 'NULL'), ', S36_SLA=', @SLA_S36, ', S37_SLA=', @SLA_S37, ', S37_Seg=', ISNULL(CAST(@Seg_S37 AS VARCHAR), 'NULL'), ', DiagLog=', @DiagLogExiste),
    CASE WHEN @RC_T24 = 0 
          AND @SegCapacidadExtrema IS NULL 
          AND @Seg_S35 IS NULL AND @SLA_S35 = 'EvidenciaInsuficiente'
          AND @Seg_S36 IS NULL AND @SLA_S36 = 'EvidenciaInsuficiente' AND @Resp15M_S36 = 0
          AND @Seg_S37 IS NULL AND @SLA_S37 = 'EvidenciaInsuficiente' AND @Resp15M_S37 = 0
          AND @DiagLogExiste >= 1 
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO
-- ----------------------------------------------------------------------------------------------------
-- CASO T25: Calendario con Intervalos Superpuestos o Ausente y Hito NULL (Aborto Defensivo con Diagnóstico)
-- ----------------------------------------------------------------------------------------------------
USE Test_NexoSalud_Mart_Lead_Bateria;

DECLARE @ErrHitoNullCapturado BIT = 0;
DECLARE @ErrOverlapCapturado BIT = 0;
DECLARE @ErrSinCalCapturado BIT = 0;

-- Sub-caso 1: Hito NULL aborta sin cambios en hechos
BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_LEAD_T25_NULL',
        @ConfigHitoConversion = NULL,
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%@ConfigHitoConversion es obligatorio%' SET @ErrHitoNullCapturado = 1;
END CATCH;

-- Sub-caso 2: Intervalo laborable superpuesto en dbo.Config_CalendarioAtencion_ETL
INSERT INTO dbo.Config_CalendarioAtencion_ETL (IdIntervalo, DiaSemana, HoraInicio, HoraFin, EsLaborable, Activo, DescripcionHorario)
VALUES (999, 1, '09:00:00', '12:00:00', 1, 1, 'Intervalo superpuesto de prueba');

BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_LEAD_T25_OVERLAP',
        @ConfigHitoConversion = 'CreacionReserva',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%intervalos laborables superpuestos%' SET @ErrOverlapCapturado = 1;
END CATCH;

-- Limpieza del intervalo superpuesto
DELETE FROM dbo.Config_CalendarioAtencion_ETL WHERE IdIntervalo = 999;

-- Sub-caso 3: Desactivar todos los intervalos laborables (ausencia de calendario activo)
UPDATE dbo.Config_CalendarioAtencion_ETL SET Activo = 0;

BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_NegociacionLead
        @FechaCorte = '2026-09-30',
        @BatchId = 'BATCH_LEAD_T25_SINCAL',
        @ConfigHitoConversion = 'CreacionReserva',
        @FuenteOLTP = 'Test_NexoSalud_OLTP_Lead_Bateria',
    @ConvencionHoraria = 'Local_Clinica_SinOffset';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%no contiene intervalos laborables activos%' SET @ErrSinCalCapturado = 1;
END CATCH;

-- Restaurar intervalos laborables activos
UPDATE dbo.Config_CalendarioAtencion_ETL SET Activo = 1;

INSERT INTO #ResultadosPruebaLead VALUES (
    'T25', 'Calendario Superpuesto, Ausente y Hito NULL (Aborto Defensivo con Diagnóstico)',
    'ErrHitoNull: 1, ErrOverlap: 1, ErrSinCal: 1',
    CONCAT('ErrHitoNull: ', @ErrHitoNullCapturado, ', ErrOverlap: ', @ErrOverlapCapturado, ', ErrSinCal: ', @ErrSinCalCapturado),
    CASE WHEN @ErrHitoNullCapturado = 1 AND @ErrOverlapCapturado = 1 AND @ErrSinCalCapturado = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ====================================================================================================
-- FASE 6: REPORTE CONSOLIDADO Y DICTAMEN DINÁMICO DE LA BATERÍA LEAD
-- ====================================================================================================
USE Test_NexoSalud_Mart_Lead_Bateria;

SELECT 
    CasoId AS [Caso],
    NombreCaso AS [Nombre del Escenario],
    ResultadoEsperado AS [Resultado Esperado],
    ResultadoObtenido AS [Resultado Obtenido],
    Estado AS [Veredicto]
FROM #ResultadosPruebaLead
ORDER BY CasoId;

DECLARE @TotalCasos INT = (SELECT COUNT(*) FROM #ResultadosPruebaLead);
DECLARE @CasosOk INT = (SELECT COUNT(*) FROM #ResultadosPruebaLead WHERE Estado = 'CORRECTO');
DECLARE @CasosFail INT = (SELECT COUNT(*) FROM #ResultadosPruebaLead WHERE Estado = 'FALLIDO');
DECLARE @CasosEsperados INT = 25;

PRINT '=================================================================================';
PRINT 'RESUMEN DE EJECUCIÓN BATERÍA PROCEDURAL LEAD:';
PRINT CONCAT('Casos Esperados  : ', @CasosEsperados);
PRINT CONCAT('Casos Ejecutados : ', @TotalCasos);
PRINT CONCAT('Casos Correctos  : ', @CasosOk);
PRINT CONCAT('Casos Fallidos   : ', @CasosFail);

IF @TotalCasos = @CasosEsperados AND @CasosFail = 0
BEGIN
    PRINT 'Dictamen Final   : BATERÍA LEAD APROBADA (25/25 CASOS SATISFACTORIOS)';
END
ELSE
BEGIN
    PRINT 'Dictamen Final   : BATERÍA LEAD CON FALLAS O CASOS PENDIENTES';
    RAISERROR('La batería procedural de LEAD no alcanzó la aprobación global.', 16, 1);
END;
PRINT '=================================================================================';
GO

-- ====================================================================================================
-- FASE 7: LIMPIEZA FINAL NO DESTRUCTIVA DEL ENTORNO DE PRUEBAS LEAD
-- ====================================================================================================
USE master;
GO

DECLARE @DbTestOLTP NVARCHAR(128) = N'Test_NexoSalud_OLTP_Lead_Bateria';
DECLARE @DbTestMart NVARCHAR(128) = N'Test_NexoSalud_Mart_Lead_Bateria';

-- Cierre limpio y eliminación exclusiva de las bases temporales creadas en esta ejecución
IF DB_ID(@DbTestOLTP) IS NOT NULL
BEGIN
    BEGIN TRY
        EXEC(N'DROP DATABASE ' + @DbTestOLTP + N';');
        PRINT '>> Base temporal [' + @DbTestOLTP + '] eliminada limpiamente.';
    END TRY
    BEGIN CATCH
        PRINT '>> ADVERTENCIA: No se pudo eliminar [' + @DbTestOLTP + '] por conexiones activas. Se conserva sin terminación forzada.';
    END CATCH;
END;

IF DB_ID(@DbTestMart) IS NOT NULL
BEGIN
    BEGIN TRY
        EXEC(N'DROP DATABASE ' + @DbTestMart + N';');
        PRINT '>> Base temporal [' + @DbTestMart + '] eliminada limpiamente.';
    END TRY
    BEGIN CATCH
        PRINT '>> ADVERTENCIA: No se pudo eliminar [' + @DbTestMart + '] por conexiones activas. Se conserva sin terminación forzada.';
    END CATCH;
END;
GO
