-- Demo seed for Mecca Hunt — users, live map pins, and leaderboard claims.
-- Safe to re-run. Uses fixed Mecca UUIDs; users are upserted by username so
-- existing hackathon accounts (jay/loic) keep their real IDs.

begin;

-- Clear previous seed Meccas (and dependent rows) by fixed IDs only.
delete from hunt_claims where mecca_id in (
    select id from meccas where id::text like 'a1000000-%' or id::text like 'b2000000-%'
);
delete from mecca_face_photos where mecca_id::text like 'a1000000-%' or mecca_id::text like 'b2000000-%';
delete from mecca_world_maps where mecca_id::text like 'a1000000-%' or mecca_id::text like 'b2000000-%';
delete from meccas where id::text like 'a1000000-%' or id::text like 'b2000000-%';

-- Ensure demo usernames exist (do not overwrite real account UUIDs).
insert into users (id, username, created_at) values
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'jay',   now() - interval '40 days'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'loic',  now() - interval '40 days'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'alex',  now() - interval '35 days'),
    ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'mira',  now() - interval '30 days'),
    ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'kai',   now() - interval '28 days'),
    ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'sam',   now() - interval '25 days'),
    ('99999999-9999-9999-9999-999999999999', 'reno',  now() - interval '20 days'),
    ('88888888-8888-8888-8888-888888888888', 'dove',  now() - interval '18 days'),
    ('77777777-7777-7777-7777-777777777777', 'nova',  now() - interval '16 days'),
    ('66666666-6666-6666-6666-666666666666', 'rex',   now() - interval '14 days'),
    ('55555555-5555-5555-5555-555555555555', 'ivy',   now() - interval '12 days'),
    ('44444444-4444-4444-4444-444444444444', 'oz',    now() - interval '10 days'),
    ('33333333-3333-3333-3333-333333333333', 'june',  now() - interval '8 days')
on conflict (username) do nothing;

-- Active outdoor Meccas across NYC (owner resolved by username).
insert into meccas (
    id, owner_id, name, latitude, longitude, altitude,
    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
    pose, placement_mode, created_at, state
) values
    ('a1000000-0000-4000-8000-000000000001',
     (select id from users where username = 'loic'),
     'Arch Sentinel', 40.730833, -73.997500, 12.0,
     28, 0, 15, 0.20, 0.85, 0.45, 'classic', 'geo', now() - interval '3 days', 'active'),
    ('a1000000-0000-4000-8000-000000000002',
     (select id from users where username = 'alex'),
     'Fountain Sprite', 40.730820, -73.997330, 11.5,
     25, 0, -20, 0.95, 0.55, 0.20, 'pose_09', 'geo', now() - interval '1 day', 'active'),
    ('a1000000-0000-4000-8000-000000000003',
     (select id from users where username = 'mira'),
     'Bobst Guardian', 40.729544, -73.997177, 14.0,
     30, 5, 40, 0.35, 0.55, 0.95, 'pose_11', 'geo', now() - interval '6 days', 'active'),
    ('a1000000-0000-4000-8000-000000000004',
     (select id from users where username = 'kai'),
     'Strand Stalker', 40.733286, -73.990837, 10.0,
     24, 0, 0, 0.90, 0.25, 0.35, 'classic', 'geo', now() - interval '11 days', 'active'),
    ('a1000000-0000-4000-8000-000000000005',
     (select id from users where username = 'sam'),
     'Union Scout', 40.735863, -73.991084, 11.0,
     26, 0, 90, 0.15, 0.75, 0.80, 'pose_14', 'geo', now() - interval '2 days', 'active'),
    ('a1000000-0000-4000-8000-000000000006',
     (select id from users where username = 'reno'),
     'Bryant Phantom', 40.753597, -73.983233, 16.0,
     27, 0, -45, 0.75, 0.85, 0.25, 'pose_10', 'geo', now() - interval '8 days', 'active'),
    ('a1000000-0000-4000-8000-000000000007',
     (select id from users where username = 'jay'),
     'jay''s Courtyard Mecca', 40.730950, -73.996900, 12.5,
     25, 0, 10, 1.0, 0.85, 0.20, 'classic', 'geo', now() - interval '5 hours', 'active'),
    ('a1000000-0000-4000-8000-000000000008',
     (select id from users where username = 'loic'),
     'loic''s Rooftop Mecca', 40.731200, -73.996500, 22.0,
     29, 0, -10, 0.40, 0.90, 0.70, 'pose_12', 'geo', now() - interval '12 hours', 'active'),
    ('a1000000-0000-4000-8000-000000000009',
     (select id from users where username = 'nova'),
     'Flatiron Lookout', 40.741061, -73.989699, 12.0,
     26, 0, 25, 0.85, 0.35, 0.55, 'pose_15', 'geo', now() - interval '4 days', 'active'),
    ('a1000000-0000-4000-8000-00000000000a',
     (select id from users where username = 'rex'),
     'Madison Shade', 40.742054, -73.987831, 11.0,
     24, 0, -30, 0.25, 0.65, 0.90, 'classic', 'geo', now() - interval '7 days', 'active'),
    ('a1000000-0000-4000-8000-00000000000b',
     (select id from users where username = 'ivy'),
     'High Line Haunt', 40.739445, -74.006722, 18.0,
     28, 0, 60, 0.55, 0.90, 0.40, 'pose_13', 'geo', now() - interval '9 days', 'active'),
    ('a1000000-0000-4000-8000-00000000000c',
     (select id from users where username = 'oz'),
     'Chelsea Whisper', 40.742424, -74.006103, 10.0,
     25, 0, 0, 0.95, 0.70, 0.25, 'pose_16', 'geo', now() - interval '5 days', 'active'),
    ('a1000000-0000-4000-8000-00000000000d',
     (select id from users where username = 'june'),
     'SoHo Cast', 40.723301, -73.998672, 10.0,
     27, 0, 120, 0.70, 0.25, 0.85, 'classic', 'geo', now() - interval '13 days', 'active'),
    ('a1000000-0000-4000-8000-00000000000e',
     (select id from users where username = 'alex'),
     'Columbus Gate', 40.715053, -73.998123, 9.0,
     23, 0, -15, 0.30, 0.80, 0.55, 'pose_17', 'geo', now() - interval '10 days', 'active'),
    ('a1000000-0000-4000-8000-00000000000f',
     (select id from users where username = 'mira'),
     'Pier Sprite', 40.702568, -73.996225, 5.0,
     29, 0, 45, 0.15, 0.55, 0.95, 'pose_18', 'geo', now() - interval '15 days', 'active'),
    ('a1000000-0000-4000-8000-000000000010',
     (select id from users where username = 'kai'),
     'Bethesda Echo', 40.774089, -73.970869, 20.0,
     30, 0, -80, 0.45, 0.85, 0.75, 'pose_19', 'geo', now() - interval '16 days', 'active'),
    ('a1000000-0000-4000-8000-000000000011',
     (select id from users where username = 'sam'),
     'TKTS Blink', 40.759011, -73.984472, 14.0,
     22, 0, 200, 1.0, 0.35, 0.15, 'classic', 'geo', now() - interval '20 hours', 'active'),
    ('a1000000-0000-4000-8000-000000000012',
     (select id from users where username = 'reno'),
     'Low Steps Mecca', 40.807535, -73.962573, 35.0,
     26, 0, 10, 0.20, 0.45, 0.90, 'pose_09', 'geo', now() - interval '14 days', 'active'),
    ('a1000000-0000-4000-8000-000000000013',
     (select id from users where username = 'dove'),
     'Tompkins Trickster', 40.726453, -73.981834, 10.0,
     25, 0, -55, 0.80, 0.50, 0.20, 'pose_11', 'geo', now() - interval '18 hours', 'active'),
    ('a1000000-0000-4000-8000-000000000014',
     (select id from users where username = 'nova'),
     'Terminal Ghost', 40.752726, -73.977229, 15.0,
     28, 0, 75, 0.60, 0.60, 0.95, 'pose_10', 'geo', now() - interval '21 days', 'active'),
    ('a1000000-0000-4000-8000-000000000015',
     (select id from users where username = 'rex'),
     'Battery Breeze', 40.703277, -74.017028, 4.0,
     24, 0, -100, 0.35, 0.90, 0.85, 'classic', 'geo', now() - interval '17 days', 'active'),
    ('a1000000-0000-4000-8000-000000000016',
     (select id from users where username = 'ivy'),
     'Domino Drift', 40.714508, -73.967461, 6.0,
     27, 0, 35, 0.90, 0.20, 0.55, 'pose_14', 'geo', now() - interval '19 days', 'active'),
    ('a1000000-0000-4000-8000-000000000017',
     (select id from users where username = 'jay'),
     'Astor Cube Watch', 40.729643, -73.991226, 11.0,
     25, 0, 5, 0.95, 0.80, 0.30, 'pose_12', 'geo', now() - interval '2 days', 'active'),
    ('a1000000-0000-4000-8000-000000000018',
     (select id from users where username = 'loic'),
     'St Marks Shadow', 40.729492, -73.989044, 10.5,
     26, 0, -25, 0.25, 0.95, 0.60, 'pose_15', 'geo', now() - interval '3 days', 'active');

insert into meccas (
    id, owner_id, name, latitude, longitude, altitude,
    size_mm, x_rotation, y_rotation, tint_red, tint_green, tint_blue,
    pose, placement_mode, created_at, state
) values
    ('b2000000-0000-4000-8000-000000000001', (select id from users where username = 'alex'),
     'Claimed Clocktower', 40.741000, -73.989500, 20, 25, 0, 0, 0.8, 0.3, 0.3,
     'classic', 'geo', now() - interval '22 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000002', (select id from users where username = 'mira'),
     'Claimed Alley Cat', 40.728500, -73.994000, 9, 25, 0, 0, 0.2, 0.7, 0.4,
     'classic', 'geo', now() - interval '18 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000003', (select id from users where username = 'kai'),
     'Claimed Fire Escape', 40.736200, -73.995800, 18, 25, 0, 0, 0.3, 0.4, 0.9,
     'classic', 'geo', now() - interval '14 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000004', (select id from users where username = 'sam'),
     'Claimed Stoop', 40.732800, -73.998100, 11, 25, 0, 0, 0.9, 0.7, 0.2,
     'classic', 'geo', now() - interval '9 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000005', (select id from users where username = 'reno'),
     'Claimed Kiosk', 40.739400, -73.988700, 10, 25, 0, 0, 0.5, 0.8, 0.6,
     'classic', 'geo', now() - interval '4 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000006', (select id from users where username = 'dove'),
     'Claimed Bench', 40.734100, -73.990200, 10, 25, 0, 0, 0.6, 0.2, 0.7,
     'classic', 'geo', now() - interval '2 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000007', (select id from users where username = 'loic'),
     'Claimed Lamp Post', 40.731800, -73.993500, 12, 25, 0, 0, 0.1, 0.9, 0.5,
     'classic', 'geo', now() - interval '16 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000008', (select id from users where username = 'jay'),
     'Claimed Hydrant', 40.729900, -73.991800, 10, 25, 0, 0, 0.95, 0.4, 0.1,
     'classic', 'geo', now() - interval '7 days', 'claimed'),
    ('b2000000-0000-4000-8000-000000000009', (select id from users where username = 'alex'),
     'Claimed Newsstand', 40.737500, -73.996200, 10, 25, 0, 0, 0.4, 0.6, 0.95,
     'classic', 'geo', now() - interval '25 days', 'claimed'),
    ('b2000000-0000-4000-8000-00000000000a', (select id from users where username = 'mira'),
     'Claimed Bike Rack', 40.733700, -73.994600, 10, 25, 0, 0, 0.7, 0.15, 0.55,
     'classic', 'geo', now() - interval '12 days', 'claimed'),
    ('b2000000-0000-4000-8000-00000000000b', (select id from users where username = 'nova'),
     'Claimed Subway Gate', 40.750500, -73.993500, 8, 25, 0, 0, 0.2, 0.5, 0.8,
     'classic', 'geo', now() - interval '11 days', 'claimed'),
    ('b2000000-0000-4000-8000-00000000000c', (select id from users where username = 'rex'),
     'Claimed Food Cart', 40.758000, -73.985500, 12, 25, 0, 0, 0.9, 0.5, 0.1,
     'classic', 'geo', now() - interval '6 days', 'claimed'),
    ('b2000000-0000-4000-8000-00000000000d', (select id from users where username = 'ivy'),
     'Claimed Scaffold', 40.745200, -73.998800, 14, 25, 0, 0, 0.4, 0.8, 0.3,
     'classic', 'geo', now() - interval '27 days', 'claimed'),
    ('b2000000-0000-4000-8000-00000000000e', (select id from users where username = 'oz'),
     'Claimed Pier Post', 40.711800, -74.013200, 5, 25, 0, 0, 0.1, 0.7, 0.9,
     'classic', 'geo', now() - interval '8 days', 'claimed'),
    ('b2000000-0000-4000-8000-00000000000f', (select id from users where username = 'june'),
     'Claimed Bookstore Step', 40.733900, -73.990100, 10, 25, 0, 0, 0.75, 0.35, 0.55,
     'classic', 'geo', now() - interval '3 days', 'claimed');

insert into hunt_claims (mecca_id, hunter_id, claimed_at, awarded_points) values
    ('b2000000-0000-4000-8000-000000000001', (select id from users where username = 'jay'),  now() - interval '20 days', 300),
    ('b2000000-0000-4000-8000-000000000002', (select id from users where username = 'jay'),  now() - interval '17 days', 200),
    ('b2000000-0000-4000-8000-000000000003', (select id from users where username = 'loic'), now() - interval '13 days', 200),
    ('b2000000-0000-4000-8000-000000000004', (select id from users where username = 'loic'), now() - interval '8 days', 100),
    ('b2000000-0000-4000-8000-000000000005', (select id from users where username = 'loic'), now() - interval '3 days', 100),
    ('b2000000-0000-4000-8000-000000000006', (select id from users where username = 'alex'), now() - interval '1 day', 100),
    ('b2000000-0000-4000-8000-000000000007', (select id from users where username = 'mira'), now() - interval '15 days', 200),
    ('b2000000-0000-4000-8000-000000000008', (select id from users where username = 'kai'),  now() - interval '6 days', 100),
    ('b2000000-0000-4000-8000-000000000009', (select id from users where username = 'sam'),  now() - interval '24 days', 300),
    ('b2000000-0000-4000-8000-00000000000a', (select id from users where username = 'reno'), now() - interval '11 days', 200),
    ('b2000000-0000-4000-8000-000000000001', (select id from users where username = 'dove'), now() - interval '19 days', 300),
    ('b2000000-0000-4000-8000-000000000002', (select id from users where username = 'alex'), now() - interval '16 days', 200),
    ('b2000000-0000-4000-8000-000000000007', (select id from users where username = 'jay'),  now() - interval '14 days', 200),
    ('b2000000-0000-4000-8000-000000000009', (select id from users where username = 'loic'), now() - interval '23 days', 300),
    ('b2000000-0000-4000-8000-00000000000b', (select id from users where username = 'jay'),  now() - interval '10 days', 200),
    ('b2000000-0000-4000-8000-00000000000c', (select id from users where username = 'loic'), now() - interval '5 days', 100),
    ('b2000000-0000-4000-8000-00000000000d', (select id from users where username = 'nova'), now() - interval '26 days', 300),
    ('b2000000-0000-4000-8000-00000000000e', (select id from users where username = 'rex'),  now() - interval '7 days', 100),
    ('b2000000-0000-4000-8000-00000000000f', (select id from users where username = 'ivy'),  now() - interval '2 days', 100),
    ('b2000000-0000-4000-8000-00000000000b', (select id from users where username = 'june'), now() - interval '9 days', 100),
    ('b2000000-0000-4000-8000-00000000000c', (select id from users where username = 'oz'),   now() - interval '4 days', 100),
    ('b2000000-0000-4000-8000-000000000005', (select id from users where username = 'jay'),  now() - interval '3 days', 100),
    ('b2000000-0000-4000-8000-000000000006', (select id from users where username = 'loic'), now() - interval '1 day', 100),
    ('b2000000-0000-4000-8000-00000000000a', (select id from users where username = 'alex'), now() - interval '10 days', 200);

commit;

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

select count(*) as active_meccas from meccas where state = 'active';
