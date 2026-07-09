variable "apps_lb_hostname" {
  type        = string
  default     = "unset" # real value comes from deploy.sh; the default exists so destroy runs (which delete from state) never fail on a missing variable
  description = "Hostname of the ingress router's load balancer. After install-complete: oc -n openshift-ingress get svc router-default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}
