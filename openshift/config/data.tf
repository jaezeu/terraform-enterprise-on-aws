# Outputs of the cluster layer. Requires remote state sharing to be enabled on
# the tfe-hvd-ocp-cluster workspace for this workspace.
data "terraform_remote_state" "cluster" {
  backend = "remote"

  config = {
    organization = "jaz-hashi"
    workspaces = {
      name = "tfe-hvd-ocp-cluster"
    }
  }
}
