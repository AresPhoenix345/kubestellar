{{/*
Detect if KubeFlex is already installed in the cluster by checking for the kubeflex-controller-manager deployment
*/}}
{{- define "kubestellar.kubeflex.isInstalled" -}}
{{- if lookup "apps/v1" "Deployment" "kubeflex-system" "kubeflex-controller-manager" -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
Generate a warning message if KubeFlex is detected but user has kubeflex-operator.install=true
*/}}
{{- define "kubestellar.kubeflex.installWarning" -}}
{{- if and (index .Values "kubeflex-operator" "install") (eq (include "kubestellar.kubeflex.isInstalled" .) "true") -}}

================================================================================
WARNING: KubeFlex operator appears to be already installed in this cluster!
================================================================================

The kubeflex-controller-manager deployment was detected in the kubeflex-system
namespace, but you have set kubeflex-operator.install=true (or left it as default).

This may cause installation conflicts or duplicate operator installations.

To avoid this issue, reinstall the chart with:
  --set kubeflex-operator.install=false

Or if using a values file, set:
  kubeflex-operator:
    install: false

================================================================================
{{- end -}}
{{- end -}}
