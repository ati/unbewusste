create table if not exists emails (
  id integer primary key,
  from_email text not null,
  from_hash text unique not null,
  created_at integer not null
);
