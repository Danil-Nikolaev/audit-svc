ARG SOURCE_DATE_EPOCH=315532800

FROM python:3.11-slim-bookworm@sha256:f06d01d4ba3f8ad5af45a3ec87df19c1d317d8e8961edc0fabda61811af6f7cf AS build

SHELL ["/bin/sh", "-eu", "-c"]
ARG SOURCE_DATE_EPOCH
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} PYTHONHASHSEED=0
WORKDIR /build

COPY pyproject.toml poetry.lock README.md ./
COPY src/ src/

RUN python -m pip install \
      --no-cache-dir --disable-pip-version-check --progress-bar off \
      poetry==1.8.5 poetry-plugin-export==1.8.0 setuptools wheel \
    && mkdir -p dist \
    && poetry export --without-hashes --format constraints.txt --output dist/constraints.txt \
    && poetry run python -m pip wheel --isolated \
      --requirement dist/constraints.txt --wheel-dir dist/vendor \
    && poetry build --format wheel

FROM python:3.11-slim-bookworm@sha256:f06d01d4ba3f8ad5af45a3ec87df19c1d317d8e8961edc0fabda61811af6f7cf AS final

SHELL ["/bin/sh", "-eu", "-c"]
ARG UID=10001
ARG GID=10001

RUN addgroup --gid "${GID}" audit-svc \
    && adduser --disabled-password --gecos "" --home /app \
      --ingroup audit-svc --uid "${UID}" audit-svc

WORKDIR /app
COPY --from=build /build/dist /tmp/dist
RUN packages="$(find /tmp/dist /tmp/dist/vendor -maxdepth 1 -name '*.whl' -exec realpath {} \;)" \
    && python -m pip install --isolated --no-index --no-cache-dir \
      --disable-pip-version-check --no-deps ${packages} \
    && rm -rf /tmp/dist

USER audit-svc
ENV AUDIT_SVC_CONFIG=/etc/audit-svc/config.yaml \
    HOST=0.0.0.0 \
    PORT=8080
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=6 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"]
CMD ["server"]
