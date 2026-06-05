(function () {
  "use strict";

  TonztoonAdmin.mountShell();

  const STATUS_LABELS = {
    open: "Open",
    in_progress: "Diproses",
    resolved: "Resolved",
    closed: "Closed",
  };
  const STATUS_CLASSES = {
    open: "bg-amber-50 text-amber-700",
    in_progress: "bg-blue-50 text-blue-700",
    resolved: "bg-emerald-50 text-emerald-700",
    closed: "bg-slate-100 text-slate-700",
  };
  const state = {
    apiBase: "http://127.0.0.1:8000",
    token: "",
    items: [],
    selectedId: null,
    pagination: { page: 1, perPage: 50, total: 0 },
    counts: { all: 0, open: 0, in_progress: 0, resolved: 0, closed: 0 },
    loading: { list: false, save: false },
  };
  const els = {
    apiBaseLabel: document.querySelector("#apiBaseLabel"),
    reloadBtn: document.querySelector("#reloadBtn"),
    logoutBtn: document.querySelector("#logoutBtn"),
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
  const notify = TonztoonAdmin.notify;
  const setButtonLoading = TonztoonAdmin.setButtonLoading;

  const hasSession = adminSession.restoreSession();
  bindEvents();
  lucide.createIcons();
  if (hasSession) {
    els.apiBaseLabel.textContent = state.apiBase;
    loadDashboard();
  }

  function bindEvents() {
    els.logoutBtn.addEventListener("click", logout);
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
      if (els.categoryFilter.value)
        params.set("category", els.categoryFilter.value);
      if (els.statusFilter.value) params.set("status", els.statusFilter.value);
      const payload = await apiFetch(`/api/v1/helpdesk/submissions?${params}`);
      state.items = payload.items || [];
      state.pagination.total = Number(payload.total || 0);
      state.pagination.page = Number(payload.page || state.pagination.page);
      state.pagination.perPage = Number(
        payload.per_page || state.pagination.perPage,
      );
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
          apiFetch(
            `/api/v1/helpdesk/submissions?page=1&per_page=1&status=${status}`,
          ),
        ),
      ]);
      state.counts.all = Number(allPayload.total || 0);
      statuses.forEach((status, index) => {
        state.counts[status] = Number(statusPayloads[index].total || 0);
      });
      renderCounts();
    } catch (error) {
      handleRequestError(error);
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
      const updated = await apiFetch(
        `/api/v1/helpdesk/submissions/${selected.id}`,
        {
          method: "PATCH",
          body: {
            status: els.workflowStatusField.value,
            admin_note: els.adminNoteField.value.trim() || null,
          },
        },
      );
      state.items = state.items.map((item) =>
        item.id === updated.id ? updated : item,
      );
      render();
      await loadCounts();
      notify(`Submission ${updated.reference_code} diperbarui.`);
    } catch (error) {
      handleRequestError(error);
    } finally {
      setLoading("save", false);
    }
  }

  function render() {
    renderCounts();
    renderTable();
    renderPagination();
    renderDetail();
    syncLoading();
    lucide.createIcons();
  }

  function renderCounts() {
    els.totalCount.textContent = state.counts.all;
    els.openCount.textContent = state.counts.open;
    els.progressCount.textContent = state.counts.in_progress;
    els.resolvedCount.textContent = state.counts.resolved;
    els.closedCount.textContent = state.counts.closed;
    document.querySelectorAll("[data-summary-status]").forEach((card) => {
      const active = card.dataset.summaryStatus === els.statusFilter.value;
      card.classList.toggle("border-brand/30", active);
      card.classList.toggle("ring-2", active);
      card.classList.toggle("ring-brand/10", active);
    });
  }

  function renderTable() {
    const query = normalize(els.searchInput.value);
    const visibleItems = state.items.filter((item) => {
      if (!query) return true;
      return [
        item.reference_code,
        item.title,
        item.message,
        item.user_id,
        item.platform,
      ].some((value) => normalize(value).includes(query));
    });
    els.emptyState.classList.toggle("hidden", visibleItems.length > 0);
    els.submissionsTable.innerHTML = visibleItems
      .map((item) => {
        const title =
          item.category === "review"
            ? `${item.rating || "-"} / 5 - Review pengguna`
            : item.title || "Report tanpa judul";
        return `
            <tr class="submission-row" data-selected="${item.id === state.selectedId}">
              <td class="px-4 py-3">
                <p class="font-mono text-xs font-semibold text-brand">${escapeHtml(item.reference_code)}</p>
                <p class="mt-1 max-w-md truncate text-sm font-semibold text-ink">${escapeHtml(title)}</p>
                <p class="mt-1 max-w-md truncate text-xs text-muted">${escapeHtml(item.message)}</p>
              </td>
              <td class="px-4 py-3">${categoryBadge(item)}</td>
              <td class="px-4 py-3">${statusBadge(item.status)}</td>
              <td class="px-4 py-3 text-xs text-muted">
                ${item.user_id ? `<span class="font-mono">${escapeHtml(shortId(item.user_id))}</span>` : "Guest"}
              </td>
              <td class="px-4 py-3 text-xs text-muted">${escapeHtml(formatDate(item.created_at))}</td>
              <td class="px-4 py-3 text-right">
                <button type="button" data-select-submission="${escapeHtml(item.id)}" class="inline-flex h-9 items-center gap-2 rounded-2xl border border-line bg-white px-3 text-xs font-semibold text-ink hover:bg-slate-50">
                  <i data-lucide="panel-right-open" class="h-4 w-4"></i>
                  Detail
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
    els.nextPageBtn.disabled =
      state.loading.list || state.pagination.page >= pages;
  }

  function renderDetail() {
    const item = selectedSubmission();
    els.detailEmpty.classList.toggle("hidden", Boolean(item));
    els.workflowForm.classList.toggle("hidden", !item);
    if (!item) {
      els.detailReference.textContent = "Pilih submission";
      els.detailStatus.textContent = "-";
      els.detailStatus.className =
        "shrink-0 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700";
      els.detailMeta.textContent = "Data lengkap akan tampil di sini.";
      return;
    }

    els.detailReference.textContent = item.reference_code;
    els.detailStatus.textContent = STATUS_LABELS[item.status] || item.status;
    els.detailStatus.className = `shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold ${STATUS_CLASSES[item.status] || "bg-slate-100 text-slate-700"}`;
    els.detailMeta.textContent = `${item.category === "review" ? "Review" : "Report"} - ${formatDate(item.created_at)}`;
    els.workflowStatusField.value = item.status;
    els.adminNoteField.value = item.admin_note || "";

    const contextEntries = Object.entries(item.client_context || {});
    els.detailContent.innerHTML = `
          <section>
            <p class="text-xs font-semibold uppercase tracking-wide text-muted">Pesan pengguna</p>
            ${item.title ? `<h3 class="mt-2 text-base font-semibold text-ink">${escapeHtml(item.title)}</h3>` : ""}
            ${item.rating ? `<div class="mt-2 flex items-center gap-1 text-amber-500">${ratingStars(item.rating)}<span class="ml-1 text-xs font-semibold text-muted">${item.rating}/5</span></div>` : ""}
            <p class="mt-3 whitespace-pre-wrap break-words rounded-2xl border border-line bg-white/80 p-3 text-sm leading-6 text-ink">${escapeHtml(item.message)}</p>
          </section>
          <section>
            <p class="text-xs font-semibold uppercase tracking-wide text-muted">Identitas dan perangkat</p>
            <dl class="mt-2 space-y-2 text-sm">
              ${detailRow("Pengirim", item.user_id || "Guest", Boolean(item.user_id))}
              ${detailRow("Platform", item.platform || "-")}
              ${detailRow("Versi", appVersion(item))}
              ${detailRow("Locale", item.locale || "-")}
              ${detailRow("Diperbarui", formatDate(item.updated_at))}
            </dl>
          </section>
          <section>
            <p class="text-xs font-semibold uppercase tracking-wide text-muted">Client context</p>
            ${
              contextEntries.length
                ? `<dl class="mt-2 rounded-2xl border border-line bg-slate-50 p-3">${contextEntries.map(([key, value]) => detailRow(key, String(value))).join("")}</dl>`
                : `<div class="mt-2 rounded-2xl border border-line bg-slate-50 p-3"><p class="text-sm text-muted">Tidak ada metadata tambahan.</p></div>`
            }
          </section>
        `;
    lucide.createIcons();
  }

  function syncLoading() {
    setButtonLoading(els.reloadBtn, state.loading.list, "Memuat...", "Reload");
    setButtonLoading(
      els.saveWorkflowBtn,
      state.loading.save,
      "Menyimpan...",
      "Simpan perubahan",
    );
    renderPagination();
  }

  function setLoading(key, value) {
    state.loading[key] = value;
    syncLoading();
  }

  function selectedSubmission() {
    return state.items.find((item) => item.id === state.selectedId) || null;
  }

  function totalPages() {
    return Math.max(
      1,
      Math.ceil(state.pagination.total / state.pagination.perPage),
    );
  }

  function statusBadge(status) {
    return `<span class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${STATUS_CLASSES[status] || "bg-slate-100 text-slate-700"}">${escapeHtml(STATUS_LABELS[status] || status)}</span>`;
  }

  function categoryBadge(item) {
    if (item.category === "review") {
      return `<span class="inline-flex items-center gap-1 rounded-full bg-orange-50 px-2.5 py-1 text-xs font-semibold text-orange-700"><i data-lucide="star" class="h-3.5 w-3.5"></i>Review</span>`;
    }
    return `<span class="inline-flex items-center gap-1 rounded-full bg-red-50 px-2.5 py-1 text-xs font-semibold text-red-700"><i data-lucide="bug" class="h-3.5 w-3.5"></i>Report</span>`;
  }

  function ratingStars(rating) {
    return Array.from(
      { length: 5 },
      (_, index) =>
        `<i data-lucide="star" class="h-4 w-4 ${index < rating ? "fill-current" : "text-slate-300"}"></i>`,
    ).join("");
  }

  function detailRow(label, value, mono = false) {
    return `
          <div class="flex items-start justify-between gap-4 border-b border-line pb-2 last:border-b-0">
            <dt class="text-muted">${escapeHtml(label)}</dt>
            <dd class="min-w-0 break-all text-right ${mono ? "font-mono text-xs" : "text-sm"} text-ink">${escapeHtml(value)}</dd>
          </div>
        `;
  }

  function appVersion(item) {
    if (!item.app_version && !item.app_build) return "-";
    return `${item.app_version || "-"}${item.app_build ? ` (${item.app_build})` : ""}`;
  }

  function formatDate(value) {
    if (!value) return "-";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);
    return new Intl.DateTimeFormat("id-ID", {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(date);
  }

  function shortId(value) {
    const text = String(value || "");
    return text.length > 15 ? `${text.slice(0, 8)}...${text.slice(-4)}` : text;
  }

  function normalize(value) {
    return String(value || "").toLowerCase();
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }
})();
