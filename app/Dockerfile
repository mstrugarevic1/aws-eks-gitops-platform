# syntax=docker/dockerfile:1
FROM python:3.12-slim AS build

WORKDIR /install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install/prefix -r requirements.txt

FROM python:3.12-slim

# UID/GID must match the pod securityContext in the Helm chart
# (gitops/apps/example-app/chart/templates/deployment.yaml).
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid 10001 --no-create-home app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/python/lib/python3.12/site-packages \
    PORT=8000

COPY --from=build /install/prefix /opt/python
COPY main.py /app/main.py

USER 10001:10001
WORKDIR /app
EXPOSE 8000

# The filesystem is mounted read-only by the chart; nothing here writes to it.
ENTRYPOINT ["python", "/app/main.py"]
