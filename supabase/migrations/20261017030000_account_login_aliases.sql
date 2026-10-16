create table if not exists public.auth_login_aliases (
  user_id uuid primary key references auth.users(id) on delete cascade,
  login_name text not null unique,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint auth_login_aliases_format check (login_name ~ '^yj18568888318-[0-9]{2,}$')
);

alter table public.auth_login_aliases enable row level security;
revoke all on public.auth_login_aliases from anon, authenticated;
grant all on public.auth_login_aliases to service_role;
