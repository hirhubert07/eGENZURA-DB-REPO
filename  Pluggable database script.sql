-- Creating a pluggable database

CREATE PLUGGABLE DATABASE D_28310_HAGUMA_eGENZURA_DB
     ADMIN USER haguma07 IDENTIFIED BY hubert
     ROLES = (DBA)           
FILE_NAME_CONVERT=('C:\app\user\product\23ai\oradata\FREE\PDBSEED\',
'C:\app\user\product\23ai\oradata\FREE\D_28310_HAGUMA_eGENZURA_DB\' );

-- Opening the database 
alter pluggable database D_28310_HAGUMA_EGENZURA_DB open;

--	Database configuration
CREATE TABLESPACE eGENZURA_data DATAFILE 'eGENZURA_data01.dbf' SIZE 100M AUTOEXTEND ON;
CREATE TABLESPACE eGENZURA_index DATAFILE 'eGENZURA_index01.dbf' SIZE 50M AUTOEXTEND ON;
CREATE TEMPORARY TABLESPACE eGENZURA_temp TEMPFILE 'eGENZURA_temp01.dbf' SIZE 50M AUTOEXTEND ON;
