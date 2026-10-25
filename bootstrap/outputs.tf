output "client_id" {
  description = "Client ID of the GitHub Actions app registration."
  value       = azuread_application_registration.github.client_id
}

output "next_steps" {
  description = "Commands that finish the setup."
  value       = <<-EOT
    gh variable set AZURE_CLIENT_ID       --repo ${var.github_repo} --body "${azuread_application_registration.github.client_id}"
    gh variable set AZURE_TENANT_ID       --repo ${var.github_repo} --body "${data.azurerm_subscription.current.tenant_id}"
    gh variable set AZURE_SUBSCRIPTION_ID --repo ${var.github_repo} --body "${data.azurerm_subscription.current.subscription_id}"
    git add infra/backend.hcl && git commit -m "Add backend config" && git push
  EOT
}
