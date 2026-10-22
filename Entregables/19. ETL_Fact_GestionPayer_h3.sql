-- ====================================================================================================
-- NEXOSALUD — IMPLEMENTACIÓN DEL ETL DE HECHOS: PAYER (H3 - FASE 2)
-- ====================================================================================================
-- Proyecto      : NexoSalud (Plataforma de Inteligencia de Negocios Odontológica — Clínica Luxedent, Trujillo)
-- Metodología   : IMPULSE (Fase: PAYER — Fact_GestionPayer)
-- Responsable   : Jesús Daniel Ordóñez Ugarte (Integrante 4 — ETL PAYER, Cobros y Validación)
-- Ubicación     : Entregables/19. ETL_Fact_GestionPayer_h3.sql
-- Guía          : Entregables/19. Guia_ETL_Payer_h3.md
-- Staging Base  : Entregables/18. Staging_payer_h3.sql (staging.stg_Pagos)
-- Modelo Dim    : Entregables/8. DDL_modelo_dimensional_mart_h2.sql
-- Dimensiones   : Entregables/9. Poblacion_dimensiones_conformadas_h2.sql
-- Referencia    : Entregables/15. ETL_Fact_CaptacionBuyer_h3.sql (patrón Mario)
-- Referencia    : Entregables/17. Cierre_y_traspaso_Mario_h3.md
-- Motor         : SQL Server 2019 — (localdb)\MSSQLLocalDB
-- Base destino  : NexoSalud_Mart
-- Base origen   : NexoSaludDB
--
-- ADVERTENCIA HAL-03:
--   El endpoint payer.routes.ts genera un pago ficticio HAL-03 en cada sesión de prueba.
--   El staging.stg_Pagos no filtra dicho registro. Este script lo propagará a la tabla de hechos
--   si su importe > 0 y tiene estado válido. La detección de HAL-03 debe aplicarse en el staging.
--   Ver Sección 6 de la guía para detalles completos.
--
-- CONTRATO DE EJECUCIÓN REPRODUCIBLE (SQLCMD / HERRAMIENTAS CLIENTE):
--   1. Este script está diseñado para ejecutarse contra NexoSalud_Mart (sin sentencias USE).
--   2. En SQLCMD, ejecute con el parámetro -b (detener ejecución ante errores >= 11):
--        sqlcmd -S "(localdb)\MSSQLLocalDB" -E -d NexoSalud_Mart -b -i "Entregables\19. ETL_Fact_GestionPayer_h3.sql"
--   3. Ante cualquier fallo en la prevalidación defensiva, el script emite un RAISERROR detallado
--      y activa SET NOEXEC ON, impidiendo la ejecución de los lotes posteriores.
--   4. Prerequisito obligatorio: dbo.Log_Ejecucion_ETL debe existir (creada por Entregable 15).
--   5. Prerequisito obligatorio: staging.stg_Pagos debe existir (creada por Entregable 18).
--   6. IndicadorMoneda = 'MonedaNoVerificada' SIEMPRE. No asumir PEN ni USD.
--   7. El grano de Fact_GestionPayer es: 1 fila exactamente por id_pago.
--   8. SCD Tipo 1: actualizaciones in-place con FechaModificacion = GETDATE().
--
-- CONVENCIONES DE NOMENCLATURA:
--   - @Stg_*: variables de staging intermedio
--   - Key*: claves subrogadas dimensionales (INT, 0 = miembro desconocido)
--   - @Instante*: marcas de tiempo de evaluación de corte
--   - ClasificacionAccion: 'Insertar'|'Actualizar'|'SinCambio'|'Rechazada'|'Pendiente'|'SinClasificar'
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
        -- Validar unicidad individual real de KeyTiempo (PK o UNIQUE, habilitada, sin filtro)
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

    -- Comprobar miembro desconocido (KeyTiempo = 0)
    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Tiempo') AND name = 'KeyTiempo')
    BEGIN
        DECLARE @hasMem0_Tiempo INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Tiempo WHERE KeyTiempo = 0', N'@c INT OUTPUT', @c = @hasMem0_Tiempo OUTPUT;
        IF @hasMem0_Tiempo = 0
            SET @ErroresPreval += '- dbo.Dim_Tiempo no contiene el miembro desconocido verificado (KeyTiempo = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.2 Validación de Dim_Hora
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Hora', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Hora.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Hora') AND c.name = 'KeyHora' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Hora.KeyHora debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Hora')
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
                    AND c.name = 'KeyHora'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Hora.KeyHora debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Hora') AND c.name = 'id_hora' AND t.name = 'int'
    )
        SET @ErroresPreval += '- dbo.Dim_Hora.id_hora debe ser de tipo INT.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Hora') AND name = 'KeyHora')
    BEGIN
        DECLARE @hasMem0_Hora INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Hora WHERE KeyHora = 0', N'@c INT OUTPUT', @c = @hasMem0_Hora OUTPUT;
        IF @hasMem0_Hora = 0
            SET @ErroresPreval += '- dbo.Dim_Hora no contiene el miembro desconocido verificado (KeyHora = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.3 Validación de Dim_Sede
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
-- 1.4 Validación de Dim_Servicio
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
-- 1.5 Validación de Dim_Pasarela
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Pasarela', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Pasarela.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Pasarela') AND c.name = 'KeyPasarela' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Pasarela.KeyPasarela debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Pasarela')
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
                    AND c.name = 'KeyPasarela'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Pasarela.KeyPasarela debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Pasarela') AND c.name = 'MetodoPago' AND t.name IN ('varchar', 'nvarchar')
    )
        SET @ErroresPreval += '- dbo.Dim_Pasarela.MetodoPago debe existir y ser de tipo VARCHAR o NVARCHAR.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Pasarela') AND name = 'KeyPasarela')
    BEGIN
        DECLARE @hasMem0_Pasarela INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Pasarela WHERE KeyPasarela = 0', N'@c INT OUTPUT', @c = @hasMem0_Pasarela OUTPUT;
        IF @hasMem0_Pasarela = 0
            SET @ErroresPreval += '- dbo.Dim_Pasarela no contiene el miembro desconocido verificado (KeyPasarela = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.6 Validación de Dim_Cobro
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Dim_Cobro', 'U') IS NULL
    SET @ErroresPreval += '- Falta tabla requerida dbo.Dim_Cobro.' + CHAR(13) + CHAR(10);
ELSE
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Cobro') AND c.name = 'KeyCobro' AND t.name = 'int' AND c.is_nullable = 0
    )
        SET @ErroresPreval += '- dbo.Dim_Cobro.KeyCobro debe ser INT NOT NULL.' + CHAR(13) + CHAR(10);
    ELSE
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM sys.indexes i
            WHERE i.object_id = OBJECT_ID('dbo.Dim_Cobro')
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
                    AND c.name = 'KeyCobro'
              )
        )
            SET @ErroresPreval += '- dbo.Dim_Cobro.KeyCobro debe tener restricción PRIMARY KEY o UNIQUE individual real (habilitada, sin filtro y como única columna clave).' + CHAR(13) + CHAR(10);
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.columns c
        JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.object_id = OBJECT_ID('dbo.Dim_Cobro') AND c.name = 'EstadoPago' AND t.name IN ('varchar', 'nvarchar')
    )
        SET @ErroresPreval += '- dbo.Dim_Cobro.EstadoPago debe existir y ser de tipo VARCHAR o NVARCHAR.' + CHAR(13) + CHAR(10);

    IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Dim_Cobro') AND name = 'KeyCobro')
    BEGIN
        DECLARE @hasMem0_Cobro INT = 0;
        EXEC sp_executesql N'SELECT @c = COUNT(*) FROM dbo.Dim_Cobro WHERE KeyCobro = 0', N'@c INT OUTPUT', @c = @hasMem0_Cobro OUTPUT;
        IF @hasMem0_Cobro = 0
            SET @ErroresPreval += '- dbo.Dim_Cobro no contiene el miembro desconocido verificado (KeyCobro = 0).' + CHAR(13) + CHAR(10);
    END;
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.7 Validación de Dim_Persona
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
-- 1.8 Validación de Fact_GestionPayer preexistente (si existe, verificar compatibilidad H3)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Fact_GestionPayer', 'U') IS NOT NULL
BEGIN
    -- Verificar PK simple habilitada sobre KeyFactPayer (BIGINT IDENTITY)
    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes i
        JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID('dbo.Fact_GestionPayer')
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
          AND c.name = 'KeyFactPayer'
          AND c.is_identity = 1
    )
        SET @ErroresPreval += '- dbo.Fact_GestionPayer preexistente debe tener PK simple habilitada sobre KeyFactPayer (BIGINT IDENTITY). Puede ser versión H2 incompatible.' + CHAR(13) + CHAR(10);

    -- Verificar UNIQUE sobre id_pago_origen
    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes i
        JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
        JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
        WHERE i.object_id = OBJECT_ID('dbo.Fact_GestionPayer')
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
          AND c.name = 'id_pago_origen'
    )
        SET @ErroresPreval += '- dbo.Fact_GestionPayer preexistente debe tener restricción UNIQUE simple habilitada y sin filtro sobre id_pago_origen.' + CHAR(13) + CHAR(10);

    -- Verificar columnas clave de la estructura H3
    DECLARE @ColsIncompatiblesPayer VARCHAR(MAX) = '';
    SELECT @ColsIncompatiblesPayer += req.col + ' [' + req.detalle + '], '
    FROM (
        SELECT
            r.col,
            CASE
                WHEN c.column_id IS NULL THEN 'Columna inexistente'
                WHEN t.name <> r.tipo THEN CONCAT('Tipo ', t.name, ' incompatible con ', r.tipo)
                WHEN c.is_nullable <> r.es_null THEN CONCAT('Nulabilidad ', CASE WHEN c.is_nullable = 1 THEN 'NULL' ELSE 'NOT NULL' END, ' incompatible con requerido ', CASE WHEN r.es_null = 1 THEN 'NULL' ELSE 'NOT NULL' END)
                WHEN r.tipo IN ('varchar', 'nvarchar') AND c.max_length <> -1 AND c.max_length < r.min_len THEN CONCAT('Longitud ', c.max_length, ' menor a requerida ', r.min_len)
                WHEN r.tipo = 'decimal' AND (c.scale < r.req_scale OR (c.precision - c.scale) < (r.req_prec - r.req_scale)) THEN CONCAT('Capacidad decimal insuficiente: decimal(', c.precision, ',', c.scale, ')')
                WHEN r.tipo = 'datetime2' AND c.scale < r.req_scale THEN CONCAT('Escala datetime2(', c.scale, ') menor a datetime2(', r.req_scale, ')')
                ELSE 'Incompatible'
            END AS detalle
        FROM (VALUES
            ('KeyFactPayer',        'bigint',    0, 0,  19, 0),
            ('id_pago_origen',      'int',       0, 0,  10, 0),
            ('id_reserva_origen',   'int',       0, 0,  10, 0),
            ('KeyTiempoPago',       'int',       0, 0,  10, 0),
            ('KeyTiempoValidacion', 'int',       0, 0,  10, 0),
            ('KeyHora',             'int',       0, 0,  10, 0),
            ('KeySede',             'int',       0, 0,  10, 0),
            ('KeyServicio',         'int',       0, 0,  10, 0),
            ('KeyPasarela',         'int',       0, 0,  10, 0),
            ('KeyCobro',            'int',       0, 0,  10, 0),
            ('KeyPersona',          'int',       0, 0,  10, 0),
            ('PagosRegistrados',    'int',       0, 0,  10, 0),
            ('PagosValidados',      'int',       0, 0,  10, 0),
            ('PagosPendientes',     'int',       0, 0,  10, 0),
            ('PagosRechazados',     'int',       0, 0,  10, 0),
            ('ImporteTotalCobro',   'decimal',   0, 0,  10, 2),
            ('ImportePendiente',    'decimal',   0, 0,  10, 2),
            ('ImporteRechazado',    'decimal',   0, 0,  10, 2),
            ('IndicadorMoneda',     'varchar',   0, 30, 0,  0),
            ('TiempoValidacionMin', 'int',       1, 0,  10, 0),
            ('EsPagoSinAnticipo',   'bit',       0, 0,  0,  0),
            ('BatchId',             'varchar',   0, 50, 0,  0),
            ('FechaCarga',          'datetime2', 0, 0,  27, 7),
            ('FechaModificacion',   'datetime2', 1, 0,  27, 7),
            ('UsuarioCarga',        'varchar',   0, 50, 0,  0)
        ) AS r(col, tipo, es_null, min_len, req_prec, req_scale)
        LEFT JOIN sys.columns c ON c.object_id = OBJECT_ID('dbo.Fact_GestionPayer') AND c.name = r.col
        LEFT JOIN sys.types t ON c.user_type_id = t.user_type_id
        WHERE c.column_id IS NULL
           OR t.name <> r.tipo
           OR c.is_nullable <> r.es_null
           OR (r.tipo IN ('varchar', 'nvarchar') AND c.max_length <> -1 AND c.max_length < r.min_len)
           OR (r.tipo = 'decimal' AND (c.scale < r.req_scale OR (c.precision - c.scale) < (r.req_prec - r.req_scale)))
           OR (r.tipo = 'datetime2' AND c.scale < r.req_scale)
    ) AS req;

    IF LEN(@ColsIncompatiblesPayer) > 0
        SET @ErroresPreval += '- dbo.Fact_GestionPayer preexistente presenta columnas faltantes o especificaciones incompatibles: ' + SUBSTRING(@ColsIncompatiblesPayer, 1, LEN(@ColsIncompatiblesPayer)-1) + '.' + CHAR(13) + CHAR(10);
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.9 Validación de Log_Ejecucion_ETL (debe existir, creada por Mario en Entregable 15)
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
        ('BatchId',       'varchar/nvarchar(>=50)'),
        ('TipoEvento',    'varchar/nvarchar(>=30)'),
        ('Mensaje',       'varchar/nvarchar(>=500 o MAX)'),
        ('LineaError',    'int/bigint'),
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
        SET @ErroresPreval += '- dbo.Log_Ejecucion_ETL preexistente presenta columnas faltantes: ' + SUBSTRING(@ColsFaltantesLog, 1, LEN(@ColsFaltantesLog)-1) + '.' + CHAR(13) + CHAR(10);
END
ELSE
BEGIN
    -- Log_Ejecucion_ETL es prerrequisito creado por Mario (Entregable 15). Sin ella el script no puede continuar.
    SET @ErroresPreval += '- CRÍTICO: dbo.Log_Ejecucion_ETL no existe. Ejecutar primero Entregables/15. ETL_Fact_CaptacionBuyer_h3.sql.' + CHAR(13) + CHAR(10);
END;

-- ----------------------------------------------------------------------------------------------------
-- 1.10 Dictamen y Detención Segura del Script (SET NOEXEC ON)
-- ----------------------------------------------------------------------------------------------------
IF LEN(@ErroresPreval) > 0
BEGIN
    DECLARE @MensajeErrorPreval VARCHAR(MAX) = 'ABORTANDO DESPLIEGUE ETL PAYER POR DEPENDENCIAS FALTANTES O ESTRUCTURA INCOMPATIBLE:' + CHAR(13) + CHAR(10) + @ErroresPreval;
    RAISERROR(@MensajeErrorPreval, 16, 1);
    -- En entornos interactivos o sin SQLCMD -b, SET NOEXEC ON impide que los lotes posteriores se ejecuten
    SET NOEXEC ON;
END
ELSE
BEGIN
    PRINT '>> Prevalidación dimensional superada exitosamente.';
END;
GO

-- ====================================================================================================
-- LOTE 2: DDL DE OBJETOS AUXILIARES Y TABLA DE HECHOS (CON RESTRICCIONES CONTRACTUALES)
-- ====================================================================================================

-- ----------------------------------------------------------------------------------------------------
-- 2.1 Detección y Manejo de versión H2 de Fact_GestionPayer (si existiera)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Fact_GestionPayer', 'U') IS NOT NULL
BEGIN
    -- Verificar si tiene la columna KeyFactPayer (versión H3)
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Fact_GestionPayer') AND name = 'KeyFactPayer')
    BEGIN
        PRINT '>> ADVERTENCIA CRÍTICA: dbo.Fact_GestionPayer existe en versión H2 (sin KeyFactPayer).';
        PRINT '>> No se modifica destructivamente. Coordinación requerida con el equipo (especialmente Alessandro, Integrante 2).';
        PRINT '>> Para migrar a H3: ejecute el script de migración segura o recrear en entorno de prueba aislado.';
        PRINT '>> En producción real: ALTER TABLE ADD COLUMN de forma no destructiva, manteniendo datos.';
        PRINT '>> ACCIÓN REQUERIDA: El despliege ha sido detenido de forma segura.';
        -- NO se hace DROP ni ALTER destructivo en producción
        -- En entorno aislado de prueba se puede recrear eliminando primero la tabla manualmente
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        PRINT '>> dbo.Fact_GestionPayer ya existe con estructura H3 compatible (KeyFactPayer presente). Continuando.';
    END;
END;
GO

-- ----------------------------------------------------------------------------------------------------
-- 2.2 Tabla de Rechazos ETL Payer (idempotente)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Rechazos_ETL_Payer', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Rechazos_ETL_Payer (
        RechazoId       BIGINT IDENTITY(1,1) NOT NULL,
        EntidadOrigenId INT NOT NULL,           -- id_pago rechazado
        MotivoRechazo   VARCHAR(150) NOT NULL,
        DetalleRechazo  VARCHAR(MAX) NULL,
        BatchId         VARCHAR(50) NOT NULL,
        FechaRechazo    DATETIME2(7) NOT NULL CONSTRAINT DF_RechazosPayer_Fecha DEFAULT GETDATE(),
        CONSTRAINT PK_Rechazos_ETL_Payer PRIMARY KEY CLUSTERED (RechazoId)
    );
    PRINT '>> Tabla dbo.Rechazos_ETL_Payer creada exitosamente.';
END
ELSE
BEGIN
    PRINT '>> La tabla dbo.Rechazos_ETL_Payer ya existe con estructura compatible.';
END;
GO

-- ----------------------------------------------------------------------------------------------------
-- 2.3 Tabla de Hechos: dbo.Fact_GestionPayer (idempotente — solo crea si no existe)
-- ----------------------------------------------------------------------------------------------------
IF OBJECT_ID('dbo.Fact_GestionPayer', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Fact_GestionPayer (
        -- Clave Surrogada de Hecho (identidad autoincremental)
        KeyFactPayer        BIGINT IDENTITY(1,1) NOT NULL,

        -- Clave Natural de Idempotencia (grano: 1 fila por id_pago)
        id_pago_origen      INT NOT NULL,
        id_reserva_origen   INT NOT NULL CONSTRAINT DF_FactPayer_Reserva DEFAULT 0,

        -- Claves Foráneas Dimensionales
        KeyTiempoPago       INT NOT NULL,
        KeyTiempoValidacion INT NOT NULL CONSTRAINT DF_FactPayer_TiempoVal DEFAULT 0,
        KeyHora             INT NOT NULL CONSTRAINT DF_FactPayer_Hora DEFAULT 0,
        KeySede             INT NOT NULL CONSTRAINT DF_FactPayer_Sede DEFAULT 0,
        KeyServicio         INT NOT NULL CONSTRAINT DF_FactPayer_Servicio DEFAULT 0,
        KeyFuente           INT NOT NULL CONSTRAINT DF_FactPayer_Fuente DEFAULT 0,
        KeyCampana          INT NOT NULL CONSTRAINT DF_FactPayer_Campana DEFAULT 0,
        KeyPasarela         INT NOT NULL CONSTRAINT DF_FactPayer_Pasarela DEFAULT 0,
        KeyCobro            INT NOT NULL CONSTRAINT DF_FactPayer_Cobro DEFAULT 0,
        KeyPersona          INT NOT NULL CONSTRAINT DF_FactPayer_Persona DEFAULT 0,

        -- Métricas Aditivas de Gestión de Pagos
        PagosRegistrados    INT NOT NULL CONSTRAINT DF_FactPayer_PagosReg DEFAULT 1,    -- Siempre 1 (grano por pago)
        PagosValidados      INT NOT NULL CONSTRAINT DF_FactPayer_PagosVal DEFAULT 0,    -- 1 si estado = Validado
        PagosPendientes     INT NOT NULL CONSTRAINT DF_FactPayer_PagosPen DEFAULT 0,    -- 1 si estado = Pendiente
        PagosRechazados     INT NOT NULL CONSTRAINT DF_FactPayer_PagosRech DEFAULT 0,   -- 1 si estado = Rechazado

        -- Métricas Monetarias (separadas por estado, regla 1-3)
        ImporteTotalCobro   DECIMAL(10,2) NOT NULL CONSTRAINT DF_FactPayer_ImpTotal DEFAULT 0.00,  -- Solo si Validado
        ImportePendiente    DECIMAL(10,2) NOT NULL CONSTRAINT DF_FactPayer_ImpPen DEFAULT 0.00,    -- Solo si Pendiente
        ImporteRechazado    DECIMAL(10,2) NOT NULL CONSTRAINT DF_FactPayer_ImpRech DEFAULT 0.00,   -- Solo si Rechazado

        -- Indicador de Moneda (OBLIGATORIO por política — nunca asumir PEN ni USD)
        IndicadorMoneda     VARCHAR(30) NOT NULL CONSTRAINT DF_FactPayer_Moneda DEFAULT 'MonedaNoVerificada',

        -- Métricas Temporales de Proceso
        TiempoValidacionMin INT NULL,                                                   -- NULL si sin datos suficientes
        EsPagoSinAnticipo   BIT NOT NULL CONSTRAINT DF_FactPayer_SinAnticipo DEFAULT 0,

        -- Metadatos de Auditoría ETL
        BatchId             VARCHAR(50) NOT NULL,
        FechaCarga          DATETIME2(7) NOT NULL CONSTRAINT DF_FactPayer_FechaCarga DEFAULT GETDATE(),
        FechaModificacion   DATETIME2(7) NULL,                                          -- NULL en inserciones, GETDATE() en updates
        UsuarioCarga        VARCHAR(50) NOT NULL CONSTRAINT DF_FactPayer_Usuario DEFAULT SYSTEM_USER,

        -- Restricciones Contractuales
        CONSTRAINT PK_Fact_GestionPayer PRIMARY KEY CLUSTERED (KeyFactPayer),
        CONSTRAINT UQ_Fact_GestionPayer_Origen UNIQUE NONCLUSTERED (id_pago_origen),

        -- Integridad referencial dimensional
        CONSTRAINT FK_FactPayer_TiempoPago FOREIGN KEY (KeyTiempoPago)       REFERENCES dbo.Dim_Tiempo(KeyTiempo),
        CONSTRAINT FK_FactPayer_TiempoVal  FOREIGN KEY (KeyTiempoValidacion)  REFERENCES dbo.Dim_Tiempo(KeyTiempo),
        CONSTRAINT FK_FactPayer_Hora       FOREIGN KEY (KeyHora)              REFERENCES dbo.Dim_Hora(KeyHora),
        CONSTRAINT FK_FactPayer_Sede       FOREIGN KEY (KeySede)              REFERENCES dbo.Dim_Sede(KeySede),
        CONSTRAINT FK_FactPayer_Servicio   FOREIGN KEY (KeyServicio)          REFERENCES dbo.Dim_Servicio(KeyServicio),
        CONSTRAINT FK_FactPayer_Pasarela   FOREIGN KEY (KeyPasarela)          REFERENCES dbo.Dim_Pasarela(KeyPasarela),
        CONSTRAINT FK_FactPayer_Cobro      FOREIGN KEY (KeyCobro)             REFERENCES dbo.Dim_Cobro(KeyCobro),
        CONSTRAINT FK_FactPayer_Persona    FOREIGN KEY (KeyPersona)           REFERENCES dbo.Dim_Persona(KeyPersona)
    );

    -- Índices secundarios para soporte analítico
    CREATE NONCLUSTERED INDEX IX_FactPayer_TiempoPago
        ON dbo.Fact_GestionPayer (KeyTiempoPago)
        INCLUDE (ImporteTotalCobro, PagosValidados);

    CREATE NONCLUSTERED INDEX IX_FactPayer_TiempoVal
        ON dbo.Fact_GestionPayer (KeyTiempoValidacion)
        INCLUDE (TiempoValidacionMin);

    CREATE NONCLUSTERED INDEX IX_FactPayer_Persona
        ON dbo.Fact_GestionPayer (KeyPersona)
        INCLUDE (PagosRegistrados, ImporteTotalCobro);

    CREATE NONCLUSTERED INDEX IX_FactPayer_Batch
        ON dbo.Fact_GestionPayer (BatchId)
        INCLUDE (FechaCarga);

    PRINT '>> Tabla dbo.Fact_GestionPayer creada exitosamente con todas sus restricciones contractuales e índices analíticos.';
END
ELSE
BEGIN
    PRINT '>> La tabla dbo.Fact_GestionPayer ya existe con estructura H3 compatible.';
END;
GO

-- ====================================================================================================
-- LOTE 3: PROCEDIMIENTO ALMACENADO DE CARGA: dbo.usp_Cargar_Fact_GestionPayer
-- ====================================================================================================

CREATE OR ALTER PROCEDURE dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte         DATE,
    @BatchId            VARCHAR(50),
    @Insertados         INT = 0 OUTPUT,
    @Actualizados       INT = 0 OUTPUT,
    @SinCambio          INT = 0 OUTPUT,
    @Rechazados         INT = 0 OUTPUT,
    @Pendientes         INT = 0 OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;

    -- ------------------------------------------------------------------------------------------------
    -- 1. Inicialización obligatoria de contadores de salida
    -- ------------------------------------------------------------------------------------------------
    SET @Insertados  = 0;
    SET @Actualizados = 0;
    SET @SinCambio   = 0;
    SET @Rechazados  = 0;
    SET @Pendientes  = 0;

    -- ------------------------------------------------------------------------------------------------
    -- 2. Validación de Parámetros de Entrada
    -- ------------------------------------------------------------------------------------------------
    IF @FechaCorte IS NULL OR @BatchId IS NULL OR LTRIM(RTRIM(@BatchId)) = ''
    BEGIN
        RAISERROR('Error de Parámetros: @FechaCorte y @BatchId son obligatorios y no pueden ser nulos ni vacíos.', 16, 1);
        RETURN -1;
    END;

    -- ------------------------------------------------------------------------------------------------
    -- 3. Cálculo del Instante de Evaluación (Intervalo Semiabierto Exclusivo)
    --    Todos los pagos con fecha_registro < @InstanteEvaluacion son candidatos de este lote.
    -- ------------------------------------------------------------------------------------------------
    DECLARE @InstanteEvaluacion DATETIME2(0) = DATEADD(day, 1, CAST(@FechaCorte AS DATETIME2(0)));

    -- ------------------------------------------------------------------------------------------------
    -- 4. Prevalidación en Tiempo de Ejecución de Dependencias Bloqueantes
    -- ------------------------------------------------------------------------------------------------

    -- 4.1 Vista de staging
    IF OBJECT_ID('staging.stg_Pagos', 'V') IS NULL
    BEGIN
        RAISERROR('Error de Dependencias: La vista staging.stg_Pagos no existe. Ejecutar primero Entregables/18. Staging_payer_h3.sql.', 16, 1);
        RETURN -1;
    END;

    -- 4.2 Existencia de todas las dimensiones requeridas
    IF    OBJECT_ID('dbo.Dim_Tiempo',    'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Hora',      'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Sede',      'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Servicio',  'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Pasarela',  'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Cobro',     'U') IS NULL
       OR OBJECT_ID('dbo.Dim_Persona',   'U') IS NULL
    BEGIN
        RAISERROR('Error de Dependencias: Una o más dimensiones requeridas no existen físicamente en el catálogo.', 16, 1);
        RETURN -1;
    END;

    -- 4.3 Existencia de miembros desconocidos (Key = 0) en todas las dimensiones
    IF    NOT EXISTS (SELECT 1 FROM dbo.Dim_Tiempo   WHERE KeyTiempo   = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Hora     WHERE KeyHora     = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Sede     WHERE KeySede     = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Servicio WHERE KeyServicio = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Pasarela WHERE KeyPasarela = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Cobro    WHERE KeyCobro    = 0)
       OR NOT EXISTS (SELECT 1 FROM dbo.Dim_Persona  WHERE KeyPersona  = 0)
    BEGIN
        RAISERROR('Error de Dependencias: Uno o más miembros desconocidos (Key = 0) no existen en las dimensiones. Abortando.', 16, 1);
        RETURN -1;
    END;

    -- 4.4 Existencia de la tabla de hechos destino
    IF OBJECT_ID('dbo.Fact_GestionPayer', 'U') IS NULL
    BEGIN
        RAISERROR('Error de Dependencias: La tabla dbo.Fact_GestionPayer no existe. Ejecutar primero el Lote 2 de este script.', 16, 1);
        RETURN -1;
    END;

    -- ------------------------------------------------------------------------------------------------
    -- 4.5 Registro de INICIO en bitácora
    -- ------------------------------------------------------------------------------------------------
    BEGIN TRY
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError, FechaRegistro)
        VALUES (
            'dbo.usp_Cargar_Fact_GestionPayer',
            @BatchId,
            'INICIO',
            CONCAT('Iniciando carga Fact_GestionPayer. FechaCorte: ', CONVERT(VARCHAR(10), @FechaCorte, 120),
                   ', InstanteEvaluacion: ', CONVERT(VARCHAR(19), @InstanteEvaluacion, 120)),
            NULL,
            GETDATE()
        );
    END TRY
    BEGIN CATCH
        -- No bloquear si falla el log de inicio; continuar con la carga
    END CATCH;

    -- ------------------------------------------------------------------------------------------------
    -- 5. Preparación de la Tabla Temporal Intermedia
    -- ------------------------------------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#Stg_Payer_Intermedio') IS NOT NULL
        DROP TABLE #Stg_Payer_Intermedio;

    CREATE TABLE #Stg_Payer_Intermedio (
        -- Identificadores de negocio (Natural Keys)
        id_pago             INT NOT NULL,
        id_persona          INT NULL,
        id_reserva          INT NULL,
        id_solicitud        INT NULL,
        id_servicio         INT NULL,
        id_sede             INT NULL,
        id_profesional      INT NULL,

        -- Fechas y claves de tiempo del staging
        fecha_registro      DATETIME2(7) NULL,
        fecha_validacion    DATETIME2(7) NULL,
        KeyTiempoPago_stg   INT NULL,               -- Precomputada en el staging
        KeyTiempoVal_stg    INT NULL,               -- Precomputada en el staging
        KeyHoraPago_stg     INT NULL,               -- Precomputada en el staging

        -- Atributos de negocio normalizados
        estado_pago_norm    VARCHAR(20) NOT NULL DEFAULT 'Desconocido',
        importe             DECIMAL(10,2) NULL,
        canal_pago_norm     VARCHAR(50) NULL,
        tiene_comprobante   BIT NOT NULL DEFAULT 0,

        -- Indicadores de estado (BIT)
        es_pago_validado    BIT NOT NULL DEFAULT 0,
        es_pago_pendiente   BIT NOT NULL DEFAULT 0,
        es_pago_rechazado   BIT NOT NULL DEFAULT 0,
        es_pago_sin_anticipo BIT NOT NULL DEFAULT 0,

        -- Claves dimensionales resueltas (se inicializan en 0 = desconocido)
        KeyTiempoPago       INT NOT NULL DEFAULT 0,
        KeyTiempoValidacion INT NOT NULL DEFAULT 0,
        KeyHora             INT NOT NULL DEFAULT 0,
        KeySede             INT NOT NULL DEFAULT 0,
        KeyServicio         INT NOT NULL DEFAULT 0,
        KeyFuente           INT NOT NULL DEFAULT 0,
        KeyCampana          INT NOT NULL DEFAULT 0,
        KeyPasarela         INT NOT NULL DEFAULT 0,
        KeyCobro            INT NOT NULL DEFAULT 0,
        KeyPersona          INT NOT NULL DEFAULT 0,

        -- Métricas derivadas calculadas en este procedimiento
        ImporteValidado     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        ImportePendiente    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        ImporteRechazado    DECIMAL(10,2) NOT NULL DEFAULT 0.00,
        TiempoValidacionMin INT NULL,

        -- Auditoría interna de resolución dimensional
        EstadoValidacion    VARCHAR(50) NOT NULL DEFAULT 'Valido',
        MotivoRechazo       VARCHAR(150) NULL,
        DetalleRechazo      VARCHAR(MAX) NULL,
        ClasificacionAccion VARCHAR(20) NOT NULL DEFAULT 'SinClasificar'
    );

    -- ------------------------------------------------------------------------------------------------
    -- 6. Extracción desde staging.stg_Pagos con corte semiabierto (< @InstanteEvaluacion)
    -- ------------------------------------------------------------------------------------------------
    -- NOTA: fecha_registro puede venir NULL si el dato original es inválido. Los registros con
    --       fecha_registro IS NULL se capturan aquí y se rechazan en el paso de marcado (7.1).
    INSERT INTO #Stg_Payer_Intermedio (
        id_pago,
        id_persona,
        id_reserva,
        id_solicitud,
        id_servicio,
        id_sede,
        id_profesional,
        fecha_registro,
        fecha_validacion,
        KeyTiempoPago_stg,
        KeyTiempoVal_stg,
        KeyHoraPago_stg,
        estado_pago_norm,
        importe,
        canal_pago_norm,
        tiene_comprobante,
        es_pago_validado,
        es_pago_pendiente,
        es_pago_rechazado,
        es_pago_sin_anticipo
    )
    SELECT
        stg.id_pago,
        stg.id_persona,
        stg.id_reserva,
        stg.id_solicitud,
        stg.id_servicio,
        stg.id_sede,
        stg.id_profesional,
        stg.fecha_registro,
        stg.fecha_validacion,
        stg.KeyTiempoPago,
        stg.KeyTiempoValidacion,
        stg.KeyHoraPago,
        stg.estado_pago_norm,
        stg.importe,
        stg.canal_pago_norm,
        stg.tiene_comprobante,
        stg.es_pago_validado,
        stg.es_pago_pendiente,
        stg.es_pago_rechazado,
        stg.es_pago_sin_anticipo
    FROM staging.stg_Pagos stg
    WHERE stg.fecha_registro < @InstanteEvaluacion
       OR stg.fecha_registro IS NULL;   -- Se incluyen para rechazarlos luego con 'FechaRegistroNula'

    -- Verificación de Invariante de Grano: exactamente 1 fila por id_pago
    IF EXISTS (SELECT id_pago FROM #Stg_Payer_Intermedio GROUP BY id_pago HAVING COUNT(*) > 1)
    BEGIN
        RAISERROR('Invariante de Grano Violado: Se encontraron id_pago duplicados en la tabla intermedia del staging.', 16, 1);
        RETURN -1;
    END;

    -- ------------------------------------------------------------------------------------------------
    -- 7. Marcado de Registros Problemáticos (rechazos directos y anomalías)
    -- ------------------------------------------------------------------------------------------------

    -- 7.1 Rechazo: fecha_registro IS NULL (no se puede asignar KeyTiempoPago)
    UPDATE t
    SET
        t.EstadoValidacion  = 'FechaRegistroNula',
        t.MotivoRechazo     = 'FechaRegistroNula',
        t.DetalleRechazo    = CONCAT('id_pago = ', t.id_pago, ': fecha_registro es NULL. No es posible asignar dimensión de tiempo.'),
        t.ClasificacionAccion = 'Rechazada'
    FROM #Stg_Payer_Intermedio t
    WHERE t.fecha_registro IS NULL
      AND t.ClasificacionAccion = 'SinClasificar';

    -- 7.2 Rechazo: importe <= 0 (regla monetaria obligatoria)
    UPDATE t
    SET
        t.EstadoValidacion  = 'ImporteInvalido',
        t.MotivoRechazo     = 'ImporteNegativoOCero',
        t.DetalleRechazo    = CONCAT('id_pago = ', t.id_pago, ': importe = ', ISNULL(CAST(t.importe AS VARCHAR(20)), 'NULL'), '. Los pagos con importe <= 0 son rechazados por política.'),
        t.ClasificacionAccion = 'Rechazada'
    FROM #Stg_Payer_Intermedio t
    WHERE (t.importe IS NULL OR t.importe <= 0.00)
      AND t.ClasificacionAccion = 'SinClasificar';

    -- 7.3 Rechazo: estado_pago_norm = 'Desconocido' (no mapeable a ninguna dimensión de cobro)
    UPDATE t
    SET
        t.EstadoValidacion  = 'EstadoDesconocido',
        t.MotivoRechazo     = 'EstadoPagoDesconocido',
        t.DetalleRechazo    = CONCAT('id_pago = ', t.id_pago, ': estado_pago_norm = ''Desconocido''. No corresponde a ningún estado de pago válido.'),
        t.ClasificacionAccion = 'Rechazada'
    FROM #Stg_Payer_Intermedio t
    WHERE t.estado_pago_norm = 'Desconocido'
      AND t.ClasificacionAccion = 'SinClasificar';

    -- 7.4 Anomalía Cronológica: fecha_validacion < fecha_registro (registrar pero NO rechazar)
    --     Se fija TiempoValidacionMin = NULL. El registro sigue avanzando en el pipeline.
    UPDATE t
    SET
        t.EstadoValidacion = 'AnomaliaCronologicaValidacion',
        t.MotivoRechazo    = CONCAT('ADVERTENCIA AnomaliaCronologica: fecha_validacion (', CONVERT(VARCHAR(19), t.fecha_validacion, 120), ') < fecha_registro (', CONVERT(VARCHAR(19), t.fecha_registro, 120), ')'),
        t.DetalleRechazo   = CONCAT('id_pago = ', t.id_pago, ': Fecha de validacion anterior a fecha de registro. TiempoValidacionMin fijado a NULL. Registro procesado igualmente.')
        -- NOTA: NO se modifica ClasificacionAccion aquí; la anomalía se anota pero no bloquea el registro
    FROM #Stg_Payer_Intermedio t
    WHERE t.fecha_validacion IS NOT NULL
      AND t.fecha_registro IS NOT NULL
      AND t.fecha_validacion < t.fecha_registro
      AND t.ClasificacionAccion = 'SinClasificar';

    -- ------------------------------------------------------------------------------------------------
    -- 8. Cálculo de Métricas Derivadas para Registros No Rechazados
    -- ------------------------------------------------------------------------------------------------
    UPDATE t
    SET
        -- Métricas monetarias separadas por estado (reglas 1-3)
        t.ImporteValidado   = CASE WHEN t.es_pago_validado  = 1 THEN t.importe ELSE 0.00 END,
        t.ImportePendiente  = CASE WHEN t.es_pago_pendiente = 1 THEN t.importe ELSE 0.00 END,
        t.ImporteRechazado  = CASE WHEN t.es_pago_rechazado = 1 THEN t.importe ELSE 0.00 END,

        -- Tiempo de validación en minutos (regla 5: SOLO si ambas fechas existen Y validacion >= registro)
        t.TiempoValidacionMin = CASE
            WHEN t.fecha_validacion IS NOT NULL
             AND t.fecha_registro IS NOT NULL
             AND t.fecha_validacion >= t.fecha_registro
            THEN DATEDIFF(MINUTE, t.fecha_registro, t.fecha_validacion)
            ELSE NULL
        END
    FROM #Stg_Payer_Intermedio t
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- ------------------------------------------------------------------------------------------------
    -- 9. Resolución Dimensional con Detección de Ambigüedad (cnt = 0 / cnt = 1 / cnt > 1)
    --    SOLO se aplica a registros no rechazados (ClasificacionAccion = 'SinClasificar')
    -- ------------------------------------------------------------------------------------------------

    -- 9.1 KeyTiempoPago (Dim_Tiempo por fecha_registro como DATE)
    --     Si el staging proveyó KeyTiempoPago_stg válido > 0, usarlo directamente para eficiencia.
    --     Si no, buscar por id_fecha. Si no encuentra → PendienteDimensionH2 (no rechazar, dimensión no poblada).
    UPDATE t
    SET
        t.KeyTiempoPago = CASE
            WHEN t.KeyTiempoPago_stg IS NOT NULL AND t.KeyTiempoPago_stg > 0 THEN t.KeyTiempoPago_stg
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0
        END,
        t.EstadoValidacion = CASE
            WHEN (t.KeyTiempoPago_stg IS NULL OR t.KeyTiempoPago_stg = 0) AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            WHEN (t.KeyTiempoPago_stg IS NULL OR t.KeyTiempoPago_stg = 0) AND lkp.cnt IS NULL THEN 'PendienteDimensionH2'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN (t.KeyTiempoPago_stg IS NULL OR t.KeyTiempoPago_stg = 0) AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Tiempo tiene múltiples filas para fecha_registro'
            WHEN (t.KeyTiempoPago_stg IS NULL OR t.KeyTiempoPago_stg = 0) AND lkp.cnt IS NULL THEN 'PendienteDimensionH2: Fecha de registro ausente en Dim_Tiempo'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN (t.KeyTiempoPago_stg IS NULL OR t.KeyTiempoPago_stg = 0) AND lkp.cnt > 1 THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.fecha_registro AS DATE), 120), ' tiene ', lkp.cnt, ' filas en Dim_Tiempo.')
            WHEN (t.KeyTiempoPago_stg IS NULL OR t.KeyTiempoPago_stg = 0) AND lkp.cnt IS NULL THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.fecha_registro AS DATE), 120), ' no existe en Dim_Tiempo.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT id_fecha, COUNT(*) AS cnt, MIN(KeyTiempo) AS min_key
        FROM dbo.Dim_Tiempo
        GROUP BY id_fecha
    ) lkp ON lkp.id_fecha = CAST(t.fecha_registro AS DATE)
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- 9.2 KeyTiempoValidacion (Dim_Tiempo por fecha_validacion como DATE, 0 si NULL)
    UPDATE t
    SET
        t.KeyTiempoValidacion = CASE
            WHEN t.fecha_validacion IS NULL THEN 0
            WHEN t.KeyTiempoVal_stg IS NOT NULL AND t.KeyTiempoVal_stg > 0 THEN t.KeyTiempoVal_stg
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0
        END,
        t.EstadoValidacion = CASE
            WHEN t.fecha_validacion IS NOT NULL
             AND (t.KeyTiempoVal_stg IS NULL OR t.KeyTiempoVal_stg = 0)
             AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            WHEN t.fecha_validacion IS NOT NULL
             AND (t.KeyTiempoVal_stg IS NULL OR t.KeyTiempoVal_stg = 0)
             AND lkp.cnt IS NULL THEN 'PendienteDimensionH2'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN t.fecha_validacion IS NOT NULL AND (t.KeyTiempoVal_stg IS NULL OR t.KeyTiempoVal_stg = 0) AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Tiempo tiene múltiples filas para fecha_validacion'
            WHEN t.fecha_validacion IS NOT NULL AND (t.KeyTiempoVal_stg IS NULL OR t.KeyTiempoVal_stg = 0) AND lkp.cnt IS NULL THEN 'PendienteDimensionH2: Fecha de validacion ausente en Dim_Tiempo'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN t.fecha_validacion IS NOT NULL AND (t.KeyTiempoVal_stg IS NULL OR t.KeyTiempoVal_stg = 0) AND lkp.cnt > 1 THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.fecha_validacion AS DATE), 120), ' tiene ', lkp.cnt, ' filas en Dim_Tiempo.')
            WHEN t.fecha_validacion IS NOT NULL AND (t.KeyTiempoVal_stg IS NULL OR t.KeyTiempoVal_stg = 0) AND lkp.cnt IS NULL THEN CONCAT('id_fecha = ', CONVERT(VARCHAR(10), CAST(t.fecha_validacion AS DATE), 120), ' no existe en Dim_Tiempo.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT id_fecha, COUNT(*) AS cnt, MIN(KeyTiempo) AS min_key
        FROM dbo.Dim_Tiempo
        GROUP BY id_fecha
    ) lkp ON lkp.id_fecha = CAST(t.fecha_validacion AS DATE)
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- 9.3 KeyHora (Dim_Hora por id_hora = HH*100+MM de fecha_registro, 0 si no encuentra)
    UPDATE t
    SET
        t.KeyHora = CASE
            WHEN t.KeyHoraPago_stg IS NOT NULL AND t.KeyHoraPago_stg > 0 THEN t.KeyHoraPago_stg
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0   -- Miss no critico: usar desconocido, no rechazar
        END,
        t.EstadoValidacion = CASE
            WHEN (t.KeyHoraPago_stg IS NULL OR t.KeyHoraPago_stg = 0) AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN (t.KeyHoraPago_stg IS NULL OR t.KeyHoraPago_stg = 0) AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Hora tiene múltiples filas para id_hora calculado'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN (t.KeyHoraPago_stg IS NULL OR t.KeyHoraPago_stg = 0) AND lkp.cnt > 1 THEN CONCAT('id_hora = ', DATEPART(HOUR, t.fecha_registro)*100 + DATEPART(MINUTE, t.fecha_registro), ' tiene ', lkp.cnt, ' filas en Dim_Hora.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT id_hora, COUNT(*) AS cnt, MIN(KeyHora) AS min_key
        FROM dbo.Dim_Hora
        WHERE id_hora IS NOT NULL
        GROUP BY id_hora
    ) lkp ON lkp.id_hora = (DATEPART(HOUR, t.fecha_registro)*100 + DATEPART(MINUTE, t.fecha_registro))
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- 9.4 KeySede (Dim_Sede por id_sede, 0 si NULL o no encontrado — NO rechazar)
    UPDATE t
    SET
        t.KeySede = CASE
            WHEN t.id_sede IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            WHEN lkp.cnt > 1 THEN 0    -- Ambiguo pero no critico: usar desconocido
            ELSE 0                      -- Miss: usar desconocido
        END,
        t.EstadoValidacion = CASE
            WHEN t.id_sede IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN t.id_sede IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Sede tiene múltiples filas para id_sede'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN t.id_sede IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('id_sede = ', t.id_sede, ' tiene ', lkp.cnt, ' filas en Dim_Sede. KeySede fijado a 0.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT id_sede, COUNT(*) AS cnt, MIN(KeySede) AS min_key
        FROM dbo.Dim_Sede
        WHERE id_sede IS NOT NULL
        GROUP BY id_sede
    ) lkp ON lkp.id_sede = t.id_sede
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- 9.5 KeyServicio (Dim_Servicio por id_servicio, 0 si NULL o no encontrado)
    UPDATE t
    SET
        t.KeyServicio = CASE
            WHEN t.id_servicio IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0
        END,
        t.EstadoValidacion = CASE
            WHEN t.id_servicio IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN t.id_servicio IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Servicio tiene múltiples filas para id_servicio'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN t.id_servicio IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('id_servicio = ', t.id_servicio, ' tiene ', lkp.cnt, ' filas en Dim_Servicio. KeyServicio fijado a 0.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT id_servicio, COUNT(*) AS cnt, MIN(KeyServicio) AS min_key
        FROM dbo.Dim_Servicio
        WHERE id_servicio IS NOT NULL
        GROUP BY id_servicio
    ) lkp ON lkp.id_servicio = t.id_servicio
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- 9.6 KeyPasarela (Dim_Pasarela por MetodoPago = canal_pago_norm, 0 si NULL o no encuentra)
    --     canal_pago_norm viene normalizado (UPPER TRIM) desde el staging
    UPDATE t
    SET
        t.KeyPasarela = CASE
            WHEN t.canal_pago_norm IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0
        END,
        t.EstadoValidacion = CASE
            WHEN t.canal_pago_norm IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN t.canal_pago_norm IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Pasarela tiene múltiples filas para canal_pago_norm'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN t.canal_pago_norm IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('canal_pago_norm = ''', t.canal_pago_norm, ''' tiene ', lkp.cnt, ' filas en Dim_Pasarela. KeyPasarela fijado a 0.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT MetodoPago, COUNT(*) AS cnt, MIN(KeyPasarela) AS min_key
        FROM dbo.Dim_Pasarela
        WHERE MetodoPago IS NOT NULL
        GROUP BY MetodoPago
    ) lkp ON lkp.MetodoPago = t.canal_pago_norm
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- 9.7 KeyCobro (Dim_Cobro por EstadoPago = estado_pago_norm Y ComprobanteAdjunto)
    --     Si ambiguo (cnt > 1) → rechazar (es inconsistencia en la dimensión).
    --     Si no encuentra (cnt IS NULL) → usar 0 (desconocido).
    UPDATE t
    SET
        t.KeyCobro = CASE
            WHEN lkp.cnt = 1 THEN lkp.min_key
            WHEN lkp.cnt > 1 THEN 0     -- Ambiguo: rechazar
            ELSE 0                       -- No encontrado: desconocido
        END,
        t.EstadoValidacion = CASE
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Cobro tiene múltiples filas para EstadoPago+ComprobanteAdjunto'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN lkp.cnt > 1 THEN CONCAT('EstadoPago = ''', t.estado_pago_norm, ''', ComprobanteAdjunto = ''', CASE WHEN t.tiene_comprobante = 1 THEN 'SI' ELSE 'NO' END, ''' tiene ', lkp.cnt, ' coincidencias en Dim_Cobro.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT EstadoPago, ComprobanteAdjunto, COUNT(*) AS cnt, MIN(KeyCobro) AS min_key
        FROM dbo.Dim_Cobro
        GROUP BY EstadoPago, ComprobanteAdjunto
    ) lkp ON lkp.EstadoPago = t.estado_pago_norm
         AND lkp.ComprobanteAdjunto = CASE WHEN t.tiene_comprobante = 1 THEN 'SI' ELSE 'NO' END
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- 9.8 KeyPersona (Dim_Persona por id_persona, 0 si NULL o no encontrado)
    UPDATE t
    SET
        t.KeyPersona = CASE
            WHEN t.id_persona IS NULL THEN 0
            WHEN lkp.cnt = 1 THEN lkp.min_key
            ELSE 0
        END,
        t.EstadoValidacion = CASE
            WHEN t.id_persona IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo'
            ELSE t.EstadoValidacion
        END,
        t.MotivoRechazo = CASE
            WHEN t.id_persona IS NOT NULL AND lkp.cnt > 1 THEN 'ErrorLookupAmbiguo: Dim_Persona tiene múltiples filas para id_persona'
            ELSE t.MotivoRechazo
        END,
        t.DetalleRechazo = CASE
            WHEN t.id_persona IS NOT NULL AND lkp.cnt > 1 THEN CONCAT('id_persona = ', t.id_persona, ' tiene ', lkp.cnt, ' filas en Dim_Persona. KeyPersona fijado a 0.')
            ELSE t.DetalleRechazo
        END
    FROM #Stg_Payer_Intermedio t
    LEFT JOIN (
        SELECT id_persona, COUNT(*) AS cnt, MIN(KeyPersona) AS min_key
        FROM dbo.Dim_Persona
        WHERE id_persona IS NOT NULL
        GROUP BY id_persona
    ) lkp ON lkp.id_persona = t.id_persona
    WHERE t.ClasificacionAccion = 'SinClasificar';

    -- ------------------------------------------------------------------------------------------------
    -- 10. Clasificación por Estado de Resolución Dimensional
    --     Rechazos críticos y pendientes se marcan antes de la transacción
    -- ------------------------------------------------------------------------------------------------
    UPDATE t
    SET t.ClasificacionAccion = CASE
        WHEN t.EstadoValidacion IN ('ErrorLookupAmbiguo', 'ImporteInvalido', 'EstadoDesconocido', 'FechaRegistroNula') THEN 'Rechazada'
        WHEN t.EstadoValidacion = 'PendienteDimensionH2' THEN 'Pendiente'
        ELSE t.ClasificacionAccion   -- Deja 'SinClasificar' para resolución final bajo bloqueo
    END
    FROM #Stg_Payer_Intermedio t
    WHERE t.ClasificacionAccion = 'SinClasificar'
      AND t.EstadoValidacion <> 'Valido'
      AND t.EstadoValidacion <> 'AnomaliaCronologicaValidacion'; -- La anomalía cronológica sigue avanzando

    -- ------------------------------------------------------------------------------------------------
    -- 11. Transacción Atómica con Bloqueo de Aplicación (sp_getapplock)
    -- ------------------------------------------------------------------------------------------------
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Adquisición del bloqueo exclusivo de aplicación
        DECLARE @ResLock INT;
        EXEC @ResLock = sp_getapplock
            @Resource    = 'ETL_Lock_Fact_GestionPayer',
            @LockMode    = 'Exclusive',
            @LockOwner   = 'Transaction',
            @LockTimeout = 30000;

        IF @ResLock < 0
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Error de Concurrencia: No se pudo adquirir el bloqueo exclusivo ETL_Lock_Fact_GestionPayer (código %d). Carga abortada.', 16, 1, @ResLock);
            RETURN -2;
        END;

        -- --------------------------------------------------------------------------------------------
        -- 11.1 Clasificación Final Protegida contra el Destino (bajo bloqueo)
        --      Compara staging con el estado actual de Fact_GestionPayer
        -- --------------------------------------------------------------------------------------------
        UPDATE src
        SET src.ClasificacionAccion = CASE
            WHEN dest.id_pago_origen IS NULL THEN 'Insertar'
            WHEN
                dest.KeyTiempoPago       <> src.KeyTiempoPago
             OR dest.KeyTiempoValidacion <> src.KeyTiempoValidacion
             OR dest.KeyHora             <> src.KeyHora
             OR dest.KeySede             <> src.KeySede
             OR dest.KeyServicio         <> src.KeyServicio
             OR dest.KeyPasarela         <> src.KeyPasarela
             OR dest.KeyCobro            <> src.KeyCobro
             OR dest.KeyPersona          <> src.KeyPersona
             OR dest.PagosValidados      <> src.es_pago_validado
             OR dest.PagosPendientes     <> src.es_pago_pendiente
             OR dest.PagosRechazados     <> src.es_pago_rechazado
             OR dest.ImporteTotalCobro   <> src.ImporteValidado
             OR dest.ImportePendiente    <> src.ImportePendiente
             OR dest.ImporteRechazado    <> src.ImporteRechazado
             OR dest.EsPagoSinAnticipo   <> src.es_pago_sin_anticipo
             OR (dest.TiempoValidacionMin <> src.TiempoValidacionMin
                 OR (dest.TiempoValidacionMin IS NULL AND src.TiempoValidacionMin IS NOT NULL)
                 OR (dest.TiempoValidacionMin IS NOT NULL AND src.TiempoValidacionMin IS NULL))
             OR dest.id_reserva_origen   <> ISNULL(src.id_reserva, 0)
            THEN 'Actualizar'
            ELSE 'SinCambio'
        END
        FROM #Stg_Payer_Intermedio src
        LEFT JOIN dbo.Fact_GestionPayer dest ON dest.id_pago_origen = src.id_pago
        WHERE src.ClasificacionAccion = 'SinClasificar';

        -- --------------------------------------------------------------------------------------------
        -- 11.2 Cálculo de Contadores Disjuntos
        -- --------------------------------------------------------------------------------------------
        SELECT
            @Insertados  = COUNT(CASE WHEN ClasificacionAccion = 'Insertar'   THEN 1 END),
            @Actualizados = COUNT(CASE WHEN ClasificacionAccion = 'Actualizar' THEN 1 END),
            @SinCambio   = COUNT(CASE WHEN ClasificacionAccion = 'SinCambio'  THEN 1 END),
            @Rechazados  = COUNT(CASE WHEN ClasificacionAccion = 'Rechazada'  THEN 1 END),
            @Pendientes  = COUNT(CASE WHEN ClasificacionAccion = 'Pendiente'  THEN 1 END)
        FROM #Stg_Payer_Intermedio;

        -- --------------------------------------------------------------------------------------------
        -- 11.3 Persistencia 1: Rechazos de Validación → dbo.Rechazos_ETL_Payer
        -- --------------------------------------------------------------------------------------------
        INSERT INTO dbo.Rechazos_ETL_Payer (
            EntidadOrigenId,
            MotivoRechazo,
            DetalleRechazo,
            BatchId,
            FechaRechazo
        )
        SELECT
            t.id_pago,
            ISNULL(t.MotivoRechazo, 'MotivoNoEspecificado'),
            t.DetalleRechazo,
            @BatchId,
            GETDATE()
        FROM #Stg_Payer_Intermedio t
        WHERE t.ClasificacionAccion = 'Rechazada';

        -- --------------------------------------------------------------------------------------------
        -- 11.4 Persistencia 2: Actualización In-Place SCD Tipo 1 (filas con diferencias)
        -- --------------------------------------------------------------------------------------------
        UPDATE dest
        SET
            dest.id_reserva_origen      = ISNULL(src.id_reserva, 0),
            dest.KeyTiempoPago          = src.KeyTiempoPago,
            dest.KeyTiempoValidacion    = src.KeyTiempoValidacion,
            dest.KeyHora                = src.KeyHora,
            dest.KeySede                = src.KeySede,
            dest.KeyServicio            = src.KeyServicio,
            dest.KeyPasarela            = src.KeyPasarela,
            dest.KeyCobro               = src.KeyCobro,
            dest.KeyPersona             = src.KeyPersona,
            dest.PagosRegistrados       = 1,
            dest.PagosValidados         = CAST(src.es_pago_validado  AS INT),
            dest.PagosPendientes        = CAST(src.es_pago_pendiente AS INT),
            dest.PagosRechazados        = CAST(src.es_pago_rechazado AS INT),
            dest.ImporteTotalCobro      = src.ImporteValidado,
            dest.ImportePendiente       = src.ImportePendiente,
            dest.ImporteRechazado       = src.ImporteRechazado,
            dest.IndicadorMoneda        = 'MonedaNoVerificada',   -- SIEMPRE fijo por política
            dest.TiempoValidacionMin    = src.TiempoValidacionMin,
            dest.EsPagoSinAnticipo      = src.es_pago_sin_anticipo,
            dest.BatchId                = @BatchId,
            dest.FechaModificacion      = GETDATE(),              -- Solo en updates
            dest.UsuarioCarga           = SYSTEM_USER
        FROM dbo.Fact_GestionPayer dest
        INNER JOIN #Stg_Payer_Intermedio src ON dest.id_pago_origen = src.id_pago
        WHERE src.ClasificacionAccion = 'Actualizar';

        -- --------------------------------------------------------------------------------------------
        -- 11.5 Persistencia 3: Inserción de Nuevos Registros
        -- --------------------------------------------------------------------------------------------
        INSERT INTO dbo.Fact_GestionPayer (
            id_pago_origen,
            id_reserva_origen,
            KeyTiempoPago,
            KeyTiempoValidacion,
            KeyHora,
            KeySede,
            KeyServicio,
            KeyFuente,
            KeyCampana,
            KeyPasarela,
            KeyCobro,
            KeyPersona,
            PagosRegistrados,
            PagosValidados,
            PagosPendientes,
            PagosRechazados,
            ImporteTotalCobro,
            ImportePendiente,
            ImporteRechazado,
            IndicadorMoneda,
            TiempoValidacionMin,
            EsPagoSinAnticipo,
            BatchId,
            FechaCarga,
            FechaModificacion,
            UsuarioCarga
        )
        SELECT
            src.id_pago,
            ISNULL(src.id_reserva, 0),
            src.KeyTiempoPago,
            src.KeyTiempoValidacion,
            src.KeyHora,
            src.KeySede,
            src.KeyServicio,
            src.KeyFuente,
            src.KeyCampana,
            src.KeyPasarela,
            src.KeyCobro,
            src.KeyPersona,
            1,                                            -- PagosRegistrados: siempre 1 por grano
            CAST(src.es_pago_validado  AS INT),
            CAST(src.es_pago_pendiente AS INT),
            CAST(src.es_pago_rechazado AS INT),
            src.ImporteValidado,
            src.ImportePendiente,
            src.ImporteRechazado,
            'MonedaNoVerificada',                         -- SIEMPRE por política obligatoria
            src.TiempoValidacionMin,
            src.es_pago_sin_anticipo,
            @BatchId,
            GETDATE(),
            NULL,                                         -- FechaModificacion NULL en inserciones
            SYSTEM_USER
        FROM #Stg_Payer_Intermedio src
        WHERE src.ClasificacionAccion = 'Insertar';

        -- --------------------------------------------------------------------------------------------
        -- 11.6 Registro de ÉXITO en bitácora
        -- --------------------------------------------------------------------------------------------
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError, FechaRegistro)
        VALUES (
            'dbo.usp_Cargar_Fact_GestionPayer',
            @BatchId,
            'EXITO',
            CONCAT('Carga completada exitosamente. Insertados: ', @Insertados,
                   ', Actualizados: ', @Actualizados,
                   ', SinCambio: ', @SinCambio,
                   ', Rechazados: ', @Rechazados,
                   ', Pendientes: ', @Pendientes),
            NULL,
            GETDATE()
        );

        -- Confirmación atómica (libera el bloqueo de aplicación automáticamente)
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        -- Si la transacción se revirtió, los contadores confirmados son estrictamente CERO
        SET @Insertados  = 0;
        SET @Actualizados = 0;
        SET @SinCambio   = 0;
        SET @Rechazados  = 0;
        SET @Pendientes  = 0;

        DECLARE @ErrNumero INT          = ERROR_NUMBER();
        DECLARE @ErrMensaje NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrLinea INT           = ERROR_LINE();

        BEGIN TRY
            INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError, FechaRegistro)
            VALUES (
                'dbo.usp_Cargar_Fact_GestionPayer',
                COALESCE(@BatchId, 'DESCONOCIDO'),
                'ERROR',
                CONCAT('Error ', @ErrNumero, ' en línea ', @ErrLinea, ': ', @ErrMensaje),
                @ErrLinea,
                GETDATE()
            );
        END TRY
        BEGIN CATCH
            -- No bloquear el THROW principal si falla el log de error
        END CATCH;

        THROW;
    END CATCH;

    -- ------------------------------------------------------------------------------------------------
    -- 12. Limpieza de Tabla Temporal
    -- ------------------------------------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#Stg_Payer_Intermedio') IS NOT NULL
        DROP TABLE #Stg_Payer_Intermedio;

    RETURN 0;
END;
GO

PRINT '>> Procedimiento almacenado dbo.usp_Cargar_Fact_GestionPayer creado exitosamente.';
GO

-- Restablecer el estado de compilación y ejecución al finalizar el script
SET NOEXEC OFF;
GO

-- ====================================================================================================
-- FIN DEL SCRIPT — Entregables/19. ETL_Fact_GestionPayer_h3.sql
-- ====================================================================================================
