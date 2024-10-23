local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.machine_api_provider_cloudscale;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('machine-api-provider-cloudscale', params.namespace);

{
  'machine-api-provider-cloudscale': app,
}
