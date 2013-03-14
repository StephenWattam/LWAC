
-- Describe SAMPLES
CREATE TABLE samples (
    "id"        INTEGER PRIMARY KEY,
    "c200"      INTEGER NOT NULL DEFAULT (0),
    "c404"      INTEGER NOT NULL DEFAULT (0),
    "cother"    INTEGER NOT NULL DEFAULT (0),
    "datetime"  TEXT,
    "duration"  INTEGER,
    "hosts"     INTEGER NOT NULL DEFAULT (1),
    "complete"  INTEGER DEFAULT (0), 
    "errors"    INTEGER DEFAULT (0)
);

