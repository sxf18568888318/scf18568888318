(() => {
  'use strict';
  const roleNames = { owner: '老板', designer: '设计师', foreman: '工长', factory_manager: '厂长' };
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
  const nextLogin = accounts => {
    const max = accounts.reduce((n, a) => Math.max(n, Number(a.login_name?.match(/-(\d+)$/)?.[1] || 0)), 0) + 1;
    return `yj18568888318-${String(max).padStart(2, '0')}`;
  };
  function close() { document.getElementById('accountAdminDialog')?.remove(); }
  async function open() {
    if (window.__ANJU_AUTH__?.role !== 'owner') return;
    close();
    document.body.insertAdjacentHTML('beforeend', `<div class="account-admin-overlay" id="accountAdminDialog" role="dialog" aria-modal="true" aria-labelledby="accountAdminTitle"><section class="account-admin-card"><header><div><small>老板设置</small><h2 id="accountAdminTitle">账号管理</h2></div><button type="button" data-close aria-label="关闭">×</button></header><div class="account-admin-notice">只列出系统现有账号。核对姓名后填写对应编号；不自动猜测映射。账号数量按现有实际情况维护。</div><div class="account-admin-error" id="accountAdminError" role="alert"></div><div id="accountAdminList" class="account-admin-list">正在读取账号…</div><details class="account-admin-create"><summary>新增账号</summary><form id="accountAdminCreate"><label>姓名<input name="display_name" required></label><label>登录账号<input name="login_name" required></label><label>角色<select name="role"><option value="designer">设计师</option><option value="foreman">工长</option><option value="factory_manager">厂长</option><option value="owner">老板</option></select></label><label>初始密码<input name="password" type="password" minlength="10" required></label><button class="btn btn-primary" type="submit">开通账号</button></form></details><footer><button class="btn" data-close>关闭</button><button class="btn btn-primary" id="accountBulkReset">批量重置选中账号密码</button></footer></section></div>`);
    const dialog = document.getElementById('accountAdminDialog');
    dialog.querySelectorAll('[data-close]').forEach(button => button.addEventListener('click', close));
    dialog.addEventListener('click', event => { if (event.target === dialog) close(); });
    const showError = message => { document.getElementById('accountAdminError').textContent = message; };
    let accounts = [];
    async function refresh() {
      const result = await window.anjuAuth.manageAccounts('list');
      accounts = result.accounts;
      document.getElementById('accountAdminList').innerHTML = accounts.map((account, index) => `<article class="account-admin-row" data-id="${esc(account.id)}"><label class="account-check"><input type="checkbox" class="account-select"><span>${esc(account.display_name || '未命名账号')}</span></label><div><small>当前登录名</small><input class="account-login" value="${esc(account.login_name)}" placeholder="未绑定，如 yj18568888318-01"></div><div><small>角色</small><select class="account-role">${Object.entries(roleNames).map(([value, name]) => `<option value="${value}" ${account.role === value ? 'selected' : ''}>${name}</option>`).join('')}</select></div><div class="account-admin-actions"><button type="button" class="btn account-save-login">保存登录名</button><button type="button" class="btn account-reset">重置密码</button></div></article>`).join('') || '<p>没有找到已配置角色的账号。</p>';
      document.getElementById('accountAdminCreate').elements.login_name.value ||= nextLogin(accounts);
      document.querySelectorAll('.account-admin-row').forEach(row => {
        const id = row.dataset.id;
        row.querySelector('.account-save-login').addEventListener('click', async () => {
          showError(''); const login_name = row.querySelector('.account-login').value.trim();
          if (!/^yj18568888318-\d{2,}$/.test(login_name)) return showError('登录名格式应为 yj18568888318-01。');
          try { await window.anjuAuth.manageAccounts(accounts.find(a => a.id === id)?.mapped ? 'rename' : 'assign', { user_id: id, login_name }); await refresh(); }
          catch { showError('保存登录名失败，请确认账号编号未被占用。'); }
        });
        row.querySelector('.account-role').addEventListener('change', async event => {
          showError(''); try { await window.anjuAuth.manageAccounts('set_role', { user_id: id, role: event.target.value }); }
          catch { showError('角色调整失败；系统会保护最后一个老板账号。'); await refresh(); }
        });
        row.querySelector('.account-reset').addEventListener('click', async () => {
          const account = accounts.find(a => a.id === id);
          const password = prompt(`为「${account.display_name}」设置新密码（至少 10 位）：`);
          if (password === null) return;
          if (password.length < 10) return showError('新密码至少需要 10 位。');
          if (!confirm(`确认重置「${account.display_name}」的密码？`)) return;
          try { await window.anjuAuth.manageAccounts('reset_password', { user_ids: [id], password }); showError('密码已重置；列表不会保存或显示密码。'); }
          catch { showError('密码重置失败。'); }
        });
      });
    }
    document.getElementById('accountAdminCreate').addEventListener('submit', async event => {
      event.preventDefault(); showError('');
      const values = Object.fromEntries(new FormData(event.currentTarget));
      if (values.password.length < 10) return showError('密码至少需要 10 位。');
      try { await window.anjuAuth.manageAccounts('create', values); event.currentTarget.reset(); await refresh(); }
      catch { showError('开通失败，请核对登录名是否重复及资料是否完整。'); }
    });
    document.getElementById('accountBulkReset').addEventListener('click', async () => {
      const ids = [...document.querySelectorAll('.account-admin-row')].filter(row => row.querySelector('.account-select').checked).map(row => row.dataset.id);
      if (!ids.length) return showError('请先勾选需要重置的账号。');
      const password = prompt(`将为 ${ids.length} 个已选账号统一设置新密码（至少 10 位）：`);
      if (password === null) return;
      if (password.length < 10) return showError('新密码至少需要 10 位。');
      const names = ids.map(id => accounts.find(a => a.id === id)?.display_name || '员工').join('、');
      if (!confirm(`确认重置以下账号密码？\n${names}`)) return;
      try { await window.anjuAuth.manageAccounts('reset_password', { user_ids: ids, password }); showError(`已更新 ${ids.length} 个账号的密码。`); }
      catch { showError('批量重置失败。'); }
    });
    try { await refresh(); } catch { showError('账号列表读取失败；请确认该登录账号为老板角色。'); }
  }
  window.addEventListener('anju:open-account-admin', open);
})();
