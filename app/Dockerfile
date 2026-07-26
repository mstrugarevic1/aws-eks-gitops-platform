# syntax=docker/dockerfile:1
FROM python:3.14-slim AS build

WORKDIR /install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install/prefix -r requirements.txt

FROM python:3.14-slim

# UID/GID must match the pod securityContext in the Helm chart
# (gitops/apps/example-app/chart/templates/deployment.yaml).
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --no-create-home app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Installed into the default prefix so site-packages resolves without pinning
# the Python minor version.
COPY --from=build /install/prefix /usr/local
COPY main.py /app/main.py

USER 10001:10001
WORKDIR /app
EXPOSE 8000

# The filesystem is mounted read-only by the chart; nothing here writes to it.
ENTRYPOINT ["python", "/app/main.py"]
