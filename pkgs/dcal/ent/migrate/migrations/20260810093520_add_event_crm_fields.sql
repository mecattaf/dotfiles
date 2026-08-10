-- +goose Up
-- add column "crm_ref" to table: "events"
ALTER TABLE `events` ADD COLUMN `crm_ref` text NULL;
-- add column "crm_kind" to table: "events"
ALTER TABLE `events` ADD COLUMN `crm_kind` text NULL;

-- +goose Down
-- reverse: add column "crm_kind" to table: "events"
ALTER TABLE `events` DROP COLUMN `crm_kind`;
-- reverse: add column "crm_ref" to table: "events"
ALTER TABLE `events` DROP COLUMN `crm_ref`;
