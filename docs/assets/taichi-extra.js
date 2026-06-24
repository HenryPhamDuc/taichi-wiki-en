// Tennis WIKI - Client-side enhancements
// Adds copy buttons to code blocks + local knowledge graph per article.

// ====================================================================
// Copy buttons on code blocks
// ====================================================================
document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('pre code').forEach((block) => {
        const btn = document.createElement('button');
        btn.className = 'copy-button';
        btn.textContent = '📋';
        btn.title = 'Copy to clipboard';
        btn.onclick = () => {
            navigator.clipboard.writeText(block.textContent);
            btn.textContent = '✓';
            setTimeout(() => btn.textContent = '📋', 1500);
        };
        btn.style.cssText = 'position:absolute;top:8px;right:8px;background:rgba(255,255,255,0.1);border:none;color:#e8f5e9;cursor:pointer;padding:4px 8px;border-radius:3px;font-size:14px;';
        block.parentElement.style.position = 'relative';
        block.parentElement.appendChild(btn);
    });
});

// ====================================================================
// Local knowledge graph (per-article)
// Injects a small interactive graph at the top of every article
// showing the current article + its 2-hop wikilink neighborhood.
// Skipped on: landing page (index.md), search page, category index pages.
// ====================================================================
(function() {
    function injectLocalGraph() {
        // Skip on non-article pages
        const article = document.querySelector('article.md-content__inner');
        if (!article) return;

        // Skip if there's already a graph-view on this page
        if (document.querySelector('.graph-view')) return;

        // Skip on landing page (it has its own full graph)
        const h1 = article.querySelector('h1');
        if (!h1) return;
        const articleTitle = h1.textContent.trim();
        if (!articleTitle) return;

        // Skip on category index pages (no real article content below H1)
        // Heuristic: if the article is shorter than 800 chars after H1, treat as index
        const bodyText = (article.textContent || '').trim();
        if (bodyText.length < 800) return;

        // Compute article stem from URL path (e.g. /technique/kinetic-chain/ -> kinetic-chain)
        // Use decodeURIComponent to handle URL-encoded chars (Vietnamese diacritics, parens, etc.)
        const pathParts = window.location.pathname.split('/').filter(Boolean);
        // Strip repo-name prefix for GitHub Pages (e.g. "tennis-wiki" first segment)
        let fromBase = pathParts.slice();
        if (!document.querySelector('base[href]') &&
            window.location.hostname !== 'localhost' &&
            window.location.hostname !== '127.0.0.1' &&
            fromBase.length >= 1) {
          fromBase = fromBase.slice(1);
        }
        // Skip section index pages (URL ends with /<section>/, one segment under base)
        // and landing page (/). These are flat index pages, not articles.
        if (fromBase.length <= 1) return;

        let stem = fromBase[fromBase.length - 1];
        try { stem = decodeURIComponent(stem); } catch(e) { /* keep raw */ }

        // Build the graph container
        const container = document.createElement('div');
        container.className = 'graph-view graph-local';
        container.dataset.mode = 'local';
        container.dataset.articleName = stem;
        // graphUrl computed by graph-component.js based on page depth
        container.id = 'graph-view-local-' + stem;
        container.innerHTML = '<div class="graph-loading">Loading related articles...</div><div class="graph-tooltip"></div>';

        // Add a small heading before it
        const heading = document.createElement('h2');
        heading.textContent = '🕸️ Related Articles';
        heading.style.marginTop = '2rem';

        // Insert before the first paragraph (or after H1)
        const firstP = article.querySelector('p, h2, ul, ol, pre, table, blockquote');
        if (firstP && firstP.parentNode === article) {
            article.insertBefore(heading, firstP);
            article.insertBefore(container, firstP);
        } else {
            article.appendChild(heading);
            article.appendChild(container);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', injectLocalGraph);
    } else {
        injectLocalGraph();
    }
})();
