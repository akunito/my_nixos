/* Skill tooltips, one popover for the whole site.

   Two ways in, same popover:
     - [data-skill="<code>"] elements the components render (tables, browser, planners),
       anywhere on the page. Their class comes from the nearest [data-skill-class].
     - skill names matched in prose, on class pages only (the components already say
       everything a tooltip would, and one table would eat the whole MAX budget).

   Payloads: /skill-tooltips/<slug>.<lang>.json (tools/build_tooltip_data.py), fetched
   once per class and only on the first hover/focus of one of its skills — the browser
   page can touch all eight classes, so nothing is fetched up front. */
(function () {
  'use strict';

  var MAX = 200;                       // hard cap on prose wraps per page
  var TIP_ID = 'skill-tip';
  var SKIP_TAG = /^(CODE|PRE|A|H1|H2|SCRIPT|STYLE|NOSCRIPT|BUTTON|INPUT|TEXTAREA|SELECT)$/;
  // The class pages already carry a full skill table and the tool pages are the
  // browser/planner islands: wrapping names inside either is noise.
  var SKIP_CLASS = /(^|\s)(skill-table|skills-browser|stigma-planner|skill-point-planner|skill-ref)(\s|$)/;
  // Latin + Hangul syllables both count as "inside a word" for boundary tests.
  var WORD = /[A-Za-z0-9À-ɏ가-힣]/;
  var L = {
    es: { chain: 'Cadena', combos: 'combos' },
    en: { chain: 'Chain', combos: 'combos' },
  };

  var lang = 'es', pageSlug = '', t = L.es;
  var cache = {};          // slug -> Promise<{meta, byCode}>
  var tip = null, cur = null;

  function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

  function h(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  /* One fetch per class for the life of the page, shared by every ref of that class. */
  function load(slug) {
    var p = cache[slug];
    if (p) return p;
    p = fetch('/skill-tooltips/' + slug + '.' + lang + '.json')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (doc) {
        var list = doc && doc.skills, by = {}, i;
        if (list) for (i = 0; i < list.length; i++) by[list[i].code] = list[i];
        return { meta: (doc && doc.meta) || {}, byCode: by, list: list || [] };
      })
      .catch(function () { return { meta: {}, byCode: {}, list: [] }; });
    cache[slug] = p;
    return p;
  }

  /* The class a ref belongs to: its own container wins, the page is the fallback. */
  function slugOf(el) {
    var owner = el.closest('[data-skill-class]');
    return (owner && owner.getAttribute('data-skill-class')) || pageSlug;
  }

  function tipEl() {
    if (tip) return tip;
    tip = document.createElement('div');
    tip.id = TIP_ID;
    tip.className = 'skill-tip';
    tip.setAttribute('role', 'tooltip');
    tip.hidden = true;
    document.body.appendChild(tip);
    return tip;
  }

  function place(el) {
    var t2 = tipEl();
    t2.style.left = '0px';
    t2.style.top = '0px';
    var r = el.getBoundingClientRect(), b = t2.getBoundingClientRect();
    var vw = document.documentElement.clientWidth, vh = document.documentElement.clientHeight;
    var x = Math.min(r.left, vw - b.width - 8);
    if (x < 8) x = 8;
    var y = r.bottom + 8;
    if (y + b.height > vh - 8) y = Math.max(8, r.top - b.height - 8);
    t2.style.left = x + 'px';
    t2.style.top = y + 'px';
  }

  function render(el, s, cls, slug) {
    var o = '', i, bits = [], names = [], to;
    if (s.icon) o += '<img class="skill-tip-icon" src="' + h(s.icon) + '" alt="">';
    o += '<p class="skill-tip-name">' + h(s.name);
    if (s.ko && s.ko !== s.name) o += ' <span class="skill-tip-ko">' + h(s.ko) + '</span>';
    o += '</p>';
    var kind = (cls.meta.kindLabel && cls.meta.kindLabel[s.kind]) || s.kind;
    if (kind) o += '<span class="skill-tip-kind">' + h(kind) + '</span>';
    if (s.cd) bits.push('CD ' + s.cd);
    if (s.cost) bits.push('MP ' + s.cost);
    if (s.range) bits.push(s.range);
    if (s.cast) bits.push(s.cast);
    if (bits.length) o += '<p class="skill-tip-stats">' + h(bits.join(' · ')) + '</p>';
    var body = s.short || s.desc;
    if (body) o += '<p class="skill-tip-short">' + h(body) + '</p>';
    if (s.rank20) o += '<p class="skill-tip-r20">' + h(s.rank20) + '</p>';
    if (s.chain) {
      for (i = 0; i < s.chain.length; i++) {
        to = cls.byCode[s.chain[i][1]];
        if (to) names.push(to.name);
      }
      if (names.length) {
        o += '<p class="skill-tip-chain">' + h(t.chain) + ': ' + h(names.join(' → ')) + '</p>';
      }
    }
    // The table passes the anchor it already computed; anywhere else the payload carries it.
    var href = el.getAttribute('data-combos')
      || (s.anchor ? '/' + lang + '/classes/' + slug + '-skills-guide/#' + s.anchor : '');
    if (href) o += '<p class="skill-tip-combos"><a href="' + h(href) + '">' + h(t.combos) + '</a></p>';
    var t2 = tipEl();
    t2.innerHTML = o;
    t2.hidden = false;
    place(el);
  }

  function show(el) {
    cur = el;
    var slug = slugOf(el);
    if (!slug) return;
    load(slug).then(function (cls) {
      if (cur !== el) return;                        // pointer already moved on
      var s = cls.byCode[el.getAttribute('data-skill')];
      if (s) render(el, s, cls, slug);
    });
  }

  function hide() {
    if (tip) tip.hidden = true;
    cur = null;
  }

  function makeRef(s, term) {
    var span = document.createElement('span');
    span.className = 'skill-ref';
    span.setAttribute('data-skill', s.code);
    span.setAttribute('tabindex', '0');
    span.setAttribute('aria-describedby', TIP_ID);
    if (s.icon) {
      var img = document.createElement('img');
      img.className = 'skill-ref-icon';
      img.src = s.icon;
      img.alt = '';
      img.loading = 'lazy';
      img.setAttribute('aria-hidden', 'true');
      span.appendChild(img);
    }
    span.appendChild(document.createTextNode(term));
    return span;
  }

  /* Wrap matched skill names in the page's prose. Class pages only. */
  function wrapProse(root, list) {
    var byTerm = {}, terms = [], i, j, s, term, cand;
    for (i = 0; i < list.length; i++) {
      s = list[i];
      cand = [s.name, s.en, s.ko];
      for (j = 0; j < 3; j++) {
        term = cand[j];
        // 1-2 char names would match inside ordinary prose; skip them.
        if (term && term.length > 2 && !byTerm[term]) { byTerm[term] = s; terms.push(term); }
      }
    }
    if (!terms.length) return 0;
    terms.sort(function (a, b) { return b.length - a.length; });   // longest first
    var re = new RegExp(terms.map(esc).join('|'), 'g');

    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        if (!n.nodeValue || n.nodeValue.length < 3) return NodeFilter.FILTER_REJECT;
        for (var p = n.parentElement; p && p !== root.parentElement; p = p.parentElement) {
          if (SKIP_TAG.test(p.tagName)) return NodeFilter.FILTER_REJECT;
          if (p.hasAttribute('data-no-skill-tooltip')) return NodeFilter.FILTER_REJECT;
          if (typeof p.className === 'string' && SKIP_CLASS.test(p.className)) return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);

    var count = 0;
    for (i = 0; i < nodes.length && count < MAX; i++) {
      var node = nodes[i], text = node.nodeValue, frag = null, last = 0, m;
      re.lastIndex = 0;
      while ((m = re.exec(text)) !== null && count < MAX) {
        term = m[0];
        var a = m.index, b = a + term.length;
        if (WORD.test(term.charAt(0)) && a > 0 && WORD.test(text.charAt(a - 1))) { re.lastIndex = a + 1; continue; }
        if (WORD.test(term.charAt(term.length - 1)) && b < text.length && WORD.test(text.charAt(b))) { re.lastIndex = a + 1; continue; }
        if (!frag) frag = document.createDocumentFragment();
        if (a > last) frag.appendChild(document.createTextNode(text.slice(last, a)));
        frag.appendChild(makeRef(byTerm[term], term));
        last = b;
        count++;
      }
      if (frag) {
        if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
        node.parentNode.replaceChild(frag, node);
      }
    }
    return count;
  }

  /* Delegated on document: the browser and the planners build their rows after this
     runs, and re-build them on every filter change. */
  var bound = false;
  function bind() {
    if (bound) return;
    bound = true;
    document.addEventListener('mouseover', function (e) {
      var r = e.target.closest && e.target.closest('[data-skill]');
      if (r && r !== cur) show(r); else if (!r && cur) hide();
    });
    document.addEventListener('focusin', function (e) {
      var r = e.target.closest && e.target.closest('[data-skill]');
      if (r) show(r); else hide();
    });
    document.addEventListener('focusout', function (e) {
      if (e.target.closest && e.target.closest('[data-skill]')) hide();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' || e.key === 'Esc') hide();
    });
    // Touch: tap toggles. On a hover-capable pointer mouseover already opened it,
    // so a click there must not close it again — only an outside click dismisses.
    document.addEventListener('click', function (e) {
      var r = e.target.closest ? e.target.closest('[data-skill]') : null;
      if (!r) { if (!(e.target.closest && e.target.closest('.skill-tip'))) hide(); return; }
      if (!matchMedia('(hover: hover)').matches) { if (cur === r) hide(); else show(r); }
    });
    window.addEventListener('scroll', hide, { passive: true });
    window.addEventListener('resize', hide);
  }

  function init() {
    var path = location.pathname;
    var lm = path.match(/^\/(es|en)\//);
    lang = lm ? lm[1] : 'es';
    t = L[lang];
    pageSlug = (document.body.dataset && document.body.dataset.skillClass) || '';
    if (!pageSlug) {
      var cm = path.match(/^\/(?:es|en)\/classes\/([a-z]+)/);
      if (cm) pageSlug = cm[1];
    }
    if (!/^[a-z]*$/.test(pageSlug)) pageSlug = '';

    // Components render their own refs; nothing to fetch until one is hovered.
    if (document.querySelector('[data-skill]')) bind();

    // Prose matching needs the class payload up front, and only class pages get it.
    var root = pageSlug && path.indexOf('/classes/') !== -1
      ? document.querySelector('.sl-markdown-content') : null;
    if (!root) return;
    load(pageSlug).then(function (cls) {
      if (cls.list.length && wrapProse(root, cls.list)) bind();
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
