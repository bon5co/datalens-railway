# DataLens wrappers for Railway: one build context, one image per upstream component (build with --target <role>).
# DataLens (datalens-tech/datalens, Apache-2.0) ships as nine containers that share RSA key pairs and master tokens through a compose
# file whose defaults are the same public keys and tokens in every install. Railway cannot hand one file to nine services and
# `${{secret()}}` cannot make a key pair, so the db wrapper below generates a fresh set on its first boot and serves it over the
# private network behind a secret path; every other wrapper fetches the keys it needs before starting the upstream entrypoint.
# 2.9.0 is the newest release of datalens-tech/datalens, checked against the GitHub releases API on 2026-11-23; the component tags
# below are the ones its versions-config.json pins for that release.
# upstream: none component images of datalens-tech/datalens 2.9.0, tagged by component version rather than by release

ARG PG=ghcr.io/datalens-tech/datalens-postgres:16-1.3.0@sha256:37ba1c536c68fb5c0f63bc686897ea7bf654e6195e88f450437c020a063163b4
ARG TEMPORAL=ghcr.io/datalens-tech/datalens-temporal:1.27.2@sha256:e3649e0a76e8ca0adbfa3d9bd1cc36395623049ddedbad926d09c9b979e29579
ARG CONTROL=ghcr.io/datalens-tech/datalens-control-api:0.2457.0@sha256:1fa416302f8339362bbd940ba1c49c3275f5a22413ee354373b3cdca2e9117f0
ARG DATA=ghcr.io/datalens-tech/datalens-data-api:0.2457.0@sha256:c7448f7d07851541181410f8fbf4b17c4bce28cbea11bbe4c51730f337636c37
ARG US=ghcr.io/datalens-tech/datalens-us:1.39.0@sha256:9f13b3cec8d27f5e39064c083dbd22c7002f78d86830f3dd476b7ba42d397b43
ARG UI=ghcr.io/datalens-tech/datalens-ui:0.3831.0@sha256:5c720832463cc54c43307a9aeafb8f881fb54facc548edac35efb8ccfe327b0f
ARG META=ghcr.io/datalens-tech/datalens-meta-manager:0.52.0@sha256:d3c0c6041506d1f7fb0f66523639376b149866e01b0d4d888009059c7365ef11
ARG AUTH=ghcr.io/datalens-tech/datalens-auth:0.27.0@sha256:090194d29eb84fecec467afb032df2129e4d3a0b9560cb0c291047bb46bc51cd

# ---------------------------------------------------------------- db: Postgres with the seven DataLens databases + key server
FROM ${PG} AS db
# Demo workbook off: it needs the control plane to be up while Postgres initialises, and a fresh BI tool should start empty.
ENV INIT_DEMO_DATA=false \
    INIT_DB_DEMO=false \
    KEYS_PORT=8000
COPY keys-server.py /usr/local/bin/railway-keys-server.py
COPY db-entrypoint.sh /usr/local/bin/railway-db-entrypoint.sh
RUN chmod 0755 /usr/local/bin/railway-db-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/railway-db-entrypoint.sh"]
CMD ["postgres"]

# ---------------------------------------------------------------- shared: key-fetching boot shim
FROM ${TEMPORAL} AS temporal
USER root
COPY railway-boot.sh /usr/local/bin/railway-boot.sh
RUN chmod 0755 /usr/local/bin/railway-boot.sh
USER temporal
# Bind every interface, v4 and v6: the entrypoint otherwise binds the one address `hostname` resolves to, and Railway's private
# network may reach the container on the other family.
ENV BIND_ON_IP=::0 \
    KEYS_MAP="temporal_public=TEMPORAL_AUTH_PUBLIC_KEY" \
    POSTGRES_PORT=5432 \
    POSTGRES_USER=pg-user \
    POSTGRES_DB=pg-temporal-db \
    POSTGRES_DB_VISIBILITY=pg-temporal-visibility-db \
    POSTGRES_TLS_ENABLED=false \
    POSTGRES_TLS_DISABLE_HOST_VERIFICATION=true \
    TEMPORAL_AUTH_ENABLED=true \
    NAMESPACES=meta-manager
ENTRYPOINT ["/usr/local/bin/railway-boot.sh", "/etc/temporal/init-temporal.sh"]

FROM ${CONTROL} AS control-api
USER root
COPY railway-boot.sh /usr/local/bin/railway-boot.sh
RUN chmod 0755 /usr/local/bin/railway-boot.sh
USER app
ENV KEYS_MAP="bi_private=US_DYNAMIC_AUTH_PRIVATE_KEY auth_public=AUTH__JWT_KEY crypto=DL_CRY_KEY_VAL_ID_KEY" \
    BI_API_UWSGI_WORKERS_COUNT=2 \
    RQE_FORCE_OFF=1 \
    RQE_SECRET_KEY= \
    DL_CRY_ACTUAL_KEY_ID=KEY \
    US_HOST=http://us.railway.internal:8080 \
    CONNECTOR_AVAILABILITY_VISIBLE=clickhouse,postgres,chyt,ydb,mysql,greenplum,mssql,oracle,trino,appmetrica_api,metrika_api \
    AUTH__TYPE=NATIVE \
    AUTH__JWT_ALGORITHM=PS256
ENTRYPOINT ["/usr/local/bin/railway-boot.sh", "/etc/service/dl_api/run"]

FROM ${DATA} AS data-api
USER root
COPY railway-boot.sh /usr/local/bin/railway-boot.sh
RUN chmod 0755 /usr/local/bin/railway-boot.sh
USER app
ENV KEYS_MAP="bi_private=US_DYNAMIC_AUTH_PRIVATE_KEY auth_public=AUTH__JWT_KEY crypto=DL_CRY_KEY_VAL_ID_KEY" \
    GUNICORN_WORKERS_COUNT=2 \
    RQE_FORCE_OFF=1 \
    RQE_SECRET_KEY= \
    CACHES_ON=0 \
    MUTATIONS_CACHES_ON=0 \
    DL_CRY_ACTUAL_KEY_ID=KEY \
    BI_COMPENG_PG_ON=1 \
    US_HOST=http://us.railway.internal:8080 \
    AUTH__TYPE=NATIVE \
    AUTH__JWT_ALGORITHM=PS256
ENTRYPOINT ["/usr/local/bin/railway-boot.sh", "/etc/service/dl_api/run"]

FROM ${US} AS us
USER root
COPY railway-boot.sh /usr/local/bin/railway-boot.sh
RUN chmod 0755 /usr/local/bin/railway-boot.sh
USER app
ENV KEYS_MAP="bi_public=BI_MASTER_TOKEN_PUBLIC_KEY_PRIMARY ui_public=UI_MASTER_TOKEN_PUBLIC_KEY_PRIMARY auth_public=AUTH_TOKEN_PUBLIC_KEY" \
    APP_INSTALLATION=opensource \
    APP_ENV=prod \
    APP_PORT=8080 \
    AUTH_ENDPOINT=http://auth.railway.internal:8080 \
    US_SURPRESS_DB_STATUS_LOGS=true \
    SKIP_INSTALL_DB_EXTENSIONS=1 \
    USE_DEMO_DATA=0 \
    HC=0 \
    AUTH_ENABLED=true
ENTRYPOINT ["/usr/local/bin/railway-boot.sh", "/opt/app/scripts/preflight.sh"]

FROM ${UI} AS ui-api
# No key set needed: this is the stock image in API mode, wrapped only so the mode is baked in rather than a literal variable.
ENV APP_MODE=api \
    APP_ENV=production \
    APP_INSTALLATION=opensource \
    US_ENDPOINT=http://us.railway.internal:8080 \
    BI_API_ENDPOINT=http://control-api.railway.internal:8080

FROM ${META} AS meta-manager
USER root
COPY railway-boot.sh /usr/local/bin/railway-boot.sh
RUN chmod 0755 /usr/local/bin/railway-boot.sh
USER app
ENV KEYS_MAP="temporal_private=TEMPORAL_AUTH_PRIVATE_KEY auth_public=AUTH_TOKEN_PUBLIC_KEY" \
    APP_INSTALLATION=opensource \
    APP_ENV=prod \
    APP_PORT=8080 \
    US_ENDPOINT=http://us.railway.internal:8080 \
    UI_API_ENDPOINT=http://ui-api.railway.internal:8080 \
    TEMPORAL_ENDPOINT=temporal.railway.internal:7233 \
    TEMPORAL_AUTH_ENABLED=true \
    AUTH_ENABLED=true
ENTRYPOINT ["/usr/local/bin/railway-boot.sh", "/opt/app/scripts/preflight.sh"]

FROM ${AUTH} AS auth
USER root
COPY railway-boot.sh /usr/local/bin/railway-boot.sh
RUN chmod 0755 /usr/local/bin/railway-boot.sh
USER app
# AUTH_SIGNUP_DISABLED=true: upstream's default leaves self-registration open, so the first visitor could create an account.
ENV KEYS_MAP="auth_private=TOKEN_PRIVATE_KEY auth_public=TOKEN_PUBLIC_KEY" \
    APP_INSTALLATION=opensource \
    APP_ENV=prod \
    US_SURPRESS_DB_STATUS_LOGS=true \
    SKIP_INSTALL_DB_EXTENSIONS=1 \
    AUTH_SIGNUP_DISABLED=true \
    DISABLE_WILDCARD_COOKIE=true
ENTRYPOINT ["/usr/local/bin/railway-boot.sh", "/opt/app/scripts/preflight.sh"]

FROM ${UI} AS ui
USER root
COPY railway-boot.sh /usr/local/bin/railway-boot.sh
RUN chmod 0755 /usr/local/bin/railway-boot.sh
USER app
ENV KEYS_MAP="ui_private=US_DYNAMIC_MASTER_TOKEN_PRIVATE_KEY auth_public=AUTH_TOKEN_PUBLIC_KEY" \
    APP_MODE=full \
    APP_ENV=production \
    APP_INSTALLATION=opensource \
    AUTH_POLICY=disabled \
    US_ENDPOINT=http://us.railway.internal:8080 \
    AUTH_ENDPOINT=http://auth.railway.internal:8080 \
    BI_API_ENDPOINT=http://control-api.railway.internal:8080 \
    BI_DATA_ENDPOINT=http://data-api.railway.internal:8080 \
    META_MANAGER_ENDPOINT=http://meta-manager.railway.internal:8080 \
    RELEASE_VERSION=2.9.0 \
    HC=0 \
    YANDEX_MAP_ENABLED=0 \
    EXPORT_WORKBOOK_ENABLED=true \
    AUTH_ENABLED=true \
    AUTH_SIGNUP_DISABLED=true
ENTRYPOINT ["/usr/local/bin/railway-boot.sh", "/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
