/* PodPoll UI. Polls the API and renders the cards. Pure helpers live in logic.js. */
(function () {
  "use strict";
  const L = window.PodPollLogic;
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const link = (url, text) => (L.isSafeUrl(url)
    ? `<a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(text)}</a>` : esc(text));

  // ---- this frontend's own build (stamped into <body> at image build time) ----------------
  const FE = document.body.dataset;
  const FRONTEND_VERSION = FE.version;
  document.body.dataset.major = L.majorOf(FRONTEND_VERSION);
  $("fe-ver").textContent = FRONTEND_VERSION;

  let seen = {};
  let platform = null;     // learned from the API's /api/info
  let apiBuild = null;
  let resetProtected = false;

  // Bars: widths are set through the CSSOM, because the CSP forbids inline style="" attributes.
  function applyBars(container) {
    container.querySelectorAll("i[data-w]").forEach((i) => { i.style.width = i.dataset.w + "%"; });
  }

  function banner(html) {
    const b = $("banner");
    b.innerHTML = html || "";
    b.classList.toggle("show", Boolean(html));
  }

  async function getJSON(url) {
    const res = await fetch(url, { cache: "no-store" });
    const fe = res.headers.get("X-Frontend-Pod");
    if (fe) $("fe-pod").textContent = fe;
    if (!res.ok) throw new Error("HTTP " + res.status);
    return res.json();
  }

  // ---- platform-aware copy (all strings live in logic.js HINTS) ---------------------------
  function applyPlatform(p) {
    if (p === platform) return;
    platform = p;
    const h = L.hintsFor(p);
    if (!h) return;
    $("platform").textContent = "on " + p;
    $("platform").hidden = false;
    $("who-sub").textContent = h.whoSub;
    $("who-hint").textContent = h.whoHint;
    document.querySelectorAll(".instance-word").forEach((el) => { el.textContent = h.instance; });
    $("api-env-label").textContent = h.envLabel;
  }

  // ---- card 2: who answered? --------------------------------------------------------------
  async function pollInfo() {
    try {
      const d = await getJSON("/api/info");
      banner("");
      applyPlatform(d.platform || "docker");
      const h = L.hintsFor(platform);
      $("api-pod").textContent = d.pod;
      $("api-ver").textContent = d.version;
      $("api-node").textContent = d.node;
      const env = d.env || d.namespace;
      $("api-ns").textContent = platform === "kubernetes" ? d.namespace : env;
      const badge = $("env");
      badge.textContent = `${h.envLabel}: ${env}`;
      badge.classList.remove("env-unknown");
      badge.style.background = L.envColour(env);
      const chaos = L.chaosSummary(d.chaos);
      $("chaos").textContent = "chaos: " + chaos;
      $("chaos").hidden = !chaos;
      resetProtected = Boolean(d.reset_protected);
      seen[d.pod] = (seen[d.pod] || 0) + 1;
      renderSeen();
    } catch (e) {
      const h = L.hintsFor(platform);
      const cmds = h ? h.debug : L.UNKNOWN_PLATFORM_DEBUG;
      banner("⚠️ API unreachable (" + esc(e.message) + "). Debug it like a pro: " +
             cmds.map((c) => "<code>" + esc(c) + "</code>").join(" · "));
    }
  }

  function renderSeen() {
    const names = Object.keys(seen).sort();
    const max = Math.max(1, ...Object.values(seen));
    $("seen").innerHTML = names.map((n) =>
      `<div class="row seen"><span class="name">${esc(n)}</span>` +
      `<div class="bar"><i data-w="${(100 * seen[n]) / max}"></i></div><span>${seen[n]}</span></div>`).join("")
      || '<div class="empty">no responses yet</div>';
    applyBars($("seen"));
  }

  // ---- card 1: votes -------------------------------------------------------------------------
  async function pollResults() {
    try {
      const d = await getJSON("/api/results");
      if (d.question) $("question").textContent = d.question;
      const max = Math.max(1, ...d.results.map((r) => r.votes));
      $("options").innerHTML = d.results.map((r) =>
        `<div class="row"><b>${esc(r.option)}</b><div class="bar"><i data-w="${(100 * r.votes) / max}"></i></div>` +
        `<span>${r.votes}</span><button type="button" data-option="${esc(r.option)}">vote</button></div>`).join("");
      applyBars($("options"));
      $("total").textContent = "  total votes: " + d.total;
    } catch (e) {
      $("options").innerHTML = '<div class="empty">results unavailable right now</div>';
    }
  }

  async function vote(option) {
    const res = await fetch("/api/vote", { method: "POST", headers: { "Content-Type": "application/json" },
                                           body: JSON.stringify({ option }) }).catch(() => null);
    // The UI polls, so a failed vote self-corrects; but say so, so chaos is visible.
    $("vote-status").textContent = res && res.ok ? "" : `vote failed (${res ? "HTTP " + res.status : "network"})`;
    pollResults();
  }

  async function resetVotes() {
    const headers = {};
    if (resetProtected) {
      const token = window.prompt("Resetting votes is protected on this deployment. Reset token:");
      if (!token) return;
      headers["X-Reset-Token"] = token;
    }
    const res = await fetch("/api/reset", { method: "POST", headers }).catch(() => null);
    $("vote-status").textContent = res && res.ok ? "" : `reset failed (${res ? "HTTP " + res.status : "network"})`;
    pollResults();
  }

  // ---- card 3: what's running? ------------------------------------------------------------------
  function buildCells(b) {
    if (!b) return ["…", "…", "…", "…", "…"];
    const sha = L.shortSha(b.git_sha);
    const build = b.build_id === "local" ? "local build" : "#" + b.build_id;
    return [
      esc(b.version),
      link(L.commitUrl(b.source_url, b.git_sha), sha),
      link(b.build_url, build),
      esc(b.ci_system),
      esc(L.ageText(b.build_time, Date.now())),
    ];
  }

  function renderBuild() {
    const fe = { version: FE.version, git_sha: FE.gitSha, build_id: FE.buildId, build_url: FE.buildUrl,
                 ci_system: FE.ciSystem, build_time: FE.buildTime, source_url: FE.sourceUrl };
    [["build-fe", fe], ["build-api", apiBuild]].forEach(([id, b]) => {
      const tds = $(id).querySelectorAll("td");
      buildCells(b).forEach((html, i) => { tds[i].innerHTML = html; });
    });
    $("mixed").hidden = !(apiBuild && L.isMixedRelease(FE.gitSha, apiBuild.git_sha));
    const refs = [`frontend ref: ${FE.gitRef}`];
    if (apiBuild) refs.push(`api ref: ${apiBuild.git_ref}`);
    $("build-ref").textContent = refs.join(" · ");
  }

  async function pollBuild() {
    try { apiBuild = await getJSON("/api/build"); } catch (e) { /* keep the last answer */ }
    renderBuild();
  }

  // ---- card 4: release security -----------------------------------------------------------------
  const SEVERITIES = ["critical", "high", "medium", "low"];

  async function pollSecurity() {
    let d;
    try { d = await getJSON("/api/release/security"); } catch (e) { return; }
    $("card-security").hidden = !d.available;
    if (!d.available) return;
    const s = d.summary || {};
    const totals = s.totals || {};
    const badge = $("security-badge");
    badge.textContent = (s.status || "unknown").toUpperCase() + (s.gate ? " · gate: " + s.gate : "");
    badge.className = "rbac-badge " + (s.status === "pass" ? "pass" : "fail");
    $("security-hint").textContent =
      `Scanned ${L.shortSha(s.git_sha)} (${s.version || "?"}), ${L.ageText(s.generated_at, Date.now())}. ` +
      `${totals.suppressed || 0} finding(s) accepted as risk.`;
    const rows = (s.tools || []).map((t) => {
      const f = t.findings || {};
      return `<tr><td>${esc(t.name)}</td><td class="muted">${esc(t.category || "")}</td>` +
        SEVERITIES.map((sev) => `<td class="num ${f[sev] ? "sev-" + sev : ""}">${esc(f[sev] ?? 0)}</td>`).join("") +
        `<td class="num">${esc(t.suppressed ?? 0)}</td><td class="status-${esc(t.status)}">${esc(t.status)}</td></tr>`;
    }).join("");
    $("security-body").innerHTML =
      "<table><tr><th>tool</th><th></th><th>crit</th><th>high</th><th>med</th><th>low</th><th>accepted</th><th>result</th></tr>" +
      rows + "</table>" + (s.report_url ? `<p class="small-print">${link(s.report_url, "full report ↗")}</p>` : "");
  }

  // ---- wiring (no inline onclick: the CSP forbids inline handlers) -----------------------------------
  $("options").addEventListener("click", (e) => {
    const btn = e.target.closest("button[data-option]");
    if (btn) vote(btn.dataset.option);
  });
  $("reset-btn").addEventListener("click", resetVotes);
  $("clear-btn").addEventListener("click", () => { seen = {}; renderSeen(); });

  renderSeen();
  renderBuild();
  pollInfo(); pollResults(); pollBuild(); pollSecurity();
  setInterval(pollInfo, 1500);
  setInterval(pollResults, 3000);
  setInterval(pollBuild, 3000);
  setInterval(pollSecurity, 10000);
})();
