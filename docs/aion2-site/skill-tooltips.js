/* Skill tooltips: the MDX pages stay plain prose, this wraps skill names at runtime.
   Class = body[data-skill-class] (frontmatter `skillClass`) else the URL.
   Payloads: tools/build_tooltip_data.py */
(function () {
  'use strict';

  var MAX = 200;                       // hard cap on wraps per page
  var TIP_ID = 'skill-tip';
  var SKIP_TAG = /^(CODE|PRE|A|H1|H2|SCRIPT|STYLE|NOSCRIPT|BUTTON|INPUT|TEXTAREA|SELECT)$/;
  // The class pages already carry a full skill table and the tool pages are the
  // browser/planner islands: wrapping names inside either is noise, and one table
  // would eat the whole MAX budget on its own.
  var SKIP_CLASS = /(^|\s)(skill-table|skills-browser|stigma-planner|skill-point-planner|skill-ref)(\s|$)/;
  // Latin + Hangul syllables both count as "inside a word" for boundary tests.
  var WORD = /[A-Za-z0-9À-ɏ가-힣]/;

  var byCode = {}, tip = null, cur = null;

  function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

  function h(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function boundaryOk(text, start, end, term) {
    if (WORD.test(term.charAt(0)) && start > 0 && WORD.test(text.charAt(start - 1))) return false;
    if (WORD.test(term.charAt(term.length - 1)) && end < text.length && WORD.test(text.charAt(end))) return false;
    return true;
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

  function place(t, span) {
    t.style.left = '0px';
    t.style.top = '0px';
    var r = span.getBoundingClientRect(), b = t.getBoundingClientRect();
    var vw = document.documentElement.clientWidth, vh = document.documentElement.clientHeight;
    var x = Math.min(r.left, vw - b.width - 8);
    if (x < 8) x = 8;
    var y = r.bottom + 8;
    if (y + b.height > vh - 8) y = Math.max(8, r.top - b.height - 8);
    t.style.left = x + 'px';
    t.style.top = y + 'px';
  }

  function show(span) {
    var s = byCode[span.getAttribute('data-code')];
    if (!s) return;
    var t = tipEl(), o = '';
    if (s.icon) o += '<img class="skill-tip-icon" src="' + h(s.icon) + '" alt="">';
    o += '<p class="skill-tip-name">' + h(s.name);
    if (s.ko && s.ko !== s.name) o += ' <span class="skill-tip-ko">' + h(s.ko) + '</span>';
    o += '</p>';
    if (s.kind) o += '<span class="skill-tip-kind">' + h(s.kind) + '</span>';
    var bits = [];
    if (s.cd) bits.push('CD ' + s.cd);
    if (s.cost) bits.push('MP ' + s.cost);
    if (s.range) bits.push(s.range);
    if (s.cast) bits.push(s.cast);
    if (bits.length) o += '<p class="skill-tip-stats">' + h(bits.join(' · ')) + '</p>';
    var body = s.short || s.desc;
    if (body) o += '<p class="skill-tip-short">' + h(body) + '</p>';
    if (s.rank20) o += '<p class="skill-tip-r20">' + h(s.rank20) + '</p>';
    t.innerHTML = o;
    t.hidden = false;
    place(t, span);
    cur = span;
  }

  function hide() {
    if (tip) tip.hidden = true;
    cur = null;
  }

  function makeRef(s, term) {
    var span = document.createElement('span');
    span.className = 'skill-ref';
    span.setAttribute('data-code', s.code);
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

  function start(root, list) {
    var byTerm = {}, terms = [], i, j, s, t, cand;
    for (i = 0; i < list.length; i++) {
      s = list[i];
      byCode[s.code] = s;
      cand = [s.name, s.en, s.ko];
      for (j = 0; j < 3; j++) {
        t = cand[j];
        // 1-2 char names would match inside ordinary prose; skip them.
        if (t && t.length > 2 && !byTerm[t]) { byTerm[t] = s; terms.push(t); }
      }
    }
    if (!terms.length) return;
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
        var term = m[0], a = m.index, b = a + term.length;
        if (!boundaryOk(text, a, b, term)) { re.lastIndex = a + 1; continue; }
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
    if (!count) return;

    root.addEventListener('mouseover', function (e) {
      var r = e.target.closest && e.target.closest('.skill-ref');
      if (r && r !== cur) show(r);
    });
    root.addEventListener('mouseout', function (e) {
      var r = e.target.closest && e.target.closest('.skill-ref');
      if (r && (!e.relatedTarget || !r.contains(e.relatedTarget))) hide();
    });
    root.addEventListener('focusin', function (e) {
      var r = e.target.closest && e.target.closest('.skill-ref');
      if (r) show(r);
    });
    root.addEventListener('focusout', function (e) {
      if (e.target.closest && e.target.closest('.skill-ref')) hide();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' || e.key === 'Esc') hide();
    });
    // Touch: tap toggles. On a hover-capable pointer mouseover already opened it,
    // so a click there must not close it again — only an outside click dismisses.
    document.addEventListener('click', function (e) {
      var r = e.target.closest ? e.target.closest('.skill-ref') : null;
      if (!r) { hide(); return; }
      if (!matchMedia('(hover: hover)').matches) { if (cur === r) hide(); else show(r); }
    });
    window.addEventListener('scroll', hide, { passive: true });
    window.addEventListener('resize', hide);
  }

  function init() {
    var path = location.pathname;
    if (path.indexOf('/tools/') !== -1) return;          // browser + planner islands
    var lm = path.match(/^\/(es|en)\//);
    var lang = lm ? lm[1] : 'es';
    var slug = (document.body.dataset && document.body.dataset.skillClass) || '';
    if (!slug) {
      var cm = path.match(/^\/(?:es|en)\/classes\/([a-z]+)/);
      if (cm) slug = cm[1];
    }
    if (!/^[a-z]+$/.test(slug)) return;
    var root = document.querySelector('.sl-markdown-content');
    if (!root) return;
    fetch('/skill-tooltips/' + slug + '.' + lang + '.json')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (list) { if (list && list.length) start(root, list); })
      .catch(function () { /* no payload for this class: leave the prose alone */ });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
