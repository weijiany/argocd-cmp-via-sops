FROM alpine:3.24.1

RUN apk add --no-cache \
    curl \
    sops \
    helm \
    git

ENV HELM_PLUGINS=/helm-plugins

# ArgoCD uid: 999, https://github.com/argoproj/argo-cd/blob/v3.4.1/Dockerfile#L43
RUN mkdir -p /helm-plugins \
    && helm plugin install https://github.com/jkroepke/helm-secrets \
         --version v4.7.7 \
    && chown -R 999:999 /helm-plugins

USER 999

WORKDIR /tmp
