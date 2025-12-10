# Infrastructure Issue - DNS Resolution in GitHub Actions

## Problem Summary

The test scenarios cannot complete validation due to persistent DNS resolution issues in the GitHub Actions runner environment. This prevents Alpine Linux package manager (apk) from downloading required packages (openssl, pgbackrest, postgresql-contrib, su-exec, curl) at runtime.

## Root Cause

Docker containers in GitHub Actions experience DNS initialization delays of 60-90+ seconds. During this time:
- DNS queries fail with "DNS: transient error (try again later)"
- Alpine package repositories are unreachable
- Package installation fails even with retry logic

## What Was Implemented

### 1. Docker Build Fix
The Dockerfile was modified to:
- Skip `apk update` during build (avoids TLS/network errors)
- Build successfully without requiring network access
- Image builds but lacks critical runtime packages

### 2. Runtime Package Installation
The entrypoint script (`scripts/entrypoint.sh`) now:
- Detects missing packages on container startup
- Waits 90 seconds for DNS to initialize
- Attempts package installation with 5 retries
- Uses exponential backoff (5s, 7s, 9s, 11s, 13s delays)
- Total wait time: ~130 seconds before giving up

### 3. Test Infrastructure Fixes
All test docker-compose files updated:
- MinIO healthcheck changed from `curl` to `mc ready local`
- Proper dependency chains (minio-certs → minio → minio-setup → postgres)
- All 5 scenarios updated consistently

## Current Status

- ✅ Docker image builds successfully
- ✅ Containers start properly
- ✅ MinIO and dependencies work correctly
- ❌ Package installation fails due to DNS issues
- ❌ Tests cannot complete without openssl and pgbackrest

## Workarounds

### Option 1: Pre-built Image (Recommended)
Build the image in an environment with working DNS, then push to registry:

```bash
# On a machine with normal DNS:
docker build -t your-registry/postgres-ba:latest .
docker push your-registry/postgres-ba:latest

# In tests, use the pre-built image:
# Update docker-compose.yml:
services:
  postgres:
    image: your-registry/postgres-ba:latest
    # Remove build: section
```

### Option 2: Extended Wait Time
Increase DNS wait time even further (may or may not help):

```bash
# In scripts/entrypoint.sh, increase from 90s to 180s:
echo "Waiting 180s for DNS initialization..."
sleep 180
```

### Option 3: Different CI Environment
Run tests in a CI environment with better DNS reliability:
- GitLab CI
- CircleCI  
- Local Docker environment
- Cloud VM with Docker

### Option 4: Offline Package Installation
Pre-download APK packages and install from local cache:

```dockerfile
# Download packages separately and include in image
COPY packages/*.apk /tmp/packages/
RUN apk add --allow-untrusted /tmp/packages/*.apk
```

## Testing the Implementation

To verify the implementation works with proper DNS:

```bash
# Run on a system with normal DNS (not GitHub Actions):
cd tests/scenario-1-new-db
./test.sh
```

Expected behavior:
1. Containers start
2. DNS resolves after ~60-90 seconds
3. Packages install successfully
4. PostgreSQL starts with SSL and pgBackRest
5. All tests pass

## Files Modified

1. **Dockerfile** - Conditional package installation, runtime fallback
2. **scripts/entrypoint.sh** - DNS-aware runtime package installation
3. **tests/scenario-1-new-db/docker-compose.yml** - Fixed healthchecks
4. **tests/scenario-2-restart/docker-compose.yml** - Fixed healthchecks
5. **tests/scenario-3-restore/docker-compose.yml** - Fixed healthchecks
6. **tests/scenario-4-replica/docker-compose.yml** - Fixed healthchecks
7. **tests/scenario-5-existing-db/docker-compose.yml** - Fixed healthchecks

## Next Steps

1. **Immediate**: Use Option 1 (pre-built image) to continue testing
2. **Short-term**: Test in different CI environment
3. **Long-term**: Investigate GitHub Actions DNS configuration or file support ticket

## Verification Evidence

DNS resolution works when tested manually after container starts:
```bash
$ docker compose exec postgres nslookup dl-cdn.alpinelinux.org
Server:     127.0.0.11
Address:    127.0.0.11:53
dl-cdn.alpinelinux.org    canonical name = dualstack.j.sni.global.fastly.net
Name:   dualstack.j.sni.global.fastly.net
Address: 199.232.90.132
```

But fails during entrypoint execution despite 90s wait + retries, indicating the timing is environment-specific.
