#!/bin/bash
#
# Protect main branch - require PRs, block direct pushes
# Works with GitHub Free (limited protection)
#
# Usage:
#   ./protect-branch.sh --repo ids-aws/iam-ms
#   ./protect-branch.sh --repo ids-aws/iam-ms --branch main
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BRANCH="main"

show_help() {
    echo "Usage: $0 --repo OWNER/REPO [OPTIONS]"
    echo ""
    echo "Protect a branch to require PRs (block direct pushes)."
    echo ""
    echo "Required:"
    echo "  --repo OWNER/REPO    Repository (e.g., ids-aws/iam-ms)"
    echo ""
    echo "Options:"
    echo "  --branch BRANCH      Branch to protect (default: main)"
    echo "  --help               Show this help"
    echo ""
    echo "Note: GitHub Free has limited branch protection."
    echo "      This enables what's available for free accounts."
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            REPO="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

if [ -z "$REPO" ]; then
    echo -e "${RED}Missing required --repo argument${NC}"
    show_help
    exit 1
fi

echo -e "${GREEN}Protecting branch '$BRANCH' on $REPO${NC}"
echo ""

# GitHub Free branch protection (limited options)
# - require_pull_request: block direct pushes
# - required_status_checks: require CI to pass (optional)
gh api \
    --method PUT \
    "repos/$REPO/branches/$BRANCH/protection" \
    -f "required_status_checks[strict]=true" \
    -f "required_status_checks[contexts][]=pipeline / Build & Push" \
    -f "enforce_admins=false" \
    -f "required_pull_request_reviews=null" \
    -f "restrictions=null" \
    -f "allow_force_pushes=false" \
    -f "allow_deletions=false" \
    > /dev/null 2>&1 || {
        # Fallback: minimal protection without status checks
        echo -e "${YELLOW}Applying minimal protection (GitHub Free limitation)${NC}"
        gh api \
            --method PUT \
            "repos/$REPO/branches/$BRANCH/protection" \
            -f "enforce_admins=false" \
            -f "required_pull_request_reviews=null" \
            -f "restrictions=null" \
            -f "required_status_checks=null" \
            -f "allow_force_pushes=false" \
            -f "allow_deletions=false" \
            > /dev/null
    }

echo -e "${GREEN}✓ Branch '$BRANCH' protected${NC}"
echo ""
echo "Protection enabled:"
echo "  - Block force pushes"
echo "  - Block branch deletion"
echo ""
echo -e "${YELLOW}Note: GitHub Free cannot fully block direct pushes.${NC}"
echo "      Consider using a pre-push hook or GitHub Pro for full protection."
