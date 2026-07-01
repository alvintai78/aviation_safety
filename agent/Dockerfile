# ---------- Stage 1: build the React SPA ----------
FROM node:20-bookworm-slim AS web
WORKDIR /web
COPY web/package.json web/package-lock.json* ./
RUN npm install --no-audit --no-fund
COPY web/ .
RUN npm run build   # vite outDir = ../static -> /static

# ---------- Stage 2: runtime ----------
FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates apt-transport-https \
        unixodbc-dev gcc g++ \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
 && echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" \
        > /etc/apt/sources.list.d/mssql-release.list \
 && apt-get update \
 && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Drop the source web/ folder; runtime only needs the built /app/static
RUN rm -rf /app/web
COPY --from=web /static /app/static

ENV PORT=7700
# Unbuffered stdout/stderr so startup errors are flushed to the container logs
# immediately (otherwise a crash during import loses all buffered output).
ENV PYTHONUNBUFFERED=1
EXPOSE 7700
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7700", "--log-level", "debug"]
