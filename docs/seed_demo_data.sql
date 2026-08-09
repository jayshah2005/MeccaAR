-- Demo seed for Mecca Hunt — users, live map pins, and leaderboard claims.
-- Safe to re-run: clears previous seed rows tagged by fixed UUIDs, then inserts.

begin;

-- Fixed IDs so the seed is idempotent.
-- Users
-- jay / loic = primary hackathon accounts
-- others = demo hunters for leaderboard volume

delete from hunt_claims where hunter_id in (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    '99999999-9999-9999-9999-999999999999',
    '88888888-8888-8888-8888-888888888888'
) or mecca_id in (
    select id from meccas where owner_id in (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        '99999999-9999-9999-9999-999999999999',
        '88888888-8888-8888-8888-888888888888'
    )
);

delete from mecca_face_photos where mecca_id in (
    select id from meccas where owner_id in (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        '99999999-9999-9999-9999-999999999999',
        '88888888-8888-8888-8888-888888888888'
    )
);

delete from mecca_world_maps where mecca_id in (
    select id from meccas where owner_id in (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        'cccccccc-cccc-cccc-cccc-cccccccccccc',
        'dddddddd-dddd-dddd-dddd-dddddddddddd',
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'ffffffff-ffff-ffff-ffff-ffffffffffff',
        '99999999-9999-9999-9999-999999999999',
        '88888888-8888-8888-8888-888888888888'
    )
);

delete from meccas where owner_id in (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    '99999999-9999-9999-9999-999999999999',
    '88888888-8888-8888-8888-888888888888'
);

delete from users where id in (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'cccccccc-cccc-cccc-cccc-cccccccccccc',
    'dddddddd-dddd-dddd-dddd-dddddddddddd',
    'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
    'ffffffff-ffff-ffff-ffff-ffffffffffff',
    '99999999-9999-9999-9999-999999999999',
    '88888888-8888-8888-8888-888888888888'
);

insert into users (id, username, created_at) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'jay',   now() - interval '40 days'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'loic',  now() - interval '40 days'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'alex',  now() - interval '35 days'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'mira',  now() - interval '30 days'),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'kai',   now() - interval '28 days'),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'sam',   now() - interval '25 days'),
    ('99999999-9999-9999-9999-999999999999', 'reno',  now() - interval '20 days'),
    ('88888888-8888-8888-8888-888888888888', 'dove',  now() - interval '18 days');

-- Active outdoor Meccas at exact NYC landmarks (GPS / geo hunt).
-- Sign in as jay or loic to hunt the ones you don't own.
insert into meccas (
    id, owner_id, name, latitude, longitude, altitude,
    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
    placement_mode, created_at, state
) values
    -- Washington Square Arch
    ('a1000000-0000-4000-8000-000000000001',
     'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
     'Arch Sentinel',
     40.730833, -73.997500, 12.0,
     28, 0, 15, 0.20, 0.85, 0.45,
     'geo', now() - interval '3 days', 'active'),
    -- Washington Square Park fountain
    ('a1000000-0000-4000-8000-000000000002',
     'cccccccc-cccc-cccc-cccc-cccccccccccc',
     'Fountain Sprite',
     40.730820, -73.997330, 11.5,
     25, 0, -20, 0.95, 0.55, 0.20,
     'geo', now() - interval '1 day', 'active'),
    -- NYU Bobst Library steps
    ('a1000000-0000-4000-8000-000000000003',
     'dddddddd-dddd-dddd-dddd-dddddddddddd',
     'Bobst Guardian',
     40.729544, -73.997177, 14.0,
     30, 5, 40, 0.35, 0.55, 0.95,
     'geo', now() - interval '6 days', 'active'),
    -- Strand Bookstore corner
    ('a1000000-0000-4000-8000-000000000004',
     'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
     'Strand Stalker',
     40.733286, -73.990837, 10.0,
     24, 0, 0, 0.90, 0.25, 0.35,
     'geo', now() - interval '11 days', 'active'),
    -- Union Square north plaza
    ('a1000000-0000-4000-8000-000000000005',
     'ffffffff-ffff-ffff-ffff-ffffffffffff',
     'Union Scout',
     40.735863, -73.991084, 11.0,
     26, 0, 90, 0.15, 0.75, 0.80,
     'geo', now() - interval '2 days', 'active'),
    -- Bryant Park lawn
    ('a1000000-0000-4000-8000-000000000006',
     '99999999-9999-9999-9999-999999999999',
     'Bryant Phantom',
     40.753597, -73.983233, 16.0,
     27, 0, -45, 0.75, 0.85, 0.25,
     'geo', now() - interval '8 days', 'active'),
    -- Jay's own active hide (My Meccas)
    ('a1000000-0000-4000-8000-000000000007',
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
     'jay''s Courtyard Mecca',
     40.730950, -73.996900, 12.5,
     25, 0, 10, 1.0, 0.85, 0.20,
     'geo', now() - interval '5 hours', 'active'),
    -- Loic's own active hide
    ('a1000000-0000-4000-8000-000000000008',
     'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
     'loic''s Rooftop Mecca',
     40.731200, -73.996500, 22.0,
     29, 0, -10, 0.40, 0.90, 0.70,
     'geo', now() - interval '12 hours', 'active');

-- Claimed Meccas (history) to power a lively leaderboard.
insert into meccas (
    id, owner_id, name, latitude, longitude, altitude,
    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
    placement_mode, created_at, state
) values
    ('b2000000-0000-4000-8000-000000000001',
     'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Claimed Clocktower',
     40.741000, -73.989500, 20, 25, 0, 0, 0.8, 0.3, 0.3,
     'geo', now() - interval '22 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000002',
     'dddddddd-dddd-dddd-dddd-dddddddddddd', 'Claimed Alley Cat',
     40.728500, -73.994000, 9, 25, 0, 0, 0.2, 0.7, 0.4,
     'geo', now() - interval '18 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000003',
     'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'Claimed Fire Escape',
     40.736200, -73.995800, 18, 25, 0, 0, 0.3, 0.4, 0.9,
     'geo', now() - interval '14 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000004',
     'ffffffff-ffff-ffff-ffff-ffffffffffff', 'Claimed Stoop',
     40.732800, -73.998100, 11, 25, 0, 0, 0.9, 0.7, 0.2,
     'geo', now() - interval '9 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000005',
     '99999999-9999-9999-9999-999999999999', 'Claimed Kiosk',
     40.739400, -73.988700, 10, 25, 0, 0, 0.5, 0.8, 0.6,
     'geo', now() - interval '4 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000006',
     '88888888-8888-8888-8888-888888888888', 'Claimed Bench',
     40.734100, -73.990200, 10, 25, 0, 0, 0.6, 0.2, 0.7,
     'geo', now() - interval '2 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000007',
     'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Claimed Lamp Post',
     40.731800, -73.993500, 12, 25, 0, 0, 0.1, 0.9, 0.5,
     'geo', now() - interval '16 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000008',
     'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Claimed Hydrant',
     40.729900, -73.991800, 10, 25, 0, 0, 0.95, 0.4, 0.1,
     'geo', now() - interval '7 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000009',
     'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Claimed Newsstand',
     40.737500, -73.996200, 10, 25, 0, 0, 0.4, 0.6, 0.95,
     'geo', now() - interval '25 days', 'claimed'),
    ('b2000000-0000-4000-8000-00000000000a',
     'dddddddd-dddd-dddd-dddd-dddddddddddd', 'Claimed Bike Rack',
     40.733700, -73.994600, 10, 25, 0, 0, 0.7, 0.15, 0.55,
     'geo', now() - interval '12 days', 'claimed');

-- Leaderboard claims (awarded_points match age-tier scoring).
insert into hunt_claims (mecca_id, hunter_id, claimed_at, awarded_points) values
    ('b2000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() - interval '20 days', 300),
    ('b2000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() - interval '17 days', 200),
    ('b2000000-0000-4000-8000-000000000003', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now() - interval '13 days', 200),
    ('b2000000-0000-4000-8000-000000000004', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now() - interval '8 days', 100),
    ('b2000000-0000-4000-8000-000000000005', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now() - interval '3 days', 100),
    ('b2000000-0000-4000-8000-000000000006', 'cccccccc-cccc-cccc-cccc-cccccccccccc', now() - interval '1 day', 100),
    ('b2000000-0000-4000-8000-000000000007', 'dddddddd-dddd-dddd-dddd-dddddddddddd', now() - interval '15 days', 200),
    ('b2000000-0000-4000-8000-000000000008', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', now() - interval '6 days', 100),
    ('b2000000-0000-4000-8000-000000000009', 'ffffffff-ffff-ffff-ffff-ffffffffffff', now() - interval '24 days', 300),
    ('b2000000-0000-4000-8000-00000000000a', '99999999-9999-9999-9999-999999999999', now() - interval '11 days', 200),
    ('b2000000-0000-4000-8000-000000000001', '88888888-8888-8888-8888-888888888888', now() - interval '19 days', 300),
    ('b2000000-0000-4000-8000-000000000002', 'cccccccc-cccc-cccc-cccc-cccccccccccc', now() - interval '16 days', 200),
    ('b2000000-0000-4000-8000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', now() - interval '14 days', 200),
    ('b2000000-0000-4000-8000-000000000009', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', now() - interval '23 days', 300);

commit;

-- Quick summary
select username, points, finds
from (
    select u.username,
           coalesce(sum(c.awarded_points), 0)::int as points,
           count(c.id)::int as finds
    from users u
    left join hunt_claims c on c.hunter_id = u.id
    group by u.username
) s
order by points desc, username;

select name, latitude, longitude, state, placement_mode
from meccas
where state = 'active'
order by name;
