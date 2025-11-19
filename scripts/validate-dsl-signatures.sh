#!/bin/bash

# DSL Signature Validation Script
# Analyzes DSL files to identify potentially missing method signatures
# Usage: ./validate-dsl-signatures.sh [dsl-directory]

set -euo pipefail

DSL_DIR="${1:-jenkins-dsl}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DSL_PATH="${PROJECT_ROOT}/${DSL_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DSL Signature Validation Analysis ===${NC}"
echo "Analyzing DSL files in: ${DSL_PATH}"
echo "Date: $(date)"
echo

# Check if DSL directory exists
if [[ ! -d "$DSL_PATH" ]]; then
    echo -e "${RED}Error: DSL directory not found: $DSL_PATH${NC}"
    exit 1
fi

# Find all Groovy DSL files
DSL_FILES=($(find "$DSL_PATH" -name "*.groovy" -type f))

if [[ ${#DSL_FILES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No DSL files found in $DSL_PATH${NC}"
    exit 1
fi

echo -e "${GREEN}Found ${#DSL_FILES[@]} DSL files to analyze${NC}"
echo

# Extract method calls and analyze patterns
TEMP_DIR=$(mktemp -d)
METHODS_FILE="$TEMP_DIR/methods.txt"
PATTERNS_FILE="$TEMP_DIR/patterns.txt"
ANALYSIS_FILE="$TEMP_DIR/analysis.txt"

echo -e "${BLUE}=== Extracting Method Calls ===${NC}"

# Extract potential method calls from DSL files
for file in "${DSL_FILES[@]}"; do
    echo "Analyzing: $(basename "$file")"
    
    # Extract method calls (basic pattern matching)
    grep -oE '\w+\.[a-zA-Z_][a-zA-Z0-9_]*\s*\(' "$file" | sed 's/\s*(//' || true
    grep -oE '[a-zA-Z_][a-zA-Z0-9_]*\s*\{' "$file" | sed 's/\s*{//' || true
    grep -oE '\w+\.[a-zA-Z_][a-zA-Z0-9_]*\s*\[' "$file" | sed 's/\s*\[//' || true
done | sort | uniq > "$METHODS_FILE"

METHOD_COUNT=$(wc -l < "$METHODS_FILE")
echo -e "${GREEN}Extracted $METHOD_COUNT unique method patterns${NC}"
echo

# Analyze common patterns that might need approval
echo -e "${BLUE}=== Pattern Analysis ===${NC}"

cat > "$PATTERNS_FILE" << 'EOF'
# Common method patterns that often require approval
jenkins\.
hudson\.
org\.jenkinsci\.
com\.cloudbees\.
groovy\.
java\.
javax\.
System\.
Class\.
Thread\.
Runtime\.
File\.
URL\.
.*\.getClass\(\)
.*\.class
.*\.metaClass
.*\.properties
.*\.getDeclaredField
.*\.invoke
.*\.newInstance
.*\.forName
.*\.readObject
.*\.writeObject
.*\.exec
.*\.getRuntime
.*\.exit
.*\.halt
EOF

echo "Checking for potentially problematic patterns..."
echo

# Check for high-risk patterns
HIGH_RISK_FOUND=false
while IFS= read -r pattern; do
    [[ "$pattern" =~ ^#.*$ ]] && continue  # Skip comments
    [[ -z "$pattern" ]] && continue        # Skip empty lines
    
    if grep -qE "$pattern" "$METHODS_FILE"; then
        if [[ "$HIGH_RISK_FOUND" == false ]]; then
            echo -e "${YELLOW}⚠️ Potentially risky patterns found:${NC}"
            HIGH_RISK_FOUND=true
        fi
        echo -e "${RED}  • Pattern: $pattern${NC}"
        grep -E "$pattern" "$METHODS_FILE" | head -5 | sed 's/^/    /'
        echo
    fi
done < "$PATTERNS_FILE"

if [[ "$HIGH_RISK_FOUND" == false ]]; then
    echo -e "${GREEN}✅ No high-risk patterns detected${NC}"
fi
echo

# Analyze method frequency
echo -e "${BLUE}=== Method Usage Frequency ===${NC}"
echo "Most frequently used methods (top 20):"
sort "$METHODS_FILE" | uniq -c | sort -rn | head -20 | while read count method; do
    echo "  $count times: $method"
done
echo

# Check against current approval script
APPROVAL_SCRIPT="$PROJECT_ROOT/ansible/roles/jenkins-master-v2/files/init-scripts/setup-dsl-approval.groovy"

if [[ -f "$APPROVAL_SCRIPT" ]]; then
    echo -e "${BLUE}=== Approval Script Coverage Analysis ===${NC}"
    
    # Extract approved signatures from the approval script
    APPROVED_METHODS=$(grep -oE '"method [^"]*"' "$APPROVAL_SCRIPT" | sed 's/"method //' | sed 's/"//' | cut -d' ' -f1-2)
    
    # Check coverage
    COVERED_COUNT=0
    TOTAL_METHODS=$(wc -l < "$METHODS_FILE")
    
    echo "Checking coverage of extracted methods against approved signatures..."
    
    > "$ANALYSIS_FILE"
    while IFS= read -r method; do
        # Simple pattern matching for coverage
        if echo "$APPROVED_METHODS" | grep -q "$(echo "$method" | cut -d'.' -f2)"; then
            echo "✅ $method" >> "$ANALYSIS_FILE"
            ((COVERED_COUNT++))
        else
            echo "❌ $method" >> "$ANALYSIS_FILE"
        fi
    done < "$METHODS_FILE"
    
    COVERAGE_PERCENT=$(( (COVERED_COUNT * 100) / TOTAL_METHODS ))
    
    echo "Coverage Summary:"
    echo "  Total methods analyzed: $TOTAL_METHODS"
    echo "  Potentially covered: $COVERED_COUNT"
    echo "  Estimated coverage: ${COVERAGE_PERCENT}%"
    echo
    
    # Show uncovered methods
    UNCOVERED_COUNT=$((TOTAL_METHODS - COVERED_COUNT))
    if [[ $UNCOVERED_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}Methods that may need signature approval (showing first 10):${NC}"
        grep "❌" "$ANALYSIS_FILE" | head -10 | sed 's/❌/  •/' 
        echo
    fi
else
    echo -e "${YELLOW}⚠️ DSL approval script not found at: $APPROVAL_SCRIPT${NC}"
fi

# Generate recommendations
echo -e "${BLUE}=== Recommendations ===${NC}"

cat << EOF
1. 📋 Testing:
   • Run the test-approval-effectiveness.groovy script in Jenkins
   • Create actual jobs using the DSL patterns found
   • Monitor 'Manage Jenkins > Script Approval' for new requests

2. 🔧 Signature Updates:
   • Add missing signatures to setup-dsl-approval.groovy
   • Focus on frequently used methods first
   • Test signature additions in development environment

3. 📊 Monitoring:
   • Run this analysis after adding new DSL files
   • Check Jenkins logs for DSL security errors
   • Review approval requests regularly

4. 🛡️ Security:
   • Validate that new signatures are safe to approve
   • Avoid approving signatures that could compromise security
   • Document the purpose of each approved signature

5. 🔄 Maintenance:
   • Update signatures when Jenkins or plugins are upgraded
   • Re-run this analysis periodically
   • Keep signature list organized and commented
EOF

echo
echo -e "${GREEN}=== Analysis Complete ===${NC}"
echo "Temporary files created in: $TEMP_DIR"
echo "Review the analysis files for detailed information:"
echo "  • Methods: $METHODS_FILE"
echo "  • Analysis: $ANALYSIS_FILE"
echo

# Clean up on exit
trap "rm -rf '$TEMP_DIR'" EXIT