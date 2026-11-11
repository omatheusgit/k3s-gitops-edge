#!/usr/bin/env python3
"""Confere as regras do repositorio nos manifests renderizados.

Le YAML (saida de `kubectl kustomize` / `helm template`) pela entrada padrao
e falha se algum container fugir do padrao:

  - runAsNonRoot, readOnlyRootFilesystem, sem escalada de privilegio,
    capabilities drop ALL e seccomp RuntimeDefault
  - requests e limit de memoria definidos
  - livenessProbe existe e nao e HTTP (liveness nao pode depender de banco/broker)
  - imagem com tag fixa (nada de :latest ou sem tag)
  - enableServiceLinks: false
  - Secret so por secretKeyRef (envFrom de Secret entrega todas as chaves)
  - fsGroup com volume persistente exige fsGroupChangePolicy: OnRootMismatch

Uso: kubectl kustomize apps/perfis/completo | scripts/verificar-politicas.py
"""
import sys

import yaml

CARGAS = {"Deployment", "StatefulSet", "DaemonSet", "Job"}


def problemas_do_container(pod: dict, c: dict, inicial: bool) -> list[str]:
    erros = []
    sc_pod = pod.get("securityContext") or {}
    sc = c.get("securityContext") or {}

    def valor(campo):
        return sc.get(campo, sc_pod.get(campo))

    if valor("runAsNonRoot") is not True:
        erros.append("runAsNonRoot precisa ser true")
    if sc.get("readOnlyRootFilesystem") is not True:
        erros.append("readOnlyRootFilesystem precisa ser true")
    if sc.get("allowPrivilegeEscalation") is not False:
        erros.append("allowPrivilegeEscalation precisa ser false")
    if "ALL" not in ((sc.get("capabilities") or {}).get("drop") or []):
        erros.append("capabilities.drop precisa conter ALL")
    if ((valor("seccompProfile") or {}).get("type")) != "RuntimeDefault":
        erros.append("seccompProfile precisa ser RuntimeDefault")

    imagem = c.get("image", "")
    if ":" not in imagem.rsplit("/", 1)[-1] or imagem.endswith(":latest"):
        erros.append(f"imagem sem tag fixa: {imagem}")

    if any("secretRef" in fonte for fonte in c.get("envFrom") or []):
        erros.append("envFrom de Secret: use secretKeyRef so com as chaves necessarias")

    recursos = c.get("resources") or {}
    if not (recursos.get("requests") or {}).get("memory"):
        erros.append("falta resources.requests.memory")
    if not (recursos.get("limits") or {}).get("memory"):
        erros.append("falta resources.limits.memory")

    if not inicial:
        vida = c.get("livenessProbe")
        if not vida:
            erros.append("falta livenessProbe")
        elif "httpGet" in vida:
            erros.append("livenessProbe HTTP: use tcpSocket ou exec local")
    return erros


def main() -> int:
    total = 0
    for doc in yaml.safe_load_all(sys.stdin):
        if not doc or doc.get("kind") not in CARGAS:
            continue
        nome = f"{doc['kind']}/{doc['metadata']['name']}"
        pod = doc["spec"]["template"]["spec"]
        erros = []
        if pod.get("enableServiceLinks") is not False:
            erros.append("enableServiceLinks precisa ser false")
        sc_pod = pod.get("securityContext") or {}
        if (doc["kind"] == "StatefulSet" and doc["spec"].get("volumeClaimTemplates")
                and "fsGroup" in sc_pod and sc_pod.get("fsGroupChangePolicy") != "OnRootMismatch"):
            erros.append("fsGroup com volume persistente: use fsGroupChangePolicy OnRootMismatch")
        for c in pod.get("initContainers", []):
            erros += [f"[init {c['name']}] {e}" for e in problemas_do_container(pod, c, True)]
        for c in pod.get("containers", []):
            erros += [f"[{c['name']}] {e}" for e in problemas_do_container(pod, c, False)]
        for e in erros:
            print(f"{nome}: {e}")
        total += len(erros)
    if total:
        print(f"\n{total} problema(s)")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
