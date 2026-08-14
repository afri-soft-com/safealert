require("dotenv").config();
// Neon : préférer l'endpoint direct (sans -pooler) pour les migrations DDL
if (process.env.DATABASE_URL_DIRECT) {
  process.env.DATABASE_URL = process.env.DATABASE_URL_DIRECT;
}
const { pool } = require("./database");

const migrate = async () => {
  const client = await pool.connect();
  try {
    await client.query("CREATE EXTENSION IF NOT EXISTS postgis");

    await client.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        phone VARCHAR(20) UNIQUE NOT NULL,
        pseudo VARCHAR(50) UNIQUE NOT NULL,
        role VARCHAR(20) DEFAULT 'citizen' CHECK (role IN ('citizen','leader','agent')),
        fcm_token TEXT,
        avatar_url TEXT,
        last_lat DOUBLE PRECISION,
        last_lng DOUBLE PRECISION,
        last_seen_at TIMESTAMP WITH TIME ZONE,
        is_discreet_mode BOOLEAN DEFAULT false,
        share_presence BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS trust_contacts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        contact_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        contact_name VARCHAR(100) NOT NULL,
        contact_phone VARCHAR(20) NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(user_id, contact_phone)
      );

      CREATE TABLE IF NOT EXISTS emergency_numbers (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        country_code VARCHAR(5) DEFAULT 'CD',
        service_name VARCHAR(100) NOT NULL,
        service_type VARCHAR(50) NOT NULL,
        phone_number VARCHAR(20) NOT NULL,
        icon VARCHAR(10) DEFAULT '📞',
        is_offline_available BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS incidents (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        incident_type VARCHAR(50) NOT NULL,
        description TEXT,
        lat DOUBLE PRECISION NOT NULL,
        lng DOUBLE PRECISION NOT NULL,
        location GEOGRAPHY(Point, 4326),
        zone_name VARCHAR(100),
        severity VARCHAR(20) DEFAULT 'alert' CHECK (severity IN ('alert','danger','vigilance','safe')),
        status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active','verified','resolved','false_alarm','acknowledged','in_progress')),
        acknowledged_by UUID REFERENCES users(id) ON DELETE SET NULL,
        acknowledged_at TIMESTAMP WITH TIME ZONE,
        verified_by INTEGER DEFAULT 0,
        is_anonymous BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        resolved_at TIMESTAMP WITH TIME ZONE
      );

      CREATE INDEX IF NOT EXISTS idx_incidents_location ON incidents USING GIST (location);
      CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
      CREATE INDEX IF NOT EXISTS idx_incidents_created ON incidents(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
      CREATE INDEX IF NOT EXISTS idx_trust_contacts_user ON trust_contacts(user_id);

      CREATE TABLE IF NOT EXISTS neighborhood_groups (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(100) NOT NULL,
        description TEXT,
        zone_name VARCHAR(100),
        created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        invite_code VARCHAR(10) UNIQUE NOT NULL,
        member_count INTEGER DEFAULT 1,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS group_members (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        group_id UUID NOT NULL REFERENCES neighborhood_groups(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        role VARCHAR(20) DEFAULT 'member' CHECK (role IN ('admin','member')),
        joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(group_id, user_id)
      );

      CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);

      CREATE TABLE IF NOT EXISTS group_join_requests (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        group_id UUID NOT NULL REFERENCES neighborhood_groups(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(group_id, user_id)
      );

      CREATE INDEX IF NOT EXISTS idx_group_join_requests_group ON group_join_requests(group_id);
      CREATE INDEX IF NOT EXISTS idx_group_join_requests_status ON group_join_requests(status);

      CREATE TABLE IF NOT EXISTS otp_codes (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        phone VARCHAR(20) NOT NULL,
        code_hash VARCHAR(255) NOT NULL,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        used_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_otp_phone ON otp_codes(phone);
      CREATE INDEX IF NOT EXISTS idx_otp_expires ON otp_codes(expires_at);

      CREATE TABLE IF NOT EXISTS incident_verifications (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(incident_id, user_id)
      );

      CREATE INDEX IF NOT EXISTS idx_incident_verifications_incident ON incident_verifications(incident_id);
      CREATE INDEX IF NOT EXISTS idx_incident_verifications_user ON incident_verifications(user_id);

      CREATE TABLE IF NOT EXISTS partner_api_keys (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        partner_name VARCHAR(100) NOT NULL,
        api_key VARCHAR(64) UNIQUE NOT NULL,
        is_active BOOLEAN DEFAULT true,
        rate_limit INT DEFAULT 1000,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        expires_at TIMESTAMP WITH TIME ZONE
      );
    `);

    await client.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS share_presence BOOLEAN DEFAULT true;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS sector_name VARCHAR(100);
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS acknowledged_by UUID REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMP WITH TIME ZONE;
      ALTER TABLE incidents DROP CONSTRAINT IF EXISTS incidents_status_check;
      ALTER TABLE incidents ADD CONSTRAINT incidents_status_check
        CHECK (status IN ('active','verified','resolved','false_alarm','acknowledged','in_progress'));
      ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
      ALTER TABLE users ADD CONSTRAINT users_role_check
        CHECK (role IN ('citizen','leader','agent','platform_admin'));
      ALTER TABLE neighborhood_groups ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT true;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS sos_notify_groups BOOLEAN DEFAULT true;
    `);

    await client.query(`
      CREATE TABLE IF NOT EXISTS group_messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        group_id UUID NOT NULL REFERENCES neighborhood_groups(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        content TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_group_messages_group_created
        ON group_messages(group_id, created_at DESC);

      CREATE TABLE IF NOT EXISTS group_alerts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        group_id UUID NOT NULL REFERENCES neighborhood_groups(id) ON DELETE CASCADE,
        author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        type VARCHAR(30) NOT NULL CHECK (type IN ('info','help_needed','offer_help','danger')),
        title VARCHAR(200) NOT NULL,
        body TEXT,
        lat DOUBLE PRECISION,
        lng DOUBLE PRECISION,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_group_alerts_group_created
        ON group_alerts(group_id, created_at DESC);

      CREATE TABLE IF NOT EXISTS audit_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
        action VARCHAR(80) NOT NULL,
        entity_type VARCHAR(60) NOT NULL,
        entity_id TEXT,
        metadata JSONB,
        ip VARCHAR(64),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON audit_logs(actor_id);
    `);

    // ── Feature expansions (check-in, trips, trust zones, ops, partners, etc.) ──
    await client.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS premium_until TIMESTAMP WITH TIME ZONE;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS preferred_locale VARCHAR(8) DEFAULT 'fr';
      ALTER TABLE users ADD COLUMN IF NOT EXISTS reliability_score INTEGER DEFAULT 50;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS reliability_score INTEGER DEFAULT 50;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS assigned_to UUID REFERENCES users(id) ON DELETE SET NULL;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMP WITH TIME ZONE;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS assignment_eta TIMESTAMP WITH TIME ZONE;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS close_reason TEXT;
      ALTER TABLE partner_api_keys ADD COLUMN IF NOT EXISTS webhook_url TEXT;
      ALTER TABLE partner_api_keys ADD COLUMN IF NOT EXISTS webhook_secret TEXT;
      ALTER TABLE partner_api_keys ADD COLUMN IF NOT EXISTS webhook_events TEXT DEFAULT 'sos,incident,cancel';

      CREATE TABLE IF NOT EXISTS check_ins (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        incident_id UUID REFERENCES incidents(id) ON DELETE SET NULL,
        trip_id UUID,
        lat DOUBLE PRECISION,
        lng DOUBLE PRECISION,
        message TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_check_ins_user ON check_ins(user_id, created_at DESC);

      CREATE TABLE IF NOT EXISTS safe_trips (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        origin_lat DOUBLE PRECISION NOT NULL,
        origin_lng DOUBLE PRECISION NOT NULL,
        dest_lat DOUBLE PRECISION NOT NULL,
        dest_lng DOUBLE PRECISION NOT NULL,
        dest_label VARCHAR(200),
        eta_at TIMESTAMP WITH TIME ZONE NOT NULL,
        status VARCHAR(30) DEFAULT 'active'
          CHECK (status IN ('active','arrived','alerted','cancelled','expired')),
        last_lat DOUBLE PRECISION,
        last_lng DOUBLE PRECISION,
        last_ping_at TIMESTAMP WITH TIME ZONE,
        abnormal_stop_at TIMESTAMP WITH TIME ZONE,
        escort_contact_ids UUID[] DEFAULT '{}',
        notify_on_delay BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        arrived_at TIMESTAMP WITH TIME ZONE
      );
      CREATE INDEX IF NOT EXISTS idx_safe_trips_user ON safe_trips(user_id);
      CREATE INDEX IF NOT EXISTS idx_safe_trips_status ON safe_trips(status) WHERE status = 'active';

      CREATE TABLE IF NOT EXISTS sos_live_status (
        incident_id UUID PRIMARY KEY REFERENCES incidents(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        lat DOUBLE PRECISION NOT NULL,
        lng DOUBLE PRECISION NOT NULL,
        battery_pct SMALLINT,
        accuracy_m REAL,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_sos_live_expires ON sos_live_status(expires_at);

      CREATE TABLE IF NOT EXISTS trust_zones (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        label VARCHAR(100) NOT NULL,
        zone_type VARCHAR(30) NOT NULL CHECK (zone_type IN ('home','work','school','custom')),
        lat DOUBLE PRECISION NOT NULL,
        lng DOUBLE PRECISION NOT NULL,
        radius_m INTEGER NOT NULL DEFAULT 200,
        notify_contacts BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_trust_zones_user ON trust_zones(user_id);

      CREATE TABLE IF NOT EXISTS neighborhood_subscriptions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        quartier VARCHAR(120) NOT NULL,
        digest_hour SMALLINT DEFAULT 18,
        last_digest_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(user_id, quartier)
      );
      CREATE INDEX IF NOT EXISTS idx_neighborhood_subs_quartier ON neighborhood_subscriptions(quartier);

      CREATE TABLE IF NOT EXISTS incident_evidence (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        media_type VARCHAR(20) NOT NULL CHECK (media_type IN ('photo','audio')),
        storage_key TEXT NOT NULL,
        consent_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
        retention_until TIMESTAMP WITH TIME ZONE NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_incident_evidence_incident ON incident_evidence(incident_id);
      CREATE INDEX IF NOT EXISTS idx_incident_evidence_retention ON incident_evidence(retention_until);

      CREATE TABLE IF NOT EXISTS incident_chat_messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        body TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_incident_chat_incident
        ON incident_chat_messages(incident_id, created_at ASC);

      CREATE TABLE IF NOT EXISTS leader_sectors (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        leader_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name VARCHAR(120) NOT NULL,
        polygon GEOGRAPHY(Polygon, 4326),
        center_lat DOUBLE PRECISION,
        center_lng DOUBLE PRECISION,
        radius_m INTEGER DEFAULT 2000,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_leader_sectors_leader ON leader_sectors(leader_id);
      CREATE INDEX IF NOT EXISTS idx_leader_sectors_poly ON leader_sectors USING GIST (polygon);

      CREATE TABLE IF NOT EXISTS contact_backups (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
        ciphertext TEXT NOT NULL,
        nonce TEXT NOT NULL,
        salt TEXT NOT NULL,
        version SMALLINT DEFAULT 1,
        contact_count INTEGER DEFAULT 0,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS partner_webhook_deliveries (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        partner_id UUID NOT NULL REFERENCES partner_api_keys(id) ON DELETE CASCADE,
        event_type VARCHAR(40) NOT NULL,
        payload JSONB NOT NULL,
        status VARCHAR(20) DEFAULT 'pending',
        response_code INTEGER,
        attempts INTEGER DEFAULT 0,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        delivered_at TIMESTAMP WITH TIME ZONE
      );
      CREATE INDEX IF NOT EXISTS idx_partner_webhook_partner
        ON partner_webhook_deliveries(partner_id, created_at DESC);
    `);

    // ── Wave 2: invites, public trip share, safety pings, corridors, alert types ──
    await client.query(`
      ALTER TABLE safe_trips ADD COLUMN IF NOT EXISTS share_token VARCHAR(32);
      ALTER TABLE safe_trips ADD COLUMN IF NOT EXISTS share_expires_at TIMESTAMP WITH TIME ZONE;
      CREATE UNIQUE INDEX IF NOT EXISTS idx_safe_trips_share_token
        ON safe_trips(share_token) WHERE share_token IS NOT NULL;

      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS agent_en_route_at TIMESTAMP WITH TIME ZONE;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS agent_last_lat DOUBLE PRECISION;
      ALTER TABLE incidents ADD COLUMN IF NOT EXISTS agent_last_lng DOUBLE PRECISION;

      CREATE TABLE IF NOT EXISTS circle_invites (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        inviter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        code VARCHAR(12) UNIQUE NOT NULL,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        max_uses INTEGER DEFAULT 5,
        use_count INTEGER DEFAULT 0,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_circle_invites_code ON circle_invites(code);

      CREATE TABLE IF NOT EXISTS safety_pings (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        due_at TIMESTAMP WITH TIME ZONE NOT NULL,
        window_minutes INTEGER NOT NULL DEFAULT 15,
        status VARCHAR(20) DEFAULT 'pending'
          CHECK (status IN ('pending','ok','missed','cancelled')),
        responded_at TIMESTAMP WITH TIME ZONE,
        message TEXT,
        notify_groups BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_safety_pings_due
        ON safety_pings(due_at) WHERE status = 'pending';
      CREATE INDEX IF NOT EXISTS idx_safety_pings_user ON safety_pings(user_id, created_at DESC);

      CREATE TABLE IF NOT EXISTS landmarks (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(120) NOT NULL,
        kind VARCHAR(40) NOT NULL DEFAULT 'landmark'
          CHECK (kind IN ('landmark','corridor','market','school','hospital','bus_stop','other')),
        lat DOUBLE PRECISION NOT NULL,
        lng DOUBLE PRECISION NOT NULL,
        location GEOGRAPHY(Point, 4326),
        zone_name VARCHAR(100),
        description TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_landmarks_location ON landmarks USING GIST (location);
      CREATE INDEX IF NOT EXISTS idx_landmarks_zone ON landmarks(zone_name);

      CREATE TABLE IF NOT EXISTS route_corridors (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name VARCHAR(120) NOT NULL,
        zone_name VARCHAR(100),
        path GEOGRAPHY(LineString, 4326),
        midpoint_lat DOUBLE PRECISION,
        midpoint_lng DOUBLE PRECISION,
        incident_weight INTEGER DEFAULT 0,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
      CREATE INDEX IF NOT EXISTS idx_route_corridors_path ON route_corridors USING GIST (path);
    `);

    // Multi-device sessions + FCM tokens
    await client.query(`
      CREATE TABLE IF NOT EXISTS user_devices (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        device_id VARCHAR(128) NOT NULL,
        device_label VARCHAR(120),
        session_jti VARCHAR(64),
        fcm_token TEXT,
        last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        revoked_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE (user_id, device_id)
      );
      CREATE INDEX IF NOT EXISTS idx_user_devices_user ON user_devices(user_id);
      CREATE INDEX IF NOT EXISTS idx_user_devices_jti ON user_devices(session_jti)
        WHERE revoked_at IS NULL;
    `);

    // Widen group_alerts type CHECK for utility outage types
    await client.query(`
      ALTER TABLE group_alerts DROP CONSTRAINT IF EXISTS group_alerts_type_check;
      ALTER TABLE group_alerts ADD CONSTRAINT group_alerts_type_check
        CHECK (type IN (
          'info','help_needed','offer_help','danger',
          'power_outage','water_outage','flood','blocked_street'
        ));
    `);

    // Seed a few Kinshasa-area landmarks if empty (MVP corridors)
    const lmCount = await client.query(`SELECT COUNT(*)::int AS c FROM landmarks`);
    if (lmCount.rows[0].c === 0) {
      await client.query(`
        INSERT INTO landmarks (name, kind, lat, lng, location, zone_name, description) VALUES
          ('Gombe — Boulevard du 30 Juin', 'corridor', -4.305, 15.310,
            ST_SetSRID(ST_MakePoint(15.310, -4.305), 4326)::geography, 'Gombe', 'Axe principal'),
          ('Marché Central', 'market', -4.325, 15.313,
            ST_SetSRID(ST_MakePoint(15.313, -4.325), 4326)::geography, 'Kinshasa', 'Point de repère'),
          ('Université de Kinshasa', 'school', -4.420, 15.310,
            ST_SetSRID(ST_MakePoint(15.310, -4.420), 4326)::geography, 'Lemba', 'Campus'),
          ('Hôpital Général', 'hospital', -4.327, 15.307,
            ST_SetSRID(ST_MakePoint(15.307, -4.327), 4326)::geography, 'Kinshasa', 'Urgences'),
          ('Limete — Boulevard Lumumba', 'corridor', -4.380, 15.340,
            ST_SetSRID(ST_MakePoint(15.340, -4.380), 4326)::geography, 'Limete', 'Axe fréquenté')
      `);
    }

    const adminPhone = process.env.PLATFORM_ADMIN_PHONE;
    if (adminPhone) {
      const normalized = adminPhone.trim();
      const promoted = await client.query(
        `UPDATE users SET role = 'platform_admin', updated_at = NOW()
         WHERE phone = $1 RETURNING id, phone, pseudo`,
        [normalized]
      );
      if (promoted.rows.length > 0) {
        console.log(`Platform admin promoted: ${promoted.rows[0].phone} (${promoted.rows[0].pseudo})`);
      } else {
        console.log(`PLATFORM_ADMIN_PHONE=${normalized} — aucun utilisateur existant (créez le compte puis relancez migrate)`);
      }
    }

    console.log("Migration completed successfully");
    console.log("Pour promouvoir un admin manuellement : UPDATE users SET role = 'platform_admin' WHERE phone = '+243XXXXXXXXX';");
  } catch (err) {
    console.error("Migration failed:", err);
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
};

migrate();
