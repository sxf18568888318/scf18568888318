-- 修复：全屋定制「新建客户 / 编辑客户」被 RLS 拦截（42501）
--
-- 根因：api.custom_save_customer 经 SECURITY DEFINER 以 anju_custom_executor
-- 身份写入 public.customers。该角色在 customers 表上只有
--   reno_executor_customer_insert / reno_executor_customer_update
-- 两条写策略，且 with check 均要求 business_line in ('reno','reno+custom')。
-- 定制业务写入 business_line='custom'，因此每一户定制新客户/客户编辑都被拦。
-- （20261010024941 只给了 custom_executor_customers 的 SELECT 策略，漏了写策略。）
--
-- 本迁移为 anju_custom_executor 补齐 custom 业务线的 INSERT / UPDATE 策略，
-- 角色校验与既有 reno/custom 策略保持一致：老板全量，设计师仅限本人客户。

drop policy if exists custom_executor_customer_insert on public.customers;
create policy custom_executor_customer_insert on public.customers
  for insert to anju_custom_executor
  with check (
    business_line = 'custom'
    and (
      custom_private.request_role() = 'owner'
      or (custom_private.request_role() = 'designer' and owner_id = custom_private.request_uid())
    )
  );

drop policy if exists custom_executor_customer_update on public.customers;
create policy custom_executor_customer_update on public.customers
  for update to anju_custom_executor
  using (
    business_line = 'custom'
    and (
      custom_private.request_role() = 'owner'
      or (custom_private.request_role() = 'designer' and owner_id = custom_private.request_uid())
    )
  )
  with check (
    business_line = 'custom'
    and (
      custom_private.request_role() = 'owner'
      or (custom_private.request_role() = 'designer' and owner_id = custom_private.request_uid())
    )
  );
