# Servidor git somente leitura para o Fleet do laboratorio ler a branch
# local sem precisar publicar no GitHub.
FROM alpine:3.22
RUN apk add --no-cache git-daemon \
 && git config --system --add safe.directory '*'
USER 1000:1000
EXPOSE 9418
ENTRYPOINT ["git", "daemon", "--reuseaddr", "--base-path=/srv", "--export-all", "/srv"]
