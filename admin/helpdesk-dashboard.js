(function () {
  "use strict";

  TonztoonAdmin.mountShell();

  const escapeHtml = TonztoonAdmin.escapeHtml;
  const formatDate = TonztoonAdmin.formatDate;
  const normalize = TonztoonAdmin.normalize;
  const detailRow = TonztoonAdmin.detailRow;
  const notify = TonztoonAdmin.notify;
  const setButtonLoading = TonztoonAdmin.setButtonLoading;
  const animateCounter = TonztoonAdmin.animateCounter;

  const STATUS_LABELS = {
    open: "Open",
    in_progress: "Diproses",
    resolved: "Resolved",
    closed: "Closed",
  };
  const STATUS_BADGE_CLASS = {
    open: "badge-amber",
    in_progress: "badge-blue",
    resolved: "badge-green",
    closed: "badge-slate",
  };

  const state = {
    apiBase: TonztoonAdmin.DEFAULT_API_BASE || "http://127.0.0.1:8000",
    token: "",
    items: [],
    recentItems: [],
    selectedId: null,
    pagination: { page: 1, perPage: 50, total: 0 },
    counts: { all: 0, open: 0, in_progress: 0, resolved: 0, closed: 0 },
    loading: { list: false, save: false },
    charts: {
      statusDist: null,
      ticketsTime: null,
    }
  };

  const els = {
    apiBaseLabel: document.querySelector("#apiBaseLabel"),
    reloadBtn: document.querySelector("#reloadBtn"),
    totalCount: document.querySelector("#totalCount"),
    openCount: document.querySelector("#openCount"),
    progressCount: document.querySelector("#progressCount"),
    resolvedCount: document.querySelector("#resolvedCount"),
    closedCount: document.querySelector("#closedCount"),
    searchInput: document.querySelector("#searchInput"),
    categoryFilter: document.querySelector("#categoryFilter"),
    statusFilter: document.querySelector("#statusFilter"),
    submissionsTable: document.querySelector("#submissionsTable"),
    emptyState: document.querySelector("#emptyState"),
    paginationSummary: document.querySelector("#paginationSummary"),
    pageSizeSelect: document.querySelector("#pageSizeSelect"),
    prevPageBtn: document.querySelector("#prevPageBtn"),
    nextPageBtn: document.querySelector("#nextPageBtn"),
    detailEmpty: document.querySelector("#detailEmpty"),
    workflowForm: document.querySelector("#workflowForm"),
    detailReference: document.querySelector("#detailReference"),
    detailStatus: document.querySelector("#detailStatus"),
    detailMeta: document.querySelector("#detailMeta"),
    detailContent: document.querySelector("#detailContent"),
    workflowStatusField: document.querySelector("#workflowStatusField"),
    adminNoteField: document.querySelector("#adminNoteField"),
    saveWorkflowBtn: document.querySelector("#saveWorkflowBtn"),
  };

  const adminSession = TonztoonAdmin.createFeatureSession({
    state,
    onLogout: () => {
      state.items = [];
      state.selectedId = null;
    },
  });
  const apiFetch = adminSession.apiFetch;
  const handleRequestError = adminSession.handleRequestError;
  const logout = adminSession.logout;

  const hasSession = adminSession.restoreSession();
  bindEvents();
  lucide.createIcons();
  if (hasSession) {
    els.apiBaseLabel.textContent = state.apiBase;
    loadDashboard();
  }

  function bindEvents() {
    /* Sidebar logout */
    document.addEventListener("click", (event) => {
      const sidebarAction = event.target.closest("[data-sidebar-action]");
      if (sidebarAction?.dataset.sidebarAction === "logout") logout();
    });

    els.reloadBtn.addEventListener("click", loadDashboard);
    els.workflowForm.addEventListener("submit", saveWorkflow);
    els.searchInput.addEventListener("input", renderTable);
    els.categoryFilter.addEventListener("change", () => resetAndLoad());
    els.statusFilter.addEventListener("change", () => resetAndLoad());
    els.pageSizeSelect.addEventListener("change", () => {
      state.pagination.perPage = Number(els.pageSizeSelect.value);
      resetAndLoad();
    });
    els.prevPageBtn.addEventListener("click", () => {
      if (state.pagination.page <= 1) return;
      state.pagination.page -= 1;
      loadSubmissions();
    });
    els.nextPageBtn.addEventListener("click", () => {
      if (state.pagination.page >= totalPages()) return;
      state.pagination.page += 1;
      loadSubmissions();
    });
    document.addEventListener("click", (event) => {
      const rowAction = event.target.closest("[data-select-submission]");
      if (rowAction) selectSubmission(rowAction.dataset.selectSubmission);
      const summary = event.target.closest("[data-summary-status]");
      if (summary) {
        els.statusFilter.value = summary.dataset.summaryStatus;
        resetAndLoad();
      }
    });
  }

  async function loadDashboard() {
    const statusLoader = document.getElementById("statusChartLoader");
    const timeLoader = document.getElementById("ticketsTimeChartLoader");
    if (statusLoader) statusLoader.classList.add("active");
    if (timeLoader) timeLoader.classList.add("active");

    const loaded = await loadSubmissions();
    if (loaded) await loadCounts();
    return loaded;
  }

  async function loadSubmissions() {
    if (state.loading.list) return false;
    setLoading("list", true);
    try {
      const params = new URLSearchParams({
        page: String(state.pagination.page),
        per_page: String(state.pagination.perPage),
      });
      if (els.categoryFilter.value) params.set("category", els.categoryFilter.value);
      if (els.statusFilter.value) params.set("status", els.statusFilter.value);
      const payload = await apiFetch(`/api/v1/helpdesk/submissions?${params}`);
      state.items = payload.items || [];
      state.pagination.total = Number(payload.total || 0);
      state.pagination.page = Number(payload.page || state.pagination.page);
      state.pagination.perPage = Number(payload.per_page || state.pagination.perPage);
      if (!state.items.some((item) => item.id === state.selectedId)) {
        state.selectedId = state.items[0]?.id || null;
      }
      render();
      return true;
    } catch (error) {
      handleRequestError(error);
      return false;
    } finally {
      setLoading("list", false);
    }
  }

  async function loadCounts() {
    const statuses = ["open", "in_progress", "resolved", "closed"];
    try {
      const [allPayload, ...statusPayloads] = await Promise.all([
        apiFetch("/api/v1/helpdesk/submissions?page=1&per_page=1"),
        ...statuses.map((status) =>
          apiFetch(`/api/v1/helpdesk/submissions?page=1&per_page=1&status=${status}`),
        ),
      ]);
      state.counts.all = Number(allPayload.total || 0);
      statuses.forEach((status, i) => {
        state.counts[status] = Number(statusPayloads[i].total || 0);
      });

      // Load recent 200 items for the charts to count tickets over time
      const recentPayload = await apiFetch("/api/v1/helpdesk/submissions?page=1&per_page=200");
      state.recentItems = recentPayload.items || [];

      renderCounts();
      renderCharts();
    } catch (error) {
      handleRequestError(error);
    } finally {
      const statusLoader = document.getElementById("statusChartLoader");
      const timeLoader = document.getElementById("ticketsTimeChartLoader");
      if (statusLoader) statusLoader.classList.remove("active");
      if (timeLoader) timeLoader.classList.remove("active");
    }
  }

  function resetAndLoad() {
    state.pagination.page = 1;
    state.selectedId = null;
    loadSubmissions();
  }

  function selectSubmission(id) {
    state.selectedId = id;
    renderTable();
    renderDetail();
  }

  async function saveWorkflow(event) {
    event.preventDefault();
    const selected = selectedSubmission();
    if (!selected || state.loading.save) return;
    setLoading("save", true);
    try {
      const updated = await apiFetch(`/api/v1/helpdesk/submissions/${selected.id}`, {
        method: "PATCH",
        body: {
          status: els.workflowStatusField.value,
          admin_note: els.adminNoteField.value.trim() || null,
        },
      });
      state.items = state.items.map((item) => (item.id === updated.id ? updated : item));
      render();

      const statusLoader = document.getElementById("statusChartLoader");
      const timeLoader = document.getElementById("ticketsTimeChartLoader");
      if (statusLoader) statusLoader.classList.add("active");
      if (timeLoader) timeLoader.classList.add("active");

      await loadCounts();
      notify(`Submission ${updated.reference_code} diperbarui.`);
    } catch (error) {
      handleRequestError(error);
    } finally {
      setLoading("save", false);
    }
  }

  /* ── Render ─────────────────────────────────────────────────────────── */
  function render() {
    renderCounts();
    renderTable();
    renderPagination();
    renderDetail();
    syncLoading();
    lucide.createIcons();
  }

  function renderCharts() {
    if (!window.Chart) return;

    // Status Distribution Chart
    const ctxStatus = document.getElementById("statusChart");
    if (ctxStatus) {
      if (state.charts.statusDist) state.charts.statusDist.destroy();
      
      const counts = [state.counts.open, state.counts.in_progress, state.counts.resolved, state.counts.closed];
      const hasData = counts.some(c => c > 0);
      
      state.charts.statusDist = new Chart(ctxStatus, {
        type: 'doughnut',
        data: {
          labels: ['Open', 'Diproses', 'Resolved', 'Closed'],
          datasets: [{
            data: hasData ? counts : [1, 1, 1, 1],
            backgroundColor: ['#eab308', '#6366f1', '#14b8a6', '#94a3b8'],
            borderWidth: 0,
            hoverOffset: 4
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          cutout: '70%',
          plugins: {
            legend: { position: 'bottom' },
            tooltip: {
              callbacks: {
                label: function(context) {
                  if (!hasData) return " No data yet";
                  return ` ${context.label}: ${context.raw}`;
                }
              }
            }
          }
        }
      });
    }

    // Tickets Over Time Chart (Real End-to-End)
    const ctxTime = document.getElementById("ticketsTimeChart");
    if (ctxTime) {
      if (state.charts.ticketsTime) state.charts.ticketsTime.destroy();
      
      const labels = [];
      const countsPerDay = [0, 0, 0, 0, 0, 0, 0];
      const dateKeys = []; // formats to easily compare like YYYY-MM-DD
      const now = new Date();

      for (let i = 6; i >= 0; i--) {
        const d = new Date();
        d.setDate(now.getDate() - i);
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        dateKeys.push(`${year}-${month}-${day}`);

        if (i === 0) {
          labels.push('Hari ini');
        } else if (i === 1) {
          labels.push('Kemarin');
        } else {
          labels.push(`${i} Hari lalu`);
        }
      }

      // Aggregate state.recentItems by date key
      const items = state.recentItems || [];
      items.forEach(item => {
        if (!item.created_at) return;
        const date = new Date(item.created_at);
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const key = `${year}-${month}-${day}`;

        const index = dateKeys.indexOf(key);
        if (index !== -1) {
          countsPerDay[index]++;
        }
      });
      
      state.charts.ticketsTime = new Chart(ctxTime, {
        type: 'bar',
        data: {
          labels: labels,
          datasets: [{
            label: 'Tiket Baru',
            data: countsPerDay,
            backgroundColor: 'rgba(99, 102, 241, 0.8)',
            borderRadius: 4,
          }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: {
            legend: { display: false }
          },
          scales: {
            y: { 
              beginAtZero: true, 
              ticks: {
                precision: 0
              },
              grid: { color: 'rgba(0,0,0,0.05)' } 
            },
            x: { grid: { display: false } }
          }
        }
      });
    }
  }

  function renderCounts() {
    animateCounter(els.totalCount, state.counts.all);
    animateCounter(els.openCount, state.counts.open);
    animateCounter(els.progressCount, state.counts.in_progress);
    animateCounter(els.resolvedCount, state.counts.resolved);
    animateCounter(els.closedCount, state.counts.closed);
    document.querySelectorAll("[data-summary-status]").forEach((card) => {
      const active = card.dataset.summaryStatus === els.statusFilter.value;
      card.classList.toggle("summary-active", active);
    });
  }

  function renderTable() {
    const query = normalize(els.searchInput.value);
    const visibleItems = state.items.filter((item) => {
      if (!query) return true;
      return [item.reference_code, item.title, item.message, item.user_id, item.platform].some(
        (v) => normalize(v).includes(query),
      );
    });
    els.emptyState.classList.toggle("hidden", visibleItems.length > 0);
    els.submissionsTable.innerHTML = visibleItems
      .map((item) => {
        const title =
          item.category === "review"
            ? `${item.rating || "-"} / 5 - Review pengguna`
            : item.title || "Report tanpa judul";
        const isSelected = item.id === state.selectedId;
        return `
        <tr class="${isSelected ? "row-selected" : ""}">
          <td>
            <p class="mono text-xs font-semibold text-brand">${escapeHtml(item.reference_code)}</p>
            <p class="truncate text-sm font-semibold" style="margin-top:4px;max-width:400px">${escapeHtml(title)}</p>
            <p class="truncate text-xs text-muted" style="margin-top:4px;max-width:400px">${escapeHtml(item.message)}</p>
          </td>
          <td>${categoryBadge(item)}</td>
          <td><span class="badge ${STATUS_BADGE_CLASS[item.status] || "badge-slate"}">${escapeHtml(STATUS_LABELS[item.status] || item.status)}</span></td>
          <td class="text-xs text-muted">
            ${item.user_id ? `<span class="mono">${escapeHtml(shortId(item.user_id))}</span>` : "Guest"}
          </td>
          <td class="text-xs text-muted">${escapeHtml(formatDate(item.created_at))}</td>
          <td style="text-align:right">
            <button type="button" data-select-submission="${escapeHtml(item.id)}" class="btn btn-secondary" style="height:36px">
              <i data-lucide="panel-right-open"></i>
              <span>Detail</span>
            </button>
          </td>
        </tr>
      `;
      })
      .join("");
    lucide.createIcons();
  }

  function renderPagination() {
    const pages = totalPages();
    els.paginationSummary.textContent = `${state.pagination.total} submission - halaman ${state.pagination.page} dari ${pages}`;
    els.prevPageBtn.disabled = state.loading.list || state.pagination.page <= 1;
    els.nextPageBtn.disabled = state.loading.list || state.pagination.page >= pages;
  }

  function renderDetail() {
    const item = selectedSubmission();
    els.detailEmpty.classList.toggle("hidden", Boolean(item));
    els.workflowForm.classList.toggle("hidden", !item);
    if (!item) {
      els.detailReference.textContent = "Pilih submission";
      els.detailStatus.textContent = "-";
      els.detailStatus.className = "badge badge-slate";
      els.detailMeta.textContent = "Data lengkap akan tampil di sini.";
      return;
    }

    els.detailReference.textContent = item.reference_code;
    els.detailStatus.textContent = STATUS_LABELS[item.status] || item.status;
    els.detailStatus.className = `badge ${STATUS_BADGE_CLASS[item.status] || "badge-slate"}`;
    els.detailMeta.textContent = `${item.category === "review" ? "Review" : "Report"} - ${formatDate(item.created_at)}`;
    els.workflowStatusField.value = item.status;
    els.adminNoteField.value = item.admin_note || "";

    const contextEntries = Object.entries(item.client_context || {});
    els.detailContent.innerHTML = `
      <section>
        <p class="text-xs font-semibold uppercase tracking text-muted">Pesan pengguna</p>
        ${item.title ? `<h3 class="text-base font-semibold" style="margin-top:8px">${escapeHtml(item.title)}</h3>` : ""}
        ${item.rating ? `<div class="flex items-center gap-1" style="margin-top:8px;color:var(--accent-yellow)">${ratingStars(item.rating)}<span class="text-xs font-semibold text-muted" style="margin-left:4px">${item.rating}/5</span></div>` : ""}
        <p style="margin-top:12px;white-space:pre-wrap;word-break:break-word;padding:12px;border-radius:var(--radius-md);border:1px solid var(--line-light);background:var(--white);font-size:0.8125rem;line-height:1.625">${escapeHtml(item.message)}</p>
      </section>
      <section>
        <p class="text-xs font-semibold uppercase tracking text-muted">Identitas dan perangkat</p>
        <dl class="space-y-2" style="margin-top:8px">
          ${detailRow("Pengirim", item.user_id || "Guest", Boolean(item.user_id))}
          ${detailRow("Platform", item.platform || "-")}
          ${detailRow("Versi", appVersion(item))}
          ${detailRow("Locale", item.locale || "-")}
          ${detailRow("Diperbarui", formatDate(item.updated_at))}
        </dl>
      </section>
      <section>
        <p class="text-xs font-semibold uppercase tracking text-muted">Client context</p>
        ${
          contextEntries.length
            ? `<dl class="space-y-2" style="margin-top:8px;padding:12px;border-radius:var(--radius-md);border:1px solid var(--line-light);background:var(--surface)">${contextEntries.map(([key, value]) => detailRow(key, String(value))).join("")}</dl>`
            : `<div style="margin-top:8px;padding:12px;border-radius:var(--radius-md);border:1px solid var(--line-light);background:var(--surface)"><p class="text-sm text-muted">Tidak ada metadata tambahan.</p></div>`
        }
      </section>
    `;
    lucide.createIcons();
  }

  /* ── Loading ────────────────────────────────────────────────────────── */
  function syncLoading() {
    setButtonLoading(els.reloadBtn, state.loading.list, "Memuat...", "Reload");
    setButtonLoading(els.saveWorkflowBtn, state.loading.save, "Menyimpan...", "Simpan perubahan");
    renderPagination();
  }

  function setLoading(key, value) {
    state.loading[key] = value;
    syncLoading();
  }

  /* ── Helpers ────────────────────────────────────────────────────────── */
  function selectedSubmission() {
    return state.items.find((item) => item.id === state.selectedId) || null;
  }

  function totalPages() {
    return Math.max(1, Math.ceil(state.pagination.total / state.pagination.perPage));
  }

  function categoryBadge(item) {
    if (item.category === "review") {
      return `<span class="badge badge-orange"><i data-lucide="star" style="width:14px;height:14px"></i>Review</span>`;
    }
    return `<span class="badge badge-red"><i data-lucide="bug" style="width:14px;height:14px"></i>Report</span>`;
  }

  function ratingStars(rating) {
    return Array.from(
      { length: 5 },
      (_, i) =>
        `<i data-lucide="star" style="width:16px;height:16px;${i < rating ? "fill:currentColor" : "color:var(--line)"}"></i>`,
    ).join("");
  }

  function appVersion(item) {
    if (!item.app_version && !item.app_build) return "-";
    return `${item.app_version || "-"}${item.app_build ? ` (${item.app_build})` : ""}`;
  }

  function shortId(value) {
    const text = String(value || "");
    return text.length > 15 ? `${text.slice(0, 8)}...${text.slice(-4)}` : text;
  }
})();
