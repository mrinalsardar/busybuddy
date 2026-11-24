-- Runs once, when the database volume is first created. The Supabase Postgres
-- image creates these roles without a password; Auth and REST log in with them.
alter user authenticator with password 'postgres';
alter user supabase_auth_admin with password 'postgres';
