# Servidor git somente leitura para o Fleet do laboratorio ler a branch
# local sem precisar publicar no GitHub.
FROM alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f
RUN apk add --no-cache git-daemon \
 && git config --system --add safe.directory '*'
USER 1000:1000
EXPOSE 9418
ENTRYPOINT ["git", "daemon", "--reuseaddr", "--base-path=/srv", "--export-all", "/srv"]
