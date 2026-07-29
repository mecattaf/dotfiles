PRAGMA user_version = 1;

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
CREATE INDEX contacts_org ON contacts(org_id);

CREATE TABLE interactions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    kind            TEXT NOT NULL CHECK (kind IN ('call','meeting','email','message','note')),
    occurred_on     TEXT NOT NULL CHECK (occurred_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    summary         TEXT NOT NULL,
    body            TEXT,
    transcript_path TEXT,
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    archived_at     TEXT
);
CREATE INDEX interactions_date ON interactions(occurred_on);

CREATE TABLE interaction_people (
    interaction_id INTEGER NOT NULL REFERENCES interactions(id) ON DELETE CASCADE,
    contact_id     INTEGER NOT NULL REFERENCES contacts(id),
    UNIQUE (interaction_id, contact_id)
);

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
