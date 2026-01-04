# Platform API Validation Quick Reference

## Platform API is Internal-Only

Platform API is configured with `service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"` for security.
It's NOT accessible from the public internet.

## Validation Methods

### ✅ Method 1: Test from within cluster (Recommended)
```bash
kubectl run curl-test --rm -i --restart=Never \
  --image=curlimages/curl:latest \
  -n default \
  -- curl -k -s http://platformapi-svc:8080/platform/ping
```

### ✅ Method 2: Exec into Platform API pod
```bash
PAPI_POD=$(kubectl get pods -n default -l app=platformapi-deploy -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n default $PAPI_POD -c platformapi -- \
  curl -s http://localhost:8080/platform/ping
```

### ✅ Method 3: Check ConfigUI logs for connectivity
```bash
kubectl logs -n default -l app=configui-deploy -c configui --tail=50 | grep -i "token\|200"
# Look for successful token generation = Platform API is working
```

### ✅ Method 4: From bastion host in same VPC
```bash
# If you have a bastion in the same VPC
PAPI_URL=$(kubectl get svc platformapi-svc -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -k http://${PAPI_URL}:8080/platform/ping
```

## Expected Responses

**Success:**
```json
{"status":"UP"}
```
or
```
HTTP/1.1 200 OK
```

**Failure (500 error):**
- Missing Area UUID, Package Key, or Package Secret
- Database connectivity issues
- PreInstall job failed

## Why Internal?

Platform API handles sensitive operations:
- API key generation
- OAuth token management  
- Package and service definitions
- Administrative functions

It should only be accessed by:
- ConfigUI (for admin operations)
- Traffic Manager (for API runtime)
- Internal cluster services

**ConfigUI and Traffic Manager** are internet-facing for external user access.
