-- ====================================================================================================
-- NEXOSALUD — CONCILIACIÓN MONETARIA Y AUDITORÍA DE INTEGRIDAD PAYER (H3)
-- ====================================================================================================
-- Proyecto      : NexoSalud (Plataforma BI Odontológica — Clínica Luxedent, Trujillo)
-- Metodología   : IMPULSE (Fase: PAYER — Fact_GestionPayer)
-- Responsable   : Jesús Daniel Ordóñez Ugarte (Integrante 4 — ETL PAYER, Gestión Financiera)
-- Ubicación     : Entregables/20. Conciliacion_monetaria_Payer_h3.sql
-- Hito          : H3 — Fase 3: Conciliación Monetaria y Control de Cierre
-- Motor         : SQL Server 2019 — (localdb)\MSSQLLocalDB
-- Bases Contexto: NexoSaludDB (OLTP) y NexoSalud_Mart (Data Mart)
--
-- ADVERTENCIAS CRÍTICAS DE NEGOCIO:
--   1. POLÍTICA DE MONEDA: Queda estrictamente prohibido asumir moneda PEN o USD de forma automática.
--      El OLTP no dispone de un campo formal de divisa (moneda/id_moneda). Por tanto, todas las
--      conciliaciones operan bajo la categoría 'MonedaNoVerificada'. No sumar ni operar montos si
--      se sospecha divergencia cambiaria en la fuente.
--   2. DISTINCIÓN CRONOLÓGICA: fecha_registro (momento del registro de pago) NO ES EQUIVALENTE a
--      fecha_validacion (momento de acreditación bancaria o confirmación en recepción). Las conciliaciones
--      contables de caja efectiva deben basarse en fecha_validacion; las de actividad operativa, en fecha_registro.
--   3. GRANO ATÓMICO: 1 fila exactamente por id_pago. La existencia de múltiples pagos vinculados a una
--      misma reserva (id_reserva) representa pagos parciales legítimos y debe preservarse.
--   4. COTIZACIÓN VS PAGO: precio_ofrecido en Opciones es cotización, NUNCA un cobro ni un anticipo.
--   5. RESERVAS SIN ANTICIPO: No generan registros en Fact_GestionPayer. La ausencia de pago es válida.
--   6. ESTADOS Y MEDIDAS:
--      - Validado  --> Contribuye a ImporteTotalCobro y PagosValidados.
--      - Pendiente --> Contribuye a ImportePendiente y PagosPendientes (NO es ingreso acreditado).
--      - Rechazado --> Contribuye a ImporteRechazado y PagosRechazados (NO es ingreso; reversión/anulación).
-- ====================================================================================================

SET NOCOUNT ON;
GO

USE [NexoSalud_Mart];
GO

-- ====================================================================================================
-- COMPROBACIÓN DEFENSIVA DE ENTORNO
-- Permite abortar si alguna de las bases no está disponible sin generar errores de compilación destructivos.
-- ====================================================================================================
IF DB_ID('NexoSaludDB') IS NULL OR DB_ID('NexoSalud_Mart') IS NULL
BEGIN
    PRINT '>> [AVISO PREVENTIVO] Una o ambas bases de datos requeridas ([NexoSaludDB], [NexoSalud_Mart])';
    PRINT '>> no se encuentran actualmente creadas en la instancia activa.';
    PRINT '>> El script contiene consultas estáticas válidas parametrizadas para ambientes reales o de prueba.';
END
GO

-- ====================================================================================================
-- CONSULTA 1: CONCILIACIÓN GLOBAL DE REGISTROS Y VOLUMETRÍA (OLTP vs DATA MART)
-- Propósito: Garantizar la cuadratura exacta de registros entre la tabla transaccional y el hecho.
-- ====================================================================================================
SELECT 
    'Conciliación Global de Volumetría' AS Indicador,
    COUNT(p.id_pago) AS TotalPagosOLTP,
    COUNT(f.id_pago_origen) AS TotalPagosDataMart,
    COUNT(p.id_pago) - COUNT(f.id_pago_origen) AS DiferenciaAbsoluta,
    CASE 
        WHEN COUNT(p.id_pago) = COUNT(f.id_pago_origen) THEN 'CUADRADO / BALANCE PERFECTO'
        WHEN COUNT(p.id_pago) > COUNT(f.id_pago_origen) THEN 'HAY PAGOS EN OLTP NO CARGADOS (O RECHAZADOS)'
        ELSE 'ANOMALÍA: MÁS REGISTROS EN MART QUE EN OLTP (POSIBLES HUÉRFANOS)'
    END AS EstadoConciliacion,
    'MonedaNoVerificada' AS PoliticaMonetaria
FROM [NexoSaludDB].dbo.Pagos p
FULL OUTER JOIN dbo.Fact_GestionPayer f ON f.id_pago_origen = p.id_pago;
GO

-- ====================================================================================================
-- CONSULTA 2: IDENTIFICACIÓN DE PAGOS DISCORDANTES (FALTANTES, HUÉRFANOS O RECHAZADOS)
-- Propósito: Listar a nivel atómico cualquier id_pago que no coincida entre ambos repositorios,
--            cruzando con dbo.Rechazos_ETL_Payer para justificar discrepancias.
-- ====================================================================================================
SELECT 
    COALESCE(p.id_pago, f.id_pago_origen) AS id_pago_evaluado,
    CASE 
        WHEN p.id_pago IS NOT NULL AND f.id_pago_origen IS NULL AND r.RechazoId IS NOT NULL 
            THEN CONCAT('RECHAZADO_ETL: ', r.MotivoRechazo)
        WHEN p.id_pago IS NOT NULL AND f.id_pago_origen IS NULL 
            THEN 'NO_CARGADO_PENDIENTE_ETL'
        WHEN p.id_pago IS NULL AND f.id_pago_origen IS NOT NULL 
            THEN 'HUÉRFANO_EN_MART (NO EXISTE EN OLTP)'
        ELSE 'CONSISTENTE'
    END AS DiagnosticoIntegridad,
    p.importe AS ImporteOLTP,
    p.estado AS EstadoOLTP,
    p.fecha_registro AS FechaRegistroOLTP,
    f.KeyFactPayer,
    f.BatchId AS BatchCargaMart,
    'MonedaNoVerificada' AS IndicadorMoneda
FROM [NexoSaludDB].dbo.Pagos p
FULL OUTER JOIN dbo.Fact_GestionPayer f ON f.id_pago_origen = p.id_pago
LEFT JOIN dbo.Rechazos_ETL_Payer r ON r.EntidadOrigenId = p.id_pago
WHERE p.id_pago IS NULL OR f.id_pago_origen IS NULL;
GO

-- ====================================================================================================
-- CONSULTA 3: DETECCIÓN DE ANOMALÍAS DE DUPLICIDAD Y CONTROL DEL GRANO ATÓMICO (1 FILA X ID_PAGO)
-- Propósito: Comprobar que ninguna clave natural se encuentre repetida en Fact_GestionPayer.
-- ====================================================================================================
SELECT 
    f.id_pago_origen,
    COUNT(*) AS CantidadOcurrencias,
    MIN(f.KeyFactPayer) AS PrimerKeyFactPayer,
    MAX(f.KeyFactPayer) AS UltimoKeyFactPayer,
    CASE 
        WHEN COUNT(*) > 1 THEN 'CRÍTICO: VIOLACIÓN DEL GRANO ATÓMICO'
        ELSE 'VÁLIDO: GRANO EXACTO'
    END AS EstadoIdempotencia
FROM dbo.Fact_GestionPayer f
GROUP BY f.id_pago_origen
HAVING COUNT(*) > 1;
GO

-- ====================================================================================================
-- CONSULTA 4: CONCILIACIÓN MONETARIA Y DE VOLUMETRÍA POR ESTADO DE PAGO
-- Propósito: Comparar los importes monetarios segregados por estado (Validado, Pendiente, Rechazado).
--            Verifica que los pagos no validados no se imputen indebidamente a ImporteTotalCobro.
-- ====================================================================================================
SELECT 
    COALESCE(UPPER(TRIM(p.estado)), 'DESCONOCIDO_OLTP') AS EstadoPagoOLTP,
    -- Volumetría OLTP
    COUNT(p.id_pago) AS CantidadPagosOLTP,
    SUM(p.importe) AS ImporteNominalOLTP,
    -- Métricas en Data Mart
    COUNT(f.id_pago_origen) AS CantidadPagosMart,
    SUM(f.ImporteTotalCobro) AS ImporteValidadoMart,
    SUM(f.ImportePendiente) AS ImportePendienteMart,
    SUM(f.ImporteRechazado) AS ImporteRechazadoMart,
    -- Suma total asignada en Mart
    SUM(f.ImporteTotalCobro + f.ImportePendiente + f.ImporteRechazado) AS ImporteTotalRegistradoMart,
    -- Diferencia monetaria
    SUM(p.importe) - SUM(f.ImporteTotalCobro + f.ImportePendiente + f.ImporteRechazado) AS DiferenciaMonetaria,
    -- Evaluación
    CASE 
        WHEN SUM(p.importe) = SUM(f.ImporteTotalCobro + f.ImportePendiente + f.ImporteRechazado) THEN 'CONCILIADO EXACTO'
        ELSE 'DISCREPANCIA DETECTADA'
    END AS EstadoConciliacion,
    'MonedaNoVerificada - No asumir divisa' AS NotaTecnica
FROM [NexoSaludDB].dbo.Pagos p
INNER JOIN dbo.Fact_GestionPayer f ON f.id_pago_origen = p.id_pago
GROUP BY UPPER(TRIM(p.estado))
ORDER BY EstadoPagoOLTP;
GO

-- ====================================================================================================
-- CONSULTA 5: CONCILIACIÓN POR FECHA DE REGISTRO (EVENTO OPERATIVO DE CAPTURA)
-- Propósito: Conciliar la entrada de pagos agrupada por día de registro.
-- ====================================================================================================
SELECT 
    CAST(p.fecha_registro AS DATE) AS FechaRegistroOperativo,
    COUNT(p.id_pago) AS PagosRegistradosOLTP,
    SUM(p.importe) AS ImporteTotalOLTP,
    -- Validados OLTP
    SUM(CASE WHEN UPPER(TRIM(p.estado)) = 'VALIDADO' THEN p.importe ELSE 0.00 END) AS ImporteValidadosOLTP,
    -- Cifras en Mart
    COUNT(f.id_pago_origen) AS PagosRegistradosMart,
    SUM(f.ImporteTotalCobro) AS ImporteValidadoMart,
    SUM(f.ImportePendiente) AS ImportePendienteMart,
    SUM(f.ImporteRechazado) AS ImporteRechazadoMart,
    -- Diferencias de acreditación
    SUM(CASE WHEN UPPER(TRIM(p.estado)) = 'VALIDADO' THEN p.importe ELSE 0.00 END) - SUM(f.ImporteTotalCobro) AS DiferenciaIngresosValidados,
    'MonedaNoVerificada' AS IndicadorMoneda
FROM [NexoSaludDB].dbo.Pagos p
INNER JOIN dbo.Fact_GestionPayer f ON f.id_pago_origen = p.id_pago
GROUP BY CAST(p.fecha_registro AS DATE)
ORDER BY FechaRegistroOperativo DESC;
GO

-- ====================================================================================================
-- CONSULTA 6: CONCILIACIÓN POR FECHA DE VALIDACIÓN (ACREDITACIÓN DE CAJA EFECTIVA)
-- Propósito: Cuadrar ingresos por fecha en que el pago fue formalmente validado (caja real).
-- ====================================================================================================
SELECT 
    CASE 
        WHEN p.fecha_validacion IS NULL THEN 'SIN VALIDACIÓN / PENDIENTE'
        ELSE CONVERT(VARCHAR(10), CAST(p.fecha_validacion AS DATE), 120)
    END AS FechaValidacionEfectiva,
    COUNT(p.id_pago) AS PagosOLTP,
    SUM(p.importe) AS ImporteNominalOLTP,
    SUM(f.ImporteTotalCobro) AS ImporteAcreditadoMart,
    SUM(CASE WHEN p.fecha_validacion IS NOT NULL THEN p.importe ELSE 0.00 END) - SUM(f.ImporteTotalCobro) AS DiferenciaCajaEfectiva,
    'MonedaNoVerificada - Fecha de acreditación no convertible a fecha de registro' AS ReglaCronologica
FROM [NexoSaludDB].dbo.Pagos p
INNER JOIN dbo.Fact_GestionPayer f ON f.id_pago_origen = p.id_pago
GROUP BY 
    CASE 
        WHEN p.fecha_validacion IS NULL THEN 'SIN VALIDACIÓN / PENDIENTE'
        ELSE CONVERT(VARCHAR(10), CAST(p.fecha_validacion AS DATE), 120)
    END
ORDER BY FechaValidacionEfectiva DESC;
GO

-- ====================================================================================================
-- CONSULTA 7: CONCILIACIÓN POR PASARELA / CANAL DE PAGO Y DIMENSIÓN CONFORMADA
-- Propósito: Verificar que la normalización del canal no distorsione importes ni genere miembros huérfanos.
-- ====================================================================================================
SELECT 
    COALESCE(UPPER(TRIM(p.canal_pago)), 'NO_DEFINIDO') AS CanalPagoOLTP,
    dp.MetodoPago AS MetodoPagoDimPasarela,
    COUNT(p.id_pago) AS CantidadPagos,
    SUM(p.importe) AS ImporteOLTP,
    SUM(f.ImporteTotalCobro) AS ImporteValidadosMart,
    SUM(f.ImportePendiente) AS ImportePendientesMart,
    SUM(f.ImporteRechazado) AS ImporteRechazadosMart,
    CASE 
        WHEN f.KeyPasarela = 0 THEN 'ADVERTENCIA: CANAL MAPEA A MIEMBRO DESCONOCIDO (KeyPasarela = 0)'
        ELSE 'MAPEO DIMENSIONAL CONFORME'
    END AS EvaluacionCanal
FROM [NexoSaludDB].dbo.Pagos p
INNER JOIN dbo.Fact_GestionPayer f ON f.id_pago_origen = p.id_pago
LEFT JOIN dbo.Dim_Pasarela dp ON dp.KeyPasarela = f.KeyPasarela
GROUP BY COALESCE(UPPER(TRIM(p.canal_pago)), 'NO_DEFINIDO'), dp.MetodoPago, f.KeyPasarela
ORDER BY CantidadPagos DESC;
GO

-- ====================================================================================================
-- CONSULTA 8: CONTROL DE PAGOS PARCIALES POR RESERVA (MÚLTIPLES PAGOS POR RESERVA)
-- Propósito: Identificar reservas con múltiples abonos, garantizando que el hecho mantenga cada pago
--            de manera individual (sin agregación prematura que destruya el grano ni pérdida de montos).
-- ====================================================================================================
SELECT 
    p.id_reserva,
    COUNT(p.id_pago) AS TotalPagosRegistradosOLTP,
    COUNT(f.id_pago_origen) AS TotalPagosEnMart,
    SUM(p.importe) AS SumaAbonosOLTP,
    SUM(f.ImporteTotalCobro) AS AbonosValidadosMart,
    SUM(f.ImportePendiente) AS AbonosPendientesMart,
    SUM(f.ImporteRechazado) AS AbonosRechazadosMart,
    CASE 
        WHEN COUNT(p.id_pago) > 1 THEN 'PAGOS PARCIALES MÚLTIPLES DETECTADOS'
        ELSE 'PAGO ÚNICO ESTÁNDAR'
    END AS TipoOperacionReserva,
    'MonedaNoVerificada' AS IndicadorMoneda
FROM [NexoSaludDB].dbo.Pagos p
INNER JOIN dbo.Fact_GestionPayer f ON f.id_pago_origen = p.id_pago
GROUP BY p.id_reserva
HAVING COUNT(p.id_pago) > 1
ORDER BY TotalPagosRegistradosOLTP DESC, p.id_reserva;
GO

-- ====================================================================================================
-- CONSULTA 9: COMPROBACIÓN DE RESERVAS SIN ANTICIPO (POLÍTICA LUXEDENT)
-- Propósito: Constatar que las reservas confirmadas sin cobro previo NO generen registros espurios
--            en Fact_GestionPayer ni pagos ficticios inventados.
-- ====================================================================================================
SELECT 
    r.id_reserva,
    r.id_persona,
    r.estado AS EstadoReserva,
    r.confirmacion_explicita,
    r.fecha_reserva,
    op.precio_ofrecido AS CotizacionOfrecidaOpcion,
    CASE 
        WHEN f.id_pago_origen IS NOT NULL THEN 'CRÍTICO: SE GENERÓ PAGO FICTICIO EN FACT_GESTIONPAYER'
        ELSE 'CORRECTO: SIN REGISTRO EN FACT (POLÍTICA SIN ANTICIPO CUMPLIDA)'
    END AS EvaluacionReglaNegocio,
    'Cotización no computable como cobro efectivo' AS Advertencia
FROM [NexoSaludDB].dbo.Reservas r
LEFT JOIN [NexoSaludDB].dbo.Opciones op ON op.id_opcion = r.id_opcion
LEFT JOIN [NexoSaludDB].dbo.Pagos p ON p.id_reserva = r.id_reserva
LEFT JOIN dbo.Fact_GestionPayer f ON f.id_reserva_origen = r.id_reserva
WHERE p.id_pago IS NULL
  AND r.confirmacion_explicita = 1;
GO

-- ====================================================================================================
-- CONSULTA 10: RESUMEN EJECUTIVO Y DICTAMEN DE CONCILIACIÓN MONETARIA
-- Propósito: Cuadro consolidado final para certificación y traspaso a auditoría o siguiente rol.
-- ====================================================================================================
WITH MetricasOLTP AS (
    SELECT 
        COUNT(*) AS TotalPagosOLTP,
        SUM(importe) AS ImporteBrutoOLTP,
        SUM(CASE WHEN UPPER(TRIM(estado)) = 'VALIDADO' THEN importe ELSE 0.00 END) AS ImporteValidadosOLTP,
        SUM(CASE WHEN UPPER(TRIM(estado)) = 'PENDIENTE' THEN importe ELSE 0.00 END) AS ImportePendientesOLTP,
        SUM(CASE WHEN UPPER(TRIM(estado)) = 'RECHAZADO' THEN importe ELSE 0.00 END) AS ImporteRechazadosOLTP
    FROM [NexoSaludDB].dbo.Pagos
),
MetricasMart AS (
    SELECT 
        COUNT(*) AS TotalFilasMart,
        SUM(ImporteTotalCobro + ImportePendiente + ImporteRechazado) AS ImporteBrutoMart,
        SUM(ImporteTotalCobro) AS ImporteValidadosMart,
        SUM(ImportePendiente) AS ImportePendientesMart,
        SUM(ImporteRechazado) AS ImporteRechazadosMart,
        COUNT(DISTINCT IndicadorMoneda) AS CantidadTiposMoneda,
        MIN(IndicadorMoneda) AS IndicadorMonedaUnico
    FROM dbo.Fact_GestionPayer
),
RechazosETL AS (
    SELECT 
        COUNT(*) AS TotalRechazadosETL
    FROM dbo.Rechazos_ETL_Payer
)
SELECT 
    o.TotalPagosOLTP,
    m.TotalFilasMart,
    r.TotalRechazadosETL,
    (o.TotalPagosOLTP - (m.TotalFilasMart + r.TotalRechazadosETL)) AS BrechaVolumetricaSinExplicar,
    o.ImporteValidadosOLTP,
    m.ImporteValidadosMart,
    (o.ImporteValidadosOLTP - m.ImporteValidadosMart) AS DiferenciaIngresosValidados,
    o.ImportePendientesOLTP,
    m.ImportePendientesMart,
    o.ImporteRechazadosOLTP,
    m.ImporteRechazadosMart,
    m.IndicadorMonedaUnico AS EstadoMonedaMart,
    CASE 
        WHEN (o.TotalPagosOLTP = m.TotalFilasMart + r.TotalRechazadosETL) 
         AND (o.ImporteValidadosOLTP = m.ImporteValidadosMart)
         AND (o.ImportePendientesOLTP = m.ImportePendientesMart)
         AND (o.ImporteRechazadosOLTP = m.ImporteRechazadosMart)
        THEN 'CONCILIACIÓN MONETARIA CERTIFICADA CON ÉXITO'
        ELSE 'CONCILIACIÓN CON DISCREPANCIAS PENDIENTES DE REVISIÓN'
    END AS DictamenFinal
FROM MetricasOLTP o
CROSS JOIN MetricasMart m
CROSS JOIN RechazosETL r;
GO

PRINT '>> Script de conciliación monetaria completado exitosamente.';
GO
