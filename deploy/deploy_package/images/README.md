# images

这个目录用于存放离线镜像 tar 包。

当前已经补齐的业务服务镜像：
- `images/core-agent-service-alpha1.tar`
- `images/conversation-service-alpha1.tar`
- `images/web-service-alpha1.tar`
- `images/auth-service-keycloak-26.5.1.tar`
- `images/api-gateway-service-traefik-v3.6.13.tar`

其中：
- `core-agent-service-alpha1.tar` 包含 `core-agent-service:alpha1`
- `conversation-service-alpha1.tar` 包含 `conversation-service:alpha1`
- `web-service-alpha1.tar` 同时包含 `web-service:alpha1` 和 `agent-web:alpha1`
- `auth-service-keycloak-26.5.1.tar` 包含 `docker.aityp.com/image/docker.io/keycloak/keycloak:26.5.1`
- `api-gateway-service-traefik-v3.6.13.tar` 包含 `docker.m.daocloud.io/library/traefik:v3.6.13`

目录约定保持不变：
- 业务镜像：`images/*.tar`
- KWeaver 全套镜像：`images/kweaver-core/*.tar`

说明：
- `auth_service_chart` 和 `api_gateway_service_chart` 当前只有 chart，没有可直接构建的业务 Dockerfile，因此这里补的是 chart 默认运行镜像，而不是伪造源码镜像。
- `auth_service` 默认镜像源 `docker.aityp.com` 在本次构建时不可达，因此我使用可访问的同版本 Keycloak 镜像拉取后，重新标记为 chart 期望的 repo tag 再导出。
