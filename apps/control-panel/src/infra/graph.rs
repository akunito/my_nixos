//! Profile graph data generation for D3.js visualization

use crate::config::Config;
use crate::infra::{NodeStatus, ProfileNode, ProfileType};
use serde::Serialize;

/// Graph data for D3.js
#[derive(Debug, Clone, Serialize)]
pub struct GraphData {
    pub nodes: Vec<GraphNode>,
    pub links: Vec<GraphLink>,
}

/// Node in the D3.js graph
#[derive(Debug, Clone, Serialize)]
pub struct GraphNode {
    pub id: String,
    pub label: String,
    pub group: String,
    pub color: String,
    pub hostname: String,
    pub ip: Option<String>,
    pub ctid: Option<u32>,
    pub status: String,
}

/// Link in the D3.js graph
#[derive(Debug, Clone, Serialize)]
pub struct GraphLink {
    pub source: String,
    pub target: String,
    pub value: u32,
}

/// Generate graph data from configuration
pub fn generate_graph_data(config: &Config) -> GraphData {
    let mut nodes = Vec::new();
    let mut links = Vec::new();

    // Add base profile nodes (virtual nodes representing base configs)
    let base_profiles = vec![
        ("LXC-base-config", "LXC Base"),
        ("LAPTOP-base", "Laptop Base"),
        ("MACBOOK-base", "MacBook Base"),
    ];

    for (id, label) in &base_profiles {
        nodes.push(GraphNode {
            id: id.to_string(),
            label: label.to_string(),
            group: "base".to_string(),
            color: "#6b7280".to_string(), // gray
            hostname: "".to_string(),
            ip: None,
            ctid: None,
            status: "base".to_string(),
        });
    }

    // Add profile nodes
    for profile in &config.profiles {
        let profile_type = ProfileType::from_str(&profile.profile_type);
        let status = NodeStatus::Unknown; // Will be updated by health checks

        nodes.push(GraphNode {
            id: profile.name.clone(),
            label: profile.name.clone(),
            group: profile.profile_type.clone(),
            color: profile_type.css_color().to_string(),
            hostname: profile.hostname.clone(),
            ip: profile.ip.clone(),
            ctid: profile.ctid,
            status: "unknown".to_string(),
        });

        // Add link to base profile if specified
        if let Some(ref base) = profile.base_profile {
            links.push(GraphLink {
                source: base.clone(),
                target: profile.name.clone(),
                value: 1,
            });
        }
    }

    // Add hierarchy links based on profile type
    // LXC profiles inherit from LXC-base-config
    for profile in &config.profiles {
        if profile.profile_type == "lxc" && profile.base_profile.is_none() {
            links.push(GraphLink {
                source: "LXC-base-config".to_string(),
                target: profile.name.clone(),
                value: 1,
            });
        }
    }

    GraphData { nodes, links }
}

/// Convert profiles to ProfileNode list
pub fn get_profile_nodes(config: &Config) -> Vec<ProfileNode> {
    config
        .profiles
        .iter()
        .map(|p| ProfileNode {
            id: p.name.clone(),
            profile_type: ProfileType::from_str(&p.profile_type),
            hostname: p.hostname.clone(),
            ip: p.ip.clone(),
            ctid: p.ctid,
            status: NodeStatus::Unknown,
            base_profile: p.base_profile.clone(),
        })
        .collect()
}

/// Generate D3.js JavaScript code for the graph
pub fn generate_d3_script(data: &GraphData) -> String {
    let json_data = serde_json::to_string(data).unwrap_or_else(|_| "{}".to_string());

    format!(
        r##"
const graphData = {json_data};

const width = document.getElementById('graph-container').clientWidth;
const height = 600;

const svg = d3.select('#graph-container')
    .append('svg')
    .attr('width', width)
    .attr('height', height);

// Add zoom behavior
const g = svg.append('g');
svg.call(d3.zoom().on('zoom', (event) => {{
    g.attr('transform', event.transform);
}}));

// Create force simulation
const simulation = d3.forceSimulation(graphData.nodes)
    .force('link', d3.forceLink(graphData.links).id(d => d.id).distance(100))
    .force('charge', d3.forceManyBody().strength(-300))
    .force('center', d3.forceCenter(width / 2, height / 2))
    .force('collision', d3.forceCollide().radius(40));

// Draw links
const link = g.append('g')
    .selectAll('line')
    .data(graphData.links)
    .enter()
    .append('line')
    .attr('stroke', '#666')
    .attr('stroke-opacity', 0.6)
    .attr('stroke-width', d => Math.sqrt(d.value) * 2);

// Draw nodes
const node = g.append('g')
    .selectAll('g')
    .data(graphData.nodes)
    .enter()
    .append('g')
    .call(d3.drag()
        .on('start', dragstarted)
        .on('drag', dragged)
        .on('end', dragended));

// Node circles
node.append('circle')
    .attr('r', d => d.group === 'base' ? 15 : 25)
    .attr('fill', d => d.color)
    .attr('stroke', '#fff')
    .attr('stroke-width', 2)
    .style('cursor', 'pointer')
    .on('click', (event, d) => {{
        if (d.group !== 'base') {{
            showNodeDetails(d);
        }}
    }});

// Node labels
node.append('text')
    .text(d => d.label)
    .attr('text-anchor', 'middle')
    .attr('dy', 40)
    .attr('fill', '#fff')
    .attr('font-size', '12px');

// Status indicators
node.append('circle')
    .attr('r', 6)
    .attr('cx', 18)
    .attr('cy', -18)
    .attr('fill', d => getStatusColor(d.status))
    .attr('stroke', '#fff')
    .attr('stroke-width', 1);

// Tooltip
const tooltip = d3.select('body').append('div')
    .attr('class', 'tooltip')
    .style('position', 'absolute')
    .style('visibility', 'hidden')
    .style('background', '#1f2937')
    .style('color', '#fff')
    .style('padding', '8px 12px')
    .style('border-radius', '4px')
    .style('font-size', '12px')
    .style('z-index', '1000');

node.on('mouseover', (event, d) => {{
    tooltip
        .style('visibility', 'visible')
        .html(`
            <strong>${{d.label}}</strong><br/>
            Host: ${{d.hostname}}<br/>
            ${{d.ip ? 'IP: ' + d.ip + '<br/>' : ''}}
            ${{d.ctid ? 'CTID: ' + d.ctid + '<br/>' : ''}}
            Type: ${{d.group}}
        `);
}})
.on('mousemove', (event) => {{
    tooltip
        .style('top', (event.pageY - 10) + 'px')
        .style('left', (event.pageX + 10) + 'px');
}})
.on('mouseout', () => {{
    tooltip.style('visibility', 'hidden');
}});

// Update positions on tick
simulation.on('tick', () => {{
    link
        .attr('x1', d => d.source.x)
        .attr('y1', d => d.source.y)
        .attr('x2', d => d.target.x)
        .attr('y2', d => d.target.y);

    node.attr('transform', d => `translate(${{d.x}},${{d.y}})`);
}});

// Drag functions
function dragstarted(event, d) {{
    if (!event.active) simulation.alphaTarget(0.3).restart();
    d.fx = d.x;
    d.fy = d.y;
}}

function dragged(event, d) {{
    d.fx = event.x;
    d.fy = event.y;
}}

function dragended(event, d) {{
    if (!event.active) simulation.alphaTarget(0);
    d.fx = null;
    d.fy = null;
}}

function getStatusColor(status) {{
    switch(status) {{
        case 'online': return '#22c55e';
        case 'offline': return '#ef4444';
        case 'deploying': return '#3b82f6';
        case 'error': return '#f97316';
        default: return '#6b7280';
    }}
}}

function showNodeDetails(node) {{
    // Navigate to node details or show modal
    if (node.group === 'lxc' && node.ctid) {{
        htmx.ajax('GET', '/docker/' + node.id, 'body');
    }} else {{
        htmx.ajax('GET', '/infra/profile/' + node.id, '#details-panel');
    }}
}}
"##,
        json_data = json_data
    )
}
