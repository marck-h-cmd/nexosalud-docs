-- ====================================================================================================
-- NEXOSALUD — DATA MART DIMENSIONAL (CLÍNICA LUXEDENT, TRUJILLO)
-- Hito H3 (Fase 1): Extracción, Normalización y Perfilamiento de Datos — Etapas BUYER y LEAD
-- ====================================================================================================
-- Titular del Rol: Mario Antonio Martinez Dominguez (Integrante 3 — ETL BUYER y LEAD, Embudo y Calidad)
-- Responsable de Ejecución Técnica: Jesús Daniel Ordóñez Ugarte (Integrante 4 — titular original de PAYER;
--   Mario asumirá PAYER posteriormente según el intercambio comunicado; Anthony Garcia Ventura es Integrante 7)
-- Ubicación del Script: Entregables/13. Staging_buyer_lead_h3.sql
-- Documento de Soporte: Entregables/13. Guia_staging_buyer_lead_h3.md
-- Documento Contractual Base: Entregables/12. Contrato_y_dependencias_h3_mario.md
-- Versión de Referencia: https://github.com/tommy260803/Proyecto-IN-Odontolog-a- (commit 95471c30799c639c05218af2f6eb6a78bd25ba56)
--
-- ESTADO DE VERIFICACIÓN TÉCNICA:
--   Script preparado y revisado estáticamente a nivel de sintaxis T-SQL, lógica relacional y contratos.
--   No desplegado ni ejecutado contra bases de datos existentes en SQL Server (pendiente de motor).
--   Los bloques de pruebas sintéticas (VALUES) están diseñados de forma autónoma pero requieren un
--   motor T-SQL compatible para su ejecución física real.
--
-- PROPÓSITO:
--   Implementar la capa de staging lógico mediante vistas T-SQL bajo el esquema [staging] en [NexoSalud_Mart].
--   Estas vistas extraen, tipifican, normalizan y sanitizan los datos transaccionales de [NexoSaludDB]
--   sin modificar el OLTP, preservando estrictamente el grano atómico de 1 fila por entidad (1:1), sin exponer
--   PII ni textos libres clínicos, y sin asumir dimensiones conformadas pendientes de H2.
--
-- REGLAS ESTRICTAS DE PRIVACIDAD Y SEGURIDAD (LPDP LEY 29733):
--   1. No se proyectan nombres completos, DNI, teléfonos en claro (se elimina telefono_pe_9d) ni correos.
--   2. Se calculan teléfonos canónicos internamente para derivar banderas y hashes SHA-256 sin exponer el número.
--   3. Para valores NULL o vacíos, los hashes devuelven estrictamente NULL (evita hash de cadena vacía).
--   4. Precisión de Hashes: El hash SHA-256 sirve para detectar coincidencias de valores normalizados
--      sin revelar el dato en claro; no demuestra identidad única de la persona ni garantiza ausencia de colisiones.
--   5. Se eliminan textos libres (Interacciones.resultado, Interacciones.mensaje, Solicitudes.motivo, EventosEtapa.motivo/evidencia).
--      El campo resultado de interacciones se sustituye por bandera de presencia y categorías explícitamente permitidas
--      mediante equivalencias completas, sin búsquedas amplias que ignoren negaciones.
-- ====================================================================================================

USE [NexoSalud_Mart];
GO

-- ====================================================================================================
-- 1. PREPARACIÓN REPETIBLE DEL ESQUEMA STAGING
-- ====================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
BEGIN
    EXEC('CREATE SCHEMA staging');
    PRINT '>> Esquema [staging] creado exitosamente en NexoSalud_Mart.';
END
ELSE
BEGIN
    PRINT '>> El esquema [staging] ya existe en NexoSalud_Mart.';
END
GO

-- ====================================================================================================
-- 2. VISTA 1: staging.stg_Personas
-- Grano: Exactamente 1 fila por persona registrada (id_persona)
-- Origen: [NexoSaludDB].dbo.[Personas]
-- Reglas Clave:
--   - Minimización: telefono_pe_9d NO se expone en la proyección pública.
--   - Normalización telefónica interna: unifica celulares peruanos (9 dígitos, +51, 51 y separadores ' ', '-', '.', '(', ')', '/').
--   - Hashes: devuelve estrictamente NULL ante NULL o vacío (evita hash de cadena vacía).
--   - Extranjeros / otros formatos: no se mezclan con peruanos ni se truncan; llevan prefijo 'OTRO:' en el hash.
--   - Contactabilidad: requiere_revision_contactabilidad se deriva directamente de las banderas de canal
--     (sin celular PE acreditado ni correo válido = 1; con al menos un medio acreditado = 0),
--     siendo totalmente independiente de calidad, consentimiento o nombres.
--   - Utilizable técnico: exige nombres, apellidos, calidad 'Valido', consentimiento y canal válido acreditado.
--   - Temporalidad: no incluye cálculos volátiles con GETDATE(); convención horaria de origen permanece desconocida.
-- ====================================================================================================
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

FROM [NexoSaludDB].dbo.[Personas] p

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

PRINT '>> Vista [staging].[stg_Personas] creada exitosamente.';
GO

-- ====================================================================================================
-- 3. VISTA 2: staging.stg_Solicitudes
-- Grano: Exactamente 1 fila por solicitud formal (id_solicitud)
-- Origen: [NexoSaludDB].dbo.[Solicitudes] enriquecida escalarmente
-- Reglas Clave:
--   - Estados normalizados: incluye 'Convertida' y preserva 'Cancelada', 'Descartada', 'Perdida' como estados independientes.
--   - Banderas derivadas estrictamente de estado_solicitud_norm único (evita listas contradictorias).
--   - Contradicciones fecha-estado: detectadas por separado (una fecha de cierre aislada no inventa un resultado comercial).
--   - Agregados sin registros: Si una solicitud no tiene opciones, cantidad_opciones_ofrecidas = 0 y
--     cantidad_opciones_seleccionadas = 0; si no tiene reservas, cantidad_reservas_asociadas = 0 y
--     tiene_alguna_reserva_confirmada = 0. Se preserva NULL para importes y fechas ausentes (no convierte a cero).
--   - Primer precio ofrecido: determinista por fecha_ofrecida e id_opcion (no MIN(precio)).
--   - Precio seleccionado: si existen múltiples opciones seleccionadas, devuelve NULL (no MAX arbitrario) y reporta ambigüedad.
--   - Primera reserva: atributos coherentes de la MISMA reserva (ordenada por fecha_reserva e id_reserva).
--   - Exclusión de texto clínico libre (motivo).
-- ====================================================================================================
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

FROM [NexoSaludDB].dbo.[Solicitudes] s

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
    FROM [NexoSaludDB].dbo.[Opciones] o_prim
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
    FROM [NexoSaludDB].dbo.[Opciones] o_agg
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
    FROM [NexoSaludDB].dbo.[Reservas] r_prim
    WHERE r_prim.id_solicitud = s.id_solicitud
    ORDER BY r_prim.fecha_reserva ASC, r_prim.id_reserva ASC
) res_prim

-- Subconsulta escalar agregada para totales de reservas (garantiza cero ante ausencia y NULL en fechas)
OUTER APPLY (
    SELECT 
        COALESCE(COUNT(r_agg.id_reserva), 0) AS cantidad_reservas_asociadas,
        COALESCE(MAX(CASE WHEN r_agg.confirmacion_explicita = 1 THEN 1 ELSE 0 END), 0) AS tiene_alguna_reserva_confirmada
    FROM [NexoSaludDB].dbo.[Reservas] r_agg
    WHERE r_agg.id_solicitud = s.id_solicitud
) res_agg;
GO

PRINT '>> Vista [staging].[stg_Solicitudes] creada exitosamente.';
GO

-- ====================================================================================================
-- 4. VISTA 3: staging.stg_Interacciones
-- Grano: Exactamente 1 fila por interacción registrada (id_interaccion)
-- Origen: [NexoSaludDB].dbo.[Interacciones]
-- Reglas Clave:
--   - Minimización: Se eliminan resultado_original y resultado_norm (evita fuga de texto libre privado/clínico).
--   - Categorización segura mediante equivalencias completas explícitas (no usa búsquedas amplias que ignoren negaciones).
--   - Se excluye mensaje de texto (solo bandera de presencia y longitud).
-- ====================================================================================================
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

FROM [NexoSaludDB].dbo.[Interacciones] i;
GO

PRINT '>> Vista [staging].[stg_Interacciones] creada exitosamente.';
GO

-- ====================================================================================================
-- 5. VISTA 4: staging.stg_EventosEtapa
-- Grano: Exactamente 1 fila por evento de transición de etapa (id_evento_etapa)
-- Origen: [NexoSaludDB].dbo.[EventosEtapa] con LEFT JOIN a [Etapas]
-- Reglas Clave:
--   - Sustituye CASE fijo por LEFT JOIN al catálogo [Etapas] por id_etapa.
--   - Conserva todos los eventos e IDs originales, incluso si la etapa no está catalogada.
--   - Banderas y nombres derivados del catálogo OLTP real (incluye TURNED, no inventa ADVOCATE).
-- ====================================================================================================
CREATE OR ALTER VIEW staging.stg_EventosEtapa
AS
SELECT 
    -- 1. Identificador Natural de Origen
    e.id_evento_etapa,

    -- 2. Entidades Relacionadas Transaccionalmente
    e.id_persona,
    e.id_usuario AS id_usuario_transicion,

    -- 3. Transición de Etapas Mediante LEFT JOIN al Catálogo OLTP
    e.etapa_origen AS id_etapa_origen,
    COALESCE(et_orig.nombre, 'Sin Etapa Previa') AS etapa_origen_nombre_norm,

    e.etapa_destino AS id_etapa_destino,
    et_dest.nombre AS etapa_destino_nombre_catalogo,
    COALESCE(et_dest.nombre, CONCAT('Etapa Desconocida (ID: ', CAST(e.etapa_destino AS VARCHAR(10)), ')')) AS etapa_destino_nombre_norm,

    -- Banderas de Hitos Derivadas del Catálogo Real
    CASE WHEN UPPER(LTRIM(RTRIM(et_dest.nombre))) = 'LEAD' THEN 1 ELSE 0 END AS es_transicion_a_lead,
    CASE WHEN UPPER(LTRIM(RTRIM(et_dest.nombre))) = 'PAYER' THEN 1 ELSE 0 END AS es_transicion_a_payer,
    CASE WHEN UPPER(LTRIM(RTRIM(et_dest.nombre))) = 'CUSTOMER' THEN 1 ELSE 0 END AS es_transicion_a_customer,
    CASE WHEN UPPER(LTRIM(RTRIM(et_dest.nombre))) = 'TURNED' THEN 1 ELSE 0 END AS es_transicion_a_turned,
    CASE WHEN et_dest.id_etapa IS NULL THEN 1 ELSE 0 END AS es_etapa_destino_no_catalogada,

    -- 4. Marcas Temporales y Claves de Fecha/Hora
    e.fecha_hora AS fecha_hora_evento,
    CAST(CONVERT(VARCHAR(8), e.fecha_hora, 112) AS INT) AS KeyTiempoEvento,
    CAST(REPLACE(SUBSTRING(CONVERT(VARCHAR(8), e.fecha_hora, 108), 1, 5), ':', '') AS INT) AS KeyHoraEvento,

    -- 5. Protección de Datos (Exclusión de Motivos y Evidencias en Texto Libre)
    CASE WHEN NULLIF(LTRIM(RTRIM(e.motivo)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_motivo_registrado,
    CASE WHEN NULLIF(LTRIM(RTRIM(e.evidencia)), '') IS NOT NULL THEN 1 ELSE 0 END AS tiene_evidencia_registrada

FROM [NexoSaludDB].dbo.[EventosEtapa] e
LEFT JOIN [NexoSaludDB].dbo.[Etapas] et_dest 
    ON e.etapa_destino = et_dest.id_etapa
LEFT JOIN [NexoSaludDB].dbo.[Etapas] et_orig 
    ON e.etapa_origen = et_orig.id_etapa;
GO

PRINT '>> Vista [staging].[stg_EventosEtapa] creada exitosamente.';
GO

-- ====================================================================================================
-- 6. CONSULTAS DE PERFILAMIENTO Y AUDITORÍA DE CALIDAD (SOLO LECTURA)
-- Instrucción: Estas consultas son deterministas, no modifican datos, devuelven conteos e IDs técnicos
-- y garantizan la ausencia total de PII en claro (sin nombres, teléfonos, correos ni textos libres).
-- ====================================================================================================

-- ----------------------------------------------------------------------------------------------------
-- Test 1: Reconciliación de Conteos Absolutos (Origen OLTP vs. Staging Mart)
-- Criterio de Éxito: La columna Diferencia debe ser exactamente 0 para todas las entidades.
-- ----------------------------------------------------------------------------------------------------
SELECT 'Personas' AS Entidad, 
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[Personas]) AS Conteo_Origen_OLTP,
       (SELECT COUNT(*) FROM staging.stg_Personas) AS Conteo_Staging_Mart,
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[Personas]) - (SELECT COUNT(*) FROM staging.stg_Personas) AS Diferencia
UNION ALL
SELECT 'Solicitudes', 
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[Solicitudes]),
       (SELECT COUNT(*) FROM staging.stg_Solicitudes),
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[Solicitudes]) - (SELECT COUNT(*) FROM staging.stg_Solicitudes)
UNION ALL
SELECT 'Interacciones', 
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[Interacciones]),
       (SELECT COUNT(*) FROM staging.stg_Interacciones),
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[Interacciones]) - (SELECT COUNT(*) FROM staging.stg_Interacciones)
UNION ALL
SELECT 'EventosEtapa', 
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[EventosEtapa]),
       (SELECT COUNT(*) FROM staging.stg_EventosEtapa),
       (SELECT COUNT(*) FROM [NexoSaludDB].dbo.[EventosEtapa]) - (SELECT COUNT(*) FROM staging.stg_EventosEtapa);
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 2: Unicidad de Claves en Vistas de Staging (Preservación del Grano Atómico 1:1)
-- Criterio de Éxito: 0 registros duplicados devueltos.
-- ----------------------------------------------------------------------------------------------------
SELECT 'stg_Personas' AS Vista, id_persona AS ID_Duplicado, COUNT(*) AS Cantidad
FROM staging.stg_Personas
GROUP BY id_persona
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_Solicitudes', id_solicitud, COUNT(*)
FROM staging.stg_Solicitudes
GROUP BY id_solicitud
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_Interacciones', id_interaccion, COUNT(*)
FROM staging.stg_Interacciones
GROUP BY id_interaccion
HAVING COUNT(*) > 1
UNION ALL
SELECT 'stg_EventosEtapa', id_evento_etapa, COUNT(*)
FROM staging.stg_EventosEtapa
GROUP BY id_evento_etapa
HAVING COUNT(*) > 1;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 3: Discrepancias de Identificadores en Ambas Direcciones (Comprobación Bidireccional de IDs)
-- Criterio de Éxito: La métrica Cantidad_Discrepancias debe ser exactamente 0 para todas las evaluaciones.
-- ----------------------------------------------------------------------------------------------------
SELECT 'Personas: en OLTP pero no en Staging' AS Evaluacion_Bidireccional, COUNT(*) AS Cantidad_Discrepancias
FROM (
    SELECT id_persona FROM [NexoSaludDB].dbo.[Personas]
    EXCEPT
    SELECT id_persona FROM staging.stg_Personas
) diff1
UNION ALL
SELECT 'Personas: en Staging pero no en OLTP', COUNT(*)
FROM (
    SELECT id_persona FROM staging.stg_Personas
    EXCEPT
    SELECT id_persona FROM [NexoSaludDB].dbo.[Personas]
) diff2
UNION ALL
SELECT 'Solicitudes: en OLTP pero no en Staging', COUNT(*)
FROM (
    SELECT id_solicitud FROM [NexoSaludDB].dbo.[Solicitudes]
    EXCEPT
    SELECT id_solicitud FROM staging.stg_Solicitudes
) diff3
UNION ALL
SELECT 'Solicitudes: en Staging pero no en OLTP', COUNT(*)
FROM (
    SELECT id_solicitud FROM staging.stg_Solicitudes
    EXCEPT
    SELECT id_solicitud FROM [NexoSaludDB].dbo.[Solicitudes]
) diff4
UNION ALL
SELECT 'Interacciones: en OLTP pero no en Staging', COUNT(*)
FROM (
    SELECT id_interaccion FROM [NexoSaludDB].dbo.[Interacciones]
    EXCEPT
    SELECT id_interaccion FROM staging.stg_Interacciones
) diff5
UNION ALL
SELECT 'Interacciones: en Staging pero no en OLTP', COUNT(*)
FROM (
    SELECT id_interaccion FROM staging.stg_Interacciones
    EXCEPT
    SELECT id_interaccion FROM [NexoSaludDB].dbo.[Interacciones]
) diff6
UNION ALL
SELECT 'EventosEtapa: en OLTP pero no en Staging', COUNT(*)
FROM (
    SELECT id_evento_etapa FROM [NexoSaludDB].dbo.[EventosEtapa]
    EXCEPT
    SELECT id_evento_etapa FROM staging.stg_EventosEtapa
) diff7
UNION ALL
SELECT 'EventosEtapa: en Staging pero no en OLTP', COUNT(*)
FROM (
    SELECT id_evento_etapa FROM staging.stg_EventosEtapa
    EXCEPT
    SELECT id_evento_etapa FROM [NexoSaludDB].dbo.[EventosEtapa]
) diff8;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 4: Diagnóstico de Contactos Pseudonimizados Coincidentes (Sin Revelar Datos en Claro)
-- Criterio de Éxito: Reporta grupos de personas distintas que comparten el mismo hash de contacto.
-- Aclaración: Detecta coincidencias de valores normalizados; no demuestra identidad única de personas.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    'Coincidencia en Hash de Teléfono' AS Tipo_Coincidencia,
    COUNT(DISTINCT hash_telefono_sha256) AS Hashes_Con_Multiples_Personas,
    SUM(Personas_Por_Hash) AS Total_Personas_Involucradas
FROM (
    SELECT hash_telefono_sha256, COUNT(DISTINCT id_persona) AS Personas_Por_Hash
    FROM staging.stg_Personas
    WHERE hash_telefono_sha256 IS NOT NULL
    GROUP BY hash_telefono_sha256
    HAVING COUNT(DISTINCT id_persona) > 1
) g_tel
UNION ALL
SELECT 
    'Coincidencia en Hash de Email',
    COUNT(DISTINCT hash_email_sha256),
    SUM(Personas_Por_Hash)
FROM (
    SELECT hash_email_sha256, COUNT(DISTINCT id_persona) AS Personas_Por_Hash
    FROM staging.stg_Personas
    WHERE hash_email_sha256 IS NOT NULL
    GROUP BY hash_email_sha256
    HAVING COUNT(DISTINCT id_persona) > 1
) g_mail;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 5: Diagnóstico de Estados Desconocidos en Solicitudes
-- Criterio de Éxito: Identifica literales no mapeados que se clasifican como 'Desconocido'.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    estado_original,
    estado_solicitud_norm,
    COUNT(*) AS CantidadRegistros
FROM staging.stg_Solicitudes
WHERE es_solicitud_estado_desconocido = 1
GROUP BY estado_original, estado_solicitud_norm;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 6: Diagnóstico de Incoherencias entre Estado y Fechas en Solicitudes
-- Criterio de Éxito: Identifica registros con contradicción temporal sin inventar resultados comerciales.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    'Cierre registrado con estado abierto' AS Tipo_Incoherencia,
    COUNT(*) AS Cantidad_Solicitudes
FROM staging.stg_Solicitudes
WHERE tiene_cierre_sin_estado_resolutivo = 1
UNION ALL
SELECT 
    'Estado resolutivo sin fecha de cierre registrada',
    COUNT(*)
FROM staging.stg_Solicitudes
WHERE tiene_estado_resolutivo_sin_fecha_cierre = 1;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 7: Diagnóstico de Ambigüedad por Múltiples Opciones Seleccionadas
-- Criterio de Éxito: Detecta solicitudes con más de 1 opción marcada como seleccionada.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    tiene_multiple_opcion_seleccionada,
    COUNT(*) AS Cantidad_Solicitudes,
    AVG(CAST(cantidad_opciones_ofrecidas AS FLOAT)) AS Promedio_Opciones_Ofrecidas
FROM staging.stg_Solicitudes
GROUP BY tiene_multiple_opcion_seleccionada;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 8: Diagnóstico de Personas con Múltiples Solicitudes (Análisis de Recurrencia)
-- Criterio de Éxito: Identificación cuantitativa de pacientes recurrentes para no duplicar en BUYER.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    id_persona,
    COUNT(id_solicitud) AS Cantidad_Solicitudes,
    MIN(fecha_solicitud) AS Primera_Solicitud,
    MAX(fecha_solicitud) AS Ultima_Solicitud
FROM staging.stg_Solicitudes
GROUP BY id_persona
HAVING COUNT(id_solicitud) > 1;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 9: Diagnóstico de Solicitudes sin fecha_primera_respuesta (Punto Ciego de Runtime)
-- Aclaración Metodológica: La ausencia de fecha en la columna transaccional NO demuestra que no
-- haya existido respuesta; constata la falta de persistencia en tiempo de ejecución del backend.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    tiene_fecha_primera_respuesta,
    estado_solicitud_norm,
    COUNT(*) AS Cantidad_Solicitudes
FROM staging.stg_Solicitudes
GROUP BY tiene_fecha_primera_respuesta, estado_solicitud_norm;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 10: Interacciones Útiles Desconectadas Físicamente de Solicitudes
-- Criterio de Éxito: Cuantificación de interacciones útiles huérfanas de solicitud en el OLTP.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    i.es_respuesta_util,
    i.tipo_interaccion_norm,
    COUNT(*) AS Total_Interacciones,
    COUNT(DISTINCT i.id_persona) AS Personas_Involucradas
FROM staging.stg_Interacciones i
GROUP BY i.es_respuesta_util, i.tipo_interaccion_norm;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 11: Auditoría Cuantitativa de Completitud en Personas (BUYER)
-- Criterio de Éxito: Diagnóstico cuantitativo de cobertura sin exponer datos personales en claro.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    COUNT(*) AS Total_Personas,
    SUM(tiene_nombres) AS Con_Nombres,
    SUM(tiene_apellidos) AS Con_Apellidos,
    SUM(tiene_dni) AS Con_DNI,
    SUM(es_dni_valido_8d) AS Con_DNI_Valido_8D,
    SUM(tiene_email) AS Con_Email,
    SUM(es_email_formato_valido) AS Con_Email_Valido,
    SUM(tiene_telefono) AS Con_Telefono,
    SUM(es_celular_pe_valido) AS Con_Celular_Peru_Valido,
    SUM(tiene_telefono_otro_formato) AS Con_Telefono_Otro_Formato,
    SUM(requiere_revision_contactabilidad) AS Requieren_Revision_Contactabilidad,
    SUM(tiene_autorizacion_contacto) AS Con_Autorizacion_Contacto,
    SUM(es_calidad_valida) AS Con_Calidad_Valida,
    SUM(es_contacto_utilizable_tecnico) AS Total_Contactos_Utilizables_Tecnicos
FROM staging.stg_Personas;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 12: Detección de Integridad Referencial Huérfana en el OLTP
-- Criterio de Éxito: La columna Cantidad_Huerfanos debe ser 0.
-- ----------------------------------------------------------------------------------------------------
SELECT 'Solicitudes sin Persona' AS Tipo_Huerfano, COUNT(*) AS Cantidad_Huerfanos
FROM staging.stg_Solicitudes s
LEFT JOIN staging.stg_Personas p ON s.id_persona = p.id_persona
WHERE p.id_persona IS NULL
UNION ALL
SELECT 'Interacciones sin Persona', COUNT(*)
FROM staging.stg_Interacciones i
LEFT JOIN staging.stg_Personas p ON i.id_persona = p.id_persona
WHERE p.id_persona IS NULL
UNION ALL
SELECT 'EventosEtapa sin Persona', COUNT(*)
FROM staging.stg_EventosEtapa e
LEFT JOIN staging.stg_Personas p ON e.id_persona = p.id_persona
WHERE p.id_persona IS NULL;
GO

-- ----------------------------------------------------------------------------------------------------
-- Test 13: Consistencia Cronológica de Fechas en Solicitudes
-- Criterio de Éxito: 0 filas devueltas con fechas anómalas.
-- ----------------------------------------------------------------------------------------------------
SELECT 
    id_solicitud,
    fecha_solicitud,
    fecha_primera_respuesta,
    fecha_cierre,
    CASE WHEN fecha_primera_respuesta < fecha_solicitud THEN 'Respuesta Anterior a Solicitud' ELSE 'OK' END AS Check_Respuesta,
    CASE WHEN fecha_cierre < fecha_solicitud THEN 'Cierre Anterior a Solicitud' ELSE 'OK' END AS Check_Cierre
FROM staging.stg_Solicitudes
WHERE fecha_primera_respuesta < fecha_solicitud 
   OR fecha_cierre < fecha_solicitud;
GO

-- ====================================================================================================
-- 7. SUITE DE PRUEBAS DE TRANSFORMACIÓN CON CASOS SINTÉTICOS VERIFICABLES (VALUES)
-- Instrucción: Este bloque es totalmente autónomo, no lee tablas del proyecto ni expone datos reales.
-- Permite verificar estáticamente las reglas de negocio sin depender de bases de datos existentes,
-- pero REQUIERE un motor T-SQL compatible para su ejecución física efectiva.
--
-- REGLAS DE EVALUACIÓN:
--   - Los resultados de cada suite se acumulan en una tabla temporal de sesión (#ResultadosEvaluacion).
--   - Cada caso compara estrictamente contra un resultado esperado explícito.
--   - Devuelve 'CORRECTO' únicamente si todos los campos coinciden exactamente; de lo contrario devuelve 'FALLO'.
--   - Se incluye un Control Negativo del Evaluador (separado del resumen) para verificar que el detector
--     identifica discrepancias intencionales y no aprueba pasivamente.
--   - El Resumen Consolidado se calcula dinámicamente a partir de los resultados reales de la tabla temporal.
-- ====================================================================================================

-- ----------------------------------------------------------------------------------------------------
-- 7.0 Preparación de la Tabla Temporal de Sesión para Almacenar Resultados de Evaluación
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#ResultadosEvaluacion') IS NOT NULL 
    DROP TABLE #ResultadosEvaluacion;
CREATE TABLE #ResultadosEvaluacion (
    suite_nombre    VARCHAR(100) NOT NULL,
    id_caso         INT NOT NULL,
    desc_caso       VARCHAR(255) NOT NULL,
    resultado_test  VARCHAR(20) NOT NULL
);
GO

-- ----------------------------------------------------------------------------------------------------
-- Suite Sintética 1: Contactabilidad, Normalización Telefónica y Hashes de Email/Teléfono
-- Cobertura Telefónica: 9d directo, +51, 51, separadores ' ', '-', '.', '(', ')', '/', nulos, vacíos,
--                      blancos, extranjeros (prefijo OTRO:) e inválidos.
--   - NULL, vacío ('') y espacios ('   ') deben producir hash estrictamente NULL.
--   - Variantes equivalentes tras trim y minúsculas deben producir el mismo hash que el baseline para detección de coincidencias,
--     pero normalizar un valor para hash NO acredita su formato original como medio de contacto válido (con espacios: esp_email_val = 0, esp_req_rev = 1).
--   - Correo normalizado diferente produce un hash diferente (no colisiona en los casos de prueba).
-- Cobertura Contactabilidad:
--   - Requiere revisión si y solo si carece de celular PE válido y carece de email válido.
-- ----------------------------------------------------------------------------------------------------
WITH CasosContactos AS (
    SELECT * FROM (VALUES 
        -- ID, Tel_Raw, Email_Raw, Esp_CelPE, Esp_EmailVal, Esp_ReqRev, Esp_HashTelNull, Esp_IgualHashTel1, Esp_HashMailNull, Esp_IgualHashMail1, Esp_DistintoHashMail1, Descripcion
        (1,  '987654321',          'paciente@luxedent.pe',          1, 1, 0, 0, 1, 0, 1, 0, 'Baseline: Celular PE 9d y email valido'),
        (2,  '+51987654321',        NULL,                            1, 0, 0, 0, 1, 1, 0, 0, 'Celular PE con +51 sin correo'),
        (3,  '51987654321',         NULL,                            1, 0, 0, 0, 1, 1, 0, 0, 'Celular PE con 51 sin correo'),
        (4,  '+51 987-654-321',     NULL,                            1, 0, 0, 0, 1, 1, 0, 0, 'Celular PE con espacios y guiones sin correo'),
        (5,  '(51) 987.654.321',    NULL,                            1, 0, 0, 0, 1, 1, 0, 0, 'Celular PE con parentesis y puntos sin correo'),
        (6,  '+51/987654321',       NULL,                            1, 0, 0, 0, 1, 1, 0, 0, 'Celular PE con barra inclinada sin correo'),
        (7,  NULL,                  NULL,                            0, 0, 1, 1, 0, 1, 0, 0, 'Ambos medios NULL: hashes estrictamente NULL'),
        (8,  '',                    '',                              0, 0, 1, 1, 0, 1, 0, 0, 'Ambos medios vacios: hashes estrictamente NULL'),
        (9,  '   ',                 '   ',                           0, 0, 1, 1, 0, 1, 0, 0, 'Ambos medios con espacios: hashes estrictamente NULL'),
        (10, NULL,                  'PACIENTE@LUXEDENT.PE',          0, 1, 0, 1, 0, 0, 1, 0, 'Email mayusculas: hash identico tras lowercase (formato valido sin espacios)'),
        (11, NULL,                  '   paciente@luxedent.pe   ',    0, 0, 1, 1, 0, 0, 1, 0, 'Email con espacios: formato raw no valido (espacios), requiere revision (1), pero hash normalizado identico tras trim (normalizar no acredita contacto)'),
        (12, NULL,                  '  PaCieNTe@LuxeDent.PE  ',      0, 0, 1, 1, 0, 0, 1, 0, 'Email mixto mayusculas y espacios: formato raw no valido, requiere revision (1), pero hash normalizado identico (normalizar no acredita contacto)'),
        (13, NULL,                  'otro.paciente@luxedent.pe',     0, 1, 0, 1, 0, 0, 0, 1, 'Email diferente: produce hash distinto al baseline'),
        (14, NULL,                  'correo_sin_arroba_ni_punto',    0, 0, 1, 1, 0, 0, 0, 1, 'Telefono NULL con correo invalido: requiere revision'),
        (15, '999888777',           'correo_invalido',               1, 0, 0, 0, 0, 0, 0, 1, 'Celular valido con correo invalido: no requiere revision'),
        (16, '+1 555-123-4567',     NULL,                            0, 0, 1, 0, 0, 1, 0, 0, 'Extranjero USA: requiere revision, hash prefijo OTRO'),
        (17, '044234567',           NULL,                            0, 0, 1, 0, 0, 1, 0, 0, 'Fijo Trujillo: requiere revision, hash prefijo OTRO'),
        (18, '98765',               NULL,                            0, 0, 1, 0, 0, 1, 0, 0, 'Telefono invalido 5d: requiere revision')
    ) AS c(id_caso, tel_raw, email_raw, esp_cel_pe, esp_email_val, esp_req_rev, esp_hash_tel_null, esp_igual_hash_tel1, esp_hash_mail_null, esp_igual_hash_mail1, esp_distinto_hash_mail1, desc_caso)
),
LimpiezaContactos AS (
    SELECT 
        cc.*,
        NULLIF(
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
                LTRIM(RTRIM(cc.tel_raw)),
                ' ', ''), '-', ''), '.', ''), '(', ''), ')', ''), '/', ''),
            '') AS tel_limpio
    FROM CasosContactos cc
),
TransformacionContactos AS (
    SELECT 
        lc.*,
        CASE 
            WHEN lc.tel_limpio IS NULL THEN 0
            WHEN lc.tel_limpio LIKE '9[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' AND LEN(lc.tel_limpio) = 9 THEN 1
            WHEN lc.tel_limpio LIKE '+519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' AND LEN(lc.tel_limpio) = 12 THEN 1
            WHEN lc.tel_limpio LIKE '519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' AND LEN(lc.tel_limpio) = 11 THEN 1
            ELSE 0
        END AS calc_es_celular_pe_valido,
        CASE 
            WHEN lc.tel_limpio LIKE '9[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' AND LEN(lc.tel_limpio) = 9 THEN lc.tel_limpio
            WHEN lc.tel_limpio LIKE '+519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' AND LEN(lc.tel_limpio) = 12 THEN SUBSTRING(lc.tel_limpio, 4, 9)
            WHEN lc.tel_limpio LIKE '519[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]' AND LEN(lc.tel_limpio) = 11 THEN SUBSTRING(lc.tel_limpio, 3, 9)
            ELSE NULL
        END AS calc_tel_pe_canonico,
        CASE 
            WHEN lc.email_raw LIKE '%_@__%.__%' AND lc.email_raw NOT LIKE '% %' THEN 1 
            ELSE 0 
        END AS calc_es_email_valido
    FROM LimpiezaContactos lc
),
HashesContactos AS (
    SELECT 
        tc.*,
        CASE 
            WHEN tc.tel_limpio IS NULL THEN NULL
            WHEN tc.calc_es_celular_pe_valido = 1 THEN HASHBYTES('SHA2_256', tc.calc_tel_pe_canonico)
            ELSE HASHBYTES('SHA2_256', CONCAT('OTRO:', tc.tel_limpio))
        END AS calc_hash_tel,
        CASE 
            WHEN NULLIF(LTRIM(RTRIM(tc.email_raw)), '') IS NOT NULL 
            THEN HASHBYTES('SHA2_256', LOWER(LTRIM(RTRIM(tc.email_raw))))
            ELSE NULL 
        END AS calc_hash_email,
        CASE 
            WHEN tc.calc_es_celular_pe_valido = 0 AND tc.calc_es_email_valido = 0 
            THEN 1 
            ELSE 0 
        END AS calc_requiere_revision
    FROM TransformacionContactos tc
),
HashesReferenciaCaso1 AS (
    SELECT 
        calc_hash_tel AS hash_tel_base,
        calc_hash_email AS hash_mail_base
    FROM HashesContactos 
    WHERE id_caso = 1
),
EvaluacionContactos AS (
    SELECT 
        hc.id_caso,
        hc.desc_caso,
        hc.calc_es_celular_pe_valido,
        hc.calc_es_email_valido,
        hc.calc_requiere_revision,
        hc.calc_hash_tel,
        hc.calc_hash_email,
        CASE 
            -- Coincidencia de banderas
            WHEN hc.calc_es_celular_pe_valido = hc.esp_cel_pe
                 AND hc.calc_es_email_valido = hc.esp_email_val
                 AND hc.calc_requiere_revision = hc.esp_req_rev
                 -- Comprobacion de hash de telefono (NULL o valor)
                 AND (
                     (hc.esp_hash_tel_null = 1 AND hc.calc_hash_tel IS NULL)
                     OR (hc.esp_hash_tel_null = 0 AND hc.calc_hash_tel IS NOT NULL)
                 )
                 -- Comprobacion de equivalencia de hash de telefono con Caso 1
                 AND (
                     (hc.esp_igual_hash_tel1 = 1 AND hc.calc_hash_tel = ref1.hash_tel_base)
                     OR (hc.esp_igual_hash_tel1 = 0 AND (hc.calc_hash_tel <> ref1.hash_tel_base OR hc.calc_hash_tel IS NULL))
                 )
                 -- Comprobacion de hash de email (NULL o valor)
                 AND (
                     (hc.esp_hash_mail_null = 1 AND hc.calc_hash_email IS NULL)
                     OR (hc.esp_hash_mail_null = 0 AND hc.calc_hash_email IS NOT NULL)
                 )
                 -- Comprobacion de equivalencia de hash de email con Caso 1
                 AND (
                     (hc.esp_igual_hash_mail1 = 1 AND hc.calc_hash_email = ref1.hash_mail_base)
                     OR (hc.esp_igual_hash_mail1 = 0 AND (hc.calc_hash_email <> ref1.hash_mail_base OR hc.calc_hash_email IS NULL))
                 )
                 -- Comprobacion de email diferente produciendo hash diferente al Caso 1
                 AND (
                     (hc.esp_distinto_hash_mail1 = 1 AND hc.calc_hash_email <> ref1.hash_mail_base AND hc.calc_hash_email IS NOT NULL)
                     OR (hc.esp_distinto_hash_mail1 = 0)
                 )
            THEN 'CORRECTO'
            ELSE 'FALLO'
        END AS resultado_test
    FROM HashesContactos hc
    CROSS JOIN HashesReferenciaCaso1 ref1
)
INSERT INTO #ResultadosEvaluacion (suite_nombre, id_caso, desc_caso, resultado_test)
SELECT 'Suite 1: Contactabilidad, Normalizacion Telefonica y Hashes', id_caso, desc_caso, resultado_test
FROM EvaluacionContactos;

-- Proyección de resultados de la Suite 1 desde la tabla temporal de sesión:
SELECT id_caso, desc_caso, resultado_test
FROM #ResultadosEvaluacion
WHERE suite_nombre = 'Suite 1: Contactabilidad, Normalizacion Telefonica y Hashes'
ORDER BY id_caso ASC;
GO

-- ----------------------------------------------------------------------------------------------------
-- Suite Sintética 2: Mapeo de Estados de Solicitud (Convertida, Cancelación y Cobertura Exhaustiva)
-- ----------------------------------------------------------------------------------------------------
WITH CasosEstados AS (
    SELECT * FROM (VALUES 
        (1,  'Abierta',         'Abierta',      'Abierta capitalizada'),
        (2,  'NUEVA',           'Abierta',      'Nueva en mayusculas'),
        (3,  'abierto',         'Abierta',      'Abierto minusculas'),
        (4,  'En Negociacion',  'En Negociacion','Negociacion estandar'),
        (5,  'EN NEGOCIACIÓN',  'En Negociacion','Negociacion con tilde'),
        (6,  'Reserva',         'Reserva',      'Reserva estandar'),
        (7,  'PRE-RESERVA',     'Reserva',      'Pre-reserva con guion'),
        (8,  'Confirmada',      'Confirmada',   'Confirmada estandar'),
        (9,  'CONFIRMADO',      'Confirmada',   'Confirmado masculino'),
        (10, 'Convertida',      'Convertida',   'Convertida backend lead.routes.ts'),
        (11, 'CONVERTIDO',      'Convertida',   'Convertido mayusculas'),
        (12, 'Cancelada',       'Cancelada',    'Cancelada preservada no fusionada'),
        (13, 'CANCELADO',       'Cancelada',    'Cancelado masculino'),
        (14, 'Descartada',      'Descartada',   'Descartada preservada no fusionada'),
        (15, 'DESCARTADO',      'Descartada',   'Descartado mayusculas'),
        (16, 'Abandonada',      'Abandonada',   'Abandonada estandar'),
        (17, 'ABANDONADO',      'Abandonada',   'Abandonado masculino'),
        (18, 'Perdida',         'Perdida',      'Perdida estandar'),
        (19, 'PERDIDO',         'Perdida',      'Perdido masculino'),
        (20, 'Literal No Visto','Desconocido',  'Estado no reconocido'),
        (21, '',                'Desconocido',  'Estado vacio'),
        (22, NULL,              'Desconocido',  'Estado NULL')
    ) AS e(id_caso, estado_raw, estado_esperado_norm, desc_caso)
),
EvaluacionEstados AS (
    SELECT 
        ce.id_caso,
        ce.desc_caso,
        ce.estado_raw,
        ce.estado_esperado_norm,
        CASE 
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('ABIERTA', 'ABIERTO', 'NUEVA', 'NUEVO') THEN 'Abierta'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('EN NEGOCIACION', 'EN NEGOCIACIÓN', 'NEGOCIACION', 'NEGOCIANDO') THEN 'En Negociacion'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('RESERVA', 'RESERVADA', 'PRE-RESERVA', 'PRE RESERVA') THEN 'Reserva'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('CONFIRMADA', 'CONFIRMADO') THEN 'Confirmada'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('CONVERTIDA', 'CONVERTIDO') THEN 'Convertida'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('CANCELADA', 'CANCELADO') THEN 'Cancelada'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('DESCARTADA', 'DESCARTADO') THEN 'Descartada'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('ABANDONADA', 'ABANDONADO') THEN 'Abandonada'
            WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('PERDIDA', 'PERDIDO') THEN 'Perdida'
            ELSE 'Desconocido'
        END AS estado_solicitud_norm,
        CASE 
            WHEN (
                CASE 
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('ABIERTA', 'ABIERTO', 'NUEVA', 'NUEVO') THEN 'Abierta'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('EN NEGOCIACION', 'EN NEGOCIACIÓN', 'NEGOCIACION', 'NEGOCIANDO') THEN 'En Negociacion'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('RESERVA', 'RESERVADA', 'PRE-RESERVA', 'PRE RESERVA') THEN 'Reserva'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('CONFIRMADA', 'CONFIRMADO') THEN 'Confirmada'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('CONVERTIDA', 'CONVERTIDO') THEN 'Convertida'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('CANCELADA', 'CANCELADO') THEN 'Cancelada'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('DESCARTADA', 'DESCARTADO') THEN 'Descartada'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('ABANDONADA', 'ABANDONADO') THEN 'Abandonada'
                    WHEN UPPER(LTRIM(RTRIM(ISNULL(ce.estado_raw, '')))) IN ('PERDIDA', 'PERDIDO') THEN 'Perdida'
                    ELSE 'Desconocido'
                END
            ) = ce.estado_esperado_norm 
            THEN 'CORRECTO'
            ELSE 'FALLO'
        END AS resultado_test
    FROM CasosEstados ce
)
INSERT INTO #ResultadosEvaluacion (suite_nombre, id_caso, desc_caso, resultado_test)
SELECT 'Suite 2: Estados de Solicitud', id_caso, desc_caso, resultado_test
FROM EvaluacionEstados;

-- Proyección de resultados de la Suite 2 desde la tabla temporal de sesión:
SELECT id_caso, desc_caso, resultado_test
FROM #ResultadosEvaluacion
WHERE suite_nombre = 'Suite 2: Estados de Solicitud'
ORDER BY id_caso ASC;
GO

-- ----------------------------------------------------------------------------------------------------
-- Suite Sintética 3: Categorías de Resultado en Interacciones (Sin inferencia amplia ni ignorar negaciones)
-- Cobertura: "No interesado", "Interesado", "Reserva cancelada", "Cita agendada", equivalencias completas.
-- ----------------------------------------------------------------------------------------------------
WITH CasosResultados AS (
    SELECT * FROM (VALUES 
        (1,  'No interesado',           'No Interesado',      'Negacion explicita'),
        (2,  'NO INTERESADA',           'No Interesado',      'Negacion femenina mayusculas'),
        (3,  'Interesado',              'Interesado',         'Afirmativo directo'),
        (4,  'INTERESADA',              'Interesado',         'Afirmativo femenino'),
        (5,  'Cita agendada',           'Cita Agendada',      'Agendado estandar'),
        (6,  'Reserva agendada',        'Cita Agendada',      'Reserva agendada'),
        (7,  'Reserva cancelada',       'Reserva Cancelada',  'Cancelacion explicita no agendada'),
        (8,  'Cita cancelada',          'Reserva Cancelada',  'Cita cancelada explicita'),
        (9,  'No contesta',             'No Contactado',      'Sin respuesta telefonica'),
        (10, 'Buzon de voz',            'No Contactado',      'Buzon directo'),
        (11, 'En seguimiento',          'En Seguimiento',     'Seguimiento activo'),
        (12, NULL,                      'Sin Resultado',      'Resultado NULL'),
        (13, '',                        'Sin Resultado',      'Resultado vacio'),
        (14, 'Paciente refiere dolor',  'Otro / No Tipificado','Texto clinico particular no reconocido')
    ) AS r(id_caso, resultado_raw, categoria_esperada, desc_caso)
),
EvaluacionResultados AS (
    SELECT 
        cr.id_caso,
        cr.desc_caso,
        cr.resultado_raw,
        cr.categoria_esperada,
        CASE 
            WHEN cr.resultado_raw IS NULL OR LTRIM(RTRIM(cr.resultado_raw)) = '' 
                THEN 'Sin Resultado'
            WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                'CITA AGENDADA', 'AGENDADO', 'AGENDADA', 'RESERVA AGENDADA', 'CITA CONFIRMADA', 'TURNO ASIGNADO'
            ) THEN 'Cita Agendada'
            WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                'INTERESADO', 'INTERESADA', 'SOLICITA COTIZACION', 'SOLICITA INFORMACION', 'EN EVALUACION'
            ) THEN 'Interesado'
            WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                'NO INTERESADO', 'NO INTERESADA', 'NO DESEA', 'RECHAZADO', 'RECHAZADA', 'DESCARTADO'
            ) THEN 'No Interesado'
            WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                'NO CONTACTADO', 'NO CONTESTA', 'NO RESPONDE', 'BUZON DE VOZ', 'BUZÓN DE VOZ', 'NUMERO EQUIVOCADO', 'NÚMERO EQUIVOCADO'
            ) THEN 'No Contactado'
            WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                'RESERVA CANCELADA', 'CITA CANCELADA', 'CANCELADO', 'CANCELADA', 'CITA ANULADA'
            ) THEN 'Reserva Cancelada'
            WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                'EN SEGUIMIENTO', 'PENDIENTE DE RESPUESTA', 'RELLAMAR', 'VOLVER A LLAMAR'
            ) THEN 'En Seguimiento'
            ELSE 'Otro / No Tipificado'
        END AS calc_categoria_norm,
        CASE 
            WHEN (
                CASE 
                    WHEN cr.resultado_raw IS NULL OR LTRIM(RTRIM(cr.resultado_raw)) = '' 
                        THEN 'Sin Resultado'
                    WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                        'CITA AGENDADA', 'AGENDADO', 'AGENDADA', 'RESERVA AGENDADA', 'CITA CONFIRMADA', 'TURNO ASIGNADO'
                    ) THEN 'Cita Agendada'
                    WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                        'INTERESADO', 'INTERESADA', 'SOLICITA COTIZACION', 'SOLICITA INFORMACION', 'EN EVALUACION'
                    ) THEN 'Interesado'
                    WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                        'NO INTERESADO', 'NO INTERESADA', 'NO DESEA', 'RECHAZADO', 'RECHAZADA', 'DESCARTADO'
                    ) THEN 'No Interesado'
                    WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                        'NO CONTACTADO', 'NO CONTESTA', 'NO RESPONDE', 'BUZON DE VOZ', 'BUZÓN DE VOZ', 'NUMERO EQUIVOCADO', 'NÚMERO EQUIVOCADO'
                    ) THEN 'No Contactado'
                    WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                        'RESERVA CANCELADA', 'CITA CANCELADA', 'CANCELADO', 'CANCELADA', 'CITA ANULADA'
                    ) THEN 'Reserva Cancelada'
                    WHEN UPPER(LTRIM(RTRIM(cr.resultado_raw))) IN (
                        'EN SEGUIMIENTO', 'PENDIENTE DE RESPUESTA', 'RELLAMAR', 'VOLVER A LLAMAR'
                    ) THEN 'En Seguimiento'
                    ELSE 'Otro / No Tipificado'
                END
            ) = cr.categoria_esperada 
            THEN 'CORRECTO'
            ELSE 'FALLO'
        END AS resultado_test
    FROM CasosResultados cr
)
INSERT INTO #ResultadosEvaluacion (suite_nombre, id_caso, desc_caso, resultado_test)
SELECT 'Suite 3: Categorias de Interacciones', id_caso, desc_caso, resultado_test
FROM EvaluacionResultados;

-- Proyección de resultados de la Suite 3 desde la tabla temporal de sesión:
SELECT id_caso, desc_caso, resultado_test
FROM #ResultadosEvaluacion
WHERE suite_nombre = 'Suite 3: Categorias de Interacciones'
ORDER BY id_caso ASC;
GO

-- ----------------------------------------------------------------------------------------------------
-- Suite Sintética 4: Opciones, Reservas y Agregados sin Registros
-- Cobertura: Solicitud sin opciones ni reservas devuelve ceros en conteos y banderas, y NULL en precios/fechas.
--            Determinismo de primer precio cronológico vs MIN(precio).
--            Ambigüedad ante múltiples opciones seleccionadas (devuelve NULL, no MAX).
-- ----------------------------------------------------------------------------------------------------
WITH SolicitudesSinteticas AS (
    SELECT * FROM (VALUES 
        (101, 'Solicitud con opciones cronologicas y 1 seleccionada'),
        (102, 'Solicitud con multiple seleccion (ambiguedad)'),
        (103, 'Solicitud sin opciones ni reservas (agregados cero, importes null)')
    ) AS s(id_solicitud, desc_caso)
),
OpcionesSinteticas AS (
    SELECT * FROM (VALUES 
        -- Solicitud 101: Opcion 1 ofrecida primero cuesta 500; Opcion 2 ofrecida despues cuesta 300 (seleccionada)
        (101, 1, CAST('2026-09-01 10:00:00' AS DATETIME2), CAST(500.00 AS DECIMAL(10,2)), 0),
        (101, 2, CAST('2026-09-02 14:00:00' AS DATETIME2), CAST(300.00 AS DECIMAL(10,2)), 1),
        -- Solicitud 102: Dos opciones seleccionadas
        (102, 1, CAST('2026-09-05 09:00:00' AS DATETIME2), CAST(200.00 AS DECIMAL(10,2)), 1),
        (102, 2, CAST('2026-09-06 11:00:00' AS DATETIME2), CAST(450.00 AS DECIMAL(10,2)), 1)
        -- Solicitud 103: Sin filas en Opciones
    ) AS o(id_solicitud, id_opcion, fecha_ofrecida, precio_ofrecido, seleccionada)
),
ReservasSinteticas AS (
    SELECT * FROM (VALUES 
        -- Solicitud 101: 1 reserva confirmada
        (101, 1, CAST('2026-09-02 15:00:00' AS DATETIME2), 'Confirmada', CAST(1 AS BIT), CAST('2026-09-02 16:00:00' AS DATETIME2))
        -- Solicitudes 102 y 103: Sin reservas
    ) AS r(id_solicitud, id_reserva, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
),
TransformacionSolicitudes AS (
    SELECT 
        ss.id_solicitud,
        ss.desc_caso,
        -- Agregados Opciones
        opc_agg.cantidad_opciones_ofrecidas,
        opc_agg.cantidad_opciones_seleccionadas,
        opc_agg.precio_cotizado_seleccionado,
        opc_agg.tiene_multiple_opcion_seleccionada,
        opc_prim.primer_precio_ofrecido,
        -- Agregados Reservas
        res_agg.cantidad_reservas_asociadas,
        res_agg.tiene_alguna_reserva_confirmada,
        res_prim.id_primera_reserva,
        res_prim.primera_fecha_reserva
    FROM SolicitudesSinteticas ss
    OUTER APPLY (
        SELECT TOP 1 
            o1.id_opcion AS id_primera_opcion,
            o1.precio_ofrecido AS primer_precio_ofrecido,
            o1.fecha_ofrecida AS fecha_primer_precio_ofrecido
        FROM OpcionesSinteticas o1
        WHERE o1.id_solicitud = ss.id_solicitud
        ORDER BY o1.fecha_ofrecida ASC, o1.id_opcion ASC
    ) opc_prim
    OUTER APPLY (
        SELECT 
            COALESCE(COUNT(o2.id_opcion), 0) AS cantidad_opciones_ofrecidas,
            COALESCE(SUM(CASE WHEN o2.seleccionada = 1 THEN 1 ELSE 0 END), 0) AS cantidad_opciones_seleccionadas,
            CASE 
                WHEN COALESCE(SUM(CASE WHEN o2.seleccionada = 1 THEN 1 ELSE 0 END), 0) = 1 
                THEN MAX(CASE WHEN o2.seleccionada = 1 THEN o2.precio_ofrecido ELSE NULL END)
                ELSE NULL 
            END AS precio_cotizado_seleccionado,
            CASE 
                WHEN COALESCE(SUM(CASE WHEN o2.seleccionada = 1 THEN 1 ELSE 0 END), 0) > 1 THEN 1 
                ELSE 0 
            END AS tiene_multiple_opcion_seleccionada
        FROM OpcionesSinteticas o2
        WHERE o2.id_solicitud = ss.id_solicitud
    ) opc_agg
    OUTER APPLY (
        SELECT TOP 1 
            r1.id_reserva AS id_primera_reserva,
            r1.fecha_reserva AS primera_fecha_reserva
        FROM ReservasSinteticas r1
        WHERE r1.id_solicitud = ss.id_solicitud
        ORDER BY r1.fecha_reserva ASC, r1.id_reserva ASC
    ) res_prim
    OUTER APPLY (
        SELECT 
            COALESCE(COUNT(r2.id_reserva), 0) AS cantidad_reservas_asociadas,
            COALESCE(MAX(CASE WHEN r2.confirmacion_explicita = 1 THEN 1 ELSE 0 END), 0) AS tiene_alguna_reserva_confirmada
        FROM ReservasSinteticas r2
        WHERE r2.id_solicitud = ss.id_solicitud
    ) res_agg
),
EvaluacionSolicitudes AS (
    SELECT 
        ts.id_solicitud,
        ts.desc_caso,
        ts.cantidad_opciones_ofrecidas,
        ts.cantidad_opciones_seleccionadas,
        ts.primer_precio_ofrecido,
        ts.precio_cotizado_seleccionado,
        ts.tiene_multiple_opcion_seleccionada,
        ts.cantidad_reservas_asociadas,
        ts.tiene_alguna_reserva_confirmada,
        CASE 
            -- Caso 101: Primer precio cronologico es 500.00 (no 300.00), seleccionada es 300.00
            WHEN ts.id_solicitud = 101 
                 AND ts.primer_precio_ofrecido = 500.00 
                 AND ts.precio_cotizado_seleccionado = 300.00
                 AND ts.tiene_multiple_opcion_seleccionada = 0
                 AND ts.cantidad_reservas_asociadas = 1
                 AND ts.tiene_alguna_reserva_confirmada = 1
            THEN 'CORRECTO'
            -- Caso 102: Multiple seleccion -> precio seleccionado es NULL y bandera ambiguedad = 1
            WHEN ts.id_solicitud = 102 
                 AND ts.tiene_multiple_opcion_seleccionada = 1 
                 AND ts.precio_cotizado_seleccionado IS NULL
                 AND ts.cantidad_reservas_asociadas = 0
            THEN 'CORRECTO'
            -- Caso 103: Sin registros -> conteos 0, banderas 0, precios NULL, fechas NULL
            WHEN ts.id_solicitud = 103 
                 AND ts.cantidad_opciones_ofrecidas = 0 
                 AND ts.cantidad_opciones_seleccionadas = 0
                 AND ts.precio_cotizado_seleccionado IS NULL
                 AND ts.primer_precio_ofrecido IS NULL
                 AND ts.cantidad_reservas_asociadas = 0
                 AND ts.tiene_alguna_reserva_confirmada = 0
                 AND ts.id_primera_reserva IS NULL
                 AND ts.primera_fecha_reserva IS NULL
            THEN 'CORRECTO'
            ELSE 'FALLO'
        END AS resultado_test
    FROM TransformacionSolicitudes ts
)
INSERT INTO #ResultadosEvaluacion (suite_nombre, id_caso, desc_caso, resultado_test)
SELECT 'Suite 4: Opciones, Reservas y Ausencia de Registros', id_solicitud, desc_caso, resultado_test
FROM EvaluacionSolicitudes;

-- Proyección de resultados de la Suite 4 desde la tabla temporal de sesión:
SELECT id_caso, desc_caso, resultado_test
FROM #ResultadosEvaluacion
WHERE suite_nombre = 'Suite 4: Opciones, Reservas y Ausencia de Registros'
ORDER BY id_caso ASC;
GO

-- ----------------------------------------------------------------------------------------------------
-- 7.5 CONTROL NEGATIVO DEL EVALUADOR (PRUEBA DEL DETECTOR DE DISCREPANCIAS)
-- Propósito Metodológico:
--   Demostrar que la lógica de evaluación no aprueba pasivamente cualquier valor.
--   Se inyecta deliberadamente un resultado diferente del esperado.
--   La prueba del detector es EXITOSA únicamente si la discrepancia es detectada como 'FALLO'.
-- NOTA IMPORTANTE:
--   Este control se evalúa y exhibe por separado; NO se inserta en #ResultadosEvaluacion
--   para no alterar el resumen de las transformaciones de negocio correctas.
-- ----------------------------------------------------------------------------------------------------
WITH ControlNegativoDiscrepancia AS (
    SELECT * FROM (VALUES 
        (1, 'Estado calculado Abierta vs Esperado Confirmada (Discrepancia Deliberada)', 
            'Abierta',       -- Valor obtenido
            'Confirmada'     -- Valor esperado falsamente inyectado
        ),
        (2, 'Hash obtenido 0x123 vs Hash esperado 0xABC (Discrepancia Deliberada en Hash)',
            '0x12345678',   -- Valor obtenido
            '0xABCDEF01'    -- Valor esperado falsamente inyectado
        )
    ) AS d(id_control, descripcion_prueba, valor_obtenido, valor_esperado_falso)
),
EvaluacionDetector AS (
    SELECT 
        cnd.id_control,
        cnd.descripcion_prueba,
        cnd.valor_obtenido,
        cnd.valor_esperado_falso,
        -- Lógica del detector idéntica a la empleada en las suites:
        CASE 
            WHEN cnd.valor_obtenido = cnd.valor_esperado_falso THEN 'CORRECTO' 
            ELSE 'FALLO' 
        END AS veredicto_emitido_por_detector,
        -- Meta-evaluación del detector: Éxito si identificó el fallo intencional
        CASE 
            WHEN (CASE WHEN cnd.valor_obtenido = cnd.valor_esperado_falso THEN 'CORRECTO' ELSE 'FALLO' END) = 'FALLO'
            THEN 'CORRECTO: Detector identifico exitosamente el fallo intencional'
            ELSE 'FALLO CRITICO: El detector no detecto la discrepancia'
        END AS resultado_prueba_detector
    FROM ControlNegativoDiscrepancia cnd
)
SELECT 
    id_control,
    descripcion_prueba,
    valor_obtenido,
    valor_esperado_falso,
    veredicto_emitido_por_detector AS Veredicto_Detector_Debe_Ser_FALLO,
    resultado_prueba_detector AS Estado_Control_Detector
FROM EvaluacionDetector 
ORDER BY id_control ASC;
GO

-- ----------------------------------------------------------------------------------------------------
-- 7.6 RESUMEN CONSOLIDADO CALCULADO A PARTIR DE LOS RESULTADOS EFECTIVOS (#ResultadosEvaluacion)
-- Instrucción:
--   Este resumen NO contiene cifras fijas. Se calcula agregando dinámicamente las evaluaciones reales
--   almacenadas en la tabla temporal de sesión #ResultadosEvaluacion.
-- Criterio de Éxito:
--   Estado = 'CORRECTO' únicamente si Casos_Fallidos = 0 y Total_Casos = Casos_Esperados.
-- ----------------------------------------------------------------------------------------------------
WITH MetasSuites AS (
    SELECT * FROM (VALUES 
        ('Suite 1: Contactabilidad, Normalizacion Telefonica y Hashes', 18),
        ('Suite 2: Estados de Solicitud', 22),
        ('Suite 3: Categorias de Interacciones', 14),
        ('Suite 4: Opciones, Reservas y Ausencia de Registros', 3)
    ) AS m(suite_nombre, casos_esperados)
)
SELECT 
    m.suite_nombre AS Suite_Prueba,
    COUNT(r.id_caso) AS Total_Casos,
    COALESCE(SUM(CASE WHEN r.resultado_test = 'CORRECTO' THEN 1 ELSE 0 END), 0) AS Casos_Correctos,
    COALESCE(SUM(CASE WHEN r.resultado_test = 'FALLO' THEN 1 ELSE 0 END), 0) AS Casos_Fallidos,
    CASE 
        WHEN COUNT(r.id_caso) = m.casos_esperados 
             AND COALESCE(SUM(CASE WHEN r.resultado_test = 'FALLO' THEN 1 ELSE 0 END), 0) = 0 
        THEN 'CORRECTO' 
        ELSE 'FALLO' 
    END AS Estado
FROM MetasSuites m
LEFT JOIN #ResultadosEvaluacion r ON m.suite_nombre = r.suite_nombre
GROUP BY m.suite_nombre, m.casos_esperados
UNION ALL
SELECT 
    '>>> TOTAL CONSOLIDADO <<<' AS Suite_Prueba,
    COUNT(*) AS Total_Casos,
    COALESCE(SUM(CASE WHEN resultado_test = 'CORRECTO' THEN 1 ELSE 0 END), 0) AS Casos_Correctos,
    COALESCE(SUM(CASE WHEN resultado_test = 'FALLO' THEN 1 ELSE 0 END), 0) AS Casos_Fallidos,
    CASE 
        WHEN COALESCE(SUM(CASE WHEN resultado_test = 'FALLO' THEN 1 ELSE 0 END), 0) = 0 
             AND COUNT(*) = 57 -- Suma total esperada de casos (18 + 22 + 14 + 3)
        THEN 'CORRECTO' 
        ELSE 'FALLO' 
    END AS Estado
FROM #ResultadosEvaluacion;
GO

PRINT '>> Script de staging, perfilamiento y casos sintéticos H3 completado exitosamente.';
GO
