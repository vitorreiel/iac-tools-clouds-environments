#!/bin/bash

# IaC Tools Graphics Generator - Wrapper Script
# Generates comparative analysis graphics for IaC tools

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/generate_reports.py"

echo ""
echo "=========================================================================="
echo "IaC Tools Comparative Analysis - Graphics Generator"
echo "=========================================================================="
echo ""

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "✗ Error: Python 3 is not installed"
    echo "  Please install Python 3 first"
    exit 1
fi

# Check if required packages are installed
echo "Checking dependencies..."
python3 << PYEOF
try:
    import pandas
    import matplotlib
    import seaborn
    import numpy
    print("✓ All dependencies are installed")
except ImportError as e:
    print(f"✗ Missing dependency: {e}")
    print("\nInstall with:")
    print("  pip install pandas matplotlib seaborn numpy")
    exit(1)
PYEOF

# Run the Python script
echo ""
echo "Running graphics generator..."
echo ""
python3 "$PYTHON_SCRIPT"

# Check if outputs were generated
OUTPUT_DIR="$SCRIPT_DIR/outputs"
if [ -d "$OUTPUT_DIR" ]; then
    COUNT=$(ls -1 "$OUTPUT_DIR"/*.png 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        echo ""
        echo "=========================================================================="
        echo "✓ Success! Generated $COUNT graphics"
        echo "=========================================================================="
        echo ""
        echo "Output location: $OUTPUT_DIR"
        echo ""
        echo "Generated files:"
        ls -1 "$OUTPUT_DIR"/*.png 2>/dev/null | xargs -n1 basename
        echo ""
    else
        echo "✗ Error: No graphics were generated"
        exit 1
    fi
else
    echo "✗ Error: Output directory not found"
    exit 1
fi
