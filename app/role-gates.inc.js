  // Final role checks run after every feature include so specialized renderers cannot bypass them.
  const rgCanAccessPrevious = canAccessPage;
  canAccessPage = function (moduleId, pageId) {
    // Factory users may enter the custom module only for the production-safe
    // inventory workspace. Keep its sales, catalog and BOM routes unavailable.
    if (role === 'factory' && moduleId === 'custom') return ['home', 'custom-procurement'].includes(pageId);
    if (role === 'factory' && moduleId === 'whole') return false;
    if (role === 'foreman' && moduleId === 'whole') return ['home', 'projects', 'reno-order-detail'].includes(pageId);
    if (role === 'sales' && moduleId === 'whole' && ['customer-detail', 'reno-order-detail'].includes(pageId)) return true;
    if (['quotes', 'quote', 'quotation'].includes(pageId) && !['owner', 'sales'].includes(role) && !(role === 'designer' && moduleId === 'whole')) return false;
    if (pageId === 'nw-finance' && role !== 'owner') return false;
    if (pageId === 'expenses' && role !== 'owner') return false;
    if (pageId === 'custom-finance' && role !== 'owner') return false;
    return rgCanAccessPrevious(moduleId, pageId);
  };

  const rgWholeHomePrevious = wholeHome;
  wholeHome = function () {
    // Foremen get the actual worksite progress page as their landing view, with no quote or finance cards.
    if (role === 'foreman') return projects();
    return rgStripForbiddenCards(rgWholeHomePrevious());
  };

  function rgStripForbiddenCards(html) {
    const template = document.createElement('template');
    template.innerHTML = html;
    template.content.querySelectorAll('[data-route],[data-page],[data-action]').forEach(element => {
      const route = element.dataset.route || '';
      const pageId = element.dataset.page || '';
      const actionId = element.dataset.action || '';
      let denied = false;
      if (pageId) denied = !canAccessPage(module, pageId);
      if (route) {
        const parts = route.split('/');
        const routeModule = ['whole', 'custom', 'factory'].includes(parts[0]) ? parts[0] : module;
        const routePage = parts[1] || 'home';
        denied = denied || !canAccessPage(routeModule, routePage);
        if (/quote/i.test(route) && !['owner', 'sales'].includes(role)) denied = true;
        if (/finance|expenses/i.test(route) && role !== 'owner') denied = true;
      }
      if (['nw-finance', 'rx-finance'].includes(actionId) && role !== 'owner') denied = true;
      if (denied) (element.closest('.metric,.fo-entry,.module-card,.quote-module-card,.whole-action-shell') || element).remove();
    });
    return template.innerHTML;
  }

  const rgCustomHomePrevious = customHome;
  customHome = function () { return rgStripForbiddenCards(rgCustomHomePrevious()); };
  const rgFactoryHomePrevious = factoryHome;
  factoryHome = function () { return rgStripForbiddenCards(rgFactoryHomePrevious()); };

  const rgRenderPrevious = render;
  render = function () {
    const factoryRenoBlocked = role === 'factory' && module === 'whole';
    const foremanBlocked = role === 'foreman' && module === 'whole' && ['nw-finance', 'finance', 'reports', 'quotes', 'quote', 'quotation', 'customers', 'customer-detail'].includes(page);
    const factoryBlocked = role === 'factory' && ((module === 'factory' && page === 'expenses') || (module === 'custom' && page === 'custom-finance'));
    const nonOwnerCustomFinance = module === 'custom' && page === 'custom-finance' && role !== 'owner';
    const quoteBlocked = ['quotes', 'quote', 'quotation'].includes(page) && !['owner', 'sales'].includes(role);
    if (factoryRenoBlocked || foremanBlocked || factoryBlocked || quoteBlocked || nonOwnerCustomFinance) {
      toast('无权限访问此页面，已返回可访问的工作台。');
      if (role === 'foreman') { module = 'whole'; page = 'projects'; }
      else if (role === 'factory') { module = factoryRenoBlocked ? 'factory' : factoryBlocked && module === 'custom' ? 'custom' : 'factory'; page = 'home'; }
      else if (role === 'sales' && nonOwnerCustomFinance) { module = 'custom'; page = 'home'; }
      else { module = 'whole'; page = 'home'; }
    }
    const result = rgRenderPrevious();
    // Direct routes, bookmarks, and first entry all trigger the same cloud load as sidebar clicks.
    if (module === 'custom' && page === 'custom-procurement' && ['owner', 'factory'].includes(role)) {
      if (cpClient() && !cp.loaded && !cp.loading) cpLoad();
    }
    if (module === 'custom' && page === 'custom-finance' && role === 'owner') {
      if (cpClient() && !cp.finance.loaded && !cp.finance.loading) cpLoadFinance();
    }
    return result;
  };

  // Future Supabase-backed renovation finance readers and RPCs must enforce RLS/role checks in the database.
