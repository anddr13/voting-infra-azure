output "resource_group" {
  description = "Resource group of the cluster."
  value       = azurerm_resource_group.this.name
}

output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "kubeconfig_command" {
  description = "eval \"$(terraform output -raw kubeconfig_command)\": kubectl access through a separate kubeconfig file; ~/.kube/config is not touched."
  value       = "export KUBECONFIG=\"$HOME/.kube/voting-azure\" && az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name} --file \"$KUBECONFIG\" --overwrite-existing"
}

output "argocd_ui" {
  description = "Argo CD UI via port-forward; the admin password is in the argocd-initial-admin-secret."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8443:443"
}
