// main template for machine-api-provider-cloudscale
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.machine_api_provider_cloudscale;

// Define outputs below
{
}
