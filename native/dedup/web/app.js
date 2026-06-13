// SPDX-License-Identifier: Apache-2.0
// Pablo dedup — review UI. Vanilla JS, no build step.

const state = {
  clusters: [],
  discards: new Set(),   // image ids marked for quarantine
};

const $ = (sel) => document.querySelector(sel);
const fmtSize = (b) => {
  if (b >= 1 << 20) return (b / (1 << 20)).toFixed(1) + " MB";
  if (b >= 1 << 10) return (b / (1 << 10)).toFixed(0) + " KB";
  return b + " B";
};

async function load() {
  const res = await fetch("/api/clusters");
  const data = await res.json();
  state.clusters = data.clusters || [];
  render();
}

function render() {
  const root = $("#clusters");
  root.innerHTML = "";

  const totalImgs = state.clusters.reduce((n, c) => n + c.members.length, 0);
  $("#stats").textContent =
    `${state.clusters.length} clusters · ${totalImgs} images · ` +
    `${totalImgs - state.clusters.length} redundant copies`;

  if (state.clusters.length === 0) {
    root.innerHTML = `<div class="empty">No duplicate clusters. Run <code>dedup scan</code> first.</div>`;
    return;
  }

  for (const c of state.clusters) {
    root.appendChild(renderCluster(c));
  }
  updateActionBar();
}

function renderCluster(c) {
  const el = document.createElement("section");
  el.className = "cluster" + (c.flagged_oversize ? " oversize" : "");

  const head = document.createElement("div");
  head.className = "cluster-head";
  head.innerHTML =
    `<h2>Cluster ${c.id}</h2><span class="count">${c.members.length} images</span>` +
    (c.flagged_oversize ? `<span class="warn">⚠ oversize — verify manually</span>` : "");

  const spacer = document.createElement("span");
  spacer.className = "spacer";
  head.appendChild(spacer);

  const btn = document.createElement("button");
  btn.textContent = "Mark all but keeper";
  btn.onclick = () => {
    for (const m of c.members) {
      if (!m.is_keeper) state.discards.add(m.id);
    }
    render();
  };
  head.appendChild(btn);
  el.appendChild(head);

  const grid = document.createElement("div");
  grid.className = "grid";
  for (const m of c.members) grid.appendChild(renderTile(m));
  el.appendChild(grid);
  return el;
}

function renderTile(m) {
  const tile = document.createElement("div");
  const discarding = state.discards.has(m.id);
  tile.className = "tile" + (m.is_keeper ? " keeper" : "") + (discarding ? " discard" : "");

  const img = document.createElement("img");
  img.loading = "lazy";
  img.src = `/api/image?id=${m.id}`;
  img.alt = m.path;
  tile.appendChild(img);

  if (m.is_keeper) {
    const badge = document.createElement("span");
    badge.className = "badge";
    badge.textContent = "KEEP";
    tile.appendChild(badge);
  }

  const zoom = document.createElement("div");
  zoom.className = "zoom";
  zoom.textContent = "⤢";
  zoom.onclick = (e) => { e.stopPropagation(); openLightbox(m.id); };
  tile.appendChild(zoom);

  const meta = document.createElement("div");
  meta.className = "meta";
  const name = m.path.split(/[\\/]/).pop();
  meta.textContent = `${name} · ${m.format.toUpperCase()} · ${fmtSize(m.size)}`;
  tile.appendChild(meta);

  // Click toggles quarantine selection. Discarding the suggested keeper needs
  // an explicit confirmation so a cluster is never silently left with no master.
  tile.onclick = () => {
    if (state.discards.has(m.id)) {
      state.discards.delete(m.id);
    } else {
      if (m.is_keeper &&
          !confirm("This is the suggested KEEPER of its cluster — quarantine it anyway?")) {
        return;
      }
      state.discards.add(m.id);
    }
    render();
  };
  return tile;
}

function updateActionBar() {
  const n = state.discards.size;
  const btn = $("#quarantineBtn");
  btn.textContent = `Quarantine ${n} selected`;
  btn.disabled = n === 0;
}

function openLightbox(id) {
  $("#lightboxImg").src = `/api/image?id=${id}&full=1`;
  $("#lightbox").classList.remove("hidden");
}
$("#lightbox").onclick = () => $("#lightbox").classList.add("hidden");

$("#quarantineBtn").onclick = async () => {
  const ids = [...state.discards];
  if (ids.length === 0) return;

  // Safety: surface keepers being discarded and clusters left with no survivor.
  let keeperCount = 0;
  const noSurvivor = [];
  for (const c of state.clusters) {
    const surviving = c.members.filter((m) => !state.discards.has(m.id));
    if (surviving.length === 0) noSurvivor.push(c.id);
    for (const m of c.members) if (m.is_keeper && state.discards.has(m.id)) keeperCount++;
  }
  let msg = `Move ${ids.length} image(s) to quarantine? (reversible — files are moved, not deleted)`;
  if (keeperCount > 0) msg += `\n\n⚠ ${keeperCount} of these is the suggested KEEPER of its cluster.`;
  if (noSurvivor.length > 0)
    msg += `\n⚠ ${noSurvivor.length} cluster(s) would have NO surviving image (clusters: ${noSurvivor.join(", ")}).`;
  if (!confirm(msg)) return;

  const btn = $("#quarantineBtn");
  btn.disabled = true;
  btn.textContent = "Moving…";
  try {
    const res = await fetch("/api/act", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ discards: ids }),
    });
    const out = await res.json();
    const movedIds = new Set((out.moved || []).map((x) => x.id));
    // Drop quarantined members; remove now-trivial (≤1 member) clusters.
    for (const c of state.clusters) c.members = c.members.filter((m) => !movedIds.has(m.id));
    state.clusters = state.clusters.filter((c) => c.members.length > 1);
    state.discards.clear();
    if ((out.errors || []).length) {
      alert(`Moved ${movedIds.size}. ${out.errors.length} error(s) — see server log.`);
    }
    render();
  } catch (e) {
    alert("Request failed: " + e);
  } finally {
    updateActionBar();
  }
};

load();
