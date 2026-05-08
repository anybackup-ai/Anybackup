# API Gateway Service Helm Chart

This chart installs a global Traefik API gateway and a ForwardAuth middleware for AnyBackup AI services.

## What It Deploys

- Traefik via the official `traefik/traefik` Helm chart.
- IngressClass `traefik`.
- Traefik CRD provider for service-owned `IngressRoute` resources.
- A shared Traefik auth middleware.
- A local Go Traefik plugin that validates a Bearer token through Auth Service `userinfo` and converts the response body into the `X-User` request header.

The gateway chart only deploys Traefik resources and local middleware plugin source. It does not deploy a separate auth backend. `auth.tokenToXUser.userinfoUrl` points to the Auth Service userinfo endpoint by default.

## Default Network Model

The default values bind Traefik HTTP traffic to the Kubernetes node's port 80 with `ports.web.hostPort: 80`. HTTPS is not exposed by default. Routes match by path only, so callers use the node IP directly, for example `http://192.168.40.107/api/conversation_service/v1`.

## Business Service Usage

Business and platform service charts expose internal `ClusterIP` services and define their own Traefik route resources. Service charts decide which paths are exposed, which shared middlewares are referenced, and what route priority is used.

Routes that set `auth.enabled=true` attach the global ForwardAuth middleware. Auth-service routes should normally keep gateway auth disabled because they issue and validate tokens.

The API Gateway chart does not define service routes. It provides the Traefik deployment and shared middleware definitions consumed by service-owned routes.

The exported middleware name is `api-gateway-service-api-gateway-service-auth`. Internally it is the local `tokenToXUser` plugin, which calls Auth Service `userinfo`; on success it injects `X-User`, removes `Authorization`, and leaves the other request headers unchanged before forwarding to the business service.

## Deploy

```powershell
helm dependency update src\helm\api_gateway_service_chart
helm upgrade --install api-gateway-service src\helm\api_gateway_service_chart `
  --namespace anybackup-ai `
  --create-namespace `
  --wait `
  --timeout 5m
```
