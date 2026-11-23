// ============================================================================
// Sidebar navigation — no fetch, works when the page is opened via file://.
//
// 1. NAV_PAGES — single source for the "Submodules" menu (one line per page).
// 2. renderNav() — fills #nav-pages, marks the current page active.
// 3. buildGroups() — wraps each .nav-section label with its following links
//    into a group: the label gets a highlight background, and the in-page
//    anchor items get auto numbering (01, 02, …) plus indentation.
// ============================================================================
"use strict";

const NAV_PAGES = [
  { href: "index.html",                 label: "APB UART (Top)" },
  { href: "spec/apb_slave_spec.html",   label: "apb_slave"      },
  { href: "spec/apb2reg_spec.html",     label: "apb2reg"        },
  { href: "spec/rw_reg_spec.html",      label: "rw_reg"         },
];

const PAGE_IN_SPEC = location.pathname.split("/").filter(Boolean).includes("spec");
const PREFIX = PAGE_IN_SPEC ? "../" : "";

// ---------------------------------------------------------------------------
// "Submodules" menu — links are declared relative to the docs root
// ---------------------------------------------------------------------------
function renderNav() {
  const holder = document.getElementById("nav-pages");
  if (!holder) return;
  const current = location.pathname.split("/").pop();
  holder.innerHTML = NAV_PAGES.map(p => {
    const href = PREFIX + p.href;
    const active = href.split("/").pop() === current;
    return '<a href="' + href + '"' + (active ? ' class="active"' : "") + ">" + p.label + "</a>";
  }).join("");
}

// ---------------------------------------------------------------------------
// Group highlighting + item numbering
// ---------------------------------------------------------------------------
function buildGroups() {
  const sidebar = document.getElementById("sidebar");
  if (!sidebar) return;

  const labels = Array.from(sidebar.querySelectorAll(".nav-section"));
  labels.forEach(label => {
    // Wrap the label and everything after it (up to the next label) into a group.
    const group = document.createElement("div");
    group.className = "nav-group";
    label.parentNode.insertBefore(group, label);
    group.appendChild(label);
    let next = group.nextElementSibling;
    while (next && !next.classList.contains("nav-section")) {
      group.appendChild(next);
      next = group.nextElementSibling;
    }

    // Number the in-page anchor items (01, 02, …).
    // Cross-page links (Submodules menu) stay unnumbered.
    let n = 0;
    group.querySelectorAll(':scope > a[href^="#"]').forEach(a => {
      n += 1;
      const num = document.createElement("span");
      num.className = "nav-num";
      num.textContent = String(n).padStart(2, "0");
      a.insertBefore(num, a.firstChild);
    });
  });
}

document.addEventListener("DOMContentLoaded", () => {
  renderNav();
  buildGroups();
});
