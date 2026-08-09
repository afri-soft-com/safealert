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
