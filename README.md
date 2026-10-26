# voting-infra-azure

AKS cluster for the multi-cloud [voting-app](https://github.com/anddr13/voting-app).
Created with one click, destroyed with one click, and destroyed automatically every night: this is a pay-per-hour sandbox.

Related: [voting-gitops](https://github.com/anddr13/voting-gitops) (what runs in the cluster) ·
[voting-infra-aws](https://github.com/anddr13/voting-infra-aws) · [voting-infra-gcp](https://github.com/anddr13/voting-infra-gcp)

## What gets created

```
bootstrap/   once, local state:  Storage Account for state (Entra ID auth only, no access keys)
                                  Entra ID app + federated credential for GitHub Actions
infra/       daily (apply/destroy):
  Resource group, VNet 10.10.0.0/16, node subnet
  User-assigned cluster identity + Network Contributor on the VNet
  AKS (Free tier, Azure CNI Overlay) in swedencentral: 2 Standard_D2as_v5 nodes (2 vCPU / 8 GiB)
  Argo CD + "root" Application → everything else comes from voting-gitops (Traefik/Azure LB, KEDA, Strimzi, Kafka, Redis, Mongo, app)
```

**Cost (approximate):** control plane $0 (Free tier) + 2 × D2as_v5 ~$0.17/h + load balancer, IPs and disks ~$0.06/h
≈ **$0.23/h**, i.e. ~$1 for a 4-hour session or ~$5.5 per day. On a trial subscription the $200 starter credit covers it.

## One-time bootstrap

Requires the `az` CLI (`az login` as the subscription owner), `terraform` ≥ 1.10 and `gh`.

```bash
cd bootstrap
terraform init
terraform apply -var subscription_id=$(az account show --query id -o tsv)
terraform output -raw next_steps   # run the printed commands: repository variables + commit backend.hcl
```

Keep `bootstrap/` around: it costs next to nothing and the Storage Account holds the state.

## Create / destroy

GitHub → **Actions → terraform → Run workflow**:
- `apply`: ~10 minutes, measured 9 min 34 s (Terraform incl. AKS 6 min 36 s, then Argo CD + Kafka until the app
  answered 2 min 37 s). The job waits until the app responds and writes its URL to the job summary.
- `destroy`: removes everything. Two nightly crons (01:23 and 03:53 UTC) run it in case you forget; they avoid the top of the hour,
  where GitHub delays scheduled runs (a 01:00 run once started at 05:42).

From a laptop:

```bash
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
cd infra
terraform init -backend-config=backend.hcl
terraform apply
eval "$(terraform output -raw kubeconfig_command)"   # separate kubeconfig file, ~/.kube/config stays untouched
```

## Things to look at once it is up

```bash
kubectl -n argocd get applications                     # waves: traefik/keda/strimzi → data → voting
kubectl -n voting get kafka,kafkatopic,pods
kubectl -n voting get scaledobject,hpa -w              # run the k6 test from voting-app in another terminal
kubectl -n argocd port-forward svc/argocd-server 8443:443
```

## Results (measured 2026-10-26)

AKS in swedencentral, 2 × Standard_D2as_v5, Kubernetes 1.36, worker `PROCESSING_DELAY_MS=20`.
Load: k6 on a laptop in Ukraine at 200 votes/s for 3 minutes through the Azure load balancer, each request from a
different client id.

| Time (UTC) | Worker replicas | Consumer lag | Node CPU |
|---|---|---|---|
| 23:59:04, start | 1 | 0 | 11% / 8% |
| +20 s | 4 | 2,680 | 11% / 8% |
| +41 s | **6** (max = partitions) | 3,424 | 30% / 33% |
| peak | 6 | ~3,900, **flat** | 48% / 46% |
| end of load | 6 | 2,424 | 43% / 43% |
| +35 s after the load | 6 | **0** | 32% / 35% |
| +5 min | **1** (default HPA scale-down stabilisation) | 0 | 14% / 9% |

- **36,001** requests at 200.4/s, 100% answered `202`, 0 failed, no dropped iterations.
- p95 **74 ms**, median 66 ms: almost all of it is the network round trip from the laptop to Sweden.
- **Exactly once:** MongoDB holds **36,006** votes = 36,001 from k6 + 5 manual ones; the tallies match the API
  (cat 18,156 + dog 17,850). DLQ: 0 messages.
- **Compared with kind** ([voting-infra-local](https://github.com/anddr13/voting-infra-local#results-measured-2026-10-26)):
  on the laptop the backlog kept growing to 9,251; here it levelled off at ~3,900 because each worker handles a
  message in ~30 ms instead of ~45 ms. The nodes stayed below 50% CPU, so the ceiling is still the 6 partitions,
  not the cluster.

## Pitfalls handled (and why)

- **Scripts never touch the wrong cluster.** `drain-cluster.sh` deletes things cluster-wide, so both scripts take the
  expected cluster name and refuse to run if kubectl points anywhere else (e.g. a work context on your laptop).
  `kubeconfig_command` writes credentials to a separate file (`~/.kube/voting-<cloud>`), so `~/.kube/config`
  and its current context are never modified.
- **azurerm 5.x:** AKS now requires a `node_provisioning_profile` block, and resource providers are no longer registered
  implicitly. The required ones are listed in `resource_providers_to_register`; without them apply fails on a fresh subscription.
- **A user-assigned identity with its VNet role is created before the cluster.** With a system-assigned identity and a
  custom VNet, Terraform does not grant the role (unlike `az aks create`), and LoadBalancer Services never get an IP.
- **Region `swedencentral`.** A trial subscription sees only part of the VM catalogue, and it differs per region:
  checked with `az vm list-skus`, `northeurope` and `polandcentral` offered no general-purpose 2 vCPU size at all,
  while `swedencentral` offers B-v2, Dasv5/v6 and Dsv5/v6.
- **2 × D2as_v5 = 4 vCPU**, exactly the per-region quota of a trial subscription (`az vm list-usage`). Not burstable,
  so Kafka keeps its CPU under load. The AKS system pool cannot be spot, so the workloads run on it.
- **`scripts/drain-cluster.sh` runs before `destroy`:** it deletes the `root` Application (cascading), LoadBalancer
  Services and PVCs while the cluster is still alive. On Azure these live in the node resource group and would go away
  with the cluster anyway, but the script is shared by all three clouds so the behaviour is predictable everywhere.
- **No client secret:** GitHub Actions signs in with a federated credential, trusted only for `main` of this repository.
  The Terraform provider and backend use the same OIDC token (`ARM_USE_OIDC`).
- **Immutable GitHub OIDC subjects.** Repositories created after 2026-07-15 present
  `repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:...` instead of `repo:<owner>/<repo>:ref:...`, so a
  re-created repository with the same name cannot reuse the trust. `bootstrap/github.tf` looks the IDs up
  in the GitHub API and the federated credential uses them; the old name-only form would be rejected with `AADSTS700213`-style
  "no matching federated identity" errors.
- **The cluster admin certificate** (`kube_config`) ends up in the state; the Helm provider uses it to install Argo CD.
  The state sits in a private container reachable only through Entra ID.
