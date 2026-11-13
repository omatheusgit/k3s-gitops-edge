FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90 AS deps
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target /deps -r requirements.txt

FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90
# Correcoes de seguranca do Debian e sem pip em runtime: as dependencias ja
# vieram prontas do estagio anterior, e o pip traz bibliotecas vendorizadas
# que so aumentam a superficie de ataque.
RUN apt-get update \
 && apt-get -y upgrade \
 && rm -rf /var/lib/apt/lists/* \
 && python -m pip uninstall -y pip \
 && useradd --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin eventos
ENV PYTHONPATH=/deps:/app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
COPY --from=deps /deps /deps
COPY eventos /app/eventos
USER 10001:10001
ENTRYPOINT ["python", "-m", "eventos"]
