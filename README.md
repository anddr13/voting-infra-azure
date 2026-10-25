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
  AKS (Free tier, Azure CNI Overlay): 2 Standard_B2ms nodes (2 vCPU / 8 GiB)
  Argo CD + "root" Application → everything else comes from voting-gitops (Traefik/Azure LB, KEDA, Strimzi, Kafka, Redis, Mongo, app)
```

**Cost (approximate):** control plane $0 (Free tier) + 2 × B2ms ~$0.17/h + load balancer, IPs and disks ~$0.06/h
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
- `apply`: ~15–20 minutes (AKS ~6–8, Argo CD + Kafka ~8). The job waits until the app responds
  and writes its URL to the job summary.
- `destroy`: removes everything. A nightly cron (01:00 UTC) runs it in case you forget.

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

## Pitfalls handled (and why)

- **Scripts never touch the wrong cluster.** `drain-cluster.sh` deletes things cluster-wide, so both scripts take the
  expected cluster name and refuse to run if kubectl points anywhere else (e.g. a work context on your laptop).
  `kubeconfig_command` writes credentials to a separate file (`~/.kube/voting-<cloud>`), so `~/.kube/config`
  and its current context are never modified.
- **azurerm 5.x:** AKS now requires a `node_provisioning_profile` block, and resource providers are no longer registered
  implicitly. The required ones are listed in `resource_providers_to_register`; without them apply fails on a fresh subscription.
- **A user-assigned identity with its VNet role is created before the cluster.** With a system-assigned identity and a
  custom VNet, Terraform does not grant the role (unlike `az aks create`), and LoadBalancer Services never get an IP.
- **Region `northeurope`.** New and trial subscriptions are often refused capacity in `westeurope`.
- **2 × B2ms = 4 vCPU**, exactly the per-region quota of a trial subscription. The AKS system pool cannot be spot,
  so the workloads run on it.
- **`scripts/drain-cluster.sh` runs before `destroy`:** it deletes the `root` Application (cascading), LoadBalancer
  Services and PVCs while the cluster is still alive. On Azure these live in the node resource group and would go away
  with the cluster anyway, but the script is shared by all three clouds so the behaviour is predictable everywhere.
- **No client secret:** GitHub Actions signs in with a federated credential, trusted only for `main` of this repository.
  The Terraform provider and backend use the same OIDC token (`ARM_USE_OIDC`).
- **The cluster admin certificate** (`kube_config`) ends up in the state; the Helm provider uses it to install Argo CD.
  The state sits in a private container reachable only through Entra ID.
