-- Resolve live managed-object references without scanning all part metadata.
CREATE INDEX IF NOT EXISTS part_managed_object
    ON part (("11" ->> 'managedObjectKey'))
    WHERE "14" = 1 AND "13" = 0;
