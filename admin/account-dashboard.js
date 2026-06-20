(function () {
  "use strict";

  TonztoonAdmin.mountShell();

  const escapeHtml = TonztoonAdmin.escapeHtml;
  const formatDate = TonztoonAdmin.formatDate;
  const normalize = TonztoonAdmin.normalize;
  const blankPanel = TonztoonAdmin.blankPanel;
  const detailRow = TonztoonAdmin.detailRow;
  const notify = TonztoonAdmin.notify;
  const setButtonLoading = TonztoonAdmin.setButtonLoading;
  const togglePassword = TonztoonAdmin.togglePassword;
  const animateCounter = TonztoonAdmin.animateCounter;

  const state = {
    apiBase: TonztoonAdmin.DEFAULT_API_BASE || "http://127.0.0.1:8000",
    token: "",
    currentUserId: null,
    users: [],
    selectedUserId: null,
    currentPanel: "profile",
    relationView: "list",
    selectedRelationKey: null,
    pendingDeleteUserId: null,
    relationPreview: null,
    relationRequestId: 0,
    hasLoadedAccounts: false,
    pagination: { page: 1, perPage: 50, total: 0 },
    loading: {
      accounts: false,
      save: false,
      delete: false,
      relations: false,
      announcement: false,
    }
  };

  const els = {
    apiBaseLabel: document.querySelector("#apiBaseLabel"),
    reloadBtn: document.querySelector("#reloadBtn"),
    openCreateBtn: document.querySelector("#openCreateBtn"),
    announcementForm: document.querySelector("#announcementForm"),
    sendAnnouncementBtn: document.querySelector("#sendAnnouncementBtn"),
    announcementTitleField: document.querySelector("#announcementTitleField"),
    announcementCategoryField: document.querySelector("#announcementCategoryField"),
    announcementMessageField: document.querySelector("#announcementMessageField"),
    announcementRouteField: document.querySelector("#announcementRouteField"),
    usersTable: document.querySelector("#usersTable"),
    emptyState: document.querySelector("#emptyState"),
    totalUsers: document.querySelector("#totalUsers"),
    activeUsers: document.querySelector("#activeUsers"),
    relationCount: document.querySelector("#relationCount"),
    pageSizeSelect: document.querySelector("#pageSizeSelect"),
    prevPageBtn: document.querySelector("#prevPageBtn"),
    nextPageBtn: document.querySelector("#nextPageBtn"),
    paginationSummary: document.querySelector("#paginationSummary"),
    searchInput: document.querySelector("#searchInput"),
    roleFilter: document.querySelector("#roleFilter"),
    statusFilter: document.querySelector("#statusFilter"),
    detailName: document.querySelector("#detailName"),
    detailEmail: document.querySelector("#detailEmail"),
    detailStatus: document.querySelector("#detailStatus"),
    profilePanel: document.querySelector("#profilePanel"),
    relationsPanel: document.querySelector("#relationsPanel"),
    relationTableWorkspace: document.querySelector("#relationTableWorkspace"),
    relationDiagramWorkspace: document.querySelector("#relationDiagramWorkspace"),
    metadataPanel: document.querySelector("#metadataPanel"),
    userModal: document.querySelector("#userModal"),
    deleteModal: document.querySelector("#deleteModal"),
    userForm: document.querySelector("#userForm"),
    saveUserBtn: document.querySelector("#saveUserBtn"),
    modalTitle: document.querySelector("#modalTitle"),
    editingUserId: document.querySelector("#editingUserId"),
    emailField: document.querySelector("#emailField"),
    passwordField: document.querySelector("#passwordField"),
    displayNameField: document.querySelector("#displayNameField"),
    usernameField: document.querySelector("#usernameField"),
    accountRoleField: document.querySelector("#accountRoleField"),
    accountStatusField: document.querySelector("#accountStatusField"),
    avatarUrlField: document.querySelector("#avatarUrlField"),
    onboardingField: document.querySelector("#onboardingField"),
    roleWarning: document.querySelector("#roleWarning"),
    confirmCascade: document.querySelector("#confirmCascade"),
    confirmDeleteBtn: document.querySelector("#confirmDeleteBtn"),
    deleteMessage: document.querySelector("#deleteMessage"),
    deleteRelations: document.querySelector("#deleteRelations"),
  };

  const adminSession = TonztoonAdmin.createFeatureSession({
    state,
    onTokenChanged: (token) => {
      state.currentUserId = TonztoonAdmin.userIdFromToken(token);
    },
    onLogout: () => {
      state.currentUserId = null;
      state.users = [];
      state.selectedUserId = null;
      state.selectedRelationKey = null;
      state.hasLoadedAccounts = false;
    },
  });
  const apiFetch = adminSession.apiFetch;
  const handleRequestError = (error) =>
    adminSession.handleRequestError(error, "Akun ini tidak memiliki akses account manager.");
  const logout = adminSession.logout;

  const hasSession = adminSession.restoreSession();
  bindEvents();
  initCustomSelects();
  lucide.createIcons();
  if (hasSession) {
    els.apiBaseLabel.textContent = state.apiBase;
    loadAccounts();
  }

  function bindEvents() {
    /* Sidebar logout */
    document.addEventListener("click", (event) => {
      const sidebarAction = event.target.closest("[data-sidebar-action]");
      if (sidebarAction?.dataset.sidebarAction === "logout") logout();
    });

    els.reloadBtn.addEventListener("click", () => loadAccounts());
    els.openCreateBtn.addEventListener("click", openCreateModal);
    els.announcementForm.addEventListener("submit", sendAnnouncement);
    els.userForm.addEventListener("submit", saveUser);
    els.confirmCascade.addEventListener("change", () => syncLoadingState());
    els.confirmDeleteBtn.addEventListener("click", deleteUser);
    els.pageSizeSelect.addEventListener("change", () => {
      state.pagination.perPage = Number(els.pageSizeSelect.value);
      state.pagination.page = 1;
      loadAccounts();
    });
    els.prevPageBtn.addEventListener("click", () => {
      if (state.pagination.page <= 1) return;
      state.pagination.page -= 1;
      loadAccounts();
    });
    els.nextPageBtn.addEventListener("click", () => {
      if (state.pagination.page >= totalPages()) return;
      state.pagination.page += 1;
      loadAccounts();
    });
    els.accountRoleField.addEventListener("change", updateRoleWarning);
    els.accountStatusField.addEventListener("change", updateRoleWarning);

    [els.searchInput, els.roleFilter, els.statusFilter].forEach((input) => {
      input.addEventListener("input", renderUsers);
      input.addEventListener("change", renderUsers);
    });

    document.addEventListener("click", (event) => {
      const closeTarget = event.target.closest("[data-close-modal]");
      if (closeTarget) closeModal(closeTarget.dataset.closeModal);

      const diagramToggleBtn = event.target.closest("[data-open-diagram-for-relation]");
      if (diagramToggleBtn) {
        state.relationView = "diagram";
        setPanel("relations");
        setTimeout(() => {
          els.relationDiagramWorkspace.scrollIntoView({ behavior: "smooth", block: "start" });
        }, 80);
        return;
      }

      const panelTabTarget = event.target.closest("[data-panel-tab]");
      if (panelTabTarget) setPanel(panelTabTarget.dataset.panelTab);

      const actionTarget = event.target.closest("[data-action]");
      if (actionTarget) {
        const { action, userId } = actionTarget.dataset;
        if (action === "select") selectUser(userId);
        if (action === "edit") openEditModal(userId);
        if (action === "delete") openDeleteModal(userId);
      }

      const viewTarget = event.target.closest("[data-relation-view]");
      if (viewTarget) {
        state.relationView = viewTarget.dataset.relationView;
        renderRelationsPanel();
      }

      const relationTarget = event.target.closest("[data-relation-key]");
      if (relationTarget) selectRelation(relationTarget.dataset.relationKey);

      const jumpTarget = event.target.closest("[data-relation-jump]");
      if (jumpTarget) {
        document
          .querySelector(`#relation-${jumpTarget.dataset.relationJump}`)
          ?.scrollIntoView({ behavior: "smooth", block: "nearest" });
      }

      const diagramTarget = event.target.closest("[data-scroll-diagram]");
      if (diagramTarget) {
        els.relationDiagramWorkspace.scrollIntoView({ behavior: "smooth", block: "start" });
      }

      const toggleTarget = event.target.closest("[data-toggle-password]");
      if (toggleTarget) togglePassword(toggleTarget);

      if (!event.target.closest(".custom-select")) closeCustomSelects();
    });

    document.addEventListener("keydown", (event) => {
      if (event.key !== "Escape") return;
      closeCustomSelects();
      closeModal("userModal");
      closeModal("deleteModal");
    });
  }

  /* ── Custom Select ──────────────────────────────────────────────────── */
  function initCustomSelects() {
    document.querySelectorAll("select").forEach((select) => {
      if (select.dataset.customSelectReady === "true") return;
      select.dataset.customSelectReady = "true";
      select.classList.add("hidden");

      const wrapper = document.createElement("div");
      wrapper.className = select.classList.contains("w-full") || select.style.width !== "auto"
        ? "custom-select w-full"
        : "custom-select";
      if (select.style.width === "auto") {
        wrapper.style.minWidth = "130px";
        wrapper.style.width = "auto";
      }
      wrapper.dataset.open = "false";

      const button = document.createElement("button");
      button.type = "button";
      button.className = "custom-select-trigger";
      button.innerHTML = `
        <span class="custom-select-label truncate"></span>
        <i data-lucide="chevron-down" style="width:16px;height:16px;flex-shrink:0;color:var(--muted)"></i>
      `;

      const menu = document.createElement("div");
      menu.className = "custom-select-menu scrollbar-thin";
      Array.from(select.options).forEach((option) => {
        const optionButton = document.createElement("button");
        optionButton.type = "button";
        optionButton.dataset.value = option.value;
        optionButton.className = "custom-select-option";
        optionButton.innerHTML = `
          <span class="truncate">${escapeHtml(option.textContent)}</span>
          <i data-lucide="check" class="hidden" style="width:16px;height:16px;flex-shrink:0"></i>
        `;
        optionButton.addEventListener("click", () => {
          select.value = option.value;
          syncCustomSelect(select);
          closeCustomSelects();
          select.dispatchEvent(new Event("input", { bubbles: true }));
          select.dispatchEvent(new Event("change", { bubbles: true }));
        });
        menu.appendChild(optionButton);
      });

      button.addEventListener("click", () => {
        const willOpen = wrapper.dataset.open !== "true";
        closeCustomSelects(wrapper);
        wrapper.dataset.open = String(willOpen);
      });

      wrapper.append(button, menu);
      select.after(wrapper);
      syncCustomSelect(select);
    });
    lucide.createIcons();
  }

  function syncCustomSelect(select) {
    const wrapper = select.nextElementSibling?.classList.contains("custom-select")
      ? select.nextElementSibling
      : null;
    if (!wrapper) return;
    const selected = select.options[select.selectedIndex];
    wrapper.querySelector(".custom-select-label").textContent = selected?.textContent || "";
    wrapper.querySelectorAll(".custom-select-option").forEach((optBtn) => {
      const active = optBtn.dataset.value === select.value;
      optBtn.classList.toggle("opt-active", active);
      optBtn.querySelector("svg, i")?.classList.toggle("hidden", !active);
    });
  }

  function syncCustomSelects() {
    document.querySelectorAll("select[data-custom-select-ready='true']").forEach(syncCustomSelect);
  }

  function closeCustomSelects(except = null) {
    document.querySelectorAll(".custom-select").forEach((wrapper) => {
      if (wrapper !== except) wrapper.dataset.open = "false";
    });
  }

  /* ── Data Loading ───────────────────────────────────────────────────── */
  async function loadAccounts() {
    if (state.loading.accounts) return false;
    setLoading("accounts", true);
    try {
      const { page, perPage } = state.pagination;
      const payload = await apiFetch(
        `/api/v1/account-manager/accounts?page=${page}&per_page=${perPage}`,
      );
      state.users = payload.users || [];
      state.pagination.total = Number(payload.total || state.users.length);
      state.pagination.page = Number(payload.page || page);
      state.pagination.perPage = Number(payload.per_page || perPage);
      if (!state.users.length && state.pagination.page > totalPages()) {
        state.pagination.page = totalPages();
        state.loading.accounts = false;
        return await loadAccounts();
      }
      if (!state.users.some((user) => user.id === state.selectedUserId)) {
        state.selectedUserId = state.users[0]?.id || null;
      }
      state.relationPreview = null;
      state.selectedRelationKey = null;
      state.hasLoadedAccounts = true;
      render();
      return true;
    } catch (error) {
      handleRequestError(error);
      return false;
    } finally {
      setLoading("accounts", false);
    }
  }

  async function selectUser(userId) {
    state.selectedUserId = userId;
    state.relationPreview = null;
    state.selectedRelationKey = null;
    render();
    if (state.currentPanel === "relations") await loadRelations(userId);
  }

  async function loadRelations(userId) {
    if (!userId) return;
    const requestId = ++state.relationRequestId;
    setLoading("relations", true);
    try {
      const preview = await apiFetch(
        `/api/v1/account-manager/accounts/${userId}/relations`,
      );
      if (requestId !== state.relationRequestId || userId !== state.selectedUserId) return;
      state.relationPreview = preview;
      renderRelationsPanel();
    } catch (error) {
      if (requestId === state.relationRequestId) handleRequestError(error);
    } finally {
      if (requestId === state.relationRequestId) setLoading("relations", false);
    }
  }

  async function sendAnnouncement(event) {
    event.preventDefault();
    if (state.loading.announcement) return;

    const route = els.announcementRouteField.value.trim() || "/notifications";
    if (!route.startsWith("/")) {
      notify("Route harus diawali '/'.", true);
      return;
    }

    setLoading("announcement", true);
    try {
      const payload = await apiFetch("/api/v1/notifications/admin-announcements", {
        method: "POST",
        body: {
          title: els.announcementTitleField.value.trim(),
          message: els.announcementMessageField.value.trim(),
          category: els.announcementCategoryField.value,
          action_route: route,
        },
      });
      notify(
        `Push terkirim ke ${payload.queued_messages || 0}/${payload.target_devices || 0} device aktif.`,
      );
      els.announcementMessageField.value = "";
    } catch (error) {
      handleRequestError(error);
    } finally {
      setLoading("announcement", false);
    }
  }

  /* ── Render ─────────────────────────────────────────────────────────── */
  function render() {
    renderStats();
    renderUsers();
    renderPagination();
    renderDetail();
    lucide.createIcons();
    syncLoadingState();
  }


  function renderStats() {
    const totalVal = state.pagination.total || state.users.length;
    const activeVal = state.users.filter((u) => u.account_status === "active").length;
    const relVal = state.users.reduce((sum, u) => sum + (u.relation_total || 0), 0);
    animateCounter(els.totalUsers, totalVal);
    animateCounter(els.activeUsers, activeVal);
    animateCounter(els.relationCount, relVal);
  }

  function renderPagination() {
    const page = state.pagination.page;
    const pages = totalPages();
    const total = state.pagination.total || state.users.length;
    const start = total ? (page - 1) * state.pagination.perPage + 1 : 0;
    const end = Math.min(page * state.pagination.perPage, total);
    els.paginationSummary.textContent = `${start}-${end} dari ${total} akun | halaman ${page}/${pages}`;
    els.pageSizeSelect.value = String(state.pagination.perPage);
    syncCustomSelect(els.pageSizeSelect);
    els.prevPageBtn.disabled = page <= 1 || state.loading.accounts;
    els.nextPageBtn.disabled = page >= pages || state.loading.accounts;
  }

  function totalPages() {
    return Math.max(
      1,
      Math.ceil((state.pagination.total || state.users.length || 0) / state.pagination.perPage),
    );
  }

  function filteredUsers() {
    const query = normalize(els.searchInput.value);
    const role = els.roleFilter.value;
    const status = els.statusFilter.value;
    return state.users.filter((user) => {
      const name = user.profile?.display_name || user.user_metadata?.display_name || "";
      const matchesQuery = [name, user.email, user.id, user.profile?.username].some(
        (v) => normalize(v).includes(query),
      );
      const matchesRole = role === "all" || user.account_role === role;
      const matchesStatus = status === "all" || user.account_status === status;
      return matchesQuery && matchesRole && matchesStatus;
    });
  }

  function renderUsers() {
    const users = filteredUsers();
    els.usersTable.innerHTML = "";
    if (state.loading.accounts && !state.hasLoadedAccounts && !state.users.length) {
      els.emptyState.classList.add("hidden");
      els.usersTable.innerHTML = tableSkeletonRows();
      return;
    }
    els.emptyState.classList.toggle("hidden", users.length > 0);
    users.forEach((user) => {
      const name = displayName(user);
      const isSelf = user.id === state.currentUserId;
      const rawAvatar = user.profile?.avatar_url || user.user_metadata?.avatar_url;
      const avatarUrl = rawAvatar
        ? rawAvatar
        : `https://ui-avatars.com/api/?name=${encodeURIComponent(name || "User")}&background=random`;

      const row = document.createElement("tr");
      row.className = user.id === state.selectedUserId ? "row-selected" : "";
      row.innerHTML = `
        <td>
          <button type="button" data-action="select" data-user-id="${escapeHtml(user.id)}" class="flex items-center gap-3" style="text-align:left;background:none;border:none;cursor:pointer;padding:0;font-family:inherit">
            <img src="${escapeHtml(avatarUrl)}" alt="Avatar" class="avatar" />
            <div style="max-width:200px;min-width:0">
              <span class="block truncate text-sm font-semibold">${escapeHtml(name)}</span>
              <span class="block truncate text-xs text-muted">${escapeHtml(user.email || "-")}</span>
            </div>
          </button>
        </td>
        <td class="text-sm">${escapeHtml(user.profile?.username || "-")}</td>
        <td class="text-sm">${escapeHtml(roleLabel(user.account_role))}</td>
        <td><span class="badge ${statusBadgeClass(user.account_status)}">${escapeHtml(statusLabel(user.account_status))}</span></td>
        <td class="text-sm">${user.email_confirmed_at ? formatDate(user.email_confirmed_at) : "Belum"}</td>
        <td class="text-sm">${user.last_sign_in_at ? formatDate(user.last_sign_in_at) : "-"}</td>
        <td><span class="badge ${user.profile?.onboarding_completed ? "badge-green" : "badge-slate"}">${user.profile?.onboarding_completed ? "Selesai" : "Belum"}</span></td>
        <td class="text-sm">${user.relation_total || 0}</td>
        <td>
          <div class="flex justify-end gap-2">
            <button type="button" data-action="edit" data-user-id="${escapeHtml(user.id)}" class="btn-icon" title="Edit akun">
              <i data-lucide="pencil"></i>
            </button>
            <button type="button" ${isSelf ? "disabled" : ""} data-action="delete" data-user-id="${escapeHtml(user.id)}" class="btn-icon ${isSelf ? "" : "btn-icon-danger"}" title="${isSelf ? "Akun login aktif tidak bisa dihapus" : "Hapus akun"}">
              <i data-lucide="${isSelf ? "shield" : "trash-2"}"></i>
            </button>
          </div>
        </td>
      `;
      els.usersTable.appendChild(row);
    });
    lucide.createIcons();
  }

  function renderDetail() {
    const user = selectedUser();
    if (!user) {
      els.detailName.textContent = "Pilih akun";
      els.detailEmail.textContent = "Relasi muncul berdasarkan user ID.";
      els.detailStatus.textContent = "-";
      els.detailStatus.className = "badge badge-slate";
      els.profilePanel.innerHTML = blankPanel("Belum ada akun.");
      els.relationsPanel.innerHTML = "";
      hideRelationTableWorkspace();
      hideRelationDiagramWorkspace();
      els.metadataPanel.innerHTML = "";
      return;
    }
    els.detailName.textContent = displayName(user);
    els.detailEmail.textContent = user.email || "-";
    els.detailStatus.textContent = statusLabel(user.account_status);
    els.detailStatus.className = `badge ${statusBadgeClass(user.account_status)}`;

    els.profilePanel.innerHTML = `
      <dl class="space-y-3">
        ${detailRow("User ID", user.id, true)}
        ${detailRow("Auth role", user.role || "-")}
        ${detailRow("Account role", roleLabel(user.account_role))}
        ${detailRow("Username", user.profile?.username || "-")}
        ${detailRow("Display name", user.profile?.display_name || user.user_metadata?.display_name || "-")}
        ${detailRow("Email confirmed", user.email_confirmed_at ? formatDate(user.email_confirmed_at) : "Belum")}
        ${detailRow("Last sign in", user.last_sign_in_at ? formatDate(user.last_sign_in_at) : "-")}
        ${detailRow("Onboarding", user.profile?.onboarding_completed ? "Selesai" : "Belum")}
      </dl>
    `;
    els.metadataPanel.innerHTML = `
      <div>
        <p class="text-xs font-semibold uppercase tracking text-muted" style="margin-bottom:8px">App metadata</p>
        <pre class="code-block">${escapeHtml(JSON.stringify(user.app_metadata || {}, null, 2))}</pre>
      </div>
      <div>
        <p class="text-xs font-semibold uppercase tracking text-muted" style="margin-bottom:8px">User metadata</p>
        <pre class="code-block">${escapeHtml(JSON.stringify(user.user_metadata || {}, null, 2))}</pre>
      </div>
    `;
    setPanel(state.currentPanel);
  }

  function renderRelationsPanel() {
    const user = selectedUser();
    if (!user) return;
    const entries = relationEntries(user, state.relationPreview);
    ensureSelectedRelation(entries);
    const selectedEntry = selectedRelationEntry(entries);
    const total = entries.reduce((sum, e) => sum + e.count, 0);
    const activeTables = entries.filter((e) => e.count > 0).length;
    const sections =
      state.relationView === "diagram"
        ? renderDiagramPanelHint(entries)
        : renderRelationList(entries);
    els.relationsPanel.innerHTML = `
      <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:8px">
        ${relationMetric("Total", total)}
        ${relationMetric("Tabel aktif", activeTables)}
        ${relationMetric("Preview", state.relationPreview ? "Siap" : "Belum")}
      </div>
      <div class="flex items-center justify-between gap-2 flex-wrap">
        <div class="view-toggle">
          ${relationViewButton("list", "List", "list")}
          ${relationViewButton("diagram", "Diagram", "network")}
        </div>
        <button type="button" id="loadRelationsBtn" ${state.loading.relations ? "disabled" : ""} class="btn btn-secondary" style="height:36px">
          <i data-loading-icon data-lucide="${state.loading.relations ? "loader-2" : "database"}" class="${state.loading.relations ? "animate-spin" : ""}"></i>
          <span>${state.loading.relations ? "Memuat..." : state.relationPreview ? "Refresh preview" : "Muat preview"}</span>
        </button>
      </div>
      <div style="max-height:26rem;overflow-y:auto;padding-right:4px" class="scrollbar-thin">
        <div class="space-y-3">
          ${sections || blankPanel("Tidak ada relasi.")}
        </div>
      </div>
    `;
    renderRelationTableWorkspace(selectedEntry);
    renderRelationDiagramWorkspace(user, entries);
    document.querySelector("#loadRelationsBtn")?.addEventListener("click", () => loadRelations(user.id));
    lucide.createIcons();
  }

  function tableSkeletonRows() {
    return Array.from({ length: 4 })
      .map(
        () => `
        <tr>
          <td><div class="skeleton" style="height:40px;width:100%"></div></td>
          <td><div class="skeleton" style="height:24px;width:100%"></div></td>
          <td><div class="skeleton" style="height:24px;width:100%"></div></td>
          <td><div class="skeleton" style="height:24px;width:100%"></div></td>
          <td><div class="skeleton" style="height:24px;width:100%"></div></td>
          <td><div class="skeleton" style="height:24px;width:100%"></div></td>
          <td><div class="skeleton" style="height:24px;width:100%"></div></td>
          <td><div class="skeleton" style="height:24px;width:100%"></div></td>
          <td><div class="skeleton" style="height:36px;width:80px;margin-left:auto"></div></td>
        </tr>
      `,
      )
      .join("");
  }

  function renderRelationTableWorkspace(entry) {
    if (state.currentPanel !== "relations" || !entry) {
      hideRelationTableWorkspace();
      return;
    }
    els.relationTableWorkspace.classList.remove("hidden");
    els.relationTableWorkspace.innerHTML = renderSelectedRelationTable(entry);
    lucide.createIcons();
  }

  function hideRelationTableWorkspace() {
    els.relationTableWorkspace.classList.add("hidden");
    els.relationTableWorkspace.innerHTML = "";
  }

  function renderRelationDiagramWorkspace(user, entries) {
    if (state.currentPanel !== "relations" || state.relationView !== "diagram") {
      hideRelationDiagramWorkspace();
      return;
    }
    els.relationDiagramWorkspace.classList.remove("hidden");
    els.relationDiagramWorkspace.innerHTML = renderRelationDiagram(user, entries);
    lucide.createIcons();
    requestAnimationFrame(setupRelationDiagramInteractions);
  }

  function hideRelationDiagramWorkspace() {
    els.relationDiagramWorkspace.classList.add("hidden");
    els.relationDiagramWorkspace.innerHTML = "";
  }

  function setupRelationDiagramInteractions() {
    const viewport = els.relationDiagramWorkspace.querySelector("[data-relation-diagram-viewport]");
    const scene = els.relationDiagramWorkspace.querySelector("[data-relation-diagram-scene]");
    const zoomLabel = els.relationDiagramWorkspace.querySelector("[data-diagram-zoom-label]");
    if (!viewport || !scene) return;

    const sceneWidth = Number(scene.dataset.sceneWidth) || 1080;
    const sceneHeight = Number(scene.dataset.sceneHeight) || 600;
    const minScale = 0.3;
    const maxScale = 2.5;
    const transform = { x: 0, y: 0, scale: 1 };
    const pointers = new Map();
    let gesture = null;
    let gestureMoved = false;
    let suppressNextClick = false;

    const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

    function constrainPosition() {
      const visibleEdge = 72;
      const scaledWidth = sceneWidth * transform.scale;
      const scaledHeight = sceneHeight * transform.scale;
      transform.x = clamp(transform.x, visibleEdge - scaledWidth, viewport.clientWidth - visibleEdge);
      transform.y = clamp(transform.y, visibleEdge - scaledHeight, viewport.clientHeight - visibleEdge);
    }

    function applyTransform() {
      constrainPosition();
      scene.style.transform = `translate3d(${transform.x}px, ${transform.y}px, 0) scale(${transform.scale})`;
      if (zoomLabel) zoomLabel.textContent = `${Math.round(transform.scale * 100)}%`;
    }

    function zoomAt(nextScale, clientX, clientY) {
      const rect = viewport.getBoundingClientRect();
      const pointX = clientX - rect.left;
      const pointY = clientY - rect.top;
      const sceneX = (pointX - transform.x) / transform.scale;
      const sceneY = (pointY - transform.y) / transform.scale;
      transform.scale = clamp(nextScale, minScale, maxScale);
      transform.x = pointX - sceneX * transform.scale;
      transform.y = pointY - sceneY * transform.scale;
      applyTransform();
    }

    function zoomFromCenter(factor) {
      const rect = viewport.getBoundingClientRect();
      zoomAt(transform.scale * factor, rect.left + rect.width / 2, rect.top + rect.height / 2);
    }

    function fitDiagram() {
      const padding = viewport.clientWidth < 640 ? 24 : 32;
      const availableWidth = Math.max(viewport.clientWidth - padding * 2, 1);
      const availableHeight = Math.max(viewport.clientHeight - padding * 2, 1);
      transform.scale = clamp(
        Math.min(availableWidth / sceneWidth, availableHeight / sceneHeight, 1),
        minScale,
        maxScale,
      );
      transform.x = (viewport.clientWidth - sceneWidth * transform.scale) / 2;
      transform.y = (viewport.clientHeight - sceneHeight * transform.scale) / 2;
      applyTransform();
    }

    function resetDiagram() {
      transform.scale = 1;
      transform.x = (viewport.clientWidth - sceneWidth) / 2;
      transform.y = (viewport.clientHeight - sceneHeight) / 2;
      applyTransform();
    }

    function beginGesture() {
      const activePointers = Array.from(pointers.values());
      if (activePointers.length >= 2) {
        const [first, second] = activePointers;
        const rect = viewport.getBoundingClientRect();
        const midpointX = (first.x + second.x) / 2 - rect.left;
        const midpointY = (first.y + second.y) / 2 - rect.top;
        gesture = {
          type: "pinch",
          distance: Math.hypot(second.x - first.x, second.y - first.y) || 1,
          scale: transform.scale,
          sceneX: (midpointX - transform.x) / transform.scale,
          sceneY: (midpointY - transform.y) / transform.scale,
        };
        return;
      }

      const pointer = activePointers[0];
      gesture = pointer
        ? {
            type: "pan",
            pointerId: pointer.id,
            startClientX: pointer.x,
            startClientY: pointer.y,
            startX: transform.x,
            startY: transform.y,
          }
        : null;
    }

    viewport.addEventListener("pointerdown", (event) => {
      if (event.target.closest("[data-diagram-action], [data-relation-key]")) return;
      if (event.pointerType === "mouse" && event.button !== 0) return;
      pointers.set(event.pointerId, { id: event.pointerId, x: event.clientX, y: event.clientY });
      viewport.setPointerCapture(event.pointerId);
      gestureMoved = false;
      viewport.classList.add("is-panning");
      beginGesture();
    });

    viewport.addEventListener("pointermove", (event) => {
      if (!pointers.has(event.pointerId) || !gesture) return;
      pointers.set(event.pointerId, { id: event.pointerId, x: event.clientX, y: event.clientY });

      if (gesture.type === "pan") {
        const pointer = pointers.get(gesture.pointerId);
        if (!pointer) return;
        const deltaX = pointer.x - gesture.startClientX;
        const deltaY = pointer.y - gesture.startClientY;
        transform.x = gesture.startX + deltaX;
        transform.y = gesture.startY + deltaY;
        gestureMoved ||= Math.hypot(deltaX, deltaY) > 4;
      } else {
        const [first, second] = Array.from(pointers.values());
        if (!first || !second) return;
        const rect = viewport.getBoundingClientRect();
        const midpointX = (first.x + second.x) / 2 - rect.left;
        const midpointY = (first.y + second.y) / 2 - rect.top;
        const distance = Math.hypot(second.x - first.x, second.y - first.y) || 1;
        transform.scale = clamp(gesture.scale * (distance / gesture.distance), minScale, maxScale);
        transform.x = midpointX - gesture.sceneX * transform.scale;
        transform.y = midpointY - gesture.sceneY * transform.scale;
        gestureMoved = true;
      }

      applyTransform();
    });

    function finishPointer(event) {
      if (!pointers.has(event.pointerId)) return;
      pointers.delete(event.pointerId);
      if (viewport.hasPointerCapture(event.pointerId)) viewport.releasePointerCapture(event.pointerId);
      if (pointers.size) {
        beginGesture();
        return;
      }
      viewport.classList.remove("is-panning");
      gesture = null;
      suppressNextClick = gestureMoved;
      gestureMoved = false;
    }

    viewport.addEventListener("pointerup", finishPointer);
    viewport.addEventListener("pointercancel", finishPointer);
    viewport.addEventListener(
      "click",
      (event) => {
        if (!suppressNextClick) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        suppressNextClick = false;
      },
      true,
    );

    viewport.addEventListener(
      "wheel",
      (event) => {
        event.preventDefault();
        const factor = Math.exp(-event.deltaY * 0.0015);
        zoomAt(transform.scale * factor, event.clientX, event.clientY);
      },
      { passive: false },
    );

    viewport.addEventListener("keydown", (event) => {
      const panStep = event.shiftKey ? 80 : 32;
      const actions = {
        ArrowLeft: () => { transform.x += panStep; },
        ArrowRight: () => { transform.x -= panStep; },
        ArrowUp: () => { transform.y += panStep; },
        ArrowDown: () => { transform.y -= panStep; },
        "+": () => zoomFromCenter(1.2),
        "=": () => zoomFromCenter(1.2),
        "-": () => zoomFromCenter(1 / 1.2),
        "0": fitDiagram,
      };
      const action = actions[event.key];
      if (!action) return;
      event.preventDefault();
      action();
      applyTransform();
    });

    els.relationDiagramWorkspace.querySelectorAll("[data-diagram-action]").forEach((button) => {
      button.addEventListener("click", () => {
        const action = button.dataset.diagramAction;
        if (action === "zoom-in") zoomFromCenter(1.2);
        if (action === "zoom-out") zoomFromCenter(1 / 1.2);
        if (action === "fit") fitDiagram();
        if (action === "reset") resetDiagram();
      });
    });

    fitDiagram();
  }

  function relationEntries(user, preview) {
    return Object.entries(user.relation_counts || {}).map(([key, count]) => {
      const items = relationItemsFor(user, key, preview);
      return { key, count: Number(count || 0), label: tableLabel(key), description: tableDescription(key), items };
    });
  }

  function renderRelationList(entries) {
    return entries
      .map((entry) => {
        const active = entry.key === state.selectedRelationKey;
        return `
        <section id="relation-${escapeHtml(entry.key)}" style="scroll-margin-top:6rem">
          <button type="button" data-relation-key="${escapeHtml(entry.key)}" class="card card-p-sm w-full" style="text-align:left;cursor:pointer;display:flex;align-items:flex-start;justify-content:space-between;gap:12px;${active ? "border-color:var(--brand);background:var(--brand-bg)" : ""}">
            <div style="min-width:0">
              <h3 class="text-sm font-semibold">${escapeHtml(entry.label)}</h3>
              <p class="text-xs text-muted" style="margin-top:2px;line-height:1.5">${escapeHtml(entry.description)}</p>
              <p class="text-xs font-medium" style="margin-top:8px;color:${active ? "var(--brand)" : "var(--muted)"}">${active ? "Tampil di tabel bawah" : "Klik untuk melihat data"}</p>
            </div>
            <span class="badge ${entry.count ? "badge-brand" : "badge-slate"}">${entry.count}</span>
          </button>
        </section>
      `;
      })
      .join("");
  }

  function renderSelectedRelationTable(entry) {
    if (!entry) return blankPanel("Pilih tabel relasi untuk melihat datanya.");
    const previewNeeded = entry.count > 0 && !state.relationPreview && entry.key !== "profiles";
    const rows = entry.items.length
      ? entry.items.map((item, i) => relationTableRow(item, entry, i)).join("")
      : `<tr><td colspan="4" style="padding:20px;text-align:center" class="text-sm text-muted">${escapeHtml(previewNeeded ? "Memuat data tabel..." : "Belum ada data untuk tabel ini.")}</td></tr>`;
    const sampleNote =
      entry.count > entry.items.length && entry.items.length
        ? `<p class="text-xs text-muted" style="margin-top:8px">Menampilkan ${entry.items.length} preview dari ${entry.count} data.</p>`
        : "";
    return `
      <div class="card card-shadow-md" style="padding:20px">
        <div class="flex items-start justify-between gap-3 flex-wrap" style="margin-bottom:16px">
          <div class="section-header">
            <span class="section-eyebrow">Data tabel terpilih</span>
            <h2 class="section-title">${escapeHtml(entry.label)}</h2>
            <p class="section-desc">${escapeHtml(entry.description)}</p>
            ${sampleNote}
          </div>
          <div class="flex items-center gap-2 flex-wrap">
            <span class="badge ${entry.count ? "badge-brand" : "badge-slate"}">${entry.count} data</span>
            <button type="button" data-open-diagram-for-relation class="btn btn-secondary" style="height:36px">
              <i data-lucide="network"></i>
              <span>Diagram relasi</span>
            </button>
          </div>
        </div>
        <div class="table-wrapper" style="max-height:24rem">
          <table class="data-table" style="min-width:860px">
            <thead>
              <tr>
                <th>#</th>
                <th>UUID / ID</th>
                <th>Data</th>
                <th>Detail</th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </div>
      </div>
    `;
  }

  function relationTableRow(item, entry, index) {
    return `
      <tr>
        <td class="text-xs font-semibold text-muted">${index + 1}</td>
        <td style="max-width:240px"><span class="truncate block mono text-xs" title="${escapeHtml(item.id)}">${escapeHtml(item.id || "-")}</span></td>
        <td style="max-width:280px"><span class="truncate block font-medium" title="${escapeHtml(item.title || entry.label)}">${escapeHtml(item.title || entry.label)}</span></td>
        <td style="max-width:320px"><div style="display:flex; flex-wrap:wrap; gap:4px;" title="${escapeHtml(item.meta || entry.key)}">${formatRelationMeta(item.meta || entry.key)}</div></td>
      </tr>
    `;
  }

  function selectRelation(key) {
    state.selectedRelationKey = key;
    renderRelationsPanel();
    if (!els.relationTableWorkspace.classList.contains("hidden")) {
      els.relationTableWorkspace.scrollIntoView({ behavior: "smooth", block: "start" });
    }
    const user = selectedUser();
    if (!user) return;
    const entry = selectedRelationEntry(relationEntries(user, state.relationPreview));
    if (entry?.count > 0 && !state.relationPreview && !state.loading.relations) {
      loadRelations(user.id);
    }
  }

  function ensureSelectedRelation(entries) {
    if (entries.some((e) => e.key === state.selectedRelationKey)) return;
    state.selectedRelationKey = entries.find((e) => e.count > 0)?.key || entries[0]?.key || null;
  }

  function selectedRelationEntry(entries) {
    return entries.find((e) => e.key === state.selectedRelationKey) || entries[0] || null;
  }

  function renderDiagramPanelHint(entries) {
    const totalTables = entries.length;
    const activeTables = entries.filter((e) => e.count > 0).length;
    return `
      <div class="card card-p" style="background:var(--white)">
        <div class="flex items-start gap-3">
          <span class="stat-icon icon-brand shrink-0"><i data-lucide="network"></i></span>
          <div style="min-width:0">
            <p class="text-sm font-semibold">Diagram tampil di workspace lebar</p>
            <p class="text-xs text-muted" style="margin-top:4px;line-height:1.5">Mode diagram dipindahkan ke bawah area tabel supaya node dan garis relasi tidak terpotong di panel kanan.</p>
          </div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:16px">
          <div class="relation-metric">
            <p class="relation-metric-label">Tabel</p>
            <p class="relation-metric-value">${totalTables}</p>
          </div>
          <div class="relation-metric" style="background:var(--brand-bg)">
            <p class="relation-metric-label" style="color:var(--brand)">Aktif</p>
            <p class="relation-metric-value" style="color:var(--brand)">${activeTables}</p>
          </div>
        </div>
        <button type="button" data-scroll-diagram class="btn btn-primary w-full" style="margin-top:16px">
          <i data-lucide="maximize-2"></i>
          <span>Lihat diagram</span>
        </button>
      </div>
    `;
  }

  function renderRelationDiagram(user, entries) {
    const selectedKey = state.selectedRelationKey || "profiles";
    const selectedEntry = entries.find(e => e.key === selectedKey) || entries[0];

    // Relationship mappings representing PK/FK database schema
    const RELATION_MAPS = {
      profiles: {
        left: [{ name: "auth.users", desc: "Tabel user utama Supabase", key: "profiles" }],
        right: [
          { name: "reader_preferences", desc: "Preferensi reader default", key: "reader_preferences" },
          { name: "user_reading_stats", desc: "Statistik baca user", key: "user_reading_stats" },
          { name: "user_bookmarks", desc: "Bookmark komik user", key: "user_bookmarks" },
          { name: "user_bookmark_links", desc: "Relasi bookmark multi-source", key: "user_bookmark_links" },
          { name: "user_collections", desc: "Folder koleksi komik user", key: "user_collections" },
          { name: "user_progress", desc: "Progress baca user", key: "user_progress" },
          { name: "user_completed_chapters", desc: "Chapter selesai dibaca", key: "user_completed_chapters" },
          { name: "user_history_entries", desc: "Riwayat baca user", key: "user_history_entries" },
          { name: "user_favorite_scenes", desc: "Scene favorit user", key: "user_favorite_scenes" },
          { name: "user_download_entries", desc: "Daftar chapter diunduh", key: "user_download_entries" }
        ]
      },
      reader_preferences: {
        left: [{ name: "profiles", desc: "Profil publik user", key: "profiles" }],
        right: []
      },
      user_reading_stats: {
        left: [{ name: "profiles", desc: "Profil publik user", key: "profiles" }],
        right: []
      },
      user_bookmarks: {
        left: [
          { name: "profiles", desc: "Profil publik user", key: "profiles" },
          { name: "comics", desc: "Tabel komik utama", key: "comics_sys" }
        ],
        right: [{ name: "user_bookmark_links", desc: "Relasi source alternatif bookmark", key: "user_bookmark_links" }]
      },
      user_bookmark_links: {
        left: [
          { name: "profiles", desc: "Profil publik user", key: "profiles" },
          { name: "user_bookmarks", desc: "Bookmark induk user", key: "user_bookmarks" },
          { name: "comics", desc: "Komik source alternatif", key: "comics_sys" }
        ],
        right: []
      },
      user_collections: {
        left: [{ name: "profiles", desc: "Profil publik user", key: "profiles" }],
        right: [{ name: "user_collection_comics", desc: "Asosiasi komik ke koleksi", key: "user_collection_comics" }]
      },
      user_collection_comics: {
        left: [
          { name: "user_collections", desc: "Folder koleksi komik user", key: "user_collections" },
          { name: "comics", desc: "Tabel komik utama", key: "comics_sys" }
        ],
        right: []
      },
      user_progress: {
        left: [
          { name: "profiles", desc: "Profil publik user", key: "profiles" },
          { name: "comics", desc: "Tabel komik utama", key: "comics_sys" },
          { name: "chapters", desc: "Tabel chapter komik", key: "chapters_sys" }
        ],
        right: []
      },
      user_completed_chapters: {
        left: [
          { name: "profiles", desc: "Profil publik user", key: "profiles" },
          { name: "comics", desc: "Tabel komik utama", key: "comics_sys" },
          { name: "chapters", desc: "Tabel chapter komik", key: "chapters_sys" }
        ],
        right: []
      },
      user_history_entries: {
        left: [
          { name: "profiles", desc: "Profil publik user", key: "profiles" },
          { name: "comics", desc: "Tabel komik utama", key: "comics_sys" },
          { name: "chapters", desc: "Tabel chapter komik", key: "chapters_sys" }
        ],
        right: []
      },
      user_favorite_scenes: {
        left: [
          { name: "profiles", desc: "Profil publik user", key: "profiles" },
          { name: "comics", desc: "Tabel komik utama", key: "comics_sys" },
          { name: "chapters", desc: "Tabel chapter komik", key: "chapters_sys" }
        ],
        right: []
      },
      user_download_entries: {
        left: [
          { name: "profiles", desc: "Profil publik user", key: "profiles" },
          { name: "comics", desc: "Tabel komik utama", key: "comics_sys" },
          { name: "chapters", desc: "Tabel chapter komik", key: "chapters_sys" }
        ],
        right: []
      }
    };

    const currentMap = RELATION_MAPS[selectedKey] || { left: [{ name: "auth.users", desc: "Tabel user utama Supabase", key: "profiles" }], right: [] };
    const leftNodes = currentMap.left;
    const rightNodes = currentMap.right;

    const nodeHeight = 80;
    const nodeStride = 92;
    const centerNodeHeight = 96;
    const maxSideNodes = Math.max(leftNodes.length, rightNodes.length, 1);
    const height = Math.max(340, maxSideNodes * nodeStride + 40);
    const centerY = Math.round((height - centerNodeHeight) / 2);

    // Render central node (Selected Table)
    const centerNodeHtml = `
      <div class="relation-node relation-node-center" style="position:absolute;left:380px;top:${centerY}px;height:${centerNodeHeight}px;width:320px;">
        <span class="relation-node-center-key">${escapeHtml(selectedKey)} (Tabel Terpilih)</span>
        <span class="relation-node-center-label">${escapeHtml(selectedEntry ? selectedEntry.label : tableLabel(selectedKey))}</span>
        <span class="badge badge-brand relation-node-center-count">${selectedEntry ? selectedEntry.count : 0} data</span>
      </div>
    `;

    // Render left nodes (Parent tables / PKs / FKs pointing from central table)
    let leftNodesHtml = "";
    let leftLinesHtml = "";
    const leftTotalHeight =
      leftNodes.length * nodeHeight + Math.max(leftNodes.length - 1, 0) * (nodeStride - nodeHeight);
    const leftStartY = Math.round((height - leftTotalHeight) / 2);

    leftNodes.forEach((node, i) => {
      const nodeY = leftStartY + i * nodeStride;

      const entryMatch = entries.find(e => e.key === node.key);
      const isAuthUser = node.name === "auth.users";

      let countText = "";
      let buttonAttr = "";
      let nodeStyle = "border:1px solid var(--line);background:var(--white);";
      let titleColor = "var(--ink)";

      if (isAuthUser) {
        countText = `<span class="badge badge-brand">Selected</span>`;
        titleColor = "var(--brand)";
        nodeStyle = "border:1.5px solid var(--brand);background:var(--white);";
      } else if (entryMatch) {
        countText = `<span class="badge ${entryMatch.count ? "badge-brand" : "badge-slate"}">${entryMatch.count}</span>`;
        buttonAttr = `data-relation-key="${escapeHtml(node.key)}"`;
        if (entryMatch.count) {
          nodeStyle = "border:1px solid var(--brand);background:#eef6ff;";
          titleColor = "var(--brand)";
        }
      } else {
        countText = `<span class="badge badge-slate">Sistem</span>`;
      }

      const nodeTag = buttonAttr ? "button" : "div";
      leftNodesHtml += `
        <${nodeTag} ${buttonAttr} ${buttonAttr ? 'type="button"' : ""} class="relation-node" style="position:absolute;left:0px;top:${nodeY}px;display:flex;height:80px;width:280px;align-items:center;justify-content:space-between;gap:12px;border-radius:var(--radius-md);${nodeStyle};padding:12px;box-shadow:var(--shadow-sm);${buttonAttr ? "cursor:pointer;" : ""}">
          <span style="min-width:0">
            <span class="block truncate text-sm font-semibold" style="color:${titleColor}">${escapeHtml(node.name)}</span>
            <span class="block truncate text-xs text-muted" style="margin-top:2px">${escapeHtml(node.desc || "Tabel sistem terkait")}</span>
          </span>
          ${countText}
        </${nodeTag}>
      `;

      // Connection lines
      const stroke = (isAuthUser || (entryMatch && entryMatch.count)) ? "var(--brand)" : "var(--line)";
      const strokeWidth = (isAuthUser || (entryMatch && entryMatch.count)) ? 2.4 : 1.4;
      const strokeDash = (isAuthUser || (entryMatch && entryMatch.count)) ? "0" : "6 6";

      const centerConnectY =
        centerY + 16 + ((i + 1) * (centerNodeHeight - 32)) / (leftNodes.length + 1);

      leftLinesHtml += `
        <path d="M 280 ${nodeY + 40} C 330 ${nodeY + 40}, 330 ${centerConnectY}, 380 ${centerConnectY}" stroke="${stroke}" stroke-width="${strokeWidth}" fill="none" stroke-dasharray="${strokeDash}" />
      `;
    });

    // Render right nodes (Child tables referencing central table)
    let rightNodesHtml = "";
    let rightLinesHtml = "";
    const rightTotalHeight =
      rightNodes.length * nodeHeight + Math.max(rightNodes.length - 1, 0) * (nodeStride - nodeHeight);
    const rightStartY = Math.round((height - rightTotalHeight) / 2);

    rightNodes.forEach((node, i) => {
      const nodeY = rightStartY + i * nodeStride;
      const entryMatch = entries.find(e => e.key === node.key);

      let countText = "";
      let buttonAttr = "";
      let nodeStyle = "border:1px solid var(--line);background:var(--white);";
      let titleColor = "var(--ink)";

      if (entryMatch) {
        countText = `<span class="badge ${entryMatch.count ? "badge-brand" : "badge-slate"}">${entryMatch.count}</span>`;
        buttonAttr = `data-relation-key="${escapeHtml(node.key)}"`;
        if (entryMatch.count) {
          nodeStyle = "border:1px solid var(--brand);background:#eef6ff;";
          titleColor = "var(--brand)";
        }
      }

      const nodeTag = buttonAttr ? "button" : "div";
      rightNodesHtml += `
        <${nodeTag} ${buttonAttr} ${buttonAttr ? 'type="button"' : ""} class="relation-node" style="position:absolute;left:800px;top:${nodeY}px;display:flex;height:80px;width:280px;align-items:center;justify-content:space-between;gap:12px;border-radius:var(--radius-md);${nodeStyle};padding:12px;box-shadow:var(--shadow-sm);${buttonAttr ? "cursor:pointer;" : ""}">
          <span style="min-width:0">
            <span class="block truncate text-sm font-semibold" style="color:${titleColor}">${escapeHtml(node.name)}</span>
            <span class="block truncate text-xs text-muted" style="margin-top:2px">${escapeHtml(node.desc || "Tabel sistem terkait")}</span>
          </span>
          ${countText}
        </${nodeTag}>
      `;

      const stroke = (entryMatch && entryMatch.count) ? "var(--brand)" : "var(--line)";
      const strokeWidth = (entryMatch && entryMatch.count) ? 2.4 : 1.4;
      const strokeDash = (entryMatch && entryMatch.count) ? "0" : "6 6";

      const centerConnectY =
        centerY + 16 + ((i + 1) * (centerNodeHeight - 32)) / (rightNodes.length + 1);

      rightLinesHtml += `
        <path d="M 700 ${centerConnectY} C 750 ${centerConnectY}, 750 ${nodeY + 40}, 800 ${nodeY + 40}" stroke="${stroke}" stroke-width="${strokeWidth}" fill="none" stroke-dasharray="${strokeDash}" />
      `;
    });

    return `
      <div class="card card-shadow-md" style="padding:20px">
        <div class="flex items-center justify-between gap-3 flex-wrap" style="margin-bottom:16px">
          <div class="section-header">
            <span class="section-eyebrow">Visualisasi Relasi Skema</span>
            <h2 class="section-title">Diagram ERD: ${escapeHtml(tableLabel(selectedKey))}</h2>
            <p class="section-desc">Diagram relasi spesifik untuk tabel <strong>${escapeHtml(selectedKey)}</strong>. Klik node tabel relasi aktif untuk berpindah data.</p>
          </div>
          <div class="flex gap-2 flex-wrap">
            <button type="button" data-relation-view="list" class="btn btn-secondary" style="height:36px">
              <i data-lucide="list"></i>
              <span>Tutup diagram</span>
            </button>
          </div>
        </div>
        <div class="relation-diagram-toolbar">
          <p class="relation-diagram-help">
            <i data-lucide="mouse-pointer-2"></i>
            Drag untuk pan, scroll atau pinch untuk zoom
          </p>
          <div class="relation-diagram-controls" role="group" aria-label="Kontrol zoom diagram">
            <button type="button" data-diagram-action="zoom-out" class="btn-icon" title="Perkecil diagram" aria-label="Perkecil diagram">
              <i data-lucide="minus"></i>
            </button>
            <output data-diagram-zoom-label class="relation-diagram-zoom" aria-live="polite">100%</output>
            <button type="button" data-diagram-action="zoom-in" class="btn-icon" title="Perbesar diagram" aria-label="Perbesar diagram">
              <i data-lucide="plus"></i>
            </button>
            <button type="button" data-diagram-action="fit" class="btn btn-secondary relation-diagram-control-btn" title="Sesuaikan seluruh diagram ke viewport">
              <i data-lucide="scan"></i>
              <span>Fit</span>
            </button>
            <button type="button" data-diagram-action="reset" class="btn-icon" title="Kembalikan zoom ke 100%" aria-label="Kembalikan zoom ke 100%">
              <i data-lucide="rotate-ccw"></i>
            </button>
          </div>
        </div>
        <div
          class="relation-diagram-viewport"
          data-relation-diagram-viewport
          tabindex="0"
          aria-label="Kanvas diagram relasi. Gunakan drag atau tombol panah untuk menggeser, scroll atau tombol tambah dan kurang untuk zoom."
        >
          <div
            class="relation-diagram-scene"
            data-relation-diagram-scene
            data-scene-width="1080"
            data-scene-height="${height}"
            style="width:1080px;height:${height}px"
          >
            <svg style="position:absolute;inset:0;width:100%;height:100%" preserveAspectRatio="none" role="img" aria-label="Diagram relasi skema">${leftLinesHtml}${rightLinesHtml}</svg>
            ${leftNodesHtml}
            ${centerNodeHtml}
            ${rightNodesHtml}
          </div>
        </div>
      </div>
    `;
  }

  function relationMetric(label, value) {
    return `
      <div class="relation-metric">
        <p class="relation-metric-label">${escapeHtml(label)}</p>
        <p class="relation-metric-value">${escapeHtml(value)}</p>
      </div>
    `;
  }

  function relationViewButton(view, label, icon) {
    const active = state.relationView === view;
    return `
      <button type="button" data-relation-view="${view}" class="view-toggle-btn ${active ? "toggle-active" : ""}">
        <i data-lucide="${icon}"></i>
        <span>${label}</span>
      </button>
    `;
  }

  /* ── Panels ─────────────────────────────────────────────────────────── */
  function setPanel(panel) {
    state.currentPanel = panel;
    document.querySelectorAll(".panel-tab").forEach((tab) => {
      tab.classList.toggle("tab-active", tab.dataset.panelTab === panel);
    });
    els.profilePanel.hidden = panel !== "profile";
    els.relationsPanel.hidden = panel !== "relations";
    els.metadataPanel.hidden = panel !== "metadata";
    if (panel !== "relations") {
      hideRelationTableWorkspace();
      hideRelationDiagramWorkspace();
    }
    if (panel === "relations" && selectedUser()) {
      renderRelationsPanel();
      if (!state.relationPreview) loadRelations(selectedUser().id);
    }
  }

  function selectedUser() {
    return state.users.find((u) => u.id === state.selectedUserId) || null;
  }

  function relationItemsFor(user, key, preview) {
    let items = [];
    if (preview?.[key]?.length) {
      items = preview[key];
    } else if (key === "profiles" && user.profile) {
      items = [
        {
          id: user.id,
          title: user.profile.display_name || user.profile.username || user.email || user.id,
          meta: user.profile.username || "profiles",
          table: "profiles",
        },
      ];
    }

    // Ensure profiles table correctly falls back to email if title is raw ID
    if (key === "profiles") {
      return items.map((item) => ({
        ...item,
        title: item.title === item.id ? user.email || item.title : item.title,
      }));
    }

    return items;
  }

  /* ── Modal Operations ───────────────────────────────────────────────── */
  function openCreateModal() {
    els.modalTitle.textContent = "Tambah akun";
    els.userForm.reset();
    els.editingUserId.value = "";
    els.passwordField.required = true;
    els.accountRoleField.value = "reader";
    els.accountStatusField.value = "active";
    syncCustomSelects();
    updateRoleWarning();
    openModal("userModal");
  }

  function openEditModal(userId) {
    const user = state.users.find((u) => u.id === userId);
    if (!user) return;
    els.modalTitle.textContent = "Edit akun";
    els.editingUserId.value = user.id;
    els.emailField.value = user.email || "";
    els.passwordField.value = "";
    els.passwordField.required = false;
    els.displayNameField.value = user.profile?.display_name || user.user_metadata?.display_name || "";
    els.usernameField.value = user.profile?.username || user.user_metadata?.username || "";
    els.accountRoleField.value = user.account_role || "reader";
    els.accountStatusField.value = user.account_status || "active";
    els.avatarUrlField.value = user.profile?.avatar_url || "";
    els.onboardingField.checked = Boolean(user.profile?.onboarding_completed);
    syncCustomSelects();
    updateRoleWarning();
    openModal("userModal");
  }

  async function saveUser(event) {
    event.preventDefault();
    if (state.loading.save) return;
    const userId = els.editingUserId.value;
    const payload = {
      email: els.emailField.value.trim(),
      password: els.passwordField.value,
      display_name: els.displayNameField.value.trim() || null,
      username: els.usernameField.value.trim() || null,
      account_role: els.accountRoleField.value,
      account_status: els.accountStatusField.value,
      avatar_url: els.avatarUrlField.value.trim() || null,
      onboarding_completed: els.onboardingField.checked,
    };
    if (userId && !payload.password) delete payload.password;
    const currentUser = state.users.find((u) => u.id === userId);
    const willGrantPrivilegedRole =
      ["admin", "owner"].includes(payload.account_role) &&
      !["admin", "owner"].includes(currentUser?.account_role);
    const willSuspend =
      payload.account_status === "suspended" && currentUser?.account_status !== "suspended";
    if (
      willGrantPrivilegedRole &&
      !window.confirm("Role ini memberi akses tinggi ke account manager. Lanjutkan menyimpan?")
    )
      return;
    if (willSuspend && !window.confirm("Status suspended akan memblokir login user ini. Lanjutkan?"))
      return;

    setLoading("save", true);
    try {
      const saved = userId
        ? await apiFetch(`/api/v1/account-manager/accounts/${userId}`, { method: "PATCH", body: payload })
        : await apiFetch("/api/v1/account-manager/accounts", { method: "POST", body: payload });
      closeModal("userModal");
      mergeSavedUser(saved, !userId);
      state.selectedUserId = saved.id;
      state.relationPreview = null;
      render();
      notify("Akun tersimpan.");
    } catch (error) {
      handleRequestError(error);
    } finally {
      setLoading("save", false);
    }
  }

  function mergeSavedUser(saved, isCreate = false) {
    const existingIndex = state.users.findIndex((u) => u.id === saved.id);
    if (existingIndex >= 0) {
      state.users[existingIndex] = keepExistingRelationSnapshot(saved, state.users[existingIndex]);
      return;
    }
    state.users = [saved, ...state.users].slice(0, state.pagination.perPage);
    if (isCreate) {
      state.pagination.total += 1;
    } else {
      state.pagination.total = Math.max(state.pagination.total, state.users.length);
    }
  }

  function keepExistingRelationSnapshot(saved, existing) {
    if (!existing) return saved;
    const existingTotal = existing.relation_total ?? relationCountTotal(existing.relation_counts);
    const savedTotal = saved.relation_total ?? relationCountTotal(saved.relation_counts);
    if (existingTotal < savedTotal) return saved;
    return {
      ...saved,
      relation_counts: existing.relation_counts || saved.relation_counts,
      relation_total: existingTotal ?? savedTotal ?? 0,
    };
  }

  function relationCountTotal(counts) {
    return Object.values(counts || {}).reduce((sum, c) => sum + Number(c || 0), 0);
  }

  async function openDeleteModal(userId) {
    const user = state.users.find((u) => u.id === userId);
    if (!user) return;
    if (user.id === state.currentUserId) {
      notify("Akun yang sedang dipakai login tidak bisa dihapus.", true);
      return;
    }
    state.pendingDeleteUserId = userId;
    els.confirmCascade.checked = false;
    syncLoadingState();
    els.deleteMessage.textContent = `${displayName(user)} (${user.id}) akan dihapus dari Supabase Auth dan tabel aplikasi.`;
    els.deleteRelations.innerHTML = `<p class="text-sm text-muted">Memuat preview...</p>`;
    openModal("deleteModal");
    try {
      const preview = await apiFetch(`/api/v1/account-manager/accounts/${userId}/delete-preview`);
      els.deleteRelations.innerHTML = Object.entries(preview.relation_counts || {})
        .map(
          ([key, count]) => `
          <div class="delete-relation-row">
            <span class="font-medium">${tableLabel(key)}</span>
            <span class="font-semibold text-muted">${count}</span>
          </div>
        `,
        )
        .join("");
    } catch (error) {
      handleRequestError(error);
      closeModal("deleteModal");
    }
  }

  async function deleteUser() {
    if (!state.pendingDeleteUserId || !els.confirmCascade.checked || state.loading.delete) return;
    if (state.pendingDeleteUserId === state.currentUserId) {
      notify("Akun yang sedang dipakai login tidak bisa dihapus.", true);
      return;
    }
    const deletedUserId = state.pendingDeleteUserId;
    setLoading("delete", true);
    try {
      await apiFetch(`/api/v1/account-manager/accounts/${deletedUserId}`, { method: "DELETE" });
      state.pendingDeleteUserId = null;
      closeModal("deleteModal");
      if (!removeDeletedUser(deletedUserId)) await loadAccounts();
      notify("Akun dan relasinya sudah dihapus.");
    } catch (error) {
      handleRequestError(error);
    } finally {
      setLoading("delete", false);
    }
  }

  function removeDeletedUser(userId) {
    state.users = state.users.filter((u) => u.id !== userId);
    state.pagination.total = Math.max(0, state.pagination.total - 1);
    if (state.selectedUserId === userId) {
      state.selectedUserId = state.users[0]?.id || null;
      state.relationPreview = null;
    }
    if (!state.users.length && state.pagination.page > 1) {
      state.pagination.page -= 1;
      return false;
    }
    render();
    return true;
  }

  /* ── Loading / State Sync ───────────────────────────────────────────── */
  function setLoading(key, value) {
    state.loading[key] = value;
    if (key === "relations" && state.currentPanel === "relations" && selectedUser()) {
      renderRelationsPanel();
    }
    if (key === "accounts") renderUsers();
    syncLoadingState();
  }

  function syncLoadingState() {
    setButtonLoading(els.reloadBtn, state.loading.accounts, {
      loadingText: "Memuat...",
      idleText: "Reload",
      loadingIcon: "loader-2",
      idleIcon: "refresh-cw",
    });
    els.openCreateBtn.disabled = state.loading.accounts || state.loading.save;
    setButtonLoading(els.saveUserBtn, state.loading.save, {
      loadingText: "Menyimpan...",
      idleText: "Simpan",
      loadingIcon: "loader-2",
      idleIcon: "save",
    });
    setButtonLoading(els.confirmDeleteBtn, state.loading.delete, {
      loadingText: "Menghapus...",
      idleText: "Hapus bersih",
      loadingIcon: "loader-2",
      idleIcon: "trash-2",
      disabled: !els.confirmCascade.checked,
    });
    setButtonLoading(els.sendAnnouncementBtn, state.loading.announcement, {
      loadingText: "Mengirim...",
      idleText: "Kirim",
      loadingIcon: "loader-2",
      idleIcon: "send",
    });
    renderPagination();
    lucide.createIcons();
  }

  function updateRoleWarning() {
    const role = els.accountRoleField.value;
    const status = els.accountStatusField.value;
    const warnings = [];
    if (["admin", "owner"].includes(role))
      warnings.push("Role ini dapat mengakses fitur account manager.");
    if (status === "suspended")
      warnings.push("Status suspended akan mengirim ban ke Supabase Auth.");
    els.roleWarning.textContent = warnings.join(" ");
    els.roleWarning.classList.toggle("hidden", warnings.length === 0);
  }

  /* ── Modals ─────────────────────────────────────────────────────────── */
  function openModal(id) {
    const modal = document.querySelector(`#${id}`);
    modal.classList.add("modal-open");
    lucide.createIcons();
  }

  function closeModal(id) {
    const modal = document.querySelector(`#${id}`);
    modal.classList.remove("modal-open");
  }

  /* ── Display Helpers ────────────────────────────────────────────────── */
  function displayName(user) {
    return user.profile?.display_name || user.user_metadata?.display_name || user.email || user.id;
  }

  function roleLabel(role) {
    return { admin: "Admin", reader: "Reader" }[role] || role || "-";
  }

  function statusLabel(status) {
    return { active: "Aktif", pending: "Pending", suspended: "Suspended" }[status] || status || "-";
  }

  function statusBadgeClass(status) {
    return { active: "badge-green", pending: "badge-amber", suspended: "badge-red" }[status] || "badge-slate";
  }

  function formatRelationMeta(value) {
    if (!value) return `<span class="badge badge-slate">-</span>`;

    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime()) && String(value).includes("T")) {
      return `<span class="badge badge-slate">${escapeHtml(formatDate(value))}</span>`;
    }

    if (typeof value === "string" && value.includes(" • ")) {
      return value.split(" • ").map(part => {
        let badgeClass = "badge-slate";
        const normalized = part.toLowerCase().trim();

        if (normalized.includes("nonaktif") || normalized.includes("belum selesai") || normalized.includes("suspended") || normalized.includes("failed")) {
          badgeClass = "badge-red";
        } else if (normalized.includes("aktif") || normalized.includes("selesai") || normalized.includes("active") || normalized.includes("completed")) {
          badgeClass = "badge-green";
        } else if (normalized.includes("menit") || normalized.includes("total") || normalized.includes("reading") || normalized.includes("bookmark")) {
          badgeClass = "badge-brand";
        } else if (normalized.includes("ltr") || normalized.includes("vertical") || normalized.includes("webtoon") || normalized.includes("pending")) {
          badgeClass = "badge-amber";
        }

        return `<span class="badge ${badgeClass}" style="display: inline-flex; align-items: center;">${escapeHtml(part)}</span>`;
      }).join("");
    }

    let badgeClass = "badge-slate";
    const normalized = String(value).toLowerCase().trim();
    if (normalized.includes("nonaktif") || normalized.includes("belum selesai") || normalized.includes("suspended") || normalized.includes("failed")) {
      badgeClass = "badge-red";
    } else if (normalized.includes("aktif") || normalized.includes("selesai") || normalized.includes("active") || normalized.includes("completed")) {
      badgeClass = "badge-green";
    } else if (normalized.includes("menit") || normalized.includes("total") || normalized.includes("reading") || normalized.includes("bookmark")) {
      badgeClass = "badge-brand";
    } else if (normalized.includes("ltr") || normalized.includes("vertical") || normalized.includes("webtoon") || normalized.includes("pending")) {
      badgeClass = "badge-amber";
    }

    return `<span class="badge ${badgeClass}">${escapeHtml(value)}</span>`;
  }

  function tableLabel(key) {
    return (
      {
        profiles: "Profiles",
        reader_preferences: "Reader Preferences",
        user_reading_stats: "Reading Stats",
        user_bookmarks: "Bookmarks",
        user_bookmark_links: "Bookmark Links",
        user_collections: "Collections",
        user_collection_comics: "Collection Items",
        user_progress: "Progress",
        user_completed_chapters: "Completed Chapters",
        user_history_entries: "History",
        user_favorite_scenes: "Favorite Scenes",
        user_download_entries: "Downloads",
      }[key] || key
    );
  }

  function tableDescription(key) {
    return (
      {
        profiles: "Profil publik dan onboarding user.",
        reader_preferences: "Preferensi reader default milik user.",
        user_reading_stats: "Akumulasi statistik baca per user.",
        user_bookmarks: "Komik yang disimpan sebagai bookmark.",
        user_bookmark_links: "Relasi source alternatif untuk bookmark multi-source.",
        user_collections: "Koleksi pribadi yang dibuat user.",
        user_collection_comics: "Item komik di dalam koleksi user.",
        user_progress: "Progress baca per komik dan chapter.",
        user_completed_chapters: "Chapter yang selesai dibaca.",
        user_history_entries: "Riwayat baca terakhir user.",
        user_favorite_scenes: "Scene favorit yang ditandai user.",
        user_download_entries: "Daftar chapter/komik yang diunduh.",
      }[key] || "Data aplikasi yang terhubung ke user ID."
    );
  }
})();
