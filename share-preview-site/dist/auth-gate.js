(() => {
  'use strict';
  const SUPABASE_URL = 'https://quindxekbhpgymxfzixs.supabase.co';
  const SUPABASE_KEY = 'sb_publishable_rD_tjSEwPHULTZMMvv1EpQ_sfJJGCl-';
  const demoMode = new URLSearchParams(location.search).get('demo') === '1';
  const roleNames = { owner: '老板', designer: '设计师', foreman: '工长', factory_manager: '厂长' };
  const internalRoles = { owner: 'owner', designer: 'sales', foreman: 'foreman', factory_manager: 'factory' };
  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  window.anjuAuth = { client, demoMode, roleNames, internalRoles };
  let loadedPrincipal = '';

  function roleFromUser(user) {
    return user?.app_metadata?.role || '';
  }

  function ensureShellState() {
    const shell = document.querySelector('.shell');
    if (!shell) return;
    shell.classList.toggle('auth-pending', !demoMode && !window.__ANJU_AUTH__);
  }

  function renderLogin(message = '') {
    if (demoMode || document.getElementById('authGate')) return;
    document.body.classList.add('auth-required');
    document.body.insertAdjacentHTML('afterbegin', `
      <div id="authGate" class="auth-gate" role="dialog" aria-modal="true" aria-labelledby="authGateTitle">
        <div class="auth-card">
          <div class="auth-brand"><img class="brand-icon" src="assets/brand/yijiang-icon-512.png?v=20261017014356" alt="艺匠全屋定制"><div><strong>艺匠全屋定制</strong><small>整装 · 定制 · 工厂</small></div></div>
          <div class="auth-kicker">员工登录</div>
          <h1 id="authGateTitle">登录工作台</h1>
          <p class="auth-help">使用公司分配的账号密码登录，系统会按角色显示可用模块。</p>
          <form id="authForm" novalidate>
            <label class="auth-field"><span>账号</span><input name="email" type="email" autocomplete="username" placeholder="员工账号" required></label>
            <label class="auth-field"><span>密码</span><input name="password" type="password" autocomplete="current-password" placeholder="登录密码" required></label>
            <div id="authError" class="auth-error" role="alert">${message}</div>
            <button class="auth-submit" type="submit">登录</button>
          </form>
          <div class="auth-foot">权限由服务器控制；登录后无法通过页面切换成其他角色。</div>
        </div>
      </div>`);
    document.getElementById('authForm')?.addEventListener('submit', async (event) => {
      event.preventDefault();
      const form = event.currentTarget;
      const submit = form.querySelector('button[type=submit]');
      const error = document.getElementById('authError');
      error.textContent = '';
      submit.disabled = true;
      submit.textContent = '登录中…';
      const data = new FormData(form);
      const { data: result, error: signInError } = await client.auth.signInWithPassword({
        email: String(data.get('email') || '').trim(),
        password: String(data.get('password') || '')
      });
      if (signInError || !result.user) {
        error.textContent = signInError?.message || '账号或密码不正确';
        submit.disabled = false;
        submit.textContent = '登录';
        return;
      }
      await completeLogin(result.user);
    });
  }

  function renderUserBar(user, role) {
    const actions = document.querySelector('.top-actions');
    if (!actions || document.getElementById('authUserMenu')) return;
    const email = user.email || '';
    actions.insertAdjacentHTML('beforeend', `<div id="authUserMenu" class="auth-user-menu"><span class="auth-role">${roleNames[role] || '员工'}</span><span class="auth-email">${email}</span><button type="button" id="authProfile" class="auth-profile">个人中心</button><button type="button" id="authLogout" class="auth-logout">退出</button></div>`);
    document.getElementById('authProfile')?.addEventListener('click', openProfile);
    document.getElementById('authLogout')?.addEventListener('click', async () => {
      const { error } = await client.auth.signOut();
      if (!error) location.reload();
    });
    document.querySelector('.role-select-wrap')?.classList.add('auth-hidden');
    const sideFoot = document.querySelector('.side-foot');
    if (sideFoot) {
      sideFoot.classList.remove('auth-hidden');
      sideFoot.innerHTML = '<span class="pulse"></span><span><b>云端正式版</b><small>真实数据 · 角色隔离</small></span>';
    }
    document.querySelector('.demo-strip')?.classList.add('auth-cloud-strip');
    const strip = document.querySelector('.demo-strip');
    if (strip) strip.innerHTML = '<span>●</span> 云端权限版：当前登录身份由服务器分配，数据权限按角色隔离。';
  }

  function closeProfile() {
    document.getElementById('authProfileDialog')?.remove();
  }

  function openProfile() {
    if (!window.__ANJU_AUTH__?.user) return;
    closeProfile();
    const profileEmail = String(window.__ANJU_AUTH__.user.email || '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
    document.body.insertAdjacentHTML('beforeend', `
      <div id="authProfileDialog" class="auth-profile-overlay" role="dialog" aria-modal="true" aria-labelledby="authProfileTitle">
        <section class="auth-profile-card">
          <button type="button" class="auth-profile-close" aria-label="关闭">×</button>
          <div class="auth-kicker">个人中心</div>
          <h2 id="authProfileTitle">修改密码</h2>
          <p class="auth-help">${profileEmail}<br>修改后请使用新密码登录。新密码至少 10 位。</p>
          <form id="authPasswordForm" novalidate>
            <label class="auth-field"><span>当前密码</span><input name="currentPassword" type="password" autocomplete="current-password" required></label>
            <label class="auth-field"><span>新密码</span><input name="newPassword" type="password" autocomplete="new-password" minlength="10" required></label>
            <label class="auth-field"><span>确认新密码</span><input name="confirmPassword" type="password" autocomplete="new-password" minlength="10" required></label>
            <div id="authPasswordError" class="auth-error" role="alert"></div>
            <div class="auth-profile-actions"><button type="button" class="btn" data-profile-close>取消</button><button class="auth-submit" type="submit">保存新密码</button></div>
          </form>
        </section>
      </div>`);
    document.querySelector('#authProfileDialog .auth-profile-close')?.addEventListener('click', closeProfile);
    document.querySelector('#authProfileDialog [data-profile-close]')?.addEventListener('click', closeProfile);
    document.getElementById('authProfileDialog')?.addEventListener('click', event => {
      if (event.target.id === 'authProfileDialog') closeProfile();
    });
    document.getElementById('authPasswordForm')?.addEventListener('submit', async event => {
      event.preventDefault();
      const form = event.currentTarget;
      const submit = form.querySelector('button[type=submit]');
      const error = document.getElementById('authPasswordError');
      const values = new FormData(form);
      const currentPassword = String(values.get('currentPassword') || '');
      const newPassword = String(values.get('newPassword') || '');
      const confirmPassword = String(values.get('confirmPassword') || '');
      error.textContent = '';
      if (newPassword.length < 10) { error.textContent = '新密码至少需要 10 位。'; return; }
      if (newPassword !== confirmPassword) { error.textContent = '两次输入的新密码不一致。'; return; }
      submit.disabled = true;
      submit.textContent = '正在更新…';
      try {
        const email = window.__ANJU_AUTH__?.user?.email;
        if (!email || !currentPassword) throw new Error('请填写当前密码。');
        const { error: verifyError } = await client.auth.signInWithPassword({ email, password: currentPassword });
        if (verifyError) throw new Error('当前密码验证失败，请检查后重试。');
        const { error: updateError } = await client.auth.updateUser({ password: newPassword });
        if (updateError) throw new Error('密码更新失败，请稍后重试。');
        form.reset();
        closeProfile();
        const notice = document.getElementById('toast');
        if (notice) { notice.textContent = '密码已更新'; notice.classList.add('show'); setTimeout(() => notice.classList.remove('show'), 2600); }
        window.dispatchEvent(new CustomEvent('anju:password-updated'));
      } catch (failure) {
        error.textContent = failure?.message || '密码更新失败，请稍后重试。';
      } finally {
        if (submit.isConnected) { submit.disabled = false; submit.textContent = '保存新密码'; }
      }
    });
    document.querySelector('#authProfileDialog input')?.focus();
  }

  async function completeLogin(user) {
    // Discard role-scoped page caches when another account signs in.
    // Token refresh for the same account keeps the current editor intact.
    if (loadedPrincipal && loadedPrincipal !== user.id) { location.reload(); return; }
    loadedPrincipal = user.id;
    const role = roleFromUser(user);
    if (!roleNames[role]) {
      await client.auth.signOut();
      const gate = document.getElementById('authGate');
      if (gate) gate.querySelector('#authError').textContent = '账号尚未分配业务角色，请联系老板管理员。';
      return;
    }
    window.__ANJU_AUTH__ = { client, user, role, internalRole: internalRoles[role] };
    document.body.classList.remove('auth-required');
    document.getElementById('authGate')?.remove();
    renderUserBar(user, role);
    ensureShellState();
    window.dispatchEvent(new CustomEvent('anju:auth-ready', { detail: window.__ANJU_AUTH__ }));
  }

  async function boot() {
    if (demoMode) {
      document.body.classList.add('demo-mode');
      return;
    }
    ensureShellState();
    const { data } = await client.auth.getSession();
    if (data.session?.user) await completeLogin(data.session.user);
    else renderLogin();
    client.auth.onAuthStateChange((_event, session) => {
      if (session?.user) completeLogin(session.user);
      else {
        window.__ANJU_AUTH__ = null;
        document.getElementById('authUserMenu')?.remove();
        renderLogin();
      }
    });
  }

  window.addEventListener('DOMContentLoaded', boot, { once: true });
})();
