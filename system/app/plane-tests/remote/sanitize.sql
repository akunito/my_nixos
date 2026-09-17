-- Dev sanitize, part 1 (APLANE-8). Runs on the freshly restored dev database
-- while plane-dev-aio is STOPPED, so no worker can act on prod rows first.
-- Part 2 (workspace deletion, needs Django cascades) is delete_workspaces.py.
BEGIN;

-- Webhooks: prod has the Telegram bot (host.docker.internal:8766, reachable
-- from dev too) and the n8n calendar sync. Delete, not deactivate.
DELETE FROM webhooks;

-- Prod API tokens are plaintext and would authenticate against dev.
DELETE FROM api_tokens;

-- Session data is excluded from the dump; make sure.
DELETE FROM sessions;

-- Email → mailpit (these rows win over env: SKIP_ENV_VAR=1).
UPDATE instance_configurations SET value = 'plane-dev-mailpit' WHERE key = 'EMAIL_HOST';
UPDATE instance_configurations SET value = '1025' WHERE key = 'EMAIL_PORT';
UPDATE instance_configurations SET value = '0' WHERE key IN ('EMAIL_USE_TLS', 'EMAIL_USE_SSL');
UPDATE instance_configurations SET value = '' WHERE key = 'EMAIL_HOST_USER';

-- Dev-only login: password for the QA users (prod stays Pocket-ID-only).
UPDATE instance_configurations SET value = '1' WHERE key = 'ENABLE_EMAIL_PASSWORD';

DO $$
BEGIN
  IF (SELECT count(*) FROM webhooks) <> 0 THEN RAISE EXCEPTION 'webhooks not empty'; END IF;
  IF (SELECT count(*) FROM api_tokens) <> 0 THEN RAISE EXCEPTION 'api_tokens not empty'; END IF;
  IF (SELECT count(*) FROM instance_configurations WHERE key = 'EMAIL_HOST' AND value = 'plane-dev-mailpit') <> 1
    THEN RAISE EXCEPTION 'EMAIL_HOST row not set'; END IF;
  IF (SELECT count(*) FROM instance_configurations WHERE key = 'ENABLE_EMAIL_PASSWORD' AND value = '1') <> 1
    THEN RAISE EXCEPTION 'ENABLE_EMAIL_PASSWORD row not set'; END IF;
END $$;

COMMIT;
