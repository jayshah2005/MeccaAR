-- Mecca Hunt — Neon Postgres schema
-- Run this once against your Neon database (SQL editor or psql).

create extension if not exists pgcrypto;

create table if not exists users (
    id         uuid primary key default gen_random_uuid(),
    username   text unique not null,
    created_at timestamptz not null default now()
);

create table if not exists meccas (
    id         uuid primary key default gen_random_uuid(),
    owner_id   uuid not null references users(id) on delete cascade,
    name       text not null,
    latitude   double precision not null,
    longitude  double precision not null,
    altitude   double precision,
    -- Owner-chosen appearance, persisted so the Mecca renders identically for
    -- everyone who finds it. size in mm, rotations in degrees, tint 0..1 sRGB.
    size_mm    double precision not null default 25,
    x_rotation double precision not null default 0,
    y_rotation double precision not null default 0,
    tint_red   double precision not null default 1,
    tint_green double precision not null default 1,
    tint_blue  double precision not null default 1,
    -- Bundled USDZ pose identifier. Existing Meccas remain on the classic pose.
    pose       text not null default 'classic',
    -- 'world_map' (indoor/LiDAR AR map) or 'geo' (outdoor ARGeoTracking).
    placement_mode text not null default 'world_map',
    created_at timestamptz not null default now(),
    state      text not null default 'active'
);

-- Safe migration for databases created before pose selection was introduced.
alter table meccas add column if not exists pose text not null default 'classic';

create table if not exists hunt_claims (
    id            uuid primary key default gen_random_uuid(),
    mecca_id      uuid not null references meccas(id) on delete cascade,
    hunter_id     uuid not null references users(id) on delete cascade,
    claimed_at    timestamptz not null default now(),
    awarded_points int not null default 100,
    unique (mecca_id, hunter_id)
);

-- Centimeter-accurate visual positioning. Each row stores a serialized,
-- zlib-compressed ARKit ARWorldMap (base64 text) for one Mecca, letting a
-- hunter's device relocalize to the exact spot it was hidden. GPS is only a
-- coarse gate; this is what delivers cm-level accuracy.
create table if not exists mecca_world_maps (
    mecca_id   uuid primary key references meccas(id) on delete cascade,
    data       text not null,
    created_at timestamptz not null default now()
);

-- Optional face photo (JPEG, base64 text) chosen while hiding a Mecca, so
-- hunters see the same face overlay when they find it.
create table if not exists mecca_face_photos (
    mecca_id   uuid primary key references meccas(id) on delete cascade,
    data       text not null,
    created_at timestamptz not null default now()
);

create index if not exists meccas_owner_idx on meccas(owner_id);
create index if not exists claims_hunter_idx on hunt_claims(hunter_id);
