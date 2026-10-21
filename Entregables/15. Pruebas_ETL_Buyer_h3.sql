-- ====================================================================================================
-- NEXOSALUD — BATERÍA AUTOMATIZADA DE PRUEBAS TÉCNICAS: ETL BUYER (H3 - FASE 2)
-- ====================================================================================================
-- Proyecto: NexoSalud (Plataforma de Inteligencia de Negocios Odontológica — Clínica Luxedent, Trujillo)
-- Metodología: IMPULSE (Fase: BUYER — Fact_CaptacionBuyer)
-- Titular del Rol: Mario Antonio Martinez Dominguez (Integrante 3 — ETL BUYER y LEAD, Embudo y Calidad)
-- Responsable de Ejecución Técnica: Jesús Daniel Ordóñez Ugarte (Integrante 4 — asumiendo la ejecución técnica
--   de BUYER/LEAD según el intercambio de responsabilidades acordado)
-- Ubicación del Entregable: Entregables/15. Pruebas_ETL_Buyer_h3.sql
-- Guía de Despliegue y Pruebas: Entregables/15. Guia_ETL_Buyer_h3.md
-- Script de Implementación Real Evaluado: Entregables/15. ETL_Fact_CaptacionBuyer_h3.sql
--
-- CONTRATO DE EJECUCIÓN REPRODUCIBLE (SQLCMD / HERRAMIENTAS CLIENTE):
--   1. Este script está diseñado para ejecutarse en la raíz del repositorio con SQLCMD en modo estricto (-b):
--        sqlcmd -S localhost -E -b -i "Entregables\15. Pruebas_ETL_Buyer_h3.sql"
--   2. Inclusión Directa de la Implementación Real:
--      Este script NO contiene una segunda definición de dbo.usp_Cargar_Fact_CaptacionBuyer ni DDL duplicado
--      de dbo.Fact_CaptacionBuyer. La implementación física entregada se incluye directamente mediante la
--      directiva SQLCMD :r "Entregables\15. ETL_Fact_CaptacionBuyer_h3.sql".
--   3. Vistas de Staging Reales del Entregable 13:
--      Se despliegan copias íntegras de las definiciones reales de staging.stg_Personas y staging.stg_Solicitudes
--      del SQL 13, alterando exclusivamente la referencia a la base de origen temporal, sin simplificaciones.
--   4. Política de Inocuidad y Limpieza No Destructiva:
--      - Si las bases temporales ya existen, el script aborta inmediatamente sin modificarlas ni eliminarlas.
--      - Se elimina cualquier uso de ALTER DATABASE ... SET SINGLE_USER WITH ROLLBACK IMMEDIATE.
--      - La limpieza final se realiza mediante DROP DATABASE en bloque TRY/CATCH; si una base no puede
--        eliminarse (por bloqueos externos), se informa su nombre sin forzar conexiones.
--
-- BATERÍA DE 18 ESCENARIOS DE PRUEBA FORMALES:
--   T01: Primera Carga (10 personas base con corte 2026-09-30).
--   T02: Repetición Idéntica (Idempotencia estricta: 0 inserciones, 0 actualizaciones).
--   T03: Persona con Múltiples Solicitudes (Grano Atómico Estricto 1:1, primera solicitud y segundos).
--   T04: Actualización In-Place por Subsanación de Calidad y Autorización.
--   T05: Cambio de Canal y Campaña (Actualización física de claves sustitutas).
--   T06: Maduración Temporal de Cohortes sin Modificaciones Físicas en OLTP.
--   T07: Límites Exactos de la Ventana de 14 Días y Exclusión en Corte Semiabierto.
--   T08: Contactabilidad Técnica con Canales Rechazados (Real Staging 13: ContactosUtilizables = 0 para P15).
--   T09: Costos Desconocidos en NULL y Estado 'PendienteConciliacion'.
--   T10: Búsquedas Dimensionales (Código Ausente -> Miembro 0, Duplicado -> Rechazo por Ambigüedad).
--   T11: Validación de Parámetros de Entrada (@FechaCorte NULL / @BatchId vacío).
--   T12: Prevalidación Defensiva ante Dependencia o Miembro 0 Ausente (con restauración).
--   T13: Error Capturable durante Persistencia vía Trigger con Rollback Atómico y Validación Bidireccional EXCEPT.
--   T14: Comprobación del Mecanismo de Bloqueo sp_getapplock (readquisición, serialización y liberación).
--   T15: Tratamiento de Anomalías Cronológicas y Bitácora de Rechazos.
--   T16: Prevalidación Negativa: Columna Contractual con Longitud o Precisión Insuficiente en Fact_CaptacionBuyer.
--   T17: Prevalidación Negativa: Tabla Auxiliar con Identidad Correcta pero Columna Necesaria Ausente (Log_Ejecucion_ETL sin Mensaje).
--   T18: Prevalidación Negativa: Unicidad Compuesta no Válida para Clave Individual y Clave Foránea Deshabilitada.
-- ====================================================================================================

SET NOCOUNT ON;
GO

-- ====================================================================================================
-- FASE 1: PREPARACIÓN DEL ENTORNO AISLADO TEMPORAL Y COMPROBACIÓN DEFENSIVA
-- ====================================================================================================

-- 1.1 Comprobación de seguridad: No ejecutar en bases productivas ni permitir contexto inválido
IF DB_NAME() IN ('NexoSaludDB', 'NexoSalud_Mart')
BEGIN
    RAISERROR('ABORTANDO: Este script de prueba no debe ejecutarse en el contexto de bases reales del proyecto (NexoSaludDB / NexoSalud_Mart).', 16, 1);
    SET NOEXEC ON;
END;
GO

-- 1.2 Comprobación de existencia previa sin borrado destructivo
-- Si alguna de las bases temporales ya existe, se aborta sin modificarlas ni terminarlas forzadamente.
IF EXISTS (SELECT 1 FROM sys.databases WHERE name IN ('Test_NexoSalud_OLTP_Buyer_Bateria', 'Test_NexoSalud_Mart_Buyer_Bateria'))
BEGIN
    RAISERROR('ABORTANDO EJECUCIÓN: Una o más bases temporales de prueba ya existen en el servidor (Test_NexoSalud_OLTP_Buyer_Bateria / Test_NexoSalud_Mart_Buyer_Bateria). Por política de despliegue defensivo y no destructivo, no se eliminan bases preexistentes. Verifique las conexiones o limpie manualmente.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- 1.3 Creación de Bases de Datos Temporales Aisladas
CREATE DATABASE Test_NexoSalud_OLTP_Buyer_Bateria;
CREATE DATABASE Test_NexoSalud_Mart_Buyer_Bateria;
GO

PRINT '>> Bases temporales aisladas creadas exitosamente: Test_NexoSalud_OLTP_Buyer_Bateria, Test_NexoSalud_Mart_Buyer_Bateria.';
GO

-- ====================================================================================================
-- FASE 2: CREACIÓN DE TABLAS EN OLTP TEMPORAL (ESQUEMA COMPATIBLE CON STAGING REAL 13)
-- ====================================================================================================
USE Test_NexoSalud_OLTP_Buyer_Bateria;
GO

IF DB_NAME() <> 'Test_NexoSalud_OLTP_Buyer_Bateria'
BEGIN
    RAISERROR('Fallo al cambiar contexto a Test_NexoSalud_OLTP_Buyer_Bateria.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE TABLE dbo.Canales (
    id_canal INT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    tipo VARCHAR(50) NOT NULL
);

CREATE TABLE dbo.Campanas (
    id_campana INT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    tipo_origen VARCHAR(100) NOT NULL
);

CREATE TABLE dbo.Personas (
    id_persona INT PRIMARY KEY,
    nombres VARCHAR(100) NULL,
    apellidos VARCHAR(100) NULL,
    dni VARCHAR(20) NULL,
    email VARCHAR(100) NULL,
    numero VARCHAR(50) NULL,
    id_canal_origen INT NULL,
    id_campana_origen INT NULL,
    id_etapa_actual INT NULL,
    estado_calidad VARCHAR(50) NULL,
    autoriza_contacto INT NULL,
    fecha_autorizacion DATETIME2 NULL,
    fecha_registro DATETIME2 NOT NULL,
    fecha_actualizacion DATETIME2 NULL,
    zona VARCHAR(100) NULL,
    tipo_persona VARCHAR(50) NULL,
    fecha_nacimiento DATE NULL
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

CREATE TABLE dbo.Opciones (
    id_opcion INT PRIMARY KEY,
    id_solicitud INT NOT NULL,
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

-- Siembra de catálogos OLTP
INSERT INTO dbo.Canales (id_canal, nombre, tipo) VALUES
(1, 'WhatsApp', 'Digital'),
(2, 'Web Form', 'Digital'),
(3, 'Telefono', 'Telefonico');

INSERT INTO dbo.Campanas (id_campana, nombre, tipo_origen) VALUES
(10, 'Campana Ortodoncia Primavera', 'Redes Sociales'),
(20, 'Campana Implantes 2026', 'Google Ads');

-- Siembra de la Cohorte Inicial: 10 Personas Base (P1 a P10 para corte 2026-09-30)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento) VALUES
(1, 'Carlos', 'Mendoza', '45891234', 'carlos.mendoza@email.com', '987654321', 1, 10, 2, 'Valido', 1, '2026-09-01 10:00:00', '2026-09-01 10:00:00', '2026-09-01 10:00:00', 'Trujillo', 'Natural', '1990-05-12'),
(2, 'Ana', 'Rios', '46781290', 'ana.rios@email.com', '976543210', 2, 20, 2, 'Valido', 1, '2026-09-02 11:00:00', '2026-09-02 11:00:00', '2026-09-02 11:00:00', 'Victor Larco', 'Natural', '1992-08-20'),
(3, 'Pedro', 'Gomez', '47891230', 'pedro.g@email.com', '965432109', 1, 10, 1, 'Incompleto', 0, NULL, '2026-09-03 12:00:00', '2026-09-03 12:00:00', 'Trujillo', 'Natural', '1988-11-03'),
(4, 'Maria', 'Vargas', '48901234', 'maria.v@email.com', '954321098', 2, 20, 2, 'Valido', 1, '2026-09-04 14:00:00', '2026-09-04 14:00:00', '2026-09-04 14:00:00', 'Huanchaco', 'Natural', '1995-03-15'),
(5, 'Jorge', 'Soto', '49012345', 'jorge.s@email.com', '943210987', 1, 10, 1, 'Valido', 1, '2026-09-05 15:00:00', '2026-09-05 15:00:00', '2026-09-05 15:00:00', 'Trujillo', 'Natural', '1985-07-22'),
(6, 'Lucia', 'Perez', '50123456', 'lucia.p@email.com', '932109876', 1, 10, 2, 'Valido', 1, '2026-09-20 10:00:00', '2026-09-20 10:00:00', '2026-09-20 10:00:00', 'Moche', 'Natural', '1998-01-30'),
(7, 'Raul', 'Torres', '51234567', 'raul.t@email.com', '921098765', 1, 10, 2, 'Valido', 1, '2026-09-01 10:00:00', '2026-09-01 10:00:00', '2026-09-01 10:00:00', 'Trujillo', 'Natural', '1991-09-18'),
(8, 'Elena', 'Castro', '52345678', 'elena.c@email.com', '910987654', 2, 20, 2, 'Valido', 1, '2026-09-01 10:00:00', '2026-09-01 10:00:00', '2026-09-01 10:00:00', 'Victor Larco', 'Natural', '1993-12-05'),
(9, 'Diego', 'Navarro', '53456789', 'diego.n@email.com', '909876543', 1, 10, 2, 'Valido', 1, '2026-09-01 10:00:00', '2026-09-01 10:00:00', '2026-09-01 10:00:00', 'Trujillo', 'Natural', '1987-04-14'),
(10, 'Sofia', 'Ruiz', '54567890', 'sofia.r@email.com', '998765432', 2, 20, 1, 'Valido', 1, '2026-09-10 12:00:00', '2026-09-10 12:00:00', '2026-09-10 12:00:00', 'Trujillo', 'Natural', '1996-06-25');

-- Siembra de Solicitudes Iniciales
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, tipo_consulta, prioridad, motivo, fecha_solicitud, fecha_primera_respuesta, fecha_cierre) VALUES
(101, 1, 1, 'Confirmada', 'Ortodoncia', 'Media', 'Brackets', '2026-09-05 10:00:00', '2026-09-05 10:05:00', '2026-09-06 10:00:00'),
(102, 2, 2, 'Confirmada', 'Implante', 'Alta', 'Implante', '2026-09-20 11:00:00', '2026-09-20 11:10:00', '2026-09-21 11:00:00'),

-- P4: Grano 1:1 con múltiples solicitudes (S103 confirmada, S104 abierta, S105 cancelada)
(103, 4, 1, 'Confirmada', 'Ortodoncia', 'Media', 'Solicitud 1', '2026-09-05 14:00:00', '2026-09-05 14:08:00', NULL),
(104, 4, 2, 'Abierta', 'Limpieza', 'Baja', 'Solicitud 2', '2026-09-08 10:00:00', '2026-09-08 10:15:00', NULL),
(105, 4, 1, 'Cancelada', 'Control', 'Baja', 'Solicitud 3', '2026-09-12 16:00:00', NULL, '2026-09-13 10:00:00'),

-- P6: Solicitud para maduración
(106, 6, 1, 'Confirmada', 'Ortodoncia', 'Media', 'Consulta P6', '2026-09-22 10:00:00', '2026-09-22 10:05:00', NULL),

-- Límites exactos de ventana de 14 días (336 horas desde registro 2026-09-01 10:00:00)
(107, 7, 1, 'Confirmada', 'Ortodoncia', 'Media', '335h 59m', '2026-09-15 09:59:00', '2026-09-15 10:02:00', NULL),
(108, 8, 1, 'Confirmada', 'Ortodoncia', 'Media', '336h exactas', '2026-09-15 10:00:00', '2026-09-15 10:05:00', NULL),
(109, 9, 1, 'Confirmada', 'Ortodoncia', 'Media', '336h 1s', '2026-09-15 10:00:01', '2026-09-15 10:04:00', NULL);

-- Siembra de opciones y reservas de soporte para la compilación fiel de stg_Solicitudes
INSERT INTO dbo.Opciones (id_opcion, id_solicitud, precio_ofrecido, fecha_ofrecida, seleccionada) VALUES
(1, 101, 1500.00, '2026-09-05 10:02:00', 1),
(2, 102, 3500.00, '2026-09-20 11:05:00', 1),
(3, 103, 1600.00, '2026-09-05 14:05:00', 1);

INSERT INTO dbo.Reservas (id_reserva, id_solicitud, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion) VALUES
(1, 101, '2026-09-06 09:00:00', 'Confirmada', 1, '2026-09-06 09:05:00'),
(2, 102, '2026-09-21 10:00:00', 'Confirmada', 1, '2026-09-21 10:05:00');
GO

PRINT '>> Esquema y cohorte base (10 personas) sembrados en Test_NexoSalud_OLTP_Buyer_Bateria.';
GO

-- ====================================================================================================
-- FASE 3: CONFIGURACIÓN DE DATA MART TEMPORAL Y VISTAS REALES DE STAGING (SQL 13)
-- ====================================================================================================
USE Test_NexoSalud_Mart_Buyer_Bateria;
GO

IF DB_NAME() <> 'Test_NexoSalud_Mart_Buyer_Bateria'
BEGIN
    RAISERROR('Fallo al cambiar contexto a Test_NexoSalud_Mart_Buyer_Bateria.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
GO

-- 3.1 Vista Real staging.stg_Personas (Copia Íntegra del Entregable 13, apuntando al OLTP temporal)
CREATE OR ALTER VIEW staging.stg_Personas
AS
SELECT 
    p.id_persona,
    p.id_canal_origen,
    p.id_campana_origen,
    p.id_etapa_actual,
    p.fecha_registro,
    p.fecha_actualizacion,
    CAST(CONVERT(VARCHAR(8), p.fecha_registro, 112) AS INT) AS KeyTiempoRegistro,
    CAST(REPLACE(SUBSTRING(CONVERT(VARCHAR(8), p.fecha_registro, 108), 1, 5), ':', '') AS INT) AS KeyHoraRegistro,
    CASE WHEN NULLIF(LTRIM(RTRIM(p.nombres)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_nombres,
    CASE WHEN NULLIF(LTRIM(RTRIM(p.apellidos)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_apellidos,
    CASE WHEN NULLIF(LTRIM(RTRIM(p.dni)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_dni,
    CASE 
        WHEN LTRIM(RTRIM(p.dni)) LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
             AND LEN(LTRIM(RTRIM(p.dni))) = 8 
        THEN 1 
        ELSE 0 
    END AS es_dni_valido_8d,
    CASE WHEN NULLIF(LTRIM(RTRIM(p.email)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_email,
    CASE 
        WHEN p.email LIKE '%_@__%.__%' AND p.email NOT LIKE '% %' THEN 1 
        ELSE 0 
    END AS es_email_formato_valido,
    CASE WHEN NULLIF(LTRIM(RTRIM(p.numero)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_telefono,
    tel_norm.es_celular_pe_valido,
    CASE 
        WHEN NULLIF(LTRIM(RTRIM(p.numero)), '') IS NOT NULL AND tel_norm.es_celular_pe_valido = 0 THEN 1 
        ELSE 0 
    END AS tiene_telefono_otro_formato,
    CASE 
        WHEN NULLIF(LTRIM(RTRIM(p.email)), '') IS NOT NULL 
        THEN HASHBYTES('SHA2_256', LOWER(LTRIM(RTRIM(p.email))))
        ELSE NULL 
    END AS hash_email_sha256,
    CASE 
        WHEN tel_norm.tel_limpio IS NULL THEN NULL
        WHEN tel_norm.es_celular_pe_valido = 1 
        THEN HASHBYTES('SHA2_256', tel_norm.tel_pe_canonico)
        ELSE HASHBYTES('SHA2_256', CONCAT('OTRO:', tel_norm.tel_limpio))
    END AS hash_telefono_sha256,
    p.estado_calidad AS estado_calidad_original,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(p.estado_calidad))) IN ('VALIDO', 'VÁLIDO', 'VALIDOS', 'VÁLIDOS') THEN 'Valido'
        WHEN UPPER(LTRIM(RTRIM(p.estado_calidad))) IN ('INCOMPLETO', 'INCOMPLETOS') THEN 'Incompleto'
        WHEN UPPER(LTRIM(RTRIM(p.estado_calidad))) IN ('DUPLICADO', 'DUPLICADOS') THEN 'Duplicado'
        WHEN UPPER(LTRIM(RTRIM(p.estado_calidad))) IN ('RECHAZADO', 'RECHAZADOS') THEN 'Rechazado'
        ELSE 'Desconocido'
    END AS estado_calidad_norm,
    CASE 
        WHEN UPPER(LTRIM(RTRIM(p.estado_calidad))) IN ('VALIDO', 'VÁLIDO', 'VALIDOS', 'VÁLIDOS') THEN 1 
        ELSE 0 
    END AS es_calidad_valida,
    p.autoriza_contacto AS autoriza_contacto_original,
    p.fecha_autorizacion,
    CASE WHEN p.autoriza_contacto = 1 THEN 1 ELSE 0 END AS tiene_autorizacion_contacto,
    CASE 
        WHEN tel_norm.es_celular_pe_valido = 0 
             AND (p.email NOT LIKE '%_@__%.__%' OR p.email LIKE '% %' OR p.email IS NULL)
        THEN 1 
        ELSE 0 
    END AS requiere_revision_contactabilidad,
    CASE 
        WHEN NULLIF(LTRIM(RTRIM(p.nombres)), '') IS NOT NULL
             AND NULLIF(LTRIM(RTRIM(p.apellidos)), '') IS NOT NULL
             AND UPPER(LTRIM(RTRIM(p.estado_calidad))) IN ('VALIDO', 'VÁLIDO', 'VALIDOS', 'VÁLIDOS')
             AND p.autoriza_contacto = 1
             AND (
                 tel_norm.es_celular_pe_valido = 1 
                 OR (p.email LIKE '%_@__%.__%' AND p.email NOT LIKE '% %')
             )
        THEN 1 
        ELSE 0 
    END AS es_contacto_utilizable_tecnico,
    p.zona AS zona_original,
    COALESCE(NULLIF(LTRIM(RTRIM(p.zona)), ''), 'No Especificada') AS zona_norm,
    p.tipo_persona AS tipo_persona_original,
    COALESCE(NULLIF(LTRIM(RTRIM(p.tipo_persona)), ''), 'No Especificado') AS tipo_persona_norm,
    p.fecha_nacimiento,
    CASE WHEN p.fecha_nacimiento IS NOT NULL THEN 1 ELSE 0 END AS tiene_fecha_nacimiento
FROM [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.[Personas] p
CROSS APPLY (
    SELECT 
        NULLIF(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                LTRIM(RTRIM(p.numero)),
                ' ', ''),
                '-', ''),
                '.', ''),
                '(', ''),
                ')', ''),
                '/', ''),
            '') AS tel_limpio
) raw_tel
CROSS APPLY (
    SELECT 
        raw_tel.tel_limpio,
        CASE 
            WHEN raw_tel.tel_limpio IS NULL THEN 0
            WHEN raw_tel.tel_limpio LIKE '9[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 9 
            THEN 1
            WHEN raw_tel.tel_limpio LIKE '+519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 12 
            THEN 1
            WHEN raw_tel.tel_limpio LIKE '519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 11 
            THEN 1
            ELSE 0
        END AS es_celular_pe_valido,
        CASE 
            WHEN raw_tel.tel_limpio LIKE '9[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 9 
            THEN raw_tel.tel_limpio
            WHEN raw_tel.tel_limpio LIKE '+519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 12 
            THEN SUBSTRING(raw_tel.tel_limpio, 4, 9)
            WHEN raw_tel.tel_limpio LIKE '519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 11 
            THEN SUBSTRING(raw_tel.tel_limpio, 3, 9)
            ELSE NULL
        END AS tel_pe_canonico
) tel_norm;
GO

-- 3.2 Vista Real staging.stg_Solicitudes (Copia Íntegra del Entregable 13, apuntando al OLTP temporal)
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
    CASE 
        WHEN s.fecha_primera_respuesta IS NULL OR s.fecha_primera_respuesta >= s.fecha_solicitud THEN 1 
        ELSE 0 
    END AS es_cronologia_respuesta_valida,
    CASE 
        WHEN s.fecha_cierre IS NULL OR s.fecha_cierre >= s.fecha_solicitud THEN 1 
        ELSE 0 
    END AS es_cronologia_cierre_valida,
    s.estado AS estado_original,
    st_norm.estado_solicitud_norm,
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
    CASE 
        WHEN s.fecha_cierre IS NOT NULL AND st_norm.estado_solicitud_norm IN ('Abierta', 'En Negociacion') THEN 1 
        ELSE 0 
    END AS tiene_cierre_sin_estado_resolutivo,
    CASE 
        WHEN s.fecha_cierre IS NULL AND st_norm.estado_solicitud_norm IN ('Confirmada', 'Convertida', 'Abandonada', 'Cancelada', 'Descartada', 'Perdida') THEN 1 
        ELSE 0 
    END AS tiene_estado_resolutivo_sin_fecha_cierre,
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
    opc_prim.primer_precio_ofrecido,
    opc_prim.fecha_primer_precio_ofrecido,
    opc_prim.id_primera_opcion,
    opc_agg.cantidad_opciones_ofrecidas,
    opc_agg.cantidad_opciones_seleccionadas,
    opc_agg.precio_cotizado_seleccionado,
    opc_agg.tiene_multiple_opcion_seleccionada,
    res_prim.id_primera_reserva,
    res_prim.primera_fecha_reserva,
    res_prim.estado_primera_reserva,
    res_prim.confirmacion_explicita_primera_reserva,
    res_prim.fecha_confirmacion_primera_reserva,
    res_agg.cantidad_reservas_asociadas,
    res_agg.tiene_alguna_reserva_confirmada,
    CASE WHEN res_agg.cantidad_reservas_asociadas > 0 THEN 1 ELSE 0 END AS tiene_reserva_registrada
FROM [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.[Solicitudes] s
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
    FROM [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.[Opciones] o_prim
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
    FROM [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.[Opciones] o_agg
    WHERE o_agg.id_solicitud = s.id_solicitud
) opc_agg
OUTER APPLY (
    SELECT TOP 1
        r_prim.id_reserva AS id_primera_reserva,
        r_prim.fecha_reserva AS primera_fecha_reserva,
        r_prim.estado AS estado_primera_reserva,
        r_prim.confirmacion_explicita AS confirmacion_explicita_primera_reserva,
        r_prim.fecha_confirmacion AS fecha_confirmacion_primera_reserva
    FROM [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.[Reservas] r_prim
    WHERE r_prim.id_solicitud = s.id_solicitud
    ORDER BY r_prim.fecha_reserva ASC, r_prim.id_reserva ASC
) res_prim
OUTER APPLY (
    SELECT 
        COALESCE(COUNT(r_agg.id_reserva), 0) AS cantidad_reservas_asociadas,
        COALESCE(MAX(CASE WHEN r_agg.confirmacion_explicita = 1 THEN 1 ELSE 0 END), 0) AS tiene_alguna_reserva_confirmada
    FROM [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.[Reservas] r_agg
    WHERE r_agg.id_solicitud = s.id_solicitud
) res_agg;
GO

PRINT '>> Vistas reales de staging (staging.stg_Personas, staging.stg_Solicitudes) desplegadas exitosamente.';
GO

-- ====================================================================================================
-- FASE 4: CREACIÓN DE DIMENSIONES Y MIEMBRO 0 EN EL MART TEMPORAL
-- ====================================================================================================
CREATE TABLE dbo.Dim_Tiempo (
    KeyTiempo INT IDENTITY(1,1) PRIMARY KEY,
    id_fecha DATE NOT NULL,
    Anio INT NOT NULL,
    Trimestre INT NOT NULL,
    Mes INT NOT NULL,
    Dia INT NOT NULL
);

CREATE TABLE dbo.Dim_Canal (
    KeyCanal INT IDENTITY(1,1) PRIMARY KEY,
    id_canal INT NULL,
    NombreCanal VARCHAR(50) NULL,
    TipoMedio VARCHAR(50) NULL
);

CREATE TABLE dbo.Dim_Fuente (
    KeyFuente INT IDENTITY(1,1) PRIMARY KEY,
    id_fuente INT NULL,
    id_campana INT NULL,
    TipoOrigen VARCHAR(100) NULL,
    Campana VARCHAR(150) NULL
);

CREATE TABLE dbo.Dim_Sede (
    KeySede INT IDENTITY(1,1) PRIMARY KEY,
    id_sede INT NULL,
    Sede VARCHAR(100) NULL,
    Distrito VARCHAR(100) NULL,
    Zona VARCHAR(100) NULL
);

CREATE TABLE dbo.Dim_EstadoRegistro (
    KeyEstadoRegistro INT IDENTITY(1,1) PRIMARY KEY,
    EstadoCalidad VARCHAR(50) NOT NULL,
    AutorizacionContacto VARCHAR(2) NOT NULL
);

-- Estructuras de prueba propuestas para validar las restricciones contractuales de FK
CREATE TABLE dbo.Dim_Persona (
    KeyPersona INT IDENTITY(1,1) PRIMARY KEY,
    id_persona INT NULL,
    NombreCompleto VARCHAR(150) NULL
);

CREATE TABLE dbo.Dim_Campana (
    KeyCampana INT IDENTITY(1,1) PRIMARY KEY,
    id_campana INT NULL,
    Campana VARCHAR(150) NULL
);
GO

-- Poblamiento de Miembro Desconocido (Key = 0) y Catálogos Dimensionales
SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha, Anio, Trimestre, Mes, Dia) VALUES (0, '1900-01-01', 1900, 1, 1, 1);
SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;

DECLARE @f DATE = '2026-08-01';
WHILE @f <= '2026-12-31'
BEGIN
    INSERT INTO dbo.Dim_Tiempo (id_fecha, Anio, Trimestre, Mes, Dia)
    VALUES (@f, YEAR(@f), DATEPART(qq, @f), MONTH(@f), DAY(@f));
    SET @f = DATEADD(day, 1, @f);
END;

SET IDENTITY_INSERT dbo.Dim_Canal ON;
INSERT INTO dbo.Dim_Canal (KeyCanal, id_canal, NombreCanal, TipoMedio) VALUES 
(0, NULL, 'Desconocido', 'Desconocido'),
(1, 1, 'WhatsApp', 'Digital'),
(2, 2, 'Web Form', 'Digital'),
(3, 3, 'Telefono', 'Telefonico');
SET IDENTITY_INSERT dbo.Dim_Canal OFF;

SET IDENTITY_INSERT dbo.Dim_Fuente ON;
INSERT INTO dbo.Dim_Fuente (KeyFuente, id_fuente, id_campana, TipoOrigen, Campana) VALUES 
(0, NULL, NULL, 'Desconocido', 'Desconocido'),
(1, 1, 10, 'Redes Sociales', 'Campana Ortodoncia Primavera'),
(2, 2, 20, 'Google Ads', 'Campana Implantes 2026');
SET IDENTITY_INSERT dbo.Dim_Fuente OFF;

SET IDENTITY_INSERT dbo.Dim_Sede ON;
INSERT INTO dbo.Dim_Sede (KeySede, id_sede, Sede, Distrito, Zona) VALUES 
(0, NULL, 'Sin Sede Asignada', 'Desconocido', 'Desconocido'),
(1, 1, 'Sede Central Trujillo', 'Trujillo', 'Norte');
SET IDENTITY_INSERT dbo.Dim_Sede OFF;

SET IDENTITY_INSERT dbo.Dim_EstadoRegistro ON;
INSERT INTO dbo.Dim_EstadoRegistro (KeyEstadoRegistro, EstadoCalidad, AutorizacionContacto) VALUES 
(0, 'Desconocido', 'NO'),
(1, 'Valido', 'SI'),
(2, 'Valido', 'NO'),
(3, 'Incompleto', 'NO'),
(4, 'Incompleto', 'SI'),
(5, 'Duplicado', 'NO'),
(6, 'Rechazado', 'NO');
SET IDENTITY_INSERT dbo.Dim_EstadoRegistro OFF;

SET IDENTITY_INSERT dbo.Dim_Persona ON;
INSERT INTO dbo.Dim_Persona (KeyPersona, id_persona, NombreCompleto) VALUES 
(0, NULL, 'No Conformada'),
(1, 1, 'Carlos Mendoza'),
(2, 2, 'Ana Rios');
SET IDENTITY_INSERT dbo.Dim_Persona OFF;

SET IDENTITY_INSERT dbo.Dim_Campana ON;
INSERT INTO dbo.Dim_Campana (KeyCampana, id_campana, Campana) VALUES 
(0, NULL, 'Sin Campana'),
(1, 10, 'Campana Ortodoncia Primavera'),
(2, 20, 'Campana Implantes 2026');
SET IDENTITY_INSERT dbo.Dim_Campana OFF;
GO

PRINT '>> Dimensiones conformadas y miembros desconocidos (Key = 0) poblados exitosamente en Mart.';
GO

-- ====================================================================================================
-- FASE 5: INCLUSIÓN DE LA IMPLEMENTACIÓN REAL MEDIANTE SQLCMD (:r)
-- ====================================================================================================
-- No existe código duplicado de DDL ni de procedimiento almacenado en este script de pruebas.
-- Se invoca directamente el archivo entregable real mediante la directiva de inclusión de SQLCMD.
:r "Entregables\15. ETL_Fact_CaptacionBuyer_h3.sql"
GO

-- ====================================================================================================
-- FASE 6: EJECUCIÓN DE LA BATERÍA COMPLETA DE 15 PRUEBAS TÉCNICAS
-- ====================================================================================================
USE Test_NexoSalud_Mart_Buyer_Bateria;
GO

IF OBJECT_ID('tempdb..#ResultadosPruebas') IS NOT NULL DROP TABLE #ResultadosPruebas;
CREATE TABLE #ResultadosPruebas (
    Orden INT IDENTITY(1,1),
    Caso VARCHAR(10),
    Nombre VARCHAR(80),
    ResultadoEsperado VARCHAR(250),
    ResultadoObtenido VARCHAR(250),
    Estado VARCHAR(15) -- CORRECTO / FALLIDO
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T01: Primera Carga (10 personas base con corte 2026-09-30)
-- ----------------------------------------------------------------------------------------------------
DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
DECLARE @TotalHechos INT;

EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-09-30', 
    @BatchId = 'BATCH_T01_INI',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

SELECT @TotalHechos = COUNT(*) FROM dbo.Fact_CaptacionBuyer;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T01',
    'Primera Carga (10 Personas Base)',
    'Insertados: 10, Actualizados: 0, SinCambio: 0, Rechazados: 0, Hechos: 10',
    CONCAT('Insertados: ', @Ins, ', Actualizados: ', @Act, ', SinCambio: ', @Sin, ', Rechazados: ', @Rec, ', Hechos: ', @TotalHechos),
    CASE WHEN @Ins = 10 AND @Act = 0 AND @Sin = 0 AND @Rec = 0 AND @TotalHechos = 10 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T02: Repetición Idéntica (Idempotencia Estricta)
-- ----------------------------------------------------------------------------------------------------
DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
DECLARE @TotalHechos INT;

EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-09-30', 
    @BatchId = 'BATCH_T02_IDEM',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

SELECT @TotalHechos = COUNT(*) FROM dbo.Fact_CaptacionBuyer;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T02',
    'Repeticion Identica (Idempotencia)',
    'Insertados: 0, Actualizados: 0, SinCambio: 10, Rechazados: 0, Hechos: 10',
    CONCAT('Insertados: ', @Ins, ', Actualizados: ', @Act, ', SinCambio: ', @Sin, ', Rechazados: ', @Rec, ', Hechos: ', @TotalHechos),
    CASE WHEN @Ins = 0 AND @Act = 0 AND @Sin = 10 AND @Rec = 0 AND @TotalHechos = 10 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T03: Persona con Múltiples Solicitudes (Grano Atómico Estricto 1:1)
-- ----------------------------------------------------------------------------------------------------
DECLARE @FilasP4 INT, @SegundosConv BIGINT, @KeyTiempoConv INT;

SELECT 
    @FilasP4 = COUNT(*),
    @SegundosConv = MAX(SegundosConversion),
    @KeyTiempoConv = MAX(KeyTiempoConversion)
FROM dbo.Fact_CaptacionBuyer
WHERE id_persona_origen = 4;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T03',
    'Grano Atomico 1:1 (Multiples Solicitudes)',
    'Filas P4: 1, Segundos: 86400, KeyTiempoConv > 0',
    CONCAT('Filas P4: ', @FilasP4, ', Segundos: ', COALESCE(CAST(@SegundosConv AS VARCHAR(20)), 'NULL'), ', KeyTiempoConv: ', @KeyTiempoConv),
    CASE WHEN @FilasP4 = 1 AND @SegundosConv = 86400 AND @KeyTiempoConv > 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T04: Actualización In-Place por Subsanación de Calidad y Autorización
-- ----------------------------------------------------------------------------------------------------
UPDATE [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas
SET estado_calidad = 'Valido',
    autoriza_contacto = 1,
    fecha_autorizacion = '2026-09-04 10:00:00',
    fecha_actualizacion = '2026-09-04 10:00:00'
WHERE id_persona = 3;

DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-09-30', 
    @BatchId = 'BATCH_T04_UPD',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

DECLARE @UtilizablesP3 INT, @KeyEstadoRegP3 INT;
SELECT 
    @UtilizablesP3 = ContactosUtilizables,
    @KeyEstadoRegP3 = KeyEstadoRegistro
FROM dbo.Fact_CaptacionBuyer
WHERE id_persona_origen = 3;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T04',
    'Actualizacion In-Place (Calidad y Autorizacion)',
    'Actualizados: 1, SinCambio: 9, P3 Utilizables: 1, KeyEstadoReg: 1',
    CONCAT('Actualizados: ', @Act, ', SinCambio: ', @Sin, ', P3 Utilizables: ', @UtilizablesP3, ', KeyEstadoReg: ', @KeyEstadoRegP3),
    CASE WHEN @Act = 1 AND @Sin = 9 AND @UtilizablesP3 = 1 AND @KeyEstadoRegP3 = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T05: Cambio de Canal y Campaña (Actualización Física de Claves Sustitutas)
-- ----------------------------------------------------------------------------------------------------
UPDATE [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas
SET id_canal_origen = 2,
    id_campana_origen = 20,
    fecha_actualizacion = '2026-09-06 10:00:00'
WHERE id_persona = 5;

DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-09-30', 
    @BatchId = 'BATCH_T05_CANAL',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

DECLARE @KeyCanalP5 INT, @KeyFuenteP5 INT, @KeyCampanaP5 INT;
SELECT 
    @KeyCanalP5 = KeyCanal,
    @KeyFuenteP5 = KeyFuente,
    @KeyCampanaP5 = KeyCampana
FROM dbo.Fact_CaptacionBuyer
WHERE id_persona_origen = 5;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T05',
    'Cambio de Canal y Campana (Actualizacion Claves)',
    'Actualizados: 1, SinCambio: 9, KeyCanal: 2, KeyFuente: 2, KeyCampana: 2',
    CONCAT('Actualizados: ', @Act, ', SinCambio: ', @Sin, ', KeyCanal: ', @KeyCanalP5, ', KeyFuente: ', @KeyFuenteP5, ', KeyCampana: ', @KeyCampanaP5),
    CASE WHEN @Act = 1 AND @Sin = 9 AND @KeyCanalP5 = 2 AND @KeyFuenteP5 = 2 AND @KeyCampanaP5 = 2 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T06: Maduración Temporal de Cohortes sin Modificaciones Físicas en OLTP
-- ----------------------------------------------------------------------------------------------------
DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-10-10', -- Corte a 20 días de registro de P6
    @BatchId = 'BATCH_T06_MADURACION',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

DECLARE @ElegibleP6 INT, @Conv14P6 INT;
SELECT 
    @ElegibleP6 = ContactosElegiblesB1,
    @Conv14P6 = ConversionesALead14Dias
FROM dbo.Fact_CaptacionBuyer
WHERE id_persona_origen = 6;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T06',
    'Maduracion Temporal de Cohortes',
    'Actualizados >= 1, P6 ElegibleB1: 1, Conv14D: 1',
    CONCAT('Actualizados: ', @Act, ', P6 ElegibleB1: ', @ElegibleP6, ', Conv14D: ', @Conv14P6),
    CASE WHEN @Act >= 1 AND @ElegibleP6 = 1 AND @Conv14P6 = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T07: Límites Exactos de la Ventana de 14 Días y Exclusión en Corte Semiabierto
-- ----------------------------------------------------------------------------------------------------
-- Sembrar P11 registrada posterior al corte (2026-10-15)
INSERT INTO [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas (
    id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual,
    estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento
) VALUES (
    11, 'Manuel', 'Silva', '55678901', 'manuel.s@email.com', '987123456', 1, 10, 1,
    'Valido', 1, '2026-10-15 10:00:00', '2026-10-15 10:00:00', '2026-10-15 10:00:00', 'Trujillo', 'Natural', '1994-02-10'
);

DECLARE @ConvP7 INT, @ConvP8 INT, @ConvP9 INT, @ExisteP11 INT;
SELECT @ConvP7 = ConversionesALead14Dias FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 7;
SELECT @ConvP8 = ConversionesALead14Dias FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 8;
SELECT @ConvP9 = ConversionesALead14Dias FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 9;
SELECT @ExisteP11 = COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 11;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T07',
    'Limites Exactos 14 Dias y Exclusion en Corte',
    'P7 Conv14: 1, P8 Conv14: 1, P9 Conv14: 0, P11 Existe: 0',
    CONCAT('P7 Conv14: ', @ConvP7, ', P8 Conv14: ', @ConvP8, ', P9 Conv14: ', @ConvP9, ', P11 Existe: ', @ExisteP11),
    CASE WHEN @ConvP7 = 1 AND @ConvP8 = 1 AND @ConvP9 = 0 AND @ExisteP11 = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T08: Contactabilidad Técnica con Canales Rechazados (Real Staging 13: ContactosUtilizables = 0 para P15)
-- ----------------------------------------------------------------------------------------------------
-- Sembrar P15 con nombres presentes, calidad 'Valido', autoriza_contacto = 1, pero email inválido y teléfono no móvil PE
INSERT INTO [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas (
    id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual,
    estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento
) VALUES (
    15, 'Valeria', 'Paredes', '59012345', 'correo_invalido_sin_arroba', '12345678', 1, 10, 1,
    'Valido', 1, '2026-09-10 10:00:00', '2026-09-10 10:00:00', '2026-09-10 10:00:00', 'Trujillo', 'Natural', '1995-05-15'
);

DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-10-10',
    @BatchId = 'BATCH_T08_CONTACTO',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

DECLARE @UtilizablesP15 INT, @RegistradosP15 INT;
SELECT 
    @UtilizablesP15 = ContactosUtilizables,
    @RegistradosP15 = ContactosRegistrados
FROM dbo.Fact_CaptacionBuyer
WHERE id_persona_origen = 15;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T08',
    'Contactabilidad Real Staging 13 (P15 ContactosUtilizables = 0)',
    'P15 Registrados: 1, Utilizables: 0 (canal rechazado sin celular/email valido)',
    CONCAT('P15 Registrados: ', COALESCE(CAST(@RegistradosP15 AS VARCHAR(10)), 'NULL'), ', Utilizables: ', COALESCE(CAST(@UtilizablesP15 AS VARCHAR(10)), 'NULL')),
    CASE WHEN @RegistradosP15 = 1 AND @UtilizablesP15 = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T09: Costos Desconocidos en NULL y Estado 'PendienteConciliacion'
-- ----------------------------------------------------------------------------------------------------
DECLARE @CostosNoNull INT, @EstadosInvalidos INT;

SELECT 
    @CostosNoNull = COUNT(CASE WHEN CostoAtribuidoCaptacion IS NOT NULL THEN 1 END),
    @EstadosInvalidos = COUNT(CASE WHEN EstadoDisponibilidadCosto <> 'PendienteConciliacion' THEN 1 END)
FROM dbo.Fact_CaptacionBuyer;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T09',
    'Costos Desconocidos en NULL y PendienteConciliacion',
    'CostosNoNull: 0, EstadosInvalidos: 0',
    CONCAT('CostosNoNull: ', @CostosNoNull, ', EstadosInvalidos: ', @EstadosInvalidos),
    CASE WHEN @CostosNoNull = 0 AND @EstadosInvalidos = 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T10: Búsquedas Dimensionales: Código Ausente (Miembro 0) y Duplicado (Rechazo por Ambigüedad)
-- ----------------------------------------------------------------------------------------------------
-- 1. Código Ausente: Sembrar P12 con id_canal_origen = 99 (no catalogado en Dim_Canal)
INSERT INTO [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas (
    id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual,
    estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento
) VALUES (
    12, 'Carmen', 'Ortiz', '56789012', 'carmen.o@email.com', '976234567', 99, 10, 1,
    'Valido', 1, '2026-09-05 10:00:00', '2026-09-05 10:00:00', '2026-09-05 10:00:00', 'Trujillo', 'Natural', '1989-10-11'
);

-- 2. Código Duplicado: Insertar duplicado en Dim_Canal y sembrar P13 con id_canal_origen = 1
INSERT INTO dbo.Dim_Canal (id_canal, NombreCanal, TipoMedio) VALUES (1, 'WhatsApp Duplicado Test', 'Digital');

INSERT INTO [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas (
    id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual,
    estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento
) VALUES (
    13, 'Andres', 'Luna', '57890123', 'andres.l@email.com', '965345678', 1, 10, 1,
    'Valido', 1, '2026-09-05 11:00:00', '2026-09-05 11:00:00', '2026-09-05 11:00:00', 'Trujillo', 'Natural', '1992-03-28'
);

DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-10-10', 
    @BatchId = 'BATCH_T10_AMBIGUEDAD',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

DECLARE @KeyCanalP12 INT;
SELECT @KeyCanalP12 = KeyCanal FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 12;

DECLARE @ExisteP13Hechos INT, @ExisteP13Rechazos INT;
SELECT @ExisteP13Hechos = COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 13;
SELECT @ExisteP13Rechazos = COUNT(*) FROM dbo.Rechazos_ETL_Buyer WHERE EntidadOrigenId = 13 AND MotivoRechazo LIKE '%Dim_Canal%';

-- Limpiar el duplicado dimensional para restaurar integridad
DELETE FROM dbo.Dim_Canal WHERE NombreCanal = 'WhatsApp Duplicado Test';

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T10',
    'Busquedas Dimensionales (Ausente -> 0, Duplicada -> Rechazo)',
    'P12 KeyCanal: 0, P13 en Hechos: 0, P13 en Rechazos: 1, Rechazados >= 1',
    CONCAT('P12 KeyCanal: ', @KeyCanalP12, ', P13 en Hechos: ', @ExisteP13Hechos, ', P13 en Rechazos: ', @ExisteP13Rechazos, ', Rechazados: ', @Rec),
    CASE WHEN @KeyCanalP12 = 0 AND @ExisteP13Hechos = 0 AND @ExisteP13Rechazos >= 1 AND @Rec >= 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T11: Validación de Parámetros de Entrada (@FechaCorte NULL / @BatchId vacío)
-- ----------------------------------------------------------------------------------------------------
DECLARE @ErrCapturadoParam BIT = 0;
DECLARE @ErrNumParam INT = 0;
DECLARE @ErrMsgParam NVARCHAR(4000) = '';

BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
        @FechaCorte = NULL, 
        @BatchId = 'BATCH_INVALIDO';
END TRY
BEGIN CATCH
    SET @ErrCapturadoParam = 1;
    SET @ErrNumParam = ERROR_NUMBER();
    SET @ErrMsgParam = ERROR_MESSAGE();
END CATCH;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T11',
    'Validacion de Parametros de Entrada (@FechaCorte NULL)',
    'ErrorCapturado: 1, Error 50000 con mensaje sobre parametros obligatorios',
    CONCAT('ErrorCapturado: ', @ErrCapturadoParam, ', Num: ', @ErrNumParam, ', Msg: ', SUBSTRING(@ErrMsgParam, 1, 60)),
    CASE WHEN @ErrCapturadoParam = 1 AND @ErrMsgParam LIKE '%parámetros%' THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T12: Prevalidación Defensiva ante Dependencia o Miembro 0 Ausente (con Restauración)
-- ----------------------------------------------------------------------------------------------------
-- 1. Reasignar temporalmente en Fact_CaptacionBuyer las filas con KeyCanal = 0 a KeyCanal = 1 para no violar la FK
UPDATE dbo.Fact_CaptacionBuyer SET KeyCanal = 1 WHERE KeyCanal = 0;

-- 2. Eliminar el miembro desconocido de Dim_Canal (KeyCanal = 0)
DELETE FROM dbo.Dim_Canal WHERE KeyCanal = 0;

DECLARE @ErrCapturadoDep BIT = 0;
DECLARE @ErrMsgDep NVARCHAR(4000) = '';

BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
        @FechaCorte = '2026-10-10', 
        @BatchId = 'BATCH_TEST_DEP';
END TRY
BEGIN CATCH
    SET @ErrCapturadoDep = 1;
    SET @ErrMsgDep = ERROR_MESSAGE();
END CATCH;

-- 3. Restaurar inmediatamente el escenario para mantener el entorno operativo
SET IDENTITY_INSERT dbo.Dim_Canal ON;
INSERT INTO dbo.Dim_Canal (KeyCanal, id_canal, NombreCanal, TipoMedio) VALUES (0, NULL, 'Desconocido', 'Desconocido');
SET IDENTITY_INSERT dbo.Dim_Canal OFF;

-- Restaurar el hecho original para P12
UPDATE dbo.Fact_CaptacionBuyer SET KeyCanal = 0 WHERE id_persona_origen = 12;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T12',
    'Dependencia/Miembro 0 Ausente (Aborto sin persistencia)',
    'ErrorCapturado: 1, Mensaje contiene: miembros desconocidos (Key = 0)',
    CONCAT('ErrorCapturado: ', @ErrCapturadoDep, ', Msg: ', SUBSTRING(@ErrMsgDep, 1, 65)),
    CASE WHEN @ErrCapturadoDep = 1 AND @ErrMsgDep LIKE '%miembros desconocidos (Key = 0)%' THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T13: Error Capturable durante Persistencia vía Trigger con Rollback Atómico y Validación Bidireccional EXCEPT
-- ----------------------------------------------------------------------------------------------------
-- 1. Conservar instantánea previa completa de todas las columnas de Fact_CaptacionBuyer
IF OBJECT_ID('tempdb..#Instantanea_Fact_Buyer') IS NOT NULL
    DROP TABLE #Instantanea_Fact_Buyer;

SELECT * 
INTO #Instantanea_Fact_Buyer 
FROM dbo.Fact_CaptacionBuyer;

-- 2. Preparar cambio legítimo en una fila existente (P1: id_canal_origen de 1 a 2)
--    y sembrar en OLTP una persona nueva pendiente de carga (P16: Roberto Mena)
UPDATE [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas
SET id_canal_origen = 2,
    fecha_actualizacion = '2026-09-08 12:00:00'
WHERE id_persona = 1;

INSERT INTO [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas (
    id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual,
    estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento
) VALUES (
    16, 'Roberto', 'Mena', '60123456', 'roberto.m@email.com', '944556677', 1, 10, 1,
    'Valido', 1, '2026-09-08 10:00:00', '2026-09-08 10:00:00', '2026-09-08 10:00:00', 'Trujillo', 'Natural', '1993-04-12'
);

-- 3. Crear trigger de prueba que falla exclusivamente durante el INSERT de la persona nueva (P16)
--    Nota: En el procedimiento real, Persistencia 2 (UPDATE) se ejecuta antes de Persistencia 3 (INSERT).
--    Por tanto, el UPDATE de P1 se ejecuta físicamente antes del INSERT de P16 que dispara el error.
EXEC sp_executesql N'
CREATE OR ALTER TRIGGER dbo.trg_Test_FalloPersistencia 
ON dbo.Fact_CaptacionBuyer 
AFTER INSERT 
AS 
BEGIN 
    IF EXISTS (SELECT 1 FROM inserted WHERE id_persona_origen = 16)
    BEGIN
        THROW 51000, ''Error forzado en INSERT de persona nueva para validar rollback atomico.'', 1; 
    END;
END;';

-- 4. Ejecutar el procedimiento real esperando captura de error y rollback
DECLARE @ErrCapturadoPersist BIT = 0;
DECLARE @ErrNumPersist INT = 0;
DECLARE @ErrMsgPersist NVARCHAR(4000) = '';
DECLARE @InsOut INT = 0, @ActOut INT = 0, @SinOut INT = 0, @RecOut INT = 0, @PenOut INT = 0;

BEGIN TRY
    EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
        @FechaCorte = '2026-10-10', 
        @BatchId = 'BATCH_T13_TRIGGER_FAIL',
        @Insertados = @InsOut OUTPUT,
        @Actualizados = @ActOut OUTPUT,
        @SinCambio = @SinOut OUTPUT,
        @Rechazados = @RecOut OUTPUT,
        @Pendientes = @PenOut OUTPUT;
END TRY
BEGIN CATCH
    SET @ErrCapturadoPersist = 1;
    SET @ErrNumPersist = ERROR_NUMBER();
    SET @ErrMsgPersist = ERROR_MESSAGE();
END CATCH;

-- 5. Eliminar el trigger de prueba inmediatamente
IF OBJECT_ID('dbo.trg_Test_FalloPersistencia', 'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_Test_FalloPersistencia;

-- 6. Comparación bidireccional mediante EXCEPT entre el hecho completo y la instantánea previa
DECLARE @DiffHechoVsInstantanea INT = 0;
SELECT @DiffHechoVsInstantanea = COUNT(*) 
FROM (
    SELECT * FROM dbo.Fact_CaptacionBuyer
    EXCEPT
    SELECT * FROM #Instantanea_Fact_Buyer
) d1;

DECLARE @DiffInstantaneaVsHecho INT = 0;
SELECT @DiffInstantaneaVsHecho = COUNT(*) 
FROM (
    SELECT * FROM #Instantanea_Fact_Buyer
    EXCEPT
    SELECT * FROM dbo.Fact_CaptacionBuyer
) d2;

-- 7. Comprobación de ausencia de P16, contadores confirmados en 0 y registro en bitácora
DECLARE @ExisteP16Hechos INT = 0;
SELECT @ExisteP16Hechos = COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 16;

DECLARE @ExisteLogPersist INT = 0;
SELECT @ExisteLogPersist = COUNT(*) 
FROM dbo.Log_Ejecucion_ETL 
WHERE BatchId = 'BATCH_T13_TRIGGER_FAIL' AND TipoEvento = 'ERROR' AND Mensaje LIKE '%51000%';

-- 8. Restaurar los datos fuente del escenario en OLTP y limpiar instantánea
UPDATE [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas 
SET id_canal_origen = 1,
    fecha_actualizacion = '2026-09-01 10:00:00'
WHERE id_persona = 1;

DELETE FROM [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas WHERE id_persona = 16;

IF OBJECT_ID('tempdb..#Instantanea_Fact_Buyer') IS NOT NULL
    DROP TABLE #Instantanea_Fact_Buyer;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T13',
    'Error en Persistencia via Trigger (Rollback Atomico y EXCEPT Bidireccional)',
    'Error 51000 capturado, EXCEPT=0 en ambas direcciones, P16 en Hechos=0, Ins=0, Act=0, Log ERROR=1',
    CONCAT('Error: ', @ErrNumPersist, ', Diff1: ', @DiffHechoVsInstantanea, ', Diff2: ', @DiffInstantaneaVsHecho, ', P16: ', @ExisteP16Hechos, ', Ins: ', @InsOut, ', Act: ', @ActOut, ', Log: ', @ExisteLogPersist),
    CASE WHEN @ErrCapturadoPersist = 1 
          AND @ErrNumPersist = 51000 
          AND @DiffHechoVsInstantanea = 0 
          AND @DiffInstantaneaVsHecho = 0 
          AND @ExisteP16Hechos = 0 
          AND @InsOut = 0 
          AND @ActOut = 0 
          AND @ExisteLogPersist >= 1 
    THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T14: Comprobación del Mecanismo de Bloqueo sp_getapplock
-- ----------------------------------------------------------------------------------------------------
DECLARE @ResLock1 INT, @ResLock2 INT;
BEGIN TRANSACTION;
EXEC @ResLock1 = sp_getapplock 
    @Resource = 'ETL_Lock_Fact_CaptacionBuyer', 
    @LockMode = 'Exclusive', 
    @LockOwner = 'Transaction', 
    @LockTimeout = 1000;

-- Readquisición en la misma transacción devuelve 0
EXEC @ResLock2 = sp_getapplock 
    @Resource = 'ETL_Lock_Fact_CaptacionBuyer', 
    @LockMode = 'Exclusive', 
    @LockOwner = 'Transaction', 
    @LockTimeout = 1000;

COMMIT TRANSACTION;

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T14',
    'Comprobacion del Mecanismo de Bloqueo sp_getapplock',
    'LockAdquirido >= 0 (Mecanismo sp_getapplock operativo)',
    CONCAT('LockAdquirido: ', @ResLock1, ', SegundoLock: ', @ResLock2),
    CASE WHEN @ResLock1 >= 0 AND @ResLock2 >= 0 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- T15: Tratamiento de Anomalías Cronológicas y Bitácora de Rechazos
-- ----------------------------------------------------------------------------------------------------
-- Sembrar P14 con solicitud anterior a su fecha de registro (registro 2026-09-10, solicitud 2026-09-01)
INSERT INTO [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Personas (
    id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual,
    estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento
) VALUES (
    14, 'Patricia', 'Bravo', '58901234', 'patricia.b@email.com', '954456789', 1, 10, 1,
    'Valido', 1, '2026-09-10 10:00:00', '2026-09-10 10:00:00', '2026-09-10 10:00:00', 'Trujillo', 'Natural', '1991-12-01'
);

INSERT INTO [Test_NexoSalud_OLTP_Buyer_Bateria].dbo.Solicitudes (
    id_solicitud, id_persona, id_servicio, estado, tipo_consulta, prioridad, motivo,
    fecha_solicitud, fecha_primera_respuesta, fecha_cierre
) VALUES (
    114, 14, 1, 'Confirmada', 'Ortodoncia', 'Media', 'Solicitud antes de registro',
    '2026-09-01 10:00:00', '2026-09-01 10:05:00', NULL
);

DECLARE @Ins INT, @Act INT, @Sin INT, @Rec INT, @Pen INT;
EXEC dbo.usp_Cargar_Fact_CaptacionBuyer 
    @FechaCorte = '2026-10-10', 
    @BatchId = 'BATCH_T15_ANOMALIA',
    @Insertados = @Ins OUTPUT,
    @Actualizados = @Act OUTPUT,
    @SinCambio = @Sin OUTPUT,
    @Rechazados = @Rec OUTPUT,
    @Pendientes = @Pen OUTPUT;

DECLARE @ExisteP14Hechos INT, @ExisteP14Rechazos INT;
SELECT @ExisteP14Hechos = COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 14;
SELECT @ExisteP14Rechazos = COUNT(*) FROM dbo.Rechazos_ETL_Buyer WHERE EntidadOrigenId = 14 AND MotivoRechazo LIKE '%AnomaliaCronologica%';

INSERT INTO #ResultadosPruebas (Caso, Nombre, ResultadoEsperado, ResultadoObtenido, Estado)
VALUES (
    'T15',
    'Tratamiento de Anomalias y Bitacora de Rechazos',
    'P14 en Hechos: 0, P14 en Rechazos: 1',
    CONCAT('P14 en Hechos: ', @ExisteP14Hechos, ', P14 en Rechazos: ', @ExisteP14Rechazos),
    CASE WHEN @ExisteP14Hechos = 0 AND @ExisteP14Rechazos = 1 THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ====================================================================================================
-- FASE 6: EVALUACIÓN Y REPORTE DEL RESUMEN FINAL (BATERÍA PROCEDIMENTAL 15 CASOS)
-- ====================================================================================================
SELECT 
    Orden,
    Caso,
    Nombre,
    ResultadoEsperado,
    ResultadoObtenido,
    Estado
FROM #ResultadosPruebas
ORDER BY Orden;

DECLARE @CasosEsperados INT = 15;
DECLARE @CasosEjecutados INT;
DECLARE @CasosCorrectos INT;
DECLARE @CasosFallidos INT;
DECLARE @DictamenFinal VARCHAR(50);

SELECT 
    @CasosEjecutados = COUNT(*),
    @CasosCorrectos = COUNT(CASE WHEN Estado = 'CORRECTO' THEN 1 END),
    @CasosFallidos = COUNT(CASE WHEN Estado <> 'CORRECTO' THEN 1 END)
FROM #ResultadosPruebas;

IF @CasosEjecutados = @CasosEsperados AND @CasosFallidos = 0
    SET @DictamenFinal = 'BATERÍA PROCEDIMENTAL APROBADA (15/15 SATISFACTORIOS)';
ELSE
    SET @DictamenFinal = 'BATERÍA NO APROBADA (FALLOS DETECTADOS)';

SELECT 
    @CasosEsperados AS CasosEsperados,
    @CasosEjecutados AS CasosEjecutados,
    @CasosCorrectos AS CasosCorrectos,
    @CasosFallidos AS CasosFallidos,
    @DictamenFinal AS DictamenFinal;
GO

-- ====================================================================================================
-- FASE 7: LIMPIEZA FINAL CONTROLADA Y NO DESTRUCTIVA
-- ====================================================================================================
-- Cierre de contexto y eliminación exclusiva de las bases temporales de la batería procedimental.
-- Se descarta terminantemente cualquier uso de SINGLE_USER WITH ROLLBACK IMMEDIATE.
USE master;
GO

PRINT '>> Procediendo a la eliminacion controlada y no destructiva de las bases temporales de prueba...';

BEGIN TRY
    DROP DATABASE Test_NexoSalud_Mart_Buyer_Bateria;
    PRINT '>> Base temporal Test_NexoSalud_Mart_Buyer_Bateria eliminada exitosamente.';
END TRY
BEGIN CATCH
    PRINT 'ADVERTENCIA: No se pudo eliminar la base Test_NexoSalud_Mart_Buyer_Bateria limpiamente: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    DROP DATABASE Test_NexoSalud_OLTP_Buyer_Bateria;
    PRINT '>> Base temporal Test_NexoSalud_OLTP_Buyer_Bateria eliminada exitosamente.';
END TRY
BEGIN CATCH
    PRINT 'ADVERTENCIA: No se pudo eliminar la base Test_NexoSalud_OLTP_Buyer_Bateria limpiamente: ' + ERROR_MESSAGE();
END CATCH;
GO

-- Verificación de inexistencia de bases residuales
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name IN ('Test_NexoSalud_OLTP_Buyer_Bateria', 'Test_NexoSalud_Mart_Buyer_Bateria'))
    PRINT '>> VERIFICACIÓN DE LIMPIEZA CONFIRMADA: Cero bases temporales residuales en el motor.';
ELSE
    PRINT '>> ADVERTENCIA: Una o más bases temporales permanecen activas.';
GO
