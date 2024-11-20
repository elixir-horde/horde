defmodule HordeProTest.Repo.Migrations.NotifyTrigger do
  use Ecto.Migration

  # import SqlFmt.Helpers

  def change do
    execute("""
    DO $create_trigger$
    BEGIN
    CREATE
    OR REPLACE FUNCTION notify_events() RETURNS trigger AS $func$
    DECLARE
    channel text;
    payload text;
    BEGIN
    channel := NEW.registry_id;
    payload := 'UPDATE';
    PERFORM pg_notify(channel, payload);
    RETURN NULL;
    END;
    $func$ language plpgsql;
    CREATE trigger event_notification
    AFTER
    INSERT
      ON horde_pro_registry_events FOR EACH ROW EXECUTE PROCEDURE notify_events();
    END;
    $create_trigger$ language plpgsql;
    """)

    # DO $migration$
    # BEGIN
    #   CREATE OR REPLACE FUNCTION notify_events()
    #     RETURNS trigger AS $func$
    #   DECLARE
    #     channel text;
    #     payload text;
    #   BEGIN
    #       -- Payload text contains:
    #       --  * `stream_uuid`
    #       --  * `stream_id`
    #       --  * first `stream_version`
    #       --  * last `stream_version`
    #       -- Each separated by a comma (e.g. 'stream-12345,1,1,5')

    #       channel := TG_TABLE_SCHEMA || '.events';
    #       payload := NEW.stream_uuid || ',' || NEW.stream_id || ',' || COALESCE(OLD.stream_version, 0) + 1 || ',' || NEW.stream_version;

    #       -- Notify events to listeners
    #       PERFORM pg_notify(channel, payload);

    #       RETURN NULL;
    #   END;
    #   $func$ LANGUAGE plpgsql;

    #   DROP TRIGGER event_notification ON streams;

    #   CREATE TRIGGER event_notification
    #   AFTER INSERT OR UPDATE ON streams
    #   FOR EACH ROW EXECUTE PROCEDURE notify_events();

    #   -- Record schema migration
    #   INSERT INTO schema_migrations (major_version, minor_version, patch_version) VALUES (1, 2, 1);
    # END;
    # $migration$ LANGUAGE plpgsql;
  end
end
