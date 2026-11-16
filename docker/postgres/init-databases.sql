-- Exécuté une seule fois, à la création du volume pgdata (docker-entrypoint-initdb.d).
-- Une base et un rôle par service (spec §3, ADR-000 D2) : un service ne peut pas
-- se connecter à la base d'un autre.

CREATE ROLE payment LOGIN;
CREATE DATABASE payment_db OWNER payment;
REVOKE ALL ON DATABASE payment_db FROM PUBLIC;

CREATE ROLE account LOGIN;
CREATE DATABASE account_db OWNER account;
REVOKE ALL ON DATABASE account_db FROM PUBLIC;

CREATE ROLE savings LOGIN;
CREATE DATABASE savings_db OWNER savings;
REVOKE ALL ON DATABASE savings_db FROM PUBLIC;
