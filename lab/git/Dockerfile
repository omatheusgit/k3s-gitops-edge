# Servidor git somente leitura para o Fleet do laboratorio ler a branch
# local sem precisar publicar no GitHub.
FROM alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
RUN apk add --no-cache git-daemon \
 && git config --system --add safe.directory '*'
USER 1000:1000
EXPOSE 9418
ENTRYPOINT ["git", "daemon", "--reuseaddr", "--base-path=/srv", "--export-all", "/srv"]
