-- crm initial schema — single greenfield migration (migrations/001_initial.sql).
-- The migration runner owns PRAGMA user_version: it bumps it inside the same
-- transaction that applies this file. Never split this file on semicolons —
-- the FTS triggers contain semicolons inside BEGIN…END; execute it as one string.
-- All *_at columns (including stage_changed_at, closed_at, and
-- stage_moves.moved_at) are RFC3339 UTC TEXT generated in Go; occurred_on is a
-- YYYY-MM-DD TEXT date generated in Go. journal_mode=DELETE, busy_timeout=5000,
-- foreign_keys=ON (and the rest of the open-funnel pragmas) are applied at
-- open, not here.

CREATE TABLE orgs (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    name               TEXT NOT NULL,
    name_norm          TEXT NOT NULL,
    category           TEXT,
    website            TEXT,
    linkedin           TEXT,
    location           TEXT,
    focus              TEXT,
    context            TEXT,
    relationship_hint  TEXT,
    provenance_sources TEXT,
    provenance_details TEXT,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    archived_at        TEXT
);
CREATE UNIQUE INDEX orgs_name_norm_live ON orgs(name_norm) WHERE archived_at IS NULL;
CREATE INDEX orgs_name ON orgs(name);
CREATE INDEX orgs_linkedin ON orgs(linkedin);

CREATE TABLE contacts (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    name               TEXT NOT NULL,
    name_norm          TEXT NOT NULL,
    org_id             INTEGER REFERENCES orgs(id),
    job_title          TEXT,
    email              TEXT,
    phone              TEXT,
    linkedin           TEXT,
    location           TEXT,
    context            TEXT,
    relationship_hint  TEXT,
    provenance_sources TEXT,
    provenance_details TEXT,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL,
    archived_at        TEXT
);
CREATE UNIQUE INDEX contacts_email_live ON contacts(email) WHERE email IS NOT NULL AND archived_at IS NULL;
CREATE INDEX contacts_name_norm ON contacts(name_norm);
CREATE INDEX contacts_name ON contacts(name);
CREATE INDEX contacts_linkedin ON contacts(linkedin);
CREATE INDEX contacts_org ON contacts(org_id);

CREATE TABLE contact_links (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id         INTEGER NOT NULL REFERENCES contacts(id),
    related_contact_id INTEGER NOT NULL REFERENCES contacts(id),
    link_type          TEXT NOT NULL,
    note               TEXT,
    created_at         TEXT NOT NULL,
    CHECK (contact_id <> related_contact_id),
    UNIQUE (contact_id, related_contact_id, link_type)
);
CREATE INDEX contact_links_contact ON contact_links(contact_id);
CREATE INDEX contact_links_related ON contact_links(related_contact_id);

CREATE TABLE pipelines (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    name_norm   TEXT NOT NULL,
    position    INTEGER NOT NULL,
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    archived_at TEXT
);
CREATE UNIQUE INDEX pipelines_name_norm_live ON pipelines(name_norm) WHERE archived_at IS NULL;

CREATE TABLE stages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    pipeline_id INTEGER NOT NULL REFERENCES pipelines(id),
    name        TEXT NOT NULL,
    name_norm   TEXT NOT NULL,
    position    INTEGER NOT NULL,
    rot_days    INTEGER CHECK (rot_days IS NULL OR rot_days > 0),
    created_at  TEXT NOT NULL,
    updated_at  TEXT NOT NULL,
    archived_at TEXT
);
CREATE UNIQUE INDEX stages_name_norm_live ON stages(pipeline_id, name_norm) WHERE archived_at IS NULL;
CREATE INDEX stages_pipeline ON stages(pipeline_id, position);

CREATE TABLE deals (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    title            TEXT NOT NULL,
    title_norm       TEXT NOT NULL,
    org_id           INTEGER REFERENCES orgs(id),
    contact_id       INTEGER REFERENCES contacts(id),
    pipeline_id      INTEGER NOT NULL REFERENCES pipelines(id),
    stage_id         INTEGER NOT NULL REFERENCES stages(id),
    status           TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','won','lost')),
    outcome_reason   TEXT,
    closed_at        TEXT CHECK (closed_at IS NULL OR closed_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    stage_changed_at TEXT NOT NULL CHECK (stage_changed_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL,
    archived_at      TEXT,
    CHECK (org_id IS NOT NULL OR contact_id IS NOT NULL)
);
CREATE INDEX deals_title_norm ON deals(title_norm);
CREATE INDEX deals_title ON deals(title);
CREATE INDEX deals_org ON deals(org_id);
CREATE INDEX deals_contact ON deals(contact_id);
CREATE INDEX deals_pipeline_stage ON deals(pipeline_id, stage_id);
CREATE INDEX deals_stage ON deals(stage_id);
CREATE INDEX deals_status ON deals(status);

CREATE TABLE stage_moves (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    deal_id       INTEGER NOT NULL REFERENCES deals(id) ON DELETE CASCADE,
    from_stage_id INTEGER REFERENCES stages(id),
    to_stage_id   INTEGER NOT NULL REFERENCES stages(id),
    moved_at      TEXT NOT NULL CHECK (moved_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'),
    note          TEXT,
    CHECK (from_stage_id IS NULL OR from_stage_id <> to_stage_id)
);
CREATE INDEX stage_moves_deal ON stage_moves(deal_id, moved_at);
CREATE INDEX stage_moves_from ON stage_moves(from_stage_id);
CREATE INDEX stage_moves_to ON stage_moves(to_stage_id);

CREATE TABLE interactions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    kind            TEXT NOT NULL CHECK (kind IN ('call','meeting','email','message','note')),
    occurred_on     TEXT NOT NULL CHECK (occurred_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    summary         TEXT NOT NULL,
    body            TEXT,
    transcript_path TEXT,
    org_id          INTEGER REFERENCES orgs(id),
    deal_id         INTEGER REFERENCES deals(id),
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    archived_at     TEXT
);
CREATE INDEX interactions_date ON interactions(occurred_on);
CREATE INDEX interactions_org ON interactions(org_id);
CREATE INDEX interactions_deal ON interactions(deal_id);

CREATE TABLE interaction_people (
    interaction_id INTEGER NOT NULL REFERENCES interactions(id) ON DELETE CASCADE,
    contact_id     INTEGER NOT NULL REFERENCES contacts(id),
    UNIQUE (interaction_id, contact_id)
);
CREATE INDEX interaction_people_contact ON interaction_people(contact_id);

CREATE VIRTUAL TABLE orgs_fts USING fts5(
    name, category, focus, context, relationship_hint,
    content='orgs', content_rowid='id'
);
CREATE TRIGGER orgs_ai AFTER INSERT ON orgs BEGIN
    INSERT INTO orgs_fts(rowid, name, category, focus, context, relationship_hint)
    VALUES (new.id, new.name, new.category, new.focus, new.context, new.relationship_hint);
END;
CREATE TRIGGER orgs_ad AFTER DELETE ON orgs BEGIN
    INSERT INTO orgs_fts(orgs_fts, rowid, name, category, focus, context, relationship_hint)
    VALUES ('delete', old.id, old.name, old.category, old.focus, old.context, old.relationship_hint);
END;
CREATE TRIGGER orgs_au AFTER UPDATE ON orgs BEGIN
    INSERT INTO orgs_fts(orgs_fts, rowid, name, category, focus, context, relationship_hint)
    VALUES ('delete', old.id, old.name, old.category, old.focus, old.context, old.relationship_hint);
    INSERT INTO orgs_fts(rowid, name, category, focus, context, relationship_hint)
    VALUES (new.id, new.name, new.category, new.focus, new.context, new.relationship_hint);
END;

CREATE VIRTUAL TABLE contacts_fts USING fts5(
    name, job_title, email, context, relationship_hint,
    content='contacts', content_rowid='id'
);
CREATE TRIGGER contacts_ai AFTER INSERT ON contacts BEGIN
    INSERT INTO contacts_fts(rowid, name, job_title, email, context, relationship_hint)
    VALUES (new.id, new.name, new.job_title, new.email, new.context, new.relationship_hint);
END;
CREATE TRIGGER contacts_ad AFTER DELETE ON contacts BEGIN
    INSERT INTO contacts_fts(contacts_fts, rowid, name, job_title, email, context, relationship_hint)
    VALUES ('delete', old.id, old.name, old.job_title, old.email, old.context, old.relationship_hint);
END;
CREATE TRIGGER contacts_au AFTER UPDATE ON contacts BEGIN
    INSERT INTO contacts_fts(contacts_fts, rowid, name, job_title, email, context, relationship_hint)
    VALUES ('delete', old.id, old.name, old.job_title, old.email, old.context, old.relationship_hint);
    INSERT INTO contacts_fts(rowid, name, job_title, email, context, relationship_hint)
    VALUES (new.id, new.name, new.job_title, new.email, new.context, new.relationship_hint);
END;

CREATE VIRTUAL TABLE interactions_fts USING fts5(
    summary, body,
    content='interactions', content_rowid='id'
);
CREATE TRIGGER interactions_ai AFTER INSERT ON interactions BEGIN
    INSERT INTO interactions_fts(rowid, summary, body)
    VALUES (new.id, new.summary, new.body);
END;
CREATE TRIGGER interactions_ad AFTER DELETE ON interactions BEGIN
    INSERT INTO interactions_fts(interactions_fts, rowid, summary, body)
    VALUES ('delete', old.id, old.summary, old.body);
END;
CREATE TRIGGER interactions_au AFTER UPDATE ON interactions BEGIN
    INSERT INTO interactions_fts(interactions_fts, rowid, summary, body)
    VALUES ('delete', old.id, old.summary, old.body);
    INSERT INTO interactions_fts(rowid, summary, body)
    VALUES (new.id, new.summary, new.body);
END;

CREATE VIRTUAL TABLE deals_fts USING fts5(
    title, outcome_reason,
    content='deals', content_rowid='id'
);
CREATE TRIGGER deals_ai AFTER INSERT ON deals BEGIN
    INSERT INTO deals_fts(rowid, title, outcome_reason)
    VALUES (new.id, new.title, new.outcome_reason);
END;
CREATE TRIGGER deals_ad AFTER DELETE ON deals BEGIN
    INSERT INTO deals_fts(deals_fts, rowid, title, outcome_reason)
    VALUES ('delete', old.id, old.title, old.outcome_reason);
END;
CREATE TRIGGER deals_au AFTER UPDATE ON deals BEGIN
    INSERT INTO deals_fts(deals_fts, rowid, title, outcome_reason)
    VALUES ('delete', old.id, old.title, old.outcome_reason);
    INSERT INTO deals_fts(rowid, title, outcome_reason)
    VALUES (new.id, new.title, new.outcome_reason);
END;
