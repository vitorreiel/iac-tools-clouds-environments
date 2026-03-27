#!/usr/bin/env python3
"""
IaC Tools Comparative Analysis - Graphics Generator
Generates beautiful, organized comparison graphics for IaC tools across topologies.
"""

import os
import sys
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
import numpy as np
from datetime import datetime

# =====================================================================
# CONFIGURATION
# =====================================================================

BASE_PATH = Path(__file__).parent.parent / "results"
GRAPHICS_PATH = Path(__file__).parent
OUTPUT_DIR = GRAPHICS_PATH / "outputs"
TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")

# Create output directory
OUTPUT_DIR.mkdir(exist_ok=True)

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (14, 8)
plt.rcParams['font.size'] = 10
plt.rcParams['axes.labelsize'] = 11
plt.rcParams['axes.titlesize'] = 13
plt.rcParams['xtick.labelsize'] = 9
plt.rcParams['ytick.labelsize'] = 9
plt.rcParams['legend.fontsize'] = 10

# Color palette for tools
TOOL_COLORS = {
    'Terraform': '#1f77b4',
    'OpenTofu': '#ff7f0e',
    'Pulumi': '#2ca02c',
    'Chef': '#d62728',
    'Ansible': '#9467bd',
    'CloudFormation': '#8c564b',
    'Puppet': '#e377c2',
}

# =====================================================================
# DATA LOADING
# =====================================================================

def load_topology_data(topology_name):
    """Load all IaC tool results for a specific topology."""
    data = {}
    topology_path = BASE_PATH / topology_name

    for tool_dir in topology_path.iterdir():
        if tool_dir.is_dir():
            csv_file = tool_dir / "results.csv"
            if csv_file.exists():
                tool_name = tool_dir.name.capitalize()
                try:
                    df = pd.read_csv(csv_file)
                    data[tool_name] = df
                    print(f"✓ Loaded {topology_name}/{tool_name}: {len(df)} records")
                except Exception as e:
                    print(f"✗ Error loading {topology_name}/{tool_name}: {e}")

    return data

# =====================================================================
# GRAPH 1: Duration Comparison (Total, Install, Topology, Convergence)
# =====================================================================

def plot_duration_comparison(fat_tree_data, leaf_spine_data):
    """Compare duration metrics across tools and topologies."""
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    fig.suptitle('Duration Metrics Comparison: Fat-Tree vs Leaf-Spine',
                 fontsize=16, fontweight='bold', y=0.995)

    metrics = [
        ('duration_total_sec', 'Total Duration (sec)', 0),
        ('duration_install_sec', 'Install Duration (sec)', 1),
        ('duration_topology_sec', 'Topology Duration (sec)', 2),
        ('convergence_sec', 'Convergence Duration (sec)', 3),
    ]

    for metric, title, idx in metrics:
        ax = axes.flat[idx]

        # Prepare data
        tools = sorted(fat_tree_data.keys())
        ft_means = [fat_tree_data[tool][metric].mean() for tool in tools]
        ls_means = [leaf_spine_data[tool][metric].mean() for tool in tools]

        # Plotting
        x = np.arange(len(tools))
        width = 0.35

        bars1 = ax.bar(x - width/2, ft_means, width, label='Fat-Tree',
                       color='#3498db', alpha=0.8, edgecolor='black')
        bars2 = ax.bar(x + width/2, ls_means, width, label='Leaf-Spine',
                       color='#e74c3c', alpha=0.8, edgecolor='black')

        # Formatting
        ax.set_xlabel('IaC Tool', fontweight='bold')
        ax.set_ylabel(title, fontweight='bold')
        ax.set_title(title, fontsize=12, fontweight='bold', pad=10)
        ax.set_xticks(x)
        ax.set_xticklabels(tools, rotation=45, ha='right')
        ax.legend(loc='upper left', framealpha=0.95)
        ax.grid(axis='y', alpha=0.3)

        # Add value labels on bars
        for bars in [bars1, bars2]:
            for bar in bars:
                height = bar.get_height()
                ax.text(bar.get_x() + bar.get_width()/2., height,
                       f'{height:.1f}',
                       ha='center', va='bottom', fontsize=8)

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f'01_duration_comparison_{TIMESTAMP}.png', dpi=300, bbox_inches='tight')
    print("✓ Generated: Duration Comparison")
    plt.close()

# =====================================================================
# GRAPH 2: Duration Breakdown (Stacked Bars)
# =====================================================================

def plot_total_duration_ranking(fat_tree_data, leaf_spine_data):
    """Show duration composition: Install + Topology + Convergence."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 8))
    fig.suptitle('Duration Breakdown by Component: Installation → Topology → Convergence',
                 fontsize=16, fontweight='bold', y=0.98)

    topologies = [('Fat-Tree', fat_tree_data), ('Leaf-Spine', leaf_spine_data)]

    for idx, (topo_name, data) in enumerate(topologies):
        ax = axes[idx]

        # Calculate means for each component
        tools = sorted(data.keys())
        install_means = [data[tool]['duration_install_sec'].mean() for tool in tools]
        topology_means = [data[tool]['duration_topology_sec'].mean() for tool in tools]
        convergence_means = [data[tool]['convergence_sec'].mean() for tool in tools]
        total_means = [install_means[i] + topology_means[i] + convergence_means[i] for i in range(len(tools))]

        # Sort by total duration
        sorted_indices = sorted(range(len(tools)), key=lambda i: total_means[i])
        tools_sorted = [tools[i] for i in sorted_indices]
        install_sorted = [install_means[i] for i in sorted_indices]
        topology_sorted = [topology_means[i] for i in sorted_indices]
        convergence_sorted = [convergence_means[i] for i in sorted_indices]
        total_sorted = [total_means[i] for i in sorted_indices]

        # Define colors for components
        color_install = '#3498db'      # Blue - Installation
        color_topology = '#2ecc71'     # Green - Topology
        color_convergence = '#e74c3c'  # Red - Convergence

        # Create stacked horizontal bars
        y_pos = np.arange(len(tools_sorted))

        bars1 = ax.barh(y_pos, install_sorted, label='Installation',
                       color=color_install, alpha=0.85, edgecolor='black', linewidth=0.5)
        bars2 = ax.barh(y_pos, topology_sorted, left=install_sorted, label='Topology Provisioning',
                       color=color_topology, alpha=0.85, edgecolor='black', linewidth=0.5)
        bars3 = ax.barh(y_pos, convergence_sorted,
                       left=[install_sorted[i] + topology_sorted[i] for i in range(len(tools_sorted))],
                       label='Convergence Waiting',
                       color=color_convergence, alpha=0.85, edgecolor='black', linewidth=0.5)

        # Formatting
        ax.set_yticks(y_pos)
        ax.set_yticklabels(tools_sorted, fontsize=10, fontweight='bold')
        ax.set_xlabel('Duration (seconds)', fontweight='bold', fontsize=11)
        ax.set_title(f'{topo_name} Topology', fontsize=13, fontweight='bold', pad=10)
        ax.legend(loc='lower right', framealpha=0.95, fontsize=10)
        ax.grid(axis='x', alpha=0.3)

        # Add total duration labels at the end of each bar
        for i, (bar, total) in enumerate(zip([bars1[i] for i in range(len(bars1))], total_sorted)):
            sum_width = install_sorted[i] + topology_sorted[i] + convergence_sorted[i]
            ax.text(sum_width, i, f' {total:.2f}s',
                   va='center', fontweight='bold', fontsize=9, color='black')

        # Add component value labels inside bars
        for i in range(len(tools_sorted)):
            # Install label
            ax.text(install_sorted[i] / 2, i, f'{install_sorted[i]:.1f}s',
                   va='center', ha='center', fontweight='bold', fontsize=8, color='white')

            # Topology label
            topology_start = install_sorted[i]
            ax.text(topology_start + topology_sorted[i] / 2, i, f'{topology_sorted[i]:.1f}s',
                   va='center', ha='center', fontweight='bold', fontsize=8, color='white')

            # Convergence label
            convergence_start = install_sorted[i] + topology_sorted[i]
            ax.text(convergence_start + convergence_sorted[i] / 2, i, f'{convergence_sorted[i]:.1f}s',
                   va='center', ha='center', fontweight='bold', fontsize=8, color='white')

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f'02_duration_breakdown_{TIMESTAMP}.png', dpi=300, bbox_inches='tight')
    print("✓ Generated: Duration Breakdown (Stacked)")
    plt.close()

# =====================================================================
# GRAPH 3: Resource Usage (CPU, Memory)
# =====================================================================

def plot_resource_usage(fat_tree_data, leaf_spine_data):
    """Compare CPU and Memory usage."""
    fig, axes = plt.subplots(2, 2, figsize=(16, 10))
    fig.suptitle('Resource Usage Comparison: CPU & Memory',
                 fontsize=16, fontweight='bold', y=0.995)

    resources = [
        ('cpu_avg_pct', 'Average CPU Usage (%)', (0, 0)),
        ('cpu_max_pct', 'Maximum CPU Usage (%)', (0, 1)),
        ('mem_avg_pct', 'Average Memory Usage (%)', (1, 0)),
        ('mem_max_pct', 'Maximum Memory Usage (%)', (1, 1)),
    ]

    for metric, title, (row, col) in resources:
        ax = axes[row, col]

        tools = sorted(fat_tree_data.keys())
        ft_means = [fat_tree_data[tool][metric].mean() for tool in tools]
        ls_means = [leaf_spine_data[tool][metric].mean() for tool in tools]

        x = np.arange(len(tools))
        width = 0.35

        bars1 = ax.bar(x - width/2, ft_means, width, label='Fat-Tree',
                       color='#3498db', alpha=0.8, edgecolor='black')
        bars2 = ax.bar(x + width/2, ls_means, width, label='Leaf-Spine',
                       color='#e74c3c', alpha=0.8, edgecolor='black')

        ax.set_ylabel(title, fontweight='bold')
        ax.set_title(title, fontsize=12, fontweight='bold', pad=10)
        ax.set_xticks(x)
        ax.set_xticklabels(tools, rotation=45, ha='right')
        ax.legend(loc='upper right', framealpha=0.95)
        ax.grid(axis='y', alpha=0.3)
        ax.set_ylim(0, 100)

        # Add value labels
        for bars in [bars1, bars2]:
            for bar in bars:
                height = bar.get_height()
                ax.text(bar.get_x() + bar.get_width()/2., height,
                       f'{height:.1f}%', ha='center', va='bottom', fontsize=8)

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f'03_resource_usage_{TIMESTAMP}.png', dpi=300, bbox_inches='tight')
    print("✓ Generated: Resource Usage")
    plt.close()

# =====================================================================
# GRAPH 4: Network I/O Comparison
# =====================================================================

def plot_network_io(fat_tree_data, leaf_spine_data):
    """Compare network I/O metrics."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    fig.suptitle('Network I/O Metrics: Rx vs Tx',
                 fontsize=16, fontweight='bold', y=0.98)

    topologies = [('Fat-Tree', fat_tree_data), ('Leaf-Spine', leaf_spine_data)]

    for idx, (topo_name, data) in enumerate(topologies):
        ax = axes[idx]

        tools = sorted(data.keys())
        rx_means = [data[tool]['net_rx_mb'].mean() for tool in tools]
        tx_means = [data[tool]['net_tx_mb'].mean() for tool in tools]

        x = np.arange(len(tools))
        width = 0.35

        bars1 = ax.bar(x - width/2, rx_means, width, label='RX (MB)',
                       color='#27ae60', alpha=0.8, edgecolor='black')
        bars2 = ax.bar(x + width/2, tx_means, width, label='TX (MB)',
                       color='#f39c12', alpha=0.8, edgecolor='black')

        ax.set_ylabel('Data Transferred (MB)', fontweight='bold', fontsize=11)
        ax.set_title(f'{topo_name}', fontsize=13, fontweight='bold', pad=10)
        ax.set_xticks(x)
        ax.set_xticklabels(tools, rotation=45, ha='right')
        ax.legend(loc='upper left', framealpha=0.95)
        ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f'04_network_io_{TIMESTAMP}.png', dpi=300, bbox_inches='tight')
    print("✓ Generated: Network I/O")
    plt.close()

# =====================================================================
# GRAPH 5: Convergence Time Analysis
# =====================================================================

def plot_convergence_analysis(fat_tree_data, leaf_spine_data):
    """Analyze convergence times."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    fig.suptitle('Convergence Time Analysis',
                 fontsize=16, fontweight='bold', y=0.98)

    topologies = [('Fat-Tree', fat_tree_data), ('Leaf-Spine', leaf_spine_data)]

    for idx, (topo_name, data) in enumerate(topologies):
        ax = axes[idx]

        tools = sorted(data.keys())
        conv_means = [data[tool]['convergence_sec'].mean() for tool in tools]
        conv_stds = [data[tool]['convergence_sec'].std() for tool in tools]

        colors_list = [TOOL_COLORS.get(tool, '#95a5a6') for tool in tools]

        bars = ax.bar(tools, conv_means, yerr=conv_stds, capsize=5,
                      color=colors_list, alpha=0.8, edgecolor='black', linewidth=1.5)

        ax.set_ylabel('Convergence Time (seconds)', fontweight='bold', fontsize=11)
        ax.set_title(f'{topo_name}', fontsize=13, fontweight='bold', pad=10)
        ax.set_xticklabels(tools, rotation=45, ha='right')
        ax.grid(axis='y', alpha=0.3)

        # Add value labels
        for i, (bar, mean, std) in enumerate(zip(bars, conv_means, conv_stds)):
            ax.text(bar.get_x() + bar.get_width()/2., mean + std,
                   f'{mean:.2f}±{std:.2f}', ha='center', va='bottom', fontsize=9, fontweight='bold')

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f'05_convergence_analysis_{TIMESTAMP}.png', dpi=300, bbox_inches='tight')
    print("✓ Generated: Convergence Analysis")
    plt.close()

# =====================================================================
# GRAPH 6: Performance Summary (Box plots)
# =====================================================================

def plot_performance_distribution(fat_tree_data, leaf_spine_data):
    """Show distribution of performance metrics."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    fig.suptitle('Performance Distribution: Duration Total (seconds)',
                 fontsize=16, fontweight='bold', y=0.98)

    topologies = [('Fat-Tree', fat_tree_data), ('Leaf-Spine', leaf_spine_data)]

    for idx, (topo_name, data) in enumerate(topologies):
        ax = axes[idx]

        # Prepare data for box plot
        tools = sorted(data.keys())
        box_data = [data[tool]['duration_total_sec'].values for tool in tools]
        colors_list = [TOOL_COLORS.get(tool, '#95a5a6') for tool in tools]

        bp = ax.boxplot(box_data, labels=tools, patch_artist=True,
                       showmeans=True, meanline=True)

        # Color the boxes
        for patch, color in zip(bp['boxes'], colors_list):
            patch.set_facecolor(color)
            patch.set_alpha(0.7)

        ax.set_ylabel('Duration (seconds)', fontweight='bold', fontsize=11)
        ax.set_title(f'{topo_name}', fontsize=13, fontweight='bold', pad=10)
        ax.set_xticklabels(tools, rotation=45, ha='right')
        ax.grid(axis='y', alpha=0.3)

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f'06_performance_distribution_{TIMESTAMP}.png', dpi=300, bbox_inches='tight')
    print("✓ Generated: Performance Distribution")
    plt.close()

# =====================================================================
# GRAPH 7: Tool Efficiency Score
# =====================================================================

def plot_efficiency_score(fat_tree_data, leaf_spine_data):
    """Create composite efficiency scores."""
    fig, axes = plt.subplots(1, 2, figsize=(16, 6))
    fig.suptitle('Tool Efficiency Score (Lower is Better)',
                 fontsize=16, fontweight='bold', y=0.98)

    topologies = [('Fat-Tree', fat_tree_data), ('Leaf-Spine', leaf_spine_data)]

    for idx, (topo_name, data) in enumerate(topologies):
        ax = axes[idx]

        tools = sorted(data.keys())
        scores = []

        for tool in tools:
            df = data[tool]
            # Composite score: normalized sum of duration and cpu usage
            duration_norm = df['duration_total_sec'].mean() / 100  # Normalize
            cpu_norm = df['cpu_avg_pct'].mean() / 100
            mem_norm = df['mem_avg_pct'].mean() / 100
            score = (duration_norm * 0.5 + cpu_norm * 0.25 + mem_norm * 0.25) * 100
            scores.append(score)

        colors_list = [TOOL_COLORS.get(tool, '#95a5a6') for tool in tools]
        bars = ax.barh(tools, scores, color=colors_list, alpha=0.8, edgecolor='black', linewidth=1.5)

        ax.set_xlabel('Efficiency Score', fontweight='bold', fontsize=11)
        ax.set_title(f'{topo_name}', fontsize=13, fontweight='bold', pad=10)
        ax.grid(axis='x', alpha=0.3)

        # Add value labels
        for bar, score in zip(bars, scores):
            ax.text(score, bar.get_y() + bar.get_height()/2.,
                   f' {score:.2f}', va='center', fontweight='bold', fontsize=9)

    plt.tight_layout()
    plt.savefig(OUTPUT_DIR / f'07_efficiency_score_{TIMESTAMP}.png', dpi=300, bbox_inches='tight')
    print("✓ Generated: Efficiency Score")
    plt.close()

# =====================================================================
# MAIN EXECUTION
# =====================================================================

def main():
    print("\n" + "="*70)
    print("IaC Tools Comparative Analysis - Graphics Generator")
    print("="*70 + "\n")

    # Load data
    print("Loading data...")
    fat_tree_data = load_topology_data('fat-tree')
    leaf_spine_data = load_topology_data('leaf-spine')

    if not fat_tree_data or not leaf_spine_data:
        print("\n✗ Error: Could not load data from both topologies")
        return 1

    print(f"\n✓ Loaded {len(fat_tree_data)} tools from Fat-Tree")
    print(f"✓ Loaded {len(leaf_spine_data)} tools from Leaf-Spine")

    # Generate graphs
    print("\nGenerating graphics...\n")
    try:
        plot_duration_comparison(fat_tree_data, leaf_spine_data)
        plot_total_duration_ranking(fat_tree_data, leaf_spine_data)
        plot_resource_usage(fat_tree_data, leaf_spine_data)
        plot_network_io(fat_tree_data, leaf_spine_data)
        plot_convergence_analysis(fat_tree_data, leaf_spine_data)
        plot_performance_distribution(fat_tree_data, leaf_spine_data)
        plot_efficiency_score(fat_tree_data, leaf_spine_data)

        print("\n" + "="*70)
        print(f"✓ All graphics generated successfully!")
        print(f"✓ Output directory: {OUTPUT_DIR}")
        print("="*70 + "\n")

        return 0
    except Exception as e:
        print(f"\n✗ Error generating graphics: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == '__main__':
    sys.exit(main())
