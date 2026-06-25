/* ===================================================================
   Tennis WIKI — Graph View Component
   Renders an interactive D3 force-directed graph showing article
   wikilinks. Two modes:
     - FULL: top N most-connected nodes (landing page)
     - LOCAL: current article + 2-hop neighborhood (per-article page)

   Markup contract:
     <div class="graph-view"
          data-mode="full|local"
          data-graph-url="path/to/graph-data.json"
          data-article-name="article-stem"
          id="graph-view-<unique>"
          style="height: NNNpx;">
       <div class="graph-loading">Loading...</div>
       <div class="graph-tooltip" id="graph-tooltip-<unique>"></div>
     </div>
   =================================================================== */

(function() {
  if (typeof d3 === 'undefined') {
    console.warn('[graph-component] D3 not loaded — graph will not render');
    return;
  }

  const CLUSTERS = {};

  function getGraphDataUrl() {
    // Compute the correct relative path to /<base>/assets/graph-data.json
    // from the current page.
    //
    // For a GitHub Pages site at https://user.github.io/<repo>/, the JSON
    // lives at https://user.github.io/<repo>/assets/graph-data.json.
    // From an article at https://user.github.io/<repo>/section/name/,
    // we need "../../assets/graph-data.json" (2 levels up).
    //
    // Strategy:
    // 1. If a <base href="..."> tag exists, trust it and compute depth below it.
    // 2. Otherwise, infer the base by trying to fetch '/assets/graph-data.json'
    //    from the current host root. If that fails, the first path segment is
    //    probably the repo name on GitHub Pages — strip it.
    // 3. For local dev (no repo segment), all segments are depth.
    const path = window.location.pathname;
    const segments = path.split('/').filter(Boolean);

    // Strip a trailing filename if any
    let fromBase = segments.slice();
    const baseEl = document.querySelector('base[href]');
    if (baseEl) {
      const baseHref = baseEl.getAttribute('href').replace(/\/$/, '');
      try {
        const baseSegs = new URL(baseHref, window.location.origin).pathname.split('/').filter(Boolean);
        if (baseSegs.length && baseSegs.length <= fromBase.length &&
            baseSegs.every((s, i) => s === fromBase[i])) {
          fromBase = fromBase.slice(baseSegs.length);
        }
      } catch(e) { /* ignore */ }
    }
    // For GitHub Pages: the path always starts with /<repo>/. Strip the first
    // segment so depth is computed below the repo root. Local dev (localhost)
    // typically has no repo prefix, so we skip this for the first segment.
    // Detect: if there's no <base> tag AND the path has at least one segment
    // AND we're NOT on localhost, strip the first segment.
    if (!baseEl && segments.length >= 1 && window.location.hostname !== 'localhost' &&
        window.location.hostname !== '127.0.0.1') {
      fromBase = segments.slice(1);
    }
    if (fromBase.length === 0) return 'assets/graph-data.json';
    return '../'.repeat(fromBase.length) + 'assets/graph-data.json';
  }

  // Convert a URL like "technique/arming-on-the-volley/" (from graph-data)
  // into an absolute path that works from any current page depth.
  // Strategy: replace the page's content path with the relative URL,
  // stripping the current article's directory.
  function resolveAbsoluteUrl(relUrl) {
    if (!relUrl) return '';
    if (/^https?:\/\//.test(relUrl)) return relUrl;  // already absolute
    if (relUrl.startsWith('/')) return relUrl;       // already root-absolute
    const path = window.location.pathname;
    const segments = path.split('/').filter(Boolean);
    // Same base-detection as getGraphDataUrl
    let fromBase = segments.slice();
    const baseEl = document.querySelector('base[href]');
    if (baseEl) {
      const baseHref = baseEl.getAttribute('href').replace(/\/$/, '');
      try {
        const baseSegs = new URL(baseHref, window.location.origin).pathname.split('/').filter(Boolean);
        if (baseSegs.length && baseSegs.length <= fromBase.length &&
            baseSegs.every((s, i) => s === fromBase[i])) {
          fromBase = fromBase.slice(baseSegs.length);
        }
      } catch(e) { /* ignore */ }
    }
    if (!baseEl && segments.length >= 1 && window.location.hostname !== 'localhost' &&
        window.location.hostname !== '127.0.0.1') {
      fromBase = segments.slice(1);
    }
    // The current article's directory depth (under base) is fromBase.length.
    // To go from "/<base>/.../article/" to "/<base>/<relUrl>", we need
    // to go up fromBase.length levels then append relUrl.
    // But relUrl is already a site-relative path (e.g. "technique/foo/")
    // — we want "<base> + relUrl".
    // Build the base from origin + detected base prefix.
    const basePath = (() => {
      if (baseEl) return new URL(baseEl.getAttribute('href').replace(/\/$/, ''), window.location.origin).pathname.replace(/\/$/, '');
      if (segments.length >= 1 && window.location.hostname !== 'localhost' &&
          window.location.hostname !== '127.0.0.1') {
        return '/' + segments[0];
      }
      return '';
    })();
    return basePath + '/' + relUrl.replace(/^\/+/, '');
  }

  function init() {
    const containers = document.querySelectorAll('.graph-view');
    const defaultUrl = getGraphDataUrl();
    containers.forEach(c => renderContainer(c, defaultUrl));
  }

  function renderContainer(c, defaultUrl) {
    if (c.dataset.rendered === '1') return;
    c.dataset.rendered = '1';
    if (!c.id) c.id = 'graph-view-auto-' + Math.random().toString(36).slice(2, 8);
    const tooltip = c.querySelector('.graph-tooltip');
    if (!tooltip) return;
    const graphUrl = c.dataset.graphUrl || defaultUrl;
    fetch(graphUrl, { credentials: 'same-origin' })
      .then(r => r.ok ? r.json() : Promise.reject(new Error('HTTP ' + r.status)))
      .then(data => renderGraph(c, tooltip, data, c.dataset.mode || 'full'))
      .catch(err => {
        console.error('[graph-component] load failed', err);
        c.innerHTML = '<div class="graph-loading">Failed to load graph: ' + err.message + '</div>';
      });
  }

  function watchForNewContainers() {
    // Re-scan when new .graph-view elements are added (e.g. by tennis-extra.js on article pages)
    const observer = new MutationObserver(muts => {
      for (const m of muts) {
        m.addedNodes.forEach(node => {
          if (node.nodeType !== 1) return;
          if (node.classList && node.classList.contains('graph-view')) {
            renderContainer(node, getGraphDataUrl());
          }
          // Also check children (in case entire sub-tree was added)
          const nested = node.querySelectorAll && node.querySelectorAll('.graph-view');
          if (nested) nested.forEach(c => renderContainer(c, getGraphDataUrl()));
        });
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  function filterForLocal(allNodes, allEdges, centerName) {
    const nodeByName = new Map(allNodes.map(n => [n.name, n]));
    const center = nodeByName.get(centerName);
    if (!center) return { nodes: [], edges: [] };

    const hop1 = new Set([center.id]);
    allEdges.forEach(e => {
      if (e.source === center.id) hop1.add(e.target);
      if (e.target === center.id) hop1.add(e.source);
    });

    const hop2 = new Set(hop1);
    hop1.forEach(id => {
      allEdges.forEach(e => {
        if (e.source === id && e.target !== center.id) hop2.add(e.target);
        if (e.target === id && e.source !== center.id) hop2.add(e.source);
      });
    });

    const nodes = allNodes.filter(n => hop2.has(n.id));
    const edges = allEdges.filter(e => hop2.has(e.source) && hop2.has(e.target));
    return { nodes, edges };
  }

  function escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function renderGraph(container, tooltip, data, mode) {
    // Clear loading message but keep tooltip
    Array.from(container.querySelectorAll('.graph-loading')).forEach(n => n.remove());

    const width = Math.max(container.clientWidth, 320);
    const height = container.clientHeight || 600;

    const articleName = container.dataset.articleName || '';
    let activeData = data;
    if (mode === 'full') {
      // For landing page: keep only top-N most-connected nodes
      const topIds = new Set(data.topIds || []);
      const idMap = new Map();
      const newNodes = data.nodes.filter(n => topIds.has(n.id)).map((n, idx) => {
        idMap.set(n.id, idx);
        return { ...n, id: idx };
      });
      const newEdges = data.edges
        .filter(e => topIds.has(e.source) && topIds.has(e.target))
        .map(e => ({ source: idMap.get(e.source), target: idMap.get(e.target) }));
      activeData = { nodes: newNodes, edges: newEdges };
    } else if (mode === 'local') {
      activeData = filterForLocal(data.nodes, data.edges, articleName);
      if (activeData.nodes.length === 0) {
        container.innerHTML = '<div class="graph-loading">No wikilinks found for this article yet.</div>';
        return;
      }
    }

    // Build cluster id→color map from data
    const clusterMap = {};
    (data.clusters || []).forEach(c => { clusterMap[c.id] = c; });

    // Controls overlay
    const controls = document.createElement('div');
    controls.className = 'graph-controls';
    container.appendChild(controls);

    // Legend overlay
    const legend = document.createElement('div');
    legend.className = 'graph-legend';
    container.appendChild(legend);

    const disabledClusters = new Set();
    let centerId = null;
    if (mode === 'local') {
      // Find the center node by article name (not by position)
      const centerNode = activeData.nodes.find(n => n.name === articleName);
      if (centerNode) centerId = centerNode.id;
    }

    const svg = d3.select(container).append('svg')
      .attr('class', 'graph-svg')
      .attr('viewBox', [0, 0, width, height])
      .attr('preserveAspectRatio', 'xMidYMid meet');

    const root = svg.append('g');

    // Arrow marker for directed links
    svg.append('defs').append('marker')
      .attr('id', 'graph-arrowhead-' + container.id)
      .attr('viewBox', '-0 -5 10 10')
      .attr('refX', 14)
      .attr('refY', 0)
      .attr('orient', 'auto')
      .attr('markerWidth', 4)
      .attr('markerHeight', 4)
      .append('path')
      .attr('d', 'M 0,-5 L 10,0 L 0,5')
      .attr('fill', '#999');

    let simulation = null;
    let playing = true;

    function buildLegend() {
      legend.innerHTML = '';
      (data.clusters || []).forEach(c => {
        if (!c.count) return;
        const item = document.createElement('span');
        item.className = 'legend-item' + (disabledClusters.has(c.id) ? ' disabled' : '');
        const dot = document.createElement('span');
        dot.className = 'legend-dot';
        dot.style.background = c.color;
        item.appendChild(dot);
        const txt = document.createElement('span');
        txt.textContent = c.label;
        item.appendChild(txt);
        item.addEventListener('click', () => {
          if (disabledClusters.has(c.id)) disabledClusters.delete(c.id);
          else disabledClusters.add(c.id);
          update();
          buildLegend();
        });
        legend.appendChild(item);
      });
    }

    function update() {
      const visibleNodes = activeData.nodes.filter(n => !disabledClusters.has(n.cluster));
      const visibleIds = new Set(visibleNodes.map(n => n.id));
      const visibleEdges = activeData.edges.filter(e =>
        visibleIds.has(typeof e.source === 'object' ? e.source.id : e.source) &&
        visibleIds.has(typeof e.target === 'object' ? e.target.id : e.target));

      if (simulation) simulation.stop();
      root.selectAll('*').remove();

      const link = root.append('g').attr('class', 'links')
        .selectAll('line').data(visibleEdges).enter().append('line')
        .attr('stroke', '#999')
        .attr('stroke-opacity', 0.3)
        .attr('stroke-width', 0.5);

      const node = root.append('g').attr('class', 'nodes')
        .selectAll('circle').data(visibleNodes).enter().append('circle')
        .attr('r', d => {
          if (d.id === centerId) return 12;
          return Math.max(2, Math.min(10, 2 + Math.sqrt(d.degree || 0) * 1.5));
        })
        .attr('fill', d => (clusterMap[d.cluster] || {}).color || '#666')
        .attr('stroke', d => d.id === centerId ? '#000' : '#fff')
        .attr('stroke-width', d => d.id === centerId ? 2 : 1)
        .style('cursor', 'pointer')
        .on('click', (event, d) => { if (d.url) window.location.href = resolveAbsoluteUrl(d.url); })
        .on('mouseover', function(event, d) {
          const label = (clusterMap[d.cluster] || {}).label || '';
          const articleName = escapeHtml(d.name);
          tooltip.innerHTML = '<strong>' + articleName + '</strong><br>' +
            '<small>' + escapeHtml(label) + ' · ' + (d.degree || 0) + ' links</small><br>' +
            '<a href="' + escapeHtml(resolveAbsoluteUrl(d.url)) + '">Open article →</a>';
          tooltip.style.display = 'block';
          const connectedIds = new Set([d.id]);
          visibleEdges.forEach(l => {
            const sId = typeof l.source === 'object' ? l.source.id : l.source;
            const tId = typeof l.target === 'object' ? l.target.id : l.target;
            if (sId === d.id) connectedIds.add(tId);
            if (tId === d.id) connectedIds.add(sId);
          });
          node.attr('opacity', n => connectedIds.has(n.id) ? 1 : 0.2);
          link.attr('stroke-opacity', l => {
            const sId = typeof l.source === 'object' ? l.source.id : l.source;
            const tId = typeof l.target === 'object' ? l.target.id : l.target;
            return (sId === d.id || tId === d.id) ? 0.9 : 0.05;
          }).attr('stroke', l => {
            const sId = typeof l.source === 'object' ? l.source.id : l.source;
            const tId = typeof l.target === 'object' ? l.target.id : l.target;
            return (sId === d.id || tId === d.id) ? '#2e7d32' : '#999';
          });
        })
        .on('mousemove', (event) => {
          const rect = container.getBoundingClientRect();
          tooltip.style.left = (event.clientX - rect.left + 12) + 'px';
          tooltip.style.top = (event.clientY - rect.top + 12) + 'px';
        })
        .on('mouseout', () => {
          tooltip.style.display = 'none';
          node.attr('opacity', 1);
          link.attr('stroke-opacity', 0.3).attr('stroke', '#999');
        });

      // Compute degree from edges (graph-data.json doesn't include degree field)
      const degreeMap = new Map();
      visibleEdges.forEach(e => {
        const sId = typeof e.source === 'object' ? e.source.id : e.source;
        const tId = typeof e.target === 'object' ? e.target.id : e.target;
        degreeMap.set(sId, (degreeMap.get(sId) || 0) + 1);
        degreeMap.set(tId, (degreeMap.get(tId) || 0) + 1);
      });
      visibleNodes.forEach(n => { n.degree = degreeMap.get(n.id) || 0; });

      // Labels on all connected nodes + center node
      const labelData = visibleNodes.filter(n => n.degree >= 1 || n.id === centerId || n._isCenter);
      const label = root.append('g').attr('class', 'labels')
        .selectAll('text').data(labelData).enter().append('text')
        .text(d => {
          const max = 22;
          return d.name.length > max ? d.name.slice(0, max - 1) + '…' : d.name;
        })
        .attr('font-size', 14)
        .attr('font-weight', 600)
        .attr('dx', 14)
        .attr('dy', 4)
        .attr('fill', '#1a1a1a')
        .attr('stroke', '#ffffff')
        .attr('stroke-width', 3)
        .attr('paint-order', 'stroke')
        .style('pointer-events', 'none')
        .style('font-family', '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif');

      simulation = d3.forceSimulation(visibleNodes)
        .force('link', d3.forceLink(visibleEdges).id(d => d.id).distance(80))
        .force('charge', d3.forceManyBody().strength(-60))
        .force('center', d3.forceCenter(width / 2, height / 2))
        .force('collide', d3.forceCollide().radius(d => Math.max(8, 6 + Math.sqrt(d.degree || 0))));

      simulation.on('tick', () => {
        link
          .attr('x1', d => d.source.x)
          .attr('y1', d => d.source.y)
          .attr('x2', d => d.target.x)
          .attr('y2', d => d.target.y);
        node
          .attr('cx', d => d.x)
          .attr('cy', d => d.y);
        label
          .attr('x', d => d.x)
          .attr('y', d => d.y);
      });

      node.call(d3.drag()
        .on('start', (event, d) => {
          if (!event.active) simulation.alphaTarget(0.3).restart();
          d.fx = d.x; d.fy = d.y;
        })
        .on('drag', (event, d) => { d.fx = event.x; d.fy = event.y; })
        .on('end', (event, d) => {
          if (!event.active) simulation.alphaTarget(0);
          d.fx = null; d.fy = null;
        }));

      svg.call(d3.zoom()
        .scaleExtent([0.2, 5])
        .on('zoom', (event) => root.attr('transform', event.transform)));
    }

    function addButton(label, onClick, modifier) {
      const btn = document.createElement('button');
      btn.textContent = label;
      if (modifier === 'active') btn.classList.add('active');
      btn.addEventListener('click', onClick);
      controls.appendChild(btn);
      return btn;
    }

    const pauseBtn = addButton('⏸ Pause', () => {
      playing = !playing;
      if (playing) { simulation.alpha(0.3).restart(); pauseBtn.textContent = '⏸ Pause'; }
      else { simulation.stop(); pauseBtn.textContent = '▶ Play'; }
    });
    addButton('↻ Reset', () => update());
    addButton('🎯 Fit', () => {
      svg.transition().duration(500).call(d3.zoom().transform, d3.zoomIdentity);
    });

    buildLegend();
    update();

    // Handle window resize
    let resizeTimer;
    window.addEventListener('resize', () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        const w = container.clientWidth;
        svg.attr('viewBox', [0, 0, w, height]);
        simulation.force('center', d3.forceCenter(w / 2, height / 2));
        simulation.alpha(0.3).restart();
      }, 200);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => { init(); watchForNewContainers(); });
  } else {
    init();
    watchForNewContainers();
  }
})();