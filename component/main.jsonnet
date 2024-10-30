// main template for machine-api-provider-cloudscale
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.machine_api_provider_cloudscale;

local commonLabels = {
  'app.kubernetes.io/name': 'machine-api-provider',
  'app.kubernetes.io/instance': 'machine-api-provider-cloudscale',
  'app.kubernetes.io/part-of': 'syn',
  'app.kubernetes.io/managed-by': 'commodore',
};

local secrets = com.generateResources(
  params.secrets,
  function(name) kube.Secret(name) {
    metadata+: {
      namespace: params.namespace,
      labels+: commonLabels,
    },
  }
);

local alertlabels = {
  syn: 'true',
  syn_component: 'machine-api-provider-cloudscale',
};

local alerts = function(name, groupName, alerts)
  com.namespaced(params.namespace, kube._Object('monitoring.coreos.com/v1', 'PrometheusRule', name) {
    spec+: {
      groups+: [
        {
          name: groupName,
          rules:
            std.sort(std.filterMap(
              function(field) alerts[field].enabled == true,
              function(field) alerts[field].rule {
                alert: field,
                labels+: alertlabels,
              },
              std.objectFields(alerts)
            ), function(x) x.alert),
        },
      ],
    },
  });

local serviceAccount = kube.ServiceAccount('appuio-machine-api-provider-cloudscale') {
  metadata+: {
    namespace: params.namespace,
    labels+: commonLabels,
  },
};

local clusterRoleBinding = kube.ClusterRoleBinding('appuio-machine-api-provider-cloudscale') {
  metadata+: { labels+: commonLabels },
  subjects_: [ serviceAccount ],
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'ClusterRole',
    name: 'cluster-admin',
  },
};

local kubeProxyContainer = function(upstreamPort, portName, exposePort) {
  args: [
    '--secure-listen-address=0.0.0.0:%s' % exposePort,
    '--upstream=http://localhost:%s' % upstreamPort,
    '--logtostderr=true',
    '--v=0',
  ],
  image: '%(registry)s/%(image)s:%(tag)s' % params.images.kube_rbac_proxy,
  imagePullPolicy: 'IfNotPresent',
  name: 'kube-rbac-proxy-%s' % portName,
  ports: [
    {
      containerPort: exposePort,
      name: portName,
      protocol: 'TCP',
    },
  ],
  resources: {
    requests: {
      cpu: '10m',
      memory: '20Mi',
    },
  },
  terminationMessagePath: '/dev/termination-log',
  terminationMessagePolicy: 'File',
};

local deployment = kube._Object('apps/v1', 'Deployment', 'appuio-machine-api-provider-cloudscale') {
  metadata+: {
    namespace: params.namespace,
    annotations+: {},
    labels+: commonLabels,
  },
  spec: {
    progressDeadlineSeconds: 600,
    replicas: 1,
    revisionHistoryLimit: 10,
    selector: {
      matchLabels: {
        'app.kubernetes.io/name': commonLabels['app.kubernetes.io/name'],
        'app.kubernetes.io/instance': commonLabels['app.kubernetes.io/instance'],
      },
    },
    template: {
      metadata: {
        annotations: {
          'target.workload.openshift.io/management': '{"effect": "PreferredDuringScheduling"}',
        },
        labels: {
          'app.kubernetes.io/name': commonLabels['app.kubernetes.io/name'],
          'app.kubernetes.io/instance': commonLabels['app.kubernetes.io/instance'],
        },
      },
      spec: {
        containers: [
          {
            name: 'manager',
            command: [
              'machine-api-provider-cloudscale',
              '-target=manager',
            ],
            args: [
              '-metrics-bind-address=127.0.0.1:8080',
              '-health-probe-bind-address=:8081',
              '-leader-elect=true',
              '-namespace=%s' % params.namespace,
            ],
            image: '%(registry)s/%(image)s:%(tag)s' % params.images.provider,
            imagePullPolicy: 'IfNotPresent',
            livenessProbe: {
              httpGet: {
                path: '/readyz',
                port: 8081,
                scheme: 'HTTP',
              },
              periodSeconds: 20,
              initialDelaySeconds: 15,
            },
            readinessProbe: {
              httpGet: {
                path: '/healthz',
                port: 8081,
                scheme: 'HTTP',
              },
              periodSeconds: 10,
              initialDelaySeconds: 5,
            },
            resources: params.resources.provider,
          },
          {
            name: 'machine-api-controllers-manager',
            command: [
              'machine-api-provider-cloudscale',
              '-target=machine-api-controllers-manager',
            ],
            args: [
              '-metrics-bind-address=127.0.0.1:8082',
              '-health-probe-bind-address=:8083',
              '-leader-elect=true',
              '-namespace=%s' % params.namespace,
            ],
            image: '%(registry)s/%(image)s:%(tag)s' % params.images.machine_api_controllers_manager,
            imagePullPolicy: 'IfNotPresent',
            livenessProbe: {
              httpGet: {
                path: '/readyz',
                port: 8083,
                scheme: 'HTTP',
              },
              periodSeconds: 20,
              initialDelaySeconds: 15,
            },
            readinessProbe: {
              httpGet: {
                path: '/healthz',
                port: 8083,
                scheme: 'HTTP',
              },
              periodSeconds: 10,
              initialDelaySeconds: 5,
            },
            resources: params.resources.machine_api_controllers_manager,
          },
          kubeProxyContainer(8080, 'manager-metrics', 8440),
          kubeProxyContainer(8082, 'mac-metrics', 8442),
        ],
        dnsPolicy: 'ClusterFirst',
        nodeSelector: {
          'node-role.kubernetes.io/master': '',
        },
        priorityClassName: 'system-node-critical',
        restartPolicy: 'Always',
        schedulerName: 'default-scheduler',
        securityContext: {},
        serviceAccount: serviceAccount.metadata.name,
        serviceAccountName: serviceAccount.metadata.name,
        terminationGracePeriodSeconds: 30,
        tolerations: [
          {
            effect: 'NoSchedule',
            key: 'node-role.kubernetes.io/master',
          },
          {
            key: 'CriticalAddonsOnly',
            operator: 'Exists',
          },
          {
            effect: 'NoExecute',
            key: 'node.kubernetes.io/not-ready',
            operator: 'Exists',
            tolerationSeconds: 120,
          },
          {
            effect: 'NoExecute',
            key: 'node.kubernetes.io/unreachable',
            operator: 'Exists',
            tolerationSeconds: 120,
          },
        ],
      },
    },
  },
};


// Define outputs below
{
  '00_secrets': secrets,

  '10_serviceAccount': serviceAccount,
  '10_clusterRoleBinding': clusterRoleBinding,
  '11_deployment': deployment,

  '20_alerts': alerts('appuio-machine-api-provider-cloudscale', 'provider.alerts', params.alerts),
}
