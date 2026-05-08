# Auth Service Helm Chart

This chart deploys Keycloak as the AnyBackup AI Auth Service. It owns the Auth Service workload, internal Kubernetes services, and the Auth Service route rules.

## Boundary

Auth Service does not own the API Gateway deployment or shared middleware implementation. It does own the Auth Service route configuration.

API Gateway supplies Traefik and shared middlewares. This chart defines the `/api/auth_service/v1` route rules that Traefik consumes and forwards to the internal Auth Service HTTP service. Auth Service routes do not use the shared `tokenToXUser` middleware because Keycloak endpoints must receive the original `Authorization` header and perform their own token validation. Auth Service keeps Keycloak configured under the same relative path:

```text
/api/auth_service/v1
```

## Files

- `Chart.yaml`: local chart metadata.
- `values.yaml`: Keycloak runtime and external PostgreSQL connection.
- `templates/deployment.yaml`: Keycloak Deployment.
- `templates/service.yaml`: internal HTTP and management Service.
- `templates/ingressroute.yaml`: service-owned Traefik route rules.
- `templates/realm-config-job.yaml`: post-install/post-upgrade realm settings.
- `templates/secret.yaml`: optional bootstrap Secret for local or test environments.

## Secrets

By default, this chart expects an existing Kubernetes Secret and does not store passwords in Git.

```bash
kubectl -n anybackup-ai create secret generic auth-service-keycloak-secrets \
  --from-literal=admin-password='<replace-with-admin-password>' \
  --from-literal=database-password='<replace-with-keycloak-db-password>'
```

## Install

```bash
helm upgrade --install auth-service src/helm/auth_service_chart \
  --namespace anybackup-ai \
  --create-namespace \
  -f src/helm/auth_service_chart/values.yaml
```

## Verify

```bash
helm template auth-service src/helm/auth_service_chart
kubectl rollout status deployment/auth-service-auth-service -n anybackup-ai
kubectl -n anybackup-ai port-forward svc/auth-service-auth-service 8080:80
curl -i http://127.0.0.1:8080/api/auth_service/v1/realms/master/.well-known/openid-configuration
```

External verification must go through API Gateway, for example:

```bash
curl -i http://192.168.40.107/api/auth_service/v1/realms/master/.well-known/openid-configuration
```

## Configuration Basis

- PostgreSQL backend: `KC_DB=postgres`, `KC_DB_URL_HOST`, `KC_DB_URL_PORT`, `KC_DB_URL_DATABASE`, `KC_DB_USERNAME`, `KC_DB_PASSWORD`.
- Initial admin: `KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD`.
- Realm token policy: `keycloak.realm.accessTokenLifespan` defaults to `1800` seconds and is applied by a Helm hook Job after install or upgrade.
- HTTP and proxy: `KC_HTTP_ENABLED`, `KC_HTTP_PORT`, `KC_HTTP_RELATIVE_PATH`, `KC_PROXY_HEADERS`, `KC_HOSTNAME`, `KC_HOSTNAME_ADMIN`, `KC_HOSTNAME_STRICT`.
- Operations: `KC_HEALTH_ENABLED`, `KC_METRICS_ENABLED`.
- UI feature flags: `KC_FEATURES_DISABLED=admin,account`.
