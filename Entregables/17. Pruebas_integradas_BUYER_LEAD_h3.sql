-- ====================================================================================================
-- NEXOSALUD — SISTEMA DE BUSINESS INTELLIGENCE ODONTOLÓGICO (CLÍNICA LUXEDENT)
-- PROYECTO BI — HITO H3 / CIERRE TÉCNICO INTEGRADO: BUYER → LEAD
-- SCRIPT DE EVALUACIÓN INTEGRADA: Entregables/17. Pruebas_integradas_BUYER_LEAD_h3.sql
-- RESPONSABLE TÉCNICO: Jesús Daniel Ordóñez Ugarte (Integrante 4 — integración técnica y cierre)
-- TITULAR DEL ROL: Mario Antonio Martinez Dominguez (Integrante 3 — ETL BUYER y LEAD, Embudo y Calidad)
-- ARCHIVOS REALES EVALUADOS: 
--   - Entregables/15. ETL_Fact_CaptacionBuyer_h3.sql (invocado mediante inclusión :r)
--   - Entregables/16. ETL_Fact_NegociacionLead_h3.sql (invocado mediante inclusión :r)
-- BASES DE DATOS AISLADAS: Test_NexoSalud_OLTP_Integrada / Test_NexoSalud_Mart_Integrada
-- REQUISITOS EVALUADOS: 10 Casos Integrados Formales (INT-01 a INT-10)
-- ====================================================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ====================================================================================================
-- FASE 1: PREPARACIÓN DEL ENTORNO AISLADO COMPARTIDO (POLÍTICA ESTRICTA NO DESTRUCTIVA)
-- ====================================================================================================
USE master;
GO

DECLARE @DbTestOLTP NVARCHAR(128) = N'Test_NexoSalud_OLTP_Integrada';
DECLARE @DbTestMart NVARCHAR(128) = N'Test_NexoSalud_Mart_Integrada';

-- Verificación preventiva de existencia: aborta inmediatamente si los nombres ya existen
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

-- Creación de las bases de datos temporales compartidas
EXEC(N'CREATE DATABASE ' + @DbTestOLTP + N';');
EXEC(N'CREATE DATABASE ' + @DbTestMart + N';');
GO

PRINT '>> Entornos aislados compartidos creados exitosamente.';
GO

-- ====================================================================================================
-- FASE 2: MODELO TRANSACCIONAL (OLTP) SINTÉTICO COMPARTIDO
-- ====================================================================================================
USE Test_NexoSalud_OLTP_Integrada;
GO

CREATE TABLE dbo.Canales (
    id_canal            INT NOT NULL PRIMARY KEY,
    nombre              VARCHAR(100) NOT NULL,
    tipo                VARCHAR(50) NOT NULL
);

CREATE TABLE dbo.Campanas (
    id_campana          INT NOT NULL PRIMARY KEY,
    nombre              VARCHAR(150) NOT NULL,
    tipo_origen         VARCHAR(100) NOT NULL
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
    nombres             VARCHAR(100) NOT NULL,
    apellidos           VARCHAR(100) NOT NULL,
    especialidad        VARCHAR(100) NULL
);

CREATE TABLE dbo.Usuarios (
    id_usuario          INT NOT NULL PRIMARY KEY,
    nombre_usuario      VARCHAR(100) NOT NULL,
    rol                 VARCHAR(50) NOT NULL
);

CREATE TABLE dbo.Disponibilidad (
    id_disponibilidad   INT NOT NULL PRIMARY KEY,
    id_sede             INT NOT NULL REFERENCES dbo.Sedes(id_sede),
    id_profesional      INT NOT NULL REFERENCES dbo.Profesionales(id_profesional),
    fecha_hora_inicio   DATETIME2(7) NOT NULL,
    fecha_hora_fin      DATETIME2(7) NOT NULL,
    estado              VARCHAR(30) NOT NULL DEFAULT 'Disponible'
);

CREATE TABLE dbo.Personas (
    id_persona          INT NOT NULL PRIMARY KEY,
    nombres             VARCHAR(100) NULL,
    apellidos           VARCHAR(100) NULL,
    dni                 VARCHAR(20) NULL,
    email               VARCHAR(150) NULL,
    numero              VARCHAR(50) NULL,
    id_canal_origen     INT NULL REFERENCES dbo.Canales(id_canal),
    id_campana_origen   INT NULL REFERENCES dbo.Campanas(id_campana),
    id_etapa_actual     INT NULL,
    estado_calidad      VARCHAR(50) NULL DEFAULT 'Valido',
    autoriza_contacto   INT NULL DEFAULT 1,
    fecha_autorizacion  DATETIME2(7) NULL,
    fecha_registro      DATETIME2(7) NOT NULL,
    fecha_actualizacion DATETIME2(7) NULL,
    zona                VARCHAR(100) NULL,
    tipo_persona        VARCHAR(50) NULL DEFAULT 'Natural',
    fecha_nacimiento    DATE NULL
);

CREATE TABLE dbo.Solicitudes (
    id_solicitud        INT NOT NULL PRIMARY KEY,
    id_persona          INT NOT NULL REFERENCES dbo.Personas(id_persona),
    id_servicio         INT NULL,
    estado              VARCHAR(50) NOT NULL,
    tipo_consulta       VARCHAR(50) NULL,
    prioridad           VARCHAR(50) NULL,
    motivo              VARCHAR(200) NULL,
    fecha_solicitud     DATETIME2(7) NOT NULL,
    fecha_primera_respuesta DATETIME2(7) NULL,
    fecha_cierre        DATETIME2(7) NULL
);

CREATE TABLE dbo.Opciones (
    id_opcion           INT NOT NULL PRIMARY KEY,
    id_solicitud        INT NOT NULL REFERENCES dbo.Solicitudes(id_solicitud),
    id_disponibilidad   INT NULL REFERENCES dbo.Disponibilidad(id_disponibilidad),
    precio_ofrecido     DECIMAL(10,2) NULL,
    fecha_ofrecida      DATETIME2(7) NOT NULL,
    seleccionada        BIT NOT NULL DEFAULT 0
);

CREATE TABLE dbo.Reservas (
    id_reserva          INT NOT NULL PRIMARY KEY,
    id_solicitud        INT NOT NULL REFERENCES dbo.Solicitudes(id_solicitud),
    fecha_reserva       DATETIME2(7) NOT NULL,
    estado              VARCHAR(50) NOT NULL,
    confirmacion_explicita BIT NOT NULL DEFAULT 0,
    fecha_confirmacion  DATETIME2(7) NULL
);

CREATE TABLE dbo.Interacciones (
    id_interaccion      INT NOT NULL PRIMARY KEY,
    id_persona          INT NOT NULL REFERENCES dbo.Personas(id_persona),
    id_canal            INT NULL REFERENCES dbo.Canales(id_canal),
    id_fuente           INT NULL,
    id_usuario          INT NULL REFERENCES dbo.Usuarios(id_usuario),
    fecha_hora          DATETIME2(7) NOT NULL,
    tipo                VARCHAR(50) NOT NULL,
    es_respuesta_util   BIT NOT NULL DEFAULT 0,
    resultado           VARCHAR(100) NULL,
    mensaje             VARCHAR(MAX) NULL
);

-- Siembra de catálogos fijos en OLTP
INSERT INTO dbo.Canales (id_canal, nombre, tipo) VALUES
(1, 'WhatsApp', 'Digital'),
(2, 'Web Form', 'Digital'),
(3, 'Telefono', 'Telefonico');

INSERT INTO dbo.Campanas (id_campana, nombre, tipo_origen) VALUES
(10, 'Campana Ortodoncia 2026', 'Redes Sociales'),
(20, 'Campana Implantes 2026', 'Google Ads');

INSERT INTO dbo.Servicios (id_servicio, nombre_servicio) VALUES
(1, 'Limpieza Dental'),
(2, 'Ortodoncia'),
(3, 'Implante Dental');

INSERT INTO dbo.Sedes (id_sede, nombre_sede) VALUES
(1, 'Sede Central Trujillo'),
(2, 'Sede Victor Larco'),
(3, 'Sede Huanchaco');

INSERT INTO dbo.Profesionales (id_profesional, nombres, apellidos, especialidad) VALUES
(1, 'Roberto', 'Mendoza', 'Odontología General'),
(2, 'Patricia', 'Alva', 'Ortodoncia'),
(3, 'Fernando', 'Ruiz', 'Implantología');

INSERT INTO dbo.Usuarios (id_usuario, nombre_usuario, rol) VALUES
(1, 'operador1', 'Asesor Comercial'),
(2, 'operador2', 'Asesor Comercial');

INSERT INTO dbo.Disponibilidad (id_disponibilidad, id_sede, id_profesional, fecha_hora_inicio, fecha_hora_fin, estado) VALUES
(101, 1, 1, '2026-09-01 08:00:00', '2026-09-01 13:00:00', 'Disponible'),
(102, 2, 2, '2026-09-02 08:00:00', '2026-09-02 13:00:00', 'Disponible'),
(103, 3, 3, '2026-09-03 08:00:00', '2026-09-03 13:00:00', 'Disponible');
GO

PRINT '>> Esquemas y catálogos OLTP desplegados exitosamente.';
GO

-- ====================================================================================================
-- FASE 3: MODELO DIMENSIONAL CONFORMADO Y CAPA STAGING EN EL MART COMPARTIDO
-- ====================================================================================================
USE Test_NexoSalud_Mart_Integrada;
GO

-- Creación del esquema staging en el Mart
EXEC(N'CREATE SCHEMA staging AUTHORIZATION dbo;');
GO

-- 3.1 Vistas Reales Necesarias del Entregable 13 (Copia exacta cambiando solo la base a Test_NexoSalud_OLTP_Integrada)
CREATE OR ALTER VIEW staging.stg_Personas
AS
SELECT 
    -- 1. Identificador Natural de Origen
    p.id_persona,

    -- 2. Claves de Atribución Transaccional (Directas de Origen, sin forzar dimensiones pendientes)
    p.id_canal_origen,
    p.id_campana_origen,
    p.id_etapa_actual,

    -- 3. Marcas Temporales y Claves de Fecha/Hora
    p.fecha_registro,
    p.fecha_actualizacion,
    CAST(CONVERT(VARCHAR(8), p.fecha_registro, 112) AS INT) AS KeyTiempoRegistro,
    CAST(REPLACE(SUBSTRING(CONVERT(VARCHAR(8), p.fecha_registro, 108), 1, 5), ':', '') AS INT) AS KeyHoraRegistro,

    -- 4. Banderas de Presencia y Formato de Identidad (Sin PII en Claro)
    CASE WHEN NULLIF(LTRIM(RTRIM(p.nombres)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_nombres,
    CASE WHEN NULLIF(LTRIM(RTRIM(p.apellidos)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_apellidos,
    CASE WHEN NULLIF(LTRIM(RTRIM(p.dni)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_dni,
    CASE 
        WHEN LTRIM(RTRIM(p.dni)) LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
             AND LEN(LTRIM(RTRIM(p.dni))) = 8 
        THEN 1 
        ELSE 0 
    END AS es_dni_valido_8d,

    -- 5. Banderas de Presencia y Formato de Canales de Contacto
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

    -- 6. Pseudonimización para Detección de Coincidencias de Valores Normalizados (Sin PII en Claro)
    -- Regla Estricta: Si el dato es NULL o vacío, devuelve NULL (evita hash de cadena vacía)
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

    -- 7. Normalización de Calidad Registral
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

    -- 8. Consentimiento y Banderas de Contactabilidad Técnica
    p.autoriza_contacto AS autoriza_contacto_original,
    p.fecha_autorizacion,
    CASE WHEN p.autoriza_contacto = 1 THEN 1 ELSE 0 END AS tiene_autorizacion_contacto,
    
    -- Bandera de Revisión de Contactabilidad:
    -- Derivada estrictamente de los canales acreditados (independiente de nombres, calidad o consentimiento):
    -- Si no cuenta con celular PE válido NI con correo electrónico válido = 1; con al menos un medio acreditado = 0
    CASE 
        WHEN tel_norm.es_celular_pe_valido = 0 
             AND (p.email NOT LIKE '%_@__%.__%' OR p.email LIKE '% %' OR p.email IS NULL)
        THEN 1 
        ELSE 0 
    END AS requiere_revision_contactabilidad,

    -- 9. Indicador Técnico de Contacto Utilizable
    -- Requiere: Nombres, Apellidos, Calidad 'Valido', Consentimiento = 1 y Vía Acreditada (Celular PE o Email válido)
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

    -- 10. Normalización de Segmentación y Demografía
    p.zona AS zona_original,
    COALESCE(NULLIF(LTRIM(RTRIM(p.zona)), ''), 'No Especificada') AS zona_norm,
    p.tipo_persona AS tipo_persona_original,
    COALESCE(NULLIF(LTRIM(RTRIM(p.tipo_persona)), ''), 'No Especificado') AS tipo_persona_norm,
    p.fecha_nacimiento,
    CASE WHEN p.fecha_nacimiento IS NOT NULL THEN 1 ELSE 0 END AS tiene_fecha_nacimiento

FROM [Test_NexoSalud_OLTP_Integrada].dbo.[Personas] p

-- Normalización telefónica interna mediante CROSS APPLY (no expone cleartext)
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
            -- Móvil peruano estándar de 9 dígitos que inicia con 9
            WHEN raw_tel.tel_limpio LIKE '9[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 9 
            THEN 1
            -- Con código +51 y 9 dígitos
            WHEN raw_tel.tel_limpio LIKE '+519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' 
                 AND LEN(raw_tel.tel_limpio) = 12 
            THEN 1
            -- Con código 51 y 9 dígitos
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

PRINT '>> Vista [staging].[stg_Personas] desplegada con definición real del Entregable 13.';
GO

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
    -- (Una fecha de cierre aislada NO inventa un resultado comercial; se audita la incoherencia)
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

FROM [Test_NexoSalud_OLTP_Integrada].dbo.[Solicitudes] s

-- Derivación centralizada del estado normalizado para alimentar todas las banderas
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

-- Subconsulta escalar para la PRIMERA opción (orden determinista por fecha_ofrecida e id_opcion)
OUTER APPLY (
    SELECT TOP 1 
        o_prim.id_opcion AS id_primera_opcion,
        o_prim.precio_ofrecido AS primer_precio_ofrecido,
        o_prim.fecha_ofrecida AS fecha_primer_precio_ofrecido
    FROM [Test_NexoSalud_OLTP_Integrada].dbo.[Opciones] o_prim
    WHERE o_prim.id_solicitud = s.id_solicitud
    ORDER BY o_prim.fecha_ofrecida ASC, o_prim.id_opcion ASC
) opc_prim

-- Subconsulta escalar agregada para opciones (garantiza cero ante ausencia y NULL en precios)
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
    FROM [Test_NexoSalud_OLTP_Integrada].dbo.[Opciones] o_agg
    WHERE o_agg.id_solicitud = s.id_solicitud
) opc_agg

-- Subconsulta escalar para la PRIMERA reserva (atributos coherentes de la MISMA reserva)
OUTER APPLY (
    SELECT TOP 1
        r_prim.id_reserva AS id_primera_reserva,
        r_prim.fecha_reserva AS primera_fecha_reserva,
        r_prim.estado AS estado_primera_reserva,
        r_prim.confirmacion_explicita AS confirmacion_explicita_primera_reserva,
        r_prim.fecha_confirmacion AS fecha_confirmacion_primera_reserva
    FROM [Test_NexoSalud_OLTP_Integrada].dbo.[Reservas] r_prim
    WHERE r_prim.id_solicitud = s.id_solicitud
    ORDER BY r_prim.fecha_reserva ASC, r_prim.id_reserva ASC
) res_prim

-- Subconsulta escalar agregada para totales de reservas (garantiza cero ante ausencia y NULL en fechas)
OUTER APPLY (
    SELECT 
        COALESCE(COUNT(r_agg.id_reserva), 0) AS cantidad_reservas_asociadas,
        COALESCE(MAX(CASE WHEN r_agg.confirmacion_explicita = 1 THEN 1 ELSE 0 END), 0) AS tiene_alguna_reserva_confirmada
    FROM [Test_NexoSalud_OLTP_Integrada].dbo.[Reservas] r_agg
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
    
    -- Categorización Explícita por Equivalencias Completas (No ignora negaciones ni usa LIKE parcial)
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

FROM [Test_NexoSalud_OLTP_Integrada].dbo.[Interacciones] i;
GO

PRINT '>> Vista [staging].[stg_Interacciones] desplegada con definición real del Entregable 13.';
GO

-- 3.2 Dimensiones Conformadas en el Data Mart Compartido (Unión completa de Requisitos BUYER y LEAD)
CREATE TABLE dbo.Dim_Tiempo (
    KeyTiempo   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_fecha    DATE NOT NULL,
    Anio        INT NOT NULL DEFAULT 2026,
    Trimestre   INT NOT NULL DEFAULT 3,
    Mes         INT NOT NULL DEFAULT 9,
    Dia         INT NOT NULL DEFAULT 1
);

CREATE TABLE dbo.Dim_Canal (
    KeyCanal    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_canal    INT NULL,
    NombreCanal VARCHAR(100) NOT NULL,
    TipoMedio   VARCHAR(50) NULL
);

CREATE TABLE dbo.Dim_Fuente (
    KeyFuente   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_fuente   INT NULL,
    id_campana  INT NULL,
    TipoOrigen  VARCHAR(100) NULL,
    Campana     VARCHAR(150) NULL
);

CREATE TABLE dbo.Dim_Campana (
    KeyCampana    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_campana    INT NULL,
    NombreCampana VARCHAR(150) NOT NULL DEFAULT 'Sin Campana',
    Campana       VARCHAR(150) NULL
);

CREATE TABLE dbo.Dim_Sede (
    KeySede     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_sede     INT NULL,
    NombreSede  VARCHAR(100) NOT NULL DEFAULT 'Sede No Especificada',
    Sede        VARCHAR(100) NULL,
    Distrito    VARCHAR(100) NULL,
    Zona        VARCHAR(100) NULL
);

CREATE TABLE dbo.Dim_EstadoRegistro (
    KeyEstadoRegistro    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EstadoCalidad        VARCHAR(50) NOT NULL,
    AutorizacionContacto VARCHAR(2) NOT NULL
);

CREATE TABLE dbo.Dim_Servicio (
    KeyServicio    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_servicio    INT NULL,
    NombreServicio VARCHAR(100) NOT NULL
);

CREATE TABLE dbo.Dim_Profesional (
    KeyProfesional    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_profesional    INT NULL,
    NombreProfesional VARCHAR(150) NOT NULL
);

CREATE TABLE dbo.Dim_Negociador (
    KeyNegociador    INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_usuario       INT NULL,
    NombreNegociador VARCHAR(150) NOT NULL
);

-- ====================================================================================================
-- PROPUESTA DE PRUEBA EXPRESA: Dim_Persona
-- NOTA METODOLÓGICA OBLIGATORIA:
-- Dim_Persona no existe en el DDL físico entregado por Marck (Entregables 8 y 9). Se despliega aquí
-- expresamente como PROPUESTA DE PRUEBA requerida por el contrato (Entregable 12) para validar la
-- integridad referencial FK_FactBuyer_Persona y FK_FactLead_Persona sin alterar el modelo de producción.
-- ====================================================================================================
CREATE TABLE dbo.Dim_Persona (
    KeyPersona      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_persona      INT NULL,
    NombreCompleto  VARCHAR(200) NOT NULL
);

-- Siembra de Miembros Desconocidos (Key = 0) verificados con unicidad
SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha, Anio, Trimestre, Mes, Dia) VALUES (0, '1900-01-01', 1900, 1, 1, 1);
SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;

SET IDENTITY_INSERT dbo.Dim_Canal ON;
INSERT INTO dbo.Dim_Canal (KeyCanal, id_canal, NombreCanal, TipoMedio) VALUES (0, 0, 'Canal No Especificado', 'Desconocido');
SET IDENTITY_INSERT dbo.Dim_Canal OFF;

SET IDENTITY_INSERT dbo.Dim_Fuente ON;
INSERT INTO dbo.Dim_Fuente (KeyFuente, id_fuente, id_campana, TipoOrigen, Campana) VALUES (0, 0, 0, 'Desconocido', 'Desconocido');
SET IDENTITY_INSERT dbo.Dim_Fuente OFF;

SET IDENTITY_INSERT dbo.Dim_Campana ON;
INSERT INTO dbo.Dim_Campana (KeyCampana, id_campana, NombreCampana, Campana) VALUES (0, 0, 'Sin Campana Asociada', 'Sin Campana');
SET IDENTITY_INSERT dbo.Dim_Campana OFF;

SET IDENTITY_INSERT dbo.Dim_Sede ON;
INSERT INTO dbo.Dim_Sede (KeySede, id_sede, NombreSede, Sede, Distrito, Zona) VALUES (0, 0, 'Sede No Especificada', 'Sin Sede Asignada', 'Desconocido', 'Desconocido');
SET IDENTITY_INSERT dbo.Dim_Sede OFF;

SET IDENTITY_INSERT dbo.Dim_EstadoRegistro ON;
INSERT INTO dbo.Dim_EstadoRegistro (KeyEstadoRegistro, EstadoCalidad, AutorizacionContacto) VALUES (0, 'Desconocido', 'NO');
SET IDENTITY_INSERT dbo.Dim_EstadoRegistro OFF;

SET IDENTITY_INSERT dbo.Dim_Servicio ON;
INSERT INTO dbo.Dim_Servicio (KeyServicio, id_servicio, NombreServicio) VALUES (0, 0, 'Servicio No Especificado');
SET IDENTITY_INSERT dbo.Dim_Servicio OFF;

SET IDENTITY_INSERT dbo.Dim_Profesional ON;
INSERT INTO dbo.Dim_Profesional (KeyProfesional, id_profesional, NombreProfesional) VALUES (0, 0, 'Profesional No Especificado');
SET IDENTITY_INSERT dbo.Dim_Profesional OFF;

SET IDENTITY_INSERT dbo.Dim_Negociador ON;
INSERT INTO dbo.Dim_Negociador (KeyNegociador, id_usuario, NombreNegociador) VALUES (0, 0, 'Negociador No Asignado');
SET IDENTITY_INSERT dbo.Dim_Negociador OFF;

SET IDENTITY_INSERT dbo.Dim_Persona ON;
INSERT INTO dbo.Dim_Persona (KeyPersona, id_persona, NombreCompleto) VALUES (0, 0, 'Persona No Registrada');
SET IDENTITY_INSERT dbo.Dim_Persona OFF;

-- Siembra de Miembros Reales en Dimensiones Conformadas
SET IDENTITY_INSERT dbo.Dim_Canal ON;
INSERT INTO dbo.Dim_Canal (KeyCanal, id_canal, NombreCanal, TipoMedio) VALUES
(1, 1, 'WhatsApp', 'Digital'), 
(2, 2, 'Web Form', 'Digital'), 
(3, 3, 'Telefono', 'Telefonico');
SET IDENTITY_INSERT dbo.Dim_Canal OFF;

SET IDENTITY_INSERT dbo.Dim_Fuente ON;
INSERT INTO dbo.Dim_Fuente (KeyFuente, id_fuente, id_campana, TipoOrigen, Campana) VALUES
(1, 1, 10, 'Redes Sociales', 'Campana Ortodoncia 2026'),
(2, 2, 20, 'Google Ads', 'Campana Implantes 2026');
SET IDENTITY_INSERT dbo.Dim_Fuente OFF;

SET IDENTITY_INSERT dbo.Dim_Campana ON;
INSERT INTO dbo.Dim_Campana (KeyCampana, id_campana, NombreCampana, Campana) VALUES
(1, 10, 'Campana Ortodoncia 2026', 'Campana Ortodoncia 2026'), 
(2, 20, 'Campana Implantes 2026', 'Campana Implantes 2026');
SET IDENTITY_INSERT dbo.Dim_Campana OFF;

SET IDENTITY_INSERT dbo.Dim_Sede ON;
INSERT INTO dbo.Dim_Sede (KeySede, id_sede, NombreSede, Sede, Distrito, Zona) VALUES
(1, 1, 'Sede Central Trujillo', 'Sede Central Trujillo', 'Trujillo', 'Norte'), 
(2, 2, 'Sede Victor Larco', 'Sede Victor Larco', 'Victor Larco', 'Oeste'), 
(3, 3, 'Sede Huanchaco', 'Sede Huanchaco', 'Huanchaco', 'Costa');
SET IDENTITY_INSERT dbo.Dim_Sede OFF;

SET IDENTITY_INSERT dbo.Dim_EstadoRegistro ON;
INSERT INTO dbo.Dim_EstadoRegistro (KeyEstadoRegistro, EstadoCalidad, AutorizacionContacto) VALUES
(1, 'Valido', 'SI'),
(2, 'Valido', 'NO'),
(3, 'Incompleto', 'NO'),
(4, 'Incompleto', 'SI'),
(5, 'Duplicado', 'NO'),
(6, 'Rechazado', 'NO');
SET IDENTITY_INSERT dbo.Dim_EstadoRegistro OFF;

SET IDENTITY_INSERT dbo.Dim_Servicio ON;
INSERT INTO dbo.Dim_Servicio (KeyServicio, id_servicio, NombreServicio) VALUES
(1, 1, 'Limpieza Dental'), 
(2, 2, 'Ortodoncia'), 
(3, 3, 'Implante Dental');
SET IDENTITY_INSERT dbo.Dim_Servicio OFF;

SET IDENTITY_INSERT dbo.Dim_Profesional ON;
INSERT INTO dbo.Dim_Profesional (KeyProfesional, id_profesional, NombreProfesional) VALUES
(1, 1, 'Roberto Mendoza'), 
(2, 2, 'Patricia Alva'), 
(3, 3, 'Fernando Ruiz');
SET IDENTITY_INSERT dbo.Dim_Profesional OFF;

SET IDENTITY_INSERT dbo.Dim_Negociador ON;
INSERT INTO dbo.Dim_Negociador (KeyNegociador, id_usuario, NombreNegociador) VALUES
(1, 1, 'operador1'), 
(2, 2, 'operador2');
SET IDENTITY_INSERT dbo.Dim_Negociador OFF;

-- Generación de Calendario en Dim_Tiempo (claves inteligentes YYYYMMDD)
SET IDENTITY_INSERT dbo.Dim_Tiempo ON;
DECLARE @f DATE = '2026-08-01';
WHILE @f <= '2026-11-30'
BEGIN
    INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha, Anio, Trimestre, Mes, Dia) 
    VALUES (CAST(CONVERT(VARCHAR(8), @f, 112) AS INT), @f, YEAR(@f), DATEPART(qq, @f), MONTH(@f), DAY(@f));
    SET @f = DATEADD(DAY, 1, @f);
END;
SET IDENTITY_INSERT dbo.Dim_Tiempo OFF;

-- Siembra de Dim_Persona (P1 a P8)
SET IDENTITY_INSERT dbo.Dim_Persona ON;
DECLARE @p INT = 1;
WHILE @p <= 8
BEGIN
    INSERT INTO dbo.Dim_Persona (KeyPersona, id_persona, NombreCompleto) 
    VALUES (@p, @p, CONCAT('Persona Sintetica ', @p));
    SET @p = @p + 1;
END;
SET IDENTITY_INSERT dbo.Dim_Persona OFF;
GO

PRINT '>> Dimensiones conformadas y propuesta de prueba Dim_Persona pobladas exitosamente.';
GO
-- ====================================================================================================
-- FASE 4: INCLUSIÓN DE LOS ARCHIVOS REALES DE IMPLEMENTACIÓN 15 Y 16 MEDIANTE :r
-- (Sin duplicar ni reimplementar ningún procedimiento en el script de pruebas)
-- ====================================================================================================
PRINT '>> Invocando implementación real Entregables/15. ETL_Fact_CaptacionBuyer_h3.sql...';
:r "Entregables\15. ETL_Fact_CaptacionBuyer_h3.sql"
GO

PRINT '>> Invocando implementación real Entregables/16. ETL_Fact_NegociacionLead_h3.sql...';
:r "Entregables\16. ETL_Fact_NegociacionLead_h3.sql"
GO

PRINT '>> Ambas implementaciones reales compiladas y verificadas en el Mart compartido.';
GO

-- ====================================================================================================
-- FASE 5: SIEMBRA DEL CONJUNTO COMPACTO DE DATOS SINTÉTICOS INTEGRADOS (P1 A P8)
-- Diseñado para cubrir todos los requisitos de disyunción, concurrencia, multiplicidad y cohortes
-- ====================================================================================================
USE Test_NexoSalud_OLTP_Integrada;
GO

-- Persona 1: Prospecto válido -> Lead estándar convertido en 14 días (Hito Creación y Confirmación válidos)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (1, 'Carlos', 'Mendoza', '45891234', 'carlos.m@test.pe', '987654321', 1, 10, 2, 'Valido', 1, '2026-09-01 10:00:00', '2026-09-01 10:00:00', '2026-09-01 10:00:00', 'Trujillo', 'Natural', '1990-05-12');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (1, 1, 1, 'Convertida', '2026-09-01 11:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
VALUES (1, 1, 101, 150.00, '2026-09-01 11:30:00', 1);

INSERT INTO dbo.Reservas (id_reserva, id_solicitud, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (1, 1, '2026-09-05 10:00:00', 'Confirmada', 1, '2026-09-06 12:00:00');

INSERT INTO dbo.Interacciones (id_interaccion, id_persona, id_canal, id_usuario, fecha_hora, tipo, es_respuesta_util, resultado)
VALUES (101, 1, 1, 1, '2026-09-01 11:10:00', 'WhatsApp', 1, 'Cita Agendada');

-- Persona 2: Una persona con MÚLTIPLES solicitudes (S21 y S22) -> No debe multiplicar totales en BUYER
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (2, 'Ana', 'Rios', '46781290', 'ana.r@test.pe', '976543210', 2, 20, 2, 'Valido', 1, '2026-09-02 10:00:00', '2026-09-02 10:00:00', '2026-09-02 10:00:00', 'Victor Larco', 'Natural', '1992-08-20');

-- S21: Primera solicitud formal de P2 (convertida a reserva)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (21, 2, 1, 'Convertida', '2026-09-02 11:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
VALUES (21, 21, 101, 150.00, '2026-09-02 11:30:00', 1);

INSERT INTO dbo.Reservas (id_reserva, id_solicitud, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (21, 21, '2026-09-04 10:00:00', 'Confirmada', 1, '2026-09-04 12:00:00');

-- S22: Segunda solicitud de P2 (en negociación, sin reserva)
INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (22, 2, 2, 'En Negociacion', '2026-09-15 14:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
VALUES (22, 22, 102, 350.00, '2026-09-15 14:30:00', 1);

-- Persona 3: Persona SIN solicitud (Buyer puro no convertido a Lead)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (3, 'Pedro', 'Gomez', '47891230', 'pedro.g@test.pe', '965432109', 1, 10, 1, 'Valido', 1, '2026-09-03 10:00:00', '2026-09-03 10:00:00', '2026-09-03 10:00:00', 'Trujillo', 'Natural', '1988-11-03');

-- Persona 4: Solicitud SIN reserva (Lead no convertido a Payer)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (4, 'Maria', 'Vargas', '48901234', 'maria.v@test.pe', '954321098', 2, 20, 2, 'Valido', 1, '2026-09-04 10:00:00', '2026-09-04 10:00:00', '2026-09-04 10:00:00', 'Huanchaco', 'Natural', '1995-03-15');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (4, 4, 1, 'En Negociacion', '2026-09-04 11:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
VALUES (4, 4, 101, 150.00, '2026-09-04 11:30:00', 1);

-- Persona 5: Divergencia entre Hito Creación (dentro de 14d) vs Confirmación (fuera de 14d)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (5, 'Jorge', 'Soto', '49012345', 'jorge.s@test.pe', '943210987', 1, 10, 2, 'Valido', 1, '2026-09-05 10:00:00', '2026-09-05 10:00:00', '2026-09-05 10:00:00', 'Trujillo', 'Natural', '1985-07-22');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (5, 5, 2, 'Confirmada', '2026-09-05 11:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
VALUES (5, 5, 102, 400.00, '2026-09-05 11:30:00', 1);

-- Reserva creada el 2026-09-12 (7 días después, <= 14d), confirmada el 2026-09-25 (20 días después, > 14d)
INSERT INTO dbo.Reservas (id_reserva, id_solicitud, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
VALUES (5, 5, '2026-09-12 10:00:00', 'Confirmada', 1, '2026-09-25 10:00:00');

-- Persona 6: Cohorte Inmadura (< 14 días al corte del 2026-09-30)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (6, 'Lucia', 'Perez', '50123456', 'lucia.p@test.pe', '932109876', 1, 10, 2, 'Valido', 1, '2026-09-22 10:00:00', '2026-09-22 10:00:00', '2026-09-22 10:00:00', 'Moche', 'Natural', '1998-01-30');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (6, 6, 1, 'En Negociacion', '2026-09-22 11:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
VALUES (6, 6, 101, 150.00, '2026-09-22 11:30:00', 1);

-- Persona 7: Registro y Solicitud POSTERIOR al corte (Exclusión por corte semiabierto)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (7, 'Raul', 'Torres', '51234567', 'raul.t@test.pe', '921098765', 1, 10, 1, 'Valido', 1, '2026-10-02 10:00:00', '2026-10-02 10:00:00', '2026-10-02 10:00:00', 'Trujillo', 'Natural', '1991-09-18');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (7, 7, 1, 'En Negociacion', '2026-10-02 11:00:00');

-- Persona 8: Anomalía comercial controlada (Estado no catalogado -> Rechazo derivado a Rechazos_ETL_Lead)
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, id_canal_origen, id_campana_origen, id_etapa_actual, estado_calidad, autoriza_contacto, fecha_autorizacion, fecha_registro, fecha_actualizacion, zona, tipo_persona, fecha_nacimiento)
VALUES (8, 'Elena', 'Castro', '52345678', 'elena.c@test.pe', '910987654', 2, 20, 2, 'Valido', 1, '2026-09-08 10:00:00', '2026-09-08 10:00:00', '2026-09-08 10:00:00', 'Victor Larco', 'Natural', '1993-12-05');

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_servicio, estado, fecha_solicitud)
VALUES (8, 8, 1, 'EstadoAnomaloXYZ', '2026-09-08 11:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
VALUES (8, 8, 101, 150.00, '2026-09-08 11:30:00', 1);
GO

PRINT '>> Datos sintéticos integrados poblados exitosamente en OLTP.';
GO

-- ====================================================================================================
-- FASE 6: EJECUCIÓN INTEGRADA BUYER → LEAD Y VERIFICACIÓN DE EXPECTATIVAS (INT-01 A INT-10)
-- ====================================================================================================
USE Test_NexoSalud_Mart_Integrada;
GO

-- Configuración obligatoria del calendario de atención clínica en el Mart
DELETE FROM dbo.Config_CalendarioAtencion_ETL;
INSERT INTO dbo.Config_CalendarioAtencion_ETL (IdIntervalo, DiaSemana, HoraInicio, HoraFin, EsLaborable, Activo, DescripcionHorario) VALUES
(1, 1, '08:00:00', '18:00:00', 1, 1, 'Lunes 08:00 a 18:00'),
(2, 2, '08:00:00', '18:00:00', 1, 1, 'Martes 08:00 a 18:00'),
(3, 3, '08:00:00', '18:00:00', 1, 1, 'Miercoles 08:00 a 18:00'),
(4, 4, '08:00:00', '18:00:00', 1, 1, 'Jueves 08:00 a 18:00'),
(5, 5, '08:00:00', '18:00:00', 1, 1, 'Viernes 08:00 a 18:00'),
(6, 6, '08:00:00', '13:00:00', 1, 1, 'Sabado 08:00 a 13:00');

-- Tabla temporal en memoria para recopilar resultados de las pruebas integradas
CREATE TABLE #ResultadosIntegracion (
    CasoId          VARCHAR(10) NOT NULL PRIMARY KEY,
    Descripcion     VARCHAR(120) NOT NULL,
    CriterioEsperado VARCHAR(250) NOT NULL,
    ValorObtenido   VARCHAR(250) NOT NULL,
    Estado          VARCHAR(20) NOT NULL
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-01: Ejecución Secuencial BUYER → LEAD en el Mismo Data Mart (Reutilización de Objetos)
-- ----------------------------------------------------------------------------------------------------
DECLARE @InsBuyer INT, @ActBuyer INT, @SinBuyer INT, @RechBuyer INT, @PendBuyer INT;
DECLARE @InsLead INT, @ActLead INT, @SinLead INT, @RechLead INT, @PendLead INT;

-- 1. Ejecución de BUYER
EXEC dbo.usp_Cargar_Fact_CaptacionBuyer
    @FechaCorte   = '2026-09-30',
    @BatchId      = 'BATCH_INT_BUYER_01',
    @Insertados   = @InsBuyer OUTPUT,
    @Actualizados = @ActBuyer OUTPUT,
    @SinCambio    = @SinBuyer OUTPUT,
    @Rechazados   = @RechBuyer OUTPUT,
    @Pendientes   = @PendBuyer OUTPUT;

-- 2. Ejecución de LEAD sobre el mismo Mart
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte           = '2026-09-30',
    @BatchId              = 'BATCH_INT_LEAD_01',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP           = 'Test_NexoSalud_OLTP_Integrada',
    @ConvencionHoraria    = 'Local_Clinica_SinOffset',
    @Insertados           = @InsLead OUTPUT,
    @Actualizados         = @ActLead OUTPUT,
    @SinCambio            = @SinLead OUTPUT,
    @Rechazados           = @RechLead OUTPUT,
    @Pendientes           = @PendLead OUTPUT;

DECLARE @TotalBuyer_01 INT = (SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer);
DECLARE @TotalLead_01 INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead);
DECLARE @TotalLogs INT = (SELECT COUNT(*) FROM dbo.Log_Ejecucion_ETL WHERE BatchId IN ('BATCH_INT_BUYER_01', 'BATCH_INT_LEAD_01'));

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-01', 'Ejecución Secuencial BUYER -> LEAD en Mismo Mart',
    'Buyer Ins=7, Lead Ins=6, Lead Rech=1, Logs>=2',
    CONCAT('Buyer Ins=', @InsBuyer, ', Lead Ins=', @InsLead, ', Lead Rech=', @RechLead, ', TotalBuyer=', @TotalBuyer_01, ', TotalLead=', @TotalLead_01, ', Logs=', @TotalLogs),
    CASE WHEN @InsBuyer = 7 AND @InsLead = 6 AND @RechLead = 1 AND @TotalBuyer_01 = 7 AND @TotalLead_01 = 6 AND @TotalLogs >= 2
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-02: Grano Contractual Estricto (1 Fila BUYER por Persona, 1 Fila LEAD por Solicitud)
-- ----------------------------------------------------------------------------------------------------
DECLARE @BuyerFilas INT = (SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer);
DECLARE @BuyerPersonas INT = (SELECT COUNT(DISTINCT id_persona_origen) FROM dbo.Fact_CaptacionBuyer);
DECLARE @LeadFilas INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead);
DECLARE @LeadSolicitudes INT = (SELECT COUNT(DISTINCT id_solicitud_origen) FROM dbo.Fact_NegociacionLead);

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-02', 'Grano Contractual Estricto (1 por Persona en Buyer, 1 por Solicitud en Lead)',
    'Buyer: Filas=Personas=7 | Lead: Filas=Solicitudes=6',
    CONCAT('Buyer: Filas=', @BuyerFilas, ' Personas=', @BuyerPersonas, ' | Lead: Filas=', @LeadFilas, ' Solicitudes=', @LeadSolicitudes),
    CASE WHEN @BuyerFilas = 7 AND @BuyerPersonas = 7 AND @LeadFilas = 6 AND @LeadSolicitudes = 6
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-03: Persona con Varias Solicitudes sin Multiplicar Totales BUYER al Relacionar
-- ----------------------------------------------------------------------------------------------------
-- P2 tiene 2 solicitudes en LEAD (S21 y S22) y 1 fila en BUYER
DECLARE @CantSol_P2 INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_persona_origen = 2);
DECLARE @CantBuyer_P2 INT = (SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 2);

-- Total de contactos registrados en BUYER puro
DECLARE @TotalBuyerPuro INT = (SELECT SUM(ContactosRegistrados) FROM dbo.Fact_CaptacionBuyer);

-- Relación 1:N entre BUYER y LEAD:
-- Al relacionar ambos hechos por id_persona_origen mediante agrupamiento por persona (grano BUYER),
-- los totales de BUYER se preservan estrictamente en 7 sin multiplicarse.
DECLARE @TotalBuyerConRelacion INT = (
    SELECT SUM(t.Contactos)
    FROM (
        SELECT fb.id_persona_origen, MAX(fb.ContactosRegistrados) AS Contactos
        FROM dbo.Fact_CaptacionBuyer fb
        LEFT JOIN dbo.Fact_NegociacionLead fl ON fb.id_persona_origen = fl.id_persona_origen
        GROUP BY fb.id_persona_origen
    ) t
);

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-03', 'Persona Multi-Solicitud sin Multiplicar Totales BUYER en Relación',
    'P2_Buyer=1, P2_Lead=2, TotalPuro=7, TotalConRelacion=7 (no duplicados)',
    CONCAT('P2_Buyer=', @CantBuyer_P2, ', P2_Lead=', @CantSol_P2, ', TotalPuro=', @TotalBuyerPuro, ', TotalRel=', @TotalBuyerConRelacion),
    CASE WHEN @CantBuyer_P2 = 1 AND @CantSol_P2 = 2 AND @TotalBuyerPuro = 7 AND @TotalBuyerConRelacion = 7
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-04: Disyunción Funcional (Persona sin Solicitud, Solicitud sin Reserva, Conversión Válida)
-- ----------------------------------------------------------------------------------------------------
-- P3: Buyer sin solicitud
DECLARE @P3_Buyer INT = (SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 3);
DECLARE @P3_Lead INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_persona_origen = 3);

-- S4: Lead sin reserva
DECLARE @S4_KeyRes INT = (SELECT KeyTiempoReserva FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 4);
DECLARE @S4_Conv INT = (SELECT LeadsConvertidosPayerTotal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 4);

-- S1: Conversión válida
DECLARE @S1_KeyRes INT = (SELECT KeyTiempoReserva FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 1);
DECLARE @S1_Conv INT = (SELECT LeadsConvertidosPayerTotal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 1);

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-04', 'Disyunción Funcional (Persona sin Solicitud, Solicitud sin Reserva, Conversión)',
    'P3: Buyer=1 Lead=0 | S4: KeyRes=0 Conv=0 | S1: KeyRes=20260905 Conv=1',
    CONCAT('P3: B=', @P3_Buyer, ' L=', @P3_Lead, ' | S4: KeyRes=', @S4_KeyRes, ' Conv=', @S4_Conv, ' | S1: KeyRes=', @S1_KeyRes, ' Conv=', @S1_Conv),
    CASE WHEN @P3_Buyer = 1 AND @P3_Lead = 0 AND @S4_KeyRes = 0 AND @S4_Conv = 0 AND @S1_KeyRes = 20260905 AND @S1_Conv = 1
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-05: Consistencia de Cortes y Cohortes de 14 Días (Numerador ⊆ Denominador)
-- ----------------------------------------------------------------------------------------------------
-- Verificar que todo convertido en 14d pertenezca a la cohorte madura
DECLARE @Inconsistencias14D INT = (
    SELECT COUNT(*) 
    FROM dbo.Fact_NegociacionLead 
    WHERE LeadsConvertidosPayer14Dias = 1 AND LeadsCohorteEvaluable = 0
);

-- S6 registrada el 22-sep (inmadura al 30-sep): Denominador=0, Numerador=0
DECLARE @S6_Madura INT = (SELECT LeadsCohorteEvaluable FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 6);
DECLARE @S6_Inmadura INT = (SELECT CohorteInmadura FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 6);
DECLARE @S6_Conv14D INT = (SELECT LeadsConvertidosPayer14Dias FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 6);

-- P7 (del 02-oct) no debe existir en ningún hecho (corte 30-sep)
DECLARE @P7_Existe_Buyer INT = (SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer WHERE id_persona_origen = 7);
DECLARE @P7_Existe_Lead INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead WHERE id_persona_origen = 7);

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-05', 'Cortes y Cohortes Consistentes (Numerador 14D <= Denominador, Post-Corte Excluido)',
    'Inconsistencias=0, S6: Eval=0 Inmad=1 Conv14D=0, P7_Buyer=0, P7_Lead=0',
    CONCAT('Inconsistencias=', @Inconsistencias14D, ', S6: Eval=', @S6_Madura, ' Inmad=', @S6_Inmadura, ' Conv=', @S6_Conv14D, ', P7_B=', @P7_Existe_Buyer, ', P7_L=', @P7_Existe_Lead),
    CASE WHEN @Inconsistencias14D = 0 AND @S6_Madura = 0 AND @S6_Inmadura = 1 AND @S6_Conv14D = 0 AND @P7_Existe_Buyer = 0 AND @P7_Existe_Lead = 0
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-06: Creación y Confirmación con Resultados Diferentes según Hito Configurado
-- ----------------------------------------------------------------------------------------------------
-- En INT-01 se ejecutó con 'CreacionReserva': S5 reservó a los 7d (dentro de 14d)
DECLARE @S5_Conv14D_Creacion INT = (SELECT LeadsConvertidosPayer14Dias FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 5);

-- Re-ejecutar LEAD configurando 'ConfirmacionReserva': S5 confirmó a los 20d (fuera de 14d)
DECLARE @Ins_Hito INT, @Act_Hito INT, @Sin_Hito INT, @Rech_Hito INT;
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte           = '2026-09-30',
    @BatchId              = 'BATCH_INT_LEAD_HITO_CONF',
    @ConfigHitoConversion = 'ConfirmacionReserva',
    @FuenteOLTP           = 'Test_NexoSalud_OLTP_Integrada',
    @ConvencionHoraria    = 'Local_Clinica_SinOffset',
    @Insertados           = @Ins_Hito OUTPUT,
    @Actualizados         = @Act_Hito OUTPUT,
    @SinCambio            = @Sin_Hito OUTPUT,
    @Rechazados           = @Rech_Hito OUTPUT;

DECLARE @S5_Conv14D_Confirmacion INT = (SELECT LeadsConvertidosPayer14Dias FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 5);
DECLARE @S5_ConvTotal_Confirmacion INT = (SELECT LeadsConvertidosPayerTotal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 5);

-- Restaurar a CreacionReserva para los siguientes casos
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte           = '2026-09-30',
    @BatchId              = 'BATCH_INT_LEAD_HITO_REVERT',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP           = 'Test_NexoSalud_OLTP_Integrada',
    @ConvencionHoraria    = 'Local_Clinica_SinOffset';

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-06', 'Divergencia Controlada de Hitos (Creación=1 vs Confirmación=0 en S5)',
    'HitoCreacion Conv14D=1 | HitoConfirmacion Conv14D=0, ConvTotal=1, Actualizados>=1',
    CONCAT('Creacion_14D=', @S5_Conv14D_Creacion, ', Confirmacion_14D=', @S5_Conv14D_Confirmacion, ', ConvTot=', @S5_ConvTotal_Confirmacion, ', Act=', @Act_Hito),
    CASE WHEN @S5_Conv14D_Creacion = 1 AND @S5_Conv14D_Confirmacion = 0 AND @S5_ConvTotal_Confirmacion = 1 AND @Act_Hito >= 1
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-07: Resolución Coherente de Dimensiones y Claves de Fecha Inteligentes
-- ----------------------------------------------------------------------------------------------------
DECLARE @ClavesFechaInvalidas_Buyer INT = (
    SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer 
    WHERE KeyTiempoRegistro NOT BETWEEN 20260901 AND 20260930 AND KeyTiempoRegistro <> 0
);

DECLARE @ClavesFechaInvalidas_Lead INT = (
    SELECT COUNT(*) FROM dbo.Fact_NegociacionLead 
    WHERE (KeyTiempoSolicitud NOT BETWEEN 20260901 AND 20260930 AND KeyTiempoSolicitud <> 0)
       OR (KeyTiempoReserva NOT BETWEEN 20260901 AND 20260930 AND KeyTiempoReserva <> 0)
);

-- Resolución de S1: Sede 1, Profesional 1 resueltos desde Disponibilidad (no 0 ni NULL)
DECLARE @KeySede_S1 INT = (SELECT KeySede FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 1);
DECLARE @KeyProf_S1 INT = (SELECT KeyProfesional FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 1);

DECLARE @KeySede1_Esp INT = (SELECT KeySede FROM dbo.Dim_Sede WHERE id_sede = 1);
DECLARE @KeyProf1_Esp INT = (SELECT KeyProfesional FROM dbo.Dim_Profesional WHERE id_profesional = 1);

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-07', 'Resolución Coherente de Dimensiones y Claves de Fecha Inteligentes',
    'ClavesInvalidas Buyer=0 Lead=0, KeySede_S1=Sede1, KeyProf_S1=Prof1',
    CONCAT('ClavesInvBuyer=', @ClavesFechaInvalidas_Buyer, ', ClavesInvLead=', @ClavesFechaInvalidas_Lead, ', S1_Sede=', @KeySede_S1, ' (Esp ', @KeySede1_Esp, '), S1_Prof=', @KeyProf_S1, ' (Esp ', @KeyProf1_Esp, ')'),
    CASE WHEN @ClavesFechaInvalidas_Buyer = 0 AND @ClavesFechaInvalidas_Lead = 0 AND @KeySede_S1 = @KeySede1_Esp AND @KeyProf_S1 = @KeyProf1_Esp
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-08: Idempotencia Operativa Absoluta (Segunda Ejecución sin Cambios en Ambos Hechos)
-- ----------------------------------------------------------------------------------------------------
DECLARE @InsB_Idem INT, @ActB_Idem INT, @SinB_Idem INT, @RechB_Idem INT;
DECLARE @InsL_Idem INT, @ActL_Idem INT, @SinL_Idem INT, @RechL_Idem INT;

EXEC dbo.usp_Cargar_Fact_CaptacionBuyer
    @FechaCorte   = '2026-09-30',
    @BatchId      = 'BATCH_INT_BUYER_IDEM',
    @Insertados   = @InsB_Idem OUTPUT,
    @Actualizados = @ActB_Idem OUTPUT,
    @SinCambio    = @SinB_Idem OUTPUT,
    @Rechazados   = @RechB_Idem OUTPUT;

EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte           = '2026-09-30',
    @BatchId              = 'BATCH_INT_LEAD_IDEM',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP           = 'Test_NexoSalud_OLTP_Integrada',
    @ConvencionHoraria    = 'Local_Clinica_SinOffset',
    @Insertados           = @InsL_Idem OUTPUT,
    @Actualizados         = @ActL_Idem OUTPUT,
    @SinCambio            = @SinL_Idem OUTPUT,
    @Rechazados           = @RechL_Idem OUTPUT;

DECLARE @TotalBuyer_Idem INT = (SELECT COUNT(*) FROM dbo.Fact_CaptacionBuyer);
DECLARE @TotalLead_Idem INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead);

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-08', 'Idempotencia Operativa Absoluta (0 Ins, 0 Act en Ambos Hechos)',
    'Buyer: Ins=0 Act=0 Sin=7 | Lead: Ins=0 Act=0 Sin=6 | Totales Invariantes',
    CONCAT('Buyer: Ins=', @InsB_Idem, ' Act=', @ActB_Idem, ' Sin=', @SinB_Idem, ' Tot=', @TotalBuyer_Idem, ' | Lead: Ins=', @InsL_Idem, ' Act=', @ActL_Idem, ' Sin=', @SinL_Idem, ' Tot=', @TotalLead_Idem),
    CASE WHEN @InsB_Idem = 0 AND @ActB_Idem = 0 AND @SinB_Idem = 7 AND @TotalBuyer_Idem = 7
          AND @InsL_Idem = 0 AND @ActL_Idem = 0 AND @SinL_Idem = 6 AND @TotalLead_Idem = 6
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-09: Cambio Controlado In-Place sin Duplicados
-- ----------------------------------------------------------------------------------------------------
-- Modificación controlada en OLTP: S4 pasa de 'En Negociacion' a 'Perdida'
UPDATE Test_NexoSalud_OLTP_Integrada.dbo.Solicitudes
SET estado = 'Perdida'
WHERE id_solicitud = 4;

DECLARE @InsL_Mod INT, @ActL_Mod INT, @SinL_Mod INT, @RechL_Mod INT;
EXEC dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte           = '2026-09-30',
    @BatchId              = 'BATCH_INT_LEAD_MOD',
    @ConfigHitoConversion = 'CreacionReserva',
    @FuenteOLTP           = 'Test_NexoSalud_OLTP_Integrada',
    @ConvencionHoraria    = 'Local_Clinica_SinOffset',
    @Insertados           = @InsL_Mod OUTPUT,
    @Actualizados         = @ActL_Mod OUTPUT,
    @SinCambio            = @SinL_Mod OUTPUT,
    @Rechazados           = @RechL_Mod OUTPUT;

DECLARE @TotalLead_PostMod INT = (SELECT COUNT(*) FROM dbo.Fact_NegociacionLead);
DECLARE @S4_ResultadoFinal INT = (SELECT LeadsResultadoFinal FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 4);
DECLARE @S4_EnNegociacion INT = (SELECT LeadsEnNegociacion FROM dbo.Fact_NegociacionLead WHERE id_solicitud_origen = 4);

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-09', 'Actualización Controlada In-Place sin Duplicados',
    'Ins=0, Act=1, Sin=5, Total=6 (sin duplicados), S4 ResFinal=1 EnNeg=0',
    CONCAT('Ins=', @InsL_Mod, ', Act=', @ActL_Mod, ', Sin=', @SinL_Mod, ', Total=', @TotalLead_PostMod, ', S4_ResFinal=', @S4_ResultadoFinal, ', S4_EnNeg=', @S4_EnNegociacion),
    CASE WHEN @InsL_Mod = 0 AND @ActL_Mod = 1 AND @SinL_Mod = 5 AND @TotalLead_PostMod = 6 AND @S4_ResultadoFinal = 1 AND @S4_EnNegociacion = 0
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ----------------------------------------------------------------------------------------------------
-- CASO INT-10: Integridad Referencial y Conciliación Exhaustiva (Aceptados, Rechazados, Pendientes)
-- ----------------------------------------------------------------------------------------------------
-- 1. Verificación de integridad referencial (cero claves foráneas huérfanas en ambos hechos)
DECLARE @HuerfanosBuyer INT = 0;
DECLARE @HuerfanosLead INT = 0;

SELECT @HuerfanosBuyer = COUNT(*)
FROM dbo.Fact_CaptacionBuyer fb
LEFT JOIN dbo.Dim_Tiempo dt_reg ON fb.KeyTiempoRegistro = dt_reg.KeyTiempo
LEFT JOIN dbo.Dim_Tiempo dt_conv ON fb.KeyTiempoConversion = dt_conv.KeyTiempo
LEFT JOIN dbo.Dim_Canal dc ON fb.KeyCanal = dc.KeyCanal
LEFT JOIN dbo.Dim_Fuente df ON fb.KeyFuente = df.KeyFuente
LEFT JOIN dbo.Dim_Campana dcp ON fb.KeyCampana = dcp.KeyCampana
LEFT JOIN dbo.Dim_Sede dsd ON fb.KeySede = dsd.KeySede
LEFT JOIN dbo.Dim_Persona dp ON fb.KeyPersona = dp.KeyPersona
LEFT JOIN dbo.Dim_EstadoRegistro der ON fb.KeyEstadoRegistro = der.KeyEstadoRegistro
WHERE dt_reg.KeyTiempo IS NULL 
   OR dt_conv.KeyTiempo IS NULL
   OR dc.KeyCanal IS NULL 
   OR df.KeyFuente IS NULL 
   OR dcp.KeyCampana IS NULL 
   OR dsd.KeySede IS NULL 
   OR dp.KeyPersona IS NULL 
   OR der.KeyEstadoRegistro IS NULL;

SELECT @HuerfanosLead = COUNT(*)
FROM dbo.Fact_NegociacionLead fl
LEFT JOIN dbo.Dim_Tiempo dt_sol ON fl.KeyTiempoSolicitud = dt_sol.KeyTiempo
LEFT JOIN dbo.Dim_Tiempo dt_res ON fl.KeyTiempoReserva = dt_res.KeyTiempo
LEFT JOIN dbo.Dim_Servicio ds ON fl.KeyServicio = ds.KeyServicio
LEFT JOIN dbo.Dim_Sede dsd ON fl.KeySede = dsd.KeySede
LEFT JOIN dbo.Dim_Profesional dp ON fl.KeyProfesional = dp.KeyProfesional
LEFT JOIN dbo.Dim_Negociador dn ON fl.KeyNegociador = dn.KeyNegociador
LEFT JOIN dbo.Dim_Persona dper ON fl.KeyPersona = dper.KeyPersona
WHERE dt_sol.KeyTiempo IS NULL 
   OR dt_res.KeyTiempo IS NULL 
   OR ds.KeyServicio IS NULL 
   OR dsd.KeySede IS NULL 
   OR dp.KeyProfesional IS NULL 
   OR dn.KeyNegociador IS NULL 
   OR dper.KeyPersona IS NULL;

-- 2. Conciliación verificable de LEAD frente a Staging pre-corte
-- Se toma como referencia de lote a conciliar el lote base 'BATCH_INT_LEAD_01'
DECLARE @LoteAConciliar VARCHAR(50) = 'BATCH_INT_LEAD_01';

-- Total observado dinámicamente desde staging aplicando el corte (2026-09-30)
DECLARE @TotalStagingObservado_Lead INT = (
    SELECT COUNT(DISTINCT id_solicitud)
    FROM staging.stg_Solicitudes
    WHERE fecha_solicitud < '2026-10-01 00:00:00'
);

-- Universo de claves de staging pre-corte en tabla temporal para contrastes de conjuntos
IF OBJECT_ID('tempdb..#Stg_Keys_Corte') IS NOT NULL DROP TABLE #Stg_Keys_Corte;
SELECT DISTINCT id_solicitud 
INTO #Stg_Keys_Corte
FROM staging.stg_Solicitudes
WHERE fecha_solicitud < '2026-10-01 00:00:00';

-- Conjunto de aceptados en hechos observados
DECLARE @AceptadasLead INT = (
    SELECT COUNT(DISTINCT fl.id_solicitud_origen)
    FROM dbo.Fact_NegociacionLead fl
    JOIN #Stg_Keys_Corte k ON fl.id_solicitud_origen = k.id_solicitud
);

-- Conjunto de rechazados reales del lote de carga, sin filtrar por una solicitud específica
DECLARE @RechazadasLead INT = (
    SELECT COUNT(DISTINCT r.id_solicitud_origen)
    FROM dbo.Rechazos_ETL_Lead r
    JOIN #Stg_Keys_Corte k ON r.id_solicitud_origen = k.id_solicitud
    WHERE r.BatchId = @LoteAConciliar
);

-- Pendientes observados: claves de staging pre-corte no presentes ni en hechos ni en rechazos del lote
DECLARE @PendientesLead INT = (
    SELECT COUNT(*)
    FROM #Stg_Keys_Corte k
    WHERE k.id_solicitud NOT IN (SELECT id_solicitud_origen FROM dbo.Fact_NegociacionLead)
      AND k.id_solicitud NOT IN (SELECT id_solicitud_origen FROM dbo.Rechazos_ETL_Lead WHERE BatchId = @LoteAConciliar)
);

-- Verificación de disyunción: intersección entre aceptados y rechazados debe ser exactamente 0
DECLARE @InterseccionAceptadosRechazados INT = (
    SELECT COUNT(DISTINCT fl.id_solicitud_origen)
    FROM dbo.Fact_NegociacionLead fl
    JOIN dbo.Rechazos_ETL_Lead r ON fl.id_solicitud_origen = r.id_solicitud_origen
    WHERE r.BatchId = @LoteAConciliar
);

-- Expectativas separadas de la muestra sintética
DECLARE @EspStaging INT = 7;
DECLARE @EspAceptados INT = 6;
DECLARE @EspRechazados INT = 1;
DECLARE @EspPendientes INT = 0;
DECLARE @EspInterseccion INT = 0;

INSERT INTO #ResultadosIntegracion VALUES (
    'INT-10', 'Integridad Referencial FK y Conciliación Exhaustiva',
    CONCAT('HuerfBuyer=0, HuerfLead=0, EspStg=', @EspStaging, ' (Acept=', @EspAceptados, ' Rech=', @EspRechazados, ' Pend=', @EspPendientes, ' Disjuntos=0)'),
    CONCAT('HuerfBuyer=', @HuerfanosBuyer, ', HuerfLead=', @HuerfanosLead, ', StgObs=', @TotalStagingObservado_Lead, ', Acept=', @AceptadasLead, ', Rech=', @RechazadasLead, ', Pend=', @PendientesLead, ', Intersec=', @InterseccionAceptadosRechazados),
    CASE WHEN @HuerfanosBuyer = 0 
          AND @HuerfanosLead = 0 
          AND @TotalStagingObservado_Lead = @EspStaging
          AND @AceptadasLead = @EspAceptados
          AND @RechazadasLead = @EspRechazados
          AND @PendientesLead = @EspPendientes
          AND @InterseccionAceptadosRechazados = @EspInterseccion
          AND (@AceptadasLead + @RechazadasLead + @PendientesLead) = @TotalStagingObservado_Lead
         THEN 'CORRECTO' ELSE 'FALLIDO' END
);
GO

-- ====================================================================================================
-- FASE 7: MATRIZ Y RESUMEN FINAL DE LA PRUEBA INTEGRADA
-- ====================================================================================================
SELECT 
    CasoId,
    Descripcion,
    CriterioEsperado,
    ValorObtenido,
    Estado AS [Veredicto]
FROM #ResultadosIntegracion
ORDER BY CasoId;

DECLARE @TotalCasos INT = (SELECT COUNT(*) FROM #ResultadosIntegracion);
DECLARE @CasosOk INT = (SELECT COUNT(*) FROM #ResultadosIntegracion WHERE Estado = 'CORRECTO');
DECLARE @CasosFail INT = (SELECT COUNT(*) FROM #ResultadosIntegracion WHERE Estado = 'FALLIDO');
DECLARE @CasosEsperados INT = 10;

PRINT '=================================================================================';
PRINT 'RESUMEN DE EJECUCIÓN PRUEBA INTEGRADA BUYER -> LEAD:';
PRINT CONCAT('Casos Esperados  : ', @CasosEsperados);
PRINT CONCAT('Casos Ejecutados : ', @TotalCasos);
PRINT CONCAT('Casos Aprobados  : ', @CasosOk);
PRINT CONCAT('Casos Fallidos   : ', @CasosFail);

IF @TotalCasos = @CasosEsperados AND @CasosFail = 0
BEGIN
    PRINT 'Dictamen Final   : INTEGRACIÓN TÉCNICA BUYER -> LEAD APROBADA (10/10 CASOS SATISFACTORIOS)';
END
ELSE
BEGIN
    PRINT 'Dictamen Final   : INTEGRACIÓN CON FALLAS O CASOS PENDIENTES';
    RAISERROR('La prueba integrada no alcanzó la aprobación global.', 16, 1);
END;
PRINT '=================================================================================';
GO

-- ====================================================================================================
-- FASE 8: LIMPIEZA FINAL NO DESTRUCTIVA DEL ENTORNO DE PRUEBAS
-- Elimina exclusivamente las bases temporales compartidas creadas en esta prueba sin matar conexiones ajenas
-- ====================================================================================================
USE master;
GO

DECLARE @DbTestOLTP NVARCHAR(128) = N'Test_NexoSalud_OLTP_Integrada';
DECLARE @DbTestMart NVARCHAR(128) = N'Test_NexoSalud_Mart_Integrada';

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
