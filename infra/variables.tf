variable "location" {
  description = "Azure region. Trial subscriptions see only some VM sizes per region; swedencentral offers the 2 vCPU ones."
  type        = string
  default     = "swedencentral"
}

variable "env" {
  description = "Environment name, part of every resource name."
  type        = string
  default     = "dev"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. null = the current AKS default."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "Node size. 2 vCPU / 8 GiB, not burstable (steady CPU for Kafka under load); two of them fit the 4 vCPU quota of a trial subscription."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "node_count" {
  description = "Number of nodes."
  type        = number
  default     = 2
}

variable "gitops_repo_url" {
  description = "Repository Argo CD syncs from."
  type        = string
  default     = "https://github.com/anddr13/voting-gitops.git"
}

variable "gitops_revision" {
  description = "Branch or tag of the GitOps repository."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version."
  type        = string
  default     = "10.10.5"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version."
  type        = string
  default     = "2.0.7"
}
