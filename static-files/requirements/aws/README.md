# requirements/aws

Este directorio declara la infraestructura AWS que el scope necesita para funcionar. Es consumido por `tofu-modules` como un módulo de OpenTofu en el momento del `tofu apply`.

## Cómo funciona

`tofu-modules` referencia este directorio como source de un módulo git:

```hcl
module "scope_infra" {
  source = "git::github.com/nullplatform/<scope-repo>.git//requirements/aws?ref=<tag>"

  bucket_name    = "..."
  service_name   = "..."
  agent_role_arn = "..."
}
```

OpenTofu clona el repositorio, carga este directorio como módulo y aplica los recursos declarados dentro del estado de infraestructura del cliente.

## Variables requeridas

| Variable | Descripción |
|---|---|
| `bucket_name` | Nombre del bucket S3 a crear |
| `service_name` | Prefijo usado para nombrar el IAM role y las policies |
| `agent_role_arn` | ARN del IAM role del agente de nullplatform |

## Requisitos

### IAM Role obligatorio

**Todo scope que declare infraestructura en este directorio debe crear un IAM role** que permita al agente de nullplatform asumir las credenciales necesarias para operar los recursos.

El role debe tener un trust policy que permita al agent role asumir este role via `sts:AssumeRole`:

```hcl
resource "aws_iam_role" "this" {
  name = "${var.service_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = var.agent_role_arn }
    }]
  })
}
```

Sin este role el agente no puede acceder a los recursos declarados en este directorio.

## Versionado

El `source` del módulo debe apuntar siempre a un **tag**, nunca a una branch:

```hcl
# ✅ Correcto — inmutable
?ref=v1.0.0

# ❌ Incorrecto — cualquier push a la branch modifica lo que se aplica
?ref=feat/mi-branch
```
