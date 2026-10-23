import docx
import os
import re

print("Iniciando consolidación de Anexos en NexoSalud...")

docx_path = r'D:\Proyects\nexosalud-docs\Contexto\Archivo Anexos Informe.docx'
md_path = r'D:\Proyects\nexosalud-docs\Contexto\Anexos.md'

# 1. Leer Anexos A y B del markdown original
with open(md_path, 'r', encoding='utf-8') as f:
    orig_md = f.read()

pos_c = orig_md.find('# Anexo C')
if pos_c == -1:
    pos_c = orig_md.find('Anexo C')
anexo_ab_md = orig_md[:pos_c].strip()

# 2. Cargar DDL transaccional (Anexo C)
# Leemos el DDL transaccional existente en el docx original
doc_orig = docx.Document(r'D:\Proyects\nexosalud-docs\Contexto\Archivo Anexos Informe_PRE_CONSOLIDATION_BACKUP.docx')
lines_c = [doc_orig.paragraphs[i].text for i in range(89, 1053)]

# Agregamos CREATE DATABASE NexoSaludDB al inicio si no existe
anexo_c_sql_head = """-- ====================================================================
-- NEXOSALUD — BASE DE DATOS TRANSACCIONAL (OLTP)
-- Esquema: NexoSaludDB
-- Motor: Microsoft SQL Server 2019 / 2022
-- ====================================================================

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NexoSaludDB')
BEGIN
    CREATE DATABASE NexoSaludDB;
END;
GO

USE NexoSaludDB;
GO
"""

anexo_c_sql_tail = """
-- ====================================================================
-- POBLAMIENTO INICIAL DE CATÁLOGOS BASE (NexoSaludDB)
-- ====================================================================

INSERT INTO [dbo].[Etapas] ([nombre], [descripcion]) VALUES
('BUYER', 'Contacto identificable con autorización de contacto'),
('LEAD', 'Persona con intención administrativa concreta'),
('PAYER', 'Persona con pago inicial validado'),
('CUSTOMER', 'Persona que recibe el servicio'),
('TURNED', 'Servicio finalizado y gestión postventa');
GO

INSERT INTO [dbo].[Canales] ([nombre]) VALUES
('WhatsApp'),
('Facebook'),
('Instagram'),
('Página Web'),
('Formulario Web'),
('Llamada'),
('Correo Electrónico');
GO

INSERT INTO [dbo].[Modalidades] ([nombre]) VALUES
('Presencial'),
('Virtual');
GO

INSERT INTO [dbo].[Roles] ([nombre]) VALUES
('Administrador'),
('Marketing'),
('Negociador'),
('Cobranza'),
('Soporte'),
('PostVenta');
GO

INSERT INTO [dbo].[Servicios] ([nombre], [descripcion]) VALUES
('Evaluación odontológica', 'Evaluación inicial integral'),
('Limpieza dental', 'Profilaxis y destartraje básico'),
('Curación simple', 'Resina compuesta 1 superficie'),
('Curación compuesta', 'Resina compuesta 2 o más superficies'),
('Extracción simple', 'Pieza anterior o posterior no compleja'),
('Endodoncia unirradicular', 'Tratamiento de conducto 1 conducto'),
('Endodoncia multirradicular', 'Tratamiento de conducto molar'),
('Ortodoncia - Instalación', 'Colocación de brackets metálicos'),
('Blanqueamiento dental', 'Tratamiento estético en consultorio');
GO
"""

anexo_c_sql = anexo_c_sql_head + "\n" + "\n".join(lines_c) + "\n" + anexo_c_sql_tail

# 3. Anexo D: Creación de la Base de Datos Dimensional (NexoSalud_Mart)
anexo_d_sql = """-- ====================================================================
-- NEXOSALUD — DATA MART DIMENSIONAL (MODELO ESTRELLA CONFORMADO)
-- Esquema: NexoSalud_Mart
-- Motor: Microsoft SQL Server 2019 / 2022
-- ====================================================================

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'NexoSalud_Mart')
BEGIN
    CREATE DATABASE NexoSalud_Mart;
END;
GO

USE NexoSalud_Mart;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ====================================================================
-- 1. CREACIÓN DE TABLAS DIMENSIONALES (CONFORMADAS Y DE CATÁLOGO)
-- ====================================================================

-- 1.1 Dimensión Tiempo (Conformada para las etapas analíticas)
IF OBJECT_ID('dbo.Dim_Tiempo', 'U') IS NULL
CREATE TABLE dbo.Dim_Tiempo (
    KeyTiempo INT PRIMARY KEY, 
    id_fecha DATE NOT NULL,
    Anio INT NOT NULL,
    Trimestre INT NOT NULL,
    Mes INT NOT NULL,
    Dia INT NOT NULL
);
GO

-- 1.2 Dimensión Hora (Para PAYER y CUSTOMER)
IF OBJECT_ID('dbo.Dim_Hora', 'U') IS NULL
CREATE TABLE dbo.Dim_Hora (
    KeyHora INT IDENTITY(1,1) PRIMARY KEY,
    id_hora INT NOT NULL,
    Turno VARCHAR(50),
    Hora INT,
    Minuto INT
);
GO

-- 1.3 Dimensión Sede (Conformada para las etapas clínicas y comerciales)
IF OBJECT_ID('dbo.Dim_Sede', 'U') IS NULL
CREATE TABLE dbo.Dim_Sede (
    KeySede INT IDENTITY(1,1) PRIMARY KEY,
    id_sede INT NULL,
    Sede VARCHAR(100),
    Distrito VARCHAR(100),
    Zona VARCHAR(100)
);
GO

-- 1.4 Dimensión Servicio (Conformada para las etapas analíticas)
IF OBJECT_ID('dbo.Dim_Servicio', 'U') IS NULL
CREATE TABLE dbo.Dim_Servicio (
    KeyServicio INT IDENTITY(1,1) PRIMARY KEY,
    id_servicio INT NULL,
    ServicioOdontologico VARCHAR(100),
    Categoria VARCHAR(100),
    Procedimiento VARCHAR(100)
);
GO

-- 1.5 Dimensión Canal (Para BUYER y SEGUIMIENTO)
IF OBJECT_ID('dbo.Dim_Canal', 'U') IS NULL
CREATE TABLE dbo.Dim_Canal (
    KeyCanal INT IDENTITY(1,1) PRIMARY KEY,
    id_canal INT NULL,
    NombreCanal VARCHAR(50),
    TipoMedio VARCHAR(50)
);
GO

-- 1.6 Dimensión Fuente / Campaña (Para BUYER)
IF OBJECT_ID('dbo.Dim_Fuente', 'U') IS NULL
CREATE TABLE dbo.Dim_Fuente (
    KeyFuente INT IDENTITY(1,1) PRIMARY KEY,
    id_fuente INT NULL,
    id_campana INT NULL,
    TipoOrigen VARCHAR(100),
    Campana VARCHAR(150)
);
GO

-- 1.7 Dimensión Estado del Registro (Para BUYER)
IF OBJECT_ID('dbo.Dim_EstadoRegistro', 'U') IS NULL
CREATE TABLE dbo.Dim_EstadoRegistro (
    KeyEstadoRegistro INT IDENTITY(1,1) PRIMARY KEY,
    EstadoCalidad VARCHAR(50),
    AutorizacionContacto VARCHAR(2)
);
GO

-- 1.8 Dimensión Tipo Persona / Perfil Buyer
IF OBJECT_ID('dbo.Dim_TipoPersona', 'U') IS NULL
CREATE TABLE dbo.Dim_TipoPersona (
    KeyTipoPersona INT IDENTITY(1,1) PRIMARY KEY,
    id_persona INT NULL,
    Ocupacion VARCHAR(100),
    RangoEdad VARCHAR(50)
);
GO

-- 1.9 Dimensión Pagador (Para PAYER)
IF OBJECT_ID('dbo.Dim_Pagador', 'U') IS NULL
CREATE TABLE dbo.Dim_Pagador (
    KeyPagador INT IDENTITY(1,1) PRIMARY KEY,
    id_persona INT NULL,
    Ocupacion VARCHAR(100),
    RangoEdad VARCHAR(50),
    EstadoCivil VARCHAR(50),
    NivelIngreso VARCHAR(50)
);
GO

-- 1.10 Dimensión Profesional (Para LEAD, CUSTOMER y TURNED)
IF OBJECT_ID('dbo.Dim_Profesional', 'U') IS NULL
CREATE TABLE dbo.Dim_Profesional (
    KeyProfesional INT IDENTITY(1,1) PRIMARY KEY,
    id_profesional INT NULL,
    Odontologo VARCHAR(100),
    EspecialidadPrincipal VARCHAR(100)
);
GO

-- 1.11 Dimensión Negociador (Para LEAD)
IF OBJECT_ID('dbo.Dim_Negociador', 'U') IS NULL
CREATE TABLE dbo.Dim_Negociador (
    KeyNegociador INT IDENTITY(1,1) PRIMARY KEY,
    id_usuario INT NULL,
    NombreNegociador VARCHAR(100)
);
GO

-- 1.12 Dimensión Pasarela (Para PAYER)
IF OBJECT_ID('dbo.Dim_Pasarela', 'U') IS NULL
CREATE TABLE dbo.Dim_Pasarela (
    KeyPasarela INT IDENTITY(1,1) PRIMARY KEY,
    MetodoPago VARCHAR(50),
    EntidadFinanciera VARCHAR(100),
    TipoMedio VARCHAR(50)
);
GO

-- 1.13 Dimensión Cobro (Para PAYER)
IF OBJECT_ID('dbo.Dim_Cobro', 'U') IS NULL
CREATE TABLE dbo.Dim_Cobro (
    KeyCobro INT IDENTITY(1,1) PRIMARY KEY,
    EstadoPago VARCHAR(50),
    ComprobanteAdjunto VARCHAR(2)
);
GO

-- 1.14 Dimensión Estado Atención (Para CUSTOMER)
IF OBJECT_ID('dbo.Dim_EstadoAtencion', 'U') IS NULL
CREATE TABLE dbo.Dim_EstadoAtencion (
    KeyEstadoAtencion INT IDENTITY(1,1) PRIMARY KEY,
    EstadoFinal VARCHAR(50),
    Asistencia VARCHAR(50)
);
GO

-- ====================================================================
-- 2. CREACIÓN DE TABLAS DE HECHOS (FACT TABLES)
-- ====================================================================

-- 2.1 Hecho: CAPTACIÓN BUYER
IF OBJECT_ID('dbo.Fact_CaptacionBuyer', 'U') IS NULL
CREATE TABLE dbo.Fact_CaptacionBuyer (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyCanal INT FOREIGN KEY REFERENCES dbo.Dim_Canal(KeyCanal),
    KeyFuente INT FOREIGN KEY REFERENCES dbo.Dim_Fuente(KeyFuente),
    KeyTipoPersona INT FOREIGN KEY REFERENCES dbo.Dim_TipoPersona(KeyTipoPersona),
    KeyEstadoRegistro INT FOREIGN KEY REFERENCES dbo.Dim_EstadoRegistro(KeyEstadoRegistro),
    
    -- Medidas
    ContactosRegistrados INT DEFAULT 0,
    ContactosUtilizables INT DEFAULT 0,
    ConversionesALead INT DEFAULT 0,
    TiempoConversionDias INT DEFAULT 0,
    CostoAtribuidoCaptacion DECIMAL(10,2) DEFAULT 0.00
);
GO

-- 2.2 Hecho: NEGOCIACIÓN LEAD
IF OBJECT_ID('dbo.Fact_NegociacionLead', 'U') IS NULL
CREATE TABLE dbo.Fact_NegociacionLead (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyProfesional INT FOREIGN KEY REFERENCES dbo.Dim_Profesional(KeyProfesional),
    KeyNegociador INT FOREIGN KEY REFERENCES dbo.Dim_Negociador(KeyNegociador),
    
    -- Medidas
    LeadsCohorteEvaluable INT DEFAULT 0,
    LeadsConvertidosPayer14Dias INT DEFAULT 0,
    LeadsRequierenRespuesta INT DEFAULT 0,
    LeadsRespuestaUtil15Min INT DEFAULT 0,
    LeadsResultadoFinal INT DEFAULT 0,
    LeadsAbandonados INT DEFAULT 0,
    LeadsEnNegociacion INT DEFAULT 0
);
GO

-- 2.3 Hecho: GESTIÓN PAYER
IF OBJECT_ID('dbo.Fact_GestionPayer', 'U') IS NULL
CREATE TABLE dbo.Fact_GestionPayer (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyHora INT FOREIGN KEY REFERENCES dbo.Dim_Hora(KeyHora),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyFuente INT FOREIGN KEY REFERENCES dbo.Dim_Fuente(KeyFuente),
    KeyPasarela INT FOREIGN KEY REFERENCES dbo.Dim_Pasarela(KeyPasarela),
    KeyPagador INT FOREIGN KEY REFERENCES dbo.Dim_Pagador(KeyPagador),
    KeyCobro INT FOREIGN KEY REFERENCES dbo.Dim_Cobro(KeyCobro),
    
    -- Medidas
    PagosRegistrados INT DEFAULT 0,
    PagosValidados INT DEFAULT 0,
    PagosRechazados INT DEFAULT 0,
    ConversionesACustomer INT DEFAULT 0,
    ImporteTotalCobro DECIMAL(12,2) DEFAULT 0.00,
    CostoTotalTransacciones DECIMAL(10,2) DEFAULT 0.00,
    TiempoTotalValidacionMin INT DEFAULT 0
);
GO

-- 2.4 Hecho: ATENCIÓN CUSTOMER
IF OBJECT_ID('dbo.Fact_AtencionCustomer', 'U') IS NULL
CREATE TABLE dbo.Fact_AtencionCustomer (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeyHora INT FOREIGN KEY REFERENCES dbo.Dim_Hora(KeyHora),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyProfesional INT FOREIGN KEY REFERENCES dbo.Dim_Profesional(KeyProfesional),
    KeyEstadoAtencion INT FOREIGN KEY REFERENCES dbo.Dim_EstadoAtencion(KeyEstadoAtencion),
    
    -- Medidas
    CitasEvaluables INT DEFAULT 0,
    AtencionesRealizadas INT DEFAULT 0,
    CitasConInasistencia INT DEFAULT 0,
    TiempoEnSillonDentalMin INT DEFAULT 0,
    AtencionesFinalizadasConformes INT DEFAULT 0
);
GO

-- 2.5 Hecho: SEGUIMIENTO TURNED
IF OBJECT_ID('dbo.Fact_SeguimientoTurned', 'U') IS NULL
CREATE TABLE dbo.Fact_SeguimientoTurned (
    KeyTiempo INT FOREIGN KEY REFERENCES dbo.Dim_Tiempo(KeyTiempo),
    KeySede INT FOREIGN KEY REFERENCES dbo.Dim_Sede(KeySede),
    KeyServicio INT FOREIGN KEY REFERENCES dbo.Dim_Servicio(KeyServicio),
    KeyProfesional INT FOREIGN KEY REFERENCES dbo.Dim_Profesional(KeyProfesional),
    KeyCanal INT FOREIGN KEY REFERENCES dbo.Dim_Canal(KeyCanal),
    
    -- Medidas
    SeguimientosRegistrados INT DEFAULT 0,
    SeguimientosEfectivos INT DEFAULT 0,
    IncidenciasReportadas INT DEFAULT 0,
    IncidenciasResueltas24h INT DEFAULT 0,
    RetornosCohorte90Dias INT DEFAULT 0,
    PacientesElegiblesRetorno INT DEFAULT 0
);
GO

-- ====================================================================
-- 3. ÍNDICES DE UNICIDAD FÍSICA PARA EL GRANO ANALÍTICO
-- ====================================================================
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_FactCaptacionBuyer_Grain' AND object_id = OBJECT_ID('Fact_CaptacionBuyer'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_FactCaptacionBuyer_Grain 
    ON Fact_CaptacionBuyer (KeyTiempo, KeySede, KeyCanal, KeyFuente, KeyEstadoRegistro);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_FactNegociacionLead_Grain' AND object_id = OBJECT_ID('Fact_NegociacionLead'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_FactNegociacionLead_Grain 
    ON Fact_NegociacionLead (KeyTiempo, KeySede, KeyNegociador, KeyServicio, KeyProfesional);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_FactGestionPayer_Grain' AND object_id = OBJECT_ID('Fact_GestionPayer'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_FactGestionPayer_Grain 
    ON Fact_GestionPayer (KeyTiempo, KeyPasarela, KeyCobro, KeySede, KeyServicio);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_FactAtencionCustomer_Grain' AND object_id = OBJECT_ID('Fact_AtencionCustomer'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_FactAtencionCustomer_Grain 
    ON Fact_AtencionCustomer (KeyTiempo, KeySede, KeyServicio, KeyProfesional, KeyEstadoAtencion);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_FactSeguimientoTurned_Grain' AND object_id = OBJECT_ID('Fact_SeguimientoTurned'))
    CREATE UNIQUE NONCLUSTERED INDEX UQ_FactSeguimientoTurned_Grain 
    ON Fact_SeguimientoTurned (KeyTiempo, KeySede, KeyServicio, KeyProfesional, KeyCanal);
GO
"""

# 4. Anexo E: Poblamiento Inicial y Homologación de Dimensiones
anexo_e_sql = """-- ====================================================================
-- NEXOSALUD — DATA MART DIMENSIONAL (NexoSalud_Mart)
-- POBLAMIENTO INICIAL, MIEMBROS CANÓNICOS (KEY=0) Y HOMOLOGACIÓN SCD TIPO 1
-- Motor: Microsoft SQL Server 2019 / 2022
-- ====================================================================

USE NexoSalud_Mart;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ====================================================================
-- 1. POBLAMIENTO INICIAL DIM_TIEMPO (CALENDARIO 2024 A 2030)
-- ====================================================================
IF (SELECT COUNT(*) FROM dbo.Dim_Tiempo WHERE KeyTiempo > 0) = 0
BEGIN
    DECLARE @StartDate DATE = '2024-01-01';
    DECLARE @EndDate DATE = '2030-12-31';

    WITH Fechas AS (
        SELECT @StartDate AS Fecha
        UNION ALL
        SELECT DATEADD(DAY, 1, Fecha)
        FROM Fechas
        WHERE DATEADD(DAY, 1, Fecha) <= @EndDate
    )
    INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha, Anio, Trimestre, Mes, Dia)
    SELECT 
        CAST(FORMAT(Fecha, 'yyyyMMdd') AS INT) AS KeyTiempo,
        Fecha AS id_fecha,
        YEAR(Fecha) AS Anio,
        DATEPART(QUARTER, Fecha) AS Trimestre,
        MONTH(Fecha) AS Mes,
        DAY(Fecha) AS Dia
    FROM Fechas
    OPTION (MAXRECURSION 0);
END;
GO

-- ====================================================================
-- 2. REGLA KIMBALL: MIEMBROS DESCONOCIDOS CANÓNICOS (KEY = 0)
-- Garantiza que claves foráneas huérfanas o nulas nunca rompan la integridad
-- ni se atribuyan falsamente a entidades con Key = 1.
-- ====================================================================

-- 2.1 Dim_Tiempo (KeyTiempo = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Tiempo WHERE KeyTiempo = 0)
BEGIN
    INSERT INTO dbo.Dim_Tiempo (KeyTiempo, id_fecha, Anio, Trimestre, Mes, Dia)
    VALUES (0, '1900-01-01', 1900, 1, 1, 1);
END;
GO

-- 2.2 Dim_Sede (KeySede = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Sede WHERE KeySede = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Sede ON;
    INSERT INTO dbo.Dim_Sede (KeySede, id_sede, Sede, Distrito, Zona)
    VALUES (0, 0, 'Sede No Especificada', 'No Especificado', 'No Especificado');
    SET IDENTITY_INSERT dbo.Dim_Sede OFF;
END;
GO

-- 2.3 Dim_Servicio (KeyServicio = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Servicio WHERE KeyServicio = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Servicio ON;
    INSERT INTO dbo.Dim_Servicio (KeyServicio, id_servicio, ServicioOdontologico, Categoria, Procedimiento)
    VALUES (0, 0, 'Servicio No Especificado', 'General', 'No Especificado');
    SET IDENTITY_INSERT dbo.Dim_Servicio OFF;
END;
GO

-- 2.4 Dim_Canal (KeyCanal = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Canal WHERE KeyCanal = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Canal ON;
    INSERT INTO dbo.Dim_Canal (KeyCanal, id_canal, NombreCanal, TipoMedio)
    VALUES (0, 0, 'Canal Desconocido', 'No Especificado');
    SET IDENTITY_INSERT dbo.Dim_Canal OFF;
END;
GO

-- 2.5 Dim_Fuente (KeyFuente = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Fuente WHERE KeyFuente = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Fuente ON;
    INSERT INTO dbo.Dim_Fuente (KeyFuente, id_fuente, id_campana, TipoOrigen, Campana)
    VALUES (0, 0, 0, 'Fuente No Especificada', 'Sin Campaña');
    SET IDENTITY_INSERT dbo.Dim_Fuente OFF;
END;
GO

-- 2.6 Dim_EstadoRegistro (KeyEstadoRegistro = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_EstadoRegistro WHERE KeyEstadoRegistro = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_EstadoRegistro ON;
    INSERT INTO dbo.Dim_EstadoRegistro (KeyEstadoRegistro, EstadoCalidad, AutorizacionContacto)
    VALUES (0, 'Desconocido', 'NO');
    SET IDENTITY_INSERT dbo.Dim_EstadoRegistro OFF;
END;
GO

-- 2.7 Dim_Profesional (KeyProfesional = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Profesional WHERE KeyProfesional = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Profesional ON;
    INSERT INTO dbo.Dim_Profesional (KeyProfesional, id_profesional, Odontologo, EspecialidadPrincipal)
    VALUES (0, 0, 'Profesional No Asignado', 'No Especificada');
    SET IDENTITY_INSERT dbo.Dim_Profesional OFF;
END;
GO

-- 2.8 Dim_Negociador (KeyNegociador = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Negociador WHERE KeyNegociador = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Negociador ON;
    INSERT INTO dbo.Dim_Negociador (KeyNegociador, id_usuario, NombreNegociador)
    VALUES (0, 0, 'Negociador No Asignado');
    SET IDENTITY_INSERT dbo.Dim_Negociador OFF;
END;
GO

-- 2.9 Dim_Pasarela (KeyPasarela = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Pasarela WHERE KeyPasarela = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Pasarela ON;
    INSERT INTO dbo.Dim_Pasarela (KeyPasarela, MetodoPago, EntidadFinanciera, TipoMedio)
    VALUES (0, 'No Especificado', 'No Especificada', 'No Especificado');
    SET IDENTITY_INSERT dbo.Dim_Pasarela OFF;
END;
GO

-- 2.10 Dim_Cobro (KeyCobro = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Cobro WHERE KeyCobro = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Cobro ON;
    INSERT INTO dbo.Dim_Cobro (KeyCobro, EstadoPago, ComprobanteAdjunto)
    VALUES (0, 'NO DEFINIDO', 'NO');
    SET IDENTITY_INSERT dbo.Dim_Cobro OFF;
END;
GO

-- 2.11 Dim_EstadoAtencion (KeyEstadoAtencion = 0)
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_EstadoAtencion WHERE KeyEstadoAtencion = 0)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_EstadoAtencion ON;
    INSERT INTO dbo.Dim_EstadoAtencion (KeyEstadoAtencion, EstadoFinal, Asistencia)
    VALUES (0, 'No Definido', 'No Definido');
    SET IDENTITY_INSERT dbo.Dim_EstadoAtencion OFF;
END;
GO

-- ====================================================================
-- 3. HOMOLOGACIÓN Y POBLAMIENTO INICIAL SCD TIPO 1 (OLTP -> OLAP)
-- ====================================================================

-- 3.1 Homologación Dim_Sede
UPDATE dim
SET dim.Sede = oltp.Sede, dim.Distrito = oltp.Distrito, dim.Zona = oltp.Zona
FROM dbo.Dim_Sede dim
JOIN (
    SELECT id_sede, nombre AS Sede, zona AS Distrito, zona AS Zona 
    FROM [NexoSaludDB].dbo.[Sedes]
) oltp ON dim.id_sede = oltp.id_sede;

INSERT INTO dbo.Dim_Sede (id_sede, Sede, Distrito, Zona)
SELECT oltp.id_sede, oltp.Sede, oltp.Distrito, oltp.Zona
FROM (
    SELECT id_sede, nombre AS Sede, zona AS Distrito, zona AS Zona 
    FROM [NexoSaludDB].dbo.[Sedes]
) oltp
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Sede dim WHERE dim.id_sede = oltp.id_sede
);
GO

-- 3.2 Homologación Dim_Servicio
UPDATE dim
SET dim.ServicioOdontologico = oltp.ServicioOdontologico, dim.Categoria = oltp.Categoria, dim.Procedimiento = oltp.Procedimiento
FROM dbo.Dim_Servicio dim
JOIN (
    SELECT 
        id_servicio, 
        nombre AS ServicioOdontologico, 
        CASE 
            WHEN descripcion LIKE '%Preventiva%' THEN 'Odontología Preventiva'
            WHEN descripcion LIKE '%Especializada%' THEN 'Odontología Especializada'
            WHEN descripcion LIKE '%Restauradora%' THEN 'Odontología Restauradora'
            WHEN descripcion LIKE '%Estética%' THEN 'Odontología Estética'
            ELSE 'Odontología General'
        END AS Categoria, 
        nombre AS Procedimiento
    FROM [NexoSaludDB].dbo.[Servicios]
) oltp ON dim.id_servicio = oltp.id_servicio;

INSERT INTO dbo.Dim_Servicio (id_servicio, ServicioOdontologico, Categoria, Procedimiento)
SELECT oltp.id_servicio, oltp.ServicioOdontologico, oltp.Categoria, oltp.Procedimiento
FROM (
    SELECT 
        id_servicio, 
        nombre AS ServicioOdontologico, 
        CASE 
            WHEN descripcion LIKE '%Preventiva%' THEN 'Odontología Preventiva'
            WHEN descripcion LIKE '%Especializada%' THEN 'Odontología Especializada'
            WHEN descripcion LIKE '%Restauradora%' THEN 'Odontología Restauradora'
            WHEN descripcion LIKE '%Estética%' THEN 'Odontología Estética'
            ELSE 'Odontología General'
        END AS Categoria, 
        nombre AS Procedimiento
    FROM [NexoSaludDB].dbo.[Servicios]
) oltp
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Servicio dim WHERE dim.id_servicio = oltp.id_servicio
);
GO

-- 3.3 Homologación Dim_Canal
UPDATE dim
SET dim.NombreCanal = oltp.NombreCanal, dim.TipoMedio = oltp.TipoMedio
FROM dbo.Dim_Canal dim
JOIN (
    SELECT id_canal, nombre AS NombreCanal, 'Digital' AS TipoMedio
    FROM [NexoSaludDB].dbo.[Canales]
) oltp ON dim.id_canal = oltp.id_canal;

INSERT INTO dbo.Dim_Canal (id_canal, NombreCanal, TipoMedio)
SELECT oltp.id_canal, oltp.NombreCanal, oltp.TipoMedio
FROM (
    SELECT id_canal, nombre AS NombreCanal, 'Digital' AS TipoMedio
    FROM [NexoSaludDB].dbo.[Canales]
) oltp
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Canal dim WHERE dim.id_canal = oltp.id_canal
);
GO

-- 3.4 Homologación Dim_Fuente
UPDATE dim
SET dim.TipoOrigen = oltp.TipoOrigen, dim.Campana = oltp.Campana
FROM dbo.Dim_Fuente dim
JOIN (
    SELECT 
        c.id_fuente,
        c.id_campana,
        f.nombre AS TipoOrigen,
        c.nombre AS Campana
    FROM [NexoSaludDB].dbo.[Campanas] c
    JOIN [NexoSaludDB].dbo.[Fuentes] f ON c.id_fuente = f.id_fuente
) oltp ON dim.id_campana = oltp.id_campana;

INSERT INTO dbo.Dim_Fuente (id_fuente, id_campana, TipoOrigen, Campana)
SELECT oltp.id_fuente, oltp.id_campana, oltp.TipoOrigen, oltp.Campana
FROM (
    SELECT 
        c.id_fuente,
        c.id_campana,
        f.nombre AS TipoOrigen,
        c.nombre AS Campana
    FROM [NexoSaludDB].dbo.[Campanas] c
    JOIN [NexoSaludDB].dbo.[Fuentes] f ON c.id_fuente = f.id_fuente
) oltp
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Fuente dim WHERE dim.id_campana = oltp.id_campana
);
GO

-- 3.5 Homologación Dim_Profesional
UPDATE dim
SET dim.Odontologo = oltp.Odontologo, dim.EspecialidadPrincipal = oltp.EspecialidadPrincipal
FROM dbo.Dim_Profesional dim
JOIN (
    SELECT id_profesional, CONCAT(nombres, ' ', apellidos) AS Odontologo, especialidad AS EspecialidadPrincipal
    FROM [NexoSaludDB].dbo.[Profesionales]
) oltp ON dim.id_profesional = oltp.id_profesional;

INSERT INTO dbo.Dim_Profesional (id_profesional, Odontologo, EspecialidadPrincipal)
SELECT oltp.id_profesional, oltp.Odontologo, oltp.EspecialidadPrincipal
FROM (
    SELECT id_profesional, CONCAT(nombres, ' ', apellidos) AS Odontologo, especialidad AS EspecialidadPrincipal
    FROM [NexoSaludDB].dbo.[Profesionales]
) oltp
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Profesional dim WHERE dim.id_profesional = oltp.id_profesional
);
GO

-- 3.6 Homologación Dim_Negociador
UPDATE dim
SET dim.NombreNegociador = oltp.NombreNegociador
FROM dbo.Dim_Negociador dim
JOIN (
    SELECT id_usuario, CONCAT(nombres, ' ', apellidos) AS NombreNegociador
    FROM [NexoSaludDB].dbo.[Usuarios]
) oltp ON dim.id_usuario = oltp.id_usuario;

INSERT INTO dbo.Dim_Negociador (id_usuario, NombreNegociador)
SELECT oltp.id_usuario, oltp.NombreNegociador
FROM (
    SELECT id_usuario, CONCAT(nombres, ' ', apellidos) AS NombreNegociador
    FROM [NexoSaludDB].dbo.[Usuarios]
) oltp
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Negociador dim WHERE dim.id_usuario = oltp.id_usuario
);
GO

-- 3.7 Homologación Dim_Pasarela
UPDATE dim
SET dim.EntidadFinanciera = src.EntidadFinanciera, dim.TipoMedio = src.TipoMedio
FROM dbo.Dim_Pasarela dim
JOIN (
    SELECT 1 AS KeyPasarela, 'Plin' AS MetodoPago, 'Interbank/BBVA' AS EntidadFinanciera, 'Billeteras Digitales' AS TipoMedio
    UNION ALL SELECT 2, 'Tarjeta (Web)', 'Niubiz/Culqi', 'Bancarizado'
    UNION ALL SELECT 3, 'Transferencia', 'Interbancaria', 'Bancarizado'
    UNION ALL SELECT 4, 'Yape', 'BCP', 'Billeteras Digitales'
) src ON dim.KeyPasarela = src.KeyPasarela;

INSERT INTO dbo.Dim_Pasarela (MetodoPago, EntidadFinanciera, TipoMedio)
SELECT src.MetodoPago, src.EntidadFinanciera, src.TipoMedio
FROM (
    SELECT 1 AS KeyPasarela, 'Plin' AS MetodoPago, 'Interbank/BBVA' AS EntidadFinanciera, 'Billeteras Digitales' AS TipoMedio
    UNION ALL SELECT 2, 'Tarjeta (Web)', 'Niubiz/Culqi', 'Bancarizado'
    UNION ALL SELECT 3, 'Transferencia', 'Interbancaria', 'Bancarizado'
    UNION ALL SELECT 4, 'Yape', 'BCP', 'Billeteras Digitales'
) src
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Pasarela dim WHERE dim.MetodoPago = src.MetodoPago
);
GO

-- 3.8 Homologación Dim_Cobro
UPDATE dim
SET dim.EstadoPago = src.EstadoPago, dim.ComprobanteAdjunto = src.ComprobanteAdjunto
FROM dbo.Dim_Cobro dim
JOIN (
    SELECT 1 AS KeyCobro, 'VALIDATED' AS EstadoPago, 'SI' AS ComprobanteAdjunto
    UNION ALL SELECT 2, 'PENDING', 'NO'
    UNION ALL SELECT 3, 'REJECTED', 'NO'
    UNION ALL SELECT 4, 'Confirmado', 'SI'
    UNION ALL SELECT 5, 'Pendiente', 'NO'
    UNION ALL SELECT 6, 'Fallido', 'NO'
) src ON dim.KeyCobro = src.KeyCobro;

INSERT INTO dbo.Dim_Cobro (EstadoPago, ComprobanteAdjunto)
SELECT src.EstadoPago, src.ComprobanteAdjunto
FROM (
    SELECT 1 AS KeyCobro, 'VALIDATED' AS EstadoPago, 'SI' AS ComprobanteAdjunto
    UNION ALL SELECT 2, 'PENDING', 'NO'
    UNION ALL SELECT 3, 'REJECTED', 'NO'
    UNION ALL SELECT 4, 'Confirmado', 'SI'
    UNION ALL SELECT 5, 'Pendiente', 'NO'
    UNION ALL SELECT 6, 'Fallido', 'NO'
) src
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_Cobro dim WHERE dim.EstadoPago = src.EstadoPago
);
GO

-- 3.9 Homologación Dim_EstadoAtencion
UPDATE dim
SET dim.EstadoFinal = src.EstadoFinal, dim.Asistencia = src.Asistencia
FROM dbo.Dim_EstadoAtencion dim
JOIN (
    SELECT 1 AS KeyEstadoAtencion, 'Completada' AS EstadoFinal, 'Asistió' AS Asistencia
    UNION ALL SELECT 2, 'No Asistió', 'Inasistencia'
    UNION ALL SELECT 3, 'Cancelados', 'Cancelado'
) src ON dim.KeyEstadoAtencion = src.KeyEstadoAtencion;

INSERT INTO dbo.Dim_EstadoAtencion (EstadoFinal, Asistencia)
SELECT src.EstadoFinal, src.Asistencia
FROM (
    SELECT 1 AS KeyEstadoAtencion, 'Completada' AS EstadoFinal, 'Asistió' AS Asistencia
    UNION ALL SELECT 2, 'No Asistió', 'Inasistencia'
    UNION ALL SELECT 3, 'Cancelados', 'Cancelado'
) src
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Dim_EstadoAtencion dim WHERE dim.EstadoFinal = src.EstadoFinal
);
GO
"""

# 5. Anexo F: Poblamiento de la Base Dimensional mediante INSERT (database/etl_populate_mart_insert.sql)
with open(r'D:\Proyects\Proyecto-IN-Odontolog-a-\database\etl_populate_mart_insert.sql', 'r', encoding='utf-8') as f:
    anexo_f_sql = f.read()

# 6. Anexo G: Guía de Ejecución y Comandos
anexo_g_text = """# Anexo G

**Orden de Ejecución y Guía de Comandos de Reproducción**

La secuencia técnica para reproducir de forma determinista la creación de las bases de datos transaccional y analítica, la carga de catálogos y el poblamiento incremental mediante la estrategia `INSERT` desde una instalación limpia de SQL Server es la siguiente:

### 1. Requisitos Previos del Entorno
- **Motor de Base de Datos:** Microsoft SQL Server 2019 o 2022 instalado en `localhost:1433`.
- **Modo de Autenticación:** Autenticación de Windows (`Trusted_Connection=yes`) o Autenticación Mixta (usuario `sa`).
- **Entorno de Ejecución Backend:** Node.js v18+ y paquete `tsx` para ejecución directa de scripts TypeScript sin compilación previa.

---

### 2. Secuencia de Dependencias y Ejecución en SQL Server (SSMS o sqlcmd)

#### Paso 1: Creación de la Base de Datos Transaccional (OLTP)
Ejecutar el script del **Anexo C** para crear la base de datos `NexoSaludDB`, sus 30 tablas con claves primarias, foráneas, restricciones `CHECK`, valores por defecto e inserción de catálogos básicos (`Etapas`, `Canales`, `Modalidades`, `Roles`, `Servicios`).
```powershell
sqlcmd -S localhost -E -C -i database/init_oltp.sql
```

#### Paso 2 (Opcional): Carga de Datos de Prueba Transaccionales
Si se requiere sembrar datos sintéticos de prueba con volumen para simular el flujo comercial y clínico de la clínica:
```powershell
sqlcmd -S localhost -E -C -d NexoSaludDB -i database/seed/01_catalogos.sql
sqlcmd -S localhost -E -C -d NexoSaludDB -i database/seed/02_validacion.sql
sqlcmd -S localhost -E -C -d NexoSaludDB -i database/seed/03_disponibilidades_masivas.sql
```

#### Paso 3: Creación de la Base de Datos Dimensional (OLAP / Data Mart)
Ejecutar el script del **Anexo D** para crear la base de datos `NexoSalud_Mart`, sus 14 tablas dimensionales, las 5 tablas de hechos (`Fact_CaptacionBuyer`, `Fact_NegociacionLead`, `Fact_GestionPayer`, `Fact_AtencionCustomer`, `Fact_SeguimientoTurned`) y los 5 índices únicos de grano compuesto (`UQ_Fact*_Grain`).
```powershell
sqlcmd -S localhost -E -C -i database/init_mart.sql
```

#### Paso 4: Poblamiento Inicial y Homologación de Dimensiones
Ejecutar el script del **Anexo E** para generar la dimensión `Dim_Tiempo` (calendario 2024 al 2030), inicializar con `SET IDENTITY_INSERT ON` los miembros desconocidos canónicos Kimball `Key = 0` ('No Especificado') y homologar los catálogos transaccionales hacia las dimensiones mediante SCD Tipo 1.
```powershell
sqlcmd -S localhost -E -C -d NexoSalud_Mart -i database/seed_dimensions.sql
```

#### Paso 5: Poblamiento Incremental de Hechos mediante la Estrategia INSERT
Ejecutar el script del **Anexo F** (`database/etl_populate_mart_insert.sql`) que contiene la lógica completa de:
1. Adquisición del candado exclusivo de sesión con `sp_getapplock @Resource = 'ETL_NexoSalud_Lock'`.
2. Extracción agregada por grano hacia tablas temporales `#Staging_*`.
3. Actualización in-place mediante `UPDATE ... FROM #Staging s JOIN Fact f ON (Grano) WHERE (Medidas distintas)`.
4. Inserción de novedades mediante `INSERT INTO Fact (...) SELECT ... WHERE NOT EXISTS (Grano)`.
5. Poda y reconciliación de grupos obsoletos mediante `DELETE f FROM Fact f WHERE NOT EXISTS (SELECT 1 FROM #Staging s WHERE Grano)`.
6. Registro de telemetría, duración en segundos y filas modificadas en `dbo.Log_Ejecucion_ETL`.

---

### 3. Ejecución desde el Backend (Node.js / TypeScript)

El backend de NexoSalud dispone del lanzador unificado `run-etl.ts`, el cual soporta la ejecución de la estrategia incremental `INSERT` mediante el parámetro `--strategy=insert`:

```powershell
# Ubicarse en el directorio del backend
cd D:\\Proyects\\Proyecto-IN-Odontolog-a-\\backend

# Ejecución de la estrategia incremental UPDATE + INSERT (WHERE NOT EXISTS)
npx tsx src/scripts/run-etl.ts --strategy=insert

# Ejecución de la suite completa de 10 pruebas comparativas
npx tsx src/scripts/test-compare-insert-merge.ts

# Verificación de reportes agregados consumidos por los dashboards
npx tsx src/scripts/test-etl-aggregations.ts
```

---

### 4. Consultas de Verificación y Auditoría en SQL Server

Para comprobar el estado final de las tablas de hechos y la auditoría de ejecución:
```sql
USE NexoSalud_Mart;
GO

-- 1. Inspeccionar últimos eventos de ejecución del ETL
SELECT TOP 5 
    BatchId, Procedimiento, TipoEvento, Mensaje, FilasAfectadas, DuracionSegundos, FechaRegistro
FROM dbo.Log_Ejecucion_ETL 
ORDER BY LogId DESC;

-- 2. Conteo de registros por tabla de hechos
SELECT 'Fact_CaptacionBuyer' AS Tabla, COUNT(*) AS Filas FROM Fact_CaptacionBuyer
UNION ALL SELECT 'Fact_NegociacionLead', COUNT(*) FROM Fact_NegociacionLead
UNION ALL SELECT 'Fact_GestionPayer', COUNT(*) FROM Fact_GestionPayer
UNION ALL SELECT 'Fact_AtencionCustomer', COUNT(*) FROM Fact_AtencionCustomer
UNION ALL SELECT 'Fact_SeguimientoTurned', COUNT(*) FROM Fact_SeguimientoTurned;
```
"""

# ====================================================================
# GUARDAR EL ARCHIVO MARKDOWN CONSOLIDADO (Anexos.md)
# ====================================================================
full_md = f"""{anexo_ab_md}

# Anexo C

**Script de Base de Datos Transaccional (OLTP — NexoSaludDB)**

El siguiente script crea la base de datos transaccional `NexoSaludDB`, sus 30 tablas operativas, claves primarias, claves foráneas, restricciones de integridad `CHECK`, valores por defecto y poblamiento inicial de catálogos base indispensables.

```sql
{anexo_c_sql.strip()}
```

# Anexo D

**Script de Creación de la Base de Datos Dimensional (OLAP / Data Mart — NexoSalud_Mart)**

El siguiente script crea la base de datos analítica `NexoSalud_Mart`, sus 14 tablas dimensionales con claves subrogadas, las 5 tablas de hechos del modelo conformado en PascalCase (`Fact_CaptacionBuyer`, `Fact_NegociacionLead`, `Fact_GestionPayer`, `Fact_AtencionCustomer`, `Fact_SeguimientoTurned`) y los 5 índices únicos físicos de grano compuesto (`UQ_Fact*_Grain`).

```sql
{anexo_d_sql.strip()}
```

# Anexo E

**Poblamiento Inicial y Homologación de Dimensiones (SCD Tipo 1 y Miembros Desconocidos Key = 0)**

El siguiente script genera la dimensión `Dim_Tiempo` (calendario 2024 al 2030), establece la regla canónica Kimball insertando con `SET IDENTITY_INSERT ON` el miembro desconocido `Key = 0` ('No Especificado') en las 8 dimensiones analíticas para garantizar la integridad referencial de claves foráneas huérfanas, y sincroniza mediante SCD Tipo 1 los catálogos del OLTP.

```sql
{anexo_e_sql.strip()}
```

# Anexo F

**Poblamiento Incremental de la Base Dimensional mediante la Estrategia INSERT**

El siguiente script corresponde a la implementación vigente de `database/etl_populate_mart_insert.sql`. Implementa la carga incremental, no destructiva e idempotente de las 5 tablas de hechos basada en la preparación de datos en tablas temporales `#Staging_*`, `UPDATE` in-place condicional de métricas modificadas, `INSERT ... WHERE NOT EXISTS` sobre el grano compuesto, reconciliación selectiva de grupos obsoletos con `DELETE ... WHERE NOT EXISTS`, exclusión mutua de concurrencia mediante `sp_getapplock` y auditoría en `dbo.Log_Ejecucion_ETL`.

```sql
{anexo_f_sql.strip()}
```

{anexo_g_text.strip()}
"""

with open(md_path, 'w', encoding='utf-8') as f:
    f.write(full_md)
print(f"[OK] Archivo Markdown actualizado exitosamente: {md_path} ({len(full_md)} caracteres)")

# ====================================================================
# GUARDAR EL ARCHIVO WORD CONSOLIDADO (Archivo Anexos Informe.docx)
# ====================================================================
doc = docx.Document(r'D:\Proyects\nexosalud-docs\Contexto\Archivo Anexos Informe_PRE_CONSOLIDATION_BACKUP.docx')

# Conservamos Anexos A y B (párrafos 0 a 86) y eliminamos los párrafos a partir del índice 87
p_to_remove = [p._p for p in doc.paragraphs[87:]]
for p in p_to_remove:
    p.getparent().remove(p)

print(f"Párrafos base conservados (Anexo A y B): {len(doc.paragraphs)}")

def add_anexo_to_doc(document, title, description, code_or_text, is_sql=True):
    # Título Heading 1
    h = document.add_paragraph(title, style='Heading 1')
    # Descripción
    d = document.add_paragraph(description)
    # Bloque de código / texto
    if is_sql:
        for line in code_or_text.strip().split('\n'):
            document.add_paragraph(line)
    else:
        for line in code_or_text.strip().split('\n'):
            if line.startswith('### '):
                document.add_paragraph(line[4:], style='Heading 2')
            elif line.startswith('#### '):
                document.add_paragraph(line[5:], style='Heading 3')
            else:
                document.add_paragraph(line)

print("Añadiendo Anexo C al documento Word...")
add_anexo_to_doc(
    doc,
    "Anexo C. Script de Base de Datos Transaccional (OLTP — NexoSaludDB)",
    "Script DDL completo para la creación de la base de datos NexoSaludDB, sus 30 tablas operativas, claves primarias, foráneas, restricciones CHECK, valores por defecto y poblamiento inicial de catálogos base.",
    anexo_c_sql,
    is_sql=True
)

print("Añadiendo Anexo D al documento Word...")
add_anexo_to_doc(
    doc,
    "Anexo D. Script de Creación de la Base de Datos Dimensional (OLAP — NexoSalud_Mart)",
    "Script DDL completo para la creación de la base de datos NexoSalud_Mart, sus 14 dimensiones conformadas y de catálogo, las 5 tablas de hechos en PascalCase y los 5 índices únicos físicos de grano compuesto.",
    anexo_d_sql,
    is_sql=True
)

print("Añadiendo Anexo E al documento Word...")
add_anexo_to_doc(
    doc,
    "Anexo E. Poblamiento Inicial y Homologación de Dimensiones (SCD Tipo 1 y Miembros Desconocidos Key = 0)",
    "Script para la generación de la dimensión Dim_Tiempo (calendario 2024 al 2030), inicialización canónica Kimball del miembro desconocido Key = 0 ('No Especificado') en las 8 dimensiones analíticas y homologación SCD Tipo 1 desde NexoSaludDB.",
    anexo_e_sql,
    is_sql=True
)

print("Añadiendo Anexo F al documento Word...")
add_anexo_to_doc(
    doc,
    "Anexo F. Poblamiento Incremental de la Base Dimensional mediante la Estrategia INSERT",
    "Script oficial vigente de etl_populate_mart_insert.sql. Carga incremental, no destructiva e idempotente de las 5 tablas de hechos mediante UPDATE in-place de métricas modificadas, INSERT ... WHERE NOT EXISTS, reconciliación selectiva de obsoletos, exclusión mutua con sp_getapplock y telemetría en Log_Ejecucion_ETL.",
    anexo_f_sql,
    is_sql=True
)

print("Añadiendo Anexo G al documento Word...")
add_anexo_to_doc(
    doc,
    "Anexo G. Orden de Ejecución y Guía de Comandos de Reproducción",
    "Secuencia exacta de dependencias, scripts de carga, comandos de ejecución en SSMS/sqlcmd y comando verificado de ejecución desde el backend (npx tsx src/scripts/run-etl.ts --strategy=insert).",
    anexo_g_text,
    is_sql=False
)

doc.save(docx_path)
print(f"[OK] Archivo Word actualizado exitosamente: {docx_path}")
print(f"Total párrafos finales en Word: {len(doc.paragraphs)}")
