#!/bin/bash

# Minimal PostgreSQL startup script with full paths + schema creation and seed data
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
    echo "Database: ${DB_NAME}"
    echo "User: ${DB_USER}"
    echo "Port: ${DB_PORT}"
    echo ""
    echo "To connect to the database, use:"
    echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
    
    # Check if connection info file exists
    if [ -f "db_connection.txt" ]; then
        echo "Or use: $(cat db_connection.txt)"
    fi
else
    # Also check if there's a PostgreSQL process running (in case pg_isready fails)
    if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
        echo "Found existing PostgreSQL process on port ${DB_PORT}"
        echo "Attempting to verify connection..."
        
        # Try to connect and verify the database exists
        if sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c '\q' 2>/dev/null; then
            echo "Database ${DB_NAME} is accessible."
            ALREADY_RUNNING=1
        fi
    fi

    # Initialize PostgreSQL data directory if it doesn't exist
    if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
        echo "Initializing PostgreSQL..."
        sudo -u postgres ${PG_BIN}/initdb -D /var/lib/postgresql/data
    fi

    # Start PostgreSQL server in background if not already running
    if ! sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
      echo "Starting PostgreSQL server..."
      sudo -u postgres ${PG_BIN}/postgres -D /var/lib/postgresql/data -p ${DB_PORT} &
      # Wait for PostgreSQL to start
      echo "Waiting for PostgreSQL to start..."
      for i in {1..20}; do
          if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
              echo "PostgreSQL is ready!"
              break
          fi
          echo "Waiting... ($i/20)"
          sleep 1
      done
    fi

    # Create database and user
    echo "Setting up database and user..."
    sudo -u postgres ${PG_BIN}/createdb -p ${DB_PORT} ${DB_NAME} 2>/dev/null || echo "Database might already exist"

    # Set up user and permissions with proper schema ownership
    sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d postgres << EOF
DO \$$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
\c ${DB_NAME}
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

    # Save connection command to a file
    echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
    echo "Connection string saved to db_connection.txt"
fi

# Save environment variables to a file (for db viewer)
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

echo "Ensuring baseline schema exists (one statement per psql -c)..."

# Read connection string for psql -c pattern (CRITICAL RULE)
PSQL_CMD="$(cat db_connection.txt 2>/dev/null)"
if [ -z "$PSQL_CMD" ]; then
  # Fallback to admin if file missing
  PSQL_CMD="sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME}"
fi

# Enable pgcrypto for gen_random_uuid if available - must be before UUID defaults
$PSQL_CMD -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# Create tables individually
$PSQL_CMD -c "CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

$PSQL_CMD -c "CREATE TABLE IF NOT EXISTS projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

$PSQL_CMD -c "CREATE TABLE IF NOT EXISTS project_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  version INTEGER NOT NULL,
  commit_hash TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(project_id, version)
);"

$PSQL_CMD -c "CREATE TABLE IF NOT EXISTS templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  description TEXT,
  category TEXT,
  tech_stack TEXT,
  content JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

$PSQL_CMD -c "CREATE TABLE IF NOT EXISTS chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

$PSQL_CMD -c "CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user','assistant','system')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);"

$PSQL_CMD -c "CREATE TABLE IF NOT EXISTS generated_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  content TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(project_id, path)
);"

# Indexes
$PSQL_CMD -c "CREATE INDEX IF NOT EXISTS idx_projects_user ON projects(user_id);"
$PSQL_CMD -c "CREATE INDEX IF NOT EXISTS idx_chat_messages_chat ON chat_messages(chat_id);"
$PSQL_CMD -c "CREATE INDEX IF NOT EXISTS idx_generated_files_project ON generated_files(project_id);"
$PSQL_CMD -c "CREATE INDEX IF NOT EXISTS idx_project_versions_project ON project_versions(project_id);"
$PSQL_CMD -c "CREATE INDEX IF NOT EXISTS idx_chats_project ON chats(project_id);"

echo "Seeding minimal template data (one INSERT per command)..."

# Seed minimal templates if not present (use upsert to keep idempotent)
$PSQL_CMD -c "INSERT INTO templates (name, description, category, tech_stack, content)
VALUES ('CRUD App', 'Basic CRUD application template', 'application', 'Next.js + FastAPI + PostgreSQL', '{}'::jsonb)
ON CONFLICT (name) DO NOTHING;"

$PSQL_CMD -c "INSERT INTO templates (name, description, category, tech_stack, content)
VALUES ('Admin Dashboard', 'Admin dashboard with auth and charts', 'dashboard', 'Next.js + FastAPI + PostgreSQL', '{}'::jsonb)
ON CONFLICT (name) DO NOTHING;"

$PSQL_CMD -c "INSERT INTO templates (name, description, category, tech_stack, content)
VALUES ('Blog', 'Simple blog with posts and comments', 'content', 'Next.js + FastAPI + PostgreSQL', '{}'::jsonb)
ON CONFLICT (name) DO NOTHING;"

echo "Schema and seed completed."

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""
echo "Environment variables saved to db_visualizer/postgres.env"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"
echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
