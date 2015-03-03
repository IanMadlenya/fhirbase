-- #import ../src/tests.sql
-- #import ../src/fhir.sql

SET search_path TO fhir, vars, public;

BEGIN;

SELECT fhir.generate_tables('{Order}');

setv('created',
  fhir.create('{}'::jsonb, '{"resourceType":"Order", "id":"myid"}'::jsonb)
);

fhir.read('{}'::jsonb, 'myid') => getv('created')
fhir.read('{}'::jsonb, 'Order/myid') => getv('created')

expect 'id is myid'
  getv('created')->>'id'
=> 'myid'

expect 'order in table'
  SELECT count(*) FROM "order"
  WHERE logical_id = 'myid'
=> 1::bigint

expect 'meta info'
  jsonb_typeof(getv('created')->'meta')
=> 'object'

expect 'meta info'
  jsonb_typeof(getv('created')#>'{meta,versionId}')
=> 'string'

expect 'meta info'
  jsonb_typeof(getv('created')#>'{meta,lastUpdated}')
=> 'string'

setv('without-id',
  fhir.create('{}'::jsonb, '{"resourceType":"Order", "name":{"text":"Goga"}}'::jsonb)
);

expect 'id was set'
  SELECT (getv('without-id')->>'id') IS NOT NULL
=> true


expect 'meta respected in create'
  fhir.create('{}'::jsonb, '{"resourceType":"Order", "meta":{"tags":[1]}}'::jsonb)#>'{meta,tags}'
=> '[1]'::jsonb

expect 'order created'
  SELECT count(*) FROM "order"
  WHERE logical_id = getv('without-id')->>'id'
=> 1::bigint

expect_raise 'id and meta.versionId are required'
  SELECT fhir.update('{}'::jsonb, '{"resourceType":"Order", "id":"myid"}'::jsonb)

expect_raise 'expected last versionId'
  SELECT fhir.update('{}'::jsonb, '{"resourceType":"Order", "id":"myid", "meta":{"versionId":"wrong"}}'::jsonb)

expect 'updated'
  SELECT count(*) FROM "order_history"
  WHERE logical_id = 'myid'
=> 0::bigint

setv('updated',
  fhir.update('{}'::jsonb,
    jsonbext.assoc(getv('created'),'name','{"text":"Updated name"}')
  )
);

expect 'updated'
  SELECT count(*) FROM "order_history"
  WHERE logical_id = 'myid'
=> 1::bigint

fhir.read('{}'::jsonb, 'myid')#>>'{name,text}' => 'Updated name'

fhir.vread('{}'::jsonb, getv('created')#>>'{meta,versionId}') => getv('created')

expect "latest"
  fhir.is_latest('{}'::jsonb, 'Order', 'myid',
    getv('updated')#>>'{meta,versionId}')
=> true

expect "not latest"
  fhir.is_latest('{}'::jsonb, 'Order', 'myid',
    getv('created')#>>'{meta,versionId}')
=> false

fhir.history('{}'::jsonb, 'Order', 'myid')#>'{entry,0,resource}' => getv('updated')
fhir.history('{}'::jsonb, 'Order', 'myid')#>'{entry,1,resource}' => getv('created')

expect '2 items for resource history'
  jsonb_array_length(
    fhir.history('{}'::jsonb, 'Order', 'myid')->'entry'
  )
=> 2

expect '4 items for resource type history'
  jsonb_array_length(
    fhir.history('{}'::jsonb, 'Order')->'entry'
  )
=> 4

expect 'more then 4 items for all history'
  jsonb_array_length(
    fhir.history('{}'::jsonb)->'entry'
  ) > 4
=> true

-- SEARCH

expect 'not empty search'
  jsonb_array_length(
    fhir.search('{}'::jsonb, 'Order', '')->'entry'
  )
=> 3

-- DELETE

fhir.is_exists('{}'::jsonb, 'Order', 'myid') => true
fhir.is_deleted('{}'::jsonb, 'Order', 'myid') => false

setv('deleted',
  fhir.delete('{}'::jsonb, 'Order', 'myid')
);

expect_raise 'already deleted'
  SELECT fhir.delete('{}'::jsonb, 'Order', 'myid')

expect_raise 'does not exist'
  SELECT fhir.delete('{}'::jsonb, 'Order', 'nonexisting')

fhir.read('{}'::jsonb, 'myid') => null

fhir.is_exists('{}'::jsonb, 'Order', 'myid') => false
fhir.is_deleted('{}'::jsonb, 'Order', 'myid') => true


getv('deleted')#>>'{meta,versionId}' => getv('updated')#>>'{meta,versionId}'

ROLLBACK;
