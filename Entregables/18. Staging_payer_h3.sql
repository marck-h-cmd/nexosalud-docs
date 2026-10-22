-- ====================================================================================================
-- NEXOSALUD — DATA MART DIMENSIONAL (CLÍNICA LUXEDENT, TRUJILLO)
-- Hito H3 (Fase 1): Extracción, Normalización y Perfilamiento de Datos — Etapa PAYER
-- ====================================================================================================
-- Titular del Rol   : Jesús Daniel Ordóñez Ugarte (Integrante 4 — ETL PAYER, Gestión Financiera)
-- Documento de Soporte: Entregables/18. Matriz_reglas_monetarias_y_diseno_payer_h3.md
-- Documento Contractual Base: Entregables/12. Contrato_y_dependencias_h3_mario.md
-- Referencia Técnica de Patrón: Entregables/13. Staging_buyer_lead_h3.sql (Mario A. Martínez Domínguez)
-- Versión de Referencia OLTP: https://github.com/tommy260803/Proyecto-IN-Odontolog-a- (commit 95471c30799c639c05218af2f6eb6a78bd25ba56)
--
-- ESTADO DE VERIFICACIÓN TÉCNICA:
--   Script preparado y revisado estáticamente a nivel de sintaxis T-SQL, lógica relacional y contratos.
--   No desplegado ni ejecutado contra bases de datos existentes en SQL Server (pendiente de motor).
--   Los bloques de verificación estática están diseñados para lectura no destructiva.
--
-- PROPÓSITO:
--   Implementar la capa de staging lógico mediante vistas T-SQL bajo el esquema [staging] en [NexoSalud_Mart].
--   Estas vistas extraen, tipifican, normalizan y sanitizan los datos transaccionales de [NexoSaludDB]
--   sin modificar el OLTP. Grano atómico: 1 fila por pago (id_pago) en stg_Pagos;
--   1 fila por reserva sin pago en stg_Reservas_SinPago.
--   Diseñado para ser consumido por dbo.usp_Cargar_Fact_GestionPayer en la fase de carga.
--
-- REGLAS ESTRICTAS DE PRIVACIDAD Y SEGURIDAD (LPDP LEY 29733):
--   1. No se proyectan textos libres clínicos: observaciones, referencia_pago, comprobante (solo presencia).
--   2. El campo validado_por se expone únicamente como id entero (presencia técnica), no datos del usuario en claro.
--   3. Los importes se documentan como MonedaNoVerificada: no se asume PEN, USD ni ninguna divisa.
--      El OLTP no posee campo de divisa formal; la cifra se propaga tal cual para evitar distorsión analítica.
--   4. precio_ofrecido (Opciones) es una cotización comprometida, NUNCA un cobro efectivo. No sustituye a importe.
--   5. No se crea, modifica ni elimina ninguna base de datos existente (OLTP ni Mart).
--
-- REGLAS DE DISEÑO TÉCNICO:
--   - fecha_registro: momento en que se registró el evento de pago en el sistema (siempre NOT NULL).
--   - fecha_validacion: momento en que fue acreditado/procesado el pago (NULL si Pendiente o Rechazado).
--     Estas dos fechas tienen semánticas distintas y NUNCA son intercambiables.
--   - importe_moneda_no_verificada: se propaga sin conversión porque no existe campo de divisa en el OLTP.
--   - es_pago_sin_anticipo: reservado para lógica futura (requiere fecha de atención efectiva; se emite 0).
--   - Todas las columnas derivadas se documentan con comentario de intención y fuente.
--
-- INCIDENCIA ABIERTA:
--   HAL-03: Se detectó en payer.routes.ts un pago ficticio de S/1.00 generado automáticamente en el backend.
--   Ver Sección 9 del documento de soporte. No se toma acción en este script; requiere coordinación con backend.
-- ====================================================================================================

USE [NexoSalud_Mart];
GO

-- ====================================================================================================
-- SECCIÓN 1: VERIFICACIÓN Y PREPARACIÓN DEL ESQUEMA STAGING
-- Reutiliza el esquema si ya fue creado por el script de Mario (13. Staging_buyer_lead_h3.sql).
-- ====================================================================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
BEGIN
    EXEC('CREATE SCHEMA staging');
    PRINT '>> Esquema [staging] creado exitosamente en NexoSalud_Mart.';
END
ELSE
BEGIN
    PRINT '>> El esquema [staging] ya existe en NexoSalud_Mart. Se reutiliza.';
END
GO

-- ====================================================================================================
-- SECCIÓN 2: VISTA PRINCIPAL — staging.stg_Pagos
-- Grano: 1 fila por pago registrado en la tabla Pagos del OLTP (id_pago es clave natural de idempotencia).
-- Origen principal: [NexoSaludDB].dbo.[Pagos]
-- Joins auxiliares (todos LEFT JOIN para preservar el grano):
--   Pagos → Reservas (por id_reserva)
--   Reservas → Opciones (por id_opcion)
--   Opciones → Disponibilidad (por id_disponibilidad)
--   Reservas → Solicitudes (por id_solicitud)
-- Valores de estado OLTP verificados en el repositorio: 'Validado', 'Pendiente', 'Rechazado'.
--
-- REGLAS DE NEGOCIO APLICADAS:
--   R-01: Grano atómico — 1 fila por id_pago. No se agrega ni pivotea en staging.
--   R-02: importe se propaga sin transformación. No se multiplica, divide ni convierte.
--   R-03: MonedaNoVerificada — no se asume PEN. El campo importe_moneda_no_verificada documenta esta limitación.
--   R-04: fecha_registro y fecha_validacion son semánticamente distintas. No se usan como sinónimos.
--   R-05: precio_ofrecido (Opciones) es cotización, no cobro. Se expone con alias explícito precio_ofrecido_cotizacion.
--   R-06: Los textos libres (observaciones, referencia_pago, comprobante) NO se exponen; solo banderas de presencia.
--   R-07: es_reserva_confirmada_sin_pago = 0 siempre en esta vista (si hay fila, hay pago asociado).
--   R-08: es_pago_sin_anticipo = 0 (reservado; requiere fecha de atención efectiva no disponible en OLTP actual).
--   R-09: es_cronologia_pago_valida = 1 si fecha_validacion IS NULL OR fecha_validacion >= fecha_registro.
-- ====================================================================================================
CREATE OR ALTER VIEW staging.stg_Pagos
AS
SELECT
    -- -------------------------------------------------------------------------
    -- BLOQUE A: Identificadores Naturales y Claves de Relación
    -- -------------------------------------------------------------------------

    -- Identificador primario del pago (clave natural de idempotencia para usp_Cargar_Fact_GestionPayer)
    p.id_pago,

    -- Identificador de la persona que realizó el pago (FK a Personas)
    p.id_persona,

    -- Identificador de la reserva asociada al pago (FK a Reservas; puede ser NULL si la reserva fue eliminada)
    p.id_reserva,

    -- Identificador de la opción seleccionada, obtenido desde Reservas (JOIN a Reservas)
    r.id_opcion,

    -- Identificador de la solicitud, obtenido desde Reservas (JOIN a Solicitudes)
    r.id_solicitud,

    -- Identificador del servicio desde Solicitudes (nullable: la solicitud puede no tener servicio asignado)
    sol.id_servicio,

    -- Identificador del profesional desde Disponibilidad vía Opciones (nullable: cadena de JOINs puede fallar)
    dis.id_profesional,

    -- Identificador de la sede desde Disponibilidad vía Opciones (nullable: cadena de JOINs puede fallar)
    dis.id_sede,

    -- -------------------------------------------------------------------------
    -- BLOQUE B: Marcas Temporales y Claves de Tiempo
    -- -------------------------------------------------------------------------

    -- Fecha y hora exacta en que se registró el pago en el sistema OLTP (SIEMPRE NOT NULL según contrato)
    -- SEMÁNTICA: Evento de pago, no acreditación. Ver R-04.
    p.fecha_registro,

    -- Fecha y hora de validación/acreditación efectiva del pago.
    -- NULL si el pago está en estado 'Pendiente' o 'Rechazado'. Ver R-04. NO reemplazar con fecha_registro.
    p.fecha_validacion,

    -- Clave de tiempo (dimensión Tiempo) para fecha_registro — formato YYYYMMDD como INT
    CAST(CONVERT(VARCHAR(8), p.fecha_registro, 112) AS INT)
        AS KeyTiempoPago,

    -- Clave de tiempo (dimensión Tiempo) para fecha_validacion — 0 si NULL (pago no validado o rechazado)
    -- El valor 0 indica "sin fecha de validación"; no confundir con el 1 de enero del año 0.
    CASE
        WHEN p.fecha_validacion IS NOT NULL
        THEN CAST(CONVERT(VARCHAR(8), p.fecha_validacion, 112) AS INT)
        ELSE 0
    END AS KeyTiempoValidacion,

    -- Clave de hora del pago: HHMM como INT (0-2359). Derivada de fecha_registro.
    -- Ejemplo: las 14:35 = 1435. Útil para análisis de distribución horaria de pagos.
    (DATEPART(HOUR, p.fecha_registro) * 100) + DATEPART(MINUTE, p.fecha_registro)
        AS KeyHoraPago,

    -- -------------------------------------------------------------------------
    -- BLOQUE C: Estado del Pago — Original y Normalizado
    -- -------------------------------------------------------------------------

    -- Valor de estado tal como existe en el OLTP, sin transformación.
    -- Valores reales verificados en el repositorio: 'Validado', 'Pendiente', 'Rechazado'.
    p.estado AS estado_pago_original,

    -- Estado normalizado para analítica uniforme.
    -- Se usan CASE con igualdad exacta (case-insensitive en SQL Server por collation predeterminada).
    -- 'Desconocido' actúa como centinela para detectar valores inesperados en el OLTP.
    CASE UPPER(LTRIM(RTRIM(p.estado)))
        WHEN 'VALIDADO'   THEN 'Validado'
        WHEN 'PENDIENTE'  THEN 'Pendiente'
        WHEN 'RECHAZADO'  THEN 'Rechazado'
        ELSE 'Desconocido'
    END AS estado_pago_norm,

    -- Bandera: 1 si el pago fue acreditado exitosamente. Base para cálculo de ingresos reales.
    CAST(
        CASE UPPER(LTRIM(RTRIM(p.estado)))
            WHEN 'VALIDADO' THEN 1
            ELSE 0
        END
    AS BIT) AS es_pago_validado,

    -- Bandera: 1 si el pago está en espera de confirmación. Base para cuentas por cobrar.
    CAST(
        CASE UPPER(LTRIM(RTRIM(p.estado)))
            WHEN 'PENDIENTE' THEN 1
            ELSE 0
        END
    AS BIT) AS es_pago_pendiente,

    -- Bandera: 1 si el pago fue rechazado o revertido. Base para análisis de reversiones.
    CAST(
        CASE UPPER(LTRIM(RTRIM(p.estado)))
            WHEN 'RECHAZADO' THEN 1
            ELSE 0
        END
    AS BIT) AS es_pago_rechazado,

    -- -------------------------------------------------------------------------
    -- BLOQUE D: Importes — Sin Conversión de Moneda (MonedaNoVerificada)
    -- -------------------------------------------------------------------------

    -- Importe original del OLTP, sin transformación de ningún tipo.
    -- RESTRICCIÓN CRÍTICA: No se asume ni se aplica ninguna moneda (PEN, USD, etc.).
    p.importe,

    -- Alias explícito para documentar la limitación de moneda.
    -- SEMÁNTICA: "No existe campo de divisa en el OLTP. Se propaga tal cual.
    --             El importe debe tratarse como pendiente de verificación de moneda (MonedaNoVerificada)."
    -- Este campo y p.importe son idénticos en valor; el alias sirve para forzar la intención en el ETL.
    p.importe AS importe_moneda_no_verificada,

    -- Importe atribuible a pagos validados. 0.00 si el pago no está validado.
    -- Usar esta columna para calcular ingresos confirmados en la Fact.
    CASE UPPER(LTRIM(RTRIM(p.estado)))
        WHEN 'VALIDADO' THEN p.importe
        ELSE CAST(0.00 AS DECIMAL(10,2))
    END AS importe_si_validado,

    -- Importe atribuible a pagos pendientes. 0.00 si el pago no está pendiente.
    -- Usar esta columna para calcular cuentas por cobrar en proceso.
    CASE UPPER(LTRIM(RTRIM(p.estado)))
        WHEN 'PENDIENTE' THEN p.importe
        ELSE CAST(0.00 AS DECIMAL(10,2))
    END AS importe_si_pendiente,

    -- Importe atribuible a pagos rechazados. 0.00 si el pago no fue rechazado.
    -- Usar esta columna para calcular el volumen de reversiones o anulaciones.
    CASE UPPER(LTRIM(RTRIM(p.estado)))
        WHEN 'RECHAZADO' THEN p.importe
        ELSE CAST(0.00 AS DECIMAL(10,2))
    END AS importe_si_rechazado,

    -- -------------------------------------------------------------------------
    -- BLOQUE E: Canal de Pago
    -- -------------------------------------------------------------------------

    -- Canal de pago tal como viene del OLTP (ejemplo: 'Transferencia', 'Efectivo', 'Tarjeta').
    p.canal_pago AS canal_pago_original,

    -- Canal de pago normalizado: UPPER + TRIM + 'DESCONOCIDO' si NULL.
    -- Unifica variantes de capitalización para agrupación analítica.
    COALESCE(NULLIF(UPPER(LTRIM(RTRIM(p.canal_pago))), ''), 'DESCONOCIDO')
        AS canal_pago_norm,

    -- -------------------------------------------------------------------------
    -- BLOQUE F: Banderas de Presencia (Sin Exponer Datos en Claro)
    -- -------------------------------------------------------------------------

    -- Bandera: 1 si existe un comprobante asociado al pago (no se expone el texto del comprobante, solo presencia).
    -- Cumple con restricción de privacidad: no proyectar datos de documentos en claro.
    CAST(
        CASE
            WHEN p.comprobante IS NOT NULL AND LTRIM(RTRIM(p.comprobante)) <> ''
            THEN 1
            ELSE 0
        END
    AS BIT) AS tiene_comprobante,

    -- ID del usuario que validó el pago. Se expone solo como entero (presencia técnica y trazabilidad de rol).
    -- No se proyectan nombres, emails ni datos del usuario validador en claro.
    p.validado_por AS validado_por_usuario,

    -- -------------------------------------------------------------------------
    -- BLOQUE G: Cotización de la Opción (Distinción Crítica: Cotización ≠ Cobro)
    -- -------------------------------------------------------------------------

    -- precio_ofrecido desde la tabla Opciones, obtenido vía JOIN a Reservas → Opciones.
    -- RESTRICCIÓN CRÍTICA: Este valor es la cotización comprometida al momento de seleccionar la opción,
    --   NO el importe efectivamente cobrado. NUNCA debe usarse como sustituto de p.importe.
    --   La diferencia entre precio_ofrecido_cotizacion e importe puede revelar descuentos, recargos o errores.
    op.precio_ofrecido AS precio_ofrecido_cotizacion,

    -- -------------------------------------------------------------------------
    -- BLOQUE H: Metadatos de la Reserva Asociada
    -- -------------------------------------------------------------------------

    -- Bandera de confirmación explícita de la reserva (campo BIT en Reservas).
    -- Indica si el paciente/cliente confirmó la reserva de forma explícita (no solo automática).
    r.confirmacion_explicita AS reserva_tiene_confirmacion_explicita,

    -- Fecha y hora de confirmación de la reserva (NULL si no ha sido confirmada explícitamente).
    r.fecha_confirmacion AS fecha_confirmacion_reserva,

    -- Bandera de reserva confirmada sin pago.
    -- NOTA: Esta vista opera sobre la tabla Pagos; por construcción, toda fila aquí tiene un pago asociado.
    --   La bandera se fija en 0 para documentación y consistencia con el patrón ETL del equipo.
    --   La detección real de reservas confirmadas sin anticipo se hace en staging.stg_Reservas_SinPago.
    CAST(0 AS BIT) AS es_reserva_confirmada_sin_pago,

    -- Estado de la reserva asociada (tal como viene del OLTP, p.ej.: 'Activa', 'Cancelada', 'Completada').
    r.estado AS estado_reserva,

    -- -------------------------------------------------------------------------
    -- BLOQUE I: Banderas de Calidad y Cronología
    -- -------------------------------------------------------------------------

    -- Bandera: 1 si el pago se registró después de la fecha de atención (pago extemporáneo / sin anticipo).
    -- RESERVADO para lógica futura: requiere la fecha de atención efectiva, que no existe como campo
    --   directo en el OLTP actual (Disponibilidad.fecha es la fecha ofrecida, no necesariamente la real).
    --   Se emite 0 como centinela para que el ETL pueda detectar su pendencia sin romper el flujo.
    CAST(0 AS BIT) AS es_pago_sin_anticipo,

    -- Bandera de cronología válida del pago.
    -- = 1 si: fecha_validacion IS NULL (pago no procesado aún) OR fecha_validacion >= fecha_registro.
    -- = 0 si: fecha_validacion < fecha_registro (anomalía: acreditado antes de registrarse → requiere revisión).
    CAST(
        CASE
            WHEN p.fecha_validacion IS NULL THEN 1
            WHEN p.fecha_validacion >= p.fecha_registro THEN 1
            ELSE 0
        END
    AS BIT) AS es_cronologia_pago_valida

FROM [NexoSaludDB].dbo.[Pagos] AS p

    -- JOIN a Reservas: LEFT porque un pago podría (en OLTP sucio) no tener reserva vigente.
    -- En datos limpios de Luxedent, todos los pagos tienen reserva asociada.
    LEFT JOIN [NexoSaludDB].dbo.[Reservas] AS r
        ON p.id_reserva = r.id_reserva

    -- JOIN a Opciones: LEFT porque el id_opcion en Reservas es NOT NULL pero el registro en Opciones
    -- podría haberse eliminado (integridad referencial débil posible en OLTP).
    LEFT JOIN [NexoSaludDB].dbo.[Opciones] AS op
        ON r.id_opcion = op.id_opcion

    -- JOIN a Disponibilidad: LEFT porque id_disponibilidad en Opciones es NOT NULL pero la cadena
    -- puede romperse si hay limpieza o depuraciones en el OLTP.
    LEFT JOIN [NexoSaludDB].dbo.[Disponibilidad] AS dis
        ON op.id_disponibilidad = dis.id_disponibilidad

    -- JOIN a Solicitudes: LEFT porque Reservas.id_solicitud puede ser NULL o el registro puede no existir.
    LEFT JOIN [NexoSaludDB].dbo.[Solicitudes] AS sol
        ON r.id_solicitud = sol.id_solicitud;
GO

PRINT '>> Vista staging.stg_Pagos creada exitosamente.';
GO

-- ====================================================================================================
-- SECCIÓN 3: VISTA AUXILIAR — staging.stg_Reservas_SinPago
-- Grano: 1 fila por reserva que NO tiene ningún pago registrado en la tabla Pagos.
-- Propósito:
--   Permite detectar reservas confirmadas sin anticipo (política Luxedent).
--   Garantiza que el ETL no genere pagos ficticios ni registros fantasma en Fact_GestionPayer.
--   Complementa a stg_Pagos cubriendo el universo de reservas no pagadas.
--
-- AVISO PARA EL PROCESO ETL:
--   "Esta vista permite detectar las reservas confirmadas sin anticipo (política de Luxedent)
--    para verificar que no se generen pagos ficticios ni registros en Fact_GestionPayer.
--    Las filas aquí presentes deben tratarse como ausencia de pago, no como error de carga."
--
-- REGLAS APLICADAS:
--   R-10: Si confirmacion_explicita = 1 y no hay pago → es_reserva_sin_anticipo_confirmada = 1.
--   R-11: La vista no modifica datos del OLTP; es solo de lectura.
--   R-12: La verificación NOT EXISTS es preferible a LEFT JOIN / IS NULL por legibilidad y rendimiento
--         en OLTP con índices sobre id_reserva.
-- ====================================================================================================
CREATE OR ALTER VIEW staging.stg_Reservas_SinPago
AS
SELECT
    -- Identificador de la reserva sin pago asociado
    r.id_reserva,

    -- Persona asociada a la reserva
    r.id_persona,

    -- Solicitud que originó la reserva (puede ser NULL si la reserva fue creada sin solicitud formal)
    r.id_solicitud,

    -- Opción de disponibilidad seleccionada para la reserva
    r.id_opcion,

    -- Fecha y hora en que se creó la reserva
    r.fecha_reserva,

    -- Estado actual de la reserva en el OLTP (p.ej.: 'Activa', 'Cancelada', 'Completada')
    r.estado,

    -- Indica si el paciente/cliente confirmó la reserva de forma explícita
    r.confirmacion_explicita,

    -- Fecha y hora de confirmación explícita (NULL si no fue confirmada o el proceso fue automático)
    r.fecha_confirmacion,

    -- Bandera de reserva confirmada sin anticipo:
    -- = 1 si la reserva fue confirmada explícitamente y aun así no existe ningún pago asociado.
    -- Este es el escenario que la política de Luxedent busca controlar (se espera anticipo al confirmar).
    -- = 0 si no fue confirmada explícitamente (la ausencia de pago es esperable en ese caso).
    CAST(
        CASE
            WHEN r.confirmacion_explicita = 1 THEN 1
            ELSE 0
        END
    AS BIT) AS es_reserva_sin_anticipo_confirmada

FROM [NexoSaludDB].dbo.[Reservas] AS r

WHERE NOT EXISTS (
    -- Subquery de exclusión: descarta todas las reservas que tienen AL MENOS un pago.
    -- Si existe cualquier fila en Pagos con el mismo id_reserva, la reserva queda fuera de esta vista.
    SELECT 1
    FROM [NexoSaludDB].dbo.[Pagos] AS pg
    WHERE pg.id_reserva = r.id_reserva
);
GO

PRINT '>> Vista staging.stg_Reservas_SinPago creada exitosamente.';
GO

-- ====================================================================================================
-- SECCIÓN 4: SUITE DE VERIFICACIÓN ESTÁTICA (READ-ONLY)
-- Propósito: Sanidad post-creación. NO crea ni modifica datos.
-- Todas las consultas son SELECT sobre las vistas recién creadas.
-- Ejecutar tras cada despliegue para validar que las vistas funcionan y los datos son coherentes.
-- ====================================================================================================

PRINT '>> Iniciando suite de verificación estática (solo lectura)...';
GO

-- -----------------------------------------------------------------------
-- VER-01: Conteo total de pagos en staging y distribución por estado
-- Esperado: El total debe coincidir con COUNT(*) de [NexoSaludDB].dbo.[Pagos].
-- Los estados 'Validado', 'Pendiente' y 'Rechazado' deben sumar el total.
-- Si aparece 'Desconocido' > 0, hay valores inesperados en el OLTP → investigar.
-- -----------------------------------------------------------------------
SELECT
    'VER-01 | Distribución por Estado' AS verificacion,
    estado_pago_norm,
    COUNT(*)                         AS cantidad_pagos,
    SUM(importe)                     AS suma_importe_total
FROM staging.stg_Pagos
GROUP BY estado_pago_norm
ORDER BY cantidad_pagos DESC;
GO

-- -----------------------------------------------------------------------
-- VER-02: Pagos con importe <= 0 (anomalías financieras)
-- Esperado: 0 filas. Un importe de 0.00 o negativo no debería ser válido en Luxedent.
-- INCIDENCIA RELACIONADA: HAL-03 — pago ficticio de S/1.00 detectado en backend.
-- Si se encuentran importes de 1.00 de forma masiva, puede estar relacionado con HAL-03.
-- -----------------------------------------------------------------------
SELECT
    'VER-02 | Pagos con importe <= 0' AS verificacion,
    id_pago,
    id_persona,
    id_reserva,
    importe,
    estado_pago_norm,
    canal_pago_norm,
    fecha_registro
FROM staging.stg_Pagos
WHERE importe <= 0.00
ORDER BY fecha_registro DESC;
GO

-- -----------------------------------------------------------------------
-- VER-03: Pagos sin reserva vinculada (JOIN roto)
-- Esperado: 0 filas. Todo pago en Luxedent debe estar asociado a una reserva.
-- Si hay filas, verificar integridad referencial en el OLTP o limpieza de datos.
-- -----------------------------------------------------------------------
SELECT
    'VER-03 | Pagos sin reserva vinculada' AS verificacion,
    id_pago,
    id_persona,
    id_reserva,
    importe,
    estado_pago_norm,
    fecha_registro
FROM staging.stg_Pagos
WHERE id_opcion IS NULL   -- Si id_opcion es NULL, el JOIN a Reservas no encontró la reserva
  AND id_reserva IS NOT NULL
ORDER BY fecha_registro DESC;
GO

-- -----------------------------------------------------------------------
-- VER-04: Verificación de cronología inválida (fecha_validacion < fecha_registro)
-- Esperado: 0 filas. Una validación anterior al registro indica anomalía en el sistema o carga errónea.
-- -----------------------------------------------------------------------
SELECT
    'VER-04 | Cronología inválida (validacion < registro)' AS verificacion,
    id_pago,
    id_persona,
    id_reserva,
    fecha_registro,
    fecha_validacion,
    estado_pago_norm,
    importe
FROM staging.stg_Pagos
WHERE es_cronologia_pago_valida = 0
ORDER BY fecha_registro DESC;
GO

-- -----------------------------------------------------------------------
-- VER-05: Pagos validados sin fecha_validacion (inconsistencia de estado)
-- Esperado: 0 filas. Un pago en estado 'Validado' DEBE tener fecha_validacion NOT NULL.
-- Si hay filas, el OLTP tiene inconsistencia entre estado y fecha de acreditación.
-- -----------------------------------------------------------------------
SELECT
    'VER-05 | Validados sin fecha_validacion' AS verificacion,
    id_pago,
    id_persona,
    id_reserva,
    importe,
    estado_pago_original,
    fecha_registro,
    fecha_validacion
FROM staging.stg_Pagos
WHERE es_pago_validado = 1
  AND fecha_validacion IS NULL
ORDER BY fecha_registro DESC;
GO

-- -----------------------------------------------------------------------
-- VER-06: Pagos rechazados con comprobante (posible inconsistencia de proceso)
-- Esperado: preferiblemente 0 filas. Un pago rechazado con comprobante adjunto
-- puede indicar un error en el flujo de procesamiento o una reversión post-comprobante.
-- -----------------------------------------------------------------------
SELECT
    'VER-06 | Rechazados con comprobante' AS verificacion,
    id_pago,
    id_persona,
    id_reserva,
    importe,
    estado_pago_norm,
    tiene_comprobante,
    fecha_registro,
    fecha_validacion
FROM staging.stg_Pagos
WHERE es_pago_rechazado = 1
  AND tiene_comprobante = 1
ORDER BY fecha_registro DESC;
GO

-- -----------------------------------------------------------------------
-- VER-07: Verificación de canal de pago desconocido
-- Esperado: idealmente 0 filas. Canales NULL o vacíos producen 'DESCONOCIDO'.
-- Permite evaluar completitud del dato canal_pago en el OLTP.
-- -----------------------------------------------------------------------
SELECT
    'VER-07 | Pagos con canal DESCONOCIDO' AS verificacion,
    COUNT(*) AS cantidad_pagos_canal_desconocido
FROM staging.stg_Pagos
WHERE canal_pago_norm = 'DESCONOCIDO';
GO

-- -----------------------------------------------------------------------
-- VER-08: Conteo de reservas sin pago (desde stg_Reservas_SinPago)
-- Esperado: puede ser > 0 (es válido tener reservas sin pago en Luxedent).
-- La bandera es_reserva_sin_anticipo_confirmada = 1 identifica los casos críticos.
-- -----------------------------------------------------------------------
SELECT
    'VER-08 | Reservas sin pago (total y críticas)' AS verificacion,
    COUNT(*)                                             AS total_reservas_sin_pago,
    SUM(CAST(es_reserva_sin_anticipo_confirmada AS INT)) AS reservas_confirmadas_sin_anticipo
FROM staging.stg_Reservas_SinPago;
GO

-- -----------------------------------------------------------------------
-- VER-09: Distribución de canal de pago normalizado (top canales)
-- Informativo: muestra los canales de pago más usados en el OLTP.
-- Útil para validar que la normalización UPPER/TRIM funciona correctamente.
-- -----------------------------------------------------------------------
SELECT
    'VER-09 | Top canales de pago normalizados' AS verificacion,
    canal_pago_norm,
    COUNT(*) AS cantidad_pagos,
    SUM(importe_si_validado) AS total_validado_por_canal
FROM staging.stg_Pagos
GROUP BY canal_pago_norm
ORDER BY cantidad_pagos DESC;
GO

-- -----------------------------------------------------------------------
-- VER-10: Resumen ejecutivo de la vista — métricas clave del staging
-- Tabla de control para la fase de carga (usp_Cargar_Fact_GestionPayer).
-- -----------------------------------------------------------------------
SELECT
    'VER-10 | Resumen ejecutivo stg_Pagos' AS verificacion,
    COUNT(*)                                AS total_filas_staging,
    COUNT(DISTINCT id_persona)              AS personas_distintas,
    COUNT(DISTINCT id_reserva)              AS reservas_distintas,
    COUNT(DISTINCT id_sede)                 AS sedes_distintas,
    COUNT(DISTINCT id_profesional)          AS profesionales_distintos,
    SUM(CAST(es_pago_validado AS INT))      AS pagos_validados,
    SUM(CAST(es_pago_pendiente AS INT))     AS pagos_pendientes,
    SUM(CAST(es_pago_rechazado AS INT))     AS pagos_rechazados,
    SUM(importe_si_validado)                AS suma_importe_validado,
    SUM(importe_si_pendiente)               AS suma_importe_pendiente,
    SUM(importe_si_rechazado)               AS suma_importe_rechazado,
    SUM(CAST(tiene_comprobante AS INT))     AS pagos_con_comprobante,
    SUM(CAST(CASE WHEN es_cronologia_pago_valida = 0 THEN 1 ELSE 0 END AS INT))
                                            AS anomalias_cronologia,
    MIN(fecha_registro)                     AS fecha_pago_mas_antigua,
    MAX(fecha_registro)                     AS fecha_pago_mas_reciente
FROM staging.stg_Pagos;
GO

PRINT '>> Suite de verificación estática completada. Revisar resultados anteriores.';
GO

-- ====================================================================================================
-- FIN DEL SCRIPT — ENTREGABLE 18 | ETL PAYER — STAGING
-- Autor: Jesús Daniel Ordóñez Ugarte — Integrante 4
-- Hito: H3 — NexoSalud / Clínica Luxedent, Trujillo
-- ====================================================================================================
