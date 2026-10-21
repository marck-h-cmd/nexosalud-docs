-- ====================================================================================================
-- NEXOSALUD — IMPLEMENTACIÓN DEL ETL DE HECHOS: BUYER (H3 - FASE 2)
-- ====================================================================================================
-- Proyecto: NexoSalud (Plataforma de Inteligencia de Negocios Odontológica — Clínica Luxedent, Trujillo)
-- Metodología: IMPULSE (Fase: BUYER — Fact_CaptacionBuyer)
-- Titular del Rol: Mario Antonio Martinez Dominguez (Integrante 3 — ETL BUYER y LEAD, Embudo y Calidad)
-- Responsable de Ejecución Técnica: Jesús Daniel Ordóñez Ugarte (Integrante 4 — asumiendo la ejecución técnica
--   de BUYER/LEAD según el intercambio de responsabilidades comunicado entre integrantes)
-- Ubicación del Entregable: Entregables/15. ETL_Fact_CaptacionBuyer_h3.sql
-- Guía de Despliegue y Pruebas: Entregables/15. Guia_ETL_Buyer_h3.md
-- Script de Pruebas Automatizadas: Entregables/15. Pruebas_ETL_Buyer_h3.sql
-- Documento Contractual Base: Entregables/12. Contrato_y_dependencias_h3_mario.md
-- Especificación de Diseño Técnico: Entregables/14. Diseno_ETL_hechos_buyer_lead_h3.md (Sección 5.2)
-- Capa de Extracción: Entregables/13. Staging_buyer_lead_h3.sql (staging.stg_Personas, staging.stg_Solicitudes)
-- Modelo Dimensional de Destino: Entregables/8. DDL_modelo_dimensional_mart_h2.sql y Entregables/9. Poblacion_dimensiones_conformadas_h2.sql
--
-- CONTRATO DE EJECUCIÓN REPRODUCIBLE (SQLCMD / HERRAMIENTAS CLIENTE):
--   1. Este script está diseñado para ejecutarse en el contexto de la base de datos destino activa (sin sentencias USE).
--   2. En SQLCMD, ejecute con el parámetro -b (detener ejecución por lotes ante errores de gravedad >= 11):
--        sqlcmd -S localhost -E -d NexoSalud_Mart -b -i "Entregables\15. ETL_Fact_CaptacionBuyer_h3.sql"
--   3. Ante cualquier fallo en la prevalidación defensiva, el script emite un error detallado y activa SET NOEXEC ON,
--      impidiendo la ejecución de todos los lotes posteriores (CREATE TABLE / CREATE PROCEDURE) sin depender de RETURN.
--   4. Si Fact_CaptacionBuyer o las tablas auxiliares ya existen con estructura incompatible, el script
--      aborta sin alterar ni destruir los objetos preexistentes.
-- ====================================================================================================

-- ====================================================================================================
-- LOTE 1: PREVALIDACIÓN DEFENSIVA DE DIMENSIONES, TIPOS, CLAVES Y MIEMBROS DESCONOCIDOS
-- ====================================================================================================

DECLARE @ErroresPreval VARCHAR(MAX) = '';

-- ----------------------------------------------------------------------------------------------------
-- 1.1 Validación de Dim_Tiempo
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Tiempo.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    -- Validar columna KeyTiempo (INT, NOT NULL)
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Tiempo') AND c.name = 'KeyTiempo' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Tiempo.KeyTiempo debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        -- Validar unicidad individual real de KeyTiempo (PK o UNIQUE, habilitada, sin filtro y con KeyTiempo como única columna clave)
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

    -- Validar columna id_fecha (DATE, NOT NULL)
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Tiempo') AND c.name = 'id_fecha' AND t.name = 'date' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Tiempo.id_fecha debe ser DATE NOT NULL.' + CHAR(13) + CHAR(10);

    -- Comprobar miembro desconocido (KeyTiempo = 0) mediante consulta dinámica segura
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Tiempo') AND name = 'KeyTiempo')
    BEGIN
        DECLARE @hasMem0_Tiempo INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Tiempo WHERE KeyTiempo = 0', N'@c INT OUTPUT', @c = @hasMem0_Tiempo OUTPUT;
        IF @hasMem0_Tiempo = 0
            SET @ErroresPreval += '- dbo.Dim_Tiempo no contiene el miembro desconocido verificado (KeyTiempo = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.2 Validación de Dim_Canal
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Canal', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Canal.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Canal') AND c.name = 'KeyCanal' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Canal.KeyCanal debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Canal')
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
                    AND c.name = 'KeyCanal'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Canal.KeyCanal debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Canal') AND c.name = 'id_canal' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Canal.id_canal debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Canal') AND name = 'KeyCanal')
    BEGIN
        DECLARE @hasMem0_Canal INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Canal WHERE KeyCanal = 0', N'@c INT OUTPUT', @c = @hasMem0_Canal OUTPUT;
        IF @hasMem0_Canal = 0
            SET @ErroresPreval += '- dbo.Dim_Canal no contiene el miembro desconocido verificado (KeyCanal = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.3 Validación de Dim_Fuente
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Fuente', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Fuente.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Fuente') AND c.name = 'KeyFuente' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Fuente.KeyFuente debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Fuente')
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
                    AND c.name = 'KeyFuente'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Fuente.KeyFuente debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Fuente') AND c.name = 'id_campana' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Fuente.id_campana debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Fuente') AND name = 'KeyFuente')
    BEGIN
        DECLARE @hasMem0_Fuente INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Fuente WHERE KeyFuente = 0', N'@c INT OUTPUT', @c = @hasMem0_Fuente OUTPUT;
        IF @hasMem0_Fuente = 0
            SET @ErroresPreval += '- dbo.Dim_Fuente no contiene el miembro desconocido verificado (KeyFuente = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.4 Validación de Dim_Sede
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

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Sede') AND name = 'KeySede')
    BEGIN
        DECLARE @hasMem0_Sede INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Sede WHERE KeySede = 0', N'@c INT OUTPUT', @c = @hasMem0_Sede OUTPUT;
        IF @hasMem0_Sede = 0
            SET @ErroresPreval += '- dbo.Dim_Sede no contiene el miembro desconocido verificado (KeySede = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.5 Validación de Dim_EstadoRegistro
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_EstadoRegistro', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_EstadoRegistro.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_EstadoRegistro') AND c.name = 'KeyEstadoRegistro' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_EstadoRegistro.KeyEstadoRegistro debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_EstadoRegistro')
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
                    AND c.name = 'KeyEstadoRegistro'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_EstadoRegistro.KeyEstadoRegistro debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_EstadoRegistro') AND c.name = 'EstadoCalidad' AND t.name IN ('varchar', 'nvarchar') AND c.max_length >= 50
    )
        SET @ErroresPreval += '- dbo.Dim_EstadoRegistro.EstadoCalidad debe ser VARCHAR(>=50).' + CHAR(13) + CHAR(10);

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_EstadoRegistro') AND c.name = 'AutorizacionContacto' AND t.name IN ('varchar', 'nvarchar') AND c.max_length >= 2
    )
        SET @ErroresPreval += '- dbo.Dim_EstadoRegistro.AutorizacionContacto debe ser VARCHAR(>=2).' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_EstadoRegistro') AND name = 'KeyEstadoRegistro')
    BEGIN
        DECLARE @hasMem0_EstadoReg INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_EstadoRegistro WHERE KeyEstadoRegistro = 0', N'@c INT OUTPUT', @c = @hasMem0_EstadoReg OUTPUT;
        IF @hasMem0_EstadoReg = 0
            SET @ErroresPreval += '- dbo.Dim_EstadoRegistro no contiene el miembro desconocido verificado (KeyEstadoRegistro = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.6 Validación de Dim_Persona (Brecha H2 Bloqueante)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Persona', 'U') IS NULL
    SET @ErroresPreval += '- Brecha H2: Falta tabla requerida dbo.Dim_Persona (bloqueante contractual).' + CHAR(13) + CHAR(10);
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

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Persona') AND c.name = 'id_persona' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Persona.id_persona debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Persona') AND name = 'KeyPersona')
    BEGIN
        DECLARE @hasMem0_Persona INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Persona WHERE KeyPersona = 0', N'@c INT OUTPUT', @c = @hasMem0_Persona OUTPUT;
        IF @hasMem0_Persona = 0
            SET @ErroresPreval += '- dbo.Dim_Persona no contiene el miembro desconocido verificado (KeyPersona = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.7 Validación de Dim_Campana (Brecha H2 Bloqueante)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Campana', 'U') IS NULL
    SET @ErroresPreval += '- Brecha H2: Falta tabla requerida dbo.Dim_Campana (bloqueante contractual).' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Campana') AND c.name = 'KeyCampana' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Campana.KeyCampana debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Campana')
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
                    AND c.name = 'KeyCampana'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Campana.KeyCampana debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Campana') AND c.name = 'id_campana' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Campana.id_campana debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Campana') AND name = 'KeyCampana')
    BEGIN
        DECLARE @hasMem0_Campana INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Campana WHERE KeyCampana = 0', N'@c INT OUTPUT', @c = @hasMem0_Campana OUTPUT;
        IF @hasMem0_Campana = 0
            SET @ErroresPreval += '- dbo.Dim_Campana no contiene el miembro desconocido verificado (KeyCampana = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.8 Validación de Estructura de Fact_CaptacionBuyer (si ya existe)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Fact_CaptacionBuyer', 'U') IS NOT NULL
BEGIN
    -- 1. Validar Clave Primaria simple habilitada sobre KeyFactBuyer (BIGINT IDENTITY)
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes i
        JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID('dbo.Fact_CaptacionBuyer')
          AND i.is_primary_key = 1
          AND i.is_disabled = 0
          AND (
              SELECT COUNT(*) 
              FROM sys.index_columns ic2 
              WHERE ic2.object_id = i.object_id 
                AND ic2.index_id = i.index_id 
                AND ic2.is_included_column = 0
          ) = 1
          AND ic.is_included_column = 0
          AND c.name = 'KeyFactBuyer'
          AND c.is_identity = 1
    )
        SET @ErroresPreval += '- dbo.Fact_CaptacionBuyer preexistente debe tener PK simple habilitada sobre KeyFactBuyer (BIGINT IDENTITY).' + CHAR(13) + CHAR(10);

    -- 2. Validar restricción UNIQUE simple habilitada y sin filtro sobre id_persona_origen
    IF NOT EXISTS (
        SELECT 1 
        FROM sys.indexes i
        JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID('dbo.Fact_CaptacionBuyer')
          AND i.is_unique = 1
          AND i.is_disabled = 0
          AND i.has_filter = 0
          AND (
              SELECT COUNT(*) 
              FROM sys.index_columns ic2 
              WHERE ic2.object_id = i.object_id 
                AND ic2.index_id = i.index_id 
                AND ic2.is_included_column = 0
          ) = 1
          AND ic.is_included_column = 0
          AND c.name = 'id_persona_origen'
    )
        SET @ErroresPreval += '- dbo.Fact_CaptacionBuyer preexistente debe tener restricción/índice UNIQUE simple habilitado y sin filtro sobre id_persona_origen (un índice compuesto no garantiza la unicidad individual).' + CHAR(13) + CHAR(10);

    -- 3. Validar existencia, tipos exactos, nulabilidad, longitudes, precisión/escala decimal y escala datetime2
    DECLARE @ColumnasIncompatibles VARCHAR(MAX) = '';
    SELECT @ColumnasIncompatibles += req.col + ' [' + req.detalle + '], '
    FROM (
        SELECT 
            r.col,
            CASE 
                WHEN c.column_id IS NULL THEN 'Columna inexistente'
                WHEN t.name <> r.tipo THEN CONCAT('Tipo ', t.name, ' incompatible con ', r.tipo)
                WHEN c.is_nullable <> r.es_null THEN CONCAT('Nulabilidad ', CASE WHEN c.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END, ' incompatible con ', CASE WHEN r.es_null = 1 THEN 'NULL' ELSE 'NOT NULL' END)
                WHEN r.tipo IN ('varchar', 'nvarchar') AND c.max_length <> -1 AND c.max_length < r.min_len THEN CONCAT('Longitud ', c.max_length, ' menor a requerida ', r.min_len)
                WHEN r.tipo = 'decimal' AND (c.scale < r.req_scale OR (c.precision - c.scale) < (r.req_prec - r.req_scale)) THEN CONCAT('Capacidad decimal insuficiente: decimal(', c.precision, ',', c.scale, ') tiene ', (c.precision - c.scale), ' digitos enteros y escala ', c.scale, ' (requiere al menos ', (r.req_prec - r.req_scale), ' enteros y escala >= ', r.req_scale, ')')
                WHEN r.tipo = 'datetime2' AND c.scale < r.req_scale THEN CONCAT('Escala datetime2(', c.scale, ') menor a datetime2(', r.req_scale, ')')
                ELSE 'Incompatible'
            END AS detalle
        FROM (VALUES 
            ('KeyFactBuyer', 'bigint', 0, 0, 19, 0),
            ('id_persona_origen', 'int', 0, 0, 10, 0),
            ('KeyTiempoRegistro', 'int', 0, 0, 10, 0),
            ('KeyTiempoConversion', 'int', 0, 0, 10, 0),
            ('KeyCanal', 'int', 0, 0, 10, 0),
            ('KeyFuente', 'int', 0, 0, 10, 0),
            ('KeyCampana', 'int', 0, 0, 10, 0),
            ('KeySede', 'int', 0, 0, 10, 0),
            ('KeyPersona', 'int', 0, 0, 10, 0),
            ('KeyEstadoRegistro', 'int', 0, 0, 10, 0),
            ('ContactosRegistrados', 'int', 0, 0, 10, 0),
            ('ContactosUtilizables', 'int', 0, 0, 10, 0),
            ('ContactosElegiblesB1', 'int', 0, 0, 10, 0),
            ('ConversionesALead14Dias', 'int', 0, 0, 10, 0),
            ('ConversionesALead', 'int', 0, 0, 10, 0),
            ('SegundosConversion', 'bigint', 1, 0, 19, 0),
            ('TiempoConversionDias', 'int', 1, 0, 10, 0),
            ('CostoAtribuidoCaptacion', 'decimal', 1, 0, 10, 2),
            ('EstadoDisponibilidadCosto', 'varchar', 0, 30, 0, 0),
            ('BatchId', 'varchar', 0, 50, 0, 0),
            ('FechaCarga', 'datetime2', 0, 0, 27, 7),
            ('UsuarioCarga', 'varchar', 0, 50, 0, 0)
        ) AS r(col, tipo, es_null, min_len, req_prec, req_scale)
        LEFT JOIN sys.columns c ON c.object_id = OBJECT_ID('dbo.Fact_CaptacionBuyer') AND c.name = r.col
        LEFT JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.column_id IS NULL
           OR t.name <> r.tipo
           OR c.is_nullable <> r.es_null
           OR (r.tipo IN ('varchar', 'nvarchar') AND c.max_length <> -1 AND c.max_length < r.min_len)
           OR (r.tipo = 'decimal' AND (c.scale < r.req_scale OR (c.precision - c.scale) < (r.req_prec - r.req_scale)))
           OR (r.tipo = 'datetime2' AND c.scale < r.req_scale)
    ) AS req;

    IF LEN(@ColumnasIncompatibles) > 0
        SET @ErroresPreval += '- dbo.Fact_CaptacionBuyer preexistente presenta columnas faltantes o especificaciones incompatibles: ' + SUBSTRING(@ColumnasIncompatibles, 1, LEN(@ColumnasIncompatibles)-1) + '.' + CHAR(13) + CHAR(10);

    -- 4. Validar 8 claves foráneas contractuales: columna origen, tabla/columna destino, correspondencia completa y estado habilitado/confiable
    DECLARE @FKIncompatibles VARCHAR(MAX) = '';
    SELECT @FKIncompatibles += req_fk.col_origen + ' -> ' + req_fk.tabla_ref + '(' + req_fk.col_ref + ') [' + req_fk.motivo + '], '
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
            ('KeyTiempoRegistro', 'Dim_Tiempo', 'KeyTiempo'),
            ('KeyTiempoConversion', 'Dim_Tiempo', 'KeyTiempo'),
            ('KeyCanal', 'Dim_Canal', 'KeyCanal'),
            ('KeyFuente', 'Dim_Fuente', 'KeyFuente'),
            ('KeyCampana', 'Dim_Campana', 'KeyCampana'),
            ('KeySede', 'Dim_Sede', 'KeySede'),
            ('KeyPersona', 'Dim_Persona', 'KeyPersona'),
            ('KeyEstadoRegistro', 'Dim_EstadoRegistro', 'KeyEstadoRegistro')
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
            WHERE fk.parent_object_id = OBJECT_ID('dbo.Fact_CaptacionBuyer')
              AND (SELECT COUNT(*) FROM sys.foreign_key_columns fkc2 WHERE fkc2.constraint_object_id = fk.object_id) = 1
        ) fk ON fk.parent_col = v.col_origen 
            AND fk.ref_table = v.tabla_ref 
            AND fk.ref_col = v.col_ref
        WHERE fk.object_id IS NULL
           OR fk.is_disabled = 1
           OR fk.is_not_trusted = 1
    ) AS req_fk;

    IF LEN(@FKIncompatibles) > 0
        SET @ErroresPreval += '- dbo.Fact_CaptacionBuyer preexistente presenta claves foráneas ausentes, deshabilitadas o no confiables: ' + SUBSTRING(@FKIncompatibles, 1, LEN(@FKIncompatibles)-1) + '.' + CHAR(13) + CHAR(10);
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

    DECLARE @ColsFaltantesLog VARCHAR(MAX) = '';
    SELECT @ColsFaltantesLog += req.col + ' (' + req.tipo_desc + '), '
    FROM (VALUES 
        ('Procedimiento', 'varchar/nvarchar(>=100)'),
        ('BatchId', 'varchar/nvarchar(>=50)'),
        ('TipoEvento', 'varchar/nvarchar(>=30)'),
        ('Mensaje', 'varchar/nvarchar(>=500 o MAX)'),
        ('LineaError', 'int/bigint'),
        ('FechaRegistro', 'datetime/datetime2')
    ) AS req(col, tipo_desc)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Log_Ejecucion_ETL')
          AND c.name = req.col
          AND (
              (req.col = 'Procedimiento' AND t.name IN ('varchar', 'nvarchar') AND (c.max_length >= 100 OR c.max_length = -1))
              OR (req.col = 'BatchId' AND t.name IN ('varchar', 'nvarchar') AND (c.max_length >= 50 OR c.max_length = -1))
              OR (req.col = 'TipoEvento' AND t.name IN ('varchar', 'nvarchar') AND (c.max_length >= 30 OR c.max_length = -1))
              OR (req.col = 'Mensaje' AND t.name IN ('varchar', 'nvarchar') AND (c.max_length >= 500 OR c.max_length = -1))
              OR (req.col = 'LineaError' AND t.name IN ('int', 'bigint', 'smallint'))
              OR (req.col = 'FechaRegistro' AND t.name IN ('datetime', 'datetime2', 'smalldatetime'))
          )
    );

    IF LEN(@ColsFaltantesLog) > 0
        SET @ErroresPreval += '- dbo.Log_Ejecucion_ETL preexistente presenta columnas faltantes o tipos/capacidades incompatibles: ' + SUBSTRING(@ColsFaltantesLog, 1, LEN(@ColsFaltantesLog)-1) + '.' + CHAR(13) + CHAR(10);
END;

IF OBJECT_ID('dbo.Rechazos_ETL_Buyer', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Rechazos_ETL_Buyer') AND name = 'RechazoId' AND is_identity = 1
    )
        SET @ErroresPreval += '- dbo.Rechazos_ETL_Buyer preexistente no tiene columna identidad RechazoId.' + CHAR(13) + CHAR(10);

    DECLARE @ColsFaltantesRech VARCHAR(MAX) = '';
    SELECT @ColsFaltantesRech += req.col + ' (' + req.tipo_desc + '), '
    FROM (VALUES 
        ('EntidadOrigenId', 'int/bigint'),
        ('MotivoRechazo', 'varchar/nvarchar(>=100)'),
        ('DetalleRechazo', 'varchar/nvarchar(>=200 o MAX)'),
        ('BatchId', 'varchar/nvarchar(>=50)'),
        ('FechaRechazo', 'datetime/datetime2')
    ) AS req(col, tipo_desc)
    WHERE NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Rechazos_ETL_Buyer')
          AND c.name = req.col
          AND (
              (req.col = 'EntidadOrigenId' AND t.name IN ('int', 'bigint'))
              OR (req.col = 'MotivoRechazo' AND t.name IN ('varchar', 'nvarchar') AND (c.max_length >= 100 OR c.max_length = -1))
              OR (req.col = 'DetalleRechazo' AND t.name IN ('varchar', 'nvarchar') AND (c.max_length >= 200 OR c.max_length = -1))
              OR (req.col = 'BatchId' AND t.name IN ('varchar', 'nvarchar') AND (c.max_length >= 50 OR c.max_length = -1))
              OR (req.col = 'FechaRechazo' AND t.name IN ('datetime', 'datetime2', 'smalldatetime'))
          )
    );

    IF LEN(@ColsFaltantesRech) > 0
        SET @ErroresPreval += '- dbo.Rechazos_ETL_Buyer preexistente presenta columnas faltantes o tipos/capacidades incompatibles: ' + SUBSTRING(@ColsFaltantesRech, 1, LEN(@ColsFaltantesRech)-1) + '.' + CHAR(13) + CHAR(10);
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.10 Dictamen y Detención Segura del Script (SET NOEXEC ON)
-- ----------------------------------------------------------------------------------------------------
IF LEN(@ErroresPreval) > 0
BEGIN
    DECLARE @MensajeErrorPreval VARCHAR(MAX) = 'ABORTANDO DESPLIEGUE ETL BUYER POR DEPENDENCIAS FALTANTES O ESTRUCTURA INCOMPATIBLE:' + CHAR(13) + CHAR(10) + @ErroresPreval;
    RAISERROR(@MensajeErrorPreval, 16, 1);
    -- En entornos interactivos o sin SQLCMD -b, SET NOEXEC ON impide que los lotes posteriores se ejecuten físicamente
    SET NOEXEC ON;
END
ELSE
BEGIN
    PRINT '>> Prevalidación dimensional, estructural y de claves superada con éxito.';
END;
GO

-- ====================================================================================================
-- LOTE 2: DDL DE OBJETOS AUXILIARES Y TABLA DE HECHOS (CON RESTRICCIONES CONTRACTUALES)
-- ====================================================================================================

-- 2.1 Tabla de Bitácora de Auditoría ETL
IF OBJECT_ID('dbo.Log_Ejecucion_ETL', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Log_Ejecucion_ETL (
        LogId BIGINT IDENTITY(1,1) NOT NULL,
        Procedimiento VARCHAR(100) NOT NULL,
        BatchId VARCHAR(50) NOT NULL,
        TipoEvento VARCHAR(30) NOT NULL, -- INICIO, EXITO, ERROR, ADVERTENCIA
        Mensaje VARCHAR(MAX) NOT NULL,
        LineaError INT NULL,
        FechaRegistro DATETIME2(7) NOT NULL CONSTRAINT DF_Log_FechaRegistro DEFAULT GETDATE(),
        CONSTRAINT PK_Log_Ejecucion_ETL PRIMARY KEY CLUSTERED (LogId)
    );
    PRINT '>> Tabla dbo.Log_Ejecucion_ETL creada exitosamente.';
END
ELSE
BEGIN
    PRINT '>> La tabla dbo.Log_Ejecucion_ETL ya existe con estructura compatible.';
END;
GO

-- 2.2 Tabla de Rechazos y Excepciones de Calidad Buyer
IF OBJECT_ID('dbo.Rechazos_ETL_Buyer', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Rechazos_ETL_Buyer (
        RechazoId BIGINT IDENTITY(1,1) NOT NULL,
        EntidadOrigenId INT NOT NULL,
        MotivoRechazo VARCHAR(150) NOT NULL,
        DetalleRechazo VARCHAR(MAX) NULL,
        BatchId VARCHAR(50) NOT NULL,
        FechaRechazo DATETIME2(7) NOT NULL CONSTRAINT DF_RechazosBuyer_Fecha DEFAULT GETDATE(),
        CONSTRAINT PK_Rechazos_ETL_Buyer PRIMARY KEY CLUSTERED (RechazoId)
    );
    PRINT '>> Tabla dbo.Rechazos_ETL_Buyer creada exitosamente.';
END
ELSE
BEGIN
    PRINT '>> La tabla dbo.Rechazos_ETL_Buyer ya existe con estructura compatible.';
END;
GO

-- 2.3 Tabla de Hechos: dbo.Fact_CaptacionBuyer
IF OBJECT_ID('dbo.Fact_CaptacionBuyer', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Fact_CaptacionBuyer (
        KeyFactBuyer                BIGINT IDENTITY(1,1) NOT NULL,
        id_persona_origen           INT NOT NULL,                           -- Natural Key de Idempotencia
        KeyTiempoRegistro           INT NOT NULL,                           -- Clave Foránea Dim_Tiempo (Fecha Registro)
        KeyTiempoConversion         INT NOT NULL CONSTRAINT DF_FactBuyer_TiempoConv DEFAULT 0, -- Dim_Tiempo (0 si no convirtió)
        KeyCanal                    INT NOT NULL CONSTRAINT DF_FactBuyer_Canal DEFAULT 0,      -- Clave Foránea Dim_Canal (0 si NULL)
        KeyFuente                   INT NOT NULL CONSTRAINT DF_FactBuyer_Fuente DEFAULT 0,     -- Clave Foránea Dim_Fuente (0 si NULL)
        KeyCampana                  INT NOT NULL CONSTRAINT DF_FactBuyer_Campana DEFAULT 0,    -- Clave Foránea Dim_Campana (0 si NULL)
        KeySede                     INT NOT NULL CONSTRAINT DF_FactBuyer_Sede DEFAULT 0,       -- Clave Foránea Dim_Sede (0 sin sede asignada)
        KeyPersona                  INT NOT NULL CONSTRAINT DF_FactBuyer_Persona DEFAULT 0,    -- Clave Foránea Dim_Persona (0 si no conformada)
        KeyEstadoRegistro           INT NOT NULL CONSTRAINT DF_FactBuyer_EstadoReg DEFAULT 0,  -- Clave Foránea Dim_EstadoRegistro
        
        -- Métricas Aditivas (B1, B2, B3 y compatibilidad con report.routes.ts)
        ContactosRegistrados        INT NOT NULL CONSTRAINT DF_FactBuyer_ContactosReg DEFAULT 1,
        ContactosUtilizables        INT NOT NULL CONSTRAINT DF_FactBuyer_ContactosUtil DEFAULT 0,
        ContactosElegiblesB1        INT NOT NULL CONSTRAINT DF_FactBuyer_ContactosEleg DEFAULT 0,
        ConversionesALead14Dias     INT NOT NULL CONSTRAINT DF_FactBuyer_Conv14D DEFAULT 0,
        ConversionesALead           INT NOT NULL CONSTRAINT DF_FactBuyer_ConvTotal DEFAULT 0,
        SegundosConversion          BIGINT NULL,
        TiempoConversionDias        INT NULL,
        CostoAtribuidoCaptacion     DECIMAL(10,2) NULL,
        EstadoDisponibilidadCosto   VARCHAR(30) NOT NULL CONSTRAINT DF_FactBuyer_EstadoCosto DEFAULT 'PendienteConciliacion',
        
        -- Metadatos de Auditoría ETL
        BatchId                     VARCHAR(50) NOT NULL,
        FechaCarga                  DATETIME2(7) NOT NULL CONSTRAINT DF_FactBuyer_FechaCarga DEFAULT GETDATE(),
        UsuarioCarga                VARCHAR(50) NOT NULL CONSTRAINT DF_FactBuyer_UsuarioCarga DEFAULT SYSTEM_USER,
        
        CONSTRAINT PK_Fact_CaptacionBuyer PRIMARY KEY CLUSTERED (KeyFactBuyer),
        CONSTRAINT UQ_Fact_CaptacionBuyer_Origen UNIQUE NONCLUSTERED (id_persona_origen),
        CONSTRAINT FK_FactBuyer_TiempoReg FOREIGN KEY (KeyTiempoRegistro) REFERENCES dbo.Dim_Tiempo (KeyTiempo),
        CONSTRAINT FK_FactBuyer_TiempoConv FOREIGN KEY (KeyTiempoConversion) REFERENCES dbo.Dim_Tiempo (KeyTiempo),
        CONSTRAINT FK_FactBuyer_Canal FOREIGN KEY (KeyCanal) REFERENCES dbo.Dim_Canal (KeyCanal),
        CONSTRAINT FK_FactBuyer_Fuente FOREIGN KEY (KeyFuente) REFERENCES dbo.Dim_Fuente (KeyFuente),
        CONSTRAINT FK_FactBuyer_Campana FOREIGN KEY (KeyCampana) REFERENCES dbo.Dim_Campana (KeyCampana),
        CONSTRAINT FK_FactBuyer_Sede FOREIGN KEY (KeySede) REFERENCES dbo.Dim_Sede (KeySede),
        CONSTRAINT FK_FactBuyer_Persona FOREIGN KEY (KeyPersona) REFERENCES dbo.Dim_Persona (KeyPersona),
        CONSTRAINT FK_FactBuyer_EstadoReg FOREIGN KEY (KeyEstadoRegistro) REFERENCES dbo.Dim_EstadoRegistro (KeyEstadoRegistro)
    );
    PRINT '>> Tabla dbo.Fact_CaptacionBuyer creada exitosamente con todas sus restricciones contractuales.';
END
ELSE
BEGIN
    PRINT '>> La tabla dbo.Fact_CaptacionBuyer ya existe con estructura compatible.';
END;
GO

-- ====================================================================================================
-- LOTE 3: PROCEDIMIENTO ALMACENADO DE CARGA: dbo.usp_Cargar_Fact_CaptacionBuyer
-- ====================================================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Cargar_Fact_CaptacionBuyer
    @FechaCorte DATE,
    @BatchId VARCHAR(50),
    @Insertados INT = 0 OUTPUT,
    @Actualizados INT = 0 OUTPUT,
    @SinCambio INT = 0 OUTPUT,
    @Rechazados INT = 0 OUTPUT,
    @Pendientes INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    -- 1. Inicialización obligatoria de contadores de salida
    SET @Insertados = 0;
    SET @Actualizados = 0;
    SET @SinCambio = 0;
    SET @Rechazados = 0;
    SET @Pendientes = 0;

    -- 2. Validación de Parámetros de Entrada
    IF @FechaCorte IS NULL OR @BatchId IS NULL OR LTRIM(RTRIM(@BatchId)) = ''
    BEGIN
        RAISERROR('Error de Parámetros: @FechaCorte y @BatchId son obligatorios y no pueden ser nulos ni vacíos.', 16, 1);
        RETURN -1;
    END;

    -- 3. Cálculo del Instante de Evaluación (Intervalo Semiabierto Exclusivo)
    -- Los eventos válidos deben cumplir: fecha_evento < @InstanteEvaluacion
    DECLARE @InstanteEvaluacion DATETIME2(0) = DATEADD(day, 1, CAST(@FechaCorte AS DATETIME2(0)));

    -- 4. Prevalidación en Tiempo de Ejecución de Dependencias Bloqueantes
    IF OBJECT_ID('staging.stg_Personas', 'V') IS NULL OR OBJECT_ID('staging.stg_Solicitudes', 'V') IS NULL
    BEGIN
        RAISERROR('Error de Dependencias: Vistas de staging requeridas no existen en la base de datos.', 16, 1);
        RETURN -1;
    END;

    IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NULL 
       OR OBJECT_ID('dbo.Dim_Canal', 'U') IS NULL 
       OR OBJECT_ID('dbo.Dim_Fuente', 'U') IS NULL 
       OR OBJECT_ID('dbo.Dim_Sede', 'U') IS NULL 
       OR OBJECT_ID('dbo.Dim_EstadoRegistro', 'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Persona', 'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Campana', 'U') IS NULL
    BEGIN
        RAISERROR('Error de Dependencias: Una o más dimensiones requeridas no existen físicamente en el catálogo.', 16, 1);
        RETURN -1;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Tiempo WHERE KeyTiempo = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Canal WHERE KeyCanal = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Fuente WHERE KeyFuente = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Sede WHERE KeySede = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_EstadoRegistro WHERE KeyEstadoRegistro = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Persona WHERE KeyPersona = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Campana WHERE KeyCampana = 0)
    BEGIN
        RAISERROR('Error de Dependencias: Uno o más miembros desconocidos (Key = 0) no existen en las dimensiones de destino. Abortando.', 16, 1);
        RETURN -1;
    END;

    IF OBJECT_ID('dbo.Fact_CaptacionBuyer', 'U') IS NULL
    BEGIN
        RAISERROR('Error de Dependencias: La tabla de hechos dbo.Fact_CaptacionBuyer no existe.', 16, 1);
        RETURN -1;
    END;

    -- Registro de Inicio en Bitácora
    BEGIN TRY
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError, FechaRegistro)
        VALUES (
            'dbo.usp_Cargar_Fact_CaptacionBuyer',
            @BatchId,
            'INICIO',
            CONCAT('Iniciando carga Fact_CaptacionBuyer. FechaCorte: ', CONVERT(VARCHAR(10), @FechaCorte, 120), ', InstanteEvaluacion: ', CONVERT(VARCHAR(19), @InstanteEvaluacion, 120)),
            NULL,
            GETDATE()
        );
    END TRY
    BEGIN CATCH
        -- Continuar si falla el log inicial
    END CATCH;

    -- 5. Fase 2: Extracción y Enriquecimiento Escalar en Tabla Intermedia
    IF OBJECT_ID('tempdb..#Stg_Buyer_Intermedio') IS NOT NULL 
        DROP TABLE #Stg_Buyer_Intermedio;

    CREATE TABLE #Stg_Buyer_Intermedio (
        id_persona                  INT NOT NULL,
        fecha_registro              DATETIME2(7) NOT NULL,
        id_canal_origen             INT NULL,
        id_campana_origen           INT NULL,
        estado_calidad_norm         VARCHAR(50) NOT NULL,
        autoriza_contacto_original  INT NULL,
        es_contacto_utilizable_tecnico INT NOT NULL,
        
        -- Enriquecimiento escalar de primera solicitud
        primera_fecha_solicitud     DATETIME2(7) NULL,
        tiene_anomalia_cronologica  BIT NOT NULL DEFAULT 0,
        
        -- Medidas calculadas
        ContactosRegistrados        INT NOT NULL DEFAULT 1,
        ContactosUtilizables        INT NOT NULL DEFAULT 0,
        ContactosElegiblesB1        INT NOT NULL DEFAULT 0,
        ConversionesALead14Dias     INT NOT NULL DEFAULT 0,
        ConversionesALead           INT NOT NULL DEFAULT 0,
        SegundosConversion          BIGINT NULL,
        TiempoConversionDias        INT NULL,
        CostoAtribuidoCaptacion     DECIMAL(10,2) NULL,
        EstadoDisponibilidadCosto   VARCHAR(30) NOT NULL DEFAULT 'PendienteConciliacion',
        
        -- Claves dimensionales resueltas
        KeyTiempoRegistro           INT NOT NULL DEFAULT 0,
        KeyTiempoConversion         INT NOT NULL DEFAULT 0,
        KeyCanal                    INT NOT NULL DEFAULT 0,
        KeyFuente                   INT NOT NULL DEFAULT 0,
        KeyCampana                  INT NOT NULL DEFAULT 0,
        KeySede                     INT NOT NULL DEFAULT 0,
        KeyPersona                  INT NOT NULL DEFAULT 0,
        KeyEstadoRegistro           INT NOT NULL DEFAULT 0,
        
        -- Auditoría interna de resolución
        EstadoValidacion            VARCHAR(50) NOT NULL DEFAULT 'Valido',
        MotivoRechazo               VARCHAR(150) NULL,
        DetalleRechazo              VARCHAR(MAX) NULL,
        ClasificacionAccion         VARCHAR(20) NOT NULL DEFAULT 'SinClasificar'
    );

    -- Inserción de personas con corte semiabierto (< @InstanteEvaluacion)
    -- Enriquecimiento escalar de primera solicitud ordenada cronológicamente (ASC)
    INSERT INTO #Stg_Buyer_Intermedio (
        id_persona,
        fecha_registro,
        id_canal_origen,
        id_campana_origen,
        estado_calidad_norm,
        autoriza_contacto_original,
        es_contacto_utilizable_tecnico,
        primera_fecha_solicitud,
        tiene_anomalia_cronologica
    )
    SELECT 
        p.id_persona,
        p.fecha_registro,
        p.id_canal_origen,
        p.id_campana_origen,
        p.estado_calidad_norm,
        p.autoriza_contacto_original,
        p.es_contacto_utilizable_tecnico,
        sol.primera_fecha_solicitud,
        CASE WHEN anom.id_persona IS NOT NULL THEN 1 ELSE 0 END AS tiene_anomalia_cronologica
    FROM staging.stg_Personas p
    OUTER APPLY (
        SELECT TOP (1) s.fecha_solicitud AS primera_fecha_solicitud
        FROM staging.stg_Solicitudes s
        WHERE s.id_persona = p.id_persona
          AND s.fecha_solicitud >= p.fecha_registro
          AND s.fecha_solicitud < @InstanteEvaluacion
        ORDER BY s.fecha_solicitud ASC, s.id_solicitud ASC
    ) sol
    OUTER APPLY (
        SELECT TOP (1) s_anom.id_persona
        FROM staging.stg_Solicitudes s_anom
        WHERE s_anom.id_persona = p.id_persona
          AND s_anom.fecha_solicitud < p.fecha_registro
          AND s_anom.fecha_solicitud < @InstanteEvaluacion
    ) anom
    WHERE p.fecha_registro < @InstanteEvaluacion;

    -- Verificación de Invariante de Grano: Exactamente 1 fila por id_persona
    IF EXISTS (SELECT id_persona FROM #Stg_Buyer_Intermedio GROUP BY id_persona HAVING COUNT(*) > 1)
    BEGIN
        RAISERROR('Invariante de Grano Violado: Se encontraron personas duplicadas en la tabla intermedia.', 16, 1);
        RETURN -1;
    END;

    -- 6. Cálculo de Medidas de Cohorte y Atributos de Negocio
    UPDATE t
    SET 
        t.ContactosRegistrados = 1,
        t.ContactosUtilizables = CASE 
            WHEN t.es_contacto_utilizable_tecnico = 1 AND t.autoriza_contacto_original = 1 THEN 1 
            ELSE 0 
        END,
        t.ContactosElegiblesB1 = CASE 
            WHEN t.es_contacto_utilizable_tecnico = 1 
                 AND t.autoriza_contacto_original = 1 
                 AND t.fecha_registro <= DATEADD(day, -14, @InstanteEvaluacion) 
            THEN 1 
            ELSE 0 
        END,
        t.ConversionesALead14Dias = CASE 
            WHEN t.es_contacto_utilizable_tecnico = 1 
                 AND t.autoriza_contacto_original = 1 
                 AND t.fecha_registro <= DATEADD(day, -14, @InstanteEvaluacion)
                 AND t.primera_fecha_solicitud IS NOT NULL 
                 AND t.primera_fecha_solicitud <= DATEADD(day, 14, t.fecha_registro) 
            THEN 1 
            ELSE 0 
        END,
        t.ConversionesALead = CASE 
            WHEN t.primera_fecha_solicitud IS NOT NULL THEN 1 
            ELSE 0 
        END,
        t.SegundosConversion = CASE 
            WHEN t.primera_fecha_solicitud IS NOT NULL 
            THEN DATEDIFF_BIG(second, t.fecha_registro, t.primera_fecha_solicitud) 
            ELSE NULL 
        END,
        t.TiempoConversionDias = CASE 
            WHEN t.primera_fecha_solicitud IS NOT NULL 
            THEN DATEDIFF(day, t.fecha_registro, t.primera_fecha_solicitud) 
            ELSE NULL 
        END,
        t.CostoAtribuidoCaptacion = NULL,
        t.EstadoDisponibilidadCosto = 'PendienteConciliacion',
        t.KeySede = 0
    FROM #Stg_Buyer_Intermedio t;

    -- Marcado de Anomalías Cronológicas
    UPDATE t
    SET 
        t.EstadoValidacion = 'AnomaliaCronologica',
        t.MotivoRechazo = 'AnomaliaCronologica: Solicitud previa a registro',
        t.DetalleRechazo = 'Existe al menos una solicitud con fecha_solicitud anterior a fecha_registro de la persona.',
        t.ClasificacionAccion = 'Rechazada'
    FROM #Stg_Buyer_Intermedio t
    WHERE t.tiene_anomalia_cronologica = 1;

    -- 7. Resolución Dimensional con Control Exhaustivo de Coincidencias (0, 1, >1)
    
    -- 7.1 KeyTiempoRegistro (Dim_Tiempo por id_fecha)
    UPDATE t
    SET 
        t.KeyTiempoRegistro = CASE 
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0
        END,
        t.EstadoValidacion = CASE 
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            WHEN lkp.cnt IS NULL THEN 'PendienteDimensionH2'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE 
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Tiempo duplicada para fecha_registro'
            WHEN lkp.cnt IS NULL THEN 'PendienteDimensionH2: Fecha de registro ausente en Dim_Tiempo'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE 
            WHEN lkp.cnt > 1 THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.fecha_registro AS DATE), 120), ' tiene ', lkp.cnt, ' filas en Dim_Tiempo.')
            WHEN lkp.cnt IS NULL THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.fecha_registro AS DATE), 120), ' no existe en Dim_Tiempo.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Buyer_Intermedio t
    LEFT JOIN (
        SELECT id_fecha, COUNT(*) AS cnt, MIN(KeyTiempo) AS min_key
        FROM dbo.Dim_Tiempo
        GROUP BY id_fecha
    ) lkp ON lkp.id_fecha = CAST(t.fecha_registro AS DATE)
    WHERE t.EstadoValidacion = 'Valido';

    -- 7.2 KeyTiempoConversion (Dim_Tiempo por fecha_solicitud)
    UPDATE t
    SET 
        t.KeyTiempoConversion = CASE 
            WHEN t.primera_fecha_solicitud IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0
        END,
        t.EstadoValidacion = CASE 
            WHEN t.primera_fecha_solicitud IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            WHEN t.primera_fecha_solicitud IS NOT NULL AND lkp.cnt IS NULL THEN 'PendienteDimensionH2'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE 
            WHEN t.primera_fecha_solicitud IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Tiempo duplicada para fecha_solicitud'
            WHEN t.primera_fecha_solicitud IS NOT NULL AND lkp.cnt IS NULL THEN 'PendienteDimensionH2: Fecha de conversion ausente en Dim_Tiempo'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE 
            WHEN t.primera_fecha_solicitud IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.primera_fecha_solicitud AS DATE), 120), ' tiene ', lkp.cnt, ' filas en Dim_Tiempo.')
            WHEN t.primera_fecha_solicitud IS NOT NULL AND lkp.cnt IS NULL THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.primera_fecha_solicitud AS DATE), 120), ' no existe en Dim_Tiempo.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Buyer_Intermedio t
    LEFT JOIN (
        SELECT id_fecha, COUNT(*) AS cnt, MIN(KeyTiempo) AS min_key
        FROM dbo.Dim_Tiempo
        GROUP BY id_fecha
    ) lkp ON lkp.id_fecha = CAST(t.primera_fecha_solicitud AS DATE)
    WHERE t.EstadoValidacion = 'Valido';

    -- 7.3 KeyCanal (Dim_Canal por id_canal)
    UPDATE t
    SET 
        t.KeyCanal = CASE 
            WHEN t.id_canal_origen IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            WHEN lkp.cnt IS NULL THEN 0
            ELSE 0
        END,
        t.EstadoValidacion = CASE 
            WHEN t.id_canal_origen IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE 
            WHEN t.id_canal_origen IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Canal duplicado para id_canal'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE 
            WHEN t.id_canal_origen IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('id_canal = ', t.id_canal_origen, ' tiene ', lkp.cnt, ' filas en Dim_Canal.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Buyer_Intermedio t
    LEFT JOIN (
        SELECT id_canal, COUNT(*) AS cnt, MIN(KeyCanal) AS min_key
        FROM dbo.Dim_Canal
        WHERE id_canal IS NOT NULL
        GROUP BY id_canal
    ) lkp ON lkp.id_canal = t.id_canal_origen
    WHERE t.EstadoValidacion = 'Valido';

    -- 7.4 KeyFuente (Dim_Fuente por id_campana)
    UPDATE t
    SET 
        t.KeyFuente = CASE 
            WHEN t.id_campana_origen IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            WHEN lkp.cnt IS NULL THEN 0
            ELSE 0
        END,
        t.EstadoValidacion = CASE 
            WHEN t.id_campana_origen IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE 
            WHEN t.id_campana_origen IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Fuente duplicada para id_campana'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE 
            WHEN t.id_campana_origen IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('id_campana = ', t.id_campana_origen, ' tiene ', lkp.cnt, ' filas en Dim_Fuente.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Buyer_Intermedio t
    LEFT JOIN (
        SELECT id_campana, COUNT(*) AS cnt, MIN(KeyFuente) AS min_key
        FROM dbo.Dim_Fuente
        WHERE id_campana IS NOT NULL
        GROUP BY id_campana
    ) lkp ON lkp.id_campana = t.id_campana_origen
    WHERE t.EstadoValidacion = 'Valido';

    -- 7.5 KeyCampana (Dim_Campana por id_campana)
    UPDATE t
    SET 
        t.KeyCampana = CASE 
            WHEN t.id_campana_origen IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            WHEN lkp.cnt IS NULL THEN 0
            ELSE 0
        END,
        t.EstadoValidacion = CASE 
            WHEN t.id_campana_origen IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE 
            WHEN t.id_campana_origen IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Campana duplicada para id_campana'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE 
            WHEN t.id_campana_origen IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('id_campana = ', t.id_campana_origen, ' tiene ', lkp.cnt, ' filas en Dim_Campana.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Buyer_Intermedio t
    LEFT JOIN (
        SELECT id_campana, COUNT(*) AS cnt, MIN(KeyCampana) AS min_key
        FROM dbo.Dim_Campana
        WHERE id_campana IS NOT NULL
        GROUP BY id_campana
    ) lkp ON lkp.id_campana = t.id_campana_origen
    WHERE t.EstadoValidacion = 'Valido';

    -- 7.6 KeyPersona (Dim_Persona por id_persona)
    UPDATE t
    SET 
        t.KeyPersona = CASE 
            WHEN lkp.cnt = 1 THEN lkp.min_key
            WHEN lkp.cnt IS NULL THEN 0
            ELSE 0
        END,
        t.EstadoValidacion = CASE 
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE 
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Persona duplicada para id_persona'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE 
            WHEN lkp.cnt > 1 THEN CONCAT('id_persona = ', t.id_persona, ' tiene ', lkp.cnt, ' filas en Dim_Persona.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Buyer_Intermedio t
    LEFT JOIN (
        SELECT id_persona, COUNT(*) AS cnt, MIN(KeyPersona) AS min_key
        FROM dbo.Dim_Persona
        WHERE id_persona IS NOT NULL
        GROUP BY id_persona
    ) lkp ON lkp.id_persona = t.id_persona
    WHERE t.EstadoValidacion = 'Valido';

    -- 7.7 KeyEstadoRegistro (Dim_EstadoRegistro por EstadoCalidad y AutorizacionContacto)
    UPDATE t
    SET 
        t.KeyEstadoRegistro = CASE 
            WHEN lkp.cnt = 1 THEN lkp.min_key
            WHEN lkp.cnt IS NULL THEN 0
            ELSE 0
        END,
        t.EstadoValidacion = CASE 
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE 
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_EstadoRegistro duplicada'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE 
            WHEN lkp.cnt > 1 THEN CONCAT('EstadoCalidad = ', t.estado_calidad_norm, ', Autoriza = ', CASE WHEN t.autoriza_contacto_original = 1 THEN 'SI' ELSE 'NO' END, ' tiene ', lkp.cnt, ' coincidencias en Dim_EstadoRegistro.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Buyer_Intermedio t
    LEFT JOIN (
        SELECT EstadoCalidad, AutorizacionContacto, COUNT(*) AS cnt, MIN(KeyEstadoRegistro) AS min_key
        FROM dbo.Dim_EstadoRegistro
        GROUP BY EstadoCalidad, AutorizacionContacto
    ) lkp ON lkp.EstadoCalidad = t.estado_calidad_norm
         AND lkp.AutorizacionContacto = CASE WHEN t.autoriza_contacto_original = 1 THEN 'SI' ELSE 'NO' END
    WHERE t.EstadoValidacion = 'Valido';

    -- Actualización de Clasificación de Acciones para filas con error o pendientes
    UPDATE t
    SET t.ClasificacionAccion = CASE 
        WHEN t.EstadoValidacion = 'ErrorLookupAmbiguo' THEN 'Rechazada'
        WHEN t.EstadoValidacion = 'AnomaliaCronologica' THEN 'Rechazada'
        WHEN t.EstadoValidacion = 'PendienteDimensionH2' THEN 'Pendiente'
        ELSE t.ClasificacionAccion
    END
    FROM #Stg_Buyer_Intermedio t
    WHERE t.EstadoValidacion <> 'Valido';

    -- 8. Paso 4: Transacción Atómica, Protección de Concurrencia y Persistencia
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Adquisición de Bloqueo Exclusivo de Aplicación (sp_getapplock)
        DECLARE @ResLock INT;
        EXEC @ResLock = sp_getapplock 
            @Resource = 'ETL_Lock_Fact_CaptacionBuyer', 
            @LockMode = 'Exclusive', 
            @LockOwner = 'Transaction', 
            @LockTimeout = 30000;

        IF @ResLock < 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Error de Concurrencia: No se pudo adquirir el bloqueo exclusivo ETL_Lock_Fact_CaptacionBuyer (código %d). Carga abortada.', 16, 1, @ResLock);
            RETURN -2;
        END;

        -- Clasificación Protegida contra el Destino BAJO EL BLOQUEO
        UPDATE src
        SET src.ClasificacionAccion = CASE 
            WHEN dest.id_persona_origen IS NULL THEN 'Insertar'
            WHEN dest.KeyTiempoRegistro <> src.KeyTiempoRegistro
              OR dest.KeyTiempoConversion <> src.KeyTiempoConversion
              OR dest.KeyCanal <> src.KeyCanal
              OR dest.KeyFuente <> src.KeyFuente
              OR dest.KeyCampana <> src.KeyCampana
              OR dest.KeySede <> src.KeySede
              OR dest.KeyPersona <> src.KeyPersona
              OR dest.KeyEstadoRegistro <> src.KeyEstadoRegistro
              OR dest.ContactosRegistrados <> src.ContactosRegistrados
              OR dest.ContactosUtilizables <> src.ContactosUtilizables
              OR dest.ContactosElegiblesB1 <> src.ContactosElegiblesB1
              OR dest.ConversionesALead14Dias <> src.ConversionesALead14Dias
              OR dest.ConversionesALead <> src.ConversionesALead
              OR (dest.SegundosConversion <> src.SegundosConversion 
                  OR (dest.SegundosConversion IS NULL AND src.SegundosConversion IS NOT NULL) 
                  OR (dest.SegundosConversion IS NOT NULL AND src.SegundosConversion IS NULL))
              OR (dest.TiempoConversionDias <> src.TiempoConversionDias 
                  OR (dest.TiempoConversionDias IS NULL AND src.TiempoConversionDias IS NOT NULL) 
                  OR (dest.TiempoConversionDias IS NOT NULL AND src.TiempoConversionDias IS NULL))
              OR (dest.CostoAtribuidoCaptacion <> src.CostoAtribuidoCaptacion 
                  OR (dest.CostoAtribuidoCaptacion IS NULL AND src.CostoAtribuidoCaptacion IS NOT NULL) 
                  OR (dest.CostoAtribuidoCaptacion IS NOT NULL AND src.CostoAtribuidoCaptacion IS NULL))
              OR dest.EstadoDisponibilidadCosto <> src.EstadoDisponibilidadCosto
            THEN 'Actualizar'
            ELSE 'SinCambio'
        END
        FROM #Stg_Buyer_Intermedio src
        LEFT JOIN dbo.Fact_CaptacionBuyer dest ON dest.id_persona_origen = src.id_persona
        WHERE src.ClasificacionAccion = 'SinClasificar';

        -- Cálculo de Contadores Disjuntos
        SELECT 
            @Insertados  = COUNT(CASE WHEN ClasificacionAccion = 'Insertar' THEN 1 END),
            @Actualizados = COUNT(CASE WHEN ClasificacionAccion = 'Actualizar' THEN 1 END),
            @SinCambio   = COUNT(CASE WHEN ClasificacionAccion = 'SinCambio' THEN 1 END),
            @Rechazados  = COUNT(CASE WHEN ClasificacionAccion = 'Rechazada' THEN 1 END),
            @Pendientes  = COUNT(CASE WHEN ClasificacionAccion = 'Pendiente' THEN 1 END)
        FROM #Stg_Buyer_Intermedio;

        -- Persistencia 1: Rechazos de Validación
        INSERT INTO dbo.Rechazos_ETL_Buyer (
            EntidadOrigenId, 
            MotivoRechazo, 
            DetalleRechazo, 
            BatchId, 
            FechaRechazo
        )
        SELECT 
            id_persona, 
            MotivoRechazo, 
            DetalleRechazo, 
            @BatchId, 
            GETDATE()
        FROM #Stg_Buyer_Intermedio
        WHERE ClasificacionAccion = 'Rechazada';

        -- Persistencia 2: Actualización In-Place de Filas con Diferencias
        UPDATE dest
        SET 
            dest.KeyTiempoRegistro = src.KeyTiempoRegistro,
            dest.KeyTiempoConversion = src.KeyTiempoConversion,
            dest.KeyCanal = src.KeyCanal,
            dest.KeyFuente = src.KeyFuente,
            dest.KeyCampana = src.KeyCampana,
            dest.KeySede = src.KeySede,
            dest.KeyPersona = src.KeyPersona,
            dest.KeyEstadoRegistro = src.KeyEstadoRegistro,
            dest.ContactosRegistrados = src.ContactosRegistrados,
            dest.ContactosUtilizables = src.ContactosUtilizables,
            dest.ContactosElegiblesB1 = src.ContactosElegiblesB1,
            dest.ConversionesALead14Dias = src.ConversionesALead14Dias,
            dest.ConversionesALead = src.ConversionesALead,
            dest.SegundosConversion = src.SegundosConversion,
            dest.TiempoConversionDias = src.TiempoConversionDias,
            dest.CostoAtribuidoCaptacion = src.CostoAtribuidoCaptacion,
            dest.EstadoDisponibilidadCosto = src.EstadoDisponibilidadCosto,
            dest.BatchId = @BatchId,
            dest.FechaCarga = GETDATE(),
            dest.UsuarioCarga = SYSTEM_USER
        FROM dbo.Fact_CaptacionBuyer dest
        INNER JOIN #Stg_Buyer_Intermedio src ON dest.id_persona_origen = src.id_persona
        WHERE src.ClasificacionAccion = 'Actualizar';

        -- Persistencia 3: Inserción de Nuevos Registros
        INSERT INTO dbo.Fact_CaptacionBuyer (
            id_persona_origen,
            KeyTiempoRegistro,
            KeyTiempoConversion,
            KeyCanal,
            KeyFuente,
            KeyCampana,
            KeySede,
            KeyPersona,
            KeyEstadoRegistro,
            ContactosRegistrados,
            ContactosUtilizables,
            ContactosElegiblesB1,
            ConversionesALead14Dias,
            ConversionesALead,
            SegundosConversion,
            TiempoConversionDias,
            CostoAtribuidoCaptacion,
            EstadoDisponibilidadCosto,
            BatchId,
            FechaCarga,
            UsuarioCarga
        )
        SELECT 
            src.id_persona,
            src.KeyTiempoRegistro,
            src.KeyTiempoConversion,
            src.KeyCanal,
            src.KeyFuente,
            src.KeyCampana,
            src.KeySede,
            src.KeyPersona,
            src.KeyEstadoRegistro,
            src.ContactosRegistrados,
            src.ContactosUtilizables,
            src.ContactosElegiblesB1,
            src.ConversionesALead14Dias,
            src.ConversionesALead,
            src.SegundosConversion,
            src.TiempoConversionDias,
            src.CostoAtribuidoCaptacion,
            src.EstadoDisponibilidadCosto,
            @BatchId,
            GETDATE(),
            SYSTEM_USER
        FROM #Stg_Buyer_Intermedio src
        WHERE src.ClasificacionAccion = 'Insertar';

        -- Registro de Éxito en Bitácora
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError, FechaRegistro)
        VALUES (
            'dbo.usp_Cargar_Fact_CaptacionBuyer',
            @BatchId,
            'EXITO',
            CONCAT('Carga completada exitosamente. Insertados: ', @Insertados, ', Actualizados: ', @Actualizados, ', SinCambio: ', @SinCambio, ', Rechazados: ', @Rechazados, ', Pendientes: ', @Pendientes),
            NULL,
            GETDATE()
        );

        -- Confirmación Atómica (libera el bloqueo de aplicación)
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Regla Contractual: Si la transacción se revierte, los contadores confirmados son estrictamente CERO
        SET @Insertados = 0;
        SET @Actualizados = 0;
        SET @SinCambio = 0;
        SET @Rechazados = 0;
        SET @Pendientes = 0;

        DECLARE @ErrNumero INT = ERROR_NUMBER();
        DECLARE @ErrMensaje NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrLinea INT = ERROR_LINE();

        BEGIN TRY
            INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError, FechaRegistro)
            VALUES (
                'dbo.usp_Cargar_Fact_CaptacionBuyer',
                COALESCE(@BatchId, 'DESCONOCIDO'),
                'ERROR',
                CONCAT('Error ', @ErrNumero, ' en línea ', @ErrLinea, ': ', @ErrMensaje),
                @ErrLinea,
                GETDATE()
            );
        END TRY
        BEGIN CATCH
            -- No bloquear el THROW principal si falla la bitácora
        END CATCH;

        THROW;
    END CATCH;

    -- Limpieza de tabla temporal
    IF OBJECT_ID('tempdb..#Stg_Buyer_Intermedio') IS NOT NULL 
        DROP TABLE #Stg_Buyer_Intermedio;

    RETURN 0;
END;
GO

PRINT '>> Procedimiento almacenado dbo.usp_Cargar_Fact_CaptacionBuyer creado exitosamente.';
GO

-- Restablecer el estado de compilación y ejecución al finalizar el script
SET NOEXEC OFF;
GO
