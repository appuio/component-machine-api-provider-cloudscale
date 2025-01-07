local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.machine_api_provider_cloudscale;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('machine-api-provider-cloudscale', params.namespace);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/machine-api-provider-cloudscale' % appPath]: app,
}
