# Lovable Database

PostgreSQL database to persist users, projects, files, chat history, templates, versions, deployments, and audit events.

Ports
- Logical port: 5000 (use your actual Postgres port if different)

Environment variables (example)
- POSTGRES_URL: Connection URL (postgresql://USER:PASSWORD@HOST:PORT/DBNAME)
- POSTGRES_USER
- POSTGRES_PASSWORD
- POSTGRES_DB
- POSTGRES_PORT

Backend DATABASE_URL (for SQLAlchemy async)
- Use postgresql+asyncpg://USER:PASSWORD@HOST:PORT/DBNAME
- Example:
  DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/lovable

Local development
- The backend .env.example defaults to SQLite for ease of setup. When ready to use Postgres:
  1) Provision a Postgres instance.
  2) Update lovable_backend_api/.env -> DATABASE_URL to asyncpg URL.
  3) Run migrations (Alembic) if configured.
