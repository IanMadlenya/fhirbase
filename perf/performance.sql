-- #import ./perf_schema.sql

func! random(a numeric, b numeric) RETURNS numeric
  SELECT ceil(a + (b - a) * random())::numeric;

func random_elem(a anyarray) RETURNS anyelement
  SELECT a[floor(RANDOM() * array_length(a, 1))];

func! random_date() RETURNS text
  SELECT this.random(1900, 2010)::text
           || '-'
           || lpad(this.random(1, 12)::text, 2, '0')
           || '-'
           || lpad(this.random(1, 28)::text, 2, '0');

func! random_phone() RETURNS text
  SELECT '+' || this.random(1, 12)::text ||
         ' (' || this.random(1, 999)::text || ') ' ||
         lpad(this.random(1, 999)::text, 3, '0') ||
         '-' ||
         lpad(this.random(1, 99)::text, 2, '0') ||
         '-' ||
         lpad(this.random(1, 99)::text, 2, '0')

-- TODO: improve generator
--       improve patient resource (add adress etc.)
--       add more resources (encounter, order etc.)
func! insert_patients(_total_count_ integer, _offset_ integer) RETURNS bigint
  WITH temp_patient_data as (
    SELECT * from temp.patient_names
     OFFSET _offset_
     LIMIT _total_count_
  ), patient_data as (
    select temp_patient_data.first_name as given_name,
           temp_patient_data.last_name as family_name,
           temp_patient_data.sex as gender,
           this.random_date() as birth_date,
           this.random_phone() as phone,
           temp_patient_data.language_code as language_code,
           temp_patient_data.language_name as language_name,
           temp_patient_data.street_name as street_name
    from temp_patient_data
  ), inserted as (
    INSERT into patient (logical_id, version_id, content)
    SELECT obj->>'id', obj#>>'{meta,versionId}', obj
    FROM (
      SELECT
        json_build_object(
         'id', gen_random_uuid(),
         'meta', json_build_object(
            'versionId', gen_random_uuid(),
            'lastUpdated', CURRENT_TIMESTAMP
          ),
         'resourceType', 'Patient',
         'gender', gender,
         'birthDate', birth_date,
         'name', ARRAY[
           json_build_object(
            'given', ARRAY[given_name],
            'family', ARRAY[family_name]
           )
         ],
         'telecom', ARRAY[
           json_build_object(
            'system', 'phone',
            'value', phone,
            'use', 'home'
           )
         ],
         'address', ARRAY[
           json_build_object(
             'use', 'home',
             'line', ARRAY[street_name || ' ' || this.random(0, 100)::text],
             'city', 'Amsterdam',
             'postalCode', '1024 RJ',
             'country', 'NLD'
           )
         ],
         'communication', ARRAY[
           json_build_object(
             'language',
             json_build_object(
               'coding', ARRAY[
                 json_build_object(
                   'system', 'urn:ietf:bcp:47',
                   'code', language_code,
                   'display', language_name
                 )
               ],
               'text', language_name
             ),
             'preferred', TRUE
           )
         ]
        )::jsonb as obj
        FROM patient_data
        LIMIT _total_count_
    ) _
    RETURNING logical_id
  )
  select count(*) inserted;

\timing
\set batch_size `echo $batch_size`
\set batch_number `echo $batch_number`
\set rand_seed `echo ${rand_seed:-0.321}`

SELECT setseed(:'rand_seed'::float);

-- select this.insert_patients((:'batch_size')::int,
--                              (:'batch_number')::int);
-- select count(*) from patient;

-- SELECT fhir.search('Patient', 'name=John');

-- SELECT indexing.index_search_param('Patient','name');
-- SELECT fhir.search('Patient', 'name=John');

-- select admin.admin_disk_usage_top(10);
