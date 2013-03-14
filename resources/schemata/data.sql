
-- Describe DATA
CREATE TABLE data (
    "link_id"       INTEGER NOT NULL,
    "sample_id"     INTEGER NOT NULL,
    "rtt"           INTEGER NOT NULL,
    "rdt"           INTEGER NOT NULL, 
    "dnst"          INTEGER  NOT NULL,
    "encoding"      TEXT NOT NULL,
    "responsecode"  INTEGER,
    "effectiveuri"  TEXT,
    "errorcode"     TEXT,
    "consistency"   INTEGER NOT NULL DEFAULT (0)
);

