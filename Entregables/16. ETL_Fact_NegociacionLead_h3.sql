-- ====================================================================================================
-- NEXOSALUD — SISTEMA DE BUSINESS INTELLIGENCE ODONTOLÓGICO (CLÍNICA LUXEDENT)
-- PROYECTO BI — HITO H3 / FASE 2: persistencia y carga de hechos de negociación (LEAD)
-- OBJETO: TABLA DE HECHOS dbo.Fact_NegociacionLead, OBJETOS AUXILIARES Y PROCEDIMIENTO DE CARGA
-- RESPONSABLE TÉCNICO: Jesús Daniel Ordóñez Ugarte (Integrante 4 — asumiendo LEAD por intercambio acordado)
-- TITULAR DEL ROL: Mario Antonio Martinez Dominguez (Integrante 3 — ETL BUYER y LEAD, Embudo y Calidad)
-- DOCUMENTO DE DISEÑO: Entregables/14. Diseno_ETL_hechos_buyer_lead_h3.md (Sección 5.3 - Algoritmo 2)
-- CONTRATO CONTRACTUAL: Entregables/12. Contrato_y_dependencias_h3_mario.md (Sección 3.2)
-- CAPA STAGING FUENTE: Entregables/13. Staging_buyer_lead_h3.sql (staging.stg_Solicitudes, staging.stg_Interacciones)
-- ====================================================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ====================================================================================================
-- LOTE 1: PREVALIDACIÓN BLOQUEANTE DEFENSIVA DEL ENTORNO DE DESTINO
-- Si alguna dimensión, columna, clave foránea o tabla auxiliar preexistente no cumple el contrato,
-- el script compila el diagnóstico detallado, emite RAISERROR (severidad 16) y activa SET NOEXEC ON.
-- ====================================================================================================

DECLARE @ErroresPreval VARCHAR(MAX) = '';

-- ----------------------------------------------------------------------------------------------------
-- 1.1 Validación de Dim_Tiempo
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Tiempo.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Tiempo') AND c.name = 'KeyTiempo' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Tiempo.KeyTiempo debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Tiempo')
              AND (i.is_primary_key = 1 OR i.is_unique = 1)
              AND i.is_disabled = 0
              AND i.has_filter = 0
              AND i.is_hypothetical = 0
              AND (
                  SELECT COUNT(*) 
                  FROM sys.index_columns ic 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0
              ) = 1
              AND EXISTS (
                  SELECT 1 
                  FROM sys.index_columns ic 
                  JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0 
                    AND c.name = 'KeyTiempo'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Tiempo.KeyTiempo debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Tiempo') AND c.name = 'id_fecha' AND t.name = 'date'
    )
        SET @ErroresPreval += '- dbo.Dim_Tiempo.id_fecha debe ser de tipo DATE.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Tiempo') AND name = 'KeyTiempo')
    BEGIN
        DECLARE @hasMem0_Tiempo INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Tiempo WHERE KeyTiempo = 0', N'@c INT OUTPUT', @c = @hasMem0_Tiempo OUTPUT;
        IF @hasMem0_Tiempo = 0
            SET @ErroresPreval += '- dbo.Dim_Tiempo no contiene el miembro desconocido verificado (KeyTiempo = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.2 Validación de Dim_Sede
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Sede', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Sede.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Sede') AND c.name = 'KeySede' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Sede.KeySede debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Sede')
              AND (i.is_primary_key = 1 OR i.is_unique = 1)
              AND i.is_disabled = 0
              AND i.has_filter = 0
              AND i.is_hypothetical = 0
              AND (
                  SELECT COUNT(*) 
                  FROM sys.index_columns ic 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0
              ) = 1
              AND EXISTS (
                  SELECT 1 
                  FROM sys.index_columns ic 
                  JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0 
                    AND c.name = 'KeySede'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Sede.KeySede debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Sede') AND c.name = 'id_sede' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Sede.id_sede debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Sede') AND name = 'KeySede')
    BEGIN
        DECLARE @hasMem0_Sede INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Sede WHERE KeySede = 0', N'@c INT OUTPUT', @c = @hasMem0_Sede OUTPUT;
        IF @hasMem0_Sede = 0
            SET @ErroresPreval += '- dbo.Dim_Sede no contiene el miembro desconocido verificado (KeySede = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.3 Validación de Dim_Servicio
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Servicio', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Servicio.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Servicio') AND c.name = 'KeyServicio' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Servicio.KeyServicio debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Servicio')
              AND (i.is_primary_key = 1 OR i.is_unique = 1)
              AND i.is_disabled = 0
              AND i.has_filter = 0
              AND i.is_hypothetical = 0
              AND (
                  SELECT COUNT(*) 
                  FROM sys.index_columns ic 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0
              ) = 1
              AND EXISTS (
                  SELECT 1 
                  FROM sys.index_columns ic 
                  JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0 
                    AND c.name = 'KeyServicio'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Servicio.KeyServicio debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Servicio') AND c.name = 'id_servicio' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Servicio.id_servicio debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Servicio') AND name = 'KeyServicio')
    BEGIN
        DECLARE @hasMem0_Servicio INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Servicio WHERE KeyServicio = 0', N'@c INT OUTPUT', @c = @hasMem0_Servicio OUTPUT;
        IF @hasMem0_Servicio = 0
            SET @ErroresPreval += '- dbo.Dim_Servicio no contiene el miembro desconocido verificado (KeyServicio = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.4 Validación de Dim_Profesional
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Profesional', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Profesional.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Profesional') AND c.name = 'KeyProfesional' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Profesional.KeyProfesional debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Profesional')
              AND (i.is_primary_key = 1 OR i.is_unique = 1)
              AND i.is_disabled = 0
              AND i.has_filter = 0
              AND i.is_hypothetical = 0
              AND (
                  SELECT COUNT(*) 
                  FROM sys.index_columns ic 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0
              ) = 1
              AND EXISTS (
                  SELECT 1 
                  FROM sys.index_columns ic 
                  JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0 
                    AND c.name = 'KeyProfesional'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Profesional.KeyProfesional debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Profesional') AND c.name = 'id_profesional' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Profesional.id_profesional debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Profesional') AND name = 'KeyProfesional')
    BEGIN
        DECLARE @hasMem0_Profesional INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Profesional WHERE KeyProfesional = 0', N'@c INT OUTPUT', @c = @hasMem0_Profesional OUTPUT;
        IF @hasMem0_Profesional = 0
            SET @ErroresPreval += '- dbo.Dim_Profesional no contiene el miembro desconocido verificado (KeyProfesional = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.5 Validación de Dim_Negociador
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Negociador', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Negociador.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Negociador') AND c.name = 'KeyNegociador' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Negociador.KeyNegociador debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Negociador')
              AND (i.is_primary_key = 1 OR i.is_unique = 1)
              AND i.is_disabled = 0
              AND i.has_filter = 0
              AND i.is_hypothetical = 0
              AND (
                  SELECT COUNT(*) 
                  FROM sys.index_columns ic 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0
              ) = 1
              AND EXISTS (
                  SELECT 1 
                  FROM sys.index_columns ic 
                  JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0 
                    AND c.name = 'KeyNegociador'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Negociador.KeyNegociador debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Negociador') AND c.name = 'id_usuario' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Negociador.id_usuario debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Negociador') AND name = 'KeyNegociador')
    BEGIN
        DECLARE @hasMem0_Negociador INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Negociador WHERE KeyNegociador = 0', N'@c INT OUTPUT', @c = @hasMem0_Negociador OUTPUT;
        IF @hasMem0_Negociador = 0
            SET @ErroresPreval += '- dbo.Dim_Negociador no contiene el miembro desconocido verificado (KeyNegociador = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.6 Validación de Dim_Persona (Estructura Contractual para H3)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Persona', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Persona (Contrato 12 / H3).' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Persona') AND c.name = 'KeyPersona' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Persona.KeyPersona debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Persona')
              AND (i.is_primary_key = 1 OR i.is_unique = 1)
              AND i.is_disabled = 0
              AND i.has_filter = 0
              AND i.is_hypothetical = 0
              AND (
                  SELECT COUNT(*) 
                  FROM sys.index_columns ic 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0
              ) = 1
              AND EXISTS (
                  SELECT 1 
                  FROM sys.index_columns ic 
                  JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id 
                  WHERE ic.object_id = i.object_id 
                    AND ic.index_id = i.index_id 
                    AND ic.is_included_column = 0 
                    AND c.name = 'KeyPersona'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Persona.KeyPersona debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Persona') AND name = 'KeyPersona')
    BEGIN
        DECLARE @hasMem0_Persona INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Persona WHERE KeyPersona = 0', N'@c INT OUTPUT', @c = @hasMem0_Persona OUTPUT;
        IF @hasMem0_Persona = 0
            SET @ErroresPreval += '- dbo.Dim_Persona no contiene el miembro desconocido verificado (KeyPersona = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.7 Validación de Config_CalendarioAtencion_ETL (Configuración de Intervalos Hábiles)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Config_CalendarioAtencion_ETL', 'U') IS NOT NULL
BEGIN
    DECLARE @CantIntervalosActivos INT = 0;
    EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Config_CalendarioAtencion_ETL WHERE EsLaborable = 1', N'@c INT OUTPUT', @c = @CantIntervalosActivos OUTPUT;
    IF @CantIntervalosActivos = 0
        SET @ErroresPreval += '- dbo.Config_CalendarioAtencion_ETL preexistente no tiene intervalos laborables activos (EsLaborable = 1).' + CHAR(13) + CHAR(10);
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.8 Validación Exhaustiva de Fact_NegociacionLead Preexistente (si ya existe)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Fact_NegociacionLead', 'U') IS NOT NULL
BEGIN
    -- 1. Validar Clave Primaria Simple
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes i
        JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID('dbo.Fact_NegociacionLead')
          AND i.is_primary_key = 1
          AND c.name = 'KeyFactLead'
          AND (SELECT COUNT(*) FROM sys.index_columns ic2 WHERE ic2.object_id = i.object_id AND ic2.index_id = i.index_id) = 1
    )
        SET @ErroresPreval += '- dbo.Fact_NegociacionLead preexistente debe tener PRIMARY KEY simple sobre KeyFactLead.' + CHAR(13) + CHAR(10);

    -- 2. Validar Unicidad Simple de Solicitud de Origen (Natural Key de Idempotencia)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes i
        JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID('dbo.Fact_NegociacionLead')
          AND i.is_unique = 1
          AND i.is_disabled = 0
          AND i.has_filter = 0
          AND c.name = 'id_solicitud_origen'
          AND (
              SELECT COUNT(*) 
              FROM sys.index_columns ic2 
              WHERE ic2.object_id = i.object_id 
                AND ic2.index_id = i.index_id 
                AND ic2.is_included_column = 0
          ) = 1
    )
        SET @ErroresPreval += '- dbo.Fact_NegociacionLead preexistente debe tener restricción PRIMARY KEY o UNIQUE simple exclusivo sobre id_solicitud_origen (sin columnas compuestas).' + CHAR(13) + CHAR(10);

    -- 3. Validar las 29 Columnas Contractuales
    DECLARE @ColumnasIncompatiblesLead VARCHAR(MAX) = '';
    SELECT @ColumnasIncompatiblesLead += req.col + ' (' + req.motivo + '), '
    FROM (
        SELECT 
            r.col,
            CASE 
                WHEN c.column_id IS NULL THEN 'Columna ausente'
                WHEN t.name <> r.tipo THEN CONCAT('Tipo esperado ', r.tipo, ', detectado ', t.name)
                WHEN c.is_nullable <> r.nullable THEN CONCAT('Nulabilidad esperada is_nullable=', r.nullable, ', detectado ', c.is_nullable)
                WHEN r.long_min > 0 AND c.max_length > 0 AND c.max_length < r.long_min THEN CONCAT('Longitud insuficiente: ', c.max_length, ' < ', r.long_min)
                WHEN r.tipo = 'decimal' AND (c.scale < r.req_scale OR (c.precision - c.scale) < (r.req_prec - r.req_scale)) 
                    THEN CONCAT('Capacidad decimal insuficiente: decimal(', c.precision, ',', c.scale, ') tiene ', (c.precision - c.scale), ' digitos enteros y escala ', c.scale, ' (requiere al menos ', (r.req_prec - r.req_scale), ' enteros y escala >= ', r.req_scale, ')')
                WHEN r.tipo = 'datetime2' AND c.scale < r.req_scale THEN CONCAT('Escala datetime2 insuficiente: ', c.scale, ' < ', r.req_scale)
                ELSE 'OK'
            END AS motivo
        FROM (VALUES 
            ('KeyFactLead', 'bigint', 0, 0, 0, 0),
            ('id_solicitud_origen', 'int', 0, 0, 0, 0),
            ('id_persona_origen', 'int', 0, 0, 0, 0),
            ('KeyTiempoSolicitud', 'int', 0, 0, 0, 0),
            ('KeyTiempoReserva', 'int', 0, 0, 0, 0),
            ('KeySede', 'int', 0, 0, 0, 0),
            ('KeyServicio', 'int', 0, 0, 0, 0),
            ('KeyProfesional', 'int', 0, 0, 0, 0),
            ('KeyNegociador', 'int', 0, 0, 0, 0),
            ('KeyPersona', 'int', 0, 0, 0, 0),
            ('SolicitudesRegistradas', 'int', 0, 0, 0, 0),
            ('LeadsCohorteEvaluable', 'int', 0, 0, 0, 0),
            ('CohorteInmadura', 'int', 0, 0, 0, 0),
            ('LeadsConvertidosPayer14Dias', 'int', 0, 0, 0, 0),
            ('LeadsConvertidosPayerTotal', 'int', 0, 0, 0, 0),
            ('LeadsAbandonados', 'int', 0, 0, 0, 0),
            ('LeadsEnNegociacion', 'int', 0, 0, 0, 0),
            ('LeadsResultadoFinal', 'int', 0, 0, 0, 0),
            ('LeadsRequierenRespuesta', 'int', 0, 0, 0, 0),
            ('LeadsRespuestaUtil15Min', 'int', 0, 0, 0, 0),
            ('SegundosPrimeraRespuesta', 'int', 1, 0, 0, 0),
            ('MinutosPrimeraRespuesta', 'int', 1, 0, 0, 0),
            ('EstadoRespuestaSLA', 'varchar', 0, 30, 0, 0),
            ('AtribucionHeuristica', 'bit', 0, 0, 0, 0),
            ('AtribucionAmbigua', 'bit', 0, 0, 0, 0),
            ('PrecioCotizado', 'decimal', 1, 0, 10, 2),
            ('BatchId', 'varchar', 0, 50, 0, 0),
            ('FechaCarga', 'datetime2', 0, 0, 0, 7),
            ('UsuarioCarga', 'varchar', 0, 30, 0, 0)
        ) AS r(col, tipo, nullable, long_min, req_prec, req_scale)
        LEFT JOIN sys.columns c ON c.object_id = OBJECT_ID('dbo.Fact_NegociacionLead') AND c.name = r.col
        LEFT JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.column_id IS NULL
           OR t.name <> r.tipo
           OR c.is_nullable <> r.nullable
           OR (r.long_min > 0 AND c.max_length > 0 AND c.max_length < r.long_min)
           OR (r.tipo = 'decimal' AND (c.scale < r.req_scale OR (c.precision - c.scale) < (r.req_prec - r.req_scale)))
           OR (r.tipo = 'datetime2' AND c.scale < r.req_scale)
    ) AS req;

    IF LEN(@ColumnasIncompatiblesLead) > 0
        SET @ErroresPreval += '- dbo.Fact_NegociacionLead preexistente presenta columnas faltantes o especificaciones incompatibles: ' + SUBSTRING(@ColumnasIncompatiblesLead, 1, LEN(@ColumnasIncompatiblesLead)-1) + '.' + CHAR(13) + CHAR(10);

    -- 4. Validar las 7 Claves Foráneas Contractuales
    DECLARE @FKIncompatiblesLead VARCHAR(MAX) = '';
    SELECT @FKIncompatiblesLead += req_fk.col_origen + ' -> ' + req_fk.tabla_ref + '(' + req_fk.col_ref + ') [' + req_fk.motivo + '], '
    FROM (
        SELECT 
            v.col_origen, v.tabla_ref, v.col_ref,
            CASE 
                WHEN fk.object_id IS NULL THEN 'FK inexistente o no coincide tabla/columna'
                WHEN fk.is_disabled = 1 THEN 'FK deshabilitada (is_disabled = 1)'
                WHEN fk.is_not_trusted = 1 THEN 'FK no confiable (is_not_trusted = 1)'
                ELSE 'Incompatible'
            END AS motivo
        FROM (VALUES 
            ('KeyTiempoSolicitud', 'Dim_Tiempo', 'KeyTiempo'),
            ('KeyTiempoReserva', 'Dim_Tiempo', 'KeyTiempo'),
            ('KeySede', 'Dim_Sede', 'KeySede'),
            ('KeyServicio', 'Dim_Servicio', 'KeyServicio'),
            ('KeyNegociador', 'Dim_Negociador', 'KeyNegociador'),
            ('KeyProfesional', 'Dim_Profesional', 'KeyProfesional'),
            ('KeyPersona', 'Dim_Persona', 'KeyPersona')
        ) AS v(col_origen, tabla_ref, col_ref)
        LEFT JOIN (
            SELECT 
                fk.object_id,
                fk.is_disabled,
                fk.is_not_trusted,
                c_parent.name AS parent_col,
                OBJECT_NAME(fk.referenced_object_id) AS ref_table,
                c_ref.name AS ref_col
            FROM sys.foreign_keys fk
            JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
            JOIN sys.columns c_parent ON fkc.parent_object_id = c_parent.object_id AND fkc.parent_column_id = c_parent.column_id
            JOIN sys.columns c_ref ON fkc.referenced_object_id = c_ref.object_id AND fkc.referenced_column_id = c_ref.column_id
            WHERE fk.parent_object_id = OBJECT_ID('dbo.Fact_NegociacionLead')
              AND (SELECT COUNT(*) FROM sys.foreign_key_columns fkc2 WHERE fkc2.constraint_object_id = fk.object_id) = 1
        ) fk ON fk.parent_col = v.col_origen 
            AND fk.ref_table = v.tabla_ref 
            AND fk.ref_col = v.col_ref
        WHERE fk.object_id IS NULL
           OR fk.is_disabled = 1
           OR fk.is_not_trusted = 1
    ) AS req_fk;

    IF LEN(@FKIncompatiblesLead) > 0
        SET @ErroresPreval += '- dbo.Fact_NegociacionLead preexistente presenta claves foráneas ausentes, deshabilitadas o no confiables: ' + SUBSTRING(@FKIncompatiblesLead, 1, LEN(@FKIncompatiblesLead)-1) + '.' + CHAR(13) + CHAR(10);
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.9 Validación de Tablas Auxiliares Preexistentes
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Log_Ejecucion_ETL', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Log_Ejecucion_ETL') AND name = 'LogId' AND is_identity = 1
    )
        SET @ErroresPreval += '- dbo.Log_Ejecucion_ETL preexistente no tiene columna identidad LogId.' + CHAR(13) + CHAR(10);

    DECLARE @ColsFaltantesLogLead VARCHAR(MAX) = '';
    SELECT @ColsFaltantesLogLead += req.col + ' (' + req.tipo_desc + '), '
    FROM (VALUES 
        ('Procedimiento', 'varchar/nvarchar(>=100)'),
        ('BatchId', 'varchar/nvarchar(>=50)'),
        ('TipoEvento', 'varchar/nvarchar(>=30)'),
        ('Mensaje', 'varchar/nvarchar/max'),
        ('LineaError', 'int'),
        ('FechaRegistro', 'datetime/datetime2')
    ) AS req(col, tipo_desc)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Log_Ejecucion_ETL') AND name = req.col
    );

    IF LEN(@ColsFaltantesLogLead) > 0
        SET @ErroresPreval += '- dbo.Log_Ejecucion_ETL preexistente presenta columnas faltantes o incompatibles: ' + SUBSTRING(@ColsFaltantesLogLead, 1, LEN(@ColsFaltantesLogLead)-1) + '.' + CHAR(13) + CHAR(10);
END;

IF OBJECT_ID('dbo.Rechazos_ETL_Lead', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Rechazos_ETL_Lead') AND name = 'RechazoId' AND is_identity = 1
    )
        SET @ErroresPreval += '- dbo.Rechazos_ETL_Lead preexistente no tiene columna identidad RechazoId.' + CHAR(13) + CHAR(10);

    DECLARE @ColsFaltantesRechLead VARCHAR(MAX) = '';
    SELECT @ColsFaltantesRechLead += req.col + ' (' + req.tipo_desc + '), '
    FROM (VALUES 
        ('id_solicitud_origen', 'int'),
        ('MotivoRechazo', 'varchar/nvarchar(>=100)'),
        ('DetalleRechazo', 'varchar/nvarchar/max'),
        ('BatchId', 'varchar/nvarchar(>=50)'),
        ('FechaRechazo', 'datetime/datetime2')
    ) AS req(col, tipo_desc)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Rechazos_ETL_Lead') AND name = req.col
    );

    IF LEN(@ColsFaltantesRechLead) > 0
        SET @ErroresPreval += '- dbo.Rechazos_ETL_Lead preexistente presenta columnas faltantes o incompatibles: ' + SUBSTRING(@ColsFaltantesRechLead, 1, LEN(@ColsFaltantesRechLead)-1) + '.' + CHAR(13) + CHAR(10);
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.10 Validación de Calendario de Atención Preexistente
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Config_CalendarioAtencion_ETL', 'U') IS NOT NULL
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM dbo.Config_CalendarioAtencion_ETL c1
        JOIN dbo.Config_CalendarioAtencion_ETL c2
          ON c1.DiaSemana = c2.DiaSemana
         AND c1.IdIntervalo <> c2.IdIntervalo
         AND c1.EsLaborable = 1 AND c1.Activo = 1
         AND c2.EsLaborable = 1 AND c2.Activo = 1
         AND c1.HoraInicio < c2.HoraFin
         AND c2.HoraInicio < c1.HoraFin
    )
        SET @ErroresPreval += '- dbo.Config_CalendarioAtencion_ETL presenta intervalos laborables activos superpuestos para el mismo día de la semana.' + CHAR(13) + CHAR(10);
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.11 Evaluación Final de Errores de Prevalidación y Activación Defensiva
-- ----------------------------------------------------------------------------------------------------
IF LEN(@ErroresPreval) > 0
BEGIN
    SET @ErroresPreval = '=====================================================================' + CHAR(13) + CHAR(10)
                       + 'ERROR CRÍTICO DE PREVALIDACIÓN EN DESPLIEGUE LEAD (H3):' + CHAR(13) + CHAR(10)
                       + 'Se aborta el despliegue sin realizar cambios ni crear objetos parciales.' + CHAR(13) + CHAR(10)
                       + 'Detalle de discrepancias detectadas:' + CHAR(13) + CHAR(10)
                       + @ErroresPreval
                       + '=====================================================================';
    RAISERROR(@ErroresPreval, 16, 1);
    SET NOEXEC ON;
END;
GO

-- ====================================================================================================
-- LOTE 2: CREACIÓN DE OBJETOS AUXILIARES (BITÁCORA, RECHAZOS Y CALENDARIO HÁBIL)
-- ====================================================================================================

-- ----------------------------------------------------------------------------------------------------
-- 2.1 Tabla de Bitácora Operativa ETL (dbo.Log_Ejecucion_ETL)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Log_Ejecucion_ETL', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Log_Ejecucion_ETL (
        LogId           BIGINT IDENTITY(1,1) NOT NULL,
        Procedimiento   VARCHAR(100) NOT NULL,
        BatchId         VARCHAR(50) NOT NULL,
        TipoEvento      VARCHAR(30) NOT NULL,
        Mensaje         VARCHAR(2048) NOT NULL,
        LineaError      INT NULL,
        FechaRegistro   DATETIME2(7) NOT NULL CONSTRAINT DF_LogETL_FechaReg DEFAULT GETDATE(),
        CONSTRAINT PK_Log_Ejecucion_ETL PRIMARY KEY CLUSTERED (LogId)
    );
    PRINT '>> Tabla [dbo].[Log_Ejecucion_ETL] creada exitosamente.';
END;
GO

-- ----------------------------------------------------------------------------------------------------
-- 2.2 Tabla de Rechazos de Calidad y Resolución LEAD (dbo.Rechazos_ETL_Lead)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Rechazos_ETL_Lead', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Rechazos_ETL_Lead (
        RechazoId           BIGINT IDENTITY(1,1) NOT NULL,
        id_solicitud_origen INT NULL,
        MotivoRechazo       VARCHAR(150) NOT NULL,
        DetalleRechazo      VARCHAR(MAX) NULL,
        BatchId             VARCHAR(50) NOT NULL,
        FechaRechazo        DATETIME2(7) NOT NULL CONSTRAINT DF_RechazosLead_Fecha DEFAULT GETDATE(),
        CONSTRAINT PK_Rechazos_ETL_Lead PRIMARY KEY CLUSTERED (RechazoId)
    );
    CREATE NONCLUSTERED INDEX IX_RechazosLead_Batch ON dbo.Rechazos_ETL_Lead (BatchId);
    CREATE NONCLUSTERED INDEX IX_RechazosLead_Solicitud ON dbo.Rechazos_ETL_Lead (id_solicitud_origen);
    PRINT '>> Tabla [dbo].[Rechazos_ETL_Lead] creada exitosamente.';
END;
GO

-- ----------------------------------------------------------------------------------------------------
-- 2.3 Tabla de Configuración de Calendario de Atención Hábil (dbo.Config_CalendarioAtencion_ETL)
-- Permite definir intervalos de atención por día de la semana para el cómputo del SLA L2.
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Config_CalendarioAtencion_ETL', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Config_CalendarioAtencion_ETL (
        IdIntervalo         INT NOT NULL,
        DiaSemana           INT NOT NULL, -- 1=Lunes, 2=Martes, 3=Miércoles, 4=Jueves, 5=Viernes, 6=Sábado, 7=Domingo
        HoraInicio          TIME(0) NOT NULL,
        HoraFin             TIME(0) NOT NULL,
        EsLaborable         BIT NOT NULL CONSTRAINT DF_ConfigCal_EsLab DEFAULT 1,
        Activo              BIT NOT NULL CONSTRAINT DF_ConfigCal_Activo DEFAULT 1,
        DescripcionHorario  VARCHAR(100) NULL,
        CONSTRAINT PK_ConfigCalendario_ETL PRIMARY KEY CLUSTERED (IdIntervalo),
        CONSTRAINT CK_ConfigCalendario_DiaSemana CHECK (DiaSemana BETWEEN 1 AND 7),
        CONSTRAINT CK_ConfigCalendario_Horas CHECK (HoraInicio < HoraFin)
    );
    PRINT '>> Tabla [dbo].[Config_CalendarioAtencion_ETL] creada exitosamente.';
END;
GO

-- ----------------------------------------------------------------------------------------------------
-- 2.4 Función Escalar Determinista para Cómputo de Segundos Hábiles (dbo.fn_CalcularSegundosHabiles)
-- Descuenta noches, domingos y horas no laborables según dbo.Config_CalendarioAtencion_ETL.
-- Totalmente independiente de @@DATEFIRST, sin límite artificial de 366 días (soporta hasta 65,536 días)
-- y con protección ante desbordamientos numéricos e intervalos superpuestos.
-- ----------------------------------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fn_CalcularSegundosHabiles (
    @FechaInicio DATETIME2(7),
    @FechaFin    DATETIME2(7)
)
RETURNS INT
AS
BEGIN
    IF @FechaInicio IS NULL OR @FechaFin IS NULL OR @FechaInicio > @FechaFin
        RETURN NULL;
    
    IF @FechaInicio = @FechaFin
        RETURN 0;

    -- Si la tabla no contiene intervalos laborables activos, devuelve NULL (marca falta de configuración)
    IF NOT EXISTS (SELECT 1 FROM dbo.Config_CalendarioAtencion_ETL WHERE EsLaborable = 1 AND Activo = 1)
        RETURN NULL;

    -- Si existen intervalos laborables activos superpuestos en el mismo día, devuelve NULL (evita duplicación)
    IF EXISTS (
        SELECT 1 
        FROM dbo.Config_CalendarioAtencion_ETL c1
        JOIN dbo.Config_CalendarioAtencion_ETL c2
          ON c1.DiaSemana = c2.DiaSemana
         AND c1.IdIntervalo <> c2.IdIntervalo
         AND c1.EsLaborable = 1 AND c1.Activo = 1
         AND c2.EsLaborable = 1 AND c2.Activo = 1
         AND c1.HoraInicio < c2.HoraFin
         AND c2.HoraInicio < c1.HoraFin
    )
        RETURN NULL;

    DECLARE @DiasTotal INT = DATEDIFF(DAY, CAST(@FechaInicio AS DATE), CAST(@FechaFin AS DATE));
    DECLARE @SegundosHabilesBig BIGINT = 0;

    -- Control de capacidad: si el intervalo excede el generador (65,535 días) devuelve NULL
    IF @DiasTotal > 65535
        RETURN NULL;

    -- Generador de números sin límite de recursión (soporta hasta 65,536 días sin MAXRECURSION)
    ;WITH L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
    L1 AS (SELECT 1 AS c FROM L0 A CROSS JOIN L0 B), -- 4
    L2 AS (SELECT 1 AS c FROM L1 A CROSS JOIN L1 B), -- 16
    L3 AS (SELECT 1 AS c FROM L2 A CROSS JOIN L2 B), -- 256
    L4 AS (SELECT 1 AS c FROM L3 A CROSS JOIN L3 B), -- 65536
    Nums AS (
        SELECT TOP (@DiasTotal + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM L4
    ),
    DiasRango AS (
        SELECT DATEADD(DAY, n, CAST(@FechaInicio AS DATE)) AS FechaDia
        FROM Nums
    ),
    IntervalosEfectivos AS (
        SELECT 
            d.FechaDia,
            c.HoraInicio,
            c.HoraFin,
            DATETIMEFROMPARTS(
                YEAR(d.FechaDia), MONTH(d.FechaDia), DAY(d.FechaDia), 
                DATEPART(HOUR, c.HoraInicio), DATEPART(MINUTE, c.HoraInicio), DATEPART(SECOND, c.HoraInicio), 0
            ) AS IntervInicio,
            DATETIMEFROMPARTS(
                YEAR(d.FechaDia), MONTH(d.FechaDia), DAY(d.FechaDia), 
                DATEPART(HOUR, c.HoraFin), DATEPART(MINUTE, c.HoraFin), DATEPART(SECOND, c.HoraFin), 0
            ) AS IntervFin
        FROM DiasRango d
        JOIN dbo.Config_CalendarioAtencion_ETL c 
          ON c.DiaSemana = (((DATEPART(dw, d.FechaDia) + @@DATEFIRST - 2) % 7) + 1)
         AND c.EsLaborable = 1
         AND c.Activo = 1
    ),
    Intersecciones AS (
        SELECT 
            CASE WHEN @FechaInicio > IntervInicio THEN @FechaInicio ELSE IntervInicio END AS EfecInicio,
            CASE WHEN @FechaFin < IntervFin THEN @FechaFin ELSE IntervFin END AS EfecFin
        FROM IntervalosEfectivos
    )
    SELECT @SegundosHabilesBig = ISNULL(SUM(
        CASE WHEN EfecInicio < EfecFin THEN CAST(DATEDIFF(SECOND, EfecInicio, EfecFin) AS BIGINT) ELSE 0 END
    ), 0)
    FROM Intersecciones;

    -- Control de desbordamiento contractual: si excede el rango máximo del tipo INT contractual (2,147,483,647 s)
    -- devuelve NULL como diagnóstico controlado (no devuelve una duración truncada o saturada como si fuera exacta)
    IF @SegundosHabilesBig > 2147483647
        RETURN NULL;

    RETURN CAST(@SegundosHabilesBig AS INT);
END;
GO

PRINT '>> Función escalar [dbo].[fn_CalcularSegundosHabiles] creada exitosamente.';
GO

-- ====================================================================================================
-- LOTE 3: DDL DE LA TABLA DE HECHOS dbo.Fact_NegociacionLead
-- Grano Atómico: Exactamente 1 fila por solicitud formal (id_solicitud_origen)
-- Claves Foráneas: 7 restricciones hacia 6 dimensiones conformadas (Dim_Tiempo referenciada doblemente)
-- ====================================================================================================

IF OBJECT_ID('dbo.Fact_NegociacionLead', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Fact_NegociacionLead (
        KeyFactLead                 BIGINT IDENTITY(1,1) NOT NULL,
        id_solicitud_origen         INT NOT NULL,
        id_persona_origen           INT NOT NULL,
        KeyTiempoSolicitud          INT NOT NULL,
        KeyTiempoReserva            INT NOT NULL CONSTRAINT DF_FactLead_KeyTiempoReserva DEFAULT 0,
        KeySede                     INT NOT NULL CONSTRAINT DF_FactLead_KeySede DEFAULT 0,
        KeyServicio                 INT NOT NULL CONSTRAINT DF_FactLead_KeyServicio DEFAULT 0,
        KeyProfesional              INT NOT NULL CONSTRAINT DF_FactLead_KeyProfesional DEFAULT 0,
        KeyNegociador               INT NOT NULL CONSTRAINT DF_FactLead_KeyNegociador DEFAULT 0,
        KeyPersona                  INT NOT NULL CONSTRAINT DF_FactLead_KeyPersona DEFAULT 0,
        
        -- Métricas Oficiales (L1, L2, L3 y compatibilidad report.routes.ts)
        SolicitudesRegistradas      INT NOT NULL CONSTRAINT DF_FactLead_SolReg DEFAULT 1,
        LeadsCohorteEvaluable       INT NOT NULL CONSTRAINT DF_FactLead_CohorteEval DEFAULT 0,
        CohorteInmadura             INT NOT NULL CONSTRAINT DF_FactLead_CohorteInmadura DEFAULT 0,
        LeadsConvertidosPayer14Dias INT NOT NULL CONSTRAINT DF_FactLead_Conv14D DEFAULT 0,
        LeadsConvertidosPayerTotal  INT NOT NULL CONSTRAINT DF_FactLead_ConvTotal DEFAULT 0,
        LeadsAbandonados            INT NOT NULL CONSTRAINT DF_FactLead_Abandonados DEFAULT 0,
        LeadsEnNegociacion          INT NOT NULL CONSTRAINT DF_FactLead_EnNegoc DEFAULT 0,
        LeadsResultadoFinal         INT NOT NULL CONSTRAINT DF_FactLead_ResFinal DEFAULT 0,
        LeadsRequierenRespuesta     INT NOT NULL CONSTRAINT DF_FactLead_ReqResp DEFAULT 1,
        LeadsRespuestaUtil15Min     INT NOT NULL CONSTRAINT DF_FactLead_RespUtil15M DEFAULT 0,
        SegundosPrimeraRespuesta    INT NULL,
        MinutosPrimeraRespuesta     INT NULL,
        EstadoRespuestaSLA          VARCHAR(30) NOT NULL CONSTRAINT DF_FactLead_EstadoSLA DEFAULT 'PendienteDentroSLA',
        AtribucionHeuristica        BIT NOT NULL CONSTRAINT DF_FactLead_AtribHeur DEFAULT 0,
        AtribucionAmbigua           BIT NOT NULL CONSTRAINT DF_FactLead_AtribAmbig DEFAULT 0,
        PrecioCotizado              DECIMAL(10,2) NULL,
        
        -- Metadatos de Auditoría ETL
        BatchId                     VARCHAR(50) NOT NULL,
        FechaCarga                  DATETIME2(7) NOT NULL CONSTRAINT DF_FactLead_FechaCarga DEFAULT GETDATE(),
        UsuarioCarga                VARCHAR(50) NOT NULL CONSTRAINT DF_FactLead_UsuarioCarga DEFAULT SYSTEM_USER,
        
        CONSTRAINT PK_Fact_NegociacionLead PRIMARY KEY CLUSTERED (KeyFactLead),
        CONSTRAINT UQ_Fact_NegociacionLead_Origen UNIQUE NONCLUSTERED (id_solicitud_origen),
        CONSTRAINT FK_FactLead_TiempoSolicitud FOREIGN KEY (KeyTiempoSolicitud) REFERENCES dbo.Dim_Tiempo (KeyTiempo),
        CONSTRAINT FK_FactLead_TiempoReserva FOREIGN KEY (KeyTiempoReserva) REFERENCES dbo.Dim_Tiempo (KeyTiempo),
        CONSTRAINT FK_FactLead_Sede FOREIGN KEY (KeySede) REFERENCES dbo.Dim_Sede (KeySede),
        CONSTRAINT FK_FactLead_Servicio FOREIGN KEY (KeyServicio) REFERENCES dbo.Dim_Servicio (KeyServicio),
        CONSTRAINT FK_FactLead_Negociador FOREIGN KEY (KeyNegociador) REFERENCES dbo.Dim_Negociador (KeyNegociador),
        CONSTRAINT FK_FactLead_Profesional FOREIGN KEY (KeyProfesional) REFERENCES dbo.Dim_Profesional (KeyProfesional),
        CONSTRAINT FK_FactLead_Persona FOREIGN KEY (KeyPersona) REFERENCES dbo.Dim_Persona (KeyPersona)
    );

    CREATE NONCLUSTERED INDEX IX_FactLead_TiempoSol ON dbo.Fact_NegociacionLead (KeyTiempoSolicitud);
    CREATE NONCLUSTERED INDEX IX_FactLead_TiempoRes ON dbo.Fact_NegociacionLead (KeyTiempoReserva);
    CREATE NONCLUSTERED INDEX IX_FactLead_Persona ON dbo.Fact_NegociacionLead (id_persona_origen);
    CREATE NONCLUSTERED INDEX IX_FactLead_Batch ON dbo.Fact_NegociacionLead (BatchId);

    PRINT '>> Tabla de Hechos [dbo].[Fact_NegociacionLead] creada exitosamente con sus 7 restricciones Foreign Key.';
END;
GO

-- ====================================================================================================
-- LOTE 4: PROCEDIMIENTO ALMACENADO DE CARGA dbo.usp_Cargar_Fact_NegociacionLead
-- Implementa el Algoritmo 2 del Entregable 14 (Sección 5.3):
-- - Validación bloqueante de parámetros, configuración de hito y miembros desconocidos.
-- - Extracción escalar y enriquecimiento de opciones, reservas y precios anteriores al corte.
-- - Atribución global de interacciones útiles 1:1 por persona con conservación monótona de ambigüedad.
-- - Cómputo de SLA hábil con precedencia estricta de EvidenciaInsuficiente.
-- - Clasificación disjunta previa protegida bajo sp_getapplock exclusivo dentro de transacción.
-- - Confirmación atómica y derivación de contadores de salida.
-- ====================================================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Cargar_Fact_NegociacionLead
    @FechaCorte             DATE,
    @BatchId                VARCHAR(50),
    @ConfigHitoConversion   VARCHAR(50), -- 'CreacionReserva' o 'ConfirmacionReserva'
    @FuenteOLTP             sysname = NULL,
    @ConvencionHoraria      VARCHAR(50) = NULL, -- Convención horaria explícita requerida
    @Insertados             INT = 0 OUTPUT,
    @Actualizados           INT = 0 OUTPUT,
    @SinCambio              INT = 0 OUTPUT,
    @Rechazados             INT = 0 OUTPUT,
    @Pendientes             INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Inicialización defensiva de contadores de salida
    SET @Insertados = 0;
    SET @Actualizados = 0;
    SET @SinCambio = 0;
    SET @Rechazados = 0;
    SET @Pendientes = 0;

    DECLARE @ProcName VARCHAR(100) = 'dbo.usp_Cargar_Fact_NegociacionLead';
    DECLARE @InstanteEvaluacion DATETIME2(7);
    DECLARE @LockResource VARCHAR(100) = 'ETL_Lock_Fact_NegociacionLead';
    DECLARE @ResLock INT;

    -- ------------------------------------------------------------------------------------------------
    -- PASO 1: VALIDACIÓN PREVIA DE PARÁMETROS, CONVENCIÓN HORARIA Y CONFIGURACIÓN DE HITO
    -- ------------------------------------------------------------------------------------------------
    -- Convención Horaria Contractual:
    -- Se exige y valida que la convención horaria de los timestamps del origen y @FechaCorte sea configurada
    -- explícitamente (ej. 'Local_Clinica_SinOffset', 'America/Lima'). No se asume 'Perú local' como decisión
    -- institucional por defecto ni se realizan conversiones de zona horaria sin evidencia ni metadatos en origen.
    IF @ConvencionHoraria IS NULL OR LTRIM(RTRIM(@ConvencionHoraria)) = ''
    BEGIN
        RAISERROR('Error de Parámetros: @ConvencionHoraria es obligatorio y no puede ser NULL ni vacío. Se exige configurar explícitamente la convención horaria de los timestamps de origen (ej. ''Local_Clinica_SinOffset'', ''America/Lima''). No se asume ninguna por defecto ni se realizan conversiones sin metadatos.', 16, 1);
        RETURN -1;
    END;

    IF @FechaCorte IS NULL
    BEGIN
        RAISERROR('Error de Parámetros: @FechaCorte es obligatorio y no puede ser NULL.', 16, 1);
        RETURN -1;
    END;

    IF @BatchId IS NULL OR LTRIM(RTRIM(@BatchId)) = ''
    BEGIN
        RAISERROR('Error de Parámetros: @BatchId es obligatorio y no puede ser vacío.', 16, 1);
        RETURN -1;
    END;

    -- Verificación explícita de configuración de hito de conversión (no se asume ninguna por defecto)
    IF @ConfigHitoConversion IS NULL OR LTRIM(RTRIM(@ConfigHitoConversion)) = ''
    BEGIN
        RAISERROR('Error de Parámetros: @ConfigHitoConversion es obligatorio y no puede ser NULL ni vacío. Se exige configurar explícitamente ''CreacionReserva'' o ''ConfirmacionReserva''.', 16, 1);
        RETURN -1;
    END;

    IF UPPER(LTRIM(RTRIM(@ConfigHitoConversion))) = 'PAGOVALIDADO'
    BEGIN
        RAISERROR('Configuración Bloqueada: El hito "PagoValidado" permanece bloqueado en staging 13 y no está habilitado.', 16, 1);
        RETURN -1;
    END;

    IF @ConfigHitoConversion NOT IN ('CreacionReserva', 'ConfirmacionReserva')
    BEGIN
        RAISERROR('Configuración Inválida: @ConfigHitoConversion ("%s") no es reconocido. Se exige configurar explícitamente "CreacionReserva" o "ConfirmacionReserva".', 16, 1, @ConfigHitoConversion);
        RETURN -1;
    END;

    -- Validación de la fuente OLTP para recalcular opciones, reservas y disponibilidad
    IF @FuenteOLTP IS NULL OR LTRIM(RTRIM(@FuenteOLTP)) = ''
    BEGIN
        RAISERROR('Error de Configuración: El parámetro @FuenteOLTP es obligatorio y debe especificarse de forma explícita y validada. No se infiere automáticamente una base real.', 16, 1);
        RETURN -1;
    END;

    IF DB_ID(@FuenteOLTP) IS NULL
    BEGIN
        RAISERROR('Error de Configuración: La base de datos origen especificada en @FuenteOLTP ("%s") no existe en la instancia de SQL Server.', 16, 1, @FuenteOLTP);
        RETURN -1;
    END;

    IF OBJECT_ID(QUOTENAME(@FuenteOLTP) + '.dbo.Opciones', 'U') IS NULL
       OR OBJECT_ID(QUOTENAME(@FuenteOLTP) + '.dbo.Reservas', 'U') IS NULL
       OR OBJECT_ID(QUOTENAME(@FuenteOLTP) + '.dbo.Disponibilidad', 'U') IS NULL
    BEGIN
        RAISERROR('Error de Configuración: La base de datos origen [ %s ] no contiene las tablas requeridas dbo.Opciones, dbo.Reservas y dbo.Disponibilidad.', 16, 1, @FuenteOLTP);
        RETURN -1;
    END;

    -- Intervalo semiabierto: todos los eventos deben ser estrictamente anteriores a las 00:00:00 del día siguiente
    SET @InstanteEvaluacion = DATEADD(DAY, 1, CAST(@FechaCorte AS DATETIME2(7)));

    -- ------------------------------------------------------------------------------------------------
    -- PASO 2: VALIDACIÓN DE CALENDARIO HÁBIL Y MIEMBROS DESCONOCIDOS (KEY = 0)
    -- ------------------------------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.Config_CalendarioAtencion_ETL WHERE EsLaborable = 1 AND Activo = 1)
    BEGIN
        RAISERROR('Error de Configuración: dbo.Config_CalendarioAtencion_ETL no contiene intervalos laborables activos (EsLaborable = 1 y Activo = 1). Aborto defensivo de cálculo SLA.', 16, 1);
        RETURN -1;
    END;

    -- Rechazo de intervalos laborables activos superpuestos en el mismo día
    IF EXISTS (
        SELECT 1 
        FROM dbo.Config_CalendarioAtencion_ETL c1
        JOIN dbo.Config_CalendarioAtencion_ETL c2
          ON c1.DiaSemana = c2.DiaSemana
         AND c1.IdIntervalo <> c2.IdIntervalo
         AND c1.EsLaborable = 1 AND c1.Activo = 1
         AND c2.EsLaborable = 1 AND c2.Activo = 1
         AND c1.HoraInicio < c2.HoraFin
         AND c2.HoraInicio < c1.HoraFin
    )
    BEGIN
        RAISERROR('Error de Configuración: Se detectaron intervalos laborables superpuestos en dbo.Config_CalendarioAtencion_ETL para el mismo día de la semana. Se aborta la carga para evitar duplicación de segundos hábiles.', 16, 1);
        RETURN -1;
    END;

    IF (SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE KeyTiempo = 0) = 0
       OR (SELECT COUNT(*) FROM dbo.Dim_Sede WHERE KeySede = 0) = 0
       OR (SELECT COUNT(*) FROM dbo.Dim_Servicio WHERE KeyServicio = 0) = 0
       OR (SELECT COUNT(*) FROM dbo.Dim_Profesional WHERE KeyProfesional = 0) = 0
       OR (SELECT COUNT(*) FROM dbo.Dim_Negociador WHERE KeyNegociador = 0) = 0
       OR (SELECT COUNT(*) FROM dbo.Dim_Persona WHERE KeyPersona = 0) = 0
    BEGIN
        RAISERROR('Error de Dependencias: Uno o más miembros desconocidos (Key = 0) no existen en las dimensiones de destino.', 16, 1);
        RETURN -1;
    END;

    -- Registrar evento de inicio en bitácora
    INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError)
    VALUES (@ProcName, @BatchId, 'INFO', CONCAT('Inicio de carga LEAD con FechaCorte = ', CONVERT(VARCHAR(10), @FechaCorte, 120), ', Hito = ', @ConfigHitoConversion, ', FuenteOLTP = ', @FuenteOLTP, ', ConvencionHoraria = ', @ConvencionHoraria), 0);

    -- ------------------------------------------------------------------------------------------------
    -- PASO 3: EXTRACCIÓN TEMPORAL Y TABLAS TEMPORALES PARA PREPARACIÓN INTERMEDIA
    -- ------------------------------------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#OLTP_Opciones') IS NOT NULL DROP TABLE #OLTP_Opciones;
    IF OBJECT_ID('tempdb..#OLTP_Reservas') IS NOT NULL DROP TABLE #OLTP_Reservas;
    IF OBJECT_ID('tempdb..#OLTP_Disponibilidad') IS NOT NULL DROP TABLE #OLTP_Disponibilidad;
    IF OBJECT_ID('tempdb..#Stg_Solicitudes_Corte') IS NOT NULL DROP TABLE #Stg_Solicitudes_Corte;
    IF OBJECT_ID('tempdb..#SolicitudesAtribucion') IS NOT NULL DROP TABLE #SolicitudesAtribucion;
    IF OBJECT_ID('tempdb..#InteraccionesUtiles') IS NOT NULL DROP TABLE #InteraccionesUtiles;
    IF OBJECT_ID('tempdb..#Stg_Lead_Intermedio') IS NOT NULL DROP TABLE #Stg_Lead_Intermedio;

    CREATE TABLE #OLTP_Opciones (
        id_opcion           INT NOT NULL,
        id_solicitud        INT NOT NULL,
        id_disponibilidad   INT NULL,
        precio_ofrecido     DECIMAL(10,2) NULL,
        fecha_ofrecida      DATETIME2(7) NOT NULL,
        seleccionada        BIT NOT NULL
    );
    CREATE NONCLUSTERED INDEX IX_OLTP_Opc ON #OLTP_Opciones (id_solicitud, fecha_ofrecida, id_opcion);

    CREATE TABLE #OLTP_Reservas (
        id_reserva              INT NOT NULL,
        id_solicitud            INT NOT NULL,
        fecha_reserva           DATETIME2(7) NOT NULL,
        estado                  VARCHAR(50) NOT NULL,
        confirmacion_explicita  BIT NOT NULL,
        fecha_confirmacion      DATETIME2(7) NULL
    );
    CREATE NONCLUSTERED INDEX IX_OLTP_Res ON #OLTP_Reservas (id_solicitud, fecha_reserva, id_reserva);

    CREATE TABLE #OLTP_Disponibilidad (
        id_disponibilidad   INT NOT NULL PRIMARY KEY,
        id_sede             INT NULL,
        id_profesional      INT NULL
    );

    -- Extracción dinámica filtrada estrictamente por el instante de evaluación
    DECLARE @SqlExtract NVARCHAR(MAX) = N'
    INSERT INTO #OLTP_Opciones (id_opcion, id_solicitud, id_disponibilidad, precio_ofrecido, fecha_ofrecida, seleccionada)
    SELECT o.id_opcion, o.id_solicitud, o.id_disponibilidad, o.precio_ofrecido, o.fecha_ofrecida, o.seleccionada
    FROM ' + QUOTENAME(@FuenteOLTP) + N'.dbo.Opciones o
    WHERE o.fecha_ofrecida < @InstanteEvaluacion;

    INSERT INTO #OLTP_Reservas (id_reserva, id_solicitud, fecha_reserva, estado, confirmacion_explicita, fecha_confirmacion)
    SELECT r.id_reserva, r.id_solicitud, r.fecha_reserva, r.estado, r.confirmacion_explicita, r.fecha_confirmacion
    FROM ' + QUOTENAME(@FuenteOLTP) + N'.dbo.Reservas r
    WHERE r.fecha_reserva < @InstanteEvaluacion;

    INSERT INTO #OLTP_Disponibilidad (id_disponibilidad, id_sede, id_profesional)
    SELECT d.id_disponibilidad, d.id_sede, d.id_profesional
    FROM ' + QUOTENAME(@FuenteOLTP) + N'.dbo.Disponibilidad d;
    ';

    EXEC sp_executesql @SqlExtract,
        N'@InstanteEvaluacion DATETIME2(7)',
        @InstanteEvaluacion = @InstanteEvaluacion;

    -- 3.1 Extracción inicial de solicitudes anteriores al corte con opciones y reservas recalculadas
    CREATE TABLE #Stg_Solicitudes_Corte (
        id_solicitud                    INT NOT NULL PRIMARY KEY,
        id_persona                      INT NOT NULL,
        id_servicio_solicitado          INT NULL,
        fecha_solicitud                 DATETIME2(7) NOT NULL,
        estado_solicitud_norm           VARCHAR(30) NOT NULL,
        -- Atributos de Opciones Recalculadas
        cant_opciones_ofrecidas         INT NOT NULL DEFAULT 0,
        cant_opciones_seleccionadas     INT NOT NULL DEFAULT 0,
        precio_cotizado_seleccionado    DECIMAL(10,2) NULL,
        id_primera_opcion               INT NULL,
        primer_precio_ofrecido          DECIMAL(10,2) NULL,
        id_sede_opcion                  INT NULL,
        id_profesional_opcion           INT NULL,
        -- Atributos de Reservas Recalculadas
        id_primera_reserva              INT NULL,
        primera_fecha_reserva           DATETIME2(7) NULL,
        confirmacion_explicita_res      BIT NULL,
        fecha_confirmacion_res          DATETIME2(7) NULL,
        -- Hito de Conversión Derivado
        HitoAlcanzado                   BIT NOT NULL DEFAULT 0,
        fecha_hito_conversion           DATETIME2(7) NULL,
        -- Anomalías Cronológicas
        TieneAnomaliaCronologica        BIT NOT NULL DEFAULT 0
    );

    INSERT INTO #Stg_Solicitudes_Corte (
        id_solicitud, id_persona, id_servicio_solicitado, fecha_solicitud, estado_solicitud_norm,
        cant_opciones_ofrecidas, cant_opciones_seleccionadas, precio_cotizado_seleccionado,
        id_primera_opcion, primer_precio_ofrecido, id_sede_opcion, id_profesional_opcion,
        id_primera_reserva, primera_fecha_reserva, confirmacion_explicita_res, fecha_confirmacion_res,
        HitoAlcanzado, fecha_hito_conversion, TieneAnomaliaCronologica
    )
    SELECT 
        s.id_solicitud,
        s.id_persona,
        s.id_servicio_solicitado,
        s.fecha_solicitud,
        s.estado_solicitud_norm,
        -- Opciones recalculadas desde registros individuales filtrados antes del corte
        -- Nota de origen: 'fecha_ofrecida' filtra cronológicamente las ofertas anteriores al corte; 'seleccionada'
        -- es un atributo mutable en OLTP sin timestamp histórico de selección. No se afirma reconstrucción histórica del estado seleccionada.
        ISNULL(opc_agg.cant_opciones_ofrecidas, 0),
        ISNULL(opc_agg.cant_opciones_seleccionadas, 0),
        opc_agg.precio_cotizado_seleccionado,
        opc_prim.id_primera_opcion,
        opc_prim.primer_precio_ofrecido,
        opc_prim.id_sede_opcion,
        opc_prim.id_profesional_opcion,
        -- Reservas recalculadas desde registros individuales filtrados antes del corte
        res_prim.id_primera_reserva,
        res_prim.primera_fecha_reserva,
        res_prim.confirmacion_explicita_res,
        res_prim.fecha_confirmacion_res,
        -- Hito de conversión según configuración explícita (sin fallbacks no contractuales)
        CASE 
            WHEN @ConfigHitoConversion = 'CreacionReserva' AND res_prim.primera_fecha_reserva IS NOT NULL THEN 1
            WHEN @ConfigHitoConversion = 'ConfirmacionReserva' AND res_conf.fecha_confirmacion IS NOT NULL THEN 1
            ELSE 0
        END AS HitoAlcanzado,
        CASE 
            WHEN @ConfigHitoConversion = 'CreacionReserva' THEN res_prim.primera_fecha_reserva
            WHEN @ConfigHitoConversion = 'ConfirmacionReserva' THEN res_conf.fecha_confirmacion
            ELSE NULL
        END AS fecha_hito_conversion,
        -- Anomalía cronológica: primera reserva anterior a la solicitud
        CASE 
            WHEN res_prim.primera_fecha_reserva IS NOT NULL AND res_prim.primera_fecha_reserva < s.fecha_solicitud THEN 1
            ELSE 0
        END AS TieneAnomaliaCronologica
    FROM staging.stg_Solicitudes s
    OUTER APPLY (
        SELECT 
            COUNT(*) AS cant_opciones_ofrecidas,
            SUM(CASE WHEN o.seleccionada = 1 THEN 1 ELSE 0 END) AS cant_opciones_seleccionadas,
            CASE 
                WHEN SUM(CASE WHEN o.seleccionada = 1 THEN 1 ELSE 0 END) = 1 
                THEN MAX(CASE WHEN o.seleccionada = 1 THEN o.precio_ofrecido END)
                ELSE NULL 
            END AS precio_cotizado_seleccionado
        FROM #OLTP_Opciones o
        WHERE o.id_solicitud = s.id_solicitud
    ) opc_agg
    OUTER APPLY (
        SELECT TOP 1
            o.id_opcion AS id_primera_opcion,
            o.precio_ofrecido AS primer_precio_ofrecido,
            disp.id_sede AS id_sede_opcion,
            disp.id_profesional AS id_profesional_opcion
        FROM #OLTP_Opciones o
        LEFT JOIN #OLTP_Disponibilidad disp ON o.id_disponibilidad = disp.id_disponibilidad
        WHERE o.id_solicitud = s.id_solicitud
        ORDER BY o.fecha_ofrecida ASC, o.id_opcion ASC
    ) opc_prim
    OUTER APPLY (
        -- Primera reserva cronológica creada antes del corte
        SELECT TOP 1
            r.id_reserva AS id_primera_reserva,
            r.fecha_reserva AS primera_fecha_reserva,
            r.confirmacion_explicita AS confirmacion_explicita_res,
            r.fecha_confirmacion AS fecha_confirmacion_res
        FROM #OLTP_Reservas r
        WHERE r.id_solicitud = s.id_solicitud
          AND r.fecha_reserva >= s.fecha_solicitud
          AND r.fecha_reserva < @InstanteEvaluacion
        ORDER BY r.fecha_reserva ASC, r.id_reserva ASC
    ) res_prim
    OUTER APPLY (
        -- Primera confirmación cronológica válida entre todas las reservas de la solicitud
        SELECT TOP 1
            r.id_reserva AS id_reserva_confirmada,
            r.fecha_confirmacion
        FROM #OLTP_Reservas r
        WHERE r.id_solicitud = s.id_solicitud
          AND r.confirmacion_explicita = 1
          AND r.fecha_reserva >= s.fecha_solicitud
          AND r.fecha_confirmacion IS NOT NULL
          AND r.fecha_confirmacion >= r.fecha_reserva
          AND r.fecha_confirmacion < @InstanteEvaluacion
        ORDER BY r.fecha_confirmacion ASC, r.id_reserva ASC
    ) res_conf
    WHERE s.fecha_solicitud < @InstanteEvaluacion;

    -- ------------------------------------------------------------------------------------------------
    -- PASO 4: ALGORITMO GLOBAL DE ATRIBUCIÓN DE INTERACCIONES Y CONTROL DE AMBIGÜEDAD
    -- ------------------------------------------------------------------------------------------------
    CREATE TABLE #SolicitudesAtribucion (
        id_solicitud                INT NOT NULL PRIMARY KEY,
        id_persona                  INT NOT NULL,
        fecha_solicitud             DATETIME2(7) NOT NULL,
        id_interaccion_atribuida    INT NULL,
        fecha_primera_respuesta     DATETIME2(7) NULL,
        id_usuario_operador         INT NULL,
        AtribucionAmbigua           BIT NOT NULL DEFAULT 0,
        AtribucionHeuristica        BIT NOT NULL DEFAULT 0
    );

    INSERT INTO #SolicitudesAtribucion (id_solicitud, id_persona, fecha_solicitud)
    SELECT id_solicitud, id_persona, fecha_solicitud
    FROM #Stg_Solicitudes_Corte;

    CREATE TABLE #InteraccionesUtiles (
        SecId                       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        id_interaccion              INT NOT NULL,
        id_persona                  INT NOT NULL,
        fecha_hora_interaccion      DATETIME2(7) NOT NULL,
        id_usuario_operador         INT NULL,
        Consumida                   BIT NOT NULL DEFAULT 0
    );

    INSERT INTO #InteraccionesUtiles (id_interaccion, id_persona, fecha_hora_interaccion, id_usuario_operador)
    SELECT i.id_interaccion, i.id_persona, i.fecha_hora_interaccion, i.id_usuario_operador
    FROM staging.stg_Interacciones i
    WHERE i.es_respuesta_util = 1
      AND i.fecha_hora_interaccion < @InstanteEvaluacion
      AND i.id_persona IN (SELECT DISTINCT id_persona FROM #SolicitudesAtribucion)
    ORDER BY i.id_persona, i.fecha_hora_interaccion ASC, i.id_interaccion ASC;

    -- Cursor local para procesamiento cronológico de interacciones útiles
    DECLARE @cur_SecId INT, @cur_id_interaccion INT, @cur_id_persona INT, @cur_fecha_interaccion DATETIME2(7), @cur_id_usuario INT;

    DECLARE cur_interacciones CURSOR LOCAL FAST_FORWARD FOR
        SELECT SecId, id_interaccion, id_persona, fecha_hora_interaccion, id_usuario_operador
        FROM #InteraccionesUtiles
        ORDER BY id_persona, fecha_hora_interaccion ASC, id_interaccion ASC;

    OPEN cur_interacciones;
    FETCH NEXT FROM cur_interacciones INTO @cur_SecId, @cur_id_interaccion, @cur_id_persona, @cur_fecha_interaccion, @cur_id_usuario;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @CantCandidatas INT = 0;

        SELECT @CantCandidatas = COUNT(*)
        FROM #SolicitudesAtribucion
        WHERE id_persona = @cur_id_persona
          AND id_interaccion_atribuida IS NULL
          AND fecha_solicitud <= @cur_fecha_interaccion;

        IF @CantCandidatas = 1
        BEGIN
            -- Exactamente una solicitud candidata: atribución directa
            UPDATE #SolicitudesAtribucion
            SET id_interaccion_atribuida = @cur_id_interaccion,
                fecha_primera_respuesta = @cur_fecha_interaccion,
                id_usuario_operador = @cur_id_usuario,
                AtribucionHeuristica = 1
            WHERE id_persona = @cur_id_persona
              AND id_interaccion_atribuida IS NULL
              AND fecha_solicitud <= @cur_fecha_interaccion;

            UPDATE #InteraccionesUtiles SET Consumida = 1 WHERE SecId = @cur_SecId;
        END
        ELSE IF @CantCandidatas >= 2
        BEGIN
            -- Ventanas concurrentes: marcar AtribucionAmbigua = 1 en TODAS las candidatas de forma irreversible
            UPDATE #SolicitudesAtribucion
            SET AtribucionAmbigua = 1
            WHERE id_persona = @cur_id_persona
              AND id_interaccion_atribuida IS NULL
              AND fecha_solicitud <= @cur_fecha_interaccion;

            -- Desempate técnico para agotar el mensaje asignándolo a la más antigua
            DECLARE @id_solicitud_ganadora INT = NULL;
            SELECT TOP 1 @id_solicitud_ganadora = id_solicitud
            FROM #SolicitudesAtribucion
            WHERE id_persona = @cur_id_persona
              AND id_interaccion_atribuida IS NULL
              AND fecha_solicitud <= @cur_fecha_interaccion
            ORDER BY fecha_solicitud ASC, id_solicitud ASC;

            UPDATE #SolicitudesAtribucion
            SET id_interaccion_atribuida = @cur_id_interaccion,
                fecha_primera_respuesta = @cur_fecha_interaccion,
                id_usuario_operador = @cur_id_usuario,
                AtribucionHeuristica = 1
            WHERE id_solicitud = @id_solicitud_ganadora;

            UPDATE #InteraccionesUtiles SET Consumida = 1 WHERE SecId = @cur_SecId;
        END

        FETCH NEXT FROM cur_interacciones INTO @cur_SecId, @cur_id_interaccion, @cur_id_persona, @cur_fecha_interaccion, @cur_id_usuario;
    END;

    CLOSE cur_interacciones;
    DEALLOCATE cur_interacciones;

    -- ------------------------------------------------------------------------------------------------
    -- PASO 5: CONSOLIDACIÓN DE MEDIDAS Y RESOLUCIÓN DIMENSIONAL EN TABLA INTERMEDIA
    -- ------------------------------------------------------------------------------------------------
    CREATE TABLE #Stg_Lead_Intermedio (
        id_solicitud_origen         INT NOT NULL PRIMARY KEY,
        id_persona_origen           INT NOT NULL,
        KeyTiempoSolicitud          INT NOT NULL,
        KeyTiempoReserva            INT NOT NULL,
        KeySede                     INT NOT NULL,
        KeyServicio                 INT NOT NULL,
        KeyProfesional              INT NOT NULL,
        KeyNegociador               INT NOT NULL,
        KeyPersona                  INT NOT NULL,
        SolicitudesRegistradas      INT NOT NULL,
        LeadsCohorteEvaluable       INT NOT NULL,
        CohorteInmadura             INT NOT NULL,
        LeadsConvertidosPayer14Dias INT NOT NULL,
        LeadsConvertidosPayerTotal  INT NOT NULL,
        LeadsAbandonados            INT NOT NULL,
        LeadsEnNegociacion          INT NOT NULL,
        LeadsResultadoFinal         INT NOT NULL,
        LeadsRequierenRespuesta     INT NOT NULL,
        LeadsRespuestaUtil15Min     INT NOT NULL,
        SegundosPrimeraRespuesta    INT NULL,
        MinutosPrimeraRespuesta     INT NULL,
        EstadoRespuestaSLA          VARCHAR(30) NOT NULL,
        AtribucionHeuristica        BIT NOT NULL,
        AtribucionAmbigua           BIT NOT NULL,
        PrecioCotizado              DECIMAL(10,2) NULL,
        BatchId                     VARCHAR(50) NOT NULL,
        -- Auditoría Interna de Validación
        EstadoValidacion            VARCHAR(30) NOT NULL DEFAULT 'Valido',
        MotivoRechazo               VARCHAR(150) NULL,
        ClasificacionAccion         VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
    );

    INSERT INTO #Stg_Lead_Intermedio (
        id_solicitud_origen, id_persona_origen, KeyTiempoSolicitud, KeyTiempoReserva,
        KeySede, KeyServicio, KeyProfesional, KeyNegociador, KeyPersona,
        SolicitudesRegistradas, LeadsCohorteEvaluable, CohorteInmadura,
        LeadsConvertidosPayer14Dias, LeadsConvertidosPayerTotal, LeadsAbandonados,
        LeadsEnNegociacion, LeadsResultadoFinal, LeadsRequierenRespuesta,
        LeadsRespuestaUtil15Min, SegundosPrimeraRespuesta, MinutosPrimeraRespuesta,
        EstadoRespuestaSLA, AtribucionHeuristica, AtribucionAmbigua, PrecioCotizado,
        BatchId, EstadoValidacion, MotivoRechazo
    )
    SELECT 
        sc.id_solicitud,
        sc.id_persona,
        -- KeyTiempoSolicitud
        ISNULL(dt_sol.KeyTiempo, 0),
        -- KeyTiempoReserva (Fecha de creación de primera reserva, o 0)
        ISNULL(dt_res.KeyTiempo, 0),
        -- KeySede (0 si no seleccionó o no hay opción)
        ISNULL(ds.KeySede, 0),
        -- KeyServicio (0 si no especificó)
        ISNULL(dserv.KeyServicio, 0),
        -- KeyProfesional (0 si no asignado)
        ISNULL(dp.KeyProfesional, 0),
        -- KeyNegociador (0 si no hay interacción atribuida)
        ISNULL(dn.KeyNegociador, 0),
        -- KeyPersona
        ISNULL(dper.KeyPersona, 0),
        -- Métricas Base y Cohorte
        1 AS SolicitudesRegistradas,
        CASE WHEN sc.fecha_solicitud <= DATEADD(DAY, -14, @InstanteEvaluacion) THEN 1 ELSE 0 END AS LeadsCohorteEvaluable,
        CASE WHEN sc.fecha_solicitud > DATEADD(DAY, -14, @InstanteEvaluacion) THEN 1 ELSE 0 END AS CohorteInmadura,
        -- Conversión a Payer 14 Días (Misma población que denominador de cohorte evaluable)
        CASE 
            WHEN sc.fecha_solicitud <= DATEADD(DAY, -14, @InstanteEvaluacion)
                 AND sc.HitoAlcanzado = 1
                 AND sc.fecha_hito_conversion <= DATEADD(DAY, 14, sc.fecha_solicitud)
            THEN 1 
            ELSE 0 
        END AS LeadsConvertidosPayer14Dias,
        sc.HitoAlcanzado AS LeadsConvertidosPayerTotal,
        CASE WHEN sc.estado_solicitud_norm = 'Abandonada' THEN 1 ELSE 0 END AS LeadsAbandonados,
        CASE WHEN sc.estado_solicitud_norm IN ('Abierta', 'En Negociacion', 'Reserva') AND sc.HitoAlcanzado = 0 THEN 1 ELSE 0 END AS LeadsEnNegociacion,
        CASE WHEN sc.HitoAlcanzado = 1 OR sc.estado_solicitud_norm IN ('Confirmada', 'Convertida', 'Abandonada', 'Cancelada', 'Descartada', 'Perdida') THEN 1 ELSE 0 END AS LeadsResultadoFinal,
        1 AS LeadsRequierenRespuesta,
        -- Medidas SLA y Segundos Hábiles
        sla.LeadsRespuestaUtil15Min,
        sla.SegundosPrimeraRespuesta,
        sla.MinutosPrimeraRespuesta,
        sla.EstadoRespuestaSLA,
        sa.AtribucionHeuristica,
        sa.AtribucionAmbigua,
        -- Precio Cotizado
        CASE 
            WHEN sc.cant_opciones_ofrecidas = 0 THEN NULL
            WHEN sc.cant_opciones_seleccionadas = 1 THEN sc.precio_cotizado_seleccionado
            WHEN sc.cant_opciones_seleccionadas = 0 AND sc.cant_opciones_ofrecidas > 0 THEN sc.primer_precio_ofrecido
            WHEN sc.cant_opciones_seleccionadas > 1 THEN NULL
            ELSE NULL
        END AS PrecioCotizado,
        @BatchId,
        -- Validación de Errores y Anomalías
        CASE 
            WHEN sc.TieneAnomaliaCronologica = 1 THEN 'Rechazada'
            WHEN sc.estado_solicitud_norm = 'Desconocido' THEN 'Rechazada'
            WHEN dt_sol.KeyTiempo IS NULL OR dt_sol_tot.c > 1 THEN 'Rechazada'
            WHEN sc.primera_fecha_reserva IS NOT NULL AND (dt_res.KeyTiempo IS NULL OR dt_res_tot.c > 1) THEN 'Rechazada'
            WHEN sc.id_sede_opcion IS NOT NULL AND ds_tot.c > 1 THEN 'Rechazada'
            WHEN sc.id_servicio_solicitado IS NOT NULL AND dserv_tot.c > 1 THEN 'Rechazada'
            WHEN sc.id_profesional_opcion IS NOT NULL AND dp_tot.c > 1 THEN 'Rechazada'
            WHEN sa.id_usuario_operador IS NOT NULL AND dn_tot.c > 1 THEN 'Rechazada'
            WHEN dper_tot.c > 1 THEN 'Rechazada'
            ELSE 'Valido'
        END AS EstadoValidacion,
        CASE 
            WHEN sc.TieneAnomaliaCronologica = 1 THEN 'AnomaliaCronologica: Fecha de reserva anterior a fecha de solicitud'
            WHEN sc.estado_solicitud_norm = 'Desconocido' THEN 'EstadoComercialDesconocido: Solicitud con estado no catalogado'
            WHEN dt_sol.KeyTiempo IS NULL OR dt_sol_tot.c > 1 THEN 'ErrorLookupAmbiguo: Dim_Tiempo fecha_solicitud'
            WHEN sc.primera_fecha_reserva IS NOT NULL AND (dt_res.KeyTiempo IS NULL OR dt_res_tot.c > 1) THEN 'ErrorLookupAmbiguo: Dim_Tiempo primera_fecha_reserva'
            WHEN sc.id_sede_opcion IS NOT NULL AND ds_tot.c > 1 THEN 'ErrorLookupAmbiguo: Dim_Sede id_sede'
            WHEN sc.id_servicio_solicitado IS NOT NULL AND dserv_tot.c > 1 THEN 'ErrorLookupAmbiguo: Dim_Servicio id_servicio'
            WHEN sc.id_profesional_opcion IS NOT NULL AND dp_tot.c > 1 THEN 'ErrorLookupAmbiguo: Dim_Profesional id_profesional'
            WHEN sa.id_usuario_operador IS NOT NULL AND dn_tot.c > 1 THEN 'ErrorLookupAmbiguo: Dim_Negociador id_usuario'
            WHEN dper_tot.c > 1 THEN 'ErrorLookupAmbiguo: Dim_Persona id_persona'
            ELSE NULL
        END AS MotivoRechazo
    FROM #Stg_Solicitudes_Corte sc
    JOIN #SolicitudesAtribucion sa ON sc.id_solicitud = sa.id_solicitud
    -- Cálculo de SLA según reglas de precedencia de ambigüedad
    CROSS APPLY (
        SELECT 
            dbo.fn_CalcularSegundosHabiles(sc.fecha_solicitud, sa.fecha_primera_respuesta) AS SegHabilesResp,
            dbo.fn_CalcularSegundosHabiles(sc.fecha_solicitud, @InstanteEvaluacion) AS SegHabilesEval
    ) calc
    CROSS APPLY (
        SELECT 
            CASE 
                -- Precedencia estricta de ambigüedad: EvidenciaInsuficiente y segundos NULL
                WHEN sa.AtribucionAmbigua = 1 THEN 'EvidenciaInsuficiente'
                WHEN sa.id_interaccion_atribuida IS NOT NULL THEN 
                    CASE 
                        -- Cuando la función devuelve NULL (fuera de capacidad, overflow o sin calendario), prevalece EvidenciaInsuficiente
                        WHEN calc.SegHabilesResp IS NULL THEN 'EvidenciaInsuficiente'
                        WHEN calc.SegHabilesResp <= 900 THEN 'Acreditada'
                        ELSE 'Incumplida'
                    END
                ELSE 
                    -- Sin respuesta atribuida: verificar si la ventana hábil de 15 min aún no expiró
                    CASE 
                        WHEN calc.SegHabilesEval IS NULL THEN 'EvidenciaInsuficiente'
                        WHEN calc.SegHabilesEval <= 900 THEN 'PendienteDentroSLA'
                        ELSE 'EvidenciaInsuficiente'
                    END
            END AS EstadoRespuestaSLA,
            CASE 
                WHEN sa.AtribucionAmbigua = 1 THEN 0
                WHEN sa.id_interaccion_atribuida IS NOT NULL AND calc.SegHabilesResp IS NOT NULL AND calc.SegHabilesResp <= 900 THEN 1
                ELSE 0
            END AS LeadsRespuestaUtil15Min,
            CASE 
                WHEN sa.AtribucionAmbigua = 1 THEN NULL
                WHEN sa.id_interaccion_atribuida IS NOT NULL THEN calc.SegHabilesResp
                ELSE NULL
            END AS SegundosPrimeraRespuesta,
            CASE 
                WHEN sa.AtribucionAmbigua = 1 THEN NULL
                WHEN sa.id_interaccion_atribuida IS NOT NULL AND calc.SegHabilesResp IS NOT NULL 
                THEN CAST(CEILING(calc.SegHabilesResp / 60.0) AS INT)
                ELSE NULL
            END AS MinutosPrimeraRespuesta
    ) sla
    -- Lookups Dimensionales con Detección de Multiplicidad (>1 Coincidencias)
    OUTER APPLY (
        SELECT TOP 1 dt.KeyTiempo FROM dbo.Dim_Tiempo dt WHERE dt.id_fecha = CAST(sc.fecha_solicitud AS DATE)
    ) dt_sol
    OUTER APPLY (
        SELECT COUNT(*) AS c FROM dbo.Dim_Tiempo dt WHERE dt.id_fecha = CAST(sc.fecha_solicitud AS DATE)
    ) dt_sol_tot
    OUTER APPLY (
        SELECT TOP 1 dt.KeyTiempo FROM dbo.Dim_Tiempo dt WHERE dt.id_fecha = CAST(sc.primera_fecha_reserva AS DATE)
    ) dt_res
    OUTER APPLY (
        SELECT COUNT(*) AS c FROM dbo.Dim_Tiempo dt WHERE dt.id_fecha = CAST(sc.primera_fecha_reserva AS DATE)
    ) dt_res_tot
    OUTER APPLY (
        SELECT TOP 1 ds.KeySede FROM dbo.Dim_Sede ds WHERE ds.id_sede = sc.id_sede_opcion
    ) ds
    OUTER APPLY (
        SELECT COUNT(*) AS c FROM dbo.Dim_Sede ds WHERE ds.id_sede = sc.id_sede_opcion
    ) ds_tot
    OUTER APPLY (
        SELECT TOP 1 dserv.KeyServicio FROM dbo.Dim_Servicio dserv WHERE dserv.id_servicio = sc.id_servicio_solicitado
    ) dserv
    OUTER APPLY (
        SELECT COUNT(*) AS c FROM dbo.Dim_Servicio dserv WHERE dserv.id_servicio = sc.id_servicio_solicitado
    ) dserv_tot
    OUTER APPLY (
        SELECT TOP 1 dp.KeyProfesional FROM dbo.Dim_Profesional dp WHERE dp.id_profesional = sc.id_profesional_opcion
    ) dp
    OUTER APPLY (
        SELECT COUNT(*) AS c FROM dbo.Dim_Profesional dp WHERE dp.id_profesional = sc.id_profesional_opcion
    ) dp_tot
    OUTER APPLY (
        SELECT TOP 1 dn.KeyNegociador FROM dbo.Dim_Negociador dn WHERE dn.id_usuario = sa.id_usuario_operador
    ) dn
    OUTER APPLY (
        SELECT COUNT(*) AS c FROM dbo.Dim_Negociador dn WHERE dn.id_usuario = sa.id_usuario_operador
    ) dn_tot
    OUTER APPLY (
        SELECT TOP 1 dper.KeyPersona FROM dbo.Dim_Persona dper WHERE dper.id_persona = sc.id_persona
    ) dper
    OUTER APPLY (
        SELECT COUNT(*) AS c FROM dbo.Dim_Persona dper WHERE dper.id_persona = sc.id_persona
    ) dper_tot;

    -- Diagnóstico controlado ante intervalos que excedan la capacidad del cálculo o del INT contractual
    -- Nota: Los segundos naturales transcurridos no equivalen a segundos hábiles acumulados
    IF EXISTS (
        SELECT 1 
        FROM #Stg_Solicitudes_Corte sc
        JOIN #SolicitudesAtribucion sa ON sc.id_solicitud = sa.id_solicitud
        WHERE (sa.id_interaccion_atribuida IS NOT NULL 
               AND sc.fecha_solicitud <= sa.fecha_primera_respuesta 
               AND dbo.fn_CalcularSegundosHabiles(sc.fecha_solicitud, sa.fecha_primera_respuesta) IS NULL)
           OR (sa.id_interaccion_atribuida IS NULL 
               AND sc.fecha_solicitud <= @InstanteEvaluacion 
               AND dbo.fn_CalcularSegundosHabiles(sc.fecha_solicitud, @InstanteEvaluacion) IS NULL)
    )
    BEGIN
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError)
        VALUES (@ProcName, @BatchId, 'ADVERTENCIA', 'Diagnóstico Controlado: Se detectaron intervalos temporales que exceden la capacidad del cálculo hábil (>65,535 días) o del tipo INT contractual. Los segundos naturales transcurridos no equivalen a segundos hábiles acumulados; se clasifica en EvidenciaInsuficiente con duración NULL sin truncamiento ni saturación artificial.', 0);
    END;

    -- ------------------------------------------------------------------------------------------------
    -- PASO 6: PROTECCIÓN TRANSACCIONAL DE CONCURRENCIA Y CLASIFICACIÓN DISJUNTA
    -- ------------------------------------------------------------------------------------------------
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Adquisición de bloqueo exclusivo de aplicación para LEAD
        EXEC @ResLock = sp_getapplock 
            @Resource    = @LockResource,
            @LockMode    = 'Exclusive',
            @LockOwner   = 'Transaction',
            @LockTimeout = 30000;

        IF @ResLock < 0
        BEGIN
            RAISERROR('No se pudo adquirir el bloqueo exclusivo de aplicación [ETL_Lock_Fact_NegociacionLead] (código retorno %d).', 16, 1, @ResLock);
        END;

        -- Clasificación disjunta bajo bloqueo exclusivo
        UPDATE src
        SET ClasificacionAccion = 
            CASE 
                WHEN src.EstadoValidacion = 'Rechazada' THEN 'Rechazada'
                WHEN dest.id_solicitud_origen IS NULL THEN 'Insertar'
                WHEN dest.id_persona_origen <> src.id_persona_origen
                  OR dest.KeyTiempoSolicitud <> src.KeyTiempoSolicitud
                  OR dest.KeyTiempoReserva <> src.KeyTiempoReserva
                  OR dest.KeySede <> src.KeySede
                  OR dest.KeyServicio <> src.KeyServicio
                  OR dest.KeyProfesional <> src.KeyProfesional
                  OR dest.KeyNegociador <> src.KeyNegociador
                  OR dest.KeyPersona <> src.KeyPersona
                  OR dest.LeadsCohorteEvaluable <> src.LeadsCohorteEvaluable
                  OR dest.CohorteInmadura <> src.CohorteInmadura
                  OR dest.LeadsConvertidosPayer14Dias <> src.LeadsConvertidosPayer14Dias
                  OR dest.LeadsConvertidosPayerTotal <> src.LeadsConvertidosPayerTotal
                  OR dest.LeadsAbandonados <> src.LeadsAbandonados
                  OR dest.LeadsEnNegociacion <> src.LeadsEnNegociacion
                  OR dest.LeadsResultadoFinal <> src.LeadsResultadoFinal
                  OR dest.LeadsRespuestaUtil15Min <> src.LeadsRespuestaUtil15Min
                  OR ISNULL(dest.SegundosPrimeraRespuesta, -1) <> ISNULL(src.SegundosPrimeraRespuesta, -1)
                  OR ISNULL(dest.MinutosPrimeraRespuesta, -1) <> ISNULL(src.MinutosPrimeraRespuesta, -1)
                  OR dest.EstadoRespuestaSLA <> src.EstadoRespuestaSLA
                  OR dest.AtribucionHeuristica <> src.AtribucionHeuristica
                  OR dest.AtribucionAmbigua <> src.AtribucionAmbigua
                  OR ISNULL(dest.PrecioCotizado, -1.0) <> ISNULL(src.PrecioCotizado, -1.0)
                THEN 'Actualizar'
                ELSE 'SinCambio'
            END
        FROM #Stg_Lead_Intermedio src
        LEFT JOIN dbo.Fact_NegociacionLead dest WITH (UPDLOCK, HOLDLOCK)
          ON dest.id_solicitud_origen = src.id_solicitud_origen;

        -- Derivación directa y disjunta de contadores
        SELECT 
            @Insertados   = ISNULL(SUM(CASE WHEN ClasificacionAccion = 'Insertar' THEN 1 ELSE 0 END), 0),
            @Actualizados = ISNULL(SUM(CASE WHEN ClasificacionAccion = 'Actualizar' THEN 1 ELSE 0 END), 0),
            @SinCambio    = ISNULL(SUM(CASE WHEN ClasificacionAccion = 'SinCambio' THEN 1 ELSE 0 END), 0),
            @Rechazados   = ISNULL(SUM(CASE WHEN ClasificacionAccion = 'Rechazada' THEN 1 ELSE 0 END), 0),
            @Pendientes   = 0
        FROM #Stg_Lead_Intermedio;

        -- --------------------------------------------------------------------------------------------
        -- PASO 7: PERSISTENCIA FÍSICA EN DESTINO
        -- --------------------------------------------------------------------------------------------
        
        -- 7.1 Actualización in-place de diferencias
        UPDATE dest
        SET 
            dest.id_persona_origen           = src.id_persona_origen,
            dest.KeyTiempoSolicitud          = src.KeyTiempoSolicitud,
            dest.KeyTiempoReserva            = src.KeyTiempoReserva,
            dest.KeySede                     = src.KeySede,
            dest.KeyServicio                 = src.KeyServicio,
            dest.KeyProfesional              = src.KeyProfesional,
            dest.KeyNegociador               = src.KeyNegociador,
            dest.KeyPersona                  = src.KeyPersona,
            dest.SolicitudesRegistradas      = src.SolicitudesRegistradas,
            dest.LeadsCohorteEvaluable       = src.LeadsCohorteEvaluable,
            dest.CohorteInmadura             = src.CohorteInmadura,
            dest.LeadsConvertidosPayer14Dias = src.LeadsConvertidosPayer14Dias,
            dest.LeadsConvertidosPayerTotal  = src.LeadsConvertidosPayerTotal,
            dest.LeadsAbandonados            = src.LeadsAbandonados,
            dest.LeadsEnNegociacion          = src.LeadsEnNegociacion,
            dest.LeadsResultadoFinal         = src.LeadsResultadoFinal,
            dest.LeadsRequierenRespuesta     = src.LeadsRequierenRespuesta,
            dest.LeadsRespuestaUtil15Min     = src.LeadsRespuestaUtil15Min,
            dest.SegundosPrimeraRespuesta    = src.SegundosPrimeraRespuesta,
            dest.MinutosPrimeraRespuesta     = src.MinutosPrimeraRespuesta,
            dest.EstadoRespuestaSLA          = src.EstadoRespuestaSLA,
            dest.AtribucionHeuristica        = src.AtribucionHeuristica,
            dest.AtribucionAmbigua           = src.AtribucionAmbigua,
            dest.PrecioCotizado              = src.PrecioCotizado,
            dest.BatchId                     = src.BatchId,
            dest.FechaCarga                  = SYSDATETIME(),
            dest.UsuarioCarga                = SYSTEM_USER
        FROM dbo.Fact_NegociacionLead dest
        JOIN #Stg_Lead_Intermedio src ON dest.id_solicitud_origen = src.id_solicitud_origen
        WHERE src.ClasificacionAccion = 'Actualizar';

        -- 7.2 Inserción de nuevas solicitudes
        INSERT INTO dbo.Fact_NegociacionLead (
            id_solicitud_origen, id_persona_origen, KeyTiempoSolicitud, KeyTiempoReserva,
            KeySede, KeyServicio, KeyProfesional, KeyNegociador, KeyPersona,
            SolicitudesRegistradas, LeadsCohorteEvaluable, CohorteInmadura,
            LeadsConvertidosPayer14Dias, LeadsConvertidosPayerTotal, LeadsAbandonados,
            LeadsEnNegociacion, LeadsResultadoFinal, LeadsRequierenRespuesta,
            LeadsRespuestaUtil15Min, SegundosPrimeraRespuesta, MinutosPrimeraRespuesta,
            EstadoRespuestaSLA, AtribucionHeuristica, AtribucionAmbigua, PrecioCotizado,
            BatchId, FechaCarga, UsuarioCarga
        )
        SELECT 
            src.id_solicitud_origen, src.id_persona_origen, src.KeyTiempoSolicitud, src.KeyTiempoReserva,
            src.KeySede, src.KeyServicio, src.KeyProfesional, src.KeyNegociador, src.KeyPersona,
            src.SolicitudesRegistradas, src.LeadsCohorteEvaluable, src.CohorteInmadura,
            src.LeadsConvertidosPayer14Dias, src.LeadsConvertidosPayerTotal, src.LeadsAbandonados,
            src.LeadsEnNegociacion, src.LeadsResultadoFinal, src.LeadsRequierenRespuesta,
            src.LeadsRespuestaUtil15Min, src.SegundosPrimeraRespuesta, src.MinutosPrimeraRespuesta,
            src.EstadoRespuestaSLA, src.AtribucionHeuristica, src.AtribucionAmbigua, src.PrecioCotizado,
            src.BatchId, SYSDATETIME(), SYSTEM_USER
        FROM #Stg_Lead_Intermedio src
        WHERE src.ClasificacionAccion = 'Insertar';

        -- 7.3 Registro de solicitudes rechazadas en la tabla de excepciones
        INSERT INTO dbo.Rechazos_ETL_Lead (
            id_solicitud_origen, MotivoRechazo, DetalleRechazo, BatchId, FechaRechazo
        )
        SELECT 
            src.id_solicitud_origen,
            src.MotivoRechazo,
            CONCAT('Solicitud rechazada: id_persona=', src.id_persona_origen, ', Motivo=', src.MotivoRechazo),
            src.BatchId,
            SYSDATETIME()
        FROM #Stg_Lead_Intermedio src
        WHERE src.ClasificacionAccion = 'Rechazada';

        -- Confirmación atómica de la transacción
        COMMIT TRANSACTION;

        -- Registrar éxito en bitácora
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError)
        VALUES (@ProcName, @BatchId, 'EXITO', 
            CONCAT('Carga LEAD finalizada exitosamente: Insertados=', @Insertados, 
                   ', Actualizados=', @Actualizados, ', SinCambio=', @SinCambio, 
                   ', Rechazados=', @Rechazados, ', Pendientes=', @Pendientes), 0);

        RETURN 0;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- En caso de fallo o rollback, los contadores confirmados son estrictamente 0
        SET @Insertados = 0;
        SET @Actualizados = 0;
        SET @SinCambio = 0;
        SET @Rechazados = 0;
        SET @Pendientes = 0;

        DECLARE @ErrorMsg VARCHAR(2048) = ERROR_MESSAGE();
        DECLARE @ErrorLine INT = ERROR_LINE();

        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError)
        VALUES (@ProcName, @BatchId, 'ERROR', CONCAT('Excepción en carga LEAD: ', @ErrorMsg), @ErrorLine);

        RAISERROR(@ErrorMsg, 16, 1);
        RETURN -1;
    END CATCH;
END;
GO

PRINT '>> Procedimiento almacenado [dbo].[usp_Cargar_Fact_NegociacionLead] creado exitosamente.';
GO

-- ====================================================================================================
-- LOTE 5: FINALIZACIÓN Y RESTABLECIMIENTO DE NOEXEC
-- ====================================================================================================
SET NOEXEC OFF;
GO
PRINT '>> Despliegue de [Entregables/16. ETL_Fact_NegociacionLead_h3.sql] finalizado exitosamente.';
GO
