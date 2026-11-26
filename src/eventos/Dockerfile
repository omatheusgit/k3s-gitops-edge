FROM python:3.13-slim@sha256:7249d5587b78209a006dc4a3b5340678f84ea729239193aa559962cd8c1fce50 AS deps
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target /deps -r requirements.txt

FROM python:3.13-slim@sha256:7249d5587b78209a006dc4a3b5340678f84ea729239193aa559962cd8c1fce50
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
