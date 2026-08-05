/*
=============================================================
Database and Schema Setup
=============================================================
Purpose:
    This script creates a database called 'MediSight'. Before creating it,
    the script checks whether the database already exists. If it does, the
    existing database is removed and a new one is created. The script also
    creates three schemas within the database: 'bronze', 'silver', and 'gold'
    — the three layers of the Medallion Architecture.

CAUTION:
    Executing this script will delete the existing 'MediSight' database,
    if present, and then recreate it from scratch. As a result, all objects
    and data stored in the database will be permanently lost. Make sure any
    important data is backed up before running this script.

RUN FREQUENCY:
    Run this anytime you want a guaranteed clean slate (e.g. during
    development, or to restart the full pipeline from scratch).
=============================================================
*/

USE master;
GO

-- Drop and recreate the 'MediSight' database
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'MediSight')
BEGIN
    ALTER DATABASE MediSight SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MediSight;
END;
GO

-- Create the 'MediSight' database
CREATE DATABASE MediSight;
GO

USE MediSight;
GO

-- =====================================================
-- Create Schemas for Medallion Architecture
-- =====================================================
-- bronze = raw / untrusted source data
-- silver = cleaned / validated / trusted data
-- gold   = business-ready / reporting (star schema)

CREATE SCHEMA bronze;
GO

CREATE SCHEMA silver;
GO

CREATE SCHEMA gold;
GO

PRINT 'Database and schemas created successfully.';
GO
