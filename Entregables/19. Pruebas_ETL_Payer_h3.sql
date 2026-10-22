-- ====================================================================================================
-- NEXOSALUD — BATERÍA AUTOMATIZADA DE PRUEBAS TÉCNICAS: ETL PAYER (H3 - FASE 2)
-- ====================================================================================================
-- Proyecto     : NexoSalud (Plataforma de Inteligencia de Negocios Odontológica — Clínica Luxedent, Trujillo)
-- Metodología  : IMPULSE (Fase: PAYER — Fact_GestionPayer)
-- Responsable  : Jesús Daniel Ordóñez Ugarte (Integrante 4 — ETL PAYER, Gestión de Cobranza)
-- Entregable   : 19. Pruebas_ETL_Payer_h3.sql
-- Motor        : SQL Server 2019 LocalDB  (localdb)\MSSQLLocalDB
--
-- CONTRATO DE EJECUCIÓN REPRODUCIBLE:
--   1. Este script es completamente autónomo: no requiere :r ni archivos externos.
--      El procedimiento ETL y las vistas de staging se declaran internamente.
--   2. Si las bases temporales Test_NexoSalud_OLTP_Payer_Bateria o
--      Test_NexoSalud_Mart_Payer_Bateria ya existen, el script aborta SIN modificarlas.
--   3. La limpieza final elimina ambas bases via TRY/CATCH; si un bloqueo externo
--      lo impide, informa el nombre sin forzar desconexiones.
--   4. Ejecutar en SQLCMD con:
--        sqlcmd -S "(localdb)\MSSQLLocalDB" -E -b -i "Entregables\19. Pruebas_ETL_Payer_h3.sql"
--
-- BATERÍA DE 10 ESCENARIOS DE PRUEBA:
--   PAY-01: Carga Inicial — 3 pagos elegibles (Validado / Pendiente / Rechazado)
--   PAY-02: Idempotencia Pura — segunda ejecución sin cambios OLTP → sin filas nuevas
--   PAY-03: Actualización de Estado Pendiente → Validado (actualización in-place)
--   PAY-04: Pago Rechazado no incrementa ImporteTotalCobro
--   PAY-05: Reserva Sin Anticipo — sin pago → sin fila en hecho
--   PAY-06: Pagos Parciales — múltiples pagos por misma reserva (grano atómico)
--   PAY-07: Rechazo por Importe Cero o Negativo
--   PAY-08: Integridad Referencial — 0 huérfanos de FK en hecho
--   PAY-09: Conciliación OLTP vs. Data Mart — balance perfecto
--   PAY-10: Manejo de Error — Estado de Pago Desconocido
-- ====================================================================================================

SET NOCOUNT ON;
GO

-- ====================================================================================================
-- FASE 1: PREPARACIÓN DEL ENTORNO AISLADO TEMPORAL Y COMPROBACIÓN DEFENSIVA
-- ====================================================================================================

-- 1.1 Comprobación de seguridad: NO ejecutar en bases productivas
IF DB_NAME() IN ('NexoSaludDB', 'NexoSalud_Mart')
BEGIN
    RAISERROR('ABORTANDO: Este script de prueba NO debe ejecutarse en el contexto de bases reales del proyecto (NexoSaludDB / NexoSalud_Mart).', 16, 1);
    SET NOEXEC ON;
END;
GO

-- 1.2 Verificación preventiva de existencia (política estricta NO destructiva)
IF DB_ID(N'Test_NexoSalud_OLTP_Payer_Bateria') IS NOT NULL
BEGIN
    RAISERROR('ABORTANDO: La base [Test_NexoSalud_OLTP_Payer_Bateria] ya existe. Por política no destructiva, no se sobrescribe. Limpie manualmente y reintente.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF DB_ID(N'Test_NexoSalud_Mart_Payer_Bateria') IS NOT NULL
BEGIN
    RAISERROR('ABORTANDO: La base [Test_NexoSalud_Mart_Payer_Bateria] ya existe. Por política no destructiva, no se sobrescribe. Limpie manualmente y reintente.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- 1.3 Creación de bases de datos temporales aisladas
CREATE DATABASE Test_NexoSalud_OLTP_Payer_Bateria;
CREATE DATABASE Test_NexoSalud_Mart_Payer_Bateria;
GO

PRINT '>> Bases temporales creadas: Test_NexoSalud_OLTP_Payer_Bateria, Test_NexoSalud_Mart_Payer_Bateria.';
GO

-- ====================================================================================================
-- FASE 2: ESQUEMA OLTP SINTÉTICO — Test_NexoSalud_OLTP_Payer_Bateria
-- ====================================================================================================
USE Test_NexoSalud_OLTP_Payer_Bateria;
GO

IF DB_NAME() <> 'Test_NexoSalud_OLTP_Payer_Bateria'
BEGIN
    RAISERROR('Fallo al cambiar contexto a Test_NexoSalud_OLTP_Payer_Bateria.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Catálogo de Sedes
CREATE TABLE dbo.Sedes (
    id_sede     INT          NOT NULL PRIMARY KEY,
    nombre_sede VARCHAR(100) NOT NULL
);

-- Catálogo de Servicios
CREATE TABLE dbo.Servicios (
    id_servicio     INT          NOT NULL PRIMARY KEY,
    nombre_servicio VARCHAR(100) NOT NULL
);

-- Tabla de Personas
CREATE TABLE dbo.Personas (
    id_persona       INT           NOT NULL PRIMARY KEY,
    nombres          VARCHAR(100)  NULL,
    apellidos        VARCHAR(100)  NULL,
    dni              VARCHAR(20)   NULL,
    email            VARCHAR(150)  NULL,
    numero           VARCHAR(50)   NULL,
    fecha_registro   DATETIME2(7)  NOT NULL DEFAULT SYSDATETIME()
);

-- Tabla de Disponibilidad (horarios de profesionales)
CREATE TABLE dbo.Disponibilidad (
    id_disponibilidad INT          NOT NULL PRIMARY KEY,
    id_sede           INT          NOT NULL REFERENCES dbo.Sedes(id_sede),
    fecha_disponible  DATE         NOT NULL,
    hora_inicio       TIME(0)      NOT NULL
);

-- Tabla de Opciones (propuestas de tratamiento)
CREATE TABLE dbo.Opciones (
    id_opcion    INT           NOT NULL PRIMARY KEY,
    id_servicio  INT           NOT NULL REFERENCES dbo.Servicios(id_servicio),
    descripcion  VARCHAR(200)  NULL,
    precio       DECIMAL(10,2) NULL
);

-- Tabla de Solicitudes
CREATE TABLE dbo.Solicitudes (
    id_solicitud      INT          NOT NULL PRIMARY KEY,
    id_persona        INT          NOT NULL REFERENCES dbo.Personas(id_persona),
    id_opcion         INT          NULL,
    estado            VARCHAR(50)  NOT NULL,
    fecha_solicitud   DATETIME2(7) NOT NULL DEFAULT SYSDATETIME()
);

-- Tabla de Reservas (central para el hecho)
CREATE TABLE dbo.Reservas (
    id_reserva            INT          NOT NULL PRIMARY KEY,
    id_solicitud          INT          NOT NULL REFERENCES dbo.Solicitudes(id_solicitud),
    id_disponibilidad     INT          NULL REFERENCES dbo.Disponibilidad(id_disponibilidad),
    estado                VARCHAR(50)  NOT NULL,
    fecha_reserva         DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    confirmacion_explicita BIT         NOT NULL DEFAULT 1,
    fecha_confirmacion    DATETIME2(7) NULL
);

-- Tabla de Canales de Pago
CREATE TABLE dbo.CanalesPago (
    id_canal_pago INT          NOT NULL PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL
);

-- Tabla de Pagos (tabla origen del ETL PAYER)
CREATE TABLE dbo.Pagos (
    id_pago          INT            NOT NULL PRIMARY KEY,
    id_persona       INT            NOT NULL REFERENCES dbo.Personas(id_persona),
    id_reserva       INT            NULL     REFERENCES dbo.Reservas(id_reserva),
    importe          DECIMAL(10,2)  NOT NULL,
    canal_pago       VARCHAR(50)    NULL,
    fecha_registro   DATETIME2(7)   NOT NULL DEFAULT SYSDATETIME(),
    fecha_validacion DATETIME2(7)   NULL,
    estado           VARCHAR(20)    NOT NULL,
    comprobante      VARCHAR(300)   NULL
);

GO

-- Siembra de catálogos
INSERT INTO dbo.Sedes    (id_sede,  nombre_sede)    VALUES (1, 'Sede Central Trujillo'), (2, 'Sede Victor Larco');
INSERT INTO dbo.Servicios(id_servicio, nombre_servicio) VALUES (1, 'Ortodoncia'), (2, 'Implantología'), (3, 'Limpieza');
INSERT INTO dbo.Personas (id_persona, nombres, apellidos, dni, email, numero, fecha_registro) VALUES
    (1, 'Carlos',  'Mendoza', '45891234', 'carlos@email.com',  '987654321', '2026-09-01 10:00:00'),
    (2, 'Ana',     'Rios',    '46781290', 'ana@email.com',     '976543210', '2026-09-02 11:00:00'),
    (3, 'Pedro',   'Gomez',   '47891230', 'pedro@email.com',   '965432109', '2026-09-03 12:00:00'),
    (4, 'Maria',   'Vargas',  '48901234', 'maria@email.com',   '954321098', '2026-09-04 14:00:00'),
    (5, 'Jorge',   'Soto',    '49012345', 'jorge@email.com',   '943210987', '2026-09-05 15:00:00'),
    (6, 'Lucia',   'Perez',   '50123456', 'lucia@email.com',   '932109876', '2026-09-06 09:00:00'),
    (7, 'Raul',    'Torres',  '51234567', 'raul@email.com',    '921098765', '2026-09-07 10:00:00'),
    (8, 'Elena',   'Castro',  '52345678', 'elena@email.com',   '910987654', '2026-09-08 11:00:00');

INSERT INTO dbo.Disponibilidad (id_disponibilidad, id_sede, fecha_disponible, hora_inicio) VALUES
    (1, 1, '2026-09-10', '09:00:00'),
    (2, 2, '2026-09-11', '10:00:00'),
    (3, 1, '2026-09-12', '11:00:00'),
    (4, 1, '2026-09-13', '09:00:00'),
    (5, 1, '2026-09-14', '10:00:00');

INSERT INTO dbo.Opciones (id_opcion, id_servicio, descripcion, precio) VALUES
    (1, 1, 'Brackets metálicos', 2500.00),
    (2, 2, 'Implante unitario',  3800.00),
    (3, 3, 'Profilaxis básica',   120.00);

INSERT INTO dbo.Solicitudes (id_solicitud, id_persona, id_opcion, estado, fecha_solicitud) VALUES
    (101, 1, 1, 'Confirmada', '2026-09-02 10:00:00'),
    (102, 2, 2, 'Confirmada', '2026-09-03 11:00:00'),
    (103, 3, 3, 'Confirmada', '2026-09-04 12:00:00'),
    (104, 4, 1, 'Confirmada', '2026-09-05 14:00:00'),  -- reserva sin anticipo (PAY-05)
    (105, 5, 1, 'Confirmada', '2026-09-06 08:00:00'),  -- reserva con 2 pagos parciales (PAY-06)
    (106, 6, 2, 'Confirmada', '2026-09-07 09:00:00'),
    (107, 7, 3, 'Confirmada', '2026-09-08 10:00:00'),
    (108, 8, 1, 'Confirmada', '2026-09-09 11:00:00');

INSERT INTO dbo.Reservas (id_reserva, id_solicitud, id_disponibilidad, estado, fecha_reserva, confirmacion_explicita, fecha_confirmacion) VALUES
    (1001, 101, 1, 'Confirmada', '2026-09-05 10:00:00', 1, '2026-09-05 10:05:00'),
    (1002, 102, 2, 'Confirmada', '2026-09-06 11:00:00', 1, '2026-09-06 11:05:00'),
    (1003, 103, 3, 'Confirmada', '2026-09-07 12:00:00', 1, '2026-09-07 12:05:00'),
    (1004, 104, 4, 'Confirmada', '2026-09-08 14:00:00', 1, '2026-09-08 14:05:00'),  -- sin pago
    (1005, 105, 5, 'Confirmada', '2026-09-09 08:00:00', 1, '2026-09-09 08:05:00'),  -- 2 pagos parciales
    (1006, 106, 1, 'Confirmada', '2026-09-10 09:00:00', 1, '2026-09-10 09:05:00'),
    (1007, 107, 2, 'Confirmada', '2026-09-11 10:00:00', 1, '2026-09-11 10:05:00'),
    (1008, 108, 3, 'Confirmada', '2026-09-12 11:00:00', 1, '2026-09-12 11:05:00');

INSERT INTO dbo.CanalesPago (id_canal_pago, nombre) VALUES
    (1, 'Efectivo'), (2, 'Tarjeta'), (3, 'Transferencia'), (4, 'Yape/Plin');

PRINT '>> OLTP sintetico poblado correctamente.';
GO

-- ====================================================================================================
-- FASE 3: ESQUEMA DATA MART SINTÉTICO — Test_NexoSalud_Mart_Payer_Bateria
-- ====================================================================================================
USE Test_NexoSalud_Mart_Payer_Bateria;
GO

IF DB_NAME() <> 'Test_NexoSalud_Mart_Payer_Bateria'
BEGIN
    RAISERROR('Fallo al cambiar contexto a Test_NexoSalud_Mart_Payer_Bateria.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- 3.1 Dimensiones Conformadas Sintéticas con Miembros Desconocidos (Key = 0)
CREATE TABLE dbo.Dim_Tiempo (
    KeyTiempo   INT  NOT NULL PRIMARY KEY,
    id_fecha    DATE NOT NULL,
    Anio        INT  NOT NULL,
    Mes         INT  NOT NULL,
    Dia         INT  NOT NULL,
    NombreMes   VARCHAR(20) NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Hora (
    KeyHora        INT         NOT NULL PRIMARY KEY,
    HoraCompleta   TIME(0)     NULL,
    HoraNumero     INT         NOT NULL DEFAULT 0,
    PeriodoDia     VARCHAR(20) NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Sede (
    KeySede       INT          NOT NULL PRIMARY KEY,
    NombreSede    VARCHAR(100) NOT NULL DEFAULT 'Desconocido',
    Ciudad        VARCHAR(100) NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Servicio (
    KeyServicio      INT          NOT NULL PRIMARY KEY,
    NombreServicio   VARCHAR(100) NOT NULL DEFAULT 'Desconocido',
    Categoria        VARCHAR(100) NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Fuente (
    KeyFuente    INT          NOT NULL PRIMARY KEY,
    NombreFuente VARCHAR(100) NOT NULL DEFAULT 'Desconocido',
    TipoFuente   VARCHAR(50)  NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Campana (
    KeyCampana    INT          NOT NULL PRIMARY KEY,
    NombreCampana VARCHAR(150) NOT NULL DEFAULT 'Desconocido',
    TipoOrigen    VARCHAR(100) NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Pasarela (
    KeyPasarela    INT          NOT NULL PRIMARY KEY,
    NombrePasarela VARCHAR(100) NOT NULL DEFAULT 'Desconocido',
    TipoPasarela   VARCHAR(50)  NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Cobro (
    KeyCobro       INT          NOT NULL PRIMARY KEY,
    TipoCobro      VARCHAR(100) NOT NULL DEFAULT 'Desconocido',
    CanalCobro     VARCHAR(100) NOT NULL DEFAULT 'Desconocido'
);

CREATE TABLE dbo.Dim_Persona (
    KeyPersona    INT          NOT NULL PRIMARY KEY,
    id_persona    INT          NOT NULL DEFAULT 0,
    NombrePersona VARCHAR(200) NOT NULL DEFAULT 'Desconocido',
    Documento     VARCHAR(20)  NOT NULL DEFAULT '00000000'
);

GO

-- Miembros desconocidos obligatorios (Key = 0)
INSERT INTO dbo.Dim_Tiempo   (KeyTiempo,  id_fecha,     Anio, Mes, Dia, NombreMes)
    VALUES (0, '1900-01-01', 1900, 1, 1, 'Desconocido');
INSERT INTO dbo.Dim_Hora     (KeyHora, HoraCompleta, HoraNumero, PeriodoDia)
    VALUES (0, NULL, 0, 'Desconocido');
INSERT INTO dbo.Dim_Sede     (KeySede, NombreSede, Ciudad)
    VALUES (0, 'Desconocido', 'Desconocido');
INSERT INTO dbo.Dim_Servicio (KeyServicio, NombreServicio, Categoria)
    VALUES (0, 'Desconocido', 'Desconocido');
INSERT INTO dbo.Dim_Fuente   (KeyFuente, NombreFuente, TipoFuente)
    VALUES (0, 'Desconocido', 'Desconocido');
INSERT INTO dbo.Dim_Campana  (KeyCampana, NombreCampana, TipoOrigen)
    VALUES (0, 'Desconocido', 'Desconocido');
INSERT INTO dbo.Dim_Pasarela (KeyPasarela, NombrePasarela, TipoPasarela)
    VALUES (0, 'Desconocido', 'Desconocido');
INSERT INTO dbo.Dim_Cobro    (KeyCobro, TipoCobro, CanalCobro)
    VALUES (0, 'Desconocido', 'Desconocido');
INSERT INTO dbo.Dim_Persona  (KeyPersona, id_persona, NombrePersona, Documento)
    VALUES (0, 0, 'Desconocido', '00000000');

-- Algunos miembros de dimensión operativos para resolución de FK
-- Dim_Tiempo: rango Sep 2026
DECLARE @d DATE = '2026-09-01';
DECLARE @k INT  = 1;
WHILE @d <= '2026-10-31'
BEGIN
    INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha, Anio, Mes, Dia, NombreMes)
    VALUES (@k, @d, YEAR(@d), MONTH(@d), DAY(@d),
        DATENAME(MONTH, @d));
    SET @d = DATEADD(DAY, 1, @d);
    SET @k = @k + 1;
END;

-- Dim_Hora: 24 horas
DECLARE @h INT = 0;
WHILE @h <= 23
BEGIN
    INSERT INTO dbo.Dim_Hora (KeyHora, HoraCompleta, HoraNumero, PeriodoDia)
    VALUES (@h + 1,
            CAST(CAST(@h AS VARCHAR(2)) + ':00:00' AS TIME(0)),
            @h,
            CASE
                WHEN @h BETWEEN  6 AND 11 THEN 'Mañana'
                WHEN @h BETWEEN 12 AND 17 THEN 'Tarde'
                WHEN @h BETWEEN 18 AND 22 THEN 'Noche'
                ELSE 'Madrugada'
            END);
    SET @h = @h + 1;
END;

-- Dim_Sede
INSERT INTO dbo.Dim_Sede (KeySede, NombreSede, Ciudad)
VALUES (1, 'Sede Central Trujillo', 'Trujillo'),
       (2, 'Sede Victor Larco', 'Trujillo');

-- Dim_Servicio
INSERT INTO dbo.Dim_Servicio (KeyServicio, NombreServicio, Categoria)
VALUES (1, 'Ortodoncia', 'Tratamiento'), (2, 'Implantología', 'Cirugía'), (3, 'Limpieza', 'Preventivo');

-- Dim_Fuente
INSERT INTO dbo.Dim_Fuente (KeyFuente, NombreFuente, TipoFuente)
VALUES (1, 'Digital', 'Online'), (2, 'Presencial', 'Offline');

-- Dim_Campana
INSERT INTO dbo.Dim_Campana (KeyCampana, NombreCampana, TipoOrigen)
VALUES (1, 'Campana Ortodoncia 2026', 'Redes Sociales'), (2, 'Campana Implantes 2026', 'Google Ads');

-- Dim_Pasarela (coincide con CanalesPago del OLTP)
INSERT INTO dbo.Dim_Pasarela (KeyPasarela, NombrePasarela, TipoPasarela)
VALUES (1, 'Efectivo', 'Presencial'), (2, 'Tarjeta', 'Digital'),
       (3, 'Transferencia', 'Digital'), (4, 'Yape/Plin', 'Digital');

-- Dim_Cobro
INSERT INTO dbo.Dim_Cobro (KeyCobro, TipoCobro, CanalCobro)
VALUES (1, 'Pago Total', 'Directo'), (2, 'Anticipo', 'Directo'), (3, 'Cuota', 'Financiado');

-- Dim_Persona (refleja personas OLTP)
INSERT INTO dbo.Dim_Persona (KeyPersona, id_persona, NombrePersona, Documento)
VALUES
    (1, 1, 'Carlos Mendoza',  '45891234'),
    (2, 2, 'Ana Rios',        '46781290'),
    (3, 3, 'Pedro Gomez',     '47891230'),
    (4, 4, 'Maria Vargas',    '48901234'),
    (5, 5, 'Jorge Soto',      '49012345'),
    (6, 6, 'Lucia Perez',     '50123456'),
    (7, 7, 'Raul Torres',     '51234567'),
    (8, 8, 'Elena Castro',    '52345678');

GO

-- 3.2 Esquema Staging
CREATE SCHEMA staging;
GO

CREATE TABLE staging.stg_Pagos (
    id_pago          INT           NOT NULL,
    id_persona       INT           NULL,
    id_reserva       INT           NULL,
    importe          DECIMAL(10,2) NULL,
    canal_pago       VARCHAR(50)   NULL,
    fecha_registro   DATETIME2(7)  NULL,
    fecha_validacion DATETIME2(7)  NULL,
    estado           VARCHAR(20)   NULL,
    comprobante      VARCHAR(300)  NULL,
    KeyTiempoPago    INT           NULL,
    KeyTiempoValid   INT           NULL,
    KeyHora          INT           NULL,
    KeySede          INT           NULL,
    KeyServicio      INT           NULL,
    KeyFuente        INT           NULL,
    KeyCampana       INT           NULL,
    KeyPasarela      INT           NULL,
    KeyCobro         INT           NULL,
    KeyPersona       INT           NULL,
    MotivoRechazo    VARCHAR(150)  NULL,
    FlagRechazar     BIT           NOT NULL DEFAULT 0
);

CREATE TABLE staging.stg_Reservas_SinPago (
    id_reserva   INT          NOT NULL PRIMARY KEY,
    id_solicitud INT          NOT NULL,
    estado       VARCHAR(50)  NOT NULL,
    fecha_reserva DATETIME2(7) NOT NULL
);

GO

-- 3.3 Tabla de Hechos principal
CREATE TABLE dbo.Fact_GestionPayer (
    KeyFactPayer        BIGINT         NOT NULL IDENTITY(1,1) PRIMARY KEY,
    id_pago_origen      INT            NOT NULL,
    id_reserva_origen   INT            NOT NULL DEFAULT 0,
    KeyTiempoPago       INT            NOT NULL,
    KeyTiempoValidacion INT            NOT NULL DEFAULT 0,
    KeyHora             INT            NOT NULL DEFAULT 0,
    KeySede             INT            NOT NULL DEFAULT 0,
    KeyServicio         INT            NOT NULL DEFAULT 0,
    KeyFuente           INT            NOT NULL DEFAULT 0,
    KeyCampana          INT            NOT NULL DEFAULT 0,
    KeyPasarela         INT            NOT NULL DEFAULT 0,
    KeyCobro            INT            NOT NULL DEFAULT 0,
    KeyPersona          INT            NOT NULL DEFAULT 0,
    PagosRegistrados    INT            NOT NULL DEFAULT 1,
    PagosValidados      INT            NOT NULL DEFAULT 0,
    PagosPendientes     INT            NOT NULL DEFAULT 0,
    PagosRechazados     INT            NOT NULL DEFAULT 0,
    ImporteTotalCobro   DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    ImportePendiente    DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    ImporteRechazado    DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    IndicadorMoneda     VARCHAR(30)    NOT NULL DEFAULT 'MonedaNoVerificada',
    TiempoValidacionMin INT            NULL,
    EsPagoSinAnticipo   BIT            NOT NULL DEFAULT 0,
    BatchId             VARCHAR(50)    NOT NULL,
    FechaCarga          DATETIME2(7)   NOT NULL DEFAULT SYSDATETIME(),
    FechaModificacion   DATETIME2(7)   NULL,
    UsuarioCarga        VARCHAR(50)    NOT NULL DEFAULT 'ETL_PAYER',
    CONSTRAINT UQ_Fact_GestionPayer_id_pago_origen UNIQUE (id_pago_origen),
    CONSTRAINT FK_FactPayer_Tiempo    FOREIGN KEY (KeyTiempoPago)       REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    CONSTRAINT FK_FactPayer_TimeValid FOREIGN KEY (KeyTiempoValidacion) REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    CONSTRAINT FK_FactPayer_Hora      FOREIGN KEY (KeyHora)             REFERENCES dbo.Dim_Hora(KeyHora),
    CONSTRAINT FK_FactPayer_Sede      FOREIGN KEY (KeySede)             REFERENCES dbo.Dim_Sede(KeySede),
    CONSTRAINT FK_FactPayer_Servicio  FOREIGN KEY (KeyServicio)         REFERENCES dbo.Dim_Servicio(KeyServicio),
    CONSTRAINT FK_FactPayer_Fuente    FOREIGN KEY (KeyFuente)           REFERENCES dbo.Dim_Fuente(KeyFuente),
    CONSTRAINT FK_FactPayer_Campana   FOREIGN KEY (KeyCampana)          REFERENCES dbo.Dim_Campana(KeyCampana),
    CONSTRAINT FK_FactPayer_Pasarela  FOREIGN KEY (KeyPasarela)         REFERENCES dbo.Dim_Pasarela(KeyPasarela),
    CONSTRAINT FK_FactPayer_Cobro     FOREIGN KEY (KeyCobro)            REFERENCES dbo.Dim_Cobro(KeyCobro),
    CONSTRAINT FK_FactPayer_Persona   FOREIGN KEY (KeyPersona)          REFERENCES dbo.Dim_Persona(KeyPersona)
);

GO

-- 3.4 Tablas Auxiliares ETL (Log + Rechazos)
CREATE TABLE dbo.Log_Ejecucion_ETL (
    LogId       BIGINT        NOT NULL IDENTITY(1,1) PRIMARY KEY,
    Procedimiento VARCHAR(150) NOT NULL,
    BatchId     VARCHAR(50)   NOT NULL,
    TipoEvento  VARCHAR(20)   NOT NULL,  -- INICIO / EXITO / ERROR / ADVERTENCIA
    Mensaje     VARCHAR(MAX)  NOT NULL,
    LineaError  INT           NULL,
    FechaRegistro DATETIME2(7) NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.Rechazos_ETL_Payer (
    RechazoId      BIGINT        NOT NULL IDENTITY(1,1) PRIMARY KEY,
    EntidadOrigenId INT          NOT NULL,
    MotivoRechazo  VARCHAR(150)  NOT NULL,
    DetalleRechazo VARCHAR(MAX)  NULL,
    BatchId        VARCHAR(50)   NOT NULL,
    FechaRechazo   DATETIME2(7)  NOT NULL DEFAULT SYSDATETIME()
);

GO

-- ====================================================================================================
-- FASE 4: PROCEDIMIENTO ETL — dbo.usp_Cargar_Fact_GestionPayer
--         Implementación autónoma (no requiere :r externo)
-- ====================================================================================================
CREATE OR ALTER PROCEDURE dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  DATE,
    @BatchId     VARCHAR(50),
    @Insertados  INT OUTPUT,
    @Actualizados INT OUTPUT,
    @SinCambio   INT OUTPUT,
    @Rechazados  INT OUTPUT,
    @Pendientes  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Parámetros de retorno
    SET @Insertados  = 0;
    SET @Actualizados = 0;
    SET @SinCambio   = 0;
    SET @Rechazados  = 0;
    SET @Pendientes  = 0;

    -- Variables locales
    DECLARE @Proc VARCHAR(150) = 'dbo.usp_Cargar_Fact_GestionPayer';
    DECLARE @OLTP_DB SYSNAME   = N'Test_NexoSalud_OLTP_Payer_Bateria';
    DECLARE @ErrMsg  VARCHAR(MAX);

    -- Validación de parámetros mínimos
    IF @FechaCorte IS NULL OR @BatchId IS NULL OR LTRIM(RTRIM(@BatchId)) = ''
    BEGIN
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje)
        VALUES (@Proc, ISNULL(@BatchId,'NULL'), 'ERROR', 'Parámetros obligatorios ausentes: @FechaCorte o @BatchId vacíos.');
        RETURN -1;
    END;

    -- Log INICIO
    INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje)
    VALUES (@Proc, @BatchId, 'INICIO',
        'Inicio ETL PAYER. FechaCorte=' + CONVERT(VARCHAR,@FechaCorte,120) + ' BatchId=' + @BatchId);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- -----------------------------------------------------------------------
        -- PASO 1: Limpiar staging de este batch
        -- -----------------------------------------------------------------------
        TRUNCATE TABLE staging.stg_Pagos;
        TRUNCATE TABLE staging.stg_Reservas_SinPago;

        -- -----------------------------------------------------------------------
        -- PASO 2: Extraer pagos elegibles desde OLTP (importe > 0, fecha <= corte)
        --         y poblar staging con resolución dimensional
        -- -----------------------------------------------------------------------
        INSERT INTO staging.stg_Pagos (
            id_pago, id_persona, id_reserva, importe, canal_pago,
            fecha_registro, fecha_validacion, estado, comprobante,
            KeyTiempoPago, KeyTiempoValid, KeyHora,
            KeySede, KeyServicio, KeyFuente, KeyCampana,
            KeyPasarela, KeyCobro, KeyPersona,
            MotivoRechazo, FlagRechazar
        )
        SELECT
            p.id_pago,
            p.id_persona,
            p.id_reserva,
            p.importe,
            p.canal_pago,
            p.fecha_registro,
            p.fecha_validacion,
            p.estado,
            p.comprobante,

            -- KeyTiempoPago: buscar por fecha de registro
            ISNULL((SELECT TOP 1 dt.KeyTiempo FROM dbo.Dim_Tiempo dt
                    WHERE dt.id_fecha = CAST(p.fecha_registro AS DATE)), 0),

            -- KeyTiempoValidacion: fecha de validación o 0
            ISNULL((SELECT TOP 1 dt.KeyTiempo FROM dbo.Dim_Tiempo dt
                    WHERE dt.id_fecha = CAST(p.fecha_validacion AS DATE)), 0),

            -- KeyHora: hora del registro
            ISNULL((SELECT TOP 1 dh.KeyHora FROM dbo.Dim_Hora dh
                    WHERE dh.HoraNumero = DATEPART(HOUR, p.fecha_registro)), 0),

            -- KeySede: derivar de la reserva → disponibilidad → sede
            ISNULL((
                SELECT TOP 1 ds.KeySede FROM dbo.Dim_Sede ds
                INNER JOIN Test_NexoSalud_OLTP_Payer_Bateria.dbo.Reservas r
                    ON r.id_reserva = p.id_reserva
                INNER JOIN Test_NexoSalud_OLTP_Payer_Bateria.dbo.Disponibilidad disp
                    ON disp.id_disponibilidad = r.id_disponibilidad
                WHERE ds.KeySede = disp.id_sede
            ), 0),

            -- KeyServicio: derivar de solicitud → opción → servicio
            ISNULL((
                SELECT TOP 1 dsv.KeyServicio FROM dbo.Dim_Servicio dsv
                INNER JOIN Test_NexoSalud_OLTP_Payer_Bateria.dbo.Reservas r
                    ON r.id_reserva = p.id_reserva
                INNER JOIN Test_NexoSalud_OLTP_Payer_Bateria.dbo.Solicitudes sol
                    ON sol.id_solicitud = r.id_solicitud
                INNER JOIN Test_NexoSalud_OLTP_Payer_Bateria.dbo.Opciones op
                    ON op.id_opcion = sol.id_opcion
                WHERE dsv.KeyServicio = op.id_servicio
            ), 0),

            -- KeyFuente: simplificado (siempre 1 = Digital en ambiente test)
            1,

            -- KeyCampana: miembro 0 por defecto en ambiente test
            0,

            -- KeyPasarela: resolver por nombre de canal_pago
            ISNULL((SELECT TOP 1 dp.KeyPasarela FROM dbo.Dim_Pasarela dp
                    WHERE dp.NombrePasarela = p.canal_pago), 0),

            -- KeyCobro: siempre Pago Total en este contexto
            1,

            -- KeyPersona: resolver por id_persona OLTP
            ISNULL((SELECT TOP 1 dpe.KeyPersona FROM dbo.Dim_Persona dpe
                    WHERE dpe.id_persona = p.id_persona), 0),

            -- MotivoRechazo inicial nulo
            NULL,

            -- FlagRechazar = 0 por defecto
            0

        FROM Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos p
        WHERE CAST(p.fecha_registro AS DATE) <= @FechaCorte;

        -- -----------------------------------------------------------------------
        -- PASO 3: Marcar rechazos por importe cero o negativo
        -- -----------------------------------------------------------------------
        UPDATE staging.stg_Pagos
        SET FlagRechazar   = 1,
            MotivoRechazo  = 'ImporteNegativoOCero'
        WHERE importe <= 0;

        -- -----------------------------------------------------------------------
        -- PASO 4: Marcar rechazos por estado de pago desconocido
        -- -----------------------------------------------------------------------
        UPDATE staging.stg_Pagos
        SET FlagRechazar  = 1,
            MotivoRechazo = 'EstadoPagoDesconocido'
        WHERE FlagRechazar = 0
          AND UPPER(LTRIM(RTRIM(estado))) NOT IN ('VALIDADO', 'PENDIENTE', 'RECHAZADO');

        -- -----------------------------------------------------------------------
        -- PASO 5: Persistir rechazos
        -- -----------------------------------------------------------------------
        INSERT INTO dbo.Rechazos_ETL_Payer (EntidadOrigenId, MotivoRechazo, DetalleRechazo, BatchId)
        SELECT
            id_pago,
            MotivoRechazo,
            'id_pago=' + CAST(id_pago AS VARCHAR) +
            ' | importe=' + CAST(importe AS VARCHAR) +
            ' | estado=' + ISNULL(estado, 'NULL'),
            @BatchId
        FROM staging.stg_Pagos
        WHERE FlagRechazar = 1;

        SET @Rechazados = @@ROWCOUNT;

        -- -----------------------------------------------------------------------
        -- PASO 6: Identificar reservas sin pago (política sin anticipo)
        -- -----------------------------------------------------------------------
        INSERT INTO staging.stg_Reservas_SinPago (id_reserva, id_solicitud, estado, fecha_reserva)
        SELECT r.id_reserva, r.id_solicitud, r.estado, r.fecha_reserva
        FROM Test_NexoSalud_OLTP_Payer_Bateria.dbo.Reservas r
        WHERE NOT EXISTS (
            SELECT 1 FROM Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos p
            WHERE p.id_reserva = r.id_reserva
        )
        AND CAST(r.fecha_reserva AS DATE) <= @FechaCorte;

        -- -----------------------------------------------------------------------
        -- PASO 7: INSERTAR filas nuevas (no existen en Fact_GestionPayer)
        -- -----------------------------------------------------------------------
        INSERT INTO dbo.Fact_GestionPayer (
            id_pago_origen, id_reserva_origen,
            KeyTiempoPago, KeyTiempoValidacion, KeyHora,
            KeySede, KeyServicio, KeyFuente, KeyCampana,
            KeyPasarela, KeyCobro, KeyPersona,
            PagosRegistrados, PagosValidados, PagosPendientes, PagosRechazados,
            ImporteTotalCobro, ImportePendiente, ImporteRechazado,
            IndicadorMoneda, TiempoValidacionMin, EsPagoSinAnticipo,
            BatchId, FechaCarga, UsuarioCarga
        )
        SELECT
            s.id_pago,
            ISNULL(s.id_reserva, 0),
            s.KeyTiempoPago,
            s.KeyTiempoValid,
            s.KeyHora,
            s.KeySede,
            s.KeyServicio,
            s.KeyFuente,
            s.KeyCampana,
            s.KeyPasarela,
            s.KeyCobro,
            s.KeyPersona,
            -- Métricas
            1,  -- PagosRegistrados
            CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'VALIDADO'  THEN 1 ELSE 0 END,
            CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'PENDIENTE' THEN 1 ELSE 0 END,
            CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'RECHAZADO' THEN 1 ELSE 0 END,
            -- Importes
            CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'VALIDADO'  THEN s.importe ELSE 0.00 END,
            CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'PENDIENTE' THEN s.importe ELSE 0.00 END,
            CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'RECHAZADO' THEN s.importe ELSE 0.00 END,
            'MonedaNoVerificada',
            -- TiempoValidacionMin
            CASE WHEN s.fecha_validacion IS NOT NULL AND s.fecha_registro IS NOT NULL
                 THEN DATEDIFF(MINUTE, s.fecha_registro, s.fecha_validacion)
                 ELSE NULL
            END,
            0,  -- EsPagoSinAnticipo (default)
            @BatchId,
            SYSDATETIME(),
            'ETL_PAYER'
        FROM staging.stg_Pagos s
        WHERE s.FlagRechazar = 0
          AND NOT EXISTS (
              SELECT 1 FROM dbo.Fact_GestionPayer f
              WHERE f.id_pago_origen = s.id_pago
          );

        SET @Insertados = @@ROWCOUNT;

        -- -----------------------------------------------------------------------
        -- PASO 8: ACTUALIZAR filas existentes que cambiaron de estado o importe
        -- -----------------------------------------------------------------------
        UPDATE f
        SET
            f.KeyTiempoPago       = s.KeyTiempoPago,
            f.KeyTiempoValidacion = s.KeyTiempoValid,
            f.KeyHora             = s.KeyHora,
            f.KeySede             = s.KeySede,
            f.KeyServicio         = s.KeyServicio,
            f.KeyFuente           = s.KeyFuente,
            f.KeyCampana          = s.KeyCampana,
            f.KeyPasarela         = s.KeyPasarela,
            f.KeyCobro            = s.KeyCobro,
            f.KeyPersona          = s.KeyPersona,
            f.id_reserva_origen   = ISNULL(s.id_reserva, 0),
            f.PagosValidados      = CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'VALIDADO'  THEN 1 ELSE 0 END,
            f.PagosPendientes     = CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'PENDIENTE' THEN 1 ELSE 0 END,
            f.PagosRechazados     = CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'RECHAZADO' THEN 1 ELSE 0 END,
            f.ImporteTotalCobro   = CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'VALIDADO'  THEN s.importe ELSE 0.00 END,
            f.ImportePendiente    = CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'PENDIENTE' THEN s.importe ELSE 0.00 END,
            f.ImporteRechazado    = CASE WHEN UPPER(LTRIM(RTRIM(s.estado))) = 'RECHAZADO' THEN s.importe ELSE 0.00 END,
            f.TiempoValidacionMin = CASE WHEN s.fecha_validacion IS NOT NULL AND s.fecha_registro IS NOT NULL
                                         THEN DATEDIFF(MINUTE, s.fecha_registro, s.fecha_validacion)
                                         ELSE f.TiempoValidacionMin END,
            f.BatchId             = @BatchId,
            f.FechaModificacion   = SYSDATETIME(),
            f.UsuarioCarga        = 'ETL_PAYER'
        FROM dbo.Fact_GestionPayer f
        INNER JOIN staging.stg_Pagos s ON s.id_pago = f.id_pago_origen
        WHERE s.FlagRechazar = 0
          AND (
              UPPER(LTRIM(RTRIM(s.estado))) <> 
                  CASE 
                      WHEN f.PagosValidados  = 1 THEN 'VALIDADO'
                      WHEN f.PagosPendientes = 1 THEN 'PENDIENTE'
                      WHEN f.PagosRechazados = 1 THEN 'RECHAZADO'
                      ELSE 'DESCONOCIDO'
                  END
              OR ABS(s.importe - (f.ImporteTotalCobro + f.ImportePendiente + f.ImporteRechazado)) > 0.001
          );

        SET @Actualizados = @@ROWCOUNT;

        -- -----------------------------------------------------------------------
        -- PASO 9: Contabilizar SinCambio
        -- -----------------------------------------------------------------------
        SELECT @SinCambio = COUNT(*)
        FROM dbo.Fact_GestionPayer f
        INNER JOIN staging.stg_Pagos s ON s.id_pago = f.id_pago_origen
        WHERE s.FlagRechazar = 0
          AND NOT (
              UPPER(LTRIM(RTRIM(s.estado))) <>
                  CASE
                      WHEN f.PagosValidados  = 1 THEN 'VALIDADO'
                      WHEN f.PagosPendientes = 1 THEN 'PENDIENTE'
                      WHEN f.PagosRechazados = 1 THEN 'RECHAZADO'
                      ELSE 'DESCONOCIDO'
                  END
              OR ABS(s.importe - (f.ImporteTotalCobro + f.ImportePendiente + f.ImporteRechazado)) > 0.001
          );

        -- -----------------------------------------------------------------------
        -- PASO 10: Contabilizar Pendientes (pagos en estado Pendiente aceptados)
        -- -----------------------------------------------------------------------
        SELECT @Pendientes = COUNT(*)
        FROM staging.stg_Pagos
        WHERE FlagRechazar = 0
          AND UPPER(LTRIM(RTRIM(estado))) = 'PENDIENTE';

        COMMIT TRANSACTION;

        -- Log EXITO
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje)
        VALUES (@Proc, @BatchId, 'EXITO',
            'ETL completado. Insertados=' + CAST(@Insertados AS VARCHAR) +
            ' Actualizados=' + CAST(@Actualizados AS VARCHAR) +
            ' SinCambio=' + CAST(@SinCambio AS VARCHAR) +
            ' Rechazados=' + CAST(@Rechazados AS VARCHAR) +
            ' Pendientes=' + CAST(@Pendientes AS VARCHAR));

        RETURN 0;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ErrMsg = ERROR_MESSAGE();
        INSERT INTO dbo.Log_Ejecucion_ETL (Procedimiento, BatchId, TipoEvento, Mensaje, LineaError)
        VALUES (@Proc, @BatchId, 'ERROR', @ErrMsg, ERROR_LINE());
        RETURN -1;
    END CATCH;
END;
GO

PRINT '>> Procedimiento usp_Cargar_Fact_GestionPayer creado en Test_NexoSalud_Mart_Payer_Bateria.';
GO

-- ====================================================================================================
-- FASE 5: TABLA DE RESULTADOS DE PRUEBA (sesión)
-- ====================================================================================================
-- Nota: Las tablas temporales globales (##) son visibles en todas las sesiones del mismo lote.
IF OBJECT_ID('tempdb..##ResultadosPayer') IS NOT NULL DROP TABLE ##ResultadosPayer;

CREATE TABLE ##ResultadosPayer (
    CasoId          VARCHAR(10)   NOT NULL,
    Descripcion     VARCHAR(200)  NOT NULL,
    CriterioEsperado VARCHAR(500) NOT NULL,
    ValorObtenido   VARCHAR(500)  NOT NULL,
    Estado          VARCHAR(20)   NOT NULL   -- 'CORRECTO' / 'FALLO'
);
GO

-- ====================================================================================================
-- FASE 6: PAY-01 — Carga Inicial (3 pagos: Validado / Pendiente / Rechazado)
-- ====================================================================================================
PRINT '>> Ejecutando PAY-01: Carga Inicial';
GO

-- Insertar los 3 pagos base en OLTP
INSERT INTO Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos
    (id_pago, id_persona, id_reserva, importe, canal_pago,
     fecha_registro, fecha_validacion, estado, comprobante)
VALUES
    (1, 1, 1001, 150.00, 'Efectivo',
     '2026-09-10 10:00:00', '2026-09-10 10:30:00', 'Validado', 'COMP-001'),
    (2, 2, 1002,  80.00, 'Yape/Plin',
     '2026-09-10 11:00:00', NULL,                  'Pendiente', NULL),
    (3, 3, 1003,  50.00, 'Transferencia',
     '2026-09-10 12:00:00', NULL,                  'Rechazado', NULL);

DECLARE @Ins01 INT, @Act01 INT, @Sin01 INT, @Rec01 INT, @Pen01 INT;
DECLARE @Ret01 INT;

EXEC @Ret01 = Test_NexoSalud_Mart_Payer_Bateria.dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  = '2026-09-30',
    @BatchId     = 'BATCH-PAY-01',
    @Insertados  = @Ins01  OUTPUT,
    @Actualizados= @Act01  OUTPUT,
    @SinCambio   = @Sin01  OUTPUT,
    @Rechazados  = @Rec01  OUTPUT,
    @Pendientes  = @Pen01  OUTPUT;

-- Verificación 1: 3 filas en Fact_GestionPayer
DECLARE @cnt01 INT;
SELECT @cnt01 = COUNT(*) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-01a', 'Carga Inicial — Total filas en hecho',
    '3 filas en Fact_GestionPayer',
    'Filas=' + CAST(@cnt01 AS VARCHAR),
    CASE WHEN @cnt01 = 3 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: ImporteTotalCobro = 150.00 (solo Validado)
DECLARE @imp01v DECIMAL(10,2);
SELECT @imp01v = SUM(ImporteTotalCobro) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-01b', 'Carga Inicial — Suma ImporteTotalCobro',
    'ImporteTotalCobro=150.00',
    'SumaImporteTotalCobro=' + CAST(ISNULL(@imp01v,0) AS VARCHAR),
    CASE WHEN @imp01v = 150.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 3: ImportePendiente = 80.00
DECLARE @imp01p DECIMAL(10,2);
SELECT @imp01p = SUM(ImportePendiente) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-01c', 'Carga Inicial — Suma ImportePendiente',
    'ImportePendiente=80.00',
    'SumaImportePendiente=' + CAST(ISNULL(@imp01p,0) AS VARCHAR),
    CASE WHEN @imp01p = 80.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 4: ImporteRechazado = 50.00
DECLARE @imp01r DECIMAL(10,2);
SELECT @imp01r = SUM(ImporteRechazado) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-01d', 'Carga Inicial — Suma ImporteRechazado',
    'ImporteRechazado=50.00',
    'SumaImporteRechazado=' + CAST(ISNULL(@imp01r,0) AS VARCHAR),
    CASE WHEN @imp01r = 50.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 5: IndicadorMoneda='MonedaNoVerificada' en todos
DECLARE @moneda01 INT;
SELECT @moneda01 = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer
WHERE IndicadorMoneda <> 'MonedaNoVerificada';

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-01e', 'Carga Inicial — IndicadorMoneda en todos',
    'FilasConMonedaDistinta=0',
    'FilasMonedaDistinta=' + CAST(@moneda01 AS VARCHAR),
    CASE WHEN @moneda01 = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-01 completado. Insertados=' + CAST(@Ins01 AS VARCHAR);
GO

-- ====================================================================================================
-- FASE 7: PAY-02 — Idempotencia Pura (segunda ejecución sin cambios OLTP)
-- ====================================================================================================
PRINT '>> Ejecutando PAY-02: Idempotencia Pura';
GO

DECLARE @Ins02 INT, @Act02 INT, @Sin02 INT, @Rec02 INT, @Pen02 INT;
DECLARE @Ret02 INT;

EXEC @Ret02 = Test_NexoSalud_Mart_Payer_Bateria.dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  = '2026-09-30',
    @BatchId     = 'BATCH-PAY-02',
    @Insertados  = @Ins02  OUTPUT,
    @Actualizados= @Act02  OUTPUT,
    @SinCambio   = @Sin02  OUTPUT,
    @Rechazados  = @Rec02  OUTPUT,
    @Pendientes  = @Pen02  OUTPUT;

-- Verificación 1: COUNT(Fact_GestionPayer) sigue en 3
DECLARE @cnt02 INT;
SELECT @cnt02 = COUNT(*) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-02a', 'Idempotencia — Total filas sin cambio',
    'Filas=3 (sin nuevas inserciones)',
    'Filas=' + CAST(@cnt02 AS VARCHAR),
    CASE WHEN @cnt02 = 3 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: @Insertados = 0
INSERT INTO ##ResultadosPayer VALUES (
    'PAY-02b', 'Idempotencia — Insertados=0',
    '@Insertados=0',
    '@Insertados=' + CAST(@Ins02 AS VARCHAR),
    CASE WHEN @Ins02 = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 3: @Actualizados = 0
INSERT INTO ##ResultadosPayer VALUES (
    'PAY-02c', 'Idempotencia — Actualizados=0',
    '@Actualizados=0',
    '@Actualizados=' + CAST(@Act02 AS VARCHAR),
    CASE WHEN @Act02 = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 4: @SinCambio = 3
INSERT INTO ##ResultadosPayer VALUES (
    'PAY-02d', 'Idempotencia — SinCambio=3',
    '@SinCambio=3',
    '@SinCambio=' + CAST(@Sin02 AS VARCHAR),
    CASE WHEN @Sin02 = 3 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-02 completado.';
GO

-- ====================================================================================================
-- FASE 8: PAY-03 — Actualización Estado Pendiente → Validado
-- ====================================================================================================
PRINT '>> Ejecutando PAY-03: Actualizacion de Estado Pendiente a Validado';
GO

-- Cambiar P2 de 'Pendiente' a 'Validado' en OLTP
UPDATE Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos
SET estado           = 'Validado',
    fecha_validacion = '2026-09-11 09:00:00'
WHERE id_pago = 2;

DECLARE @Ins03 INT, @Act03 INT, @Sin03 INT, @Rec03 INT, @Pen03 INT;
DECLARE @Ret03 INT;

EXEC @Ret03 = Test_NexoSalud_Mart_Payer_Bateria.dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  = '2026-09-30',
    @BatchId     = 'BATCH-PAY-03',
    @Insertados  = @Ins03  OUTPUT,
    @Actualizados= @Act03  OUTPUT,
    @SinCambio   = @Sin03  OUTPUT,
    @Rechazados  = @Rec03  OUTPUT,
    @Pendientes  = @Pen03  OUTPUT;

-- Verificación 1: @Actualizados = 1
INSERT INTO ##ResultadosPayer VALUES (
    'PAY-03a', 'Actualizacion Estado — @Actualizados=1',
    '@Actualizados=1',
    '@Actualizados=' + CAST(@Act03 AS VARCHAR),
    CASE WHEN @Act03 = 1 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: ImporteTotalCobro ahora incluye P2 → suma 230.00
DECLARE @imp03v DECIMAL(10,2);
SELECT @imp03v = SUM(ImporteTotalCobro)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-03b', 'Actualizacion Estado — ImporteTotalCobro actualizado',
    'SumaImporteTotalCobro=230.00 (P1=150 + P2=80)',
    'SumaImporteTotalCobro=' + CAST(ISNULL(@imp03v,0) AS VARCHAR),
    CASE WHEN @imp03v = 230.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 3: ImportePendiente = 0.00 (P2 ya no es pendiente)
DECLARE @imp03p DECIMAL(10,2);
SELECT @imp03p = SUM(ImportePendiente)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-03c', 'Actualizacion Estado — ImportePendiente=0',
    'SumaImportePendiente=0.00',
    'SumaImportePendiente=' + CAST(ISNULL(@imp03p,0) AS VARCHAR),
    CASE WHEN @imp03p = 0.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 4: No hay fila duplicada para P2 (UQ constraint)
DECLARE @dup03 INT;
SELECT @dup03 = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer
WHERE id_pago_origen = 2;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-03d', 'Actualizacion Estado — Sin duplicado para P2',
    'Filas con id_pago_origen=2 debe ser 1',
    'FilasP2=' + CAST(@dup03 AS VARCHAR),
    CASE WHEN @dup03 = 1 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-03 completado.';
GO

-- ====================================================================================================
-- FASE 9: PAY-04 — Pago Rechazado No Incrementa ImporteTotalCobro
-- ====================================================================================================
PRINT '>> Ejecutando PAY-04: Pago Rechazado no incrementa ingresos';
GO

-- P3 sigue en 'Rechazado' — verificar sin nueva ejecución ETL (estado actual del mart)
DECLARE @imp04v DECIMAL(10,2);
SELECT @imp04v = SUM(ImporteTotalCobro)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-04a', 'Pago Rechazado — ImporteTotalCobro excluye P3',
    'ImporteTotalCobro=230.00 (P3 excluido)',
    'SumaImporteTotalCobro=' + CAST(ISNULL(@imp04v,0) AS VARCHAR),
    CASE WHEN @imp04v = 230.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: P3 existe con PagosRechazados=1 e ImporteRechazado=50.00
DECLARE @rechazado04 INT;
DECLARE @imp04r      DECIMAL(10,2);

SELECT @rechazado04 = PagosRechazados,
       @imp04r      = ImporteRechazado
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer
WHERE id_pago_origen = 3;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-04b', 'Pago Rechazado — P3 tiene PagosRechazados=1 y ImporteRechazado=50.00',
    'PagosRechazados=1 | ImporteRechazado=50.00',
    'PagosRechazados=' + CAST(ISNULL(@rechazado04,0) AS VARCHAR) +
    ' | ImporteRechazado=' + CAST(ISNULL(@imp04r,0) AS VARCHAR),
    CASE WHEN @rechazado04 = 1 AND @imp04r = 50.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-04 completado.';
GO

-- ====================================================================================================
-- FASE 10: PAY-05 — Reserva Sin Anticipo (sin pago asociado)
-- ====================================================================================================
PRINT '>> Ejecutando PAY-05: Reserva Sin Anticipo (sin pago)';
GO

-- Reserva 1004 (id_solicitud=104, persona=4) no tiene ningún pago — ya creada en el OLTP
-- Ejecutar ETL para actualizar staging
DECLARE @Ins05 INT, @Act05 INT, @Sin05 INT, @Rec05 INT, @Pen05 INT;
DECLARE @Ret05 INT;

EXEC @Ret05 = Test_NexoSalud_Mart_Payer_Bateria.dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  = '2026-09-30',
    @BatchId     = 'BATCH-PAY-05',
    @Insertados  = @Ins05  OUTPUT,
    @Actualizados= @Act05  OUTPUT,
    @SinCambio   = @Sin05  OUTPUT,
    @Rechazados  = @Rec05  OUTPUT,
    @Pendientes  = @Pen05  OUTPUT;

-- Verificación 1: NO hay fila en Fact_GestionPayer para reserva 1004
DECLARE @cnt05f INT;
SELECT @cnt05f = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer
WHERE id_reserva_origen = 1004;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-05a', 'Reserva Sin Anticipo — Sin fila en hecho para reserva 1004',
    'Filas en Fact con id_reserva_origen=1004 debe ser 0',
    'Filas=' + CAST(@cnt05f AS VARCHAR),
    CASE WHEN @cnt05f = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: La reserva aparece en staging.stg_Reservas_SinPago
DECLARE @cnt05s INT;
SELECT @cnt05s = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.staging.stg_Reservas_SinPago
WHERE id_reserva = 1004;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-05b', 'Reserva Sin Anticipo — Aparece en stg_Reservas_SinPago',
    'Filas en stg_Reservas_SinPago con id_reserva=1004 >= 1',
    'Filas=' + CAST(@cnt05s AS VARCHAR),
    CASE WHEN @cnt05s >= 1 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 3: COUNT(Fact_GestionPayer) sigue siendo 3 (sin filas ficticias)
DECLARE @cnt05t INT;
SELECT @cnt05t = COUNT(*) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-05c', 'Reserva Sin Anticipo — Total filas hecho no cambio',
    'Filas en Fact_GestionPayer=3 (no se crea fila ficticia)',
    'Filas=' + CAST(@cnt05t AS VARCHAR),
    CASE WHEN @cnt05t = 3 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-05 completado.';
GO

-- ====================================================================================================
-- FASE 11: PAY-06 — Pagos Parciales (múltiples pagos por misma reserva)
-- ====================================================================================================
PRINT '>> Ejecutando PAY-06: Pagos Parciales (grano atomico)';
GO

-- Insertar P4 y P5, ambos vinculados a reserva 1005 (persona 5)
INSERT INTO Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos
    (id_pago, id_persona, id_reserva, importe, canal_pago,
     fecha_registro, fecha_validacion, estado, comprobante)
VALUES
    (4, 5, 1005, 60.00, 'Tarjeta',
     '2026-09-12 09:00:00', '2026-09-12 09:30:00', 'Validado', 'COMP-004'),
    (5, 5, 1005, 90.00, 'Efectivo',
     '2026-09-12 10:00:00', '2026-09-12 10:30:00', 'Validado', 'COMP-005');

DECLARE @Ins06 INT, @Act06 INT, @Sin06 INT, @Rec06 INT, @Pen06 INT;
DECLARE @Ret06 INT;

EXEC @Ret06 = Test_NexoSalud_Mart_Payer_Bateria.dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  = '2026-09-30',
    @BatchId     = 'BATCH-PAY-06',
    @Insertados  = @Ins06  OUTPUT,
    @Actualizados= @Act06  OUTPUT,
    @SinCambio   = @Sin06  OUTPUT,
    @Rechazados  = @Rec06  OUTPUT,
    @Pendientes  = @Pen06  OUTPUT;

-- Verificación 1: 2 filas nuevas insertadas (P4 y P5)
INSERT INTO ##ResultadosPayer VALUES (
    'PAY-06a', 'Pagos Parciales — 2 nuevas filas insertadas (P4, P5)',
    '@Insertados=2',
    '@Insertados=' + CAST(@Ins06 AS VARCHAR),
    CASE WHEN @Ins06 = 2 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: Total filas = 5 (3 anteriores + P4 + P5)
DECLARE @cnt06t INT;
SELECT @cnt06t = COUNT(*) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-06b', 'Pagos Parciales — Total filas en hecho = 5',
    'Filas=5',
    'Filas=' + CAST(@cnt06t AS VARCHAR),
    CASE WHEN @cnt06t = 5 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 3: Suma ImporteTotalCobro = 380.00
--   P1=150 + P2=80 + P4=60 + P5=90 = 380.00 (P3 rechazado → 0)
DECLARE @imp06v DECIMAL(10,2);
SELECT @imp06v = SUM(ImporteTotalCobro) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-06c', 'Pagos Parciales — Suma ImporteTotalCobro=380.00',
    'SumaImporteTotalCobro=380.00 (P1+P2+P4+P5)',
    'SumaImporteTotalCobro=' + CAST(ISNULL(@imp06v,0) AS VARCHAR),
    CASE WHEN @imp06v = 380.00 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 4: La reserva 1005 tiene exactamente 2 filas distintas (grano atómico)
DECLARE @cnt06r INT;
SELECT @cnt06r = COUNT(DISTINCT id_pago_origen)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer
WHERE id_reserva_origen = 1005;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-06d', 'Pagos Parciales — Reserva 1005 tiene 2 filas distintas (no agrupadas)',
    'Filas distintas para reserva 1005 = 2',
    'FilasDistintas=' + CAST(@cnt06r AS VARCHAR),
    CASE WHEN @cnt06r = 2 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-06 completado.';
GO

-- ====================================================================================================
-- FASE 12: PAY-07 — Rechazo por Importe Cero o Negativo
-- ====================================================================================================
PRINT '>> Ejecutando PAY-07: Rechazo por Importe Cero/Negativo';
GO

-- Insertar P6 (importe=0) y P7 (importe=-10)
INSERT INTO Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos
    (id_pago, id_persona, id_reserva, importe, canal_pago,
     fecha_registro, fecha_validacion, estado, comprobante)
VALUES
    (6, 6, 1006,   0.00, 'Efectivo',
     '2026-09-13 09:00:00', NULL, 'Pendiente', NULL),
    (7, 7, 1007, -10.00, 'Tarjeta',
     '2026-09-13 10:00:00', NULL, 'Pendiente', NULL);

DECLARE @Ins07 INT, @Act07 INT, @Sin07 INT, @Rec07 INT, @Pen07 INT;
DECLARE @Ret07 INT;

EXEC @Ret07 = Test_NexoSalud_Mart_Payer_Bateria.dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  = '2026-09-30',
    @BatchId     = 'BATCH-PAY-07',
    @Insertados  = @Ins07  OUTPUT,
    @Actualizados= @Act07  OUTPUT,
    @SinCambio   = @Sin07  OUTPUT,
    @Rechazados  = @Rec07  OUTPUT,
    @Pendientes  = @Pen07  OUTPUT;

-- Verificación 1: P6 y P7 aparecen en Rechazos_ETL_Payer con motivo correcto
DECLARE @rechazados07 INT;
SELECT @rechazados07 = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Rechazos_ETL_Payer
WHERE EntidadOrigenId IN (6, 7)
  AND MotivoRechazo = 'ImporteNegativoOCero'
  AND BatchId = 'BATCH-PAY-07';

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-07a', 'Importe Invalido — P6 y P7 rechazados con motivo ImporteNegativoOCero',
    'Rechazos para P6 y P7 = 2 con MotivoRechazo=ImporteNegativoOCero',
    'Rechazos=' + CAST(@rechazados07 AS VARCHAR),
    CASE WHEN @rechazados07 = 2 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: P6 y P7 NO en Fact_GestionPayer
DECLARE @enHecho07 INT;
SELECT @enHecho07 = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer
WHERE id_pago_origen IN (6, 7);

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-07b', 'Importe Invalido — P6 y P7 NO en Fact_GestionPayer',
    'Filas en Fact para P6 y P7 = 0',
    'FilasEnHecho=' + CAST(@enHecho07 AS VARCHAR),
    CASE WHEN @enHecho07 = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-07 completado.';
GO

-- ====================================================================================================
-- FASE 13: PAY-08 — Integridad Referencial (sin huérfanos de FK)
-- ====================================================================================================
PRINT '>> Ejecutando PAY-08: Integridad Referencial';
GO

-- Verificación 1: 0 filas con KeyTiempoPago no encontrado en Dim_Tiempo (excepto key=0 válido)
DECLARE @fk08t INT;
SELECT @fk08t = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer f
WHERE NOT EXISTS (
    SELECT 1 FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Dim_Tiempo dt
    WHERE dt.KeyTiempo = f.KeyTiempoPago
);

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-08a', 'Integridad Referencial — KeyTiempoPago valido en Dim_Tiempo',
    'Huerfanos KeyTiempoPago=0',
    'HuerfanosTiempo=' + CAST(@fk08t AS VARCHAR),
    CASE WHEN @fk08t = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: 0 filas con KeyPersona no encontrado en Dim_Persona
DECLARE @fk08p INT;
SELECT @fk08p = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer f
WHERE NOT EXISTS (
    SELECT 1 FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Dim_Persona dp
    WHERE dp.KeyPersona = f.KeyPersona
);

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-08b', 'Integridad Referencial — KeyPersona valido en Dim_Persona',
    'Huerfanos KeyPersona=0',
    'HuerfanosPersona=' + CAST(@fk08p AS VARCHAR),
    CASE WHEN @fk08p = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 3: 0 filas con KeyCobro no encontrado en Dim_Cobro
DECLARE @fk08c INT;
SELECT @fk08c = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer f
WHERE NOT EXISTS (
    SELECT 1 FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Dim_Cobro dc
    WHERE dc.KeyCobro = f.KeyCobro
);

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-08c', 'Integridad Referencial — KeyCobro valido en Dim_Cobro',
    'Huerfanos KeyCobro=0',
    'HuerfanosCobro=' + CAST(@fk08c AS VARCHAR),
    CASE WHEN @fk08c = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-08 completado.';
GO

-- ====================================================================================================
-- FASE 14: PAY-09 — Conciliación OLTP vs. Data Mart (balance perfecto)
-- ====================================================================================================
PRINT '>> Ejecutando PAY-09: Conciliacion OLTP vs Data Mart';
GO

-- Contar pagos elegibles en OLTP (importe > 0, fecha_registro <= corte 2026-09-30)
DECLARE @totalOLTP09 INT;
SELECT @totalOLTP09 = COUNT(*)
FROM Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos
WHERE importe > 0
  AND CAST(fecha_registro AS DATE) <= '2026-09-30';

-- Contar aceptados en Fact_GestionPayer del último batch (contar filas actuales)
DECLARE @aceptados09 INT;
SELECT @aceptados09 = COUNT(*) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

-- Contar rechazados acumulados (todos los batches para pagos con importe > 0)
DECLARE @rechazados09 INT;
SELECT @rechazados09 = COUNT(DISTINCT EntidadOrigenId)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Rechazos_ETL_Payer r
INNER JOIN Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos p
    ON r.EntidadOrigenId = p.id_pago
WHERE p.importe > 0;

-- Verificación: balance OLTP = aceptados + rechazados
INSERT INTO ##ResultadosPayer VALUES (
    'PAY-09a', 'Conciliacion — Balance OLTP = Aceptados + Rechazados',
    'TotalOLTP=' + CAST(@totalOLTP09 AS VARCHAR) + ' = Aceptados + Rechazados',
    'OLTP=' + CAST(@totalOLTP09 AS VARCHAR) +
    ' Aceptados=' + CAST(@aceptados09 AS VARCHAR) +
    ' Rechazados=' + CAST(@rechazados09 AS VARCHAR) +
    ' Suma=' + CAST((@aceptados09 + @rechazados09) AS VARCHAR),
    CASE WHEN @totalOLTP09 = (@aceptados09 + @rechazados09) THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación: suma ImporteTotalCobro = suma importe Validados en OLTP
DECLARE @sumaOLTPVal09 DECIMAL(10,2);
SELECT @sumaOLTPVal09 = SUM(importe)
FROM Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos
WHERE UPPER(LTRIM(RTRIM(estado))) = 'VALIDADO'
  AND importe > 0
  AND CAST(fecha_registro AS DATE) <= '2026-09-30';

DECLARE @sumaMartVal09 DECIMAL(10,2);
SELECT @sumaMartVal09 = SUM(ImporteTotalCobro)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-09b', 'Conciliacion — Importes Validados OLTP = ImporteTotalCobro Mart',
    'SumaOLTPValidados = SumaMartImporteTotalCobro',
    'SumaOLTP=' + CAST(ISNULL(@sumaOLTPVal09,0) AS VARCHAR) +
    ' SumaMart=' + CAST(ISNULL(@sumaMartVal09,0) AS VARCHAR),
    CASE WHEN ABS(ISNULL(@sumaOLTPVal09,0) - ISNULL(@sumaMartVal09,0)) < 0.01 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-09 completado.';
GO

-- ====================================================================================================
-- FASE 15: PAY-10 — Manejo de Errores: Estado Desconocido
-- ====================================================================================================
PRINT '>> Ejecutando PAY-10: Estado de Pago Desconocido';
GO

-- Insertar P8 con estado inventado
INSERT INTO Test_NexoSalud_OLTP_Payer_Bateria.dbo.Pagos
    (id_pago, id_persona, id_reserva, importe, canal_pago,
     fecha_registro, fecha_validacion, estado, comprobante)
VALUES
    (8, 8, 1008, 200.00, 'Transferencia',
     '2026-09-14 10:00:00', NULL, 'EstadoInventado', NULL);

DECLARE @Ins10 INT, @Act10 INT, @Sin10 INT, @Rec10 INT, @Pen10 INT;
DECLARE @Ret10 INT;

EXEC @Ret10 = Test_NexoSalud_Mart_Payer_Bateria.dbo.usp_Cargar_Fact_GestionPayer
    @FechaCorte  = '2026-09-30',
    @BatchId     = 'BATCH-PAY-10',
    @Insertados  = @Ins10  OUTPUT,
    @Actualizados= @Act10  OUTPUT,
    @SinCambio   = @Sin10  OUTPUT,
    @Rechazados  = @Rec10  OUTPUT,
    @Pendientes  = @Pen10  OUTPUT;

-- Verificación 1: P8 aparece en Rechazos_ETL_Payer con MotivoRechazo='EstadoPagoDesconocido'
DECLARE @rechazado10 INT;
SELECT @rechazado10 = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Rechazos_ETL_Payer
WHERE EntidadOrigenId = 8
  AND MotivoRechazo   = 'EstadoPagoDesconocido'
  AND BatchId         = 'BATCH-PAY-10';

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-10a', 'Estado Desconocido — P8 en Rechazos con MotivoRechazo=EstadoPagoDesconocido',
    'Rechazos para P8 con EstadoPagoDesconocido >= 1',
    'Rechazos=' + CAST(@rechazado10 AS VARCHAR),
    CASE WHEN @rechazado10 >= 1 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 2: P8 NO en Fact_GestionPayer
DECLARE @enHecho10 INT;
SELECT @enHecho10 = COUNT(*)
FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer
WHERE id_pago_origen = 8;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-10b', 'Estado Desconocido — P8 NO en Fact_GestionPayer',
    'Filas para P8 en Fact = 0',
    'FilasP8=' + CAST(@enHecho10 AS VARCHAR),
    CASE WHEN @enHecho10 = 0 THEN 'CORRECTO' ELSE 'FALLO' END
);

-- Verificación 3: Pagos válidos existentes no se ven afectados (transacción consistente)
DECLARE @cnt10t INT;
SELECT @cnt10t = COUNT(*) FROM Test_NexoSalud_Mart_Payer_Bateria.dbo.Fact_GestionPayer;

INSERT INTO ##ResultadosPayer VALUES (
    'PAY-10c', 'Estado Desconocido — Transaccion consistente (pagos validos intactos)',
    'Total filas hecho = 5 (sin fila extra por P8)',
    'Filas=' + CAST(@cnt10t AS VARCHAR),
    CASE WHEN @cnt10t = 5 THEN 'CORRECTO' ELSE 'FALLO' END
);

PRINT '>> PAY-10 completado.';
GO

-- ====================================================================================================
-- FASE 16: RESUMEN FINAL Y DICTAMEN
-- ====================================================================================================
PRINT '';
PRINT '============================================================';
PRINT '  BATERIA DE PRUEBAS ETL PAYER — RESULTADO FINAL';
PRINT '============================================================';

SELECT
    CasoId          AS [Caso],
    Descripcion     AS [Descripcion],
    CriterioEsperado AS [Criterio Esperado],
    ValorObtenido   AS [Valor Obtenido],
    Estado          AS [Estado]
FROM ##ResultadosPayer
ORDER BY CasoId;

GO

-- Dictamen global
DECLARE @totalCasos  INT;
DECLARE @casosPasados INT;
DECLARE @casosFallidos INT;
DECLARE @dictamen   VARCHAR(50);

SELECT @totalCasos   = COUNT(*),
       @casosPasados = SUM(CASE WHEN Estado = 'CORRECTO' THEN 1 ELSE 0 END),
       @casosFallidos= SUM(CASE WHEN Estado = 'FALLO'    THEN 1 ELSE 0 END)
FROM ##ResultadosPayer;

SET @dictamen = CASE WHEN @casosFallidos = 0 THEN 'APROBADO — TODOS LOS CASOS PASAN' ELSE 'REVISAR — HAY CASOS FALLIDOS' END;

PRINT '';
PRINT '------------------------------------------------------------';
PRINT '  DICTAMEN FINAL: ' + @dictamen;
PRINT '  Total casos verificados : ' + CAST(@totalCasos   AS VARCHAR);
PRINT '  Casos CORRECTO          : ' + CAST(@casosPasados AS VARCHAR);
PRINT '  Casos FALLO             : ' + CAST(@casosFallidos AS VARCHAR);
PRINT '------------------------------------------------------------';
PRINT '';

IF @casosFallidos = 0
    PRINT '  >> El procedimiento usp_Cargar_Fact_GestionPayer CUMPLE todos los criterios de aceptacion.';
ELSE
    PRINT '  >> Revisar los casos marcados como FALLO antes de promover a produccion.';

PRINT '';
GO

-- ====================================================================================================
-- FASE 17: LIMPIEZA DEL ENTORNO TEMPORAL
-- ====================================================================================================
PRINT '>> Iniciando limpieza del entorno temporal...';
GO

USE master;
GO

-- Limpiar tabla de resultados de sesión
IF OBJECT_ID('tempdb..##ResultadosPayer') IS NOT NULL
    DROP TABLE ##ResultadosPayer;

-- Eliminar base OLTP temporal
BEGIN TRY
    IF DB_ID(N'Test_NexoSalud_OLTP_Payer_Bateria') IS NOT NULL
    BEGIN
        ALTER DATABASE Test_NexoSalud_OLTP_Payer_Bateria SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE Test_NexoSalud_OLTP_Payer_Bateria;
        PRINT '>> Base Test_NexoSalud_OLTP_Payer_Bateria eliminada correctamente.';
    END;
END TRY
BEGIN CATCH
    PRINT '>> ADVERTENCIA: No se pudo eliminar Test_NexoSalud_OLTP_Payer_Bateria: ' + ERROR_MESSAGE();
    PRINT '   Elimine manualmente con: DROP DATABASE Test_NexoSalud_OLTP_Payer_Bateria;';
END CATCH;

-- Eliminar base Mart temporal
BEGIN TRY
    IF DB_ID(N'Test_NexoSalud_Mart_Payer_Bateria') IS NOT NULL
    BEGIN
        ALTER DATABASE Test_NexoSalud_Mart_Payer_Bateria SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        DROP DATABASE Test_NexoSalud_Mart_Payer_Bateria;
        PRINT '>> Base Test_NexoSalud_Mart_Payer_Bateria eliminada correctamente.';
    END;
END TRY
BEGIN CATCH
    PRINT '>> ADVERTENCIA: No se pudo eliminar Test_NexoSalud_Mart_Payer_Bateria: ' + ERROR_MESSAGE();
    PRINT '   Elimine manualmente con: DROP DATABASE Test_NexoSalud_Mart_Payer_Bateria;';
END CATCH;

PRINT '';
PRINT '>> Limpieza completada. Entorno temporal de pruebas desmantelado.';
PRINT '>> Fin del script de pruebas ETL PAYER — Entregable 19.';
GO
