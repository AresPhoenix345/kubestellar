#!/usr/bin/env bash
# Smart installer for KubeStellar core-chart with auto-detection of KubeFlex

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")/core-chart"

# Default values
CHART_VERSION="${KUBESTELLAR_VERSION:-}"
RELEASE_NAME="ks-core"
NAMESPACE="default"
CHART_PATH=""
EXTRA_ARGS=()
FORCE_KFLEX_INSTALL=""
DRY_RUN=""

# Usage function
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Smart installer for KubeStellar core-chart that auto-detects if KubeFlex 
is already installed in the cluster.

OPTIONS:
    --version VERSION           Chart version (uses local chart if not specified)
    --release-name NAME         Helm release name (default: ks-core)
    --namespace NAMESPACE       Kubernetes namespace (default: default)
    --chart-path PATH          Path to local chart (default: auto-detected)
    --force-kubeflex-install   Force install KubeFlex even if already present
    --dry-run                  Show what would be installed without doing it
    --set KEY=VALUE            Pass through to helm (can be used multiple times)
    --set-json JSON            Pass through to helm (can be used multiple times)
    --set-string KEY=VALUE     Pass through to helm (can be used multiple times)
    --values FILE              Pass through to helm (can be used multiple times)
    -f FILE                    Alias for --values
    --help                     Show this help message

EXAMPLES:
    # Install with auto-detection (local chart)
    $(basename "$0") --set-json ITSes='[{"name":"its1"}]' --set-json WDSes='[{"name":"wds1"}]'

    # Install specific version from OCI registry
    $(basename "$0") --version 0.29.0 --set-json ITSes='[{"name":"its1"}]'

    # Add second WDS (KubeFlex auto-detected as already installed)
    $(basename "$0") --release-name add-wds2 --set-json WDSes='[{"name":"wds2"}]'

    # Force KubeFlex reinstall
    $(basename "$0") --force-kubeflex-install --set-json ITSes='[{"name":"its1"}]'

    # Dry run to see what would happen
    $(basename "$0") --dry-run --set-json WDSes='[{"name":"wds1"}]'

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            CHART_VERSION="$2"
            shift 2
            ;;
        --release-name)
            RELEASE_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --chart-path)
            CHART_PATH="$2"
            shift 2
            ;;
        --force-kubeflex-install)
            FORCE_KFLEX_INSTALL="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --set|--set-string|--set-json)
            EXTRA_ARGS+=("$1" "$2")
            shift 2
            ;;
        --values|-f)
            EXTRA_ARGS+=("$1" "$2")
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "===================================================================="
echo "KubeStellar Core Chart Smart Installer"
echo "===================================================================="
echo ""

# Check if KubeFlex is already installed
echo "🔍 Checking for existing KubeFlex installation..."
KFLEX_INSTALLED="false"
if kubectl get deployment -n kubeflex-system kubeflex-controller-manager >/dev/null 2>&1; then
    KFLEX_INSTALLED="true"
    echo "✅ KubeFlex operator detected in cluster"
else
    echo "❌ KubeFlex operator not found in cluster"
fi

# Determine if we should install KubeFlex
KFLEX_INSTALL="true"
if [[ "$KFLEX_INSTALLED" == "true" ]] && [[ "$FORCE_KFLEX_INSTALL" != "true" ]]; then
    KFLEX_INSTALL="false"
    echo "   → Will skip KubeFlex installation (already present)"
elif [[ "$FORCE_KFLEX_INSTALL" == "true" ]]; then
    echo "   → Will install/reinstall KubeFlex (forced by --force-kubeflex-install)"
else
    echo "   → Will install KubeFlex"
fi
echo ""

# Build helm command
HELM_CMD=(helm upgrade --install "$RELEASE_NAME")

# Determine chart source
if [[ -n "$CHART_VERSION" ]]; then
    echo "📦 Using chart from OCI registry (version: $CHART_VERSION)"
    HELM_CMD+=(oci://ghcr.io/kubestellar/kubestellar/core-chart --version "$CHART_VERSION")
else
    # Use local chart
    if [[ -n "$CHART_PATH" ]]; then
        CHART_DIR="$CHART_PATH"
    fi
    
    if [[ ! -d "$CHART_DIR" ]]; then
        echo "❌ Error: Chart not found at $CHART_DIR"
        echo "   Please specify --version to use OCI registry or --chart-path for local chart"
        exit 1
    fi
    
    echo "📦 Using local chart from: $CHART_DIR"
    HELM_CMD+=("$CHART_DIR")
fi

# Add namespace
HELM_CMD+=(--namespace "$NAMESPACE")

# Add KubeFlex install decision
HELM_CMD+=(--set "kubeflex-operator.install=$KFLEX_INSTALL")

# Add user arguments
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    HELM_CMD+=("${EXTRA_ARGS[@]}")
fi

# Execute or dry-run
echo ""
echo "📋 Helm command to execute:"
echo "   ${HELM_CMD[*]}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 DRY RUN MODE - No changes will be made"
    echo ""
    HELM_CMD+=(--dry-run --debug)
fi

echo "🚀 Executing installation..."
echo "===================================================================="
"${HELM_CMD[@]}"
EXIT_CODE=$?

echo "===================================================================="
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✅ Installation completed successfully!"
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        echo "💡 Next steps:"
        echo "   1. Add control plane contexts to your kubeconfig:"
        echo "      bash <(curl -s https://raw.githubusercontent.com/kubestellar/kubestellar/v\$KUBESTELLAR_VERSION/scripts/import-cp-contexts.sh) --merge"
        echo "   2. Or use kflex to access control planes:"
        echo "      kflex ctx <control-plane-name>"
    fi
else
    echo "❌ Installation failed with exit code: $EXIT_CODE"
fi

exit $EXIT_CODE
